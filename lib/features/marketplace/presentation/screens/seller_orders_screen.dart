import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/order_model.dart';
import '../providers/marketplace_provider.dart';

/// Thin Scaffold wrapper around [SellerOrdersView], kept as its own routed
/// screen for the deep link from the marketplace app bar's receipt icon.
/// The shop admin dashboard's Orders tab embeds [SellerOrdersView]
/// directly instead, so the two never duplicate the actual list logic.
class SellerOrdersScreen extends StatelessWidget {
  const SellerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('My Orders'),
        centerTitle: true,
      ),
      body: const SellerOrdersView(),
    );
  }
}

/// The order list body on its own, with no Scaffold/AppBar -- embeddable
/// inside any host (a standalone screen, a dashboard tab) that provides
/// its own.
class SellerOrdersView extends ConsumerWidget {
  const SellerOrdersView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sellerOrdersProvider);

    if (state.isLoading && state.orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(sellerOrdersProvider.notifier).refresh(),
      child: state.orders.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 120),
                Center(
                  child: Text('No orders yet',
                      style: TextStyle(color: Colors.white54)),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: state.orders.length,
              itemBuilder: (context, i) => _OrderTile(order: state.orders[i]),
            ),
    );
  }
}

Color _statusColor(FulfillmentStatus s) {
  switch (s) {
    case FulfillmentStatus.pending:
      return AppColors.warning;
    case FulfillmentStatus.paid:
      return AppColors.info;
    case FulfillmentStatus.shipped:
      return AppColors.accent;
    case FulfillmentStatus.completed:
      return AppColors.success;
    case FulfillmentStatus.cancelled:
      return AppColors.error;
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = _statusColor(order.fulfillmentStatus);
    return Card(
      color: AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(order.productTitle ?? 'Order',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${order.currency} ${order.amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w700,
                            fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${order.buyerName ?? 'Buyer'} · qty ${order.quantity} · '
                    '${DateFormat.yMMMd().format(order.createdAt)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      OrderModel.statusString(order.fulfillmentStatus)
                          .toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<FulfillmentStatus>(
              value: order.fulfillmentStatus,
              dropdownColor: AppColors.darkSurface2,
              underline: const SizedBox(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white54),
              items: FulfillmentStatus.values
                  .map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(OrderModel.statusString(s),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                      ))
                  .toList(),
              onChanged: (status) {
                if (status != null) {
                  ref
                      .read(sellerOrdersProvider.notifier)
                      .markStatus(order.id, status);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

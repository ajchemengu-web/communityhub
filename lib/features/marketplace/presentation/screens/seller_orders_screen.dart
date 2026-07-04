import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/order_model.dart';
import '../providers/marketplace_provider.dart';

class SellerOrdersScreen extends ConsumerWidget {
  const SellerOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sellerOrdersProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('My Orders'),
        centerTitle: true,
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
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
                      itemBuilder: (context, i) =>
                          _OrderTile(order: state.orders[i]),
                    ),
            ),
    );
  }
}

class _OrderTile extends ConsumerWidget {
  const _OrderTile({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      color: AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(order.productTitle ?? 'Order', style: const TextStyle(color: Colors.white)),
        subtitle: Text(
          '${order.buyerName ?? 'Buyer'} · qty ${order.quantity} · '
          '${DateFormat.yMMMd().format(order.createdAt)}',
          style: const TextStyle(color: Colors.white54),
        ),
        trailing: DropdownButton<FulfillmentStatus>(
          value: order.fulfillmentStatus,
          dropdownColor: AppColors.darkSurface2,
          underline: const SizedBox(),
          items: FulfillmentStatus.values
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(OrderModel.statusString(s),
                        style: const TextStyle(color: Colors.white)),
                  ))
              .toList(),
          onChanged: (status) {
            if (status != null) {
              ref.read(sellerOrdersProvider.notifier).markStatus(order.id, status);
            }
          },
        ),
      ),
    );
  }
}

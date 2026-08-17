import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/marketplace_repository.dart';
import '../../domain/models/order_model.dart';
import '../../domain/models/product_model.dart';
import '../../domain/models/shop_model.dart';
import '../providers/marketplace_provider.dart';
import 'create_product_screen.dart';
import 'seller_orders_screen.dart';

/// A product's stock is called out as "running low" below this many units
/// left -- an arbitrary but reasonable threshold (Jumia/Kilimall both
/// surface a similar low-stock warning to sellers; neither publishes the
/// exact number they use, so this picks one rather than leaving sellers
/// with no warning at all).
const int _lowStockThreshold = 5;

/// The shop admin dashboard -- one hub for everything a seller needs,
/// modeled on Jumia Seller Centre and Kilimall's Seller Center (both
/// researched directly: dashboard-as-home-base, a shelf-based product
/// catalog with on/off toggles rather than deletion, an order list staged
/// by fulfillment status, and shop-level settings), scaled down to what
/// actually fits a community marketplace -- no bulk CSV import, seller
/// scoring, or promotions engine, since none of those match this app's
/// scale or trust model yet. Reached from the profile page's "My Shop"
/// bar and from the marketplace app bar's orders icon (landing straight
/// on the Orders tab via [initialTab]).
class ShopAdminScreen extends ConsumerStatefulWidget {
  const ShopAdminScreen({super.key, this.initialTab = 0});

  /// 0 = Overview, 1 = Listings, 2 = Orders, 3 = Settings.
  final int initialTab;

  @override
  ConsumerState<ShopAdminScreen> createState() => _ShopAdminScreenState();
}

class _ShopAdminScreenState extends ConsumerState<ShopAdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('My Shop'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.secondary,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Listings'),
            Tab(text: 'Orders'),
            Tab(text: 'Settings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OverviewTab(onGoToTab: (i) => _tabController.animateTo(i)),
          const _ListingsTab(),
          const SellerOrdersView(),
          const _SettingsTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Overview
// ─────────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab({required this.onGoToTab});
  final void Function(int tabIndex) onGoToTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopAsync = ref.watch(myShopProvider);

    return shopAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _OverviewMessage(
        icon: Icons.error_outline_rounded,
        title: "Couldn't load your shop",
        subtitle: 'Pull down to try again.',
        onRefresh: () async => ref.invalidate(myShopProvider),
      ),
      data: (shop) {
        if (shop == null) {
          return _OverviewMessage(
            icon: Icons.storefront_outlined,
            title: "You haven't set up a shop yet",
            subtitle: 'Create one to start listing things for sale.',
            actionLabel: 'Set up my shop',
            onAction: () => context.push(AppRoutes.manageShop),
          );
        }
        return _OverviewContent(shop: shop, onGoToTab: onGoToTab);
      },
    );
  }
}

class _OverviewContent extends ConsumerWidget {
  const _OverviewContent({required this.shop, required this.onGoToTab});
  final ShopModel shop;
  final void Function(int tabIndex) onGoToTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(myListingsProvider);
    final ordersState = ref.watch(sellerOrdersProvider);

    final listings = listingsAsync.valueOrNull ?? const <ProductModel>[];
    final activeCount = listings.where((p) => p.isActive).length;
    final lowStockCount = listings
        .where((p) =>
            p.isActive &&
            p.stock != null &&
            p.stock! > 0 &&
            p.stock! <= _lowStockThreshold)
        .length;
    final soldOutCount =
        listings.where((p) => p.isActive && p.isSoldOut).length;

    final orders = ordersState.orders;
    // "Confirmed" revenue -- paid/shipped/completed orders only. A
    // "pending" order hasn't been confirmed as paid yet and a cancelled
    // one never will be, so neither belongs in a number a seller is
    // reading as "money I've actually made."
    final revenue = orders
        .where((o) =>
            o.fulfillmentStatus == FulfillmentStatus.paid ||
            o.fulfillmentStatus == FulfillmentStatus.shipped ||
            o.fulfillmentStatus == FulfillmentStatus.completed)
        .fold<double>(0, (sum, o) => sum + o.amount);
    final needsActionCount = orders
        .where((o) =>
            o.fulfillmentStatus == FulfillmentStatus.pending ||
            o.fulfillmentStatus == FulfillmentStatus.paid)
        .length;
    final currency = orders.isNotEmpty ? orders.first.currency : 'KES';

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myListingsProvider);
        await ref.read(sellerOrdersProvider.notifier).refresh();
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ShopHeaderCard(shop: shop),
          const SizedBox(height: 16),
          if (soldOutCount > 0 || lowStockCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AlertBanner(
                soldOutCount: soldOutCount,
                lowStockCount: lowStockCount,
                onTap: () => onGoToTab(1),
              ),
            ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.55,
            children: [
              _StatCard(
                icon: Icons.payments_outlined,
                label: 'Revenue',
                value: '$currency ${revenue.toStringAsFixed(0)}',
                color: AppColors.success,
              ),
              _StatCard(
                icon: Icons.pending_actions_rounded,
                label: 'Needs attention',
                value: '$needsActionCount order${needsActionCount == 1 ? '' : 's'}',
                color: AppColors.warning,
                onTap: () => onGoToTab(2),
              ),
              _StatCard(
                icon: Icons.storefront_rounded,
                label: 'Active listings',
                value: '$activeCount',
                color: AppColors.info,
                onTap: () => onGoToTab(1),
              ),
              _StatCard(
                icon: Icons.inventory_2_outlined,
                label: 'Low stock / sold out',
                value: '${lowStockCount + soldOutCount}',
                color: AppColors.error,
                onTap: () => onGoToTab(1),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CreateProductScreen()),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add listing'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.push('/shop/${shop.id}'),
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text('View storefront'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Recent orders',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
              if (orders.isNotEmpty)
                TextButton(
                  onPressed: () => onGoToTab(2),
                  child: const Text('See all'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No orders yet',
                    style: TextStyle(color: Colors.white54)),
              ),
            )
          else
            for (final order in orders.take(4))
              _RecentOrderTile(order: order),
        ],
      ),
    );
  }
}

class _ShopHeaderCard extends StatelessWidget {
  const _ShopHeaderCard({required this.shop});
  final ShopModel shop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.darkSurface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.darkBorder,
            backgroundImage: shop.logoUrl != null
                ? CachedNetworkImageProvider(shop.logoUrl!)
                : null,
            child: shop.logoUrl == null
                ? const Icon(Icons.storefront_rounded, color: Colors.white38)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (shop.isPublished
                            ? AppColors.success
                            : AppColors.warning)
                        .withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    shop.isPublished ? 'LIVE' : 'DRAFT',
                    style: TextStyle(
                        color: shop.isPublished
                            ? AppColors.success
                            : AppColors.warning,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({
    required this.soldOutCount,
    required this.lowStockCount,
    required this.onTap,
  });
  final int soldOutCount;
  final int lowStockCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (soldOutCount > 0) '$soldOutCount sold out',
      if (lowStockCount > 0) '$lowStockCount running low',
    ];
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: AppColors.warning, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${parts.join(' · ')} — restock or update these listings',
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.darkSurface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const Spacer(),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order});
  final OrderModel order;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(order.productTitle ?? 'Order',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          Text('${order.currency} ${order.amount.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      ),
    );
  }
}

class _OverviewMessage extends StatelessWidget {
  const _OverviewMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.onRefresh,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white24, size: 48),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
    if (onRefresh == null) return content;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      child: ListView(children: [content]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Listings ("shelf" management -- on/off shelf, quick stock edit)
// ─────────────────────────────────────────────────────────────────

class _ListingsTab extends ConsumerWidget {
  const _ListingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(myListingsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        heroTag: 'shop-admin-add-listing',
        tooltip: 'Add listing',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateProductScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: listingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Couldn't load your listings",
                    style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(myListingsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (listings) {
          if (listings.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        color: Colors.white24, size: 48),
                    const SizedBox(height: 14),
                    const Text("You haven't listed anything yet",
                        style: TextStyle(color: Colors.white70, fontSize: 15)),
                    const SizedBox(height: 6),
                    const Text('Tap the + button to add your first item.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13)),
                  ],
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myListingsProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              itemCount: listings.length,
              itemBuilder: (context, i) => _ListingRow(product: listings[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ListingRow extends ConsumerStatefulWidget {
  const _ListingRow({required this.product});
  final ProductModel product;

  @override
  ConsumerState<_ListingRow> createState() => _ListingRowState();
}

class _ListingRowState extends ConsumerState<_ListingRow> {
  bool _isToggling = false;

  Future<void> _toggleActive(bool value) async {
    setState(() => _isToggling = true);
    try {
      await MarketplaceRepository.instance
          .updateProduct(widget.product.id, isActive: value);
      ref.invalidate(myListingsProvider);
    } catch (e) {
      debugPrint('ShopAdmin toggle listing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(value
                ? "Couldn't put this back on shelf — try again."
                : "Couldn't take this off shelf — try again.")));
      }
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  Future<void> _editStock() async {
    final controller = TextEditingController(
        text: widget.product.stock?.toString() ?? '');
    final result = await showDialog<int?>(
      context: context,
      builder: (dialogContext) {
        // Declared here, one level above StatefulBuilder's own builder
        // callback, so it survives across the setDialogState-triggered
        // rebuilds below -- declaring it inside that inner callback
        // instead would reset it to null on every rebuild, right before
        // the error text it's supposed to hold ever gets a chance to
        // render.
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.darkSurface2,
              title: const Text('Update stock',
                  style: TextStyle(color: Colors.white)),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Stock (leave blank for unlimited)',
                  errorText: error,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                // Distinguishing "cancelled" (null result, dialog just
                // closed) from "saved as unlimited" (an explicit -1
                // sentinel meaning "the field was left blank on
                // purpose") is why this isn't a plain `int?` pop --
                // both cases would otherwise pop something that looks
                // like "no number."
                ElevatedButton(
                  onPressed: () {
                    final text = controller.text.trim();
                    if (text.isEmpty) {
                      Navigator.of(dialogContext).pop(-1);
                      return;
                    }
                    final parsed = int.tryParse(text);
                    if (parsed == null || parsed < 0) {
                      // Invalid input stays on screen with an error
                      // instead of silently behaving like "Cancel" --
                      // popping null here would be indistinguishable
                      // from the person actually cancelling.
                      setDialogState(
                          () => error = 'Enter a whole number, or leave blank');
                      return;
                    }
                    Navigator.of(dialogContext).pop(parsed);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (result == null) return; // cancelled
    final newStock = result == -1 ? null : result;

    try {
      await MarketplaceRepository.instance
          .updateProduct(widget.product.id, stock: newStock);
      ref.invalidate(myListingsProvider);
    } catch (e) {
      debugPrint('ShopAdmin stock update failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Couldn't update stock — try again.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final stockLabel = product.stock == null
        ? 'Unlimited'
        : product.isSoldOut
            ? 'Sold out'
            : product.stock! <= _lowStockThreshold
                ? '${product.stock} left · low'
                : '${product.stock} in stock';
    final stockColor = product.stock == null
        ? Colors.white54
        : product.isSoldOut
            ? AppColors.error
            : product.stock! <= _lowStockThreshold
                ? AppColors.warning
                : Colors.white54;

    return Card(
      color: AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CreateProductScreen(product: product))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: product.coverImage != null
                      ? CachedNetworkImage(
                          imageUrl: product.coverImage!, fit: BoxFit.cover)
                      : Container(
                          color: AppColors.darkBorder,
                          child: const Icon(Icons.image_outlined,
                              color: Colors.white38, size: 22),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CreateProductScreen(product: product))),
                behavior: HitTestBehavior.opaque,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('${product.currency} ${product.price.toStringAsFixed(0)}',
                        style: const TextStyle(color: AppColors.secondary, fontSize: 13)),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _editStock,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(stockLabel,
                              style: TextStyle(color: stockColor, fontSize: 12)),
                          const SizedBox(width: 3),
                          const Icon(Icons.edit_outlined,
                              color: Colors.white24, size: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 4),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(product.isActive ? 'On shelf' : 'Off shelf',
                    style: TextStyle(
                        color: product.isActive ? AppColors.success : Colors.white38,
                        fontSize: 10)),
                _isToggling
                    ? const SizedBox(
                        width: 40,
                        height: 24,
                        child: Center(
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : Switch(
                        value: product.isActive,
                        activeThumbColor: AppColors.success,
                        onChanged: _toggleActive,
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopAsync = ref.watch(myShopProvider);
    final uid = SupabaseService.currentUserId;

    return shopAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Couldn't load your shop settings",
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => ref.invalidate(myShopProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (shop) {
        if (shop == null || uid == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storefront_outlined,
                      color: Colors.white24, size: 48),
                  const SizedBox(height: 14),
                  const Text("You haven't set up a shop yet",
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => context.push(AppRoutes.manageShop),
                    child: const Text('Set up my shop'),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ShopHeaderCard(shop: shop),
            const SizedBox(height: 20),
            _SettingsAction(
              icon: Icons.edit_outlined,
              label: 'Edit shop details',
              subtitle: 'Name, category, bio, banner and logo',
              onTap: () => context.push(AppRoutes.manageShop),
            ),
            _SettingsAction(
              icon: Icons.visibility_outlined,
              label: 'View my storefront',
              subtitle: 'See your shop the way buyers see it',
              onTap: () => context.push('/shop/$uid'),
            ),
            _SettingsAction(
              icon: Icons.receipt_long_outlined,
              label: 'All orders',
              subtitle: 'Full order history and fulfillment status',
              onTap: () => context.push(AppRoutes.sellerOrders),
            ),
          ],
        );
      },
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.darkSurface2,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(icon, color: Colors.white70),
        title: Text(label, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
        onTap: onTap,
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/product_model.dart';
import '../providers/marketplace_provider.dart';

/// Marketplace home — category tabs + search up top (research on
/// marketplace UX consistently comes back to the same two levers:
/// minimize taps between browsing and buying, and surface search/filter
/// prominently rather than burying it), a product grid with a seller
/// trust-signal strip on every card, and an "add listing" entry point
/// that routes through shop setup first for anyone who doesn't have a
/// shop yet (see _onAddTap below).
class MarketplaceHomeScreen extends ConsumerStatefulWidget {
  const MarketplaceHomeScreen({super.key});

  @override
  ConsumerState<MarketplaceHomeScreen> createState() =>
      _MarketplaceHomeScreenState();
}

class _MarketplaceHomeScreenState extends ConsumerState<MarketplaceHomeScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(marketplaceProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Marketplace'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'My orders',
            onPressed: () => context.push(AppRoutes.sellerOrders),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onAddTap(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) =>
                  ref.read(marketplaceProvider.notifier).setSearch(v),
              decoration: InputDecoration(
                hintText: 'Search listings',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38),
                filled: true,
                fillColor: AppColors.darkSurface2,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white38, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(marketplaceProvider.notifier).setSearch('');
                          setState(() {});
                        },
                      ),
              ),
              onChanged: (_) => setState(() {}), // toggles the clear button
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _CategoryChip(
                  label: 'All',
                  selected: state.category == null,
                  onTap: () =>
                      ref.read(marketplaceProvider.notifier).setCategory(null),
                ),
                for (final type in ProductType.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _CategoryChip(
                      label: _categoryLabel(type),
                      selected: state.category == type,
                      onTap: () => ref
                          .read(marketplaceProvider.notifier)
                          .setCategory(type),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: () => ref.read(marketplaceProvider.notifier).refresh(),
                    child: state.products.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text('No listings match this search',
                                    style: TextStyle(color: Colors.white54)),
                              ),
                            ],
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.66,
                            ),
                            itemCount: state.products.length,
                            itemBuilder: (context, i) =>
                                _ProductCard(product: state.products[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  /// Sending a seller-less user straight to "add a listing" produces an
  /// orphaned product with no storefront behind it — shop setup first
  /// means every listing that ever appears in the marketplace always has
  /// a real shop to click through to.
  Future<void> _onAddTap(BuildContext context, WidgetRef ref) async {
    final shop = await ref.read(myShopProvider.future);
    if (!context.mounted) return;
    if (shop == null) {
      context.push(AppRoutes.manageShop);
    } else {
      context.push(AppRoutes.createProduct);
    }
  }

  static String _categoryLabel(ProductType t) {
    switch (t) {
      case ProductType.merch:
        return 'Merch';
      case ProductType.book:
        return 'Books';
      case ProductType.course:
        return 'Courses';
      case ProductType.ticket:
        return 'Tickets';
    }
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.secondary : AppColors.darkSurface2,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/marketplace/${product.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface2,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.coverImage != null
                      ? CachedNetworkImage(
                          imageUrl: product.coverImage!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : Container(
                          color: AppColors.darkBorder,
                          child: const Icon(Icons.image_outlined,
                              color: Colors.white38, size: 32),
                        ),
                  if (product.isSoldOut)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('SOLD OUT',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${product.currency} ${product.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                        color: AppColors.secondary, fontWeight: FontWeight.w600),
                  ),
                  if (product.sellerName != null) ...[
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 7,
                          backgroundColor: AppColors.darkBorder,
                          backgroundImage: product.sellerAvatarUrl != null
                              ? CachedNetworkImageProvider(product.sellerAvatarUrl!)
                              : null,
                          child: product.sellerAvatarUrl == null
                              ? const Icon(Icons.person, size: 9, color: Colors.white38)
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            product.sellerName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

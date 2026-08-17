import 'dart:async';

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
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Filters as you type instead of making people find and tap the
  /// keyboard's search button -- the 450ms debounce is just enough to
  /// not fire a query per keystroke while still feeling live. Submitting
  /// (search button / Enter) bypasses the wait entirely.
  void _onSearchChanged(String value) {
    setState(() {}); // toggles the clear button
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      ref.read(marketplaceProvider.notifier).setSearch(value);
    });
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    ref.read(marketplaceProvider.notifier).setSearch(value);
  }

  void _clearFilters() {
    _searchDebounce?.cancel();
    _searchCtrl.clear();
    final notifier = ref.read(marketplaceProvider.notifier);
    notifier.setSearch('');
    notifier.setCategory(null);
    setState(() {});
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
            icon: const Icon(Icons.storefront_rounded),
            tooltip: 'My Shop',
            // Opens the seller dashboard directly on its Orders tab --
            // same starting point this icon always jumped to, just inside
            // the fuller dashboard (Overview/Listings/Settings are a tab
            // away) instead of the standalone orders-only screen.
            onPressed: () => context.push('${AppRoutes.shopAdmin}?tab=orders'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _onAddTap(context, ref),
        tooltip: 'List an item',
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
              onSubmitted: _onSearchSubmitted,
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
                          _onSearchSubmitted('');
                        },
                      ),
              ),
              onChanged: _onSearchChanged,
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
            child: _buildBody(state),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(MarketplaceState state) {
    if (state.isLoading && state.products.isEmpty) {
      // Only the very first load (or a hard refresh with nothing cached
      // yet) blocks the whole area -- a search/category change while
      // results are already on screen just lets the grid update under
      // RefreshIndicator's spinner instead of flashing to blank.
      return const Center(child: CircularProgressIndicator());
    }

    final hasFilter = state.category != null || state.search.isNotEmpty;

    Widget content;
    if (state.errorMessage != null && state.products.isEmpty) {
      content = _MarketplaceMessage(
        icon: Icons.wifi_off_rounded,
        title: "Couldn't load the marketplace",
        subtitle: 'Check your connection and pull down to try again.',
      );
    } else if (state.products.isEmpty && hasFilter) {
      content = _MarketplaceMessage(
        icon: Icons.search_off_rounded,
        title: 'No listings match this search',
        subtitle: 'Try a different keyword or category.',
        actionLabel: 'Clear filters',
        onAction: _clearFilters,
      );
    } else if (state.products.isEmpty) {
      content = const _MarketplaceMessage(
        icon: Icons.storefront_outlined,
        title: 'Nothing listed yet',
        subtitle: 'Be the first to open a shop and list something for sale.',
      );
    } else {
      content = GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.66,
        ),
        itemCount: state.products.length,
        itemBuilder: (context, i) => _ProductCard(product: state.products[i]),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(marketplaceProvider.notifier).refresh(),
      child: content is GridView
          ? content
          : ListView(children: [const SizedBox(height: 80), content]),
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

/// Shared shape for the marketplace's three "nothing to show" cases
/// (network error, filtered-to-nothing, genuinely empty) -- same icon +
/// title + subtitle layout, with an optional action button so
/// "no results for this filter" can offer a one-tap way out instead of
/// making people manually clear the search box and re-tap "All".
class _MarketplaceMessage extends StatelessWidget {
  const _MarketplaceMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white24, size: 48),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
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

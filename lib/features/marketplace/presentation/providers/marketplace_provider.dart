import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/marketplace_repository.dart';
import '../../domain/models/order_model.dart';
import '../../domain/models/product_model.dart';
import '../../domain/models/shop_model.dart';

// ── Marketplace listing state ───────────────────────────────────────

class MarketplaceState {
  const MarketplaceState({
    this.products = const [],
    this.isLoading = true,
    this.errorMessage,
    this.category,
    this.search = '',
  });

  final List<ProductModel> products;
  final bool isLoading;
  final String? errorMessage;

  /// Null = the "All" category tab.
  final ProductType? category;
  final String search;

  MarketplaceState copyWith({
    List<ProductModel>? products,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    ProductType? category,
    bool clearCategory = false,
    String? search,
  }) =>
      MarketplaceState(
        products: products ?? this.products,
        isLoading: isLoading ?? this.isLoading,
        // Same "?? this.x" pattern as category below can't tell "not
        // passed" apart from "passed as null", so a plain
        // `errorMessage ?? this.errorMessage` would let a stale error
        // survive every *successful* refresh after the first failure —
        // hence the explicit clearError flag, set at the start of every
        // refresh() attempt.
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        category: clearCategory ? null : (category ?? this.category),
        search: search ?? this.search,
      );
}

class MarketplaceNotifier extends StateNotifier<MarketplaceState> {
  MarketplaceNotifier() : super(const MarketplaceState()) {
    refresh();
  }

  final _repo = MarketplaceRepository.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final products = await _repo.fetchProducts(
        type: state.category,
        search: state.search,
      );
      state = state.copyWith(products: products, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> setCategory(ProductType? category) async {
    state = category == null
        ? state.copyWith(clearCategory: true)
        : state.copyWith(category: category);
    await refresh();
  }

  Future<void> setSearch(String search) async {
    state = state.copyWith(search: search);
    await refresh();
  }
}

final marketplaceProvider =
    StateNotifierProvider.autoDispose<MarketplaceNotifier, MarketplaceState>(
  (_) => MarketplaceNotifier(),
);

// ── Seller orders state ─────────────────────────────────────────────

class SellerOrdersState {
  const SellerOrdersState({this.orders = const [], this.isLoading = true});
  final List<OrderModel> orders;
  final bool isLoading;

  SellerOrdersState copyWith({List<OrderModel>? orders, bool? isLoading}) =>
      SellerOrdersState(
        orders: orders ?? this.orders,
        isLoading: isLoading ?? this.isLoading,
      );
}

class SellerOrdersNotifier extends StateNotifier<SellerOrdersState> {
  SellerOrdersNotifier() : super(const SellerOrdersState()) {
    refresh();
  }

  final _repo = MarketplaceRepository.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final orders = await _repo.fetchOrdersForSeller();
    state = state.copyWith(orders: orders, isLoading: false);
  }

  Future<void> markStatus(String orderId, FulfillmentStatus status) async {
    await _repo.updateFulfillmentStatus(orderId, status);
    await refresh();
  }
}

final sellerOrdersProvider =
    StateNotifierProvider.autoDispose<SellerOrdersNotifier, SellerOrdersState>(
  (_) => SellerOrdersNotifier(),
);

// ── Shops ─────────────────────────────────────────────────────────

/// The current user's own shop, or null if they haven't set one up yet.
/// Drives whether the marketplace's "add listing" FAB sends them to shop
/// setup first or straight to the listing form, and whether the profile
/// page's shop tile reads "Open my shop" vs "Start selling".
final myShopProvider = FutureProvider.autoDispose<ShopModel?>((ref) {
  return MarketplaceRepository.instance.fetchMyShop();
});

/// Any shop by owner id — the public storefront page. Re-fetch on demand
/// via `ref.invalidate(shopProvider(ownerId))` rather than watching a
/// stream, since a shop's own edits happen through this same app and can
/// just invalidate this provider directly.
final shopProvider =
    FutureProvider.autoDispose.family<ShopModel?, String>((ref, ownerId) {
  return MarketplaceRepository.instance.fetchShop(ownerId);
});

/// A shop's inventory grid, separate from the owner-scoped `myShopProvider`
/// so a visitor viewing someone else's storefront doesn't need to be the
/// owner to see what's for sale.
final shopProductsProvider = FutureProvider.autoDispose
    .family<List<ProductModel>, String>((ref, ownerId) {
  return MarketplaceRepository.instance.fetchProductsBySeller(ownerId);
});

/// The caller's own listings, active or not -- what the shop admin
/// dashboard's "Listings" tab manages. Deliberately separate from
/// `shopProductsProvider` (which is scoped to *published, active* items
/// for a public storefront view) since a seller managing their own
/// inventory needs to see off-shelf items too, in order to put them back
/// on shelf.
final myListingsProvider =
    FutureProvider.autoDispose<List<ProductModel>>((ref) {
  return MarketplaceRepository.instance.fetchMyListings();
});

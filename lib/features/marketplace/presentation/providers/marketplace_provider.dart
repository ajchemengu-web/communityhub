import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/marketplace_repository.dart';
import '../../domain/models/order_model.dart';
import '../../domain/models/product_model.dart';

// ── Marketplace listing state ───────────────────────────────────────

class MarketplaceState {
  const MarketplaceState({
    this.products = const [],
    this.isLoading = true,
    this.errorMessage,
  });

  final List<ProductModel> products;
  final bool isLoading;
  final String? errorMessage;

  MarketplaceState copyWith({
    List<ProductModel>? products,
    bool? isLoading,
    String? errorMessage,
  }) =>
      MarketplaceState(
        products: products ?? this.products,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

class MarketplaceNotifier extends StateNotifier<MarketplaceState> {
  MarketplaceNotifier() : super(const MarketplaceState()) {
    refresh();
  }

  final _repo = MarketplaceRepository.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final products = await _repo.fetchProducts();
      state = state.copyWith(products: products, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
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

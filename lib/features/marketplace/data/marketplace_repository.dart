import 'dart:io';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/models/order_model.dart';
import '../domain/models/product_model.dart';

class MarketplaceRepository {
  MarketplaceRepository._();
  static final instance = MarketplaceRepository._();

  final _client = SupabaseService.client;

  static const _productSelect = '''
    id, seller_id, community_id, type, title, description, price, currency,
    images, stock, is_active, created_at,
    seller:profiles!seller_id(full_name, avatar_url),
    communities(name)
  ''';

  static const _orderSelect = '''
    id, buyer_id, product_id, seller_id, quantity, amount, currency,
    fulfillment_status, payment_transaction_id, created_at,
    products(title),
    buyer:profiles!buyer_id(full_name, avatar_url)
  ''';

  // ── Products ──────────────────────────────────────────────────

  Future<List<ProductModel>> fetchProducts({String? communityId}) async {
    var query = _client.from('products').select(_productSelect).eq('is_active', true);
    if (communityId != null) {
      query = query.eq('community_id', communityId) as dynamic;
    }
    final rows = await (query as dynamic).order('created_at', ascending: false) as List;
    return rows
        .map((r) => ProductModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<ProductModel> fetchProductById(String productId) async {
    final row = await _client
        .from('products')
        .select(_productSelect)
        .eq('id', productId)
        .single();
    return ProductModel.fromMap(row);
  }

  Future<List<ProductModel>> fetchMyListings() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('products')
        .select(_productSelect)
        .eq('seller_id', uid)
        .order('created_at', ascending: false) as List;
    return rows
        .map((r) => ProductModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<ProductModel> createProduct({
    required ProductType type,
    required String title,
    required double price,
    String currency = 'KES',
    String? description,
    String? communityId,
    List<String> images = const [],
    int? stock,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final row = await _client
        .from('products')
        .insert({
          'seller_id': uid,
          'community_id': communityId,
          'type': ProductModel.typeString(type),
          'title': title,
          'description': description,
          'price': price,
          'currency': currency,
          'images': images,
          'stock': stock,
        })
        .select(_productSelect)
        .single();
    return ProductModel.fromMap(row);
  }

  Future<String> uploadProductImage(File file, String sellerId) async {
    final ext = file.path.split('.').last;
    final path = '$sellerId/${DateTime.now().millisecondsSinceEpoch}.$ext';
    await _client.storage.from(AppConstants.bucketProductImages).upload(path, file);
    return _client.storage.from(AppConstants.bucketProductImages).getPublicUrl(path);
  }

  // ── Orders ────────────────────────────────────────────────────

  /// Creates the order row before any money moves. Returns the new
  /// order id, used as `referenceId` when initiating the charge.
  Future<String> createOrder({
    required ProductModel product,
    int quantity = 1,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final row = await _client
        .from('orders')
        .insert({
          'buyer_id': uid,
          'product_id': product.id,
          'seller_id': product.sellerId,
          'quantity': quantity,
          'amount': product.price * quantity,
          'currency': product.currency,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<void> attachTransaction(String orderId, String transactionId) async {
    await _client
        .from('orders')
        .update({'payment_transaction_id': transactionId}).eq('id', orderId);
  }

  Future<List<OrderModel>> fetchMyOrders() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('orders')
        .select(_orderSelect)
        .eq('buyer_id', uid)
        .order('created_at', ascending: false) as List;
    return rows
        .map((r) => OrderModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<OrderModel>> fetchOrdersForSeller() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _client
        .from('orders')
        .select(_orderSelect)
        .eq('seller_id', uid)
        .order('created_at', ascending: false) as List;
    return rows
        .map((r) => OrderModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> updateFulfillmentStatus(
      String orderId, FulfillmentStatus status) async {
    await _client
        .from('orders')
        .update({'fulfillment_status': OrderModel.statusString(status)})
        .eq('id', orderId);
  }
}

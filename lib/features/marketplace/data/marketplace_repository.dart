import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/models/order_model.dart';
import '../domain/models/product_model.dart';
import '../domain/models/shop_model.dart';

class MarketplaceRepository {
  MarketplaceRepository._();
  static final instance = MarketplaceRepository._();

  final _client = SupabaseService.client;

  // NOTE: the seller embed below targets `users!seller_id`, not
  // `profiles!seller_id` — products.seller_id's actual FK is to
  // public.users (see 20260704d_marketplace_schema.sql), and there is no
  // public.profiles table/view in this schema, so `profiles!seller_id`
  // would fail to resolve as a PostgREST relationship. Fixed here because
  // the new shop/marketplace trust-signal UI depends on this actually
  // returning seller name/avatar; _orderSelect below has the same
  // `profiles!` pattern but is pre-existing and out of scope for this
  // change, so it's left as-is.
  static const _productSelect = '''
    id, seller_id, community_id, type, title, description, price, currency,
    images, stock, is_active, created_at,
    seller:users!seller_id(full_name, avatar_url),
    communities(name)
  ''';

  static const _shopSelect = '''
    id, name, bio, banner_url, logo_url, category, is_published, created_at,
    owner:users!id(full_name, avatar_url)
  ''';

  static const _orderSelect = '''
    id, buyer_id, product_id, seller_id, quantity, amount, currency,
    fulfillment_status, payment_transaction_id, created_at,
    products(title),
    buyer:profiles!buyer_id(full_name, avatar_url)
  ''';

  // ── Products ──────────────────────────────────────────────────

  /// [type] filters to one category tab (Merch/Books/Courses/Tickets) in
  /// the redesigned marketplace; [search] does a title match backed by
  /// the pg_trgm index added in 20260714_shops_schema.sql.
  Future<List<ProductModel>> fetchProducts({
    String? communityId,
    ProductType? type,
    String? search,
  }) async {
    var query = _client.from('products').select(_productSelect).eq('is_active', true);
    if (communityId != null) {
      query = query.eq('community_id', communityId) as dynamic;
    }
    if (type != null) {
      query = query.eq('type', ProductModel.typeString(type)) as dynamic;
    }
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('title', '%${search.trim()}%') as dynamic;
    }
    final rows = await (query as dynamic).order('created_at', ascending: false) as List;
    return rows
        .map((r) => ProductModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// A shop's public inventory grid — every active listing from one
  /// seller, newest first.
  Future<List<ProductModel>> fetchProductsBySeller(String sellerId) async {
    final rows = await _client
        .from('products')
        .select(_productSelect)
        .eq('seller_id', sellerId)
        .eq('is_active', true)
        .order('created_at', ascending: false) as List;
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

  // ── Shops ─────────────────────────────────────────────────────
  // shops.id = the owning user's id (see 20260714_shops_schema.sql), so
  // "does this user have a shop" and "load their shop" are both a plain
  // primary-key lookup — no separate shop-id indirection anywhere below.

  /// Null if [ownerId] has no shop yet, or has one but hasn't published
  /// it and isn't the caller themself (RLS enforces that half — a draft
  /// shop simply won't come back as a row for anyone else).
  Future<ShopModel?> fetchShop(String ownerId) async {
    final row = await _client
        .from('shops')
        .select(_shopSelect)
        .eq('id', ownerId)
        .maybeSingle();
    if (row == null) return null;
    return ShopModel.fromMap(row);
  }

  /// Convenience wrapper for "does *I* have a shop" checks (e.g. the
  /// marketplace FAB deciding whether to send the current user to shop
  /// setup or straight to the add-listing form).
  Future<ShopModel?> fetchMyShop() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return null;
    return fetchShop(uid);
  }

  /// Creates the caller's shop on first save, updates it on every save
  /// after — same single call either way since every column here is
  /// owner-writable and RLS's `id = auth.uid()` check on both INSERT and
  /// UPDATE means this can never target anyone else's row.
  Future<ShopModel> upsertShop({
    required String name,
    String? bio,
    String? bannerUrl,
    String? logoUrl,
    String? category,
    required bool isPublished,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final row = await _client
        .from('shops')
        .upsert({
          'id': uid,
          'name': name,
          'bio': bio,
          'banner_url': bannerUrl,
          'logo_url': logoUrl,
          'category': category,
          'is_published': isPublished,
        })
        .select(_shopSelect)
        .single();
    return ShopModel.fromMap(row);
  }

  Future<String> uploadShopImage(File file, {required String suffix}) async {
    final uid = SupabaseService.currentUserId!;
    final ext = file.path.split('.').last;
    // Deterministic path (banner/logo overwrite in place, mirroring
    // Profolio's own storage convention) instead of a timestamped name,
    // so re-uploading a banner doesn't leave the old one orphaned in the
    // bucket.
    final path = '$uid/$suffix.$ext';
    await _client.storage
        .from(AppConstants.bucketShopImages)
        .upload(path, file, fileOptions: const FileOptions(upsert: true));
    return _client.storage.from(AppConstants.bucketShopImages).getPublicUrl(path);
  }
}

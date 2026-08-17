/// A seller's storefront. One per user (`shops.id` = `users.id` — see
/// `20260714_shops_schema.sql`), holding the branding shown on the public
/// `/shop/:ownerId` page. The actual inventory is just that user's
/// `products` rows (fetched separately via
/// `MarketplaceRepository.fetchProductsBySeller`), not duplicated here.
class ShopModel {
  const ShopModel({
    required this.id,
    required this.name,
    required this.isPublished,
    required this.createdAt,
    this.bio,
    this.bannerUrl,
    this.logoUrl,
    this.category,
    this.ownerName,
    this.ownerAvatarUrl,
  });

  /// Same as the owning user's id.
  final String id;
  final String name;
  final String? bio;
  final String? bannerUrl;
  final String? logoUrl;
  final String? category;
  final bool isPublished;
  final DateTime createdAt;

  /// Denormalized from the joined `users` row — the account holder's own
  /// name/avatar, shown as a "run by" byline beneath the shop name so a
  /// storefront never feels anonymous (a trust signal, not a duplicate
  /// identity — the shop has its own name/branding, but visitors can
  /// still see the real person behind it).
  final String? ownerName;
  final String? ownerAvatarUrl;

  factory ShopModel.fromMap(Map<String, dynamic> map) {
    final owner = map['owner'] as Map?;
    return ShopModel(
      id: map['id'] as String,
      name: map['name'] as String,
      bio: map['bio'] as String?,
      bannerUrl: map['banner_url'] as String?,
      logoUrl: map['logo_url'] as String?,
      category: map['category'] as String?,
      isPublished: (map['is_published'] as bool?) ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
      ownerName: owner?['full_name'] as String?,
      ownerAvatarUrl: owner?['avatar_url'] as String?,
    );
  }
}

enum ProductType { merch, book, course, ticket }

class ProductModel {
  const ProductModel({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.price,
    required this.currency,
    required this.type,
    required this.isActive,
    required this.createdAt,
    this.communityId,
    this.communityName,
    this.sellerName,
    this.sellerAvatarUrl,
    this.description,
    this.images = const [],
    this.stock,
  });

  final String id;
  final String sellerId;
  final String? sellerName;
  final String? sellerAvatarUrl;
  final String? communityId;
  final String? communityName;
  final ProductType type;
  final String title;
  final String? description;
  final double price;
  final String currency;
  final List<String> images;
  final int? stock; // null = unlimited
  final bool isActive;
  final DateTime createdAt;

  bool get isSoldOut => stock != null && stock! <= 0;
  String? get coverImage => images.isEmpty ? null : images.first;

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    final seller = map['seller'] as Map?;
    final community = map['communities'] as Map?;
    return ProductModel(
      id: map['id'] as String,
      sellerId: map['seller_id'] as String,
      sellerName: seller?['full_name'] as String?,
      sellerAvatarUrl: seller?['avatar_url'] as String?,
      communityId: map['community_id'] as String?,
      communityName: community?['name'] as String?,
      type: _parseType(map['type'] as String? ?? 'merch'),
      title: map['title'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'KES',
      images: (map['images'] as List?)?.cast<String>() ?? const [],
      stock: map['stock'] as int?,
      isActive: (map['is_active'] as bool?) ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  static ProductType _parseType(String s) {
    switch (s) {
      case 'book':
        return ProductType.book;
      case 'course':
        return ProductType.course;
      case 'ticket':
        return ProductType.ticket;
      default:
        return ProductType.merch;
    }
  }

  static String typeString(ProductType t) {
    switch (t) {
      case ProductType.book:
        return 'book';
      case ProductType.course:
        return 'course';
      case ProductType.ticket:
        return 'ticket';
      case ProductType.merch:
        return 'merch';
    }
  }
}

class MembershipTierModel {
  const MembershipTierModel({
    required this.id,
    required this.communityId,
    required this.name,
    required this.price,
    required this.currency,
    required this.intervalDays,
    required this.isActive,
    this.communityName,
    this.description,
  });

  final String id;
  final String communityId;
  final String? communityName;
  final String name;
  final String? description;
  final double price;
  final String currency;
  final int intervalDays;
  final bool isActive;

  factory MembershipTierModel.fromMap(Map<String, dynamic> map) {
    final community = map['communities'] as Map?;
    return MembershipTierModel(
      id: map['id'] as String,
      communityId: map['community_id'] as String,
      communityName: community?['name'] as String?,
      name: map['name'] as String,
      description: map['description'] as String?,
      price: (map['price'] as num).toDouble(),
      currency: map['currency'] as String? ?? 'KES',
      intervalDays: (map['interval_days'] as int?) ?? 30,
      isActive: (map['is_active'] as bool?) ?? true,
    );
  }
}

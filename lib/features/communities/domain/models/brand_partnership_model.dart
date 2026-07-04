class BrandPartnershipModel {
  const BrandPartnershipModel({
    required this.id,
    required this.communityId,
    required this.brandName,
    required this.disclosureLabel,
    this.description,
  });

  final String id;
  final String communityId;
  final String brandName;
  final String? description;
  final String disclosureLabel;

  factory BrandPartnershipModel.fromMap(Map<String, dynamic> map) {
    return BrandPartnershipModel(
      id: map['id'] as String,
      communityId: map['community_id'] as String,
      brandName: map['brand_name'] as String,
      description: map['description'] as String?,
      disclosureLabel: map['disclosure_label'] as String? ?? 'Paid Partnership',
    );
  }
}

class CommunityChannelModel {
  const CommunityChannelModel({
    required this.id,
    required this.communityId,
    required this.name,
    this.description,
    this.isDefault = false,
    this.channelType = 'general',
    required this.createdAt,
    this.createdBy,
  });

  final String id;
  final String communityId;
  final String name;
  final String? description;
  final bool isDefault;       // Announcements & General cannot be removed
  final String channelType;   // 'announcements' | 'general'
  final DateTime createdAt;
  final String? createdBy;

  factory CommunityChannelModel.fromMap(Map<String, dynamic> map) {
    return CommunityChannelModel(
      id: map['id'] as String,
      communityId: map['community_id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      isDefault: (map['is_default'] as bool?) ?? false,
      channelType: map['channel_type'] as String? ?? 'general',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      createdBy: map['created_by'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'community_id': communityId,
        'name': name,
        'description': description,
        'is_default': isDefault,
        'channel_type': channelType,
        'created_by': createdBy,
      };
}

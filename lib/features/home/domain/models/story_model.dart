/// Typed model for a story row joined with its author's user data.
class StoryModel {
  const StoryModel({
    required this.id,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.isVerified,
    required this.mediaUrl,
    required this.mediaType,
    required this.isSeen,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String userId;

  // ── Author ────────────────────────────────────────────────
  final String username;
  final String avatarUrl;
  final bool isVerified;

  // ── Content ───────────────────────────────────────────────
  final String mediaUrl;
  final String mediaType; // 'image' | 'video'
  final bool isSeen;

  final DateTime expiresAt;
  final DateTime createdAt;

  bool get isActive => expiresAt.isAfter(DateTime.now());
  bool get isVideo => mediaType == 'video';

  factory StoryModel.fromMap(Map<String, dynamic> map) {
    final user = (map['users'] as Map<String, dynamic>?) ?? {};

    return StoryModel(
      id: map['id'] as String? ?? '',
      userId: map['user_id'] as String? ?? '',
      username: user['username'] as String? ?? 'user',
      avatarUrl: user['avatar_url'] as String? ?? '',
      isVerified: user['is_verified'] as bool? ?? false,
      mediaUrl: map['media_url'] as String? ?? '',
      mediaType: map['media_type'] as String? ?? 'image',
      isSeen: map['is_seen'] as bool? ?? false,
      expiresAt: DateTime.tryParse(map['expires_at'] as String? ?? '') ??
          DateTime.now().add(const Duration(hours: 24)),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

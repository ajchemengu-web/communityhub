/// Typed model for a post row joined with its author's user data.
/// Created from a Supabase `posts` row that includes a nested `users` object
/// and optional `is_liked` / `is_bookmarked` booleans from check queries.
class PostModel {
  const PostModel({
    required this.id,
    required this.userId,
    required this.caption,
    required this.hubType,
    required this.mediaUrls,
    required this.mediaType,
    required this.likesCount,
    required this.commentsCount,
    required this.sharesCount,
    required this.isLikedByCurrentUser,
    required this.createdAt,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.isVerified = false,
    this.thumbnailUrl,
    this.tags = const [],
    this.youtubeUrl,
    this.isBookmarkedByCurrentUser = false,
    this.audioTitle,
    this.audioArtist,
    this.audioPreviewUrl,
  });

  final String id;
  final String userId;

  // ── Author info (from joined users row) ──────────────────
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final bool isVerified;

  // ── Content ───────────────────────────────────────────────
  final String caption;
  final String hubType; // 'all' | 'faith' | 'career'
  final List<String> mediaUrls;
  final String mediaType; // 'text' | 'image' | 'video'
  final String? thumbnailUrl;
  final List<String> tags;
  final String? youtubeUrl;
  final String? audioTitle;
  final String? audioArtist;
  final String? audioPreviewUrl;

  // ── Engagement ────────────────────────────────────────────
  final int likesCount;
  final int commentsCount;
  final int sharesCount;
  final bool isLikedByCurrentUser;
  final bool isBookmarkedByCurrentUser;

  final DateTime createdAt;

  // ── Helpers ───────────────────────────────────────────────

  String get displayName => fullName ?? username ?? 'User';
  // Backward-compat alias used by FeedPostCard
  String get usernameDisplay => username ?? 'user';
  bool get hasMedia => mediaUrls.isNotEmpty;
  bool get isMultiMedia => mediaUrls.length > 1;
  bool get isVideo => mediaType == 'video';
  bool get hasAudioTrack =>
      audioPreviewUrl != null && audioPreviewUrl!.isNotEmpty;

  // ── Factory ───────────────────────────────────────────────

  static List<String> _parseMediaUrls(Map<String, dynamic> map) {
    // Supports both array (media_urls) and single string (media_url) formats
    final arr = map['media_urls'];
    if (arr is List) return arr.cast<String>();
    final single = (map['media_url'] ?? map['thumbnail_url']) as String?;
    if (single != null && single.isNotEmpty) return [single];
    return [];
  }

  factory PostModel.fromMap(Map<String, dynamic> map) {
    // Supabase returns joined user under 'users' key regardless of FK name
    final user = (map['users'] as Map<String, dynamic>?) ?? {};

    return PostModel(
      id: map['id'] as String? ?? '',
      userId: (map['author_id'] ?? map['user_id']) as String? ?? '',
      username: user['username'] as String?,
      fullName: user['full_name'] as String?,
      avatarUrl: user['avatar_url'] as String?,
      isVerified: user['is_verified'] as bool? ?? false,
      caption: (map['content'] ?? map['caption']) as String? ?? '',
      hubType: map['hub_type'] as String? ?? 'all',
      // DB has media_url (singular text) — wrap in list for app compatibility
      mediaUrls: _parseMediaUrls(map),
      mediaType: map['media_type'] as String? ?? 'text',
      thumbnailUrl: (map['media_thumbnail'] ?? map['thumbnail_url']) as String?,
      tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      youtubeUrl: map['youtube_url'] as String?,
      audioTitle: map['audio_title'] as String?,
      audioArtist: map['audio_artist'] as String?,
      audioPreviewUrl: map['audio_preview_url'] as String?,
      likesCount: map['likes_count'] as int? ?? 0,
      commentsCount: map['comments_count'] as int? ?? 0,
      sharesCount: (map['saves_count'] ?? map['shares_count']) as int? ?? 0,
      isLikedByCurrentUser: map['is_liked'] as bool? ?? false,
      isBookmarkedByCurrentUser: map['is_bookmarked'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  PostModel copyWith({
    int? likesCount,
    int? commentsCount,
    bool? isLikedByCurrentUser,
    bool? isBookmarkedByCurrentUser,
  }) {
    return PostModel(
      id: id,
      userId: userId,
      username: username,
      fullName: fullName,
      avatarUrl: avatarUrl,
      isVerified: isVerified,
      caption: caption,
      hubType: hubType,
      mediaUrls: mediaUrls,
      mediaType: mediaType,
      thumbnailUrl: thumbnailUrl,
      tags: tags,
      youtubeUrl: youtubeUrl,
      audioTitle: audioTitle,
      audioArtist: audioArtist,
      audioPreviewUrl: audioPreviewUrl,
      likesCount: likesCount ?? this.likesCount,
      commentsCount: commentsCount ?? this.commentsCount,
      sharesCount: sharesCount,
      isLikedByCurrentUser:
          isLikedByCurrentUser ?? this.isLikedByCurrentUser,
      isBookmarkedByCurrentUser:
          isBookmarkedByCurrentUser ?? this.isBookmarkedByCurrentUser,
      createdAt: createdAt,
    );
  }
}

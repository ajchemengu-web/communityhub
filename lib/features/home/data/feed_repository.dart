import '../../../core/constants/app_constants.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/youtube_service.dart';
import '../domain/models/post_model.dart';
import '../domain/models/story_model.dart';

/// Result type for a paginated post fetch.
class FeedPage {
  const FeedPage({required this.posts, required this.hasMore});
  final List<PostModel> posts;
  final bool hasMore;
}

/// All Supabase (and YouTube cache) interactions for the home feed.
class FeedRepository {
  FeedRepository._();
  static final FeedRepository instance = FeedRepository._();

  final _db = SupabaseService.client;

  // ── Posts ─────────────────────────────────────────────────

  /// Fetches a paginated page of posts. Pass [cursor] (created_at of the
  /// last item from the previous page) for subsequent pages.
  Future<FeedPage> fetchPosts({
    required String hubType,
    DateTime? cursor,
    int limit = AppConstants.feedPageSize,
  }) async {
    final uid = SupabaseService.currentUserId;

    // 1. Build the post query
    var query = _db
        .from('posts')
        .select('*, users(username, full_name, avatar_url, is_verified)')
        .eq('moderation_status', AppConstants.statusApproved)
        .order('created_at', ascending: false)
        .limit(limit + 1); // fetch one extra to detect hasMore

    if (hubType != AppConstants.hubAll) {
      query = query.eq('hub_type', hubType);
    }

    if (cursor != null) {
      query = query.lt('created_at', cursor.toIso8601String());
    }

    final rows = await query as List<dynamic>;

    final hasMore = rows.length > limit;
    final pageRows =
        hasMore ? rows.sublist(0, limit) : rows;

    // 2. Fetch liked post IDs for this batch (single round-trip)
    Set<String> likedIds = {};
    if (uid != null && pageRows.isNotEmpty) {
      final postIds =
          pageRows.map((r) => r['id'] as String).toList();
      final liked = await _db
          .from('post_likes')
          .select('post_id')
          .eq('user_id', uid)
          .inFilter('post_id', postIds) as List<dynamic>;
      likedIds = liked.map((r) => r['post_id'] as String).toSet();
    }

    final posts = pageRows.map((row) {
      final m = Map<String, dynamic>.from(row as Map);
      m['is_liked'] = likedIds.contains(row['id'] as String);
      return PostModel.fromMap(m);
    }).toList();

    return FeedPage(posts: posts, hasMore: hasMore);
  }

  // ── YouTube cache ─────────────────────────────────────────

  /// Returns cached YouTube videos from Supabase (never hits the YT API).
  Future<List<YouTubeVideo>> fetchCachedVideos({
    required String hubType,
    int limit = 8,
  }) async {
    try {
      var query = _db
          .from('youtube_cache')
          .select()
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('fetch_score', ascending: false)
          .limit(limit);

      if (hubType != AppConstants.hubAll) {
        query = query.eq('hub_type', hubType);
      }

      final rows = await query as List<dynamic>;

      return rows.map((yt) {
        final m = Map<String, dynamic>.from(yt as Map);
        return YouTubeVideo(
          id: m['youtube_id'] as String,
          title: m['title'] as String,
          description: m['description'] as String? ?? '',
          channelId: m['channel_id'] as String,
          channelTitle: m['channel_title'] as String,
          thumbnailUrl: m['thumbnail_url'] as String,
          publishedAt:
              DateTime.tryParse(m['published_at'] as String? ?? '') ??
                  DateTime.now(),
          viewCount: m['view_count'] as int?,
          likeCount: m['like_count'] as int?,
          duration: m['duration'] as String?,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Stories ───────────────────────────────────────────────

  /// Stories from people the current user follows (or all recent if no follows).
  Future<List<StoryModel>> fetchStories() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];

    try {
      // Fetch stories that haven't expired, from users other than self
      final rows = await _db
          .from('stories')
          .select('*, users(username, avatar_url, is_verified)')
          .gt('expires_at', DateTime.now().toIso8601String())
          .neq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(30) as List<dynamic>;

      return rows
          .map((r) =>
              StoryModel.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// The current user's own active story (for the "Your Story" bubble).
  Future<StoryModel?> fetchMyStory() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return null;

    try {
      final row = await _db
          .from('stories')
          .select('*, users(username, avatar_url, is_verified)')
          .eq('user_id', uid)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (row == null) return null;
      return StoryModel.fromMap(Map<String, dynamic>.from(row));
    } catch (_) {
      return null;
    }
  }

  // ── Likes ─────────────────────────────────────────────────

  /// Toggles the like on [postId] for the current user.
  /// Returns the updated like count, or null on failure.
  Future<int?> toggleLike(String postId, {required bool isCurrentlyLiked}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return null;

    try {
      if (isCurrentlyLiked) {
        // Unlike: delete the row
        await _db
            .from('post_likes')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', uid);
      } else {
        // Like: insert a row (ON CONFLICT DO NOTHING is handled by DB constraint)
        await _db.from('post_likes').upsert({
          'post_id': postId,
          'user_id': uid,
        });
      }

      // Fetch the current like count from the post row
      final result = await _db
          .from('posts')
          .select('likes_count')
          .eq('id', postId)
          .single();

      return result['likes_count'] as int? ?? 0;
    } catch (_) {
      return null;
    }
  }
}

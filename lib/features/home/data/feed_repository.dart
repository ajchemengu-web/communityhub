import '../../../core/constants/app_constants.dart';
import '../../../core/services/block_service.dart';
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
    final excludedIds = await BlockService.instance.fetchExcludedUserIds();

    // 1. Build the post query — join author info; no moderation filter so all posts show
    var query = _db
        .from('posts')
        .select('*, users!posts_author_id_fkey(username, full_name, avatar_url, is_verified)');

    if (excludedIds.isNotEmpty) {
      query = query.not('author_id', 'in', excludedIds);
    }

    if (hubType != AppConstants.hubAll) {
      // For parent hubs include all their sub-hubs
      if (hubType == AppConstants.hubScience) {
        final types = [AppConstants.hubScience, ...AppConstants.scienceSubHubs];
        query = query.inFilter('hub_type', types);
      } else if (hubType == AppConstants.hubTechnology) {
        final types = [AppConstants.hubTechnology, ...AppConstants.technologySubHubs];
        query = query.inFilter('hub_type', types);
      } else if (hubType == AppConstants.hubLanguages) {
        final types = [AppConstants.hubLanguages, ...AppConstants.languageSubHubs];
        query = query.inFilter('hub_type', types);
      } else {
        query = query.eq('hub_type', hubType);
      }
    }

    if (cursor != null) {
      query = query.lt('created_at', cursor.toIso8601String());
    }

    List<dynamic> rows = await query
        .order('created_at', ascending: false)
        .limit(limit + 1) as List<dynamic>;

    // If hub filter returns nothing, fall back to all posts (hub_type may be null on old posts)
    if (rows.isEmpty && hubType != AppConstants.hubAll) {
      var fallbackQuery = _db
          .from('posts')
          .select('*, users!posts_author_id_fkey(username, full_name, avatar_url, is_verified)');
      if (excludedIds.isNotEmpty) {
        fallbackQuery = fallbackQuery.not('author_id', 'in', excludedIds);
      }
      rows = await fallbackQuery
          .order('created_at', ascending: false)
          .limit(limit + 1) as List<dynamic>;
    }

    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.sublist(0, limit) : rows;

    final posts = await _enrichAndMapRows(pageRows, uid);

    return FeedPage(posts: posts, hasMore: hasMore);
  }

  /// Fetches specific posts by id (used to surface boosted posts that
  /// weren't already part of the loaded feed page).
  Future<List<PostModel>> fetchPostsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final uid = SupabaseService.currentUserId;
    final excludedIds = await BlockService.instance.fetchExcludedUserIds();

    var query = _db
        .from('posts')
        .select('*, users!posts_author_id_fkey(username, full_name, avatar_url, is_verified)')
        .inFilter('id', ids);
    if (excludedIds.isNotEmpty) {
      query = query.not('author_id', 'in', excludedIds);
    }
    final rows = await query as List<dynamic>;

    return _enrichAndMapRows(rows, uid);
  }

  /// Fetches a page of user-generated reels (posts flagged `is_reel`) for
  /// the Reels feed, same shape/pagination as [fetchPosts].
  Future<FeedPage> fetchUserReels({
    DateTime? cursor,
    int limit = 10,
  }) async {
    final uid = SupabaseService.currentUserId;
    final excludedIds = await BlockService.instance.fetchExcludedUserIds();

    var query = _db
        .from('posts')
        .select(
            '*, users!posts_author_id_fkey(username, full_name, avatar_url, is_verified)')
        .eq('is_reel', true);

    if (excludedIds.isNotEmpty) {
      query = query.not('author_id', 'in', excludedIds);
    }
    if (cursor != null) {
      query = query.lt('created_at', cursor.toIso8601String());
    }

    final rows = await query
        .order('created_at', ascending: false)
        .limit(limit + 1) as List<dynamic>;

    final hasMore = rows.length > limit;
    final pageRows = hasMore ? rows.sublist(0, limit) : rows;
    final reels = await _enrichAndMapRows(pageRows, uid);

    return FeedPage(posts: reels, hasMore: hasMore);
  }

  /// Attaches liked/bookmarked flags for the current user and maps rows
  /// to [PostModel]s. Shared by [fetchPosts] and [fetchPostsByIds].
  Future<List<PostModel>> _enrichAndMapRows(
      List<dynamic> rows, String? uid) async {
    Set<String> likedIds = {};
    Set<String> bookmarkedIds = {};
    if (uid != null && rows.isNotEmpty) {
      try {
        final postIds = rows.map((r) => r['id'] as String).toList();
        final results = await Future.wait([
          _db
              .from('likes')
              .select('target_id')
              .eq('user_id', uid)
              .eq('target_type', 'post')
              .inFilter('target_id', postIds) as Future<dynamic>,
          _db
              .from('bookmarks')
              .select('post_id')
              .eq('user_id', uid)
              .inFilter('post_id', postIds) as Future<dynamic>,
        ]);
        likedIds = (results[0] as List<dynamic>)
            .map((r) => r['target_id'] as String)
            .toSet();
        bookmarkedIds = (results[1] as List<dynamic>)
            .map((r) => r['post_id'] as String)
            .toSet();
      } catch (_) {}
    }

    return rows.map((row) {
      final m = Map<String, dynamic>.from(row as Map);
      m['is_liked'] = likedIds.contains(row['id'] as String);
      m['is_bookmarked'] = bookmarkedIds.contains(row['id'] as String);
      return PostModel.fromMap(m);
    }).toList();
  }

  // ── YouTube cache ─────────────────────────────────────────

  /// Returns YouTube videos — tries Supabase cache first,
  /// falls back to live YouTube Data API v3 when cache is empty.
  Future<List<YouTubeVideo>> fetchCachedVideos({
    required String hubType,
    int limit = 10,
    int offset = 0,
  }) async {
    // 1. Try Supabase cache
    try {
      var query = _db
          .from('youtube_cache')
          .select()
          .gt('expires_at', DateTime.now().toIso8601String());

      if (hubType != AppConstants.hubAll) {
        query = query.eq('hub_type', hubType);
      }

      final rows = await query
          .order('fetch_score', ascending: false)
          .range(offset, offset + limit - 1) as List<dynamic>;

      if (rows.isNotEmpty) {
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
      }
    } catch (_) {}

    // 2. Cache empty — fetch live from YouTube API
    return _fetchLiveYouTube(hubType: hubType, limit: limit);
  }

  Future<List<YouTubeVideo>> _fetchLiveYouTube({
    required String hubType,
    int limit = 10,
  }) async {
    try {
      final yt = YouTubeService.instance;
      if (AppConstants.youtubeApiKey == 'YOUR_YOUTUBE_API_KEY') return [];

      if (hubType == AppConstants.hubAll) {
        // Mix faith + science + technology + languages evenly
        final quarter = (limit / 4).ceil();
        final results = await Future.wait([
          yt.getFaithFeed(maxResults: quarter),
          yt.getHubFeed(hubType: AppConstants.hubScience, maxResults: quarter),
          yt.getHubFeed(hubType: AppConstants.hubTechnology, maxResults: quarter),
          yt.getHubFeed(hubType: AppConstants.hubLanguages, maxResults: quarter),
        ]);
        final merged = [...results[0], ...results[1], ...results[2], ...results[3]];
        merged.shuffle();
        return merged.take(limit).toList();
      } else if (hubType == AppConstants.hubFaith) {
        return await yt.getFaithFeed(maxResults: limit);
      } else {
        // All other hubs (career/technology, science, sub-hubs, languages)
        return await yt.getHubFeed(hubType: hubType, maxResults: limit);
      }
    } catch (_) {
      return [];
    }
  }

  // ── Stories ───────────────────────────────────────────────

  /// Stories from people the current user follows — matches WhatsApp's
  /// "contacts only" Updates list rather than showing every public
  /// account's story. RLS separately enforces privacy/blocking/audience
  /// restriction; this scoping is about *whose* updates surface here at
  /// all, not a security boundary by itself.
  Future<List<StoryModel>> fetchStories() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];

    try {
      final excludedIds = await BlockService.instance.fetchExcludedUserIds();

      final followRows = await _db
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .eq('status', 'accepted') as List<dynamic>;
      final followingIds =
          followRows.map((r) => r['following_id'] as String).toList();
      if (followingIds.isEmpty) return [];

      var query = _db
          .from('stories')
          .select('*, users(username, avatar_url, is_verified)')
          .gt('expires_at', DateTime.now().toIso8601String())
          .inFilter('user_id', followingIds);
      if (excludedIds.isNotEmpty) {
        query = query.not('user_id', 'in', excludedIds);
      }
      final rows = await query
          .order('created_at', ascending: false)
          .limit(100) as List<dynamic>;

      return _attachSeenStatus(rows, uid);
    } catch (_) {
      return [];
    }
  }

  /// Populates `isSeen` from `story_views` — the raw row data never has
  /// this (no join in the query above), so without this every story
  /// always looked unviewed regardless of actual view history.
  Future<List<StoryModel>> _attachSeenStatus(
      List<dynamic> rows, String uid) async {
    Set<String> seenIds = {};
    if (rows.isNotEmpty) {
      try {
        final storyIds = rows.map((r) => r['id'] as String).toList();
        final views = await _db
            .from('story_views')
            .select('story_id')
            .eq('user_id', uid)
            .inFilter('story_id', storyIds) as List<dynamic>;
        seenIds = views.map((r) => r['story_id'] as String).toSet();
      } catch (_) {}
    }
    return rows.map((r) {
      final map = Map<String, dynamic>.from(r as Map);
      map['is_seen'] = seenIds.contains(map['id']);
      return StoryModel.fromMap(map);
    }).toList();
  }

  /// The ids of users whose updates the current user has muted — their
  /// stories still show, just deprioritized into their own section.
  Future<Set<String>> fetchMutedUserIds() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return {};
    try {
      final rows = await _db
          .from('story_mutes')
          .select('muted_id')
          .eq('muter_id', uid) as List<dynamic>;
      return rows.map((r) => r['muted_id'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> muteStoryUser(String userId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      await _db.from('story_mutes').upsert({
        'muter_id': uid,
        'muted_id': userId,
      });
    } catch (_) {}
  }

  Future<void> unmuteStoryUser(String userId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      await _db
          .from('story_mutes')
          .delete()
          .eq('muter_id', uid)
          .eq('muted_id', userId);
    } catch (_) {}
  }

  /// Who has viewed one of the current user's own stories — the
  /// "seen by" list shown on your active status.
  Future<List<Map<String, dynamic>>> fetchStoryViewers(String storyId) async {
    try {
      final rows = await _db
          .from('story_views')
          .select('viewed_at, users(id, username, full_name, avatar_url)')
          .eq('story_id', storyId)
          .order('viewed_at', ascending: false) as List<dynamic>;
      return rows
          .map((r) => Map<String, dynamic>.from(r as Map))
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

  /// All of the current user's own active stories, oldest first, for
  /// viewing them back-to-back — [fetchMyStory] only ever returns the
  /// single latest one, which meant a second/third story of the day was
  /// never actually viewable.
  Future<List<StoryModel>> fetchMyStories() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];

    try {
      final rows = await _db
          .from('stories')
          .select('*, users(username, avatar_url, is_verified)')
          .eq('user_id', uid)
          .gt('expires_at', DateTime.now().toIso8601String())
          .order('created_at', ascending: true) as List<dynamic>;

      return rows
          .map((r) => StoryModel.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Likes ─────────────────────────────────────────────────

  /// Toggles the like on [postId] for the current user.
  /// Returns the updated like count, or null on failure.
  Future<int?> toggleLike(String postId,
      {required bool isCurrentlyLiked}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return null;

    try {
      if (isCurrentlyLiked) {
        // Unlike: delete the row
        await _db
            .from('likes')
            .delete()
            .eq('target_id', postId)
            .eq('target_type', 'post')
            .eq('user_id', uid);
      } else {
        // Like: insert a row (unique constraint on user_id+target_id+target_type
        // makes this idempotent under race/double-tap)
        await _db.from('likes').upsert({
          'target_id': postId,
          'target_type': 'post',
          'user_id': uid,
        }, onConflict: 'user_id,target_id,target_type');
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

  // ── Bookmarks ─────────────────────────────────────────────

  /// Toggles bookmark on [postId]. Returns new bookmarked state.
  Future<bool> toggleBookmark(String postId,
      {required bool isCurrentlyBookmarked}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return isCurrentlyBookmarked;

    try {
      if (isCurrentlyBookmarked) {
        await _db
            .from('bookmarks')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', uid);
        return false;
      } else {
        await _db.from('bookmarks').upsert({
          'post_id': postId,
          'user_id': uid,
        });
        return true;
      }
    } catch (_) {
      return isCurrentlyBookmarked;
    }
  }
}

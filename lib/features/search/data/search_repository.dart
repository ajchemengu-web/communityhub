import '../../../core/constants/app_constants.dart';
import '../../../core/services/block_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/services/youtube_service.dart';
import '../../home/domain/models/post_model.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/domain/models/notification_model.dart';

class UserResult {
  const UserResult({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.isVerified = false,
    this.isFollowing = false,
  });

  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isFollowing;

  String get displayName => fullName.isNotEmpty ? fullName : username;
}

class CommunityResult {
  const CommunityResult({
    required this.id,
    required this.name,
    required this.memberCount,
    this.coverUrl,
    this.description,
    this.hubType,
  });

  final String id;
  final String name;
  final int memberCount;
  final String? coverUrl;
  final String? description;
  final String? hubType;
}

class SearchRepository {
  SearchRepository._();
  static final SearchRepository instance = SearchRepository._();

  final _db = SupabaseService.client;

  // ── Trending ───────────────────────────────────────────────

  Future<List<PostModel>> fetchTrending({int limit = 20}) async {
    // Try with moderation filter first; fall back to all posts
    try {
      final excludedIds = await BlockService.instance.fetchExcludedUserIds();
      final since = DateTime.now()
          .subtract(const Duration(days: 7))
          .toIso8601String();
      var q = _db
          .from('posts')
          .select('*')
          .eq('moderation_status', 'approved')
          .gte('created_at', since);
      if (excludedIds.isNotEmpty) q = q.not('author_id', 'in', excludedIds);
      var rows = await q
          .order('likes_count', ascending: false)
          .limit(limit) as List<dynamic>;

      if (rows.isEmpty) {
        // Fall back: all posts, any status
        var fallbackQ = _db.from('posts').select('*');
        if (excludedIds.isNotEmpty) {
          fallbackQ = fallbackQ.not('author_id', 'in', excludedIds);
        }
        rows = await fallbackQ
            .order('likes_count', ascending: false)
            .limit(limit) as List<dynamic>;
      }

      return rows
          .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Post search ────────────────────────────────────────────

  Future<List<PostModel>> searchPosts(String query, {String? hubType}) async {
    if (query.trim().isEmpty) return [];

    try {
      final excludedIds = await BlockService.instance.fetchExcludedUserIds();

      // Search caption OR hub_type — no moderation filter so new DBs work
      var q = _db
          .from('posts')
          .select('*')
          .or('caption.ilike.%$query%,hub_type.ilike.%$query%');

      if (hubType != null && hubType != 'all') {
        q = q.eq('hub_type', hubType);
      }
      if (excludedIds.isNotEmpty) q = q.not('author_id', 'in', excludedIds);

      final rows = await q
          .order('created_at', ascending: false)
          .limit(30) as List<dynamic>;

      // If nothing, retry with just caption and no status filter
      if (rows.isEmpty) {
        var fallbackQ = _db.from('posts').select('*').ilike('caption', '%$query%');
        if (excludedIds.isNotEmpty) {
          fallbackQ = fallbackQ.not('author_id', 'in', excludedIds);
        }
        final fallback = await fallbackQ
            .order('created_at', ascending: false)
            .limit(30) as List<dynamic>;
        return fallback
            .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r as Map)))
            .toList();
      }

      return rows
          .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── YouTube search ─────────────────────────────────────────

  Future<List<YouTubeVideo>> searchVideos(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      if (AppConstants.youtubeApiKey == 'YOUR_YOUTUBE_API_KEY') return [];
      final yt = YouTubeService.instance;
      return await yt.searchVideos(query: query, maxResults: 15);
    } catch (_) {
      return [];
    }
  }

  // ── User search ────────────────────────────────────────────

  Future<List<UserResult>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final uid = SupabaseService.currentUserId;

    try {
      final excludedIds = await BlockService.instance.fetchExcludedUserIds();
      var userQuery = _db
          .from('users')
          .select('id, username, full_name, avatar_url, is_verified')
          .or('username.ilike.%$query%,full_name.ilike.%$query%');
      if (excludedIds.isNotEmpty) {
        userQuery = userQuery.not('id', 'in', excludedIds);
      }
      final rows = await userQuery.limit(20) as List<dynamic>;

      Set<String> followingIds = {};
      if (uid != null && rows.isNotEmpty) {
        final ids = rows.map((r) => r['id'] as String).toList();
        try {
          final follows = await _db
              .from('follows')
              .select('following_id')
              .eq('follower_id', uid)
              .eq('status', 'accepted')
              .inFilter('following_id', ids) as List<dynamic>;
          followingIds =
              follows.map((r) => r['following_id'] as String).toSet();
        } catch (_) {}
      }

      return rows.map((r) {
        return UserResult(
          id: r['id'] as String,
          username: r['username'] as String? ?? '',
          fullName: r['full_name'] as String? ?? '',
          avatarUrl: r['avatar_url'] as String?,
          isVerified: (r['is_verified'] as bool?) ?? false,
          isFollowing: followingIds.contains(r['id'] as String),
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  // ── Follow toggle ──────────────────────────────────────────

  /// Note: returns `true` only when the follow is immediately accepted.
  /// Following a private account from a search result still creates a
  /// pending request (consistent with the profile screen), but this
  /// simpler bool-returning API just reports it as "not following yet" —
  /// see `ProfileDetailRepository.toggleFollow` for the full tri-state
  /// version used on the profile screen where "Requested" is shown.
  Future<bool> toggleFollow(String targetId,
      {required bool isCurrentlyFollowing}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return isCurrentlyFollowing;
    try {
      if (isCurrentlyFollowing) {
        await _db
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('following_id', targetId);
        return false;
      } else {
        final target = await _db
            .from('users')
            .select('is_private')
            .eq('id', targetId)
            .maybeSingle();
        final isPrivate = (target?['is_private'] as bool?) ?? false;
        final status = isPrivate ? 'pending' : 'accepted';

        await _db.from('follows').upsert({
          'follower_id': uid,
          'following_id': targetId,
          'status': status,
        });
        _sendFollowNotification(uid, targetId);
        return status == 'accepted';
      }
    } catch (_) {
      return isCurrentlyFollowing;
    }
  }

  Future<void> _sendFollowNotification(String actorId, String targetId) async {
    try {
      final actor = await _db
          .from('users')
          .select('full_name, username')
          .eq('id', actorId)
          .maybeSingle();
      final name = actor?['full_name'] as String? ??
          actor?['username'] as String? ??
          'Someone';
      await NotificationsRepository.instance.createNotification(
        userId: targetId,
        type: NotificationType.follow,
        title: 'New follower',
        body: '$name started following you',
        actorId: actorId,
      );
    } catch (_) {}
  }

  // ── Suggested users (discover) ────────────────────────────────

  Future<List<UserResult>> fetchSuggestedUsers({int limit = 10}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    try {
      final excludedIds = await BlockService.instance.fetchExcludedUserIds();

      // People the current user doesn't follow yet, ordered by follower count
      // We approximate by joining follows and ordering by count
      var suggestQuery = _db
          .from('users')
          .select('id, username, full_name, avatar_url, is_verified')
          .neq('id', uid);
      if (excludedIds.isNotEmpty) {
        suggestQuery = suggestQuery.not('id', 'in', excludedIds);
      }
      final rows = await suggestQuery.limit(limit * 3) as List<dynamic>; // over-fetch, then filter

      if (rows.isEmpty) return [];

      final ids = rows.map((r) => r['id'] as String).toList();

      // Which of these does the current user already follow?
      final alreadyFollows = await _db
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .inFilter('following_id', ids) as List<dynamic>;

      final followingSet =
          alreadyFollows.map((r) => r['following_id'] as String).toSet();

      final suggestions = rows
          .where((r) => !followingSet.contains(r['id'] as String))
          .take(limit)
          .map((r) => UserResult(
                id: r['id'] as String,
                username: r['username'] as String? ?? '',
                fullName: r['full_name'] as String? ?? '',
                avatarUrl: r['avatar_url'] as String?,
                isVerified: (r['is_verified'] as bool?) ?? false,
                isFollowing: false,
              ))
          .toList();

      return suggestions;
    } catch (_) {
      return [];
    }
  }

  // ── Community search ───────────────────────────────────────

  Future<List<CommunityResult>> searchCommunities(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final rows = await _db
          .from('communities')
          .select('id, name, members_count, cover_url, description, hub_type')
          .or('name.ilike.%$query%,description.ilike.%$query%')
          .order('members_count', ascending: false)
          .limit(20) as List<dynamic>;

      return rows
          .map((r) => CommunityResult(
                id: r['id'] as String,
                name: r['name'] as String,
                memberCount: (r['members_count'] as int?) ?? 0,
                coverUrl: r['cover_url'] as String?,
                description: r['description'] as String?,
                hubType: r['hub_type'] as String?,
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

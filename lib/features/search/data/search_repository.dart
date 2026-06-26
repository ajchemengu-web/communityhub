import '../../../core/services/supabase_service.dart';
import '../../home/domain/models/post_model.dart';

/// Search result types returned by [SearchRepository].
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

  // ── Trending posts (no query) ──────────────────────────────

  Future<List<PostModel>> fetchTrending({int limit = 20}) async {
    // Posts with most likes in last 7 days
    final since =
        DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    final rows = await _db
        .from('posts')
        .select('*, users(username, full_name, avatar_url, is_verified)')
        .eq('moderation_status', 'approved')
        .gte('created_at', since)
        .order('likes_count', ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ── Full-text search ──────────────────────────────────────

  Future<List<PostModel>> searchPosts(String query,
      {String? hubType}) async {
    if (query.trim().isEmpty) return [];

    var q = _db
        .from('posts')
        .select('*, users(username, full_name, avatar_url, is_verified)')
        .eq('moderation_status', 'approved')
        .ilike('caption', '%$query%')
        .order('created_at', ascending: false)
        .limit(30);

    if (hubType != null && hubType != 'all') {
      q = q.eq('hub_type', hubType);
    }

    final rows = await q;
    return (rows as List<dynamic>)
        .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<List<UserResult>> searchUsers(String query) async {
    if (query.trim().isEmpty) return [];
    final uid = SupabaseService.currentUserId;

    final rows = await _db
        .from('users')
        .select('id, username, full_name, avatar_url, is_verified')
        .or('username.ilike.%$query%,full_name.ilike.%$query%')
        .limit(20);

    // Check which ones the current user follows
    Set<String> followingIds = {};
    if (uid != null && (rows as List).isNotEmpty) {
      final ids = (rows).map((r) => r['id'] as String).toList();
      final follows = await _db
          .from('follows')
          .select('following_id')
          .eq('follower_id', uid)
          .inFilter('following_id', ids);
      followingIds =
          (follows as List).map((r) => r['following_id'] as String).toSet();
    }

    return (rows as List<dynamic>).map((r) {
      return UserResult(
        id: r['id'] as String,
        username: r['username'] as String? ?? '',
        fullName: r['full_name'] as String? ?? '',
        avatarUrl: r['avatar_url'] as String?,
        isVerified: (r['is_verified'] as bool?) ?? false,
        isFollowing: followingIds.contains(r['id'] as String),
      );
    }).toList();
  }

  Future<List<CommunityResult>> searchCommunities(String query) async {
    if (query.trim().isEmpty) return [];

    final rows = await _db
        .from('communities')
        .select('id, name, member_count, cover_url, description, hub_type')
        .ilike('name', '%$query%')
        .order('member_count', ascending: false)
        .limit(20);

    return (rows as List<dynamic>)
        .map((r) => CommunityResult(
              id: r['id'] as String,
              name: r['name'] as String,
              memberCount: (r['member_count'] as int?) ?? 0,
              coverUrl: r['cover_url'] as String?,
              description: r['description'] as String?,
              hubType: r['hub_type'] as String?,
            ))
        .toList();
  }
}

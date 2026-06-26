import '../../../core/services/supabase_service.dart';
import '../../home/domain/models/post_model.dart';

/// Fetches a user's full profile, their posts grid, follower/following counts,
/// and handles follow / unfollow actions.
class ProfileDetailRepository {
  ProfileDetailRepository._();
  static final ProfileDetailRepository instance =
      ProfileDetailRepository._();

  final _db = SupabaseService.client;

  // ── Profile ───────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchProfile(String userId) async {
    final row = await _db
        .from('users')
        .select(
            'id, username, full_name, avatar_url, bio, church_name, website, is_verified, created_at')
        .eq('id', userId)
        .single();

    // Followers / following counts
    final followerCount = await _db
        .from('follows')
        .select('id')
        .eq('following_id', userId)
        .count();

    final followingCount = await _db
        .from('follows')
        .select('id')
        .eq('follower_id', userId)
        .count();

    // Is the current user following this profile?
    bool isFollowing = false;
    final currentUid = SupabaseService.currentUserId;
    if (currentUid != null && currentUid != userId) {
      final follow = await _db
          .from('follows')
          .select('id')
          .eq('follower_id', currentUid)
          .eq('following_id', userId)
          .maybeSingle();
      isFollowing = follow != null;
    }

    // Post count
    final postCount = await _db
        .from('posts')
        .select('id')
        .eq('user_id', userId)
        .eq('moderation_status', 'approved')
        .count();

    return {
      ...Map<String, dynamic>.from(row),
      'follower_count': followerCount.count,
      'following_count': followingCount.count,
      'post_count': postCount.count,
      'is_following': isFollowing,
    };
  }

  // ── Posts grid ────────────────────────────────────────────

  Future<List<PostModel>> fetchUserPosts(String userId,
      {int page = 0, int pageSize = 18}) async {
    final rows = await _db
        .from('posts')
        .select('*, users(username, full_name, avatar_url, is_verified)')
        .eq('user_id', userId)
        .eq('moderation_status', 'approved')
        .order('created_at', ascending: false)
        .range(page * pageSize, (page + 1) * pageSize - 1);

    return (rows as List<dynamic>)
        .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r)))
        .toList();
  }

  // ── Follow / Unfollow ─────────────────────────────────────

  Future<bool> toggleFollow(String targetUserId,
      {required bool isCurrentlyFollowing}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null || uid == targetUserId) return isCurrentlyFollowing;

    try {
      if (isCurrentlyFollowing) {
        await _db
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('following_id', targetUserId);
        return false;
      } else {
        await _db.from('follows').upsert({
          'follower_id': uid,
          'following_id': targetUserId,
        });
        return true;
      }
    } catch (_) {
      return isCurrentlyFollowing;
    }
  }

  // ── Edit own profile ──────────────────────────────────────

  Future<void> updateProfile({
    required String userId,
    String? fullName,
    String? username,
    String? bio,
    String? churchName,
    String? website,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (username != null) updates['username'] = username;
    if (bio != null) updates['bio'] = bio;
    if (churchName != null) updates['church_name'] = churchName;
    if (website != null) updates['website'] = website;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (updates.isEmpty) return;

    await _db.from('users').update(updates).eq('id', userId);
  }
}

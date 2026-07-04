import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../home/domain/models/post_model.dart';
import '../../notifications/data/notifications_repository.dart';
import '../../notifications/domain/models/notification_model.dart';

/// Fetches a user's full profile, their posts grid, follower/following counts,
/// and handles follow / unfollow actions.
class ProfileDetailRepository {
  ProfileDetailRepository._();
  static final ProfileDetailRepository instance =
      ProfileDetailRepository._();

  final _db = SupabaseService.client;

  // ── Profile ───────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchProfile(String userId) async {
    var row = await _db
        .from('users')
        .select(
            'id, username, full_name, avatar_url, bio, church_name, website, is_verified, created_at')
        .eq('id', userId)
        .maybeSingle();

    // Profile row doesn't exist yet — create a default one
    if (row == null) {
      final authUser = SupabaseService.client.auth.currentUser;
      final email = authUser?.email ?? '';
      final defaultUsername = email.split('@').first;
      await _db.from('users').upsert({
        'id': userId,
        'username': defaultUsername,
        'full_name': defaultUsername,
        'email': email,
        'is_verified': false,
      });
      row = await _db
          .from('users')
          .select(
              'id, username, full_name, avatar_url, bio, church_name, website, is_verified, created_at')
          .eq('id', userId)
          .maybeSingle();
      row ??= {
        'id': userId,
        'username': defaultUsername,
        'full_name': defaultUsername,
        'avatar_url': null,
        'bio': null,
        'church_name': null,
        'website': null,
        'is_verified': false,
        'created_at': DateTime.now().toIso8601String(),
      };
    }

    // Followers / following counts
    int followerVal = 0;
    int followingVal = 0;
    try {
      final followerRes = await _db
          .from('follows')
          .select()
          .eq('following_id', userId)
          .count(CountOption.exact);
      followerVal = followerRes.count;

      final followingRes = await _db
          .from('follows')
          .select()
          .eq('follower_id', userId)
          .count(CountOption.exact);
      followingVal = followingRes.count;
    } catch (_) {}

    // Is the current user following this profile?
    bool isFollowing = false;
    final currentUid = SupabaseService.currentUserId;
    if (currentUid != null && currentUid != userId) {
      try {
        final follow = await _db
            .from('follows')
            .select()
            .eq('follower_id', currentUid)
            .eq('following_id', userId)
            .maybeSingle();
        isFollowing = follow != null;
      } catch (_) {}
    }

    // Post count — try author_id first, fall back to user_id
    int postCountVal = 0;
    try {
      final postRes = await _db
          .from('posts')
          .select()
          .eq('author_id', userId)
          .count(CountOption.exact);
      postCountVal = postRes.count;
    } catch (_) {
      try {
        final postRes = await _db
            .from('posts')
            .select()
            .eq('user_id', userId)
            .count(CountOption.exact);
        postCountVal = postRes.count;
      } catch (_) {}
    }

    return {
      ...Map<String, dynamic>.from(row),
      'follower_count': followerVal,
      'following_count': followingVal,
      'post_count': postCountVal,
      'is_following': isFollowing,
    };
  }

  // ── Posts grid ────────────────────────────────────────────

  Future<List<PostModel>> fetchUserPosts(String userId,
      {int page = 0, int pageSize = 18}) async {
    final range = [page * pageSize, (page + 1) * pageSize - 1];

    // 1. Try with FK join for full author data
    try {
      final rows = await _db
          .from('posts')
          .select('*, users!posts_author_id_fkey(username, full_name, avatar_url, is_verified)')
          .eq('author_id', userId)
          .order('created_at', ascending: false)
          .range(range[0], range[1]);
      return (rows as List<dynamic>)
          .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {}

    // 2. FK join failed — try author_id without join
    try {
      final rows = await _db
          .from('posts')
          .select('*')
          .eq('author_id', userId)
          .order('created_at', ascending: false)
          .range(range[0], range[1]);
      return (rows as List<dynamic>)
          .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {}

    // 3. Legacy: some posts stored with user_id
    try {
      final rows = await _db
          .from('posts')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(range[0], range[1]);
      return (rows as List<dynamic>)
          .map((r) => PostModel.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {}

    return [];
  }

  // ── Creator dashboard stats ───────────────────────────────

  Future<Map<String, dynamic>> fetchCreatorStats(String userId) async {
    final stats = <String, dynamic>{
      'totalLikes': 0,
      'totalComments': 0,
      'totalViews': 0,
      'totalPosts': 0,
      'topPost': null,
    };
    try {
      final rows = await _db
          .from('posts')
          .select('id, content, likes_count, comments_count, views_count, media_url')
          .eq('author_id', userId)
          .order('likes_count', ascending: false) as List<dynamic>;

      if (rows.isEmpty) return stats;

      int likes = 0, comments = 0, views = 0;
      for (final r in rows) {
        likes += (r['likes_count'] as int? ?? 0);
        comments += (r['comments_count'] as int? ?? 0);
        views += (r['views_count'] as int? ?? 0);
      }
      stats['totalLikes'] = likes;
      stats['totalComments'] = comments;
      stats['totalViews'] = views;
      stats['totalPosts'] = rows.length;
      stats['topPost'] = Map<String, dynamic>.from(rows.first as Map);
    } catch (_) {}
    return stats;
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
        // Send follow notification (fire-and-forget)
        _sendFollowNotification(uid, targetUserId);
        return true;
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

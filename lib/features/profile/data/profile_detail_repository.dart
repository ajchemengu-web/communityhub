import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/block_service.dart';
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
            'id, username, full_name, avatar_url, bio, church_name, website, is_verified, is_private, created_at')
        .eq('id', userId)
        .maybeSingle();

    // Profile row doesn't exist yet. This can now only really happen
    // for an OAuth sign-in that hasn't gone through profile setup, or
    // an environment that hasn't picked up the on_auth_user_created
    // trigger yet (see 20260816c_auth_atomic_profile_and_email_lockdown.sql,
    // which makes profile creation atomic with signup going forward).
    //
    // Only ever self-heal the CURRENT user's own row here — this used
    // to create a stub for whatever `userId` was passed in using the
    // *viewer's* auth email, regardless of whose profile was being
    // looked at. Viewing another user's profile page when they happen
    // to have no row (e.g. a stale/orphaned account) would silently
    // write your own email into a row keyed by their id.
    if (row == null) {
      final currentUid = SupabaseService.currentUserId;
      if (currentUid != null && currentUid == userId) {
        // This upsert can fail for the exact same reason the signup
        // trigger can (see 20260817_fix_signup_trigger_never_blocks_-
        // account_creation.sql) -- an unexpected constraint on a
        // public.users column neither of them knows to set. Previously
        // uncaught here: that exception propagated all the way out of
        // fetchProfile(), the caller's try/catch (ProfileNotifier._load)
        // left profileData null, and profileData?['id'] == currentUid
        // (ProfileState.isOwnProfile) then evaluated to null == uid --
        // false. The profile screen would render as if you were looking
        // at a stranger's empty account (Follow/Message buttons, no
        // name, no photo) instead of your own broken one, which is
        // exactly backwards and very confusing to hit right after
        // registering. Falling through to the stub below on failure at
        // least gets isOwnProfile right; the stub already has id: userId.
        try {
          final authUser = SupabaseService.client.auth.currentUser;
          final email = authUser?.email ?? '';
          final defaultUsername = email.isNotEmpty
              ? email.split('@').first
              : 'user_${userId.substring(0, 8)}';
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
                  'id, username, full_name, avatar_url, bio, church_name, website, is_verified, is_private, created_at')
              .eq('id', userId)
              .maybeSingle();
        } catch (_) {
          // Fall through to the stub below.
        }
      }
      row ??= {
        'id': userId,
        'username': 'unknown',
        'full_name': 'Unknown user',
        'avatar_url': null,
        'bio': null,
        'church_name': null,
        'website': null,
        'is_verified': false,
        'is_private': false,
        'created_at': DateTime.now().toIso8601String(),
      };
    }

    final isPrivate = (row['is_private'] as bool?) ?? false;

    // Followers / following counts — only accepted follows count, so a
    // pile-up of pending requests to a private account doesn't inflate
    // the follower count before they're approved.
    int followerVal = 0;
    int followingVal = 0;
    try {
      final followerRes = await _db
          .from('follows')
          .select()
          .eq('following_id', userId)
          .eq('status', 'accepted')
          .count(CountOption.exact);
      followerVal = followerRes.count;

      final followingRes = await _db
          .from('follows')
          .select()
          .eq('follower_id', userId)
          .eq('status', 'accepted')
          .count(CountOption.exact);
      followingVal = followingRes.count;
    } catch (_) {}

    // Is the current user following this profile — and is it accepted
    // or still a pending request (relevant for private accounts)?
    bool isFollowing = false;
    bool isRequested = false;
    final currentUid = SupabaseService.currentUserId;
    if (currentUid != null && currentUid != userId) {
      try {
        final follow = await _db
            .from('follows')
            .select('status')
            .eq('follower_id', currentUid)
            .eq('following_id', userId)
            .maybeSingle();
        if (follow != null) {
          final status = follow['status'] as String? ?? 'accepted';
          isFollowing = status == 'accepted';
          isRequested = status == 'pending';
        }
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

    final isBlocked = currentUid != null && currentUid != userId
        ? await BlockService.instance.isBlockedEitherWay(userId)
        : false;

    final isOwnProfile = currentUid == userId;
    final canViewPosts = isOwnProfile || !isPrivate || isFollowing;

    return {
      ...Map<String, dynamic>.from(row),
      'follower_count': followerVal,
      'following_count': followingVal,
      'post_count': postCountVal,
      'is_following': isFollowing,
      'is_requested': isRequested,
      'is_blocked': isBlocked,
      'can_view_posts': canViewPosts,
    };
  }

  // ── Posts grid ────────────────────────────────────────────

  Future<List<PostModel>> fetchUserPosts(String userId,
      {int page = 0, int pageSize = 18}) async {
    final range = [page * pageSize, (page + 1) * pageSize - 1];

    if (await BlockService.instance.isBlockedEitherWay(userId)) return [];

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

  /// Toggles the follow relationship. Following a private account inserts
  /// a `pending` row instead of `accepted` — the target has to approve it
  /// from the Follow Requests screen before their content becomes
  /// visible. Unfollowing (or cancelling a pending request) is the same
  /// action either way: delete the row.
  Future<Map<String, bool>> toggleFollow(
    String targetUserId, {
    required bool isCurrentlyFollowing,
    required bool isCurrentlyRequested,
    required bool isTargetPrivate,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null || uid == targetUserId) {
      return {'is_following': isCurrentlyFollowing, 'is_requested': isCurrentlyRequested};
    }

    try {
      if (isCurrentlyFollowing || isCurrentlyRequested) {
        await _db
            .from('follows')
            .delete()
            .eq('follower_id', uid)
            .eq('following_id', targetUserId);
        return {'is_following': false, 'is_requested': false};
      } else {
        final status = isTargetPrivate ? 'pending' : 'accepted';
        await _db.from('follows').upsert({
          'follower_id': uid,
          'following_id': targetUserId,
          'status': status,
        });
        if (status == 'pending') {
          _sendFollowRequestNotification(uid, targetUserId);
        } else {
          _sendFollowNotification(uid, targetUserId);
        }
        return {'is_following': status == 'accepted', 'is_requested': status == 'pending'};
      }
    } catch (_) {
      return {'is_following': isCurrentlyFollowing, 'is_requested': isCurrentlyRequested};
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

  Future<void> _sendFollowRequestNotification(String actorId, String targetId) async {
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
        type: NotificationType.followRequest,
        title: 'Follow request',
        body: '$name wants to follow you',
        actorId: actorId,
      );
    } catch (_) {}
  }

  /// The current user's own accepted followers — used by the story
  /// audience picker ("All Followers Except…" / "Only Share With…").
  Future<List<Map<String, dynamic>>> fetchMyFollowers() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _db
        .from('follows')
        .select('follower_id, follower:users!follower_id(id, username, full_name, avatar_url)')
        .eq('following_id', uid)
        .eq('status', 'accepted')
        .order('created_at', ascending: false) as List;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  // ── Followers / Following lists ───────────────────────────
  //
  // Generic versions of fetchMyFollowers -- that one only ever looks up
  // the CURRENT user's own followers (for the story audience picker);
  // these take any [userId] and back the Followers/Following screen
  // reachable from the post/followers/following counts on a profile.

  /// Accounts that follow [userId] (accepted only), newest first. Each
  /// entry has `is_following` set relative to the CURRENT signed-in
  /// user, so the list screen can offer a Follow/Following action per
  /// row without a separate query per user.
  Future<List<Map<String, dynamic>>> fetchFollowers(String userId,
      {int page = 0, int pageSize = 30}) {
    return _fetchFollowConnections(
      userId: userId,
      filterColumn: 'following_id',
      joinColumn: 'follower_id',
      joinAlias: 'follower',
      page: page,
      pageSize: pageSize,
    );
  }

  /// Accounts [userId] follows (accepted only), newest first.
  Future<List<Map<String, dynamic>>> fetchFollowing(String userId,
      {int page = 0, int pageSize = 30}) {
    return _fetchFollowConnections(
      userId: userId,
      filterColumn: 'follower_id',
      joinColumn: 'following_id',
      joinAlias: 'following',
      page: page,
      pageSize: pageSize,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchFollowConnections({
    required String userId,
    required String filterColumn,
    required String joinColumn,
    required String joinAlias,
    required int page,
    required int pageSize,
  }) async {
    final range = [page * pageSize, (page + 1) * pageSize - 1];

    List<dynamic> rows;
    try {
      rows = await _db
          .from('follows')
          .select('$joinColumn, $joinAlias:users!$joinColumn'
              '(id, username, full_name, avatar_url, is_verified, is_private)')
          .eq(filterColumn, userId)
          .eq('status', 'accepted')
          .order('created_at', ascending: false)
          .range(range[0], range[1]) as List;
    } catch (_) {
      return [];
    }

    var users = rows
        .map((r) => Map<String, dynamic>.from(
            (r as Map)[joinAlias] as Map? ?? {}))
        .where((u) => u['id'] != null)
        .toList();

    final excludedIds =
        (await BlockService.instance.fetchExcludedUserIds()).toSet();
    if (excludedIds.isNotEmpty) {
      users = users.where((u) => !excludedIds.contains(u['id'])).toList();
    }
    if (users.isEmpty) return users;

    // Which of these users does the CURRENT viewer already follow --
    // one batched query for the whole page rather than one per row.
    final currentUid = SupabaseService.currentUserId;
    if (currentUid == null) {
      for (final u in users) {
        u['is_following'] = false;
      }
      return users;
    }
    try {
      final ids = users.map((u) => u['id'] as String).toList();
      final following = await _db
          .from('follows')
          .select('following_id')
          .eq('follower_id', currentUid)
          .eq('status', 'accepted')
          .inFilter('following_id', ids) as List;
      final followingIds =
          following.map((r) => (r as Map)['following_id'] as String).toSet();
      for (final u in users) {
        u['is_following'] = followingIds.contains(u['id']);
      }
    } catch (_) {
      for (final u in users) {
        u['is_following'] = false;
      }
    }
    return users;
  }

  // ── Follow requests (private accounts) ────────────────────

  Future<List<Map<String, dynamic>>> fetchFollowRequests() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _db
        .from('follows')
        .select('follower_id, created_at, follower:users!follower_id(id, username, full_name, avatar_url)')
        .eq('following_id', uid)
        .eq('status', 'pending')
        .order('created_at', ascending: false) as List;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  Future<void> acceptFollowRequest(String followerId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    await _db
        .from('follows')
        .update({'status': 'accepted'})
        .eq('follower_id', followerId)
        .eq('following_id', uid);
  }

  Future<void> rejectFollowRequest(String followerId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    await _db
        .from('follows')
        .delete()
        .eq('follower_id', followerId)
        .eq('following_id', uid);
  }

  /// Removes [followerUserId] as a follower of the current user -- i.e.
  /// the reverse direction from [toggleFollow]. Only meaningful from the
  /// current user's own Followers list (there's no "remove" action on
  /// someone else's followers, or on people *you* follow -- that's just
  /// unfollowing, already covered by toggleFollow). Deletes whatever
  /// status the row is in (accepted, or a still-pending request they
  /// sent you), same as rejectFollowRequest above -- this is really the
  /// same delete, just reachable from the Followers list instead of the
  /// Follow Requests screen.
  Future<void> removeFollower(String followerUserId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    await _db
        .from('follows')
        .delete()
        .eq('follower_id', followerUserId)
        .eq('following_id', uid);
  }

  // ── Account privacy ────────────────────────────────────────

  Future<void> setPrivateAccount(bool isPrivate) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    await _db.from('users').update({'is_private': isPrivate}).eq('id', uid);
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
    final updates = <String, dynamic>{'id': userId};
    if (fullName != null) updates['full_name'] = fullName;
    if (username != null) updates['username'] = username;
    if (bio != null) updates['bio'] = bio;
    if (churchName != null) updates['church_name'] = churchName;
    if (website != null) updates['website'] = website;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (updates.length <= 1) return; // nothing but id -- nothing to save

    // upsert, not update: a plain UPDATE silently matches zero rows (no
    // error at all) for any account whose public.users row never got
    // created by the signup trigger -- exactly the orphaned-account bug
    // fixed by 20260817b_backfill_missing_user_profiles.sql. The edit
    // screen always sends fullName+username together (see _save() in
    // edit_profile_screen.dart), so the NOT NULL columns are always
    // present here even if this ends up being the INSERT branch for an
    // account that still has no row.
    await _db.from('users').upsert(updates);
  }
}

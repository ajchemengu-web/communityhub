import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/models/announcement_model.dart';
import '../domain/models/brand_partnership_model.dart';
import '../domain/models/community_channel_model.dart';
import '../domain/models/community_model.dart';

/// All Supabase interactions for communities, membership, and announcements.
class CommunitiesRepository {
  CommunitiesRepository._();
  static final CommunitiesRepository instance = CommunitiesRepository._();

  final _db = SupabaseService.client;

  // ── Discover communities ───────────────────────────────────

  Future<List<CommunityModel>> fetchDiscover({
    String hubType = 'all',
    String? query,
    int limit = 20,
    int offset = 0,
  }) async {
    final uid = SupabaseService.currentUserId;

    var q = _db.from('communities').select('*');

    if (hubType != 'all') q = q.eq('hub_type', hubType);
    if (query != null && query.isNotEmpty) {
      q = q.ilike('name', '%$query%');
    }

    final rows = await q
        .order('members_count', ascending: false)
        .range(offset, offset + limit - 1) as List<dynamic>;

    // Determine membership for current user in one round-trip
    Set<String> memberIds = {};
    Map<String, String> roleMap = {};
    Map<String, String> statusMap = {};

    if (uid != null && rows.isNotEmpty) {
      final ids = rows.map((r) => r['id'] as String).toList();
      final memberships = await _db
          .from('community_members')
          .select('community_id, role, status')
          .eq('user_id', uid)
          .inFilter('community_id', ids) as List<dynamic>;

      for (final m in memberships) {
        final cid = m['community_id'] as String;
        memberIds.add(cid);
        roleMap[cid] = m['role'] as String;
        statusMap[cid] = m['status'] as String;
      }
    }

    return rows.map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      m['is_member'] = memberIds.contains(m['id'] as String);
      m['user_role'] = roleMap[m['id'] as String];
      m['member_status'] = statusMap[m['id'] as String];
      return CommunityModel.fromMap(m);
    }).toList();
  }

  // ── My communities (joined) ────────────────────────────────

  Future<List<CommunityModel>> fetchMyCommunities({String? hubType}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];

    // Include rows where status = 'approved' OR status is NULL (creator rows
    // where the status column was stripped during self-healing insert).
    List<dynamic> rows = [];
    try {
      rows = await _db
          .from('community_members')
          .select('role, status, communities(*)')
          .eq('user_id', uid)
          .or('status.eq.approved,status.is.null')
          .order('joined_at', ascending: false) as List<dynamic>;
    } catch (_) {
      // Fallback: fetch without status filter (if column missing)
      try {
        rows = await _db
            .from('community_members')
            .select('role, communities(*)')
            .eq('user_id', uid) as List<dynamic>;
      } catch (_) {
        return [];
      }
    }

    return rows.where((r) {
      final c = r['communities'] as Map<String, dynamic>?;
      if (c == null) return false;
      if (hubType != null && hubType != 'all' && c['hub_type'] != hubType) {
        return false;
      }
      return true;
    }).map((r) {
      final c = Map<String, dynamic>.from(r['communities'] as Map);
      c['is_member'] = true;
      c['user_role'] = r['role'] as String? ?? 'member';
      c['member_status'] = r['status'] as String? ?? 'approved';
      return CommunityModel.fromMap(c);
    }).toList();
  }

  // ── Single community ───────────────────────────────────────

  Future<CommunityModel> fetchCommunity(String communityId) async {
    final uid = SupabaseService.currentUserId;

    final row = await _db
        .from('communities')
        .select('*')
        .eq('id', communityId)
        .single() as Map<String, dynamic>;

    final m = Map<String, dynamic>.from(row);

    if (uid != null) {
      try {
        final mem = await _db
            .from('community_members')
            .select('role, status')
            .eq('community_id', communityId)
            .eq('user_id', uid)
            .maybeSingle();
        m['is_member'] = mem != null;
        m['user_role'] = mem?['role'] as String?;
        m['member_status'] = mem?['status'] as String?;
      } catch (_) {
        // Fallback if role/status columns don't exist yet
        try {
          final mem = await _db
              .from('community_members')
              .select('user_id')
              .eq('community_id', communityId)
              .eq('user_id', uid)
              .maybeSingle();
          m['is_member'] = mem != null;
        } catch (_) {}
      }
    }

    return CommunityModel.fromMap(m);
  }

  // ── Join / Leave ───────────────────────────────────────────

  /// Joins a community. Private communities are set to 'pending',
  /// public ones to 'approved' immediately.
  Future<CommunityModel> joinCommunity(CommunityModel community) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final status = community.isPrivate ? 'pending' : 'approved';

    await _db.from('community_members').upsert({
      'community_id': community.id,
      'user_id': uid,
      'role': 'member',
      'status': status,
      'joined_at': community.isPrivate ? null : DateTime.now().toIso8601String(),
    });

    // If approved, increment count
    if (!community.isPrivate) {
      await _db.rpc('increment_community_members', params: {
        'community_id_param': community.id,
      }).catchError((_) async {
        // Fallback: manual increment
        await _db.from('communities').update({
          'members_count': community.membersCount + 1,
        }).eq('id', community.id);
      });
    }

    return community.copyWith(
      isMember: true,
      userRole: 'member',
      memberStatus: status,
      membersCount:
          community.isPrivate ? community.membersCount : community.membersCount + 1,
    );
  }

  Future<CommunityModel> leaveCommunity(CommunityModel community) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    await _db
        .from('community_members')
        .delete()
        .eq('community_id', community.id)
        .eq('user_id', uid);

    // Decrement
    if (community.isApproved) {
      await _db.from('communities').update({
        'members_count': (community.membersCount - 1).clamp(0, 999999),
      }).eq('id', community.id);
    }

    return community.copyWith(
      isMember: false,
      userRole: null,
      memberStatus: null,
      membersCount: community.isApproved
          ? (community.membersCount - 1).clamp(0, 999999)
          : community.membersCount,
    );
  }

  // ── Create community ───────────────────────────────────────

  Future<CommunityModel> createCommunity({
    required String name,
    required String description,
    required String hubType,
    required bool isPrivate,
    File? coverFile,
    String? denomination,
    String? location,
    String? website,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    String? coverUrl;

    // Upload cover image
    if (coverFile != null) {
      try {
        await _db.storage.createBucket(
          'community_covers',
          const BucketOptions(public: true),
        );
      } catch (_) {}
      final ext = coverFile.path.split('.').last;
      final fileName = '${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await coverFile.readAsBytes();
      await _db.storage.from('community_covers').uploadBinary(
            'covers/$fileName',
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );
      coverUrl = _db.storage
          .from('community_covers')
          .getPublicUrl('covers/$fileName');
    }

    // Build insert map — only include columns that exist in the DB.
    // We probe with all fields first; on a schema-cache error we strip
    // optional columns one by one until the insert succeeds.
    final fullPayload = <String, dynamic>{
      'name': name.trim(),
      'description': description.trim(),
      'hub_type': hubType,
      'is_private': isPrivate,
      'cover_url': coverUrl ?? '',
      'creator_id': uid,
      'denomination': denomination,
      'location': location,
      'website': website,
    };

    // Optional columns that may not exist yet in older DB schemas
    final optionalKeys = [
      'creator_id', 'is_private', 'hub_type', 'cover_url',
      'denomination', 'location', 'website',
    ];

    Map<String, dynamic> row;
    Map<String, dynamic> payload = Map.from(fullPayload);
    while (true) {
      try {
        row = await _db
            .from('communities')
            .insert(payload)
            .select('*')
            .single() as Map<String, dynamic>;
        break;
      } catch (e) {
        final msg = e.toString();
        // Find which optional column is causing the schema error and drop it
        final badKey = optionalKeys.firstWhere(
          (k) => msg.contains("'$k'") && payload.containsKey(k),
          orElse: () => '',
        );
        if (badKey.isEmpty) rethrow; // unrelated error — surface it
        payload.remove(badKey);
      }
    }

    // Auto-add creator as admin — strip columns not in schema
    final memberPayload = <String, dynamic>{
      'community_id': row['id'] as String,
      'user_id': uid,
      'role': 'admin',
      'status': 'approved',
      'joined_at': DateTime.now().toIso8601String(),
    };
    final memberOptional = ['status', 'role', 'joined_at'];
    while (true) {
      try {
        await _db.from('community_members').insert(memberPayload);
        break;
      } catch (e) {
        final msg = e.toString();
        final badKey = memberOptional.firstWhere(
          (k) => msg.contains("'$k'") && memberPayload.containsKey(k),
          orElse: () => '',
        );
        if (badKey.isEmpty) rethrow;
        memberPayload.remove(badKey);
      }
    }

    final m = Map<String, dynamic>.from(row);
    m['is_member'] = true;
    m['user_role'] = 'admin';
    m['member_status'] = 'approved';
    final community = CommunityModel.fromMap(m);
    // Seed default channels in the background (no-op if table doesn't exist)
    seedDefaultChannels(community.id);
    return community;
  }

  // ── Members ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchMembers(
    String communityId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final rows = await _db
        .from('community_members')
        .select(
            'role, status, joined_at, users(id, username, full_name, avatar_url, is_verified)')
        .eq('community_id', communityId)
        .eq('status', 'approved')
        .order('joined_at', ascending: false)
        .range(offset, offset + limit - 1) as List<dynamic>;

    return rows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
  }

  // ── Announcements ─────────────────────────────────────────

  Future<List<AnnouncementModel>> fetchAnnouncements(
      String communityId) async {
    final rows = await _db
        .from('announcements')
        .select(
            '*, users:author_id(full_name, username, avatar_url)')
        .eq('community_id', communityId)
        .order('is_pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(50) as List<dynamic>;

    return rows
        .map((r) =>
            AnnouncementModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<AnnouncementModel> postAnnouncement({
    required String communityId,
    required String title,
    required String content,
    bool isPinned = false,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final row = await _db.from('announcements').insert({
      'community_id': communityId,
      'author_id': uid,
      'title': title.trim(),
      'content': content.trim(),
      'is_pinned': isPinned,
    }).select(
            '*, users:author_id(full_name, username, avatar_url)')
        .single() as Map<String, dynamic>;

    return AnnouncementModel.fromMap(row);
  }

  // ── Followed users (for Add Members picker) ───────────────

  Future<List<Map<String, dynamic>>> fetchFollowedUsers() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    try {
      final rows = await _db
          .from('follows')
          .select('users!follows_following_id_fkey(id, username, full_name, avatar_url, is_verified)')
          .eq('follower_id', uid) as List<dynamic>;
      return rows
          .map((r) {
            final u = r['users'] as Map<String, dynamic>? ?? {};
            return Map<String, dynamic>.from(u);
          })
          .where((u) => u.isNotEmpty)
          .toList();
    } catch (_) {
      // Fallback without FK alias
      try {
        final rows = await _db
            .from('follows')
            .select('following_id')
            .eq('follower_id', uid) as List<dynamic>;
        final ids = rows.map((r) => r['following_id'] as String).toList();
        if (ids.isEmpty) return [];
        final users = await _db
            .from('users')
            .select('id, username, full_name, avatar_url, is_verified')
            .inFilter('id', ids) as List<dynamic>;
        return users.map((u) => Map<String, dynamic>.from(u as Map)).toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> addMembers(String communityId, List<String> userIds) async {
    if (userIds.isEmpty) return;
    final rows = userIds
        .map((id) => {
              'community_id': communityId,
              'user_id': id,
              'role': 'member',
              'status': 'approved',
            })
        .toList();
    await _db.from('community_members').upsert(rows, onConflict: 'community_id,user_id');
  }

  // ── Join requests ──────────────────────────────────────────

  Future<void> requestToJoin(String communityId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');
    await _db.from('community_members').upsert({
      'community_id': communityId,
      'user_id': uid,
      'role': 'member',
      'status': 'pending',
    }, onConflict: 'community_id,user_id');
  }

  Future<List<Map<String, dynamic>>> fetchPendingRequests(
      String communityId) async {
    try {
      final rows = await _db
          .from('community_members')
          .select('user_id, joined_at, users(id, username, full_name, avatar_url)')
          .eq('community_id', communityId)
          .eq('status', 'pending')
          .order('joined_at', ascending: true) as List<dynamic>;
      return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> approveRequest(String communityId, String userId) async {
    await _db
        .from('community_members')
        .update({'status': 'approved'})
        .eq('community_id', communityId)
        .eq('user_id', userId);
  }

  Future<void> rejectRequest(String communityId, String userId) async {
    await _db
        .from('community_members')
        .delete()
        .eq('community_id', communityId)
        .eq('user_id', userId);
  }

  // ── Channels (groups) ─────────────────────────────────────

  /// Returns all channels for a community.
  /// Falls back to empty list if the table doesn't exist yet.
  Future<List<CommunityChannelModel>> fetchChannels(
      String communityId) async {
    try {
      final rows = await _db
          .from('community_channels')
          .select('*')
          .eq('community_id', communityId)
          .order('created_at', ascending: true) as List<dynamic>;
      return rows
          .map((r) =>
              CommunityChannelModel.fromMap(Map<String, dynamic>.from(r as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<CommunityChannelModel?> createChannel({
    required String communityId,
    required String name,
    String? description,
    String channelType = 'general',
  }) async {
    final uid = SupabaseService.currentUserId;
    try {
      final row = await _db.from('community_channels').insert({
        'community_id': communityId,
        'name': name.trim(),
        'description': description?.trim(),
        'is_default': false,
        'channel_type': channelType,
        'created_by': uid,
      }).select().single() as Map<String, dynamic>;
      return CommunityChannelModel.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteChannel(String channelId) async {
    try {
      await _db
          .from('community_channels')
          .delete()
          .eq('id', channelId);
    } catch (_) {}
  }

  /// Seeds Announcements + General default channels for a newly created community.
  Future<void> seedDefaultChannels(String communityId) async {
    final uid = SupabaseService.currentUserId;
    try {
      await _db.from('community_channels').upsert([
        {
          'community_id': communityId,
          'name': 'Announcements',
          'channel_type': 'announcements',
          'is_default': true,
          'created_by': uid,
        },
        {
          'community_id': communityId,
          'name': 'General',
          'channel_type': 'general',
          'is_default': true,
          'created_by': uid,
        },
      ], onConflict: 'community_id,name');
    } catch (_) {}
  }

  // ── Community posts ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchCommunityPosts(
      String communityId, {
    int limit = 15,
    DateTime? cursor,
  }) async {
    var q = _db
        .from('posts')
        .select('*, users(username, full_name, avatar_url, is_verified)')
        .eq('community_id', communityId)
        .eq('moderation_status', 'approved');

    if (cursor != null) {
      q = q.lt('created_at', cursor.toIso8601String());
    }

    final rows = await q
        .order('created_at', ascending: false)
        .limit(limit + 1) as List<dynamic>;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  // ── Branded content (disclosed partnerships) ───────────────────
  // v1 is manual: partnerships are created/approved directly in
  // Supabase Studio. This just reads the currently-approved one (if
  // any) so the UI can render a disclosure badge.

  Future<BrandPartnershipModel?> fetchApprovedPartnership(
      String communityId) async {
    final row = await _db
        .from('brand_partnerships')
        .select()
        .eq('community_id', communityId)
        .eq('status', 'approved')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return BrandPartnershipModel.fromMap(row);
  }
}


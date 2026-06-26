import 'dart:io';

import '../../../core/services/supabase_service.dart';
import '../domain/models/announcement_model.dart';
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

    var q = _db
        .from('communities')
        .select('*')
        .order('members_count', ascending: false)
        .range(offset, offset + limit - 1);

    if (hubType != 'all') q = q.eq('hub_type', hubType);
    if (query != null && query.isNotEmpty) {
      q = q.ilike('name', '%$query%');
    }

    final rows = await q as List<dynamic>;

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

    var q = _db
        .from('community_members')
        .select('role, status, communities(*)')
        .eq('user_id', uid)
        .eq('status', 'approved')
        .order('joined_at', ascending: false);

    final rows = await q as List<dynamic>;

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
      c['user_role'] = r['role'] as String;
      c['member_status'] = r['status'] as String;
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
      final mem = await _db
          .from('community_members')
          .select('role, status')
          .eq('community_id', communityId)
          .eq('user_id', uid)
          .maybeSingle();

      m['is_member'] = mem != null;
      m['user_role'] = mem?['role'] as String?;
      m['member_status'] = mem?['status'] as String?;
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

    // Insert community
    final row = await _db.from('communities').insert({
      'name': name.trim(),
      'description': description.trim(),
      'hub_type': hubType,
      'is_private': isPrivate,
      'cover_url': coverUrl ?? '',
      'created_by': uid,
      'denomination': denomination,
      'location': location,
      'website': website,
    }).select('*').single() as Map<String, dynamic>;

    // Auto-add creator as admin
    await _db.from('community_members').insert({
      'community_id': row['id'] as String,
      'user_id': uid,
      'role': 'admin',
      'status': 'approved',
      'joined_at': DateTime.now().toIso8601String(),
    });

    final m = Map<String, dynamic>.from(row);
    m['is_member'] = true;
    m['user_role'] = 'admin';
    m['member_status'] = 'approved';
    return CommunityModel.fromMap(m);
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
        .eq('moderation_status', 'approved')
        .order('created_at', ascending: false)
        .limit(limit + 1);

    if (cursor != null) {
      q = q.lt('created_at', cursor.toIso8601String());
    }

    final rows = await q as List<dynamic>;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }
}

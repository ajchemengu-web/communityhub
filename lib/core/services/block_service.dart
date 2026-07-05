import '../constants/app_constants.dart';
import 'supabase_service.dart';

/// Handles blocking/unblocking and the combined exclusion set used to
/// filter blocked users out of feeds, search, chat, and community posts.
///
/// A block is one-directional in intent (I blocked them) but enforced in
/// both directions in the UI — neither party should see the other's
/// content once either side has blocked. `fetchExcludedUserIds` returns
/// the union of both directions for exactly that reason.
class BlockService {
  BlockService._();
  static final instance = BlockService._();

  final _db = SupabaseService.client;

  Future<void> blockUser(String userId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null || uid == userId) return;
    await _db.from(AppConstants.tableUserBlocks).upsert({
      'blocker_id': uid,
      'blocked_id': userId,
    });
  }

  Future<void> unblockUser(String userId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    await _db
        .from(AppConstants.tableUserBlocks)
        .delete()
        .eq('blocker_id', uid)
        .eq('blocked_id', userId);
  }

  /// Users the current user blocked, with their profile info — for the
  /// "Blocked Accounts" management screen.
  Future<List<Map<String, dynamic>>> fetchBlockedByMe() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _db
        .from(AppConstants.tableUserBlocks)
        .select('blocked_id, created_at, blocked:users!blocked_id(id, username, full_name, avatar_url)')
        .eq('blocker_id', uid)
        .order('created_at', ascending: false) as List;
    return rows.map((r) => Map<String, dynamic>.from(r as Map)).toList();
  }

  /// Combined "I blocked them" + "they blocked me" id set — the filter
  /// every read path in feed/search/chat/communities applies.
  Future<List<String>> fetchExcludedUserIds() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];
    final rows = await _db
        .from(AppConstants.tableUserBlocks)
        .select('blocker_id, blocked_id')
        .or('blocker_id.eq.$uid,blocked_id.eq.$uid') as List;

    return rows
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map((r) => r['blocker_id'] == uid
            ? r['blocked_id'] as String
            : r['blocker_id'] as String)
        .toSet()
        .toList();
  }

  Future<bool> isBlockedEitherWay(String otherUserId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return false;
    final row = await _db
        .from(AppConstants.tableUserBlocks)
        .select()
        .or('and(blocker_id.eq.$uid,blocked_id.eq.$otherUserId),'
            'and(blocker_id.eq.$otherUserId,blocked_id.eq.$uid)')
        .maybeSingle();
    return row != null;
  }
}

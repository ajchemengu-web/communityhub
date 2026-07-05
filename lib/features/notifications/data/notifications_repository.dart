import '../../../core/services/supabase_service.dart';
import '../domain/models/notification_model.dart';

class NotificationsRepository {
  NotificationsRepository._();
  static final instance = NotificationsRepository._();

  final _client = SupabaseService.client;

  static const _select = '''
    id, user_id, type, title, body, data, is_read, created_at, actor_id,
    actor:users!actor_id(full_name, avatar_url)
  ''';

  // ── Fetch ──────────────────────────────────────────────────────

  Future<List<NotificationModel>> fetchNotifications({
    int limit = 50,
    DateTime? cursor,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];

    var query = _client
        .from('notifications')
        .select(_select)
        .eq('user_id', uid);

    if (cursor != null) {
      query = query.lt('created_at', cursor.toIso8601String()) as dynamic;
    }

    final rows = await (query as dynamic)
        .order('created_at', ascending: false)
        .limit(limit) as List;

    return rows
        .map((r) => NotificationModel.fromMap(
            Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ── Unread count ───────────────────────────────────────────────

  Future<int> fetchUnreadCount() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return 0;

    final result = await _client
        .from('notifications')
        .select('id')
        .eq('user_id', uid)
        .eq('is_read', false) as List;

    return result.length;
  }

  // ── Mark single as read ────────────────────────────────────────

  Future<void> markRead(String notificationId) async {
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  // ── Mark all as read ───────────────────────────────────────────

  Future<void> markAllRead() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
  }

  // ── Delete ─────────────────────────────────────────────────────

  Future<void> deleteNotification(String notificationId) async {
    await _client
        .from('notifications')
        .delete()
        .eq('id', notificationId);
  }

  // ── Insert (used by server-side triggers / Edge Functions) ─────
  // This is here for completeness; actual inserts happen via
  // Supabase DB triggers or Edge Functions on the backend.

  Future<void> createNotification({
    required String userId,
    required NotificationType type,
    required String title,
    required String body,
    String? actorId,
    Map<String, dynamic> data = const {},
  }) async {
    await _client.from('notifications').insert({
      'user_id': userId,
      'type': _typeString(type),
      'title': title,
      'body': body,
      'actor_id': actorId,
      'data': data,
      'is_read': false,
    });
  }

  static String _typeString(NotificationType t) {
    switch (t) {
      case NotificationType.message:
        return 'message';
      case NotificationType.prayerRequest:
        return 'prayer_request';
      case NotificationType.postLike:
        return 'post_like';
      case NotificationType.postComment:
        return 'post_comment';
      case NotificationType.follow:
        return 'follow';
      case NotificationType.followRequest:
        return 'follow_request';
      case NotificationType.commentLike:
        return 'comment_like';
      case NotificationType.eventRsvp:
        return 'event_rsvp';
      case NotificationType.communityJoin:
        return 'community_join';
      case NotificationType.missedCall:
        return 'missed_call';
      case NotificationType.general:
        return 'general';
    }
  }
}

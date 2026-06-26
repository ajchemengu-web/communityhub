// ── Notification type ──────────────────────────────────────────────

enum NotificationType {
  message,
  prayerRequest,
  postLike,
  postComment,
  eventRsvp,
  communityJoin,
  missedCall,
  general,
}

// ── NotificationModel ──────────────────────────────────────────────

class NotificationModel {
  const NotificationModel({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.data = const {},
    this.isRead = false,
    this.actorId,
    this.actorName,
    this.actorAvatar,
  });

  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;

  /// Arbitrary payload — e.g. {conversation_id, event_id, post_id}
  final Map<String, dynamic> data;

  final bool isRead;

  /// The user who triggered this notification (sender, liker, etc.)
  final String? actorId;
  final String? actorName;
  final String? actorAvatar;

  // ── Computed ───────────────────────────────────────────────────

  bool get isToday {
    final now = DateTime.now();
    return createdAt.year == now.year &&
        createdAt.month == now.month &&
        createdAt.day == now.day;
  }

  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return createdAt.year == yesterday.year &&
        createdAt.month == yesterday.month &&
        createdAt.day == yesterday.day;
  }

  // ── Factory ────────────────────────────────────────────────────

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    final actor = map['actor'] as Map?;
    return NotificationModel(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      type: _parseType(map['type'] as String? ?? 'general'),
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      createdAt: DateTime.parse(map['created_at'] as String),
      data: map['data'] is Map
          ? Map<String, dynamic>.from(map['data'] as Map)
          : const {},
      isRead: (map['is_read'] as bool?) ?? false,
      actorId: map['actor_id'] as String?,
      actorName: actor?['full_name'] as String?,
      actorAvatar: actor?['avatar_url'] as String?,
    );
  }

  static NotificationType _parseType(String s) {
    switch (s) {
      case 'message':
        return NotificationType.message;
      case 'prayer_request':
        return NotificationType.prayerRequest;
      case 'post_like':
        return NotificationType.postLike;
      case 'post_comment':
        return NotificationType.postComment;
      case 'event_rsvp':
        return NotificationType.eventRsvp;
      case 'community_join':
        return NotificationType.communityJoin;
      case 'missed_call':
        return NotificationType.missedCall;
      default:
        return NotificationType.general;
    }
  }

  NotificationModel copyWith({bool? isRead}) => NotificationModel(
        id: id,
        userId: userId,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        data: data,
        isRead: isRead ?? this.isRead,
        actorId: actorId,
        actorName: actorName,
        actorAvatar: actorAvatar,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is NotificationModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

import 'package:equatable/equatable.dart';

enum ConversationType { direct, group }

class ConversationModel extends Equatable {
  const ConversationModel({
    required this.id,
    required this.type,
    required this.createdAt,
    this.name,
    this.coverUrl,
    this.lastMessage,
    this.lastMessageAt,
    this.lastMessageSenderId,
    this.unreadCount = 0,
    this.participants = const [],
    this.lastReadAt,
    this.isOnline = false,
  });

  final String id;
  final ConversationType type;
  final DateTime createdAt;

  // ── Display ────────────────────────────────────────────────
  /// For direct chats, null — derive from [participants].
  final String? name;
  final String? coverUrl;

  // ── Last message preview ───────────────────────────────────
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final String? lastMessageSenderId;

  // ── Unread ────────────────────────────────────────────────
  final int unreadCount;
  final DateTime? lastReadAt;

  // ── Participants (for DMs: the other user; for groups: all) ─
  final List<ParticipantModel> participants;

  // ── Online status (for DM only) ───────────────────────────
  final bool isOnline;

  bool get isDirect => type == ConversationType.direct;
  bool get isGroup => type == ConversationType.group;
  bool get hasUnread => unreadCount > 0;

  /// Display name: group name or other participant's name
  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    if (participants.isNotEmpty) return participants.first.displayName;
    return 'Unknown';
  }

  /// Avatar for display
  String? get displayAvatar {
    if (coverUrl != null) return coverUrl;
    if (isDirect && participants.isNotEmpty) return participants.first.avatarUrl;
    return null;
  }

  factory ConversationModel.fromMap(
    Map<String, dynamic> map, {
    List<ParticipantModel> participants = const [],
  }) {
    return ConversationModel(
      id: map['id'] as String,
      type: (map['type'] as String?) == 'group'
          ? ConversationType.group
          : ConversationType.direct,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      name: map['name'] as String?,
      coverUrl: map['cover_url'] as String?,
      lastMessage: map['last_message'] as String?,
      lastMessageAt: map['last_message_at'] != null
          ? DateTime.tryParse(map['last_message_at'] as String)
          : null,
      lastMessageSenderId: map['last_message_sender_id'] as String?,
      unreadCount: (map['unread_count'] as int?) ?? 0,
      lastReadAt: map['last_read_at'] != null
          ? DateTime.tryParse(map['last_read_at'] as String)
          : null,
      participants: participants,
    );
  }

  ConversationModel copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    String? lastMessageSenderId,
    int? unreadCount,
    bool? isOnline,
    DateTime? lastReadAt,
    List<ParticipantModel>? participants,
  }) =>
      ConversationModel(
        id: id,
        type: type,
        createdAt: createdAt,
        name: name,
        coverUrl: coverUrl,
        lastMessage: lastMessage ?? this.lastMessage,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        lastMessageSenderId:
            lastMessageSenderId ?? this.lastMessageSenderId,
        unreadCount: unreadCount ?? this.unreadCount,
        lastReadAt: lastReadAt ?? this.lastReadAt,
        participants: participants ?? this.participants,
        isOnline: isOnline ?? this.isOnline,
      );

  @override
  List<Object?> get props =>
      [id, lastMessage, lastMessageAt, unreadCount, isOnline];
}

// ── Participant (denormalised member info) ─────────────────────────

class ParticipantModel extends Equatable {
  const ParticipantModel({
    required this.userId,
    this.fullName,
    this.username,
    this.avatarUrl,
    this.isOnline = false,
  });

  final String userId;
  final String? fullName;
  final String? username;
  final String? avatarUrl;
  final bool isOnline;

  String get displayName =>
      fullName ?? username ?? 'User';

  factory ParticipantModel.fromMap(Map<String, dynamic> map) {
    return ParticipantModel(
      userId: map['user_id'] as String,
      fullName: map['full_name'] as String?,
      username: map['username'] as String?,
      avatarUrl: map['avatar_url'] as String?,
    );
  }

  @override
  List<Object?> get props => [userId, isOnline];
}

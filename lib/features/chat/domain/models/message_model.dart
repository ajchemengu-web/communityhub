import 'package:equatable/equatable.dart';

enum MessageType { text, image, video, audio, callLog, deleted }

enum MessageStatus { sending, sent, delivered, read, failed }

class MessageModel extends Equatable {
  const MessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
    this.content,
    this.type = MessageType.text,
    this.mediaUrl,
    this.mediaThumbnailUrl,
    this.replyToId,
    this.replyTo,
    this.reactions = const {},
    this.isDeleted = false,
    this.status = MessageStatus.sent,
    this.senderName,
    this.senderAvatar,
    // Call-log extras
    this.callType,
    this.callDuration,
    this.callStatus,
    this.isCurrentUser = false,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final DateTime createdAt;

  // ── Content ───────────────────────────────────────────────
  final String? content;
  final MessageType type;
  final String? mediaUrl;
  final String? mediaThumbnailUrl;

  // ── Reply ─────────────────────────────────────────────────
  final String? replyToId;
  final ReplyPreview? replyTo;

  // ── Reactions: emoji → [userId, ...] ──────────────────────
  final Map<String, List<String>> reactions;

  // ── Status ────────────────────────────────────────────────
  final bool isDeleted;
  final MessageStatus status;

  // ── Sender display ────────────────────────────────────────
  final String? senderName;
  final String? senderAvatar;

  // ── Call log ──────────────────────────────────────────────
  final String? callType;    // 'audio' | 'video'
  final int? callDuration;   // seconds
  final String? callStatus;  // 'ended' | 'missed' | 'declined'

  // ── Convenience ───────────────────────────────────────────
  final bool isCurrentUser;

  String get displayText {
    if (isDeleted) return 'This message was deleted';
    switch (type) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.audio:
        return '🎙 Voice message';
      case MessageType.callLog:
        final icon = callType == 'video' ? '📹' : '📞';
        return '$icon ${callStatus == 'missed' ? 'Missed call' : 'Call ended'}';
      default:
        return content ?? '';
    }
  }

  factory MessageModel.fromMap(
    Map<String, dynamic> map, {
    required String currentUserId,
  }) {
    final typeStr = map['type'] as String? ?? 'text';
    final msgType = _parseType(typeStr);

    Map<String, List<String>> reactions = {};
    final rawReactions = map['reactions'];
    if (rawReactions is Map) {
      reactions = rawReactions.map(
        (k, v) => MapEntry(
          k as String,
          (v as List).map((e) => e as String).toList(),
        ),
      );
    }

    ReplyPreview? replyTo;
    if (map['reply_to'] is Map) {
      replyTo = ReplyPreview.fromMap(
          map['reply_to'] as Map<String, dynamic>);
    }

    final profile = map['users'] as Map<String, dynamic>?;

    return MessageModel(
      id: map['id'] as String,
      conversationId: map['conversation_id'] as String,
      senderId: map['sender_id'] as String,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      content: map['content'] as String?,
      type: msgType,
      mediaUrl: map['media_url'] as String?,
      mediaThumbnailUrl: map['media_thumbnail_url'] as String?,
      replyToId: map['reply_to_id'] as String?,
      replyTo: replyTo,
      reactions: reactions,
      isDeleted: (map['is_deleted'] as bool?) ?? false,
      status: MessageStatus.sent,
      senderName: profile?['full_name'] as String? ??
          profile?['username'] as String?,
      senderAvatar: profile?['avatar_url'] as String?,
      callType: map['call_type'] as String?,
      callDuration: map['call_duration'] as int?,
      callStatus: map['call_status'] as String?,
      isCurrentUser: map['sender_id'] as String == currentUserId,
    );
  }

  static MessageType _parseType(String s) {
    switch (s) {
      case 'image':
        return MessageType.image;
      case 'video':
        return MessageType.video;
      case 'audio':
        return MessageType.audio;
      case 'call_log':
        return MessageType.callLog;
      default:
        return MessageType.text;
    }
  }

  MessageModel copyWith({
    MessageStatus? status,
    Map<String, List<String>>? reactions,
    bool? isDeleted,
  }) =>
      MessageModel(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        createdAt: createdAt,
        content: content,
        type: type,
        mediaUrl: mediaUrl,
        mediaThumbnailUrl: mediaThumbnailUrl,
        replyToId: replyToId,
        replyTo: replyTo,
        reactions: reactions ?? this.reactions,
        isDeleted: isDeleted ?? this.isDeleted,
        status: status ?? this.status,
        senderName: senderName,
        senderAvatar: senderAvatar,
        callType: callType,
        callDuration: callDuration,
        callStatus: callStatus,
        isCurrentUser: isCurrentUser,
      );

  @override
  List<Object?> get props => [id, reactions, isDeleted, status];
}

// ── Reply preview (denormalised) ───────────────────────────────────

class ReplyPreview extends Equatable {
  const ReplyPreview({
    required this.id,
    required this.senderId,
    this.senderName,
    this.content,
    this.type = MessageType.text,
  });

  final String id;
  final String senderId;
  final String? senderName;
  final String? content;
  final MessageType type;

  factory ReplyPreview.fromMap(Map<String, dynamic> map) {
    return ReplyPreview(
      id: map['id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String?,
      content: map['content'] as String?,
      type: MessageModel._parseType(map['type'] as String? ?? 'text'),
    );
  }

  @override
  List<Object?> get props => [id];
}

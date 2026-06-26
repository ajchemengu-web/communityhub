import 'package:equatable/equatable.dart';

enum CallType { audio, video }

enum CallStatus { ringing, active, ended, missed, declined }

class CallModel extends Equatable {
  const CallModel({
    required this.id,
    required this.callerId,
    required this.conversationId,
    required this.type,
    required this.status,
    required this.createdAt,
    this.channelName,
    this.callerName,
    this.callerAvatar,
    this.receiverId,
    this.receiverName,
    this.receiverAvatar,
    this.startedAt,
    this.endedAt,
  });

  final String id;
  final String callerId;
  final String conversationId;
  final CallType type;
  final CallStatus status;
  final DateTime createdAt;

  /// Agora / WebRTC channel name
  final String? channelName;

  // ── Caller info ───────────────────────────────────────────
  final String? callerName;
  final String? callerAvatar;

  // ── Receiver (for direct calls) ───────────────────────────
  final String? receiverId;
  final String? receiverName;
  final String? receiverAvatar;

  // ── Timing ────────────────────────────────────────────────
  final DateTime? startedAt;
  final DateTime? endedAt;

  /// Duration in seconds (null while active)
  int? get duration {
    if (startedAt == null || endedAt == null) return null;
    return endedAt!.difference(startedAt!).inSeconds;
  }

  bool get isAudio => type == CallType.audio;
  bool get isVideo => type == CallType.video;
  bool get isRinging => status == CallStatus.ringing;
  bool get isActive => status == CallStatus.active;
  bool get isEnded => status == CallStatus.ended;
  bool get isMissed => status == CallStatus.missed;
  bool get isDeclined => status == CallStatus.declined;

  factory CallModel.fromMap(Map<String, dynamic> map) {
    final caller = map['caller'] as Map<String, dynamic>?;
    final receiver = map['receiver'] as Map<String, dynamic>?;

    return CallModel(
      id: map['id'] as String,
      callerId: map['caller_id'] as String,
      conversationId: map['conversation_id'] as String,
      type: (map['type'] as String?) == 'video'
          ? CallType.video
          : CallType.audio,
      status: _parseStatus(map['status'] as String? ?? 'ringing'),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      channelName: map['channel_name'] as String?,
      callerName: caller?['full_name'] as String?,
      callerAvatar: caller?['avatar_url'] as String?,
      receiverId: map['receiver_id'] as String?,
      receiverName: receiver?['full_name'] as String?,
      receiverAvatar: receiver?['avatar_url'] as String?,
      startedAt: map['started_at'] != null
          ? DateTime.tryParse(map['started_at'] as String)
          : null,
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)
          : null,
    );
  }

  static CallStatus _parseStatus(String s) {
    switch (s) {
      case 'active':
        return CallStatus.active;
      case 'ended':
        return CallStatus.ended;
      case 'missed':
        return CallStatus.missed;
      case 'declined':
        return CallStatus.declined;
      default:
        return CallStatus.ringing;
    }
  }

  CallModel copyWith({CallStatus? status, DateTime? startedAt, DateTime? endedAt}) =>
      CallModel(
        id: id,
        callerId: callerId,
        conversationId: conversationId,
        type: type,
        status: status ?? this.status,
        createdAt: createdAt,
        channelName: channelName,
        callerName: callerName,
        callerAvatar: callerAvatar,
        receiverId: receiverId,
        receiverName: receiverName,
        receiverAvatar: receiverAvatar,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
      );

  @override
  List<Object?> get props => [id, status];
}

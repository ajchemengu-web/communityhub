class LiveStreamModel {
  const LiveStreamModel({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.channelName,
    required this.title,
    required this.startedAt,
    this.hostAvatar,
    this.hubType,
    this.viewerCount = 0,
    this.isActive = true,
    this.endedAt,
  });

  final String id;
  final String hostId;
  final String hostName;
  final String? hostAvatar;
  final String channelName;
  final String title;
  final String? hubType;
  final int viewerCount;
  final bool isActive;
  final DateTime startedAt;
  final DateTime? endedAt;

  factory LiveStreamModel.fromMap(Map<String, dynamic> map) {
    final host = map['host'] as Map?;
    return LiveStreamModel(
      id: map['id'] as String,
      hostId: map['host_id'] as String,
      hostName: host?['full_name'] as String? ?? 'Unknown',
      hostAvatar: host?['avatar_url'] as String?,
      channelName: map['channel_name'] as String,
      title: map['title'] as String? ?? 'Live',
      hubType: map['hub_type'] as String?,
      viewerCount: (map['viewer_count'] as int?) ?? 0,
      isActive: (map['is_active'] as bool?) ?? true,
      startedAt: DateTime.parse(map['started_at'] as String),
      endedAt: map['ended_at'] != null
          ? DateTime.tryParse(map['ended_at'] as String)
          : null,
    );
  }

  LiveStreamModel copyWith({int? viewerCount, bool? isActive}) =>
      LiveStreamModel(
        id: id,
        hostId: hostId,
        hostName: hostName,
        hostAvatar: hostAvatar,
        channelName: channelName,
        title: title,
        hubType: hubType,
        viewerCount: viewerCount ?? this.viewerCount,
        isActive: isActive ?? this.isActive,
        startedAt: startedAt,
        endedAt: endedAt,
      );
}

class LiveCommentModel {
  const LiveCommentModel({
    required this.id,
    required this.streamId,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
    this.userAvatar,
  });

  final String id;
  final String streamId;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String content;
  final DateTime createdAt;

  factory LiveCommentModel.fromMap(Map<String, dynamic> map) {
    final user = map['user'] as Map?;
    return LiveCommentModel(
      id: map['id'] as String,
      streamId: map['stream_id'] as String,
      userId: map['user_id'] as String,
      userName: user?['full_name'] as String? ?? 'User',
      userAvatar: user?['avatar_url'] as String?,
      content: map['content'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

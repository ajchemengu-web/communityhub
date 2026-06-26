import 'package:equatable/equatable.dart';

class AnnouncementModel extends Equatable {
  const AnnouncementModel({
    required this.id,
    required this.communityId,
    required this.authorId,
    required this.title,
    required this.content,
    required this.createdAt,
    this.mediaUrl,
    this.isPinned = false,
    this.authorName,
    this.authorAvatar,
  });

  final String id;
  final String communityId;
  final String authorId;
  final String title;
  final String content;
  final DateTime createdAt;
  final String? mediaUrl;
  final bool isPinned;
  final String? authorName;
  final String? authorAvatar;

  factory AnnouncementModel.fromMap(Map<String, dynamic> map) {
    final author = map['users'] as Map<String, dynamic>?;
    return AnnouncementModel(
      id: map['id'] as String,
      communityId: map['community_id'] as String,
      authorId: map['author_id'] as String,
      title: map['title'] as String,
      content: map['content'] as String,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      mediaUrl: map['media_url'] as String?,
      isPinned: (map['is_pinned'] as bool?) ?? false,
      authorName: author?['full_name'] as String? ??
          author?['username'] as String?,
      authorAvatar: author?['avatar_url'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, isPinned];
}

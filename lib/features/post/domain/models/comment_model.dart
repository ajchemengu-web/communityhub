import 'package:equatable/equatable.dart';

class CommentModel extends Equatable {
  const CommentModel({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.likesCount,
    required this.createdAt,
    this.parentCommentId,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.isVerified = false,
    this.isLikedByCurrentUser = false,
    this.replies = const [],
  });

  final String id;
  final String postId;
  final String userId;
  final String content;
  final int likesCount;
  final DateTime createdAt;
  final String? parentCommentId;
  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final bool isVerified;
  final bool isLikedByCurrentUser;
  final List<CommentModel> replies;

  String get displayName => fullName ?? username ?? 'User';

  factory CommentModel.fromMap(Map<String, dynamic> map) {
    final user = map['users'] as Map<String, dynamic>?;
    return CommentModel(
      id: map['id'] as String,
      postId: map['post_id'] as String,
      userId: map['user_id'] as String,
      content: map['content'] as String,
      likesCount: (map['likes_count'] as int?) ?? 0,
      createdAt: DateTime.parse(map['created_at'] as String),
      parentCommentId: map['parent_comment_id'] as String?,
      username: user?['username'] as String?,
      fullName: user?['full_name'] as String?,
      avatarUrl: user?['avatar_url'] as String?,
      isVerified: (user?['is_verified'] as bool?) ?? false,
      isLikedByCurrentUser: (map['is_liked'] as bool?) ?? false,
    );
  }

  CommentModel copyWith({
    int? likesCount,
    bool? isLikedByCurrentUser,
    List<CommentModel>? replies,
  }) =>
      CommentModel(
        id: id,
        postId: postId,
        userId: userId,
        content: content,
        likesCount: likesCount ?? this.likesCount,
        createdAt: createdAt,
        parentCommentId: parentCommentId,
        username: username,
        fullName: fullName,
        avatarUrl: avatarUrl,
        isVerified: isVerified,
        isLikedByCurrentUser:
            isLikedByCurrentUser ?? this.isLikedByCurrentUser,
        replies: replies ?? this.replies,
      );

  @override
  List<Object?> get props => [id, likesCount, isLikedByCurrentUser, replies];
}

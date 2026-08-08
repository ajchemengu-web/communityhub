import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../home/domain/models/post_model.dart';
import '../../data/post_repository.dart';
import '../../domain/models/comment_model.dart';

// ── Post Detail State ──────────────────────────────────────────

class PostDetailState {
  const PostDetailState({
    this.post,
    this.comments = const [],
    this.isLoading = true,
    this.isSubmittingComment = false,
    this.replyingTo,
    this.errorMessage,
  });

  final PostModel? post;
  final List<CommentModel> comments;
  final bool isLoading;
  final bool isSubmittingComment;
  final CommentModel? replyingTo;
  final String? errorMessage;

  PostDetailState copyWith({
    PostModel? post,
    List<CommentModel>? comments,
    bool? isLoading,
    bool? isSubmittingComment,
    CommentModel? replyingTo,
    bool clearReply = false,
    String? errorMessage,
  }) =>
      PostDetailState(
        post: post ?? this.post,
        comments: comments ?? this.comments,
        isLoading: isLoading ?? this.isLoading,
        isSubmittingComment:
            isSubmittingComment ?? this.isSubmittingComment,
        replyingTo: clearReply ? null : (replyingTo ?? this.replyingTo),
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class PostDetailNotifier extends StateNotifier<PostDetailState> {
  PostDetailNotifier(this.postId) : super(const PostDetailState()) {
    _load();
  }

  final String postId;
  final _repo = PostRepository.instance;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.fetchPost(postId),
        _repo.fetchComments(postId),
      ]);

      final postMap = results[0] as Map<String, dynamic>;
      final comments = results[1] as List<CommentModel>;

      state = state.copyWith(
        post: PostModel.fromMap(postMap),
        comments: comments,
        isLoading: false,
      );

      _subscribeToComments();
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  void _subscribeToComments() {
    _channel = SupabaseService.client.channel('comments:$postId');
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'comments',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'post_id',
        value: postId,
      ),
      callback: (_) async {
        // Refresh comments on any new insert
        try {
          final updated = await _repo.fetchComments(postId);
          state = state.copyWith(comments: updated);
        } catch (_) {}
      },
    );
    _channel!.subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────

  Future<void> toggleLike() async {
    final p = state.post;
    if (p == null) return;
    final wasLiked = p.isLikedByCurrentUser;

    // Optimistic
    state = state.copyWith(
      post: p.copyWith(
        isLikedByCurrentUser: !wasLiked,
        likesCount:
            wasLiked ? (p.likesCount - 1).clamp(0, 999999) : p.likesCount + 1,
      ),
    );

    try {
      final uid = SupabaseService.currentUserId;
      if (uid == null) return;
      if (wasLiked) {
        await SupabaseService.client
            .from('likes')
            .delete()
            .eq('target_id', postId)
            .eq('target_type', 'post')
            .eq('user_id', uid);
      } else {
        await SupabaseService.client.from('likes').upsert({
          'target_id': postId,
          'target_type': 'post',
          'user_id': uid,
        }, onConflict: 'user_id,target_id,target_type');
      }
    } catch (_) {
      // revert
      state = state.copyWith(post: p);
    }
  }

  Future<void> toggleBookmark() async {
    final p = state.post;
    if (p == null) return;
    final wasBookmarked = p.isBookmarkedByCurrentUser;

    state = state.copyWith(
      post: p.copyWith(isBookmarkedByCurrentUser: !wasBookmarked),
    );

    final result = await _repo.toggleBookmark(postId,
        isCurrentlyBookmarked: wasBookmarked);
    state = state.copyWith(
      post: state.post?.copyWith(isBookmarkedByCurrentUser: result),
    );
  }

  void setReplyingTo(CommentModel? comment) {
    state = comment == null
        ? state.copyWith(clearReply: true)
        : state.copyWith(replyingTo: comment);
  }

  Future<void> addComment(String content) async {
    if (content.trim().isEmpty) return;
    state = state.copyWith(isSubmittingComment: true);

    try {
      await _repo.addComment(
        postId: postId,
        content: content,
        parentCommentId: state.replyingTo?.id,
      );

      // Increment comment count on the post
      final p = state.post;
      if (p != null) {
        state = state.copyWith(
          post: p.copyWith(commentsCount: p.commentsCount + 1),
          clearReply: true,
          isSubmittingComment: false,
        );
      } else {
        state = state.copyWith(
          clearReply: true,
          isSubmittingComment: false,
        );
      }
      // Realtime will refresh comments list
    } catch (e) {
      state = state.copyWith(
        isSubmittingComment: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> toggleCommentLike(CommentModel comment) async {
    final wasLiked = comment.isLikedByCurrentUser;

    // Optimistic: update in list
    final updated = _updateCommentInList(
      state.comments,
      comment.id,
      comment.copyWith(
        isLikedByCurrentUser: !wasLiked,
        likesCount: wasLiked
            ? (comment.likesCount - 1).clamp(0, 999999)
            : comment.likesCount + 1,
      ),
    );
    state = state.copyWith(comments: updated);

    await _repo.toggleCommentLike(comment.id,
        isCurrentlyLiked: wasLiked);
  }

  Future<void> deleteComment(String commentId) async {
    await _repo.deleteComment(commentId);
    final updated = _removeCommentFromList(state.comments, commentId);
    final p = state.post;
    state = state.copyWith(
      comments: updated,
      post: p?.copyWith(
          commentsCount: (p.commentsCount - 1).clamp(0, 999999)),
    );
  }

  // ── List helpers ──────────────────────────────────────────

  List<CommentModel> _updateCommentInList(
    List<CommentModel> list,
    String id,
    CommentModel updated,
  ) {
    return list.map((c) {
      if (c.id == id) return updated;
      if (c.replies.any((r) => r.id == id)) {
        return c.copyWith(
          replies: c.replies.map((r) => r.id == id ? updated : r).toList(),
        );
      }
      return c;
    }).toList();
  }

  List<CommentModel> _removeCommentFromList(
      List<CommentModel> list, String id) {
    return list
        .where((c) => c.id != id)
        .map((c) => c.copyWith(
              replies: c.replies.where((r) => r.id != id).toList(),
            ))
        .toList();
  }
}

// ── Provider ───────────────────────────────────────────────────

final postDetailProvider = StateNotifierProvider.autoDispose
    .family<PostDetailNotifier, PostDetailState, String>(
  (_, postId) => PostDetailNotifier(postId),
);

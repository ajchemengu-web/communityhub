import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../home/domain/models/post_model.dart';
import '../../domain/models/comment_model.dart';
import '../providers/post_detail_provider.dart';

// ─────────────────────────────────────────────────────────────────
// Sort enum
// ─────────────────────────────────────────────────────────────────

enum _CommentSort { newest, oldest, topLiked }

extension on _CommentSort {
  String get label {
    switch (this) {
      case _CommentSort.newest:
        return 'Newest';
      case _CommentSort.oldest:
        return 'Oldest';
      case _CommentSort.topLiked:
        return 'Top';
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Post Detail Screen
// ─────────────────────────────────────────────────────────────────

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  _CommentSort _sort = _CommentSort.newest;

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<CommentModel> _sorted(List<CommentModel> comments) {
    final list = List<CommentModel>.from(comments);
    switch (_sort) {
      case _CommentSort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _CommentSort.oldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _CommentSort.topLiked:
        list.sort((a, b) => b.likesCount.compareTo(a.likesCount));
    }
    return list;
  }

  void _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    _commentCtrl.clear();
    _focusNode.unfocus();
    await ref.read(postDetailProvider(widget.postId).notifier).addComment(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(postDetailProvider(widget.postId));
    final currentUid = SupabaseService.currentUserId;
    final sorted = _sorted(state.comments);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('Post', style: AppTextStyles.titleSmall),
        actions: [
          if (state.post != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              onPressed: () => Share.share(
                'Check out this post on CommunityHub!\n${state.post!.caption}',
              ),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.post == null
              ? Center(
                  child: Text('Post not found',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textMuted)),
                )
              : Column(
                  children: [
                    // ── Scrollable content ─────────────────
                    Expanded(
                      child: CustomScrollView(
                        controller: _scrollCtrl,
                        slivers: [
                          // Post card
                          SliverToBoxAdapter(
                            child: _PostBody(
                              post: state.post!,
                              onLike: () => ref
                                  .read(postDetailProvider(widget.postId)
                                      .notifier)
                                  .toggleLike(),
                              onBookmark: () => ref
                                  .read(postDetailProvider(widget.postId)
                                      .notifier)
                                  .toggleBookmark(),
                              onCommentTap: () => _focusNode.requestFocus(),
                            ),
                          ),

                          // Comments header + sort
                          SliverToBoxAdapter(
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 12, 4),
                              child: Row(
                                children: [
                                  Text('Comments',
                                      style: AppTextStyles.titleSmall
                                          .copyWith(color: Colors.white)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${state.comments.length}',
                                      style: AppTextStyles.labelSmall
                                          .copyWith(
                                              color: AppColors.primary),
                                    ),
                                  ),
                                  const Spacer(),
                                  // Sort picker
                                  PopupMenuButton<_CommentSort>(
                                    initialValue: _sort,
                                    onSelected: (s) =>
                                        setState(() => _sort = s),
                                    color: AppColors.darkSurface,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(_sort.label,
                                            style: AppTextStyles.labelSmall
                                                .copyWith(
                                                    color:
                                                        AppColors.primary)),
                                        const Icon(Icons.arrow_drop_down,
                                            color: AppColors.primary,
                                            size: 18),
                                      ],
                                    ),
                                    itemBuilder: (_) =>
                                        _CommentSort.values
                                            .map((s) => PopupMenuItem(
                                                  value: s,
                                                  child: Text(s.label,
                                                      style: AppTextStyles
                                                          .bodySmall
                                                          .copyWith(
                                                              color: Colors
                                                                  .white)),
                                                ))
                                            .toList(),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Comments list
                          sorted.isEmpty
                              ? SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 48),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          const Icon(
                                              Icons.chat_bubble_outline,
                                              size: 48,
                                              color: AppColors.textMuted),
                                          const SizedBox(height: 12),
                                          Text('Be the first to comment!',
                                              style: AppTextStyles.bodyMedium
                                                  .copyWith(
                                                      color: AppColors
                                                          .textMuted)),
                                          const SizedBox(height: 6),
                                          GestureDetector(
                                            onTap: () =>
                                                _focusNode.requestFocus(),
                                            child: Text('Write a comment',
                                                style: AppTextStyles
                                                    .labelMedium
                                                    .copyWith(
                                                        color: AppColors
                                                            .primary)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : SliverList.builder(
                                  itemCount: sorted.length,
                                  itemBuilder: (_, i) {
                                    final comment = sorted[i];
                                    return _CommentTile(
                                      comment: comment,
                                      currentUid: currentUid,
                                      onLike: () => ref
                                          .read(postDetailProvider(
                                                  widget.postId)
                                              .notifier)
                                          .toggleCommentLike(comment),
                                      onReply: () {
                                        ref
                                            .read(postDetailProvider(
                                                    widget.postId)
                                                .notifier)
                                            .setReplyingTo(comment);
                                        _focusNode.requestFocus();
                                      },
                                      onDelete:
                                          currentUid == comment.userId
                                              ? () => _confirmDelete(
                                                  context, comment.id)
                                              : null,
                                      onReplyLike: (reply) => ref
                                          .read(postDetailProvider(
                                                  widget.postId)
                                              .notifier)
                                          .toggleCommentLike(reply),
                                      onReplyDelete: (reply) =>
                                          currentUid == reply.userId
                                              ? _confirmDelete(
                                                  context, reply.id)
                                              : null,
                                      onReplyReply: (reply) {
                                        ref
                                            .read(postDetailProvider(
                                                    widget.postId)
                                                .notifier)
                                            .setReplyingTo(comment);
                                        _commentCtrl.text =
                                            '@${reply.username ?? reply.displayName} ';
                                        _focusNode.requestFocus();
                                      },
                                    );
                                  },
                                ),

                          const SliverToBoxAdapter(
                              child: SizedBox(height: 16)),
                        ],
                      ),
                    ),

                    // ── Reply banner above input ───────────
                    if (state.replyingTo != null)
                      _ReplyBanner(
                        comment: state.replyingTo!,
                        onCancel: () {
                          ref
                              .read(postDetailProvider(widget.postId)
                                  .notifier)
                              .setReplyingTo(null);
                          _commentCtrl.clear();
                        },
                      ),

                    // ── Comment input ──────────────────────
                    _CommentInput(
                      controller: _commentCtrl,
                      focusNode: _focusNode,
                      isSubmitting: state.isSubmittingComment,
                      isReplying: state.replyingTo != null,
                      onSubmit: _submitComment,
                    ),
                  ],
                ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String commentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Delete comment?',
            style: TextStyle(color: Colors.white)),
        content: const Text('This cannot be undone.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      ref
          .read(postDetailProvider(widget.postId).notifier)
          .deleteComment(commentId);
    }
  }
}

// ─────────────────────────────────────────────────────────────────
// Post Body
// ─────────────────────────────────────────────────────────────────

class _PostBody extends StatelessWidget {
  const _PostBody({
    required this.post,
    required this.onLike,
    required this.onBookmark,
    required this.onCommentTap,
  });

  final PostModel post;
  final VoidCallback onLike;
  final VoidCallback onBookmark;
  final VoidCallback onCommentTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Author
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: post.avatarUrl != null
                    ? CachedNetworkImageProvider(post.avatarUrl!)
                    : null,
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: post.avatarUrl == null
                    ? const Icon(Icons.person, color: AppColors.primary)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(post.displayName,
                            style: AppTextStyles.bodyMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                        if (post.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              size: 14, color: AppColors.primary),
                        ],
                      ],
                    ),
                    Text(timeago.format(post.createdAt),
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textMuted)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(post.hubType,
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),
        ),

        // Caption
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(post.caption,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: Colors.white, height: 1.5)),
        ),

        // Tags
        if (post.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              children: post.tags
                  .map((t) => Text('#$t',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.primary)))
                  .toList(),
            ),
          ),
        ],

        // Attached audio track
        if (post.hasAudioTrack) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.music_note_rounded,
                    size: 15, color: Colors.white54),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${post.audioTitle ?? ''}${post.audioArtist != null ? ' · ${post.audioArtist}' : ''}',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: Colors.white54),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],

        // Media
        if (post.mediaUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MediaCarousel(urls: post.mediaUrls),
        ],

        const SizedBox(height: 12),

        // Action bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _ActionBtn(
                icon: post.isLikedByCurrentUser
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: '${post.likesCount}',
                color: post.isLikedByCurrentUser
                    ? AppColors.error
                    : AppColors.textMuted,
                onTap: onLike,
              ),
              _ActionBtn(
                icon: Icons.chat_bubble_outline_rounded,
                label: '${post.commentsCount}',
                onTap: onCommentTap,
              ),
              _ActionBtn(
                icon: Icons.share_outlined,
                label: 'Share',
                onTap: () => Share.share(post.caption),
              ),
              const Spacer(),
              _ActionBtn(
                icon: post.isBookmarkedByCurrentUser
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                label: '',
                color: post.isBookmarkedByCurrentUser
                    ? AppColors.secondary
                    : AppColors.textMuted,
                onTap: onBookmark,
              ),
            ],
          ),
        ),

        const Divider(color: AppColors.darkDivider, height: 24),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.textMuted,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            if (label.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(label,
                  style: AppTextStyles.labelSmall.copyWith(color: color)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MediaCarousel extends StatefulWidget {
  const _MediaCarousel({required this.urls});
  final List<String> urls;

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  int _current = 0;
  late final PageController _pc;

  @override
  void initState() {
    super.initState();
    _pc = PageController();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: _pc,
            onPageChanged: (i) => setState(() => _current = i),
            itemCount: widget.urls.length,
            itemBuilder: (_, i) => CachedNetworkImage(
              imageUrl: widget.urls[i],
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                color: AppColors.darkSurface,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, __, ___) => Container(
                color: AppColors.darkSurface,
                child: const Icon(Icons.broken_image_outlined,
                    color: AppColors.textMuted),
              ),
            ),
          ),
        ),
        if (widget.urls.length > 1)
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                widget.urls.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: i == _current ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i == _current ? AppColors.primary : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Comment Tile  (fixed: each reply has its own like/delete handler)
// ─────────────────────────────────────────────────────────────────

class _CommentTile extends StatefulWidget {
  const _CommentTile({
    required this.comment,
    required this.currentUid,
    required this.onLike,
    required this.onReply,
    required this.onReplyLike,
    required this.onReplyReply,
    this.onDelete,
    this.onReplyDelete,
    this.isReply = false,
  });

  final CommentModel comment;
  final String? currentUid;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final void Function(CommentModel reply) onReplyLike;
  final void Function(CommentModel reply) onReplyReply;
  final VoidCallback? onDelete;
  final void Function(CommentModel reply)? onReplyDelete;
  final bool isReply;

  @override
  State<_CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends State<_CommentTile> {
  bool _showReplies = false;

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final hasReplies = comment.replies.isNotEmpty;

    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: Padding(
        padding: EdgeInsets.only(
          left: widget.isReply ? 56 : 12,
          right: 12,
          top: 8,
          bottom: 2,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            CircleAvatar(
              radius: widget.isReply ? 13 : 17,
              backgroundImage: comment.avatarUrl != null
                  ? CachedNetworkImageProvider(comment.avatarUrl!)
                  : null,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: comment.avatarUrl == null
                  ? Icon(Icons.person,
                      color: AppColors.primary,
                      size: widget.isReply ? 11 : 15)
                  : null,
            ),
            const SizedBox(width: 8),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Bubble
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.darkSurface,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Username + verified
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                comment.displayName,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (comment.isVerified) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.verified,
                                  size: 12, color: AppColors.primary),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Content
                        Text(
                          comment.content,
                          style: AppTextStyles.bodySmall
                              .copyWith(color: Colors.white, height: 1.4),
                        ),
                      ],
                    ),
                  ),

                  // Actions row
                  Padding(
                    padding: const EdgeInsets.only(left: 6, top: 5, bottom: 2),
                    child: Row(
                      children: [
                        // Time
                        Text(
                          timeago.format(comment.createdAt),
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textMuted),
                        ),
                        const SizedBox(width: 14),
                        // Like
                        GestureDetector(
                          onTap: widget.onLike,
                          child: Row(
                            children: [
                              Icon(
                                comment.isLikedByCurrentUser
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 13,
                                color: comment.isLikedByCurrentUser
                                    ? AppColors.error
                                    : AppColors.textMuted,
                              ),
                              if (comment.likesCount > 0) ...[
                                const SizedBox(width: 3),
                                Text(
                                  '${comment.likesCount}',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: comment.isLikedByCurrentUser
                                        ? AppColors.error
                                        : AppColors.textMuted,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Reply (only on top-level)
                        if (!widget.isReply) ...[
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: widget.onReply,
                            child: Text('Reply',
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: AppColors.primary)),
                          ),
                        ],
                        // Delete
                        if (widget.onDelete != null) ...[
                          const SizedBox(width: 14),
                          GestureDetector(
                            onTap: widget.onDelete,
                            child: Text('Delete',
                                style: AppTextStyles.labelSmall
                                    .copyWith(color: AppColors.error)),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // View / Hide replies toggle
                  if (hasReplies && !widget.isReply) ...[
                    GestureDetector(
                      onTap: () =>
                          setState(() => _showReplies = !_showReplies),
                      child: Padding(
                        padding:
                            const EdgeInsets.only(left: 6, top: 2, bottom: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 1,
                              color: AppColors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _showReplies
                                  ? 'Hide replies'
                                  : 'View ${comment.replies.length} ${comment.replies.length == 1 ? 'reply' : 'replies'}',
                              style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              _showReplies
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 14,
                              color: AppColors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Replies (expanded)
                  if (hasReplies && _showReplies)
                    ...comment.replies.map((reply) => _CommentTile(
                          comment: reply,
                          currentUid: widget.currentUid,
                          isReply: true,
                          onLike: () => widget.onReplyLike(reply),
                          onReply: () => widget.onReplyReply(reply),
                          onReplyLike: widget.onReplyLike,
                          onReplyReply: widget.onReplyReply,
                          onDelete: widget.currentUid == reply.userId
                              ? () => widget.onReplyDelete?.call(reply)
                              : null,
                          onReplyDelete: widget.onReplyDelete,
                        )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.copy_outlined, color: Colors.white70),
              title: const Text('Copy text',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: widget.comment.content));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Copied to clipboard'),
                      behavior: SnackBarBehavior.floating),
                );
              },
            ),
            if (!widget.isReply)
              ListTile(
                leading:
                    const Icon(Icons.reply_outlined, color: Colors.white70),
                title: const Text('Reply',
                    style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onReply();
                },
              ),
            if (widget.onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                title: const Text('Delete',
                    style: TextStyle(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete?.call();
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.flag_outlined, color: Colors.white70),
              title: const Text('Report',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Comment reported. Thank you.'),
                      behavior: SnackBarBehavior.floating),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Reply Banner
// ─────────────────────────────────────────────────────────────────

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.comment, required this.onCancel});
  final CommentModel comment;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textMuted),
                children: [
                  const TextSpan(text: 'Replying to '),
                  TextSpan(
                    text: comment.displayName,
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  "${_truncate(comment.content, 30)}"',
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close,
                size: 16, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';
}

// ─────────────────────────────────────────────────────────────────
// Comment Input
// ─────────────────────────────────────────────────────────────────

class _CommentInput extends StatelessWidget {
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.isReplying,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final bool isReplying;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: AppColors.darkSurface,
          border: Border(
              top: BorderSide(color: AppColors.darkDivider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.newline,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: Colors.white),
                decoration: InputDecoration(
                  hintText: isReplying ? 'Write a reply…' : 'Add a comment…',
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.darkBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            isSubmitting
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Padding(
                      padding: EdgeInsets.all(6),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      onTap: onSubmit,
                      borderRadius: BorderRadius.circular(22),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.send_rounded,
                            color: Colors.white, size: 20),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

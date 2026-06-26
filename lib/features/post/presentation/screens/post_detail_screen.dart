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

class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});
  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() =>
      _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
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
                              onCommentTap: () {
                                _focusNode.requestFocus();
                              },
                            ),
                          ),

                          // Comments header
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Row(
                                children: [
                                  Text(
                                    'Comments',
                                    style: AppTextStyles.titleSmall.copyWith(
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color:
                                          AppColors.primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${state.comments.length}',
                                      style: AppTextStyles.labelSmall
                                          .copyWith(color: AppColors.primary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Reply banner
                          if (state.replyingTo != null)
                            SliverToBoxAdapter(
                              child: _ReplyBanner(
                                comment: state.replyingTo!,
                                onCancel: () => ref
                                    .read(postDetailProvider(widget.postId)
                                        .notifier)
                                    .setReplyingTo(null),
                              ),
                            ),

                          // Comments list
                          state.comments.isEmpty
                              ? SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 32),
                                    child: Center(
                                      child: Column(
                                        children: [
                                          const Icon(Icons.chat_bubble_outline,
                                              size: 40,
                                              color: AppColors.textMuted),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Be the first to comment!',
                                            style: AppTextStyles.bodyMedium
                                                .copyWith(
                                                    color:
                                                        AppColors.textMuted),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                )
                              : SliverList.builder(
                                  itemCount: state.comments.length,
                                  itemBuilder: (_, i) {
                                    final comment = state.comments[i];
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
                                      onDelete: currentUid == comment.userId
                                          ? () => ref
                                              .read(postDetailProvider(
                                                      widget.postId)
                                                  .notifier)
                                              .deleteComment(comment.id)
                                          : null,
                                    );
                                  },
                                ),

                          const SliverToBoxAdapter(
                              child: SizedBox(height: 16)),
                        ],
                      ),
                    ),

                    // ── Comment input ──────────────────────
                    _CommentInput(
                      controller: _commentCtrl,
                      focusNode: _focusNode,
                      isSubmitting: state.isSubmittingComment,
                      onSubmit: _submitComment,
                    ),
                  ],
                ),
    );
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
        // ── Author ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: post.avatarUrl != null
                    ? CachedNetworkImageProvider(post.avatarUrl!)
                    : null,
                backgroundColor: AppColors.primary.withOpacity(0.2),
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
                        Text(
                          post.displayName,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (post.isVerified) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.verified,
                              size: 14, color: AppColors.primary),
                        ],
                      ],
                    ),
                    Text(
                      timeago.format(post.createdAt),
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  post.hubType,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),

        // ── Caption ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            post.caption,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),

        // ── Tags ─────────────────────────────────────────
        if (post.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 6,
              children: post.tags
                  .map((t) => Text(
                        '#$t',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.primary),
                      ))
                  .toList(),
            ),
          ),
        ],

        // ── Media ─────────────────────────────────────────
        if (post.mediaUrls.isNotEmpty) ...[
          const SizedBox(height: 12),
          _MediaCarousel(urls: post.mediaUrls),
        ],

        const SizedBox(height: 12),

        // ── Action bar ────────────────────────────────────
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
                  style:
                      AppTextStyles.labelSmall.copyWith(color: color)),
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
                    color: i == _current
                        ? AppColors.primary
                        : Colors.white38,
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
// Comment Tile
// ─────────────────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.currentUid,
    required this.onLike,
    required this.onReply,
    this.onDelete,
    this.isReply = false,
  });

  final CommentModel comment;
  final String? currentUid;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback? onDelete;
  final bool isReply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: isReply ? 52 : 16,
        right: 16,
        top: 10,
        bottom: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: isReply ? 14 : 18,
            backgroundImage: comment.avatarUrl != null
                ? CachedNetworkImageProvider(comment.avatarUrl!)
                : null,
            backgroundColor: AppColors.primary.withOpacity(0.2),
            child: comment.avatarUrl == null
                ? Icon(Icons.person,
                    color: AppColors.primary, size: isReply ? 12 : 16)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bubble
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            comment.displayName,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (comment.isVerified) ...[
                            const SizedBox(width: 3),
                            const Icon(Icons.verified,
                                size: 12, color: AppColors.primary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        comment.content,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ),

                // Actions row
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Row(
                    children: [
                      Text(
                        timeago.format(comment.createdAt),
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onLike,
                        child: Row(
                          children: [
                            Icon(
                              comment.isLikedByCurrentUser
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              size: 14,
                              color: comment.isLikedByCurrentUser
                                  ? AppColors.error
                                  : AppColors.textMuted,
                            ),
                            if (comment.likesCount > 0) ...[
                              const SizedBox(width: 2),
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
                      if (!isReply) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: onReply,
                          child: Text(
                            'Reply',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.primary),
                          ),
                        ),
                      ],
                      if (onDelete != null) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: onDelete,
                          child: Text(
                            'Delete',
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.error),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Replies
                if (comment.replies.isNotEmpty)
                  ...comment.replies.map((r) => _CommentTile(
                        comment: r,
                        currentUid: currentUid,
                        onLike: onLike,
                        onReply: onReply,
                        onDelete: currentUid == r.userId ? onDelete : null,
                        isReply: true,
                      )),
              ],
            ),
          ),
        ],
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
      color: AppColors.primary.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Replying to ${comment.displayName}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.primary),
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
}

// ─────────────────────────────────────────────────────────────────
// Comment Input
// ─────────────────────────────────────────────────────────────────

class _CommentInput extends StatelessWidget {
  const _CommentInput({
    required this.controller,
    required this.focusNode,
    required this.isSubmitting,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSubmitting;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          border: Border(top: BorderSide(color: AppColors.darkDivider)),
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
                  hintText: 'Add a comment…',
                  hintStyle: const TextStyle(color: AppColors.textMuted),
                  filled: true,
                  fillColor: AppColors.darkBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
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
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: onSubmit,
                    icon: const Icon(Icons.send_rounded),
                    color: AppColors.primary,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary.withOpacity(0.15),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}

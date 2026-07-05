import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/services/block_service.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../boosts/domain/models/boost_model.dart';
import '../../../boosts/presentation/widgets/promote_post_sheet.dart';
import '../../domain/models/post_model.dart';
import '../providers/feed_provider.dart';
import '../screens/youtube_player_screen.dart';

class FeedPostCard extends ConsumerStatefulWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.hubType,
    this.isBoosted = false,
  });

  final PostModel post;
  final String hubType; // passed so the notifier can be referenced
  final bool isBoosted;

  @override
  ConsumerState<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends ConsumerState<FeedPostCard>
    with SingleTickerProviderStateMixin {
  // ── Double-tap heart overlay ──────────────────────────────
  late AnimationController _heartCtrl;
  late Animation<double> _heartScale;
  late Animation<double> _heartOpacity;
  bool _showHeart = false;

  // ── Image carousel ────────────────────────────────────────
  int _currentPage = 0;
  final _pageCtrl = PageController();

  // ── Caption expand ────────────────────────────────────────
  bool _captionExpanded = false;

  @override
  void initState() {
    super.initState();
    _heartCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.3)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.3, end: 1.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.0), weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 20),
    ]).animate(_heartCtrl);
    _heartOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_heartCtrl);
  }

  @override
  void dispose() {
    _heartCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Like ──────────────────────────────────────────────────

  void _onLikeTap() {
    ref.read(feedProvider(widget.hubType).notifier).toggleLike(widget.post.id);
  }

  void _onDoubleTap() {
    if (!widget.post.isLikedByCurrentUser) {
      _onLikeTap();
    }
    setState(() => _showHeart = true);
    _heartCtrl.forward(from: 0).then((_) {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final hasMedia = post.hasMedia;
    final isMulti = post.isMultiMedia;
    final isLiked = post.isLikedByCurrentUser;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ──────────────────────────────────────────
        GestureDetector(
          onTap: () => context.push('/user/${post.userId}'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                // Avatar
                _PostAvatar(url: post.avatarUrl ?? '', username: post.usernameDisplay),
                const SizedBox(width: 10),

                // Username + time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            post.usernameDisplay,
                            style: AppTextStyles.username.copyWith(
                              color: AppColors.textDarkPrimary,
                            ),
                          ),
                          if (post.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 14,
                                color: AppColors.verifiedBadge),
                          ],
                          if (widget.isBoosted) ...[
                            const SizedBox(width: 6),
                            const _PromotedTag(),
                          ],
                        ],
                      ),
                      Text(
                        timeago.format(post.createdAt),
                        style: AppTextStyles.labelSmall.copyWith(
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Hub tag
                _HubTag(hubType: post.hubType),
                const SizedBox(width: 4),

                // More options
                IconButton(
                  icon: const Icon(Icons.more_horiz,
                      color: AppColors.textDarkSecondary, size: 20),
                  onPressed: () => _showPostOptions(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),

        // ── Media ────────────────────────────────────────────
        if (hasMedia)
          GestureDetector(
            onDoubleTap: _onDoubleTap,
            onTap: () {
              final ytId = extractYoutubeId(post.youtubeUrl) ??
                  (post.isVideo
                      ? extractYoutubeId(post.mediaUrls.firstOrNull)
                      : null);
              if (ytId != null) {
                // YouTube video — open YouTube-style player
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => YoutubePlayerScreen.fromPost(
                    post: post,
                    hubType: widget.hubType,
                  ),
                ));
              } else {
                // Internal post — go to post detail
                context.push('/post/${post.id}');
              }
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Image / carousel
                AspectRatio(
                  aspectRatio: post.isVideo ? 16 / 9 : 1,
                  child: isMulti
                      ? _MediaCarousel(
                          mediaUrls: post.mediaUrls,
                          isVideo: post.isVideo,
                          youtubeId: extractYoutubeId(post.youtubeUrl),
                          controller: _pageCtrl,
                          onPageChanged: (i) =>
                              setState(() => _currentPage = i),
                        )
                      : _MediaItem(
                          url: post.mediaUrls.first,
                          isVideo: post.isVideo,
                          youtubeId: extractYoutubeId(post.youtubeUrl) ??
                              extractYoutubeId(post.mediaUrls.firstOrNull),
                        ),
                ),

                // Double-tap heart
                if (_showHeart)
                  AnimatedBuilder(
                    animation: _heartCtrl,
                    builder: (_, __) => Opacity(
                      opacity: _heartOpacity.value,
                      child: Transform.scale(
                        scale: _heartScale.value,
                        child: const Icon(
                          Icons.favorite,
                          color: Colors.white,
                          size: 90,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 12,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Page indicator dots
                if (isMulti)
                  Positioned(
                    bottom: 10,
                    child: _DotIndicator(
                      count: post.mediaUrls.length,
                      current: _currentPage,
                    ),
                  ),
              ],
            ),
          ),

        // ── Action row ───────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              // Like button
              GestureDetector(
                onTap: _onLikeTap,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: child,
                  ),
                  child: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    key: ValueKey(isLiked),
                    color: isLiked
                        ? AppColors.error
                        : AppColors.textDarkPrimary,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Comment button
              GestureDetector(
                onTap: () => context.push('/post/${post.id}'),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: AppColors.textDarkPrimary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),

              // Share button
              GestureDetector(
                onTap: () => Share.share(
                  post.caption.isNotEmpty
                      ? '${post.usernameDisplay}: ${post.caption}'
                      : 'Check out this post on CommunityHub!',
                ),
                child: const Icon(
                  Icons.send_outlined,
                  color: AppColors.textDarkPrimary,
                  size: 24,
                ),
              ),

              const Spacer(),

              // Bookmark
              GestureDetector(
                onTap: () => ref
                    .read(feedProvider(widget.hubType).notifier)
                    .toggleBookmark(post.id),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: Icon(
                    post.isBookmarkedByCurrentUser
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_border_rounded,
                    key: ValueKey(post.isBookmarkedByCurrentUser),
                    color: post.isBookmarkedByCurrentUser
                        ? AppColors.secondary
                        : AppColors.textDarkPrimary,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Likes count ──────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            '${post.likesCount} ${post.likesCount == 1 ? 'like' : 'likes'}',
            style: AppTextStyles.username.copyWith(
              fontSize: 13,
              color: AppColors.textDarkPrimary,
            ),
          ),
        ),

        // ── Caption ──────────────────────────────────────────
        if (post.caption.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: GestureDetector(
              onTap: () => setState(
                  () => _captionExpanded = !_captionExpanded),
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '${post.usernameDisplay}  ',
                      style: AppTextStyles.username.copyWith(
                        color: AppColors.textDarkPrimary,
                      ),
                    ),
                    TextSpan(
                      text: post.caption,
                      style: AppTextStyles.captionText.copyWith(
                        color: AppColors.textDarkPrimary,
                      ),
                    ),
                  ],
                ),
                maxLines: _captionExpanded ? null : 2,
                overflow: _captionExpanded
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
              ),
            ),
          ),

        // ── View all comments ─────────────────────────────────
        if (post.commentsCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: GestureDetector(
              onTap: () => context.push('/post/${post.id}'),
              child: Text(
                'View all ${post.commentsCount} comments',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textDarkSecondary,
                ),
              ),
            ),
          ),

        const SizedBox(height: 10),
      ],
    );
  }

  void _showPostOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined,
                  color: AppColors.textDarkPrimary),
              title: Text('Share post',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textDarkPrimary,
                  )),
              onTap: () {
                Navigator.pop(context);
                Share.share(
                  widget.post.caption.isNotEmpty
                      ? '${widget.post.usernameDisplay}: ${widget.post.caption}'
                      : 'Check out this post on CommunityHub!',
                );
              },
            ),
            if (widget.post.userId == SupabaseService.currentUserId)
              ListTile(
                leading: const Icon(Icons.trending_up_rounded,
                    color: AppColors.secondary),
                title: Text('Promote post',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: AppColors.secondary,
                    )),
                onTap: () async {
                  Navigator.pop(context);
                  await showPromoteSheet(
                    context,
                    targetType: BoostTargetType.post,
                    targetId: widget.post.id,
                  );
                },
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined,
                  color: AppColors.textDarkPrimary),
              title: Text('Report',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textDarkPrimary,
                  )),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.block,
                  color: AppColors.error),
              title: Text('Block user',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.error,
                  )),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: AppColors.darkSurface,
                    title: Text('Block ${widget.post.usernameDisplay}?',
                        style: const TextStyle(color: Colors.white)),
                    content: const Text(
                      'They won\'t be able to see your posts or message you, and you won\'t see theirs.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Block',
                            style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await BlockService.instance.blockUser(widget.post.userId);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _PromotedTag extends StatelessWidget {
  const _PromotedTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: const Text(
        'Promoted',
        style: TextStyle(
          color: AppColors.secondary,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Media carousel
// ─────────────────────────────────────────────────────────────

class _MediaCarousel extends StatelessWidget {
  const _MediaCarousel({
    required this.mediaUrls,
    required this.isVideo,
    required this.controller,
    required this.onPageChanged,
    this.youtubeId,
  });

  final List<String> mediaUrls;
  final bool isVideo;
  final PageController controller;
  final ValueChanged<int> onPageChanged;
  final String? youtubeId;

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: controller,
      onPageChanged: onPageChanged,
      itemCount: mediaUrls.length,
      itemBuilder: (_, i) => _MediaItem(
        url: mediaUrls[i],
        isVideo: isVideo,
        youtubeId: i == 0 ? youtubeId : null,
      ),
    );
  }
}

class _MediaItem extends StatelessWidget {
  const _MediaItem({
    required this.url,
    required this.isVideo,
    this.youtubeId,
  });

  final String url;
  final bool isVideo;
  final String? youtubeId;

  @override
  Widget build(BuildContext context) {
    // For YouTube videos, use the hq YouTube thumbnail directly
    final displayUrl = youtubeId != null
        ? 'https://img.youtube.com/vi/$youtubeId/hqdefault.jpg'
        : url;

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: displayUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) =>
              Container(color: AppColors.darkSurface2),
          errorWidget: (_, __, ___) => Container(
            color: AppColors.darkSurface2,
            child: const Icon(Icons.image_not_supported_rounded,
                color: AppColors.textDarkTertiary, size: 40),
          ),
        ),
        if (isVideo)
          Center(
            child: _VideoPlayOverlay(isYoutube: youtubeId != null),
          ),
      ],
    );
  }
}

class _VideoPlayOverlay extends StatelessWidget {
  const _VideoPlayOverlay({this.isYoutube = false});
  final bool isYoutube;

  @override
  Widget build(BuildContext context) {
    if (isYoutube) {
      // Red YouTube-style play button
      return Container(
        width: 56,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFFF0000),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.play_arrow_rounded,
            color: Colors.white, size: 30),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.play_arrow_rounded,
          color: Colors.white, size: 32),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Dot indicator for multi-image
// ─────────────────────────────────────────────────────────────

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({required this.count, required this.current});
  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count.clamp(0, 10), (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: active ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active
                ? AppColors.secondary
                : Colors.white.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Avatar
// ─────────────────────────────────────────────────────────────

class _PostAvatar extends StatelessWidget {
  const _PostAvatar({required this.url, required this.username});
  final String url;
  final String username;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(width: 36, height: 36, color: AppColors.darkSurface2),
              errorWidget: (_, __, ___) => _Fallback(username: username),
            )
          : _Fallback(username: username),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      color: AppColors.primaryLight,
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Hub tag
// ─────────────────────────────────────────────────────────────

class _HubTag extends StatelessWidget {
  const _HubTag({required this.hubType});
  final String hubType;

  @override
  Widget build(BuildContext context) {
    if (hubType == 'all') return const SizedBox.shrink();
    final isFaith = hubType == 'faith';
    final color = isFaith ? AppColors.faithTag : AppColors.techTag;
    final label = isFaith ? '✝ Faith' : '⌨ Tech';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontSize: 10,
        ),
      ),
    );
  }
}

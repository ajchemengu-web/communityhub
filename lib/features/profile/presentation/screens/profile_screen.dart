import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../home/domain/models/post_model.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final String _uid;

  @override
  void initState() {
    super.initState();
    _uid = widget.userId ?? SupabaseService.currentUserId ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: Text('Not logged in')),
      );
    }

    final state = ref.watch(profileProvider(_uid));

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.errorMessage != null
              ? _ErrorView(
                  message: state.errorMessage!,
                  onRetry: () =>
                      ref.read(profileProvider(_uid).notifier).refresh(),
                )
              : RefreshIndicator(
                  onRefresh: () =>
                      ref.read(profileProvider(_uid).notifier).refresh(),
                  child: CustomScrollView(
                    slivers: [
                      // ── Header SliverAppBar ────────────
                      _ProfileSliverHeader(
                        state: state,
                        uid: _uid,
                        onFollow: () => ref
                            .read(profileProvider(_uid).notifier)
                            .toggleFollow(),
                        onEdit: () => context.push(AppRoutes.setupProfile),
                        onMessage: () =>
                            context.push('${AppRoutes.chats}?userId=$_uid'),
                      ),

                      // ── Posts grid ─────────────────────
                      state.posts.isEmpty
                          ? SliverFillRemaining(
                              child: Center(
                                child: Column(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.grid_off_rounded,
                                      size: 48,
                                      color: AppColors.textMuted,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      state.isOwnProfile
                                          ? 'Share your first post!'
                                          : 'No posts yet',
                                      style: AppTextStyles.bodyMedium
                                          .copyWith(
                                              color: AppColors.textMuted),
                                    ),
                                    if (state.isOwnProfile) ...[
                                      const SizedBox(height: 12),
                                      FilledButton.icon(
                                        onPressed: () =>
                                            context.push(AppRoutes.newPost),
                                        icon: const Icon(Icons.add),
                                        label: const Text('Create Post'),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : SliverGrid(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) {
                                  // Load more trigger
                                  if (i == state.posts.length - 3 &&
                                      state.hasMore) {
                                    ref
                                        .read(
                                            profileProvider(_uid).notifier)
                                        .loadMore();
                                  }
                                  if (i >= state.posts.length) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    );
                                  }
                                  return _PostGridTile(
                                    post: state.posts[i],
                                    onTap: () => context.push(
                                        '/post/${state.posts[i].id}'),
                                  );
                                },
                                childCount: state.posts.length +
                                    (state.isLoadingMore ? 1 : 0),
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 2,
                                mainAxisSpacing: 2,
                              ),
                            ),
                    ],
                  ),
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Profile Header (Sliver)
// ─────────────────────────────────────────────────────────────────

class _ProfileSliverHeader extends StatelessWidget {
  const _ProfileSliverHeader({
    required this.state,
    required this.uid,
    required this.onFollow,
    required this.onEdit,
    required this.onMessage,
  });

  final ProfileState state;
  final String uid;
  final VoidCallback onFollow;
  final VoidCallback onEdit;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final profile = state.profileData ?? {};
    final avatarUrl = profile['avatar_url'] as String?;
    final fullName = profile['full_name'] as String? ?? 'Unknown';
    final username = profile['username'] as String? ?? '';
    final bio = profile['bio'] as String?;
    final churchName = profile['church_name'] as String?;
    final website = profile['website'] as String?;
    final isVerified = (profile['is_verified'] as bool?) ?? false;

    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── App bar row ────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
              child: Row(
                children: [
                  if (context.canPop())
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 18),
                      onPressed: () => context.pop(),
                    )
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      username.isNotEmpty ? '@$username' : fullName,
                      style: AppTextStyles.titleSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (state.isOwnProfile)
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: () {},
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ── Avatar + stats row ─────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Avatar
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundImage: avatarUrl != null
                          ? CachedNetworkImageProvider(avatarUrl)
                          : null,
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      child: avatarUrl == null
                          ? const Icon(Icons.person,
                              color: AppColors.primary, size: 40)
                          : null,
                    ),
                    if (isVerified)
                      Positioned(
                        bottom: 2,
                        right: 2,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: AppColors.darkBackground,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.verified,
                              color: AppColors.primary, size: 18),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 20),

                // Stats
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(
                          count: state.postCount, label: 'Posts'),
                      _StatColumn(
                          count: state.followerCount,
                          label: 'Followers'),
                      _StatColumn(
                          count: state.followingCount,
                          label: 'Following'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Bio ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (bio != null && bio.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    bio,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: Colors.white70, height: 1.4),
                  ),
                ],
                if (churchName != null && churchName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.church,
                          size: 14, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        churchName,
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textMuted),
                      ),
                    ],
                  ),
                ],
                if (website != null && website.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(website)),
                    child: Row(
                      children: [
                        const Icon(Icons.link,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text(
                          website,
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Action buttons ─────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                if (state.isOwnProfile) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onEdit,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.darkDivider),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Edit Profile'),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: state.isTogglingFollow ? null : onFollow,
                      style: FilledButton.styleFrom(
                        backgroundColor: state.isFollowing
                            ? AppColors.darkSurface
                            : AppColors.primary,
                        foregroundColor: state.isFollowing
                            ? Colors.white70
                            : Colors.white,
                        side: state.isFollowing
                            ? const BorderSide(
                                color: AppColors.darkDivider)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: state.isTogglingFollow
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              state.isFollowing ? 'Following' : 'Follow'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onMessage,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side:
                          const BorderSide(color: AppColors.darkDivider),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Message'),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),
          const Divider(color: AppColors.darkDivider, height: 1),
        ],
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  const _StatColumn({required this.count, required this.label});
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _format(count),
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style:
              AppTextStyles.labelSmall.copyWith(color: AppColors.textMuted),
        ),
      ],
    );
  }

  String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────
// Post Grid Tile
// ─────────────────────────────────────────────────────────────────

class _PostGridTile extends StatelessWidget {
  const _PostGridTile({required this.post, required this.onTap});
  final PostModel post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          post.mediaUrls.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: post.mediaUrls.first,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: AppColors.darkSurface,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.darkSurface,
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppColors.textMuted, size: 20),
                  ),
                )
              : Container(
                  color: AppColors.darkSurface,
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    post.caption,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: Colors.white70, fontSize: 10),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          if (post.mediaUrls.length > 1)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.collections, size: 16, color: Colors.white),
            ),
          if (post.mediaType == 'video')
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.play_circle_outline,
                  size: 16, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Error View
// ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: AppTextStyles.titleSmall
                .copyWith(color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

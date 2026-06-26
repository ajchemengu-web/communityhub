import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../home/domain/models/post_model.dart';
import '../../domain/models/announcement_model.dart';
import '../../domain/models/community_model.dart';
import '../providers/communities_provider.dart';
import '../providers/community_detail_provider.dart';

class CommunityDetailScreen extends ConsumerStatefulWidget {
  const CommunityDetailScreen({super.key, required this.communityId});
  final String communityId;

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState
    extends ConsumerState<CommunityDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleMembership() async {
    await ref
        .read(communityDetailProvider(widget.communityId).notifier)
        .toggleMembership();

    final state = ref.read(communityDetailProvider(widget.communityId));
    if (state.community != null) {
      ref
          .read(communitiesProvider.notifier)
          .updateCommunity(state.community!);
    }
  }

  void _showAnnouncementDialog(BuildContext context, CommunityModel c) {
    final titleCtrl = TextEditingController();
    final contentCtrl = TextEditingController();
    bool pinned = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setS) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('New Announcement',
                  style: AppTextStyles.titleSmall
                      .copyWith(color: Colors.white)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: Colors.white),
                decoration: _inputDec('Title'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 4,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: Colors.white),
                decoration: _inputDec('Content…'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Switch(
                    value: pinned,
                    onChanged: (v) => setS(() => pinned = v),
                    activeColor: AppColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text('Pin this announcement',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: Colors.white70)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty || contentCtrl.text.isEmpty) {
                      return;
                    }
                    ctx.pop();
                    await ref
                        .read(communityDetailProvider(widget.communityId)
                            .notifier)
                        .postAnnouncement(
                          title: titleCtrl.text,
                          content: contentCtrl.text,
                          isPinned: pinned,
                        );
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: const Text('Post'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textMuted),
        filled: true,
        fillColor: AppColors.darkBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communityDetailProvider(widget.communityId));

    if (state.isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final c = state.community;
    if (c == null) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(
          backgroundColor: AppColors.darkSurface,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: () => context.pop()),
        ),
        body: const Center(
            child: Text('Community not found',
                style: TextStyle(color: AppColors.textMuted))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          _CommunitySliverHeader(
            community: c,
            onBack: () => context.pop(),
            onShare: () => Share.share(
                'Join ${c.name} on CommunityHub! 🙏'),
            onToggleMembership:
                state.isJoining ? null : _toggleMembership,
            onAnnouncement: c.isModerator
                ? () => _showAnnouncementDialog(context, c)
                : null,
            onNewPost: (c.isMember && c.isApproved)
                ? () => context.push(AppRoutes.newPost)
                : null,
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabCtrl,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: AppTextStyles.labelMedium,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.feed_rounded, size: 14),
                        const SizedBox(width: 4),
                        const Text('Posts'),
                        if (state.posts.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _SmallBadge(count: state.posts.length),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.campaign_rounded, size: 14),
                        const SizedBox(width: 4),
                        const Text('Updates'),
                        if (state.announcements.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _SmallBadge(
                              count: state.announcements.length),
                        ],
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_alt_rounded, size: 14),
                        const SizedBox(width: 4),
                        const Text('Members'),
                        if (state.members.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          _SmallBadge(count: c.membersCount),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            // ── Posts ──────────────────────────────────
            _PostsTab(
              posts: state.posts,
              hasMore: state.hasMorePosts,
              isLoadingMore: state.isLoadingPosts,
              isMember: c.isMember && c.isApproved,
              onLoadMore: () => ref
                  .read(communityDetailProvider(widget.communityId)
                      .notifier)
                  .loadMorePosts(),
              onNewPost: () => context.push(AppRoutes.newPost),
            ),

            // ── Announcements ──────────────────────────
            _AnnouncementsTab(announcements: state.announcements),

            // ── Members ────────────────────────────────
            _MembersTab(members: state.members),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Sliver Header
// ─────────────────────────────────────────────────────────────────

class _CommunitySliverHeader extends StatelessWidget {
  const _CommunitySliverHeader({
    required this.community,
    required this.onBack,
    required this.onShare,
    required this.onToggleMembership,
    this.onAnnouncement,
    this.onNewPost,
  });

  final CommunityModel community;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback? onToggleMembership;
  final VoidCallback? onAnnouncement;
  final VoidCallback? onNewPost;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover ──────────────────────────────────────
          Stack(
            children: [
              community.coverUrl != null && community.coverUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: community.coverUrl!,
                      height: 180,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 180,
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                      errorWidget: (_, __, ___) =>
                          _coverPlaceholder(community.hubType),
                    )
                  : _coverPlaceholder(community.hubType),
              // Nav bar overlay
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      _CircleBtn(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: onBack),
                      const Spacer(),
                      _CircleBtn(icon: Icons.share_outlined, onTap: onShare),
                      if (onAnnouncement != null) ...[
                        const SizedBox(width: 4),
                        _CircleBtn(
                          icon: Icons.campaign_rounded,
                          onTap: onAnnouncement!,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── Info ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              community.name,
                              style: AppTextStyles.titleMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (community.isVerified)
                            const Icon(Icons.verified,
                                size: 18, color: AppColors.primary),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Meta row
                      Wrap(
                        spacing: 12,
                        children: [
                          _MetaChip(
                            icon: Icons.people_alt_rounded,
                            label:
                                '${_fmt(community.membersCount)} members',
                          ),
                          if (community.hubType != 'all')
                            _MetaChip(
                              icon: community.hubType == 'faith'
                                  ? Icons.church_rounded
                                  : Icons.work_rounded,
                              label: community.hubType == 'faith'
                                  ? 'Faith'
                                  : 'Career',
                            ),
                          if (community.isPrivate)
                            const _MetaChip(
                              icon: Icons.lock_outline,
                              label: 'Private',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Join / Leave button
                FilledButton(
                  onPressed: onToggleMembership,
                  style: FilledButton.styleFrom(
                    backgroundColor: community.isMember
                        ? AppColors.darkSurface
                        : AppColors.primary,
                    foregroundColor:
                        community.isMember ? Colors.white70 : Colors.white,
                    side: community.isMember
                        ? const BorderSide(color: AppColors.darkBorder)
                        : null,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                  ),
                  child: community.isMember
                      ? Text(community.memberStatus == 'pending'
                          ? 'Pending'
                          : 'Leave')
                      : Text(community.isPrivate ? 'Request' : 'Join'),
                ),
              ],
            ),
          ),

          // ── Description ────────────────────────────────
          if (community.description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                community.description,
                style: AppTextStyles.bodySmall
                    .copyWith(color: Colors.white70, height: 1.5),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          // ── Additional info ────────────────────────────
          if (community.denomination != null ||
              community.location != null ||
              community.website != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (community.denomination != null &&
                      community.denomination!.isNotEmpty)
                    _InfoRow(
                        icon: Icons.account_balance_rounded,
                        text: community.denomination!),
                  if (community.location != null &&
                      community.location!.isNotEmpty)
                    _InfoRow(
                        icon: Icons.location_on_outlined,
                        text: community.location!),
                  if (community.website != null &&
                      community.website!.isNotEmpty)
                    GestureDetector(
                      onTap: () =>
                          launchUrl(Uri.parse(community.website!)),
                      child: _InfoRow(
                        icon: Icons.link_rounded,
                        text: community.website!,
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _coverPlaceholder(String hubType) {
    final color = hubType == 'faith'
        ? AppColors.faithTag
        : hubType == 'career'
            ? AppColors.techTag
            : AppColors.primary;
    return Container(
      height: 180,
      width: double.infinity,
      color: color.withOpacity(0.25),
      child: Icon(
        hubType == 'faith'
            ? Icons.church_rounded
            : hubType == 'career'
                ? Icons.work_rounded
                : Icons.groups_rounded,
        size: 64,
        color: color.withOpacity(0.4),
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Colors.black45,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Text(label,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textMuted)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.text, this.color = AppColors.textMuted});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: AppTextStyles.labelSmall.copyWith(color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Posts Tab
// ─────────────────────────────────────────────────────────────────

class _PostsTab extends StatelessWidget {
  const _PostsTab({
    required this.posts,
    required this.hasMore,
    required this.isLoadingMore,
    required this.isMember,
    required this.onLoadMore,
    required this.onNewPost,
  });

  final List<PostModel> posts;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isMember;
  final VoidCallback onLoadMore;
  final VoidCallback onNewPost;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.feed_rounded,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('No posts yet',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textMuted)),
            if (isMember) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onNewPost,
                icon: const Icon(Icons.add),
                label: const Text('Post Something'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: posts.length + (hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == posts.length - 3 && hasMore) onLoadMore();
        if (i == posts.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final p = posts[i];
        return _CommunityPostTile(post: p);
      },
    );
  }
}

class _CommunityPostTile extends StatelessWidget {
  const _CommunityPostTile({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/post/${post.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundImage: post.avatarUrl != null
                      ? CachedNetworkImageProvider(post.avatarUrl!)
                      : null,
                  backgroundColor: AppColors.primary.withOpacity(0.2),
                  child: post.avatarUrl == null
                      ? const Icon(Icons.person,
                          color: AppColors.primary, size: 14)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.displayName,
                          style: AppTextStyles.labelMedium
                              .copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                      Text(timeago.format(post.createdAt),
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              post.caption,
              style: AppTextStyles.bodySmall
                  .copyWith(color: Colors.white70, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (post.mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: post.mediaUrls.first,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                    post.isLikedByCurrentUser
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    size: 16,
                    color: post.isLikedByCurrentUser
                        ? AppColors.error
                        : AppColors.textMuted),
                const SizedBox(width: 4),
                Text('${post.likesCount}',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textMuted)),
                const SizedBox(width: 14),
                const Icon(Icons.chat_bubble_outline_rounded,
                    size: 16, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text('${post.commentsCount}',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Announcements Tab
// ─────────────────────────────────────────────────────────────────

class _AnnouncementsTab extends StatelessWidget {
  const _AnnouncementsTab({required this.announcements});
  final List<AnnouncementModel> announcements;

  @override
  Widget build(BuildContext context) {
    if (announcements.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.campaign_rounded,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text('No updates yet',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textMuted)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: announcements.length,
      itemBuilder: (ctx, i) =>
          _AnnouncementCard(announcement: announcements[i]),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement});
  final AnnouncementModel announcement;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: announcement.isPinned
              ? AppColors.secondary.withOpacity(0.5)
              : AppColors.darkBorder,
          width: announcement.isPinned ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pin banner
          if (announcement.isPinned)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.push_pin_rounded,
                      size: 14, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  Text('Pinned',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.secondary)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (announcement.authorAvatar != null)
                      CircleAvatar(
                        radius: 14,
                        backgroundImage: CachedNetworkImageProvider(
                            announcement.authorAvatar!),
                        backgroundColor:
                            AppColors.primary.withOpacity(0.2),
                      )
                    else
                      const CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.darkBackground,
                        child: Icon(Icons.person,
                            color: AppColors.primary, size: 14),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            announcement.authorName ?? 'Admin',
                            style: AppTextStyles.labelMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600),
                          ),
                          Text(
                            timeago.format(announcement.createdAt),
                            style: AppTextStyles.labelSmall
                                .copyWith(color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  announcement.title,
                  style: AppTextStyles.titleSmall
                      .copyWith(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  announcement.content,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: Colors.white70, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Members Tab
// ─────────────────────────────────────────────────────────────────

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.members});
  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Center(
        child: Text('No members yet',
            style: TextStyle(color: AppColors.textMuted)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: members.length,
      itemBuilder: (ctx, i) {
        final m = members[i];
        final user = m['users'] as Map<String, dynamic>? ?? {};
        final role = m['role'] as String? ?? 'member';
        final avatarUrl = user['avatar_url'] as String?;
        final fullName = user['full_name'] as String? ??
            user['username'] as String? ??
            'Member';
        final username = user['username'] as String? ?? '';
        final isVerified = (user['is_verified'] as bool?) ?? false;
        final userId = user['id'] as String?;

        return ListTile(
          onTap: userId != null
              ? () => context.push('/user/$userId')
              : null,
          leading: CircleAvatar(
            radius: 22,
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            backgroundColor: AppColors.primary.withOpacity(0.2),
            child: avatarUrl == null
                ? const Icon(Icons.person,
                    color: AppColors.primary, size: 20)
                : null,
          ),
          title: Row(
            children: [
              Text(fullName,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.white)),
              if (isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified,
                    size: 14, color: AppColors.primary),
              ],
            ],
          ),
          subtitle: Text('@$username',
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textMuted)),
          trailing: _RoleTag(role: role),
        );
      },
    );
  }
}

class _RoleTag extends StatelessWidget {
  const _RoleTag({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final color = role == 'admin'
        ? AppColors.secondary
        : role == 'moderator'
            ? AppColors.accent
            : AppColors.darkBorder;
    if (role == 'member') return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        role[0].toUpperCase() + role.substring(1),
        style:
            AppTextStyles.labelSmall.copyWith(color: color),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tab Bar Delegate (for pinned TabBar)
// ─────────────────────────────────────────────────────────────────

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  const _TabBarDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: AppColors.darkBackground, child: tabBar);

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _fmt(count),
        style: const TextStyle(
            fontSize: 9,
            color: AppColors.primary,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

String _fmt(int n) {
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

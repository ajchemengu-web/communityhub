import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../widgets/story_row.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/youtube_video_card.dart';
import '../providers/feed_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _activeHub = AppConstants.hubAll;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _activeHub = [
            AppConstants.hubAll,
            AppConstants.hubFaith,
            AppConstants.hubCareer,
          ][_tabController.index];
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          _HomeAppBar(
            onNotificationTap: () => context.push(AppRoutes.notifications),
            onChatTap: () => context.push(AppRoutes.chats),
            onCommunitiesTap: () => context.push(AppRoutes.communities),
            onMyChurchTap: () => context.push(AppRoutes.myChurch),
          ),
          SliverToBoxAdapter(child: StoryRow()),
          SliverPersistentHeader(
            pinned: true,
            delegate: _HubTabBarDelegate(controller: _tabController),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _FeedTab(hubType: AppConstants.hubAll),
            _FeedTab(hubType: AppConstants.hubFaith),
            _FeedTab(hubType: AppConstants.hubCareer),
          ],
        ),
      ),
    );
  }
}

// ── App Bar ────────────────────────────────────────────────────
class _HomeAppBar extends SliverAppBar {
  _HomeAppBar({
    required VoidCallback onNotificationTap,
    required VoidCallback onChatTap,
    required VoidCallback onCommunitiesTap,
    required VoidCallback onMyChurchTap,
  }) : super(
    backgroundColor: AppColors.darkBackground,
    floating: true,
    snap: true,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: 56,
    title: Row(
      children: [
        const Icon(Icons.hub_rounded, color: AppColors.secondary, size: 26),
        const SizedBox(width: 8),
        Text(
          'CommunityHub',
          style: AppTextStyles.titleLarge.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
    actions: [
      // My Church
      IconButton(
        icon: const Icon(Icons.church_rounded, color: Colors.white70, size: 24),
        onPressed: onMyChurchTap,
        tooltip: 'My Church',
      ),
      // Communities
      IconButton(
        icon: const Icon(Icons.groups_rounded, color: Colors.white70, size: 24),
        onPressed: onCommunitiesTap,
        tooltip: 'Communities',
      ),
      // Chat (WhatsApp style icon)
      IconButton(
        icon: const Icon(Icons.chat_bubble_outline_rounded, color: Colors.white70, size: 24),
        onPressed: onChatTap,
        tooltip: 'Chat',
      ),
      // Notifications (Facebook style)
      Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white70, size: 24),
            onPressed: onNotificationTap,
            tooltip: 'Notifications',
          ),
          // Notification badge
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: AppColors.error,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(width: 4),
    ],
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(0),
      child: Divider(height: 0, color: AppColors.darkBorder),
    ),
  );
}

// ── Hub Tab Bar ────────────────────────────────────────────────
class _HubTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _HubTabBarDelegate({required this.controller});
  final TabController controller;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.darkBackground,
      child: TabBar(
        controller: controller,
        labelStyle: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: AppTextStyles.labelLarge,
        labelColor: AppColors.secondary,
        unselectedLabelColor: AppColors.textDarkSecondary,
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(color: AppColors.secondary, width: 2),
          insets: EdgeInsets.symmetric(horizontal: 16),
        ),
        tabs: const [
          Tab(text: 'All'),
          Tab(text: 'Faith Hub'),
          Tab(text: 'Career Hub'),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HubTabBarDelegate oldDelegate) => false;
}

// ── Feed Tab (with infinite scroll) ───────────────────────────
class _FeedTab extends ConsumerStatefulWidget {
  const _FeedTab({required this.hubType});
  final String hubType;

  @override
  ConsumerState<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<_FeedTab> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Trigger load-more when within 300px of the list bottom
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(feedProvider(widget.hubType).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider(widget.hubType));
    final isLoadingMore =
        ref.watch(feedLoadingMoreProvider(widget.hubType));

    return feedAsync.when(
      loading: () => _FeedSkeleton(),
      error: (err, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 48, color: AppColors.textDarkSecondary),
            const SizedBox(height: 12),
            Text(
              'Could not load feed',
              style: AppTextStyles.titleSmall
                  .copyWith(color: AppColors.textDarkSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.invalidate(feedProvider(widget.hubType)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (items) => RefreshIndicator(
        color: AppColors.secondary,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () async =>
            ref.invalidate(feedProvider(widget.hubType)),
        child: ListView.separated(
          controller: _scrollCtrl,
          padding: const EdgeInsets.only(bottom: 20),
          itemCount: items.length + (isLoadingMore ? 1 : 0),
          separatorBuilder: (_, __) =>
              const Divider(height: 1, color: AppColors.darkBorder),
          itemBuilder: (ctx, i) {
            // Load-more spinner at the bottom
            if (i == items.length) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              );
            }

            final item = items[i];
            if (item.isYouTube) {
              return YouTubeVideoCard(video: item.youtubeVideo!);
            }
            return FeedPostCard(
              post: item.post!,
              hubType: widget.hubType,
            );
          },
        ),
      ),
    );
  }
}

// ── Skeleton Loader ────────────────────────────────────────────
class _FeedSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(top: 8),
      itemCount: 5,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: AppColors.darkBorder),
      itemBuilder: (_, i) => const _PostSkeleton(),
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _Shimmer(width: 36, height: 36, radius: 18),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Shimmer(width: 120, height: 12),
              const SizedBox(height: 4),
              _Shimmer(width: 80, height: 10),
            ]),
          ]),
          const SizedBox(height: 12),
          _Shimmer(width: double.infinity, height: 200),
          const SizedBox(height: 10),
          _Shimmer(width: 200, height: 12),
          const SizedBox(height: 6),
          _Shimmer(width: 150, height: 10),
        ],
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.width, required this.height, this.radius = 6});
  final double width;
  final double height;
  final double radius;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppColors.darkSurface2.withOpacity(_anim.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

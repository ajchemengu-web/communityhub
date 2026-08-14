import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../ads/presentation/widgets/native_ad_card.dart';
import '../widgets/feed_post_card.dart';
import '../widgets/youtube_video_card.dart';
import '../providers/feed_provider.dart';

// ── Tab definitions ────────────────────────────────────────────
class _HubTab {
  const _HubTab({required this.label, required this.hubType, this.subHubs = const []});
  final String label;
  final String hubType;
  final List<_SubFilter> subHubs;
}

class _SubFilter {
  const _SubFilter({required this.label, required this.hubType});
  final String label;
  final String hubType;
}

const _tabs = [
  _HubTab(label: 'All', hubType: AppConstants.hubAll),
  _HubTab(
    label: 'Faith',
    hubType: AppConstants.hubFaith,
    subHubs: [
      _SubFilter(label: 'Christianity', hubType: AppConstants.hubChristianity),
      _SubFilter(label: 'Islam', hubType: AppConstants.hubIslam),
    ],
  ),
  _HubTab(
    label: 'Sciences',
    hubType: AppConstants.hubScience,
    subHubs: [
      _SubFilter(label: 'Biology', hubType: AppConstants.hubBiology),
      _SubFilter(label: 'Chemistry', hubType: AppConstants.hubChemistry),
      _SubFilter(label: 'Physics', hubType: AppConstants.hubPhysics),
      _SubFilter(label: 'Mathematics', hubType: AppConstants.hubMathematics),
      _SubFilter(label: 'Psychology', hubType: AppConstants.hubPsychology),
      _SubFilter(label: 'Geography', hubType: AppConstants.hubGeography),
      _SubFilter(label: 'History', hubType: AppConstants.hubHistory),
    ],
  ),
  _HubTab(
    label: 'Technology',
    hubType: AppConstants.hubTechnology,
    subHubs: [
      _SubFilter(label: 'Engineering', hubType: AppConstants.hubEngineering),
      _SubFilter(label: 'Robotics', hubType: AppConstants.hubRobotics),
      _SubFilter(label: 'Aviation', hubType: AppConstants.hubAviation),
      _SubFilter(label: 'Computer Science', hubType: AppConstants.hubComputerScience),
    ],
  ),
  _HubTab(
    label: 'Languages',
    hubType: AppConstants.hubLanguages,
    subHubs: [
      _SubFilter(label: 'French', hubType: AppConstants.hubFrench),
      _SubFilter(label: 'English', hubType: AppConstants.hubEnglish),
      _SubFilter(label: 'Spanish', hubType: AppConstants.hubSpanish),
      _SubFilter(label: 'German', hubType: AppConstants.hubGerman),
      _SubFilter(label: 'Swahili', hubType: AppConstants.hubSwahili),
      _SubFilter(label: 'Chinese', hubType: AppConstants.hubChinese),
      _SubFilter(label: 'Japanese', hubType: AppConstants.hubJapanese),
      _SubFilter(label: 'Arabic', hubType: AppConstants.hubArabic),
    ],
  ),
];

// ── Home Screen ────────────────────────────────────────────────
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Selected sub-filter per tab index (null = show parent hub)
  final Map<int, String?> _subFilter = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _effectiveHub(int tabIndex) {
    return _subFilter[tabIndex] ?? _tabs[tabIndex].hubType;
  }

  @override
  Widget build(BuildContext context) {
    final tabIdx = _tabController.index;
    final currentTab = _tabs[tabIdx];
    final hasSubFilters = currentTab.subHubs.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, _) => [
          _HomeAppBar(
            onSearchTap: () => context.go(AppRoutes.search),
            onCommunitiesTap: () => context.go(AppRoutes.communities),
            onMarketplaceTap: () => context.push(AppRoutes.marketplace),
            onPortfolioTap: () => context.push(AppRoutes.myPortfolio),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _HubTabBarDelegate(
              controller: _tabController,
              extraHeight: hasSubFilters ? 48.0 : 0.0,
              subFilters: hasSubFilters ? currentTab.subHubs : const [],
              selectedSub: _subFilter[tabIdx],
              onSubSelected: (hubType) {
                setState(() {
                  // Toggle off if already selected
                  _subFilter[tabIdx] =
                      _subFilter[tabIdx] == hubType ? null : hubType;
                });
              },
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: List.generate(
            _tabs.length,
            (i) => _FeedTabWrapper(
              tabIndex: i,
              effectiveHub: _effectiveHub(i),
            ),
          ),
        ),
      ),
    );
  }
}

// Simple wrapper that reads the effective hub from parent via index
class _FeedTabWrapper extends StatelessWidget {
  const _FeedTabWrapper({required this.tabIndex, required this.effectiveHub});
  final int tabIndex;
  final String effectiveHub;

  @override
  Widget build(BuildContext context) => _FeedTab(hubType: effectiveHub);
}

// ── App Bar ────────────────────────────────────────────────────
// Icon-only row (no wordmark — the app icon alone anchors the brand and
// frees up room for the marketplace/portfolio entry points):
// communities · marketplace · app icon · portfolio · search.
// Built as a single full-width Row in `title` (leading/actions left
// empty) rather than SliverAppBar's leading+actions slots, so the exact
// left-to-right order above is guaranteed instead of being at the mercy
// of how those slots happen to lay out.
class _HomeAppBar extends SliverAppBar {
  _HomeAppBar({
    required VoidCallback onSearchTap,
    required VoidCallback onCommunitiesTap,
    required VoidCallback onMarketplaceTap,
    required VoidCallback onPortfolioTap,
  }) : super(
    backgroundColor: AppColors.darkBackground,
    floating: true,
    snap: true,
    elevation: 0,
    scrolledUnderElevation: 0,
    toolbarHeight: 56,
    automaticallyImplyLeading: false,
    titleSpacing: 12,
    title: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          icon: const Icon(Icons.groups_2_rounded, color: Colors.white70, size: 26),
          tooltip: 'Communities',
          onPressed: onCommunitiesTap,
          padding: EdgeInsets.zero,
        ),
        IconButton(
          icon: const Icon(Icons.storefront_rounded, color: Colors.white70, size: 25),
          tooltip: 'Marketplace',
          onPressed: onMarketplaceTap,
          padding: EdgeInsets.zero,
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/icons/app_icon.png',
            width: 30,
            height: 30,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.badge_outlined, color: Colors.white70, size: 25),
          tooltip: 'Portfolio',
          onPressed: onPortfolioTap,
          padding: EdgeInsets.zero,
        ),
        IconButton(
          icon: const Icon(Icons.search_rounded, color: Colors.white70, size: 24),
          onPressed: onSearchTap,
          tooltip: 'Search',
          padding: EdgeInsets.zero,
        ),
      ],
    ),
    // Notifications bell removed from the top app bar — it's duplicated
    // with the bell already in the bottom nav bar (main_shell.dart).
    // "Go Live" removed along with the live-streaming feature (still
    // present under lib/features/live/, just unlinked from nav).
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(0),
      child: Divider(height: 0, color: AppColors.darkBorder),
    ),
  );
}

// ── Hub Tab Bar ────────────────────────────────────────────────
class _HubTabBarDelegate extends SliverPersistentHeaderDelegate {
  const _HubTabBarDelegate({
    required this.controller,
    required this.extraHeight,
    required this.subFilters,
    required this.selectedSub,
    required this.onSubSelected,
  });

  final TabController controller;
  final double extraHeight;
  final List<_SubFilter> subFilters;
  final String? selectedSub;
  final ValueChanged<String> onSubSelected;

  static const double _tabBarHeight = 48;

  @override
  double get minExtent => _tabBarHeight + extraHeight;
  @override
  double get maxExtent => _tabBarHeight + extraHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.darkBackground,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Main tab bar
          SizedBox(
            height: _tabBarHeight,
            child: TabBar(
              controller: controller,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelStyle: AppTextStyles.labelLarge
                  .copyWith(fontWeight: FontWeight.w700),
              unselectedLabelStyle: AppTextStyles.labelLarge,
              labelColor: AppColors.secondary,
              unselectedLabelColor: AppColors.textDarkSecondary,
              indicator: const UnderlineTabIndicator(
                borderSide:
                    BorderSide(color: AppColors.secondary, width: 2),
                insets: EdgeInsets.symmetric(horizontal: 8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tabs: _tabs
                  .map((t) => Tab(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(t.label),
                        ),
                      ))
                  .toList(),
            ),
          ),

          // Sub-filter chip row
          if (subFilters.isNotEmpty)
            SizedBox(
              height: extraHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                itemCount: subFilters.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final sub = subFilters[i];
                  final isSelected = selectedSub == sub.hubType;
                  return GestureDetector(
                    onTap: () => onSubSelected(sub.hubType),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.secondary
                            : AppColors.darkSurface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.secondary
                              : AppColors.darkBorder,
                        ),
                      ),
                      child: Text(
                        sub.label,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.black
                              : AppColors.textDarkSecondary,
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HubTabBarDelegate old) =>
      old.extraHeight != extraHeight ||
      old.selectedSub != selectedSub ||
      old.subFilters != subFilters;
}

// ── Feed Tab (with infinite scroll) ───────────────────────────
class _FeedTab extends ConsumerStatefulWidget {
  const _FeedTab({required this.hubType});
  final String hubType;

  @override
  ConsumerState<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<_FeedTab>
    with AutomaticKeepAliveClientMixin<_FeedTab> {
  bool _isLoadingMore = false;
  bool _loadGuard = false; // synchronous guard — prevents duplicate calls before setState

  // Without this, TabBarView disposes off-screen tabs by default —
  // switching hub tabs would throw away the loaded feed, reset scroll
  // position, and re-fetch every time you come back to a tab.
  @override
  bool get wantKeepAlive => true;

  Future<void> _loadMore() async {
    if (_loadGuard) return;
    _loadGuard = true;
    setState(() => _isLoadingMore = true);
    try {
      await ref.read(feedProvider(widget.hubType).notifier).loadMore();
    } finally {
      _loadGuard = false;
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollUpdateNotification && n.depth == 0) {
      final m = n.metrics;
      if (m.pixels >= m.maxScrollExtent - 300) _loadMore();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final feedAsync = ref.watch(feedProvider(widget.hubType));

    return feedAsync.when(
      loading: () => _FeedSkeleton(),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
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
              const SizedBox(height: 6),
              Text(
                err.toString(),
                style: AppTextStyles.bodySmall
                    .copyWith(color: AppColors.textDarkTertiary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(feedProvider(widget.hubType)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (items) => RefreshIndicator(
        color: AppColors.secondary,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () async => ref.invalidate(feedProvider(widget.hubType)),
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScrollNotification,
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 20),
            // The leading LiveStreamsRow (and its "+1" item/index offset)
            // was removed along with the live-streaming feature; see the
            // note on the "Go Live" button above.
            itemCount: items.length + (_isLoadingMore ? 1 : 0),
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.darkBorder),
            itemBuilder: (ctx, i) {
              final itemIndex = i;
              if (itemIndex == items.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
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
              final item = items[itemIndex];
              if (item.isAd) {
                return const NativeAdCard();
              }
              if (item.isYouTube) {
                final allVideos = items
                    .where((it) => it.isYouTube)
                    .map((it) => it.youtubeVideo!)
                    .toList();
                final vidIndex = allVideos.indexOf(item.youtubeVideo!);
                return YouTubeVideoCard(
                  video: item.youtubeVideo!,
                  allVideos: allVideos,
                  index: vidIndex,
                );
              }
              return FeedPostCard(
                post: item.post!,
                hubType: widget.hubType,
                isBoosted: item.isBoosted,
              );
            },
          ),
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
    return const Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _Shimmer(width: 36, height: 36, radius: 18),
            SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Shimmer(width: 120, height: 12),
              SizedBox(height: 4),
              _Shimmer(width: 80, height: 10),
            ]),
          ]),
          SizedBox(height: 12),
          _Shimmer(width: double.infinity, height: 200),
          SizedBox(height: 10),
          _Shimmer(width: 200, height: 12),
          SizedBox(height: 6),
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
          color: AppColors.darkSurface2.withValues(alpha: _anim.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

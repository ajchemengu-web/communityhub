import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/youtube_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../home/domain/models/post_model.dart';
import 'search_provider.dart';
import '../data/search_repository.dart';

// ─────────────────────────────────────────────────────────────────
// Trending topics — shown as quick chips on the discover page
// ─────────────────────────────────────────────────────────────────

const _trendingTopics = [
  ('🔥', 'Faith'),
  ('💼', 'Career'),
  ('🤖', 'Technology'),
  ('🔬', 'Science'),
  ('🌍', 'Culture'),
  ('📖', 'Education'),
  ('⚽', 'Sports'),
  ('🎵', 'Music'),
];

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  late final TabController _tabCtrl;
  Timer? _debounce;
  bool _hasFocus = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        ref.read(searchProvider.notifier).setTab(
              SearchTab.values[_tabCtrl.index],
            );
      }
    });
    _focusNode.addListener(() {
      setState(() => _hasFocus = _focusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    _tabCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () {
      ref.read(searchProvider.notifier).search(q);
    });
  }

  void _submitSearch(String q) {
    if (q.trim().isEmpty) return;
    _focusNode.unfocus();
    ref.read(searchProvider.notifier).search(q);
  }

  void _applyQuery(String q) {
    _searchCtrl.text = q;
    _searchCtrl.selection =
        TextSelection.collapsed(offset: q.length);
    ref.read(searchProvider.notifier).search(q);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final showRecent =
        _hasFocus && !state.hasQuery && state.recentSearches.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Search bar ────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focusNode,
                      onChanged: _onQueryChanged,
                      onSubmitted: _submitSearch,
                      textInputAction: TextInputAction.search,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search posts, people, communities…',
                        hintStyle:
                            const TextStyle(color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.textMuted),
                        suffixIcon: state.query.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close,
                                    size: 18,
                                    color: AppColors.textMuted),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  ref
                                      .read(searchProvider.notifier)
                                      .clear();
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.darkSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ),
                  if (_hasFocus) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        _searchCtrl.clear();
                        ref.read(searchProvider.notifier).clear();
                        _focusNode.unfocus();
                      },
                      child: Text('Cancel',
                          style: AppTextStyles.labelMedium
                              .copyWith(color: AppColors.primary)),
                    ),
                  ],
                ],
              ),
            ),

            // ── Tabs (only when searching) ────────────────────
            if (state.hasQuery && !state.isSearching) ...[
              const SizedBox(height: 8),
              TabBar(
                controller: _tabCtrl,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: AppTextStyles.labelMedium
                    .copyWith(fontWeight: FontWeight.w600),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                tabs: [
                  Tab(
                      child: _TabLabel('Posts',
                          count: state.postResults.length)),
                  Tab(
                      child: _TabLabel('Videos',
                          count: state.videoResults.length)),
                  Tab(
                      child: _TabLabel('People',
                          count: state.userResults.length)),
                  Tab(
                      child: _TabLabel('Communities',
                          count: state.communityResults.length)),
                ],
              ),
            ],

            // ── Body ──────────────────────────────────────────
            Expanded(
              child: state.isSearching
                  ? const Center(child: CircularProgressIndicator())
                  : showRecent
                      ? _RecentSearches(
                          searches: state.recentSearches,
                          onTap: _applyQuery,
                          onRemove: (s) => ref
                              .read(searchProvider.notifier)
                              .removeRecentSearch(s),
                          onClearAll: () => ref
                              .read(searchProvider.notifier)
                              .clearRecentSearches(),
                        )
                      : !state.hasQuery
                          ? _DiscoverView(
                              posts: state.trendingPosts,
                              isLoading: state.isLoadingTrending,
                              onTopicTap: _applyQuery,
                              suggestedUsers: state.suggestedUsers,
                              onFollowTap: (uid) => ref
                                  .read(searchProvider.notifier)
                                  .toggleSuggestedFollow(uid),
                            )
                          : state.totalResults == 0
                              ? _NoResults(query: state.query)
                              : TabBarView(
                                  controller: _tabCtrl,
                                  children: [
                                    _PostResults(
                                        posts: state.postResults),
                                    _VideoResults(
                                        videos: state.videoResults),
                                    _PeopleResults(
                                      users: state.userResults,
                                      onFollowTap: (uid) => ref
                                          .read(searchProvider.notifier)
                                          .toggleFollow(uid),
                                    ),
                                    _CommunityResults(
                                        communities:
                                            state.communityResults),
                                  ],
                                ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tab label with count badge
// ─────────────────────────────────────────────────────────────────

class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Recent Searches
// ─────────────────────────────────────────────────────────────────

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.searches,
    required this.onTap,
    required this.onRemove,
    required this.onClearAll,
  });
  final List<String> searches;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onRemove;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              Text('Recent',
                  style: AppTextStyles.titleSmall
                      .copyWith(color: Colors.white)),
              const Spacer(),
              GestureDetector(
                onTap: onClearAll,
                child: Text('Clear all',
                    style: AppTextStyles.labelSmall
                        .copyWith(color: AppColors.primary)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: searches.length,
            itemBuilder: (_, i) => ListTile(
              leading: const Icon(Icons.history,
                  color: AppColors.textMuted, size: 20),
              title: Text(searches[i],
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: Colors.white)),
              trailing: GestureDetector(
                onTap: () => onRemove(searches[i]),
                child: const Icon(Icons.close,
                    size: 16, color: AppColors.textMuted),
              ),
              onTap: () => onTap(searches[i]),
              dense: true,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Discover View (no query)
// ─────────────────────────────────────────────────────────────────

class _DiscoverView extends StatelessWidget {
  const _DiscoverView({
    required this.posts,
    required this.isLoading,
    required this.onTopicTap,
    required this.suggestedUsers,
    required this.onFollowTap,
  });
  final List<PostModel> posts;
  final bool isLoading;
  final ValueChanged<String> onTopicTap;
  final List<UserResult> suggestedUsers;
  final ValueChanged<String> onFollowTap;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomScrollView(
      slivers: [
        // ── Topic chips ──────────────────────────────────────
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Text('Explore topics',
                    style: AppTextStyles.titleSmall
                        .copyWith(color: Colors.white)),
              ),
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _trendingTopics.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final (emoji, label) = _trendingTopics[i];
                    return GestureDetector(
                      onTap: () => onTopicTap(label),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.darkSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.darkDivider),
                        ),
                        child: Text('$emoji  $label',
                            style: AppTextStyles.labelMedium
                                .copyWith(color: Colors.white)),
                      ),
                    );
                  },
                ),
              ),
              // ── Suggested users ─────────────────────────────
              if (suggestedUsers.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.people_alt_rounded,
                          color: AppColors.primary, size: 18),
                      const SizedBox(width: 6),
                      Text('Suggested for you',
                          style: AppTextStyles.titleSmall
                              .copyWith(color: Colors.white)),
                    ],
                  ),
                ),
                SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: suggestedUsers.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final u = suggestedUsers[i];
                      return _SuggestedUserCard(
                        user: u,
                        onFollowTap: () => onFollowTap(u.id),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Icon(Icons.local_fire_department_rounded,
                        color: AppColors.secondary, size: 18),
                    const SizedBox(width: 6),
                    Text('Trending this week',
                        style: AppTextStyles.titleSmall
                            .copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Trending grid ─────────────────────────────────────
        posts.isEmpty
            ? const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      'No trending content yet.\nSearch for a topic to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: AppColors.textMuted, height: 1.5),
                    ),
                  ),
                ),
              )
            : SliverGrid(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _GridTile(post: posts[i]),
                  childCount: posts.length,
                ),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 2,
                  mainAxisSpacing: 2,
                ),
              ),
      ],
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.post});
  final PostModel post;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/post/${post.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Media or text background
          post.mediaUrls.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: post.mediaUrls.first,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: AppColors.darkSurface),
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
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 10),
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

          // Video indicator
          if (post.isVideo)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.play_circle_filled,
                  color: Colors.white, size: 18,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
            ),

          // Multi-image indicator
          if (post.isMultiMedia)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.collections_rounded,
                  color: Colors.white, size: 16,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)]),
            ),

          // Likes overlay at bottom
          if (post.likesCount > 0)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 4),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 11),
                    const SizedBox(width: 3),
                    Text(
                      _fmt(post.likesCount),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────
// No Results
// ─────────────────────────────────────────────────────────────────

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 56, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text('No results for "$query"',
                style: AppTextStyles.titleSmall
                    .copyWith(color: Colors.white),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'Try different keywords, check spelling,\nor search for a broader topic.',
              style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textMuted, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Post Results
// ─────────────────────────────────────────────────────────────────

class _PostResults extends StatelessWidget {
  const _PostResults({required this.posts});
  final List<PostModel> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return const _EmptyTab(
          icon: Icons.article_outlined, label: 'No posts found');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: posts.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.darkDivider, height: 1),
      itemBuilder: (ctx, i) {
        final p = posts[i];
        return InkWell(
          onTap: () => context.push('/post/${p.id}'),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 20,
                  backgroundImage: p.avatarUrl != null
                      ? CachedNetworkImageProvider(p.avatarUrl!)
                      : null,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.2),
                  child: p.avatarUrl == null
                      ? const Icon(Icons.person,
                          color: AppColors.primary, size: 18)
                      : null,
                ),
                const SizedBox(width: 10),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(p.displayName,
                              style: AppTextStyles.labelMedium
                                  .copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                          if (p.isVerified) ...[
                            const SizedBox(width: 3),
                            const Icon(Icons.verified,
                                size: 12,
                                color: AppColors.primary),
                          ],
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(p.hubType,
                                style: AppTextStyles.labelSmall
                                    .copyWith(
                                        color: AppColors.primary,
                                        fontSize: 9)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(p.caption,
                          style: AppTextStyles.bodySmall
                              .copyWith(
                                  color: Colors.white70, height: 1.4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.favorite_border_rounded,
                              size: 13, color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text('${p.likesCount}',
                              style: AppTextStyles.labelSmall
                                  .copyWith(
                                      color: AppColors.textMuted)),
                          const SizedBox(width: 12),
                          const Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 13,
                              color: AppColors.textMuted),
                          const SizedBox(width: 3),
                          Text('${p.commentsCount}',
                              style: AppTextStyles.labelSmall
                                  .copyWith(
                                      color: AppColors.textMuted)),
                        ],
                      ),
                    ],
                  ),
                ),
                // Thumbnail
                if (p.mediaUrls.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: p.mediaUrls.first,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Video Results
// ─────────────────────────────────────────────────────────────────

class _VideoResults extends StatelessWidget {
  const _VideoResults({required this.videos});
  final List<YouTubeVideo> videos;

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) {
      return const _EmptyTab(
          icon: Icons.play_circle_outline, label: 'No videos found');
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (ctx, i) {
        final v = videos[i];
        return GestureDetector(
          onTap: () => context.push('/reels', extra: {
            'videos': videos,
            'index': i,
          }),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: v.thumbnailUrl,
                      width: 130,
                      height: 78,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          width: 130,
                          height: 78,
                          color: AppColors.darkSurface),
                      errorWidget: (_, __, ___) => Container(
                          width: 130,
                          height: 78,
                          color: AppColors.darkSurface,
                          child: const Icon(Icons.play_circle_outline,
                              color: AppColors.textMuted)),
                    ),
                    // Red YouTube play button
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: 34,
                          height: 24,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF0000),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v.title,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: Colors.white, height: 1.3),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(v.channelTitle,
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textMuted)),
                    if (v.viewCount != null) ...[
                      const SizedBox(height: 2),
                      Text(_formatViews(v.viewCount!),
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textMuted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatViews(int n) {
    if (n >= 1000000) { return '${(n / 1000000).toStringAsFixed(1)}M views'; }
    if (n >= 1000) { return '${(n / 1000).toStringAsFixed(0)}K views'; }
    return '$n views';
  }
}

// ─────────────────────────────────────────────────────────────────
// People Results
// ─────────────────────────────────────────────────────────────────

class _PeopleResults extends StatelessWidget {
  const _PeopleResults({
    required this.users,
    required this.onFollowTap,
  });
  final List<UserResult> users;
  final ValueChanged<String> onFollowTap;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const _EmptyTab(
          icon: Icons.person_search_rounded, label: 'No people found');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.darkDivider),
      itemBuilder: (ctx, i) {
        final u = users[i];
        return InkWell(
          onTap: () => context.push('/user/${u.id}'),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundImage: u.avatarUrl != null
                      ? CachedNetworkImageProvider(u.avatarUrl!)
                      : null,
                  backgroundColor:
                      AppColors.primary.withValues(alpha: 0.2),
                  child: u.avatarUrl == null
                      ? const Icon(Icons.person,
                          color: AppColors.primary, size: 22)
                      : null,
                ),
                const SizedBox(width: 12),
                // Name + username
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(u.displayName,
                              style: AppTextStyles.bodyMedium
                                  .copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                          if (u.isVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 14, color: AppColors.primary),
                          ],
                        ],
                      ),
                      Text('@${u.username}',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.textMuted)),
                    ],
                  ),
                ),
                // Follow button
                GestureDetector(
                  onTap: () => onFollowTap(u.id),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: u.isFollowing
                          ? Colors.transparent
                          : AppColors.primary,
                      border: Border.all(
                        color: u.isFollowing
                            ? AppColors.darkDivider
                            : AppColors.primary,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      u.isFollowing ? 'Following' : 'Follow',
                      style: AppTextStyles.labelMedium.copyWith(
                        color: u.isFollowing
                            ? AppColors.textMuted
                            : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Community Results
// ─────────────────────────────────────────────────────────────────

class _CommunityResults extends StatelessWidget {
  const _CommunityResults({required this.communities});
  final List<CommunityResult> communities;

  @override
  Widget build(BuildContext context) {
    if (communities.isEmpty) {
      return const _EmptyTab(
          icon: Icons.groups_rounded, label: 'No communities found');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: communities.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.darkDivider),
      itemBuilder: (ctx, i) {
        final c = communities[i];
        return InkWell(
          onTap: () => context.push('/community/${c.id}'),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                // Cover
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: c.coverUrl != null
                      ? CachedNetworkImage(
                          imageUrl: c.coverUrl!,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          width: 50,
                          height: 50,
                          color: AppColors.primary
                              .withValues(alpha: 0.2),
                          child: const Icon(Icons.groups_rounded,
                              color: AppColors.primary, size: 26),
                        ),
                ),
                const SizedBox(width: 12),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: AppTextStyles.bodyMedium
                              .copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        '${_format(c.memberCount)} members'
                        '${c.hubType != null ? ' · ${c.hubType}' : ''}',
                        style: AppTextStyles.labelSmall
                            .copyWith(color: AppColors.textMuted),
                      ),
                      if (c.description != null &&
                          c.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(c.description!,
                            style: AppTextStyles.labelSmall.copyWith(
                                color: AppColors.textMuted
                                    .withValues(alpha: 0.7)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: AppColors.textMuted),
              ],
            ),
          ),
        );
      },
    );
  }

  String _format(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────
// Suggested user card (horizontal scroll in discover)
// ─────────────────────────────────────────────────────────────────

class _SuggestedUserCard extends StatelessWidget {
  const _SuggestedUserCard({required this.user, required this.onFollowTap});
  final UserResult user;
  final VoidCallback onFollowTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/user/${user.id}'),
      child: Container(
        width: 110,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.darkDivider),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 24,
              backgroundImage: user.avatarUrl != null
                  ? CachedNetworkImageProvider(user.avatarUrl!)
                  : null,
              backgroundColor: AppColors.primary.withValues(alpha: 0.2),
              child: user.avatarUrl == null
                  ? const Icon(Icons.person,
                      color: AppColors.primary, size: 22)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              user.displayName,
              style: AppTextStyles.labelSmall
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onFollowTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: user.isFollowing
                      ? Colors.transparent
                      : AppColors.primary,
                  border: Border.all(
                    color: user.isFollowing
                        ? AppColors.darkDivider
                        : AppColors.primary,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  user.isFollowing ? 'Following' : 'Follow',
                  style: AppTextStyles.labelSmall.copyWith(
                    color:
                        user.isFollowing ? AppColors.textMuted : Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Empty tab placeholder
// ─────────────────────────────────────────────────────────────────

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(label,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

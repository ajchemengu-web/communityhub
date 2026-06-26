import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../home/domain/models/post_model.dart';
import 'search_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        ref.read(searchProvider.notifier).setTab(
              SearchTab.values[_tabCtrl.index],
            );
      }
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
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(searchProvider.notifier).search(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: Column(
          children: [
            // ── Search Bar ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _focusNode,
                      onChanged: _onQueryChanged,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        hintText:
                            'Search people, posts, communities…',
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted),
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
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Tabs (when query entered) ─────────────────
            if (state.hasQuery) ...[
              const SizedBox(height: 8),
              TabBar(
                controller: _tabCtrl,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textMuted,
                indicatorColor: AppColors.primary,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: AppTextStyles.labelMedium,
                tabs: const [
                  Tab(text: 'Posts'),
                  Tab(text: 'People'),
                  Tab(text: 'Communities'),
                ],
              ),
            ],

            // ── Body ──────────────────────────────────────
            Expanded(
              child: state.isSearching
                  ? const Center(
                      child: CircularProgressIndicator(),
                    )
                  : !state.hasQuery
                      ? _TrendingGrid(
                          posts: state.trendingPosts,
                          isLoading: state.isLoadingTrending,
                        )
                      : TabBarView(
                          controller: _tabCtrl,
                          children: [
                            _PostResults(posts: state.postResults),
                            _PeopleResults(users: state.userResults),
                            _CommunityResults(
                                communities: state.communityResults),
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
// Trending Grid
// ─────────────────────────────────────────────────────────────────

class _TrendingGrid extends StatelessWidget {
  const _TrendingGrid(
      {required this.posts, required this.isLoading});
  final List<PostModel> posts;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.local_fire_department_rounded,
                    color: AppColors.secondary, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Trending this week',
                  style: AppTextStyles.titleSmall
                      .copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
        posts.isEmpty
            ? SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 48),
                    child: Text(
                      'No trending posts yet',
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: AppColors.textMuted),
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
      child: post.mediaUrls.isNotEmpty
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
              padding: const EdgeInsets.all(6),
              child: Text(
                post.caption,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 10),
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
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
      return _EmptyResults(label: 'No posts found');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: posts.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.darkDivider),
      itemBuilder: (ctx, i) {
        final p = posts[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 20,
            backgroundImage: p.avatarUrl != null
                ? CachedNetworkImageProvider(p.avatarUrl!)
                : null,
            backgroundColor: AppColors.primary.withOpacity(0.2),
            child: p.avatarUrl == null
                ? const Icon(Icons.person, color: AppColors.primary, size: 18)
                : null,
          ),
          title: Text(
            p.caption,
            style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            p.displayName,
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textMuted),
          ),
          trailing: p.mediaUrls.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: p.mediaUrls.first,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                )
              : null,
          onTap: () => context.push('/post/${p.id}'),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// People Results
// ─────────────────────────────────────────────────────────────────

class _PeopleResults extends StatelessWidget {
  const _PeopleResults({required this.users});
  final List<UserResult> users;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) return _EmptyResults(label: 'No people found');
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.darkDivider),
      itemBuilder: (ctx, i) {
        final u = users[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            radius: 22,
            backgroundImage: u.avatarUrl != null
                ? CachedNetworkImageProvider(u.avatarUrl!)
                : null,
            backgroundColor: AppColors.primary.withOpacity(0.2),
            child: u.avatarUrl == null
                ? const Icon(Icons.person,
                    color: AppColors.primary, size: 20)
                : null,
          ),
          title: Row(
            children: [
              Text(
                u.displayName,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: Colors.white),
              ),
              if (u.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified,
                    size: 14, color: AppColors.primary),
              ],
            ],
          ),
          subtitle: Text(
            '@${u.username}',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textMuted),
          ),
          trailing: OutlinedButton(
            onPressed: () => context.push('/user/${u.id}'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary.withOpacity(0.5)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(u.isFollowing ? 'Following' : 'Follow',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.primary)),
          ),
          onTap: () => context.push('/user/${u.id}'),
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
      return _EmptyResults(label: 'No communities found');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: communities.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppColors.darkDivider),
      itemBuilder: (ctx, i) {
        final c = communities[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: c.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: c.coverUrl!,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 44,
                    height: 44,
                    color: AppColors.primary.withOpacity(0.2),
                    child: const Icon(Icons.groups_rounded,
                        color: AppColors.primary, size: 24),
                  ),
          ),
          title: Text(
            c.name,
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
          ),
          subtitle: Text(
            '${_format(c.memberCount)} members · ${c.hubType ?? ''}',
            style: AppTextStyles.labelSmall
                .copyWith(color: AppColors.textMuted),
          ),
          trailing: const Icon(Icons.chevron_right,
              color: AppColors.textMuted),
          onTap: () => context.push('/community/${c.id}'),
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
// Empty State
// ─────────────────────────────────────────────────────────────────

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded,
              size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            label,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/community_model.dart';
import '../providers/communities_provider.dart';

class CommunitiesScreen extends ConsumerStatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  ConsumerState<CommunitiesScreen> createState() =>
      _CommunitiesScreenState();
}

class _CommunitiesScreenState extends ConsumerState<CommunitiesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(communitiesProvider.notifier).setSearch(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communitiesProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (ctx, _) => [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── Top bar ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                    child: Row(
                      children: [
                        Text(
                          'Communities',
                          style: AppTextStyles.titleLarge.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: AppColors.primary),
                          onPressed: () =>
                              context.push(AppRoutes.createCommunity),
                          tooltip: 'Create community',
                        ),
                      ],
                    ),
                  ),

                  // ── Search ─────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearch,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search communities…',
                        hintStyle: const TextStyle(
                            color: AppColors.textMuted),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: AppColors.textMuted),
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

                  // ── Hub filter chips ───────────────────
                  _HubFilterChips(
                    selected: state.activeHubFilter,
                    onSelected: (h) => ref
                        .read(communitiesProvider.notifier)
                        .setHubFilter(h),
                  ),
                  const SizedBox(height: 4),

                  // ── Tab bar ────────────────────────────
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
                            const Text('My Communities'),
                            if (state.myCommunities.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _CountBadge(
                                  count: state.myCommunities.length),
                            ],
                          ],
                        ),
                      ),
                      const Tab(text: 'Discover'),
                    ],
                  ),
                ],
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabCtrl,
            children: [
              // ── My Communities ─────────────────────────
              _MyCommunitiesTab(state: state),

              // ── Discover ───────────────────────────────
              _DiscoverTab(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Hub Filter Chips
// ─────────────────────────────────────────────────────────────────

class _HubFilterChips extends StatelessWidget {
  const _HubFilterChips(
      {required this.selected, required this.onSelected});
  final String selected;
  final ValueChanged<String> onSelected;

  static const _options = [
    ('all', 'All', Icons.public_rounded),
    ('faith', 'Faith', Icons.church_rounded),
    ('career', 'Career', Icons.work_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: _options.map((o) {
          final isSelected = o.$1 == selected;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FilterChip(
              selected: isSelected,
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(o.$3,
                      size: 14,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textMuted),
                  const SizedBox(width: 4),
                  Text(o.$2),
                ],
              ),
              labelStyle: AppTextStyles.labelMedium.copyWith(
                color: isSelected ? Colors.white : AppColors.textMuted,
              ),
              backgroundColor: AppColors.darkSurface,
              selectedColor: AppColors.primary,
              checkmarkColor: Colors.white,
              showCheckmark: false,
              side: BorderSide(
                color: isSelected
                    ? AppColors.primary
                    : AppColors.darkBorder,
              ),
              onSelected: (_) => onSelected(o.$1),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// My Communities Tab
// ─────────────────────────────────────────────────────────────────

class _MyCommunitiesTab extends ConsumerWidget {
  const _MyCommunitiesTab({required this.state});
  final CommunitiesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.isLoadingMine) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.myCommunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.groups_rounded,
                size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'You haven\'t joined any communities yet',
              style: AppTextStyles.titleSmall
                  .copyWith(color: AppColors.textMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Discover faith & career communities\nand connect with your people.',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textDarkTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.push(AppRoutes.createCommunity),
              icon: const Icon(Icons.add),
              label: const Text('Create Community'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () =>
          ref.read(communitiesProvider.notifier).refresh(),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.myCommunities.length,
        itemBuilder: (ctx, i) => _CommunityListTile(
          community: state.myCommunities[i],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Discover Tab
// ─────────────────────────────────────────────────────────────────

class _DiscoverTab extends StatelessWidget {
  const _DiscoverTab({required this.state});
  final CommunitiesState state;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingDiscover) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.discoverCommunities.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded,
                size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              'No communities found',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textMuted),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: state.discoverCommunities.length,
      itemBuilder: (ctx, i) =>
          _CommunityCard(community: state.discoverCommunities[i]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Community List Tile (My Communities)
// ─────────────────────────────────────────────────────────────────

class _CommunityListTile extends StatelessWidget {
  const _CommunityListTile({required this.community});
  final CommunityModel community;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      onTap: () => context.push('/community/${community.id}'),
      leading: _CommunityAvatar(
        coverUrl: community.coverUrl,
        avatarUrl: community.avatarUrl,
        size: 48,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              community.name,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (community.isVerified) ...[
            const SizedBox(width: 4),
            const Icon(Icons.verified, size: 14, color: AppColors.primary),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 2),
          Row(
            children: [
              _HubBadge(hubType: community.hubType),
              const SizedBox(width: 6),
              if (community.isPrivate)
                const Icon(Icons.lock_outline,
                    size: 12, color: AppColors.textMuted),
              const SizedBox(width: 2),
              Text(
                '${_formatCount(community.membersCount)} members',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
          if (community.userRole != null) ...[
            const SizedBox(height: 2),
            _RoleBadge(role: community.userRole!),
          ],
        ],
      ),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Community Card (Discover Grid)
// ─────────────────────────────────────────────────────────────────

class _CommunityCard extends ConsumerWidget {
  const _CommunityCard({required this.community});
  final CommunityModel community;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => context.push('/community/${community.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Cover image ────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
              child: community.coverUrl != null &&
                      community.coverUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: community.coverUrl!,
                      height: 90,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        height: 90,
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                      errorWidget: (_, __, ___) => _PlaceholderCover(
                          hubType: community.hubType),
                    )
                  : _PlaceholderCover(hubType: community.hubType),
            ),

            // ── Content ───────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            community.name,
                            style: AppTextStyles.labelMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (community.isVerified)
                          const Icon(Icons.verified,
                              size: 12, color: AppColors.primary),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatCount(community.membersCount)} members',
                      style: AppTextStyles.labelSmall
                          .copyWith(color: AppColors.textMuted),
                    ),
                    const Spacer(),
                    _HubBadge(hubType: community.hubType),
                    const SizedBox(height: 6),
                    // Join button
                    SizedBox(
                      width: double.infinity,
                      height: 30,
                      child: community.isMember
                          ? OutlinedButton(
                              onPressed: () => context
                                  .push('/community/${community.id}'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(
                                    color: AppColors.primary),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text('View',
                                  style: AppTextStyles.labelSmall
                                      .copyWith(color: AppColors.primary)),
                            )
                          : FilledButton(
                              onPressed: () => context
                                  .push('/community/${community.id}'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                  community.isPrivate
                                      ? 'Request'
                                      : 'Join',
                                  style: AppTextStyles.labelSmall
                                      .copyWith(color: Colors.white)),
                            ),
                    ),
                  ],
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
// Shared micro-widgets
// ─────────────────────────────────────────────────────────────────

class _CommunityAvatar extends StatelessWidget {
  const _CommunityAvatar(
      {this.coverUrl, this.avatarUrl, this.size = 40});
  final String? coverUrl;
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl ?? coverUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: url != null && url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) =>
                  Container(color: AppColors.primary.withOpacity(0.2)),
              errorWidget: (_, __, ___) => _defaultAvatar(size),
            )
          : _defaultAvatar(size),
    );
  }

  Widget _defaultAvatar(double sz) => Container(
        width: sz,
        height: sz,
        color: AppColors.primary.withOpacity(0.2),
        child: Icon(Icons.groups_rounded,
            color: AppColors.primary, size: sz * 0.5),
      );
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.hubType});
  final String hubType;

  @override
  Widget build(BuildContext context) {
    final color = hubType == 'faith'
        ? AppColors.faithTag
        : hubType == 'career'
            ? AppColors.techTag
            : AppColors.primary;
    return Container(
      height: 90,
      width: double.infinity,
      color: color.withOpacity(0.2),
      child: Icon(
        hubType == 'faith'
            ? Icons.church_rounded
            : hubType == 'career'
                ? Icons.work_rounded
                : Icons.groups_rounded,
        color: color.withOpacity(0.5),
        size: 36,
      ),
    );
  }
}

class _HubBadge extends StatelessWidget {
  const _HubBadge({required this.hubType});
  final String hubType;

  @override
  Widget build(BuildContext context) {
    final color = hubType == 'faith'
        ? AppColors.faithTag
        : hubType == 'career'
            ? AppColors.techTag
            : AppColors.primary;
    final label = hubType == 'faith'
        ? 'Faith'
        : hubType == 'career'
            ? 'Career'
            : 'All';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(color: color),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final color = role == 'admin'
        ? AppColors.secondary
        : role == 'moderator'
            ? AppColors.accent
            : AppColors.textMuted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          role == 'admin'
              ? Icons.shield_rounded
              : role == 'moderator'
                  ? Icons.manage_accounts_rounded
                  : Icons.person_rounded,
          size: 11,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          role[0].toUpperCase() + role.substring(1),
          style: AppTextStyles.labelSmall.copyWith(color: color),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: AppTextStyles.labelSmall
            .copyWith(color: AppColors.primary, fontSize: 10),
      ),
    );
  }
}

String _formatCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}


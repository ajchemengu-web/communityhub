import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';

import '../../../home/domain/models/post_model.dart';
import '../../data/profile_detail_repository.dart';
import '../providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.userId});
  final String? userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late final String _uid;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _uid = widget.userId ?? SupabaseService.currentUserId ?? '';
    _tabCtrl = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: Text('Not logged in',
                style: TextStyle(color: Colors.white))),
      );
    }

    final state = ref.watch(profileProvider(_uid));
    final profile = state.profileData ?? {};
    final username = profile['username'] as String? ?? '';
    final fullName = profile['full_name'] as String? ?? 'User';
    final avatarUrl = profile['avatar_url'] as String?;
    final bio = profile['bio'] as String?;
    final website = profile['website'] as String?;
    final isVerified = (profile['is_verified'] as bool?) ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : NestedScrollView(
              headerSliverBuilder: (ctx, _) => [
                // ── Top App Bar ────────────────────────────────
                SliverToBoxAdapter(
                  child: SafeArea(
                    bottom: false,
                    child: _TopBar(
                      username: username,
                      isOwnProfile: state.isOwnProfile,
                      onBack: context.canPop() ? () => context.pop() : null,
                      onSettings: () => context.push(AppRoutes.settings),
                    ),
                  ),
                ),

                // ── Profile header ─────────────────────────────
                SliverToBoxAdapter(
                  child: _ProfileHeader(
                    fullName: fullName,
                    username: username,
                    avatarUrl: avatarUrl,
                    bio: bio,
                    website: website,
                    isVerified: isVerified,
                    postCount: state.postCount,
                    followerCount: state.followerCount,
                    followingCount: state.followingCount,
                    isOwnProfile: state.isOwnProfile,
                    isFollowing: state.isFollowing,
                    isTogglingFollow: state.isTogglingFollow,
                    onEdit: () => context.push(AppRoutes.editProfile),
                    onShare: () =>
                        Share.share('Check out @$username on CommunityHub!'),
                    onFollow: () =>
                        ref.read(profileProvider(_uid).notifier).toggleFollow(),
                    onMessage: () =>
                        context.push('${AppRoutes.chats}?userId=$_uid'),
                  ),
                ),

                // ── Creator dashboard (own profile) ───────────
                if (state.isOwnProfile)
                  SliverToBoxAdapter(
                    child: _ProfessionalDashboard(uid: _uid),
                  ),

                // ── Tab bar ────────────────────────────────────
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabDelegate(
                    TabBar(
                      controller: _tabCtrl,
                      indicatorColor: Colors.white,
                      indicatorWeight: 1.5,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white38,
                      dividerColor: Colors.white12,
                      tabs: const [
                        Tab(icon: Icon(Icons.grid_on_rounded, size: 22)),
                        Tab(
                            icon: Icon(Icons.play_circle_outline_rounded,
                                size: 22)),
                        Tab(icon: Icon(Icons.repeat_rounded, size: 22)),
                        Tab(
                            icon: Icon(Icons.person_pin_outlined,
                                size: 22)),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                controller: _tabCtrl,
                children: [
                  // ── Posts grid ─────────────────────────────
                  _PostsGrid(
                    state: state,
                    uid: _uid,
                    onTap: (id) => context.push('/post/$id'),
                    onNewPost: () => context.push(AppRoutes.newPost),
                  ),

                  // ── Videos tab ─────────────────────────────
                  _PostsGrid(
                    state: state,
                    uid: _uid,
                    filterVideo: true,
                    onTap: (id) => context.push('/post/$id'),
                    onNewPost: () => context.push(AppRoutes.newPost),
                  ),

                  // ── Reposts ────────────────────────────────
                  _EmptyTab(
                    icon: Icons.repeat_rounded,
                    message: 'No reposts yet',
                  ),

                  // ── Tagged ─────────────────────────────────
                  _EmptyTab(
                    icon: Icons.person_pin_outlined,
                    message: 'No tagged posts',
                  ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Top bar (TikTok-style)
// ─────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.username,
    required this.isOwnProfile,
    required this.onSettings,
    this.onBack,
  });
  final String username;
  final bool isOwnProfile;
  final VoidCallback? onBack;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          // Left: back or add
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
            )
          else
            IconButton(
              icon: const Icon(Icons.add_box_outlined, color: Colors.white, size: 26),
              onPressed: () => context.push(AppRoutes.cameraRecorder),
            ),

          // Center: username + chevron
          Expanded(
            child: GestureDetector(
              onTap: () {},
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      username.isNotEmpty ? username : 'Profile',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.keyboard_arrow_down_rounded,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 2),
                  // Online/active dot
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Right: notification + menu
          if (isOwnProfile) ...[
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.sync_rounded, color: Colors.white),
                  onPressed: () {},
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('9+',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: Colors.white),
              onPressed: onSettings,
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
              onPressed: () {},
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Profile header
// ─────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.fullName,
    required this.username,
    required this.avatarUrl,
    required this.bio,
    required this.website,
    required this.isVerified,
    required this.postCount,
    required this.followerCount,
    required this.followingCount,
    required this.isOwnProfile,
    required this.isFollowing,
    required this.isTogglingFollow,
    required this.onEdit,
    required this.onShare,
    required this.onFollow,
    required this.onMessage,
  });

  final String fullName;
  final String username;
  final String? avatarUrl;
  final String? bio;
  final String? website;
  final bool isVerified;
  final int postCount;
  final int followerCount;
  final int followingCount;
  final bool isOwnProfile;
  final bool isFollowing;
  final bool isTogglingFollow;
  final VoidCallback onEdit;
  final VoidCallback onShare;
  final VoidCallback onFollow;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 8),

        // ── Avatar (centered) ──────────────────────────────────
        Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 46,
                backgroundImage: avatarUrl != null
                    ? CachedNetworkImageProvider(avatarUrl!)
                    : null,
                backgroundColor: Colors.grey.shade800,
                child: avatarUrl == null
                    ? const Icon(Icons.person,
                        color: Colors.white54, size: 46)
                    : null,
              ),
              if (isOwnProfile)
                Positioned(
                  bottom: 0,
                  right: -2,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                    child: const Icon(Icons.add,
                        color: Colors.white, size: 14),
                  ),
                ),
              if (isVerified)
                Positioned(
                  bottom: 0,
                  left: -2,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: Colors.black, width: 1),
                    ),
                    child: const Icon(Icons.verified,
                        color: AppColors.primary, size: 16),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // ── Full name ──────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              fullName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (isVerified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified,
                  color: AppColors.primary, size: 16),
            ],
          ],
        ),

        const SizedBox(height: 12),

        // ── Stats row (centered, TikTok-style) ────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StatCol(count: postCount, label: 'posts'),
            _VertDivider(),
            _StatCol(count: followerCount, label: 'followers'),
            _VertDivider(),
            _StatCol(count: followingCount, label: 'following'),
          ],
        ),

        const SizedBox(height: 12),

        // ── Bio ────────────────────────────────────────────────
        if (bio != null && bio!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              bio!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 13, height: 1.4),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        // ── Username + link chips ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              if (username.isNotEmpty)
                _Chip(
                  icon: Icons.alternate_email_rounded,
                  label: username,
                ),
              if (website != null && website!.isNotEmpty) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => launchUrl(Uri.parse(website!)),
                  child: _Chip(
                    icon: Icons.link_rounded,
                    label: website!,
                    color: AppColors.primary,
                  ),
                ),
              ],
              if (isOwnProfile) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => context.push(AppRoutes.editProfile),
                  child: Row(
                    children: const [
                      Icon(Icons.add,
                          color: Colors.white54, size: 14),
                      SizedBox(width: 2),
                      Text('Add',
                          style: TextStyle(
                              color: Colors.white54, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // ── Action buttons ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: isOwnProfile
              ? Row(
                  children: [
                    Expanded(
                      child: _ActionBtn(
                          label: 'Edit profile', onTap: onEdit),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                          label: 'Share profile', onTap: onShare),
                    ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      icon: Icons.person_add_outlined,
                      onTap: () {},
                      isIcon: true,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: _ActionBtn(
                        label: isFollowing ? 'Following' : 'Follow',
                        onTap: isTogglingFollow ? () {} : onFollow,
                        filled: !isFollowing,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _ActionBtn(
                          label: 'Message', onTap: onMessage),
                    ),
                    const SizedBox(width: 8),
                    _ActionBtn(
                      icon: Icons.keyboard_arrow_down_rounded,
                      onTap: () {},
                      isIcon: true,
                    ),
                  ],
                ),
        ),

        const SizedBox(height: 4),
      ],
    );
  }
}

class _StatCol extends StatelessWidget {
  const _StatCol({required this.count, required this.label});
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Text(
            _fmt(count),
            style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _VertDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 28,
        color: Colors.white12,
      );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, this.color});
  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 13),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: c, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    this.label,
    this.icon,
    required this.onTap,
    this.filled = false,
    this.isIcon = false,
  });
  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool filled;
  final bool isIcon;

  @override
  Widget build(BuildContext context) {
    if (isIcon) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon ?? Icons.more_horiz_rounded,
              color: Colors.white, size: 20),
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            label ?? '',
            style: TextStyle(
              color: filled ? Colors.white : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Professional dashboard (TikTok-style banner)
// ─────────────────────────────────────────────────────────────────

class _ProfessionalDashboard extends ConsumerStatefulWidget {
  const _ProfessionalDashboard({required this.uid});
  final String uid;

  @override
  ConsumerState<_ProfessionalDashboard> createState() =>
      _ProfessionalDashboardState();
}

class _ProfessionalDashboardState
    extends ConsumerState<_ProfessionalDashboard> {
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final stats =
          await ProfileDetailRepository.instance.fetchCreatorStats(widget.uid);
      if (mounted) setState(() => _stats = stats);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final views = _stats?['totalViews'] as int? ?? 0;

    return GestureDetector(
      onTap: () => _showDashboard(context),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF111111),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Professional dashboard',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.trending_up_rounded,
                        color: Color(0xFF4CAF50), size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${_fmt(views)} views in the last 30 days.',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white38),
          ],
        ),
      ),
    );
  }

  void _showDashboard(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _DashboardScreen(stats: _stats),
    ));
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────
// Professional dashboard screen
// ─────────────────────────────────────────────────────────────────

class _DashboardScreen extends StatelessWidget {
  const _DashboardScreen({required this.stats});
  final Map<String, dynamic>? stats;

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final views = stats?['totalViews'] as int? ?? 0;
    final likes = stats?['totalLikes'] as int? ?? 0;
    final comments = stats?['totalComments'] as int? ?? 0;
    final posts = stats?['totalPosts'] as int? ?? 0;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Professional dashboard',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overview section
          const Text('Overview · Last 30 days',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Profile views', value: _fmt(views), icon: Icons.remove_red_eye_outlined, color: Colors.blueAccent)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Likes', value: _fmt(likes), icon: Icons.favorite_border_rounded, color: Colors.pinkAccent)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Comments', value: _fmt(comments), icon: Icons.chat_bubble_outline_rounded, color: Colors.orangeAccent)),
              const SizedBox(width: 12),
              Expanded(child: _StatCard(label: 'Posts', value: _fmt(posts), icon: Icons.grid_on_rounded, color: Colors.greenAccent)),
            ],
          ),
          const SizedBox(height: 24),

          // Audience section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Audience insights',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                const Text('Grow your audience by posting consistently and engaging with your community.',
                    style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Create a post',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Tips section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Creator tips',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                SizedBox(height: 12),
                _TipRow(icon: Icons.schedule_rounded, text: 'Post at peak times for your audience'),
                SizedBox(height: 10),
                _TipRow(icon: Icons.tag_rounded, text: 'Use relevant hashtags to increase reach'),
                SizedBox(height: 10),
                _TipRow(icon: Icons.people_outline_rounded, text: 'Engage with comments to boost visibility'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13))),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Posts grid
// ─────────────────────────────────────────────────────────────────

class _PostsGrid extends ConsumerWidget {
  const _PostsGrid({
    required this.state,
    required this.uid,
    required this.onTap,
    required this.onNewPost,
    this.filterVideo = false,
  });
  final ProfileState state;
  final String uid;
  final ValueChanged<String> onTap;
  final VoidCallback onNewPost;
  final bool filterVideo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = filterVideo
        ? state.posts.where((p) => p.mediaType == 'video').toList()
        : state.posts;

    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filterVideo
                  ? Icons.play_circle_outline_rounded
                  : Icons.grid_on_rounded,
              size: 52,
              color: Colors.white24,
            ),
            const SizedBox(height: 14),
            Text(
              filterVideo ? 'No videos yet' : 'No posts yet',
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 15,
                  fontWeight: FontWeight.w500),
            ),
            if (state.isOwnProfile && !filterVideo) ...[
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onNewPost,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Create your first post',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 1.5,
        mainAxisSpacing: 1.5,
        childAspectRatio: 0.6,
      ),
      itemCount: posts.length,
      itemBuilder: (ctx, i) {
        if (i == posts.length - 3 && state.hasMore) {
          ref.read(profileProvider(uid).notifier).loadMore();
        }
        return _GridTile(
          post: posts[i],
          onTap: () => onTap(posts[i].id),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Grid tile (TikTok-style with view count)
// ─────────────────────────────────────────────────────────────────

class _GridTile extends StatelessWidget {
  const _GridTile({required this.post, required this.onTap});
  final PostModel post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Thumbnail ───────────────────────────────────────
          if (post.mediaUrls.isNotEmpty)
            CachedNetworkImage(
              imageUrl: post.mediaUrls.first,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(color: const Color(0xFF1A1A1A)),
              errorWidget: (_, __, ___) => _TextPostTile(caption: post.caption),
            )
          else
            _TextPostTile(caption: post.caption),

          // ── Dark gradient at bottom ──────────────────────────
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              height: 36,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),

          // ── Video/multi indicator (top right) ───────────────
          if (post.mediaType == 'video')
            const Positioned(
              top: 6,
              right: 6,
              child:
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
            )
          else if (post.mediaUrls.length > 1)
            const Positioned(
              top: 6,
              right: 6,
              child: Icon(Icons.photo_library_outlined,
                  color: Colors.white, size: 16),
            ),

          // ── View count (bottom left) ─────────────────────────
          Positioned(
            left: 5,
            bottom: 5,
            child: Row(
              children: [
                const Icon(Icons.remove_red_eye_outlined,
                    color: Colors.white, size: 13),
                const SizedBox(width: 3),
                Text(
                  _fmt(post.likesCount),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────
// Text post tile (no media)
// ─────────────────────────────────────────────────────────────────

class _TextPostTile extends StatelessWidget {
  const _TextPostTile({required this.caption});
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote_rounded, color: Colors.white24, size: 18),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(color: Colors.white70, fontSize: 10, height: 1.4),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Empty tab placeholder
// ─────────────────────────────────────────────────────────────────

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 52, color: Colors.white24),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(color: Colors.white54, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Pinned tab bar delegate
// ─────────────────────────────────────────────────────────────────

class _TabDelegate extends SliverPersistentHeaderDelegate {
  const _TabDelegate(this.tabBar);
  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(color: Colors.black, child: tabBar);

  @override
  bool shouldRebuild(_TabDelegate old) => false;
}

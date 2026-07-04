import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../data/communities_repository.dart';
import '../../domain/models/announcement_model.dart';
import '../../domain/models/community_channel_model.dart';
import '../../domain/models/community_model.dart';
import '../providers/communities_provider.dart';
import '../providers/community_detail_provider.dart';
import '../widgets/branded_content_badge.dart';
import 'add_members_screen.dart';

class CommunityDetailScreen extends ConsumerStatefulWidget {
  const CommunityDetailScreen({super.key, required this.communityId});
  final String communityId;

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState
    extends ConsumerState<CommunityDetailScreen> {

  List<CommunityChannelModel> _channels = [];
  bool _channelsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    final channels = await CommunitiesRepository.instance
        .fetchChannels(widget.communityId);
    if (mounted) setState(() { _channels = channels; _channelsLoaded = true; });
  }

  void _openChannel(CommunityModel c, CommunityChannelModel ch) {
    final isAnnouncements = ch.channelType == 'announcements';
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CommunityChannelScreen(
        communityId: c.id,
        channelName: ch.name,
        channelIcon: isAnnouncements
            ? Icons.campaign_rounded
            : Icons.chat_bubble_outline_rounded,
        iconColor: isAnnouncements ? const Color(0xFF1A7A6B) : Colors.grey,
        communityName: c.name,
        isAnnouncements: isAnnouncements,
        isModerator: c.isModerator,
        communityId2: widget.communityId,
      ),
    ));
  }

  Future<void> _toggleMembership() async {
    await ref
        .read(communityDetailProvider(widget.communityId).notifier)
        .toggleMembership();
    final state = ref.read(communityDetailProvider(widget.communityId));
    if (state.community != null) {
      ref.read(communitiesProvider.notifier).updateCommunity(state.community!);
    }
  }

  Future<void> _requestToJoin() async {
    try {
      await CommunitiesRepository.instance.requestToJoin(widget.communityId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Join request sent! Waiting for admin approval.'),
            backgroundColor: AppColors.primary,
          ),
        );
        ref.invalidate(communityDetailProvider(widget.communityId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openAnnouncements(CommunityModel c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CommunityChannelScreen(
        communityId: c.id,
        channelName: 'Announcements',
        channelIcon: Icons.campaign_rounded,
        iconColor: const Color(0xFF1A7A6B),
        communityName: c.name,
        isAnnouncements: true,
        isModerator: c.isModerator,
        communityId2: widget.communityId,
      ),
    ));
  }

  void _openGeneralChannel(CommunityModel c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _CommunityChannelScreen(
        communityId: c.id,
        channelName: 'General',
        channelIcon: Icons.chat_bubble_outline_rounded,
        iconColor: Colors.grey,
        communityName: c.name,
        isAnnouncements: false,
        isModerator: c.isModerator,
        communityId2: widget.communityId,
      ),
    ));
  }

  void _showManageGroups(BuildContext context, CommunityModel c) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => _ManageGroupsScreen(community: c),
        ))
        .then((_) => _loadChannels()); // refresh when coming back
  }

  void _showMenu(BuildContext context, CommunityModel c) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text('Community info',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showInfo(context, c);
            },
          ),
          if (c.isModerator)
            ListTile(
              leading: const Icon(Icons.manage_accounts_rounded,
                  color: Colors.white),
              title: const Text('Manage groups',
                  style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showManageGroups(context, c);
              },
            ),
          ListTile(
            leading: const Icon(Icons.share_outlined, color: Colors.white),
            title: const Text('Share link',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              Share.share(
                'Join "${c.name}" on CommunityHub!\n\n'
                'Download the app and search for this community, '
                'or tap the link to join directly:\n'
                'io.communityhub://community/${c.id}',
                subject: 'Join ${c.name} on CommunityHub',
              );
            },
          ),
          if (c.isMember)
            ListTile(
              leading: const Icon(Icons.exit_to_app_rounded,
                  color: Colors.redAccent),
              title: const Text('Leave community',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                await _toggleMembership();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showInfo(BuildContext context, CommunityModel c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        builder: (_, ctrl) => SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text(c.name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
              ),
              Center(
                child: Text(
                    'Community · ${c.membersCount} member${c.membersCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 13)),
              ),
              const SizedBox(height: 20),
              if (c.description.isNotEmpty) ...[
                const Text('Description',
                    style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Text(c.description,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 14, height: 1.5)),
                const SizedBox(height: 16),
              ],
              _InfoRow2(
                  icon: Icons.people_alt_rounded,
                  label: '${c.membersCount} members'),
              if (c.hubType != 'all')
                _InfoRow2(
                    icon: c.hubType == 'islam'
                        ? Icons.mosque_outlined
                        : c.hubType == 'christianity' || c.hubType == 'faith'
                            ? Icons.church_rounded
                            : Icons.work_rounded,
                    label: c.hubType == 'islam'
                        ? 'Islam'
                        : c.hubType == 'christianity'
                            ? 'Christianity'
                            : c.hubType == 'faith'
                                ? 'Faith'
                                : 'Career'),
              if (c.isPrivate)
                const _InfoRow2(
                    icon: Icons.lock_outline, label: 'Private community'),
            ],
          ),
        ),
      ),
    );
  }

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
          backgroundColor: AppColors.darkBackground,
          leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop()),
        ),
        body: const Center(
            child: Text('Community not found',
                style: TextStyle(color: Colors.white54))),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            _CommunityAvatar(
              avatarUrl: c.avatarUrl ?? c.coverUrl,
              hubType: c.hubType,
              size: 38,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.name,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      BrandedContentBadge(communityId: c.id),
                    ],
                  ),
                  Text(
                    'Community · ${c.membersCount} group${c.membersCount == 1 ? '' : 's'}',
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.volunteer_activism_outlined, color: Colors.white),
            tooltip: 'Give',
            onPressed: () => context.push(AppRoutes.give, extra: {
              'communityId': c.id,
              'communityName': c.name,
            }),
          ),
          IconButton(
            icon: const Icon(Icons.workspace_premium_outlined, color: Colors.white),
            tooltip: 'Memberships',
            onPressed: () => context.push('/community/${c.id}/memberships', extra: {
              'communityName': c.name,
              'isOwner': c.createdBy == SupabaseService.currentUserId,
            }),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showMenu(context, c),
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── Announcements channel (always first) ─────────────────
          _ChannelRow(
            icon: Icons.campaign_rounded,
            iconColor: const Color(0xFF1A7A6B),
            iconBg: const Color(0xFF1A7A6B),
            name: 'Announcements',
            subtitle: state.announcements.isNotEmpty
                ? state.announcements.first.title
                : 'Welcome to your community!',
            time: state.announcements.isNotEmpty
                ? timeago.format(state.announcements.first.createdAt,
                    allowFromNow: true)
                : '',
            onTap: () => _openAnnouncements(c),
          ),

          // ── "Groups you're in" section ───────────────────────────
          if (c.isMember) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Text(
                'Groups you\'re in',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            // Non-announcements channels from DB
            if (!_channelsLoaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_channels.where((ch) => ch.channelType != 'announcements').isEmpty)
              // Fallback: no DB channels yet — show hardcoded General
              _ChannelRow(
                icon: Icons.chat_bubble_outline_rounded,
                iconColor: Colors.white,
                iconBg: Colors.grey.shade700,
                name: 'General',
                subtitle: 'Add members to start chatting',
                time: '',
                onTap: () => _openGeneralChannel(c),
              )
            else
              ..._channels
                  .where((ch) => ch.channelType != 'announcements')
                  .map((ch) => _ChannelRow(
                        icon: Icons.chat_bubble_outline_rounded,
                        iconColor: Colors.white,
                        iconBg: Colors.grey.shade700,
                        name: ch.name,
                        subtitle: '',
                        time: '',
                        onTap: () => _openChannel(c, ch),
                      )),
          ],

          // ── Other groups (members list style) ───────────────────
          if (!c.isMember) ...[
            const SizedBox(height: 32),
            Center(
              child: Column(
                children: [
                  const Text(
                    'Other groups added to the community\nwill appear here.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Community members can join these groups.',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],

          // ── Members preview ──────────────────────────────────────
          if (state.members.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 6),
              child: Text(
                'Members',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(
              height: 80,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: state.members.length,
                itemBuilder: (_, i) {
                  final m = state.members[i];
                  final user =
                      m['users'] as Map<String, dynamic>? ?? {};
                  final avatar = user['avatar_url'] as String?;
                  final name = (user['full_name'] as String? ??
                      user['username'] as String? ??
                      'Member');
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: avatar != null
                              ? CachedNetworkImageProvider(avatar)
                              : null,
                          backgroundColor:
                              AppColors.primary.withOpacity(0.2),
                          child: avatar == null
                              ? const Icon(Icons.person,
                                  color: AppColors.primary)
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name.split(' ').first,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],

          const SizedBox(height: 100),
        ],
      ),

      // ── Add group / Join button ────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: c.isMember
              ? c.isModerator
                  ? FilledButton.icon(
                      onPressed: () => _showManageGroups(context, c),
                      icon: const Icon(Icons.add),
                      label: const Text('Add group'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.newPost),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('New post'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                    )
              : c.memberStatus == 'pending'
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.hourglass_top_rounded, size: 18),
                      label: const Text('Request pending…'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white54,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                    )
                  : FilledButton(
                      onPressed: state.isJoining
                          ? null
                          : (c.isPrivate ? _requestToJoin : _toggleMembership),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28)),
                      ),
                      child: state.isJoining
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : Text(c.isPrivate
                              ? 'Request to join'
                              : 'Join community'),
                    ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Channel row (like WhatsApp chat list row)
// ─────────────────────────────────────────────────────────────────

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.name,
    required this.subtitle,
    required this.time,
    required this.onTap,
  });
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String name;
  final String subtitle;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: onTap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          title: Text(
            name,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500),
          ),
          subtitle: Text(
            subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: time.isNotEmpty
              ? Text(time,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11))
              : null,
        ),
        const Divider(
            color: Colors.white10, height: 1, indent: 82),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Manage Groups Screen (slide-in)
// ─────────────────────────────────────────────────────────────────

class _ManageGroupsScreen extends ConsumerStatefulWidget {
  const _ManageGroupsScreen({required this.community});
  final CommunityModel community;

  @override
  ConsumerState<_ManageGroupsScreen> createState() =>
      _ManageGroupsScreenState();
}

class _ManageGroupsScreenState
    extends ConsumerState<_ManageGroupsScreen> {
  final _groupCtrl = TextEditingController();
  bool _creating = false;
  List<Map<String, dynamic>> _pendingRequests = [];
  bool _loadingRequests = true;
  List<CommunityChannelModel> _channels = [];
  bool _loadingChannels = true;

  @override
  void initState() {
    super.initState();
    _loadPending();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    final channels = await CommunitiesRepository.instance
        .fetchChannels(widget.community.id);
    if (mounted) setState(() { _channels = channels; _loadingChannels = false; });
  }

  Future<void> _loadPending() async {
    final reqs = await CommunitiesRepository.instance
        .fetchPendingRequests(widget.community.id);
    if (mounted) setState(() { _pendingRequests = reqs; _loadingRequests = false; });
  }

  Future<void> _approve(String userId) async {
    await CommunitiesRepository.instance
        .approveRequest(widget.community.id, userId);
    setState(() => _pendingRequests.removeWhere(
        (r) => (r['user_id'] as String?) == userId));
  }

  Future<void> _reject(String userId) async {
    await CommunitiesRepository.instance
        .rejectRequest(widget.community.id, userId);
    setState(() => _pendingRequests.removeWhere(
        (r) => (r['user_id'] as String?) == userId));
  }

  @override
  void dispose() {
    _groupCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalMembers = widget.community.membersCount;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Manage groups',
                style: TextStyle(color: Colors.white, fontSize: 17)),
            Text('$totalMembers of 101',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined, color: Colors.white),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    AddMembersScreen(communityId: widget.community.id),
              ));
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── Pending join requests ─────────────────────────────
          if (!_loadingRequests && _pendingRequests.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Join requests',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
            ..._pendingRequests.map((req) {
              final user = req['users'] as Map<String, dynamic>? ?? {};
              final uid = req['user_id'] as String? ?? '';
              final avatar = user['avatar_url'] as String?;
              final name = user['full_name'] as String? ??
                  user['username'] as String? ??
                  'Member';
              final username = user['username'] as String? ?? '';
              return ListTile(
                leading: CircleAvatar(
                  radius: 22,
                  backgroundImage: avatar != null
                      ? CachedNetworkImageProvider(avatar)
                      : null,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                  child: avatar == null
                      ? Text(name[0].toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.w600))
                      : null,
                ),
                title: Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500)),
                subtitle: username.isNotEmpty
                    ? Text('@$username',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12))
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => _reject(uid),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent),
                      child: const Text('Decline'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => _approve(uid),
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              );
            }),
            const Divider(color: Colors.white10, height: 1),
          ],

          // ── Create new group ──────────────────────────────────
          ListTile(
            onTap: () => _showCreateGroup(context),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.group_add_rounded,
                  color: Colors.white),
            ),
            title: const Text('Create new group',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ),
          const Divider(color: Colors.white10, height: 1, indent: 72),

          // Add existing groups
          ListTile(
            onTap: () {},
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
            title: const Text('Add existing groups',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500)),
          ),
          const Divider(color: Colors.white10, height: 1),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Members can suggest existing groups for admin\napproval and add new groups directly.',
                style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
              ),
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Groups in this community',
                style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ),

          if (_loadingChannels)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_channels.isEmpty) ...[
            // No channels in DB yet — show the two defaults
            _ManageGroupRow(
              icon: Icons.campaign_rounded,
              iconBg: const Color(0xFF1A7A6B),
              name: 'Announcements',
              subtitle: '',
              canRemove: false,
            ),
            _ManageGroupRow(
              icon: Icons.chat_bubble_outline_rounded,
              iconBg: Colors.grey.shade700,
              name: 'General',
              subtitle: '',
              canRemove: false,
            ),
          ] else
            ..._channels.map((ch) {
              final isAnnouncements =
                  ch.channelType == 'announcements' || ch.isDefault && ch.name == 'Announcements';
              final isDefaultChannel = ch.isDefault;
              return _ManageGroupRow(
                icon: isAnnouncements
                    ? Icons.campaign_rounded
                    : Icons.chat_bubble_outline_rounded,
                iconBg: isAnnouncements
                    ? const Color(0xFF1A7A6B)
                    : Colors.grey.shade700,
                name: ch.name,
                subtitle: '',
                canRemove: !isDefaultChannel,
                onRemove: isDefaultChannel
                    ? null
                    : () async {
                        await CommunitiesRepository.instance
                            .deleteChannel(ch.id);
                        setState(() => _channels.remove(ch));
                      },
              );
            }),
        ],
      ),
    );
  }

  void _showCreateGroup(BuildContext context) {
    _groupCtrl.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 20, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create new group',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                controller: _groupCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Group name',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: AppColors.darkBackground,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _creating
                      ? null
                      : () async {
                          final name = _groupCtrl.text.trim();
                          if (name.isEmpty) return;
                          setSheet(() => _creating = true);
                          final ch = await CommunitiesRepository.instance
                              .createChannel(
                            communityId: widget.community.id,
                            name: name,
                          );
                          setSheet(() => _creating = false);
                          if (ch != null && mounted) {
                            setState(() => _channels.add(ch));
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Create group'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageGroupRow extends StatelessWidget {
  const _ManageGroupRow({
    required this.icon,
    required this.iconBg,
    required this.name,
    required this.subtitle,
    required this.canRemove,
    this.onRemove,
  });
  final IconData icon;
  final Color iconBg;
  final String name;
  final String subtitle;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
            color: iconBg, borderRadius: BorderRadius.circular(14)),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
      title: Text(name,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w500)),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12))
          : null,
      trailing: canRemove
          ? GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, color: Colors.white54, size: 20),
            )
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Community Channel / Chat Screen
// ─────────────────────────────────────────────────────────────────

class _CommunityChannelScreen extends ConsumerStatefulWidget {
  const _CommunityChannelScreen({
    required this.communityId,
    required this.communityId2,
    required this.channelName,
    required this.channelIcon,
    required this.iconColor,
    required this.communityName,
    required this.isAnnouncements,
    required this.isModerator,
  });
  final String communityId;
  final String communityId2;
  final String channelName;
  final IconData channelIcon;
  final Color iconColor;
  final String communityName;
  final bool isAnnouncements;
  final bool isModerator;

  @override
  ConsumerState<_CommunityChannelScreen> createState() =>
      _CommunityChannelScreenState();
}

class _CommunityChannelScreenState
    extends ConsumerState<_CommunityChannelScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  // Local messages (real implementation would use a messages table)
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  Future<void> _loadMessages() async {
    if (widget.isAnnouncements) {
      final state = ref.read(communityDetailProvider(widget.communityId2));
      for (final a in state.announcements) {
        _messages.add({
          'text': '**${a.title}**\n${a.content}',
          'sender': a.authorName ?? 'Admin',
          'time': a.createdAt,
          'isMe': false,
          'isSystem': true,
        });
      }
      if (mounted) setState(() {});
    } else {
      // General channel — load community posts as messages
      try {
        final rows = await SupabaseService.client
            .from('posts')
            .select(
                '*, users!posts_author_id_fkey(username, full_name, avatar_url)')
            .eq('community_id', widget.communityId)
            .order('created_at', ascending: true)
            .limit(50) as List<dynamic>;

        final uid = SupabaseService.currentUserId;
        for (final r in rows) {
          final user = r['users'] as Map<String, dynamic>? ?? {};
          _messages.add({
            'text': (r['content'] ?? r['caption'] ?? '') as String,
            'sender': user['full_name'] ?? user['username'] ?? 'Member',
            'time': DateTime.tryParse(r['created_at'] as String? ?? '') ??
                DateTime.now(),
            'isMe': r['author_id'] == uid || r['user_id'] == uid,
            'isSystem': false,
          });
        }
        if (mounted) setState(() {});
      } catch (_) {}
    }
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _msgCtrl.clear();

    final uid = SupabaseService.currentUserId;

    if (widget.isAnnouncements && widget.isModerator) {
      // Post as announcement
      await ref
          .read(communityDetailProvider(widget.communityId2).notifier)
          .postAnnouncement(
              title: text.split('\n').first,
              content: text,
              isPinned: false);
    } else {
      // Post as community post
      try {
        await SupabaseService.client.from('posts').insert({
          'author_id': uid,
          'community_id': widget.communityId,
          'content': text,
          'media_type': 'text',
        });
      } catch (_) {}
    }

    setState(() {
      _messages.add({
        'text': text,
        'sender': 'You',
        'time': DateTime.now(),
        'isMe': true,
        'isSystem': false,
      });
      _sending = false;
    });

    await Future.delayed(const Duration(milliseconds: 100));
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSend = !widget.isAnnouncements || widget.isModerator;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: widget.iconColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(widget.channelIcon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.communityName,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
                Text(widget.channelName,
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 12)),
              ],
            ),
          ],
        ),
        actions: [
          if (widget.isModerator)
            IconButton(
              icon: const Icon(Icons.person_add_outlined, color: Colors.white),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      AddMembersScreen(communityId: widget.communityId),
                ));
              },
            ),
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Chat messages ──────────────────────────────────────
          Expanded(
            child: _messages.isEmpty
                ? _WelcomeCard(
                    communityName: widget.communityName,
                    isAnnouncements: widget.isAnnouncements,
                    communityId: widget.communityId,
                    isModerator: widget.isModerator,
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (_, i) {
                      final msg = _messages[i];
                      return _ChatBubble(
                        text: msg['text'] as String,
                        sender: msg['sender'] as String,
                        time: msg['time'] as DateTime,
                        isMe: msg['isMe'] as bool,
                        isSystem: msg['isSystem'] as bool? ?? false,
                      );
                    },
                  ),
          ),

          // ── Input ──────────────────────────────────────────────
          if (canSend)
            Container(
              color: const Color(0xFF0A0A0A),
              padding: EdgeInsets.fromLTRB(
                  8, 8, 8, MediaQuery.of(context).padding.bottom + 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 15),
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle:
                            const TextStyle(color: Colors.white38),
                        filled: true,
                        fillColor: const Color(0xFF1E1E1E),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _sendMessage,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white))
                          : const Icon(Icons.send_rounded,
                              color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              color: const Color(0xFF0A0A0A),
              padding: EdgeInsets.fromLTRB(
                  16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
              child: const Text(
                'Only admins can send messages here',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Welcome card (empty chat)
// ─────────────────────────────────────────────────────────────────

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({
    required this.communityName,
    required this.isAnnouncements,
    required this.communityId,
    required this.isModerator,
  });
  final String communityName;
  final bool isAnnouncements;
  final String communityId;
  final bool isModerator;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.groups_rounded,
                    size: 36, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              const Text(
                'Welcome to your community!',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isAnnouncements
                    ? 'Use this chat to send important admin announcements to all your members at once.'
                    : 'Start chatting with your community members.',
                style: const TextStyle(
                    color: Colors.white60, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              if (isAnnouncements && isModerator) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) =>
                          AddMembersScreen(communityId: communityId),
                    ));
                  },
                  icon: const Icon(Icons.person_add_outlined, size: 16),
                  label: const Text('Add members'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Chat bubble
// ─────────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.text,
    required this.sender,
    required this.time,
    required this.isMe,
    this.isSystem = false,
  });
  final String text;
  final String sender;
  final DateTime time;
  final bool isMe;
  final bool isSystem;

  @override
  Widget build(BuildContext context) {
    if (isSystem) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.campaign_rounded,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(sender,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(timeago.format(time),
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 10)),
            ]),
            const SizedBox(height: 6),
            Text(text,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.4)),
          ],
        ),
      );
    }

    return Align(
      alignment:
          isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? AppColors.primary.withOpacity(0.85)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft:
                Radius.circular(isMe ? 14 : 2),
            bottomRight:
                Radius.circular(isMe ? 2 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(sender,
                  style: TextStyle(
                      color: AppColors.primary.withOpacity(0.9),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            if (!isMe) const SizedBox(height: 2),
            Text(text,
                style: const TextStyle(
                    color: Colors.white, fontSize: 14, height: 1.4)),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────

class _CommunityAvatar extends StatelessWidget {
  const _CommunityAvatar({
    this.avatarUrl,
    required this.hubType,
    this.size = 42,
  });
  final String? avatarUrl;
  final String hubType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = hubType == 'islam'
        ? const Color(0xFF1A6B4A)
        : (hubType == 'faith' || hubType == 'christianity')
            ? const Color(0xFF1A7A6B)
            : hubType == 'career'
                ? const Color(0xFF1A5F8A)
                : AppColors.primary;
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: CachedNetworkImage(
            imageUrl: avatarUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _fallback(color)),
      );
    }
    return _fallback(color);
  }

  Widget _fallback(Color c) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(size * 0.26),
        ),
        child: Icon(Icons.groups_rounded,
            color: Colors.white, size: size * 0.52),
      );
}

class _InfoRow2 extends StatelessWidget {
  const _InfoRow2({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.white54, size: 20),
          const SizedBox(width: 12),
          Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

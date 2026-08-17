import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/profile_detail_repository.dart';

/// Who follows [userId], and who [userId] follows -- reached by tapping
/// the "followers" or "following" count on a profile (see
/// AppRoutes.followers / AppRoutes.following). Both tabs are always
/// available regardless of which count was tapped; [initialTab] just
/// decides which one is selected on open.
class FollowListScreen extends StatefulWidget {
  const FollowListScreen({super.key, required this.userId, this.initialTab = 0});

  final String userId;
  final int initialTab;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Connections'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: const [Tab(text: 'Followers'), Tab(text: 'Following')],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _FollowList(userId: widget.userId, mode: _FollowListMode.followers),
          _FollowList(userId: widget.userId, mode: _FollowListMode.following),
        ],
      ),
    );
  }
}

enum _FollowListMode { followers, following }

class _FollowList extends StatefulWidget {
  const _FollowList({required this.userId, required this.mode});
  final String userId;
  final _FollowListMode mode;

  @override
  State<_FollowList> createState() => _FollowListState();
}

class _FollowListState extends State<_FollowList>
    with AutomaticKeepAliveClientMixin {
  static const _pageSize = 30;

  final _users = <Map<String, dynamic>>[];
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false;
  int _page = 0;

  @override
  bool get wantKeepAlive => true;

  /// Only your OWN followers list gets the Instagram-style "Remove"
  /// action -- you can't remove someone else's follower, and for people
  /// *you* follow, unfollowing (the existing Follow/Following toggle)
  /// already covers it.
  bool get _isOwnFollowersList =>
      widget.mode == _FollowListMode.followers &&
      widget.userId == SupabaseService.currentUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _fetchPage(int page) {
    final repo = ProfileDetailRepository.instance;
    return widget.mode == _FollowListMode.followers
        ? repo.fetchFollowers(widget.userId, page: page, pageSize: _pageSize)
        : repo.fetchFollowing(widget.userId, page: page, pageSize: _pageSize);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await _fetchPage(0);
      if (!mounted) return;
      setState(() {
        _users
          ..clear()
          ..addAll(page);
        _page = 0;
        _hasMore = page.length == _pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchPage(_page + 1);
      if (!mounted) return;
      setState(() {
        _users.addAll(page);
        _page += 1;
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleFollow(Map<String, dynamic> user) async {
    final id = user['id'] as String;
    final wasFollowing = (user['is_following'] as bool?) ?? false;
    // Optimistic -- flips back if the request comes back different.
    setState(() => user['is_following'] = !wasFollowing);
    final result = await ProfileDetailRepository.instance.toggleFollow(
      id,
      isCurrentlyFollowing: wasFollowing,
      isCurrentlyRequested: false,
      isTargetPrivate: (user['is_private'] as bool?) ?? false,
    );
    if (!mounted) return;
    setState(() => user['is_following'] = result['is_following']);
  }

  Future<void> _removeFollower(Map<String, dynamic> user) async {
    final id = user['id'] as String;
    final index = _users.indexWhere((u) => u['id'] == id);
    if (index == -1) return;

    // Optimistic removal -- put it back with a snackbar if the delete
    // actually fails server-side.
    final removed = _users[index];
    setState(() => _users.removeAt(index));
    try {
      await ProfileDetailRepository.instance.removeFollower(id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _users.insert(index, removed));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not remove follower — please try again.')));
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_searchQuery.isEmpty) return _users;
    final q = _searchQuery.toLowerCase();
    return _users.where((u) {
      final username = (u['username'] as String? ?? '').toLowerCase();
      final fullName = (u['full_name'] as String? ?? '').toLowerCase();
      return username.contains(q) || fullName.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: Colors.white38, size: 40),
              const SizedBox(height: 12),
              const Text("Couldn't load this list.",
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return Center(
        child: Text(
          widget.mode == _FollowListMode.followers
              ? 'No followers yet'
              : 'Not following anyone yet',
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }

    final currentUid = SupabaseService.currentUserId;
    final filtered = _filtered;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: _SearchField(
            controller: _searchCtrl,
            onChanged: (q) => setState(() => _searchQuery = q),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No results found',
                    style: const TextStyle(color: Colors.white54),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n.metrics.pixels >
                          n.metrics.maxScrollExtent - 200) {
                        _loadMore();
                      }
                      return false;
                    },
                    child: ListView.builder(
                      itemCount: filtered.length +
                          (_hasMore && _searchQuery.isEmpty ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= filtered.length) {
                          return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Center(
                                child: SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))),
                          );
                        }
                        final user = filtered[index];
                        return _FollowListRow(
                          user: user,
                          isSelf: user['id'] == currentUid,
                          onToggleFollow: () => _toggleFollow(user),
                          showRemove: _isOwnFollowersList,
                          onRemove: () => _removeFollower(user),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.darkSurface2,
        borderRadius: BorderRadius.circular(10),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: const InputDecoration(
          hintText: 'Search',
          hintStyle: TextStyle(color: Colors.white38),
          prefixIcon: Icon(Icons.search, color: Colors.white38, size: 20),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

class _FollowListRow extends StatelessWidget {
  const _FollowListRow({
    required this.user,
    required this.isSelf,
    required this.onToggleFollow,
    required this.showRemove,
    required this.onRemove,
  });

  final Map<String, dynamic> user;
  final bool isSelf;
  final VoidCallback onToggleFollow;

  /// Instagram-style "Remove" trailing button, only ever true on your own
  /// Followers tab -- see _FollowListState._isOwnFollowersList.
  final bool showRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final id = user['id'] as String;
    final avatarUrl = user['avatar_url'] as String?;
    final fullName = (user['full_name'] as String?)?.trim();
    final username = (user['username'] as String?) ?? '';
    final displayName =
        (fullName != null && fullName.isNotEmpty) ? fullName : username;
    final isFollowing = (user['is_following'] as bool?) ?? false;
    final isVerified = (user['is_verified'] as bool?) ?? false;

    return ListTile(
      onTap: () => context.push('/user/$id'),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.primary.withValues(alpha: 0.3),
        backgroundImage:
            (avatarUrl != null && avatarUrl.isNotEmpty)
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
        child: (avatarUrl == null || avatarUrl.isEmpty)
            ? Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              )
            : null,
      ),
      title: showRemove
          // Own-followers layout: username on top (Instagram doesn't
          // repeat the @ here since the row's whole first line already
          // reads as a handle), with an inline "· Follow" for anyone you
          // don't already follow back.
          ? Row(
              children: [
                Flexible(
                  child: Text(
                    username.isNotEmpty ? username : 'User',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: AppColors.primary, size: 14),
                ],
                if (!isSelf && !isFollowing)
                  GestureDetector(
                    onTap: onToggleFollow,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Text(
                        '· Follow',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
              ],
            )
          : Row(
              children: [
                Flexible(
                  child: Text(
                    displayName.isNotEmpty ? displayName : 'User',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                    // maxLines wasn't set here -- TextOverflow.ellipsis
                    // only does anything on the LAST allowed line, and
                    // Text's maxLines defaults to unlimited. Without a
                    // line cap the name just wrapped to fit whatever
                    // narrow width this Flexible was squeezed into
                    // (between the avatar and the Follow button), which
                    // on a phone-width screen meant one or two characters
                    // per line, stacked vertically all the way down --
                    // exactly what showed up in the screenshot.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isVerified) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.verified, color: AppColors.primary, size: 14),
                ],
              ],
            ),
      subtitle: showRemove
          ? (fullName != null && fullName.isNotEmpty
              ? Text(fullName,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
              : null)
          : (username.isNotEmpty
              ? Text('@$username',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)
              : null),
      trailing: showRemove
          ? (isSelf
              ? null
              : SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: onRemove,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.darkSurface2,
                      side: const BorderSide(color: AppColors.darkBorder),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text(
                      'Remove',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ))
          : (isSelf
              ? null
              : SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: onToggleFollow,
                    style: OutlinedButton.styleFrom(
                      backgroundColor:
                          isFollowing ? Colors.transparent : AppColors.primary,
                      side: BorderSide(
                        color: isFollowing ? Colors.white24 : AppColors.primary,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: Text(
                      isFollowing ? 'Following' : 'Follow',
                      style: TextStyle(
                        color: isFollowing ? Colors.white70 : Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                )),
    );
  }
}

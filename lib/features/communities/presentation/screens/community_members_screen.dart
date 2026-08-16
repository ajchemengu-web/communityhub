import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/community_detail_provider.dart';

/// Full member list for a community, with role management (promote /
/// demote / remove) for admins and moderators.
///
/// Previously `/community/:communityId/members` was a declared route
/// constant (AppRoutes.communityMembers) that was never registered
/// with go_router, so it was unreachable, and there was no screen
/// anywhere in the app that let an admin see who was in their
/// community or change anyone's role -- community_members rows could
/// only ever be created (join/create) or deleted (leave), never
/// updated, despite RLS already supporting it.
class CommunityMembersScreen extends ConsumerWidget {
  const CommunityMembersScreen({super.key, required this.communityId});
  final String communityId;

  static String _initial(String? name) =>
      (name != null && name.isNotEmpty) ? name.substring(0, 1).toUpperCase() : '?';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communityDetailProvider(communityId));
    final notifier = ref.read(communityDetailProvider(communityId).notifier);
    final viewer = state.community;
    final myUid = SupabaseService.currentUserId;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: Text(
          viewer != null ? '${viewer.name} · Members' : 'Members',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : state.members.isEmpty
              ? const Center(
                  child: Text('No members yet',
                      style: TextStyle(color: Colors.white70)),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => ref
                      .read(communityDetailProvider(communityId).notifier)
                      .refresh(),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.members.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.darkDivider),
                    itemBuilder: (context, i) {
                      final m = state.members[i];
                      final u = (m['users'] as Map<String, dynamic>?) ?? {};
                      final role = (m['role'] as String?) ?? 'member';
                      final userId = u['id'] as String?;
                      final isSelf = userId != null && userId == myUid;
                      final joinedAt =
                          DateTime.tryParse(m['joined_at'] as String? ?? '');

                      // Only admins/moderators see any management menu at
                      // all, never on their own row, and moderators (as
                      // opposed to admins) may only act on plain members —
                      // not on other moderators or admins.
                      final canManage = viewer != null &&
                          viewer.isModerator &&
                          !isSelf &&
                          userId != null &&
                          (viewer.isAdmin || role == 'member');

                      return ListTile(
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: AppColors.darkSurface2,
                          backgroundImage: (u['avatar_url'] as String?)
                                      ?.isNotEmpty ==
                                  true
                              ? CachedNetworkImageProvider(
                                  u['avatar_url'] as String)
                              : null,
                          child: (u['avatar_url'] as String?)?.isNotEmpty !=
                                  true
                              ? Text(
                                  _initial(u['full_name'] as String? ??
                                      u['username'] as String?),
                                  style: const TextStyle(color: Colors.white),
                                )
                              : null,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                (u['full_name'] as String?)?.isNotEmpty ==
                                        true
                                    ? u['full_name'] as String
                                    : (u['username'] as String? ?? 'Member'),
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSelf) ...[
                              const SizedBox(width: 6),
                              const Text('(you)',
                                  style: TextStyle(
                                      color: Colors.white38, fontSize: 12)),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          joinedAt != null
                              ? 'Joined ${timeago.format(joinedAt)}'
                              : '@${u['username'] ?? ''}',
                          style:
                              const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _RoleBadge(role: role),
                            if (canManage)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert,
                                    color: Colors.white54),
                                color: AppColors.darkSurface2,
                                onSelected: (action) => _handleAction(
                                  context,
                                  notifier,
                                  action: action,
                                  // Safe: this button only renders when
                                  // `canManage` is true, which already
                                  // requires userId != null.
                                  userId: userId!,
                                  name: (u['full_name'] ??
                                      u['username'] ??
                                      'this member') as String,
                                ),
                                itemBuilder: (context) => [
                                  if (role != 'admin' && viewer!.isAdmin)
                                    const PopupMenuItem(
                                      value: 'make_admin',
                                      child: Text('Make admin'),
                                    ),
                                  if (role != 'moderator' &&
                                      role != 'admin' &&
                                      viewer!.isModerator)
                                    const PopupMenuItem(
                                      value: 'make_moderator',
                                      child: Text('Make moderator'),
                                    ),
                                  if (role != 'member' && viewer!.isAdmin)
                                    const PopupMenuItem(
                                      value: 'make_member',
                                      child: Text('Remove as staff'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Remove from community',
                                        style: TextStyle(color: Colors.redAccent)),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Future<void> _handleAction(
    BuildContext context,
    CommunityDetailNotifier notifier, {
    required String action,
    required String userId,
    required String name,
  }) async {
    try {
      switch (action) {
        case 'make_admin':
          await notifier.updateMemberRole(userId, 'admin');
          break;
        case 'make_moderator':
          await notifier.updateMemberRole(userId, 'moderator');
          break;
        case 'make_member':
          await notifier.updateMemberRole(userId, 'member');
          break;
        case 'remove':
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: AppColors.darkSurface2,
              title: const Text('Remove member?',
                  style: TextStyle(color: Colors.white)),
              content: Text(
                'Remove $name from this community? They can request to join again later.',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Remove',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await notifier.removeMember(userId);
          }
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    if (role == 'member') return const SizedBox.shrink();
    final isAdmin = role == 'admin';
    final color = isAdmin ? AppColors.secondary : AppColors.accent;
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        isAdmin ? 'Admin' : 'Moderator',
        style: TextStyle(
            color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

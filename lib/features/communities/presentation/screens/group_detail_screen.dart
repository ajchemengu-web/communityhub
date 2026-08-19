import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../events/presentation/screens/create_event_screen.dart';
import '../../domain/models/group_member_model.dart';
import '../providers/group_detail_provider.dart';

/// A single group's home: header, open join/leave, member list with
/// leader promote/demote (leader or community admin/moderator only —
/// RLS-enforced the same way on the server), and a shortcut to create
/// an event scoped to this group.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({
    super.key,
    required this.communityId,
    required this.groupId,
  });

  final String communityId;
  final String groupId;

  static String _initial(String? name) =>
      (name != null && name.isNotEmpty) ? name.substring(0, 1).toUpperCase() : '?';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerKey = (communityId, groupId);
    final state = ref.watch(groupDetailProvider(providerKey));
    final notifier = ref.read(groupDetailProvider(providerKey).notifier);
    final myUid = SupabaseService.currentUserId;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: Text(
          state.group?.name ?? 'Group',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: notifier.refresh,
              child: ListView(
                children: [
                  _GroupHeader(state: state, onToggleMembership: notifier.toggleMembership),
                  if (state.isMember)
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.event_outlined,
                            color: AppColors.primary),
                      ),
                      title: const Text('Create event for this group',
                          style: TextStyle(color: Colors.white, fontSize: 14)),
                      trailing: const Icon(Icons.chevron_right,
                          color: Colors.white38),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => CreateEventScreen(
                          communityId: communityId,
                          groupId: groupId,
                        ),
                      )),
                    ),
                  const Divider(color: AppColors.darkDivider, height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Members (${state.members.length})',
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (state.members.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No members yet',
                            style: TextStyle(color: Colors.white70)),
                      ),
                    )
                  else
                    ...state.members.map((m) {
                      final isSelf = m.userId == myUid;
                      return _MemberRow(
                        member: m,
                        isSelf: isSelf,
                        canManage: state.canManage && !isSelf,
                        onPromote: () =>
                            notifier.updateGroupMemberRole(m.userId, 'leader'),
                        onDemote: () =>
                            notifier.updateGroupMemberRole(m.userId, 'member'),
                        onRemove: () async {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: AppColors.darkSurface2,
                              title: const Text('Remove member?',
                                  style: TextStyle(color: Colors.white)),
                              content: Text(
                                'Remove ${m.displayName} from this group?',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, true),
                                  child: const Text('Remove',
                                      style:
                                          TextStyle(color: Colors.redAccent)),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            await notifier.removeGroupMember(m.userId);
                          }
                        },
                      );
                    }),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.state, required this.onToggleMembership});
  final GroupDetailState state;
  final VoidCallback onToggleMembership;

  @override
  Widget build(BuildContext context) {
    final group = state.group;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.tag_outlined,
                color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group?.name ?? 'Group',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700)),
                if (group?.description != null &&
                    group!.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(group.description!,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: state.isJoining ? null : onToggleMembership,
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    state.isMember ? Colors.white70 : AppColors.primary,
                side: BorderSide(
                  color: state.isMember
                      ? AppColors.darkBorder
                      : AppColors.primary,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: state.isJoining
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary),
                    )
                  : Text(state.isMember ? 'Leave' : 'Join'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isSelf,
    required this.canManage,
    required this.onPromote,
    required this.onDemote,
    required this.onRemove,
  });

  final GroupMemberModel member;
  final bool isSelf;
  final bool canManage;
  final VoidCallback onPromote;
  final VoidCallback onDemote;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: AppColors.darkSurface2,
        backgroundImage: member.avatarUrl?.isNotEmpty == true
            ? CachedNetworkImageProvider(member.avatarUrl!)
            : null,
        child: member.avatarUrl?.isNotEmpty != true
            ? Text(GroupDetailScreen._initial(member.displayName),
                style: const TextStyle(color: Colors.white))
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.displayName,
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isSelf) ...[
            const SizedBox(width: 6),
            const Text('(you)',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ],
      ),
      subtitle: Text(
        'Joined ${timeago.format(member.joinedAt)}',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (member.isLeader)
            Container(
              margin: const EdgeInsets.only(right: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
              ),
              child: const Text('Leader',
                  style: TextStyle(
                      color: AppColors.secondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          if (canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54),
              color: AppColors.darkSurface2,
              onSelected: (action) {
                switch (action) {
                  case 'promote':
                    onPromote();
                    break;
                  case 'demote':
                    onDemote();
                    break;
                  case 'remove':
                    onRemove();
                    break;
                }
              },
              itemBuilder: (context) => [
                if (!member.isLeader)
                  const PopupMenuItem(
                      value: 'promote', child: Text('Make leader'))
                else
                  const PopupMenuItem(
                      value: 'demote', child: Text('Remove as leader')),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove from group',
                      style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

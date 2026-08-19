import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/communities_repository.dart';
import '../../domain/models/community_channel_model.dart';
import '../../domain/models/community_model.dart';
import '../../domain/models/group_member_model.dart';

// ── Group Detail State ─────────────────────────────────────────

class GroupDetailState {
  const GroupDetailState({
    this.community,
    this.group,
    this.members = const [],
    this.myRole,
    this.isLoading = true,
    this.isJoining = false,
    this.errorMessage,
  });

  final CommunityModel? community;
  final CommunityChannelModel? group;
  final List<GroupMemberModel> members;

  /// 'member' | 'leader' | null (not a member of this group).
  final String? myRole;
  final bool isLoading;
  final bool isJoining;
  final String? errorMessage;

  bool get isMember => myRole != null;
  bool get isLeader => myRole == 'leader';

  /// A community admin/moderator can manage any group's membership too
  /// (staff override), mirroring group_members' own RLS.
  bool get canManage =>
      isLeader || (community?.isModerator ?? false);

  GroupDetailState copyWith({
    CommunityModel? community,
    CommunityChannelModel? group,
    List<GroupMemberModel>? members,
    String? myRole,
    bool clearMyRole = false,
    bool? isLoading,
    bool? isJoining,
    String? errorMessage,
  }) =>
      GroupDetailState(
        community: community ?? this.community,
        group: group ?? this.group,
        members: members ?? this.members,
        myRole: clearMyRole ? null : (myRole ?? this.myRole),
        isLoading: isLoading ?? this.isLoading,
        isJoining: isJoining ?? this.isJoining,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class GroupDetailNotifier extends StateNotifier<GroupDetailState> {
  GroupDetailNotifier(this.communityId, this.groupId)
      : super(const GroupDetailState()) {
    _load();
  }

  final String communityId;
  final String groupId;
  final _repo = CommunitiesRepository.instance;

  Future<void> _load() async {
    try {
      final community = await _repo.fetchCommunity(communityId);
      final channels = await _repo.fetchChannels(communityId);
      CommunityChannelModel? group;
      for (final ch in channels) {
        if (ch.id == groupId) {
          group = ch;
          break;
        }
      }

      final members = await _repo.fetchGroupMembers(groupId);
      final myRole = await _repo.fetchMyGroupRole(groupId);

      state = state.copyWith(
        community: community,
        group: group,
        members: members,
        myRole: myRole,
        clearMyRole: myRole == null,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  // ── Join / Leave (open join -- no approval step) ───────────────

  Future<void> toggleMembership() async {
    if (state.isJoining) return;
    state = state.copyWith(isJoining: true);
    try {
      if (state.isMember) {
        await _repo.leaveGroup(groupId);
      } else {
        await _repo.joinGroup(groupId);
      }
      final members = await _repo.fetchGroupMembers(groupId);
      final myRole = await _repo.fetchMyGroupRole(groupId);
      state = state.copyWith(
        members: members,
        myRole: myRole,
        clearMyRole: myRole == null,
        isJoining: false,
      );
    } catch (e) {
      state = state.copyWith(isJoining: false, errorMessage: e.toString());
    }
  }

  // ── Leader management (leader or community staff — RLS-enforced) ──

  Future<void> updateGroupMemberRole(String userId, String newRole) async {
    await _repo.updateGroupMemberRole(groupId, userId, newRole);
    final updated = state.members
        .map((m) => m.userId == userId
            ? GroupMemberModel(
                userId: m.userId,
                role: newRole,
                status: m.status,
                joinedAt: m.joinedAt,
                username: m.username,
                fullName: m.fullName,
                avatarUrl: m.avatarUrl,
                isVerified: m.isVerified,
              )
            : m)
        .toList();
    state = state.copyWith(members: updated);
    if (userId == SupabaseService.currentUserId) {
      state = state.copyWith(myRole: newRole);
    }
  }

  Future<void> removeGroupMember(String userId) async {
    await _repo.removeGroupMember(groupId, userId);
    state = state.copyWith(
      members: state.members.where((m) => m.userId != userId).toList(),
    );
    if (userId == SupabaseService.currentUserId) {
      state = state.copyWith(clearMyRole: true);
    }
  }
}

// ── Provider ───────────────────────────────────────────────────

final groupDetailProvider = StateNotifierProvider.autoDispose
    .family<GroupDetailNotifier, GroupDetailState, (String, String)>(
  (_, ids) => GroupDetailNotifier(ids.$1, ids.$2),
);

/// A member of a community group (`group_members` row), mirroring the
/// shape `CommunitiesRepository.fetchMembers()` already returns for
/// community-level members: role/status/joined_at plus a nested `users`
/// profile embed.
class GroupMemberModel {
  const GroupMemberModel({
    required this.userId,
    required this.role,
    required this.status,
    required this.joinedAt,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.isVerified = false,
  });

  final String userId;

  /// 'member' | 'leader'
  final String role;

  /// 'pending' | 'approved' | 'banned'
  final String status;
  final DateTime joinedAt;

  final String? username;
  final String? fullName;
  final String? avatarUrl;
  final bool isVerified;

  bool get isLeader => role == 'leader';

  String get displayName =>
      (fullName != null && fullName!.isNotEmpty) ? fullName! : (username ?? 'User');

  factory GroupMemberModel.fromMap(Map<String, dynamic> map) {
    final user = map['users'] as Map<String, dynamic>? ?? const {};
    return GroupMemberModel(
      userId: (user['id'] as String?) ?? (map['user_id'] as String? ?? ''),
      role: map['role'] as String? ?? 'member',
      status: map['status'] as String? ?? 'approved',
      joinedAt: DateTime.tryParse(map['joined_at'] as String? ?? '') ??
          DateTime.now(),
      username: user['username'] as String?,
      fullName: user['full_name'] as String?,
      avatarUrl: user['avatar_url'] as String?,
      isVerified: (user['is_verified'] as bool?) ?? false,
    );
  }
}

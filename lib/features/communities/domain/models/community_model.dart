import 'package:equatable/equatable.dart';

class CommunityModel extends Equatable {
  const CommunityModel({
    required this.id,
    required this.name,
    this.createdBy = '',
    required this.membersCount,
    required this.createdAt,
    this.description = '',
    this.coverUrl,
    this.avatarUrl,
    this.location,
    this.denomination,
    this.website,
    this.phone,
    this.isVerified = false,
    this.isPrivate = true,
    this.hubType = 'all',
    this.isMember = false,
    this.userRole,
    this.memberStatus,
  });

  final String id;
  final String name;
  final String createdBy; // empty string if column not yet in DB
  final int membersCount;
  final DateTime createdAt;

  // ── Details ───────────────────────────────────────────────
  final String description;
  final String? coverUrl;
  final String? avatarUrl;
  final String? location;
  final String? denomination;
  final String? website;
  final String? phone;
  final bool isVerified;
  final bool isPrivate;
  final String hubType; // 'faith' | 'career' | 'all'

  // ── Current user relationship ─────────────────────────────
  final bool isMember;
  final String? userRole;      // 'admin' | 'moderator' | 'member'
  final String? memberStatus;  // 'pending' | 'approved' | 'banned'

  bool get isAdmin => userRole == 'admin';
  bool get isModerator => userRole == 'moderator' || userRole == 'admin';
  bool get isApproved => memberStatus == 'approved';
  bool get isFaithCommunity => hubType == 'faith';

  factory CommunityModel.fromMap(Map<String, dynamic> map) {
    return CommunityModel(
      id: map['id'] as String,
      name: map['name'] as String,
      createdBy: (map['creator_id'] ?? map['created_by']) as String? ?? '',
      membersCount: (map['members_count'] as int?) ?? 0,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      description: map['description'] as String? ?? '',
      coverUrl: map['cover_url'] as String?,
      avatarUrl: map['avatar_url'] as String?,
      location: map['location'] as String?,
      denomination: map['denomination'] as String?,
      website: map['website'] as String?,
      phone: map['phone'] as String?,
      isVerified: (map['is_verified'] as bool?) ?? false,
      isPrivate: (map['is_private'] as bool?) ?? true,
      hubType: map['hub_type'] as String? ?? 'all',
      isMember: (map['is_member'] as bool?) ?? false,
      userRole: map['user_role'] as String?,
      memberStatus: map['member_status'] as String?,
    );
  }

  CommunityModel copyWith({
    int? membersCount,
    bool? isMember,
    String? userRole,
    String? memberStatus,
    bool? isVerified,
    String? coverUrl,
    String? avatarUrl,
    String? description,
  }) =>
      CommunityModel(
        id: id,
        name: name,
        createdBy: createdBy,
        membersCount: membersCount ?? this.membersCount,
        createdAt: createdAt,
        description: description ?? this.description,
        coverUrl: coverUrl ?? this.coverUrl,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        location: location,
        denomination: denomination,
        website: website,
        phone: phone,
        isVerified: isVerified ?? this.isVerified,
        isPrivate: isPrivate,
        hubType: hubType,
        isMember: isMember ?? this.isMember,
        userRole: userRole ?? this.userRole,
        memberStatus: memberStatus ?? this.memberStatus,
      );

  @override
  List<Object?> get props => [id, membersCount, isMember, userRole, memberStatus];
}

import 'package:equatable/equatable.dart';

class PrayerRequestModel extends Equatable {
  const PrayerRequestModel({
    required this.id,
    required this.communityId,
    required this.authorId,
    required this.content,
    required this.createdAt,
    this.isAnswered = false,
    this.isAnonymous = false,
    this.prayerCount = 0,
    this.authorName,
    this.authorAvatar,
    this.hasPrayed = false,
  });

  final String id;
  final String communityId;
  final String authorId;
  final String content;
  final DateTime createdAt;
  final bool isAnswered;
  final bool isAnonymous;
  final int prayerCount;
  final String? authorName;
  final String? authorAvatar;

  /// Whether the current user has prayed for this request
  final bool hasPrayed;

  String get displayName =>
      isAnonymous ? 'Anonymous' : (authorName ?? 'Member');

  factory PrayerRequestModel.fromMap(Map<String, dynamic> map) {
    return PrayerRequestModel(
      id: map['id'] as String,
      communityId: map['community_id'] as String,
      authorId: map['author_id'] as String,
      content: map['content'] as String,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      isAnswered: (map['is_answered'] as bool?) ?? false,
      isAnonymous: (map['is_anonymous'] as bool?) ?? false,
      prayerCount: (map['prayer_count'] as int?) ?? 0,
      authorName: map['author_name'] as String?,
      authorAvatar: map['author_avatar'] as String?,
      hasPrayed: (map['has_prayed'] as bool?) ?? false,
    );
  }

  PrayerRequestModel copyWith({
    bool? isAnswered,
    int? prayerCount,
    bool? hasPrayed,
  }) =>
      PrayerRequestModel(
        id: id,
        communityId: communityId,
        authorId: authorId,
        content: content,
        createdAt: createdAt,
        isAnswered: isAnswered ?? this.isAnswered,
        isAnonymous: isAnonymous,
        prayerCount: prayerCount ?? this.prayerCount,
        authorName: authorName,
        authorAvatar: authorAvatar,
        hasPrayed: hasPrayed ?? this.hasPrayed,
      );

  @override
  List<Object?> get props => [id, isAnswered, prayerCount, hasPrayed];
}

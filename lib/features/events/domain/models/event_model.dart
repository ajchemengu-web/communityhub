
// ── Enums ──────────────────────────────────────────────────────────

enum EventType { service, study, outreach, social, other }

enum RsvpStatus { going, maybe, notGoing }

// ── RsvpModel ──────────────────────────────────────────────────────

class RsvpModel {
  const RsvpModel({
    required this.eventId,
    required this.userId,
    required this.status,
    this.userName,
    this.userAvatar,
    this.createdAt,
  });

  final String eventId;
  final String userId;
  final RsvpStatus status;
  final String? userName;
  final String? userAvatar;
  final DateTime? createdAt;

  factory RsvpModel.fromMap(Map<String, dynamic> map) {
    return RsvpModel(
      eventId: map['event_id'] as String,
      userId: map['user_id'] as String,
      status: _parseStatus(map['status'] as String? ?? 'going'),
      userName: (map['profiles'] as Map?)?['full_name'] as String?,
      userAvatar: (map['profiles'] as Map?)?['avatar_url'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  static RsvpStatus _parseStatus(String s) {
    switch (s) {
      case 'maybe':
        return RsvpStatus.maybe;
      case 'not_going':
        return RsvpStatus.notGoing;
      default:
        return RsvpStatus.going;
    }
  }

  String get statusString {
    switch (status) {
      case RsvpStatus.going:
        return 'going';
      case RsvpStatus.maybe:
        return 'maybe';
      case RsvpStatus.notGoing:
        return 'not_going';
    }
  }
}

// ── EventModel ─────────────────────────────────────────────────────

class EventModel {
  const EventModel({
    required this.id,
    required this.title,
    required this.startTime,
    required this.endTime,
    required this.createdAt,
    this.description,
    this.communityId,
    this.communityName,
    this.organizerId,
    this.organizerName,
    this.organizerAvatar,
    this.coverUrl,
    this.type = EventType.service,
    this.isOnline = false,
    this.location,
    this.meetingUrl,
    this.goingCount = 0,
    this.maybeCount = 0,
    this.userRsvp,
  });

  final String id;
  final String title;
  final String? description;
  final String? communityId;
  final String? communityName;
  final String? organizerId;
  final String? organizerName;
  final String? organizerAvatar;
  final String? coverUrl;
  final EventType type;
  final bool isOnline;
  final String? location;
  final String? meetingUrl;
  final DateTime startTime;
  final DateTime endTime;
  final DateTime createdAt;
  final int goingCount;
  final int maybeCount;
  final RsvpStatus? userRsvp; // current user's RSVP, null = no response

  // ── Computed ───────────────────────────────────────────────────

  bool get isUpcoming => startTime.isAfter(DateTime.now());
  bool get isPast => endTime.isBefore(DateTime.now());
  bool get isToday {
    final now = DateTime.now();
    return startTime.year == now.year &&
        startTime.month == now.month &&
        startTime.day == now.day;
  }

  bool get isMultiDay => endTime.difference(startTime).inDays >= 1;

  int get totalAttendees => goingCount + maybeCount;

  String get typeLabel {
    switch (type) {
      case EventType.service:
        return 'Service';
      case EventType.study:
        return 'Bible Study';
      case EventType.outreach:
        return 'Outreach';
      case EventType.social:
        return 'Social';
      case EventType.other:
        return 'Event';
    }
  }

  // ── Factory ────────────────────────────────────────────────────

  factory EventModel.fromMap(
    Map<String, dynamic> map, {
    String? currentUserId,
  }) {
    final community = map['communities'] as Map?;
    final organizer = map['organizer'] as Map?;

    // Parse user RSVP from rsvps array if present
    RsvpStatus? userRsvp;
    final rsvps = map['rsvps'] as List?;
    if (rsvps != null && currentUserId != null) {
      final mine = rsvps.cast<Map>().where(
            (r) => r['user_id'] == currentUserId,
          );
      if (mine.isNotEmpty) {
        userRsvp = RsvpModel._parseStatus(
            mine.first['status'] as String? ?? 'going');
      }
    }

    return EventModel(
      id: map['id'] as String,
      title: map['title'] as String,
      description: map['description'] as String?,
      communityId: map['community_id'] as String?,
      communityName: community?['name'] as String?,
      organizerId: map['organizer_id'] as String?,
      organizerName: organizer?['full_name'] as String?,
      organizerAvatar: organizer?['avatar_url'] as String?,
      coverUrl: map['cover_url'] as String?,
      type: _parseType(map['type'] as String? ?? 'service'),
      isOnline: (map['is_online'] as bool?) ?? false,
      location: map['location'] as String?,
      meetingUrl: map['meeting_url'] as String?,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      createdAt: DateTime.parse(map['created_at'] as String),
      goingCount: (map['going_count'] as int?) ?? 0,
      maybeCount: (map['maybe_count'] as int?) ?? 0,
      userRsvp: userRsvp,
    );
  }

  static EventType _parseType(String s) {
    switch (s) {
      case 'study':
        return EventType.study;
      case 'outreach':
        return EventType.outreach;
      case 'social':
        return EventType.social;
      case 'other':
        return EventType.other;
      default:
        return EventType.service;
    }
  }

  String get typeString {
    switch (type) {
      case EventType.service:
        return 'service';
      case EventType.study:
        return 'study';
      case EventType.outreach:
        return 'outreach';
      case EventType.social:
        return 'social';
      case EventType.other:
        return 'other';
    }
  }

  EventModel copyWith({
    String? title,
    String? description,
    String? coverUrl,
    EventType? type,
    bool? isOnline,
    String? location,
    String? meetingUrl,
    DateTime? startTime,
    DateTime? endTime,
    int? goingCount,
    int? maybeCount,
    RsvpStatus? userRsvp,
    bool clearRsvp = false,
  }) =>
      EventModel(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        communityId: communityId,
        communityName: communityName,
        organizerId: organizerId,
        organizerName: organizerName,
        organizerAvatar: organizerAvatar,
        coverUrl: coverUrl ?? this.coverUrl,
        type: type ?? this.type,
        isOnline: isOnline ?? this.isOnline,
        location: location ?? this.location,
        meetingUrl: meetingUrl ?? this.meetingUrl,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        createdAt: createdAt,
        goingCount: goingCount ?? this.goingCount,
        maybeCount: maybeCount ?? this.maybeCount,
        userRsvp: clearRsvp ? null : (userRsvp ?? this.userRsvp),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is EventModel && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

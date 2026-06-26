import 'dart:io';

import '../../../core/services/supabase_service.dart';
import '../domain/models/event_model.dart';

class EventsRepository {
  EventsRepository._();
  static final instance = EventsRepository._();

  final _client = SupabaseService.client;

  static const _eventSelect = '''
    id, title, description, community_id, organizer_id,
    cover_url, type, is_online, location, meeting_url,
    start_time, end_time, created_at, going_count, maybe_count,
    communities(name),
    organizer:profiles!organizer_id(full_name, avatar_url),
    rsvps(user_id, status)
  ''';

  // ── Fetch all events (with optional filters) ───────────────────

  Future<List<EventModel>> fetchEvents({
    String? communityId,
    EventType? type,
    bool upcomingOnly = false,
    bool pastOnly = false,
    String? currentUserId,
  }) async {
    var query = _client.from('events').select(_eventSelect);

    if (communityId != null) {
      query = query.eq('community_id', communityId) as dynamic;
    }
    if (type != null) {
      query = query.eq('type', _typeString(type)) as dynamic;
    }
    if (upcomingOnly) {
      query = query.gte('end_time', DateTime.now().toIso8601String()) as dynamic;
    }
    if (pastOnly) {
      query = query.lt('end_time', DateTime.now().toIso8601String()) as dynamic;
    }

    final rows = await (query as dynamic).order('start_time') as List;
    final uid = currentUserId ?? SupabaseService.currentUserId;
    return rows
        .map((r) => EventModel.fromMap(
              Map<String, dynamic>.from(r as Map),
              currentUserId: uid,
            ))
        .toList();
  }

  // ── Fetch events the current user RSVPed to ────────────────────

  Future<List<EventModel>> fetchMyEvents() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return [];

    final rows = await _client
        .from('event_rsvps')
        .select('events(${ _eventSelect})')
        .eq('user_id', uid) as List;

    return rows
        .where((r) => r['events'] != null)
        .map((r) => EventModel.fromMap(
              Map<String, dynamic>.from(r['events'] as Map),
              currentUserId: uid,
            ))
        .toList();
  }

  // ── Fetch single event ─────────────────────────────────────────

  Future<EventModel> fetchEventById(String eventId) async {
    final uid = SupabaseService.currentUserId;
    final row = await _client
        .from('events')
        .select(_eventSelect)
        .eq('id', eventId)
        .single() as Map<String, dynamic>;
    return EventModel.fromMap(row, currentUserId: uid);
  }

  // ── Create event ───────────────────────────────────────────────

  Future<EventModel> createEvent({
    required String title,
    required String? description,
    required String? communityId,
    required EventType type,
    required bool isOnline,
    required String? location,
    required String? meetingUrl,
    required DateTime startTime,
    required DateTime endTime,
    String? coverUrl,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final row = await _client
        .from('events')
        .insert({
          'title': title,
          'description': description,
          'community_id': communityId,
          'organizer_id': uid,
          'type': _typeString(type),
          'is_online': isOnline,
          'location': location,
          'meeting_url': meetingUrl,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'cover_url': coverUrl,
          'going_count': 0,
          'maybe_count': 0,
        })
        .select(_eventSelect)
        .single() as Map<String, dynamic>;

    return EventModel.fromMap(row, currentUserId: uid);
  }

  // ── RSVP ───────────────────────────────────────────────────────

  Future<EventModel> updateRsvp(
      String eventId, RsvpStatus? status) async {
    final uid = SupabaseService.currentUserId!;

    if (status == null) {
      // Remove RSVP
      await _client
          .from('event_rsvps')
          .delete()
          .eq('event_id', eventId)
          .eq('user_id', uid);
    } else {
      await _client.from('event_rsvps').upsert({
        'event_id': eventId,
        'user_id': uid,
        'status': _rsvpString(status),
      });
    }

    // Refresh counts
    return fetchEventById(eventId);
  }

  // ── Fetch attendees ────────────────────────────────────────────

  Future<List<RsvpModel>> fetchRsvps(String eventId) async {
    final rows = await _client
        .from('event_rsvps')
        .select('event_id, user_id, status, created_at, profiles(full_name, avatar_url)')
        .eq('event_id', eventId) as List;

    return rows
        .map((r) => RsvpModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ── Upload cover ───────────────────────────────────────────────

  Future<String> uploadEventCover(File file, String eventId) async {
    final ext = file.path.split('.').last;
    final path = 'events/$eventId/cover.$ext';
    await _client.storage.from('event-covers').upload(path, file);
    return _client.storage.from('event-covers').getPublicUrl(path);
  }

  // ── Helpers ────────────────────────────────────────────────────

  static String _typeString(EventType t) {
    switch (t) {
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

  static String _rsvpString(RsvpStatus s) {
    switch (s) {
      case RsvpStatus.going:
        return 'going';
      case RsvpStatus.maybe:
        return 'maybe';
      case RsvpStatus.notGoing:
        return 'not_going';
    }
  }
}

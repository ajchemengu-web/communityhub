import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/events_repository.dart';
import '../../domain/models/event_model.dart';

// ── Events list state ──────────────────────────────────────────────

class EventsState {
  const EventsState({
    this.upcoming = const [],
    this.myEvents = const [],
    this.past = const [],
    this.isLoading = true,
    this.selectedType,
    this.errorMessage,
  });

  final List<EventModel> upcoming;
  final List<EventModel> myEvents;
  final List<EventModel> past;
  final bool isLoading;
  final EventType? selectedType; // null = show all
  final String? errorMessage;

  List<EventModel> get filteredUpcoming => selectedType == null
      ? upcoming
      : upcoming.where((e) => e.type == selectedType).toList();

  List<EventModel> get filteredPast => selectedType == null
      ? past
      : past.where((e) => e.type == selectedType).toList();

  EventsState copyWith({
    List<EventModel>? upcoming,
    List<EventModel>? myEvents,
    List<EventModel>? past,
    bool? isLoading,
    EventType? selectedType,
    bool clearType = false,
    String? errorMessage,
  }) =>
      EventsState(
        upcoming: upcoming ?? this.upcoming,
        myEvents: myEvents ?? this.myEvents,
        past: past ?? this.past,
        isLoading: isLoading ?? this.isLoading,
        selectedType:
            clearType ? null : (selectedType ?? this.selectedType),
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────────

class EventsNotifier extends StateNotifier<EventsState> {
  EventsNotifier() : super(const EventsState()) {
    _load();
  }

  final _repo = EventsRepository.instance;

  Future<void> _load() async {
    state = state.copyWith(isLoading: true);
    try {
      final results = await Future.wait([
        _repo.fetchEvents(upcomingOnly: true),
        _repo.fetchEvents(pastOnly: true),
        _repo.fetchMyEvents(),
      ]);

      state = state.copyWith(
        upcoming: results[0],
        past: results[1],
        myEvents: results[2],
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() => _load();

  void setTypeFilter(EventType? type) =>
      type == state.selectedType
          ? state = state.copyWith(clearType: true)
          : state = state.copyWith(selectedType: type);

  /// Called after creating a new event so list refreshes immediately.
  Future<void> onEventCreated(EventModel event) async {
    if (event.isUpcoming) {
      state = state.copyWith(
          upcoming: [event, ...state.upcoming]);
    }
    await refresh();
  }

  /// Update a single event's RSVP in all lists.
  void updateEventRsvp(EventModel updated) {
    List<EventModel> _patch(List<EventModel> list) =>
        list.map((e) => e.id == updated.id ? updated : e).toList();

    state = state.copyWith(
      upcoming: _patch(state.upcoming),
      past: _patch(state.past),
      myEvents: _patch(state.myEvents),
    );
  }
}

final eventsProvider =
    StateNotifierProvider.autoDispose<EventsNotifier, EventsState>(
  (_) => EventsNotifier(),
);

// ── Event detail state ─────────────────────────────────────────────

class EventDetailState {
  const EventDetailState({
    this.event,
    this.attendees = const [],
    this.isLoading = true,
    this.isRsvping = false,
    this.errorMessage,
  });

  final EventModel? event;
  final List<RsvpModel> attendees;
  final bool isLoading;
  final bool isRsvping;
  final String? errorMessage;

  List<RsvpModel> get goingList =>
      attendees.where((a) => a.status == RsvpStatus.going).toList();
  List<RsvpModel> get maybeList =>
      attendees.where((a) => a.status == RsvpStatus.maybe).toList();

  EventDetailState copyWith({
    EventModel? event,
    List<RsvpModel>? attendees,
    bool? isLoading,
    bool? isRsvping,
    String? errorMessage,
  }) =>
      EventDetailState(
        event: event ?? this.event,
        attendees: attendees ?? this.attendees,
        isLoading: isLoading ?? this.isLoading,
        isRsvping: isRsvping ?? this.isRsvping,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Detail notifier ────────────────────────────────────────────────

class EventDetailNotifier extends StateNotifier<EventDetailState> {
  EventDetailNotifier(this.eventId) : super(const EventDetailState()) {
    _load();
  }

  final String eventId;
  final _repo = EventsRepository.instance;

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.fetchEventById(eventId),
        _repo.fetchRsvps(eventId),
      ]);
      state = state.copyWith(
        event: results[0] as EventModel,
        attendees: results[1] as List<RsvpModel>,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: e.toString());
    }
  }

  /// Toggle RSVP: if already this status → remove; otherwise → set.
  Future<void> toggleRsvp(RsvpStatus tapped) async {
    if (state.event == null || state.isRsvping) return;
    state = state.copyWith(isRsvping: true);

    final current = state.event!.userRsvp;
    final next = current == tapped ? null : tapped;

    // Optimistic update
    final optimistic = state.event!.copyWith(
      userRsvp: next,
      clearRsvp: next == null,
      goingCount: _adjustCount(
          state.event!.goingCount, current, next, RsvpStatus.going),
      maybeCount: _adjustCount(
          state.event!.maybeCount, current, next, RsvpStatus.maybe),
    );
    state = state.copyWith(event: optimistic, isRsvping: false);

    try {
      final updated = await _repo.updateRsvp(eventId, next);
      state = state.copyWith(event: updated);
      // Refresh attendees
      final attendees = await _repo.fetchRsvps(eventId);
      state = state.copyWith(attendees: attendees);
    } catch (_) {
      // Revert
      state = state.copyWith(event: state.event!.copyWith(
        userRsvp: current,
        clearRsvp: current == null,
      ));
    }
  }

  int _adjustCount(int current, RsvpStatus? prev, RsvpStatus? next,
      RsvpStatus target) {
    int count = current;
    if (prev == target) count--; // removing old
    if (next == target) count++; // adding new
    return count.clamp(0, 999999);
  }

  Future<void> refresh() => _load();
}

final eventDetailProvider = StateNotifierProvider.autoDispose
    .family<EventDetailNotifier, EventDetailState, String>(
  (_, eventId) => EventDetailNotifier(eventId),
);

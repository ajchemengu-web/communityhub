import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/communities_repository.dart';
import '../../domain/models/announcement_model.dart';
import '../../domain/models/community_model.dart';
import '../../domain/models/prayer_request_model.dart';

// ── State ──────────────────────────────────────────────────────────

class MyChurchState {
  const MyChurchState({
    this.churches = const [],
    this.primaryChurch,
    this.announcements = const [],
    this.prayerRequests = const [],
    this.isLoading = true,
    this.isSubmittingPrayer = false,
    this.errorMessage,
  });

  final List<CommunityModel> churches;
  final CommunityModel? primaryChurch;
  final List<AnnouncementModel> announcements;
  final List<PrayerRequestModel> prayerRequests;
  final bool isLoading;
  final bool isSubmittingPrayer;
  final String? errorMessage;

  MyChurchState copyWith({
    List<CommunityModel>? churches,
    CommunityModel? primaryChurch,
    List<AnnouncementModel>? announcements,
    List<PrayerRequestModel>? prayerRequests,
    bool? isLoading,
    bool? isSubmittingPrayer,
    String? errorMessage,
  }) =>
      MyChurchState(
        churches: churches ?? this.churches,
        primaryChurch: primaryChurch ?? this.primaryChurch,
        announcements: announcements ?? this.announcements,
        prayerRequests: prayerRequests ?? this.prayerRequests,
        isLoading: isLoading ?? this.isLoading,
        isSubmittingPrayer: isSubmittingPrayer ?? this.isSubmittingPrayer,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────────

class MyChurchNotifier extends StateNotifier<MyChurchState> {
  MyChurchNotifier() : super(const MyChurchState()) {
    _load();
  }

  final _repo = CommunitiesRepository.instance;

  Future<void> _load() async {
    try {
      // Fetch all my communities filtered by faith hub
      final mine = await _repo.fetchMyCommunities();
      final churches =
          mine.where((c) => c.isFaithCommunity).toList();

      if (churches.isEmpty) {
        state = state.copyWith(
            churches: [], isLoading: false);
        return;
      }

      final primary = churches.first;

      // Load announcements + prayer requests for the primary church
      final results = await Future.wait([
        _repo.fetchAnnouncements(primary.id),
        _fetchPrayerRequests(primary.id),
      ]);

      state = state.copyWith(
        churches: churches,
        primaryChurch: primary,
        announcements: results[0] as List<AnnouncementModel>,
        prayerRequests: results[1] as List<PrayerRequestModel>,
        isLoading: false,
      );
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<List<PrayerRequestModel>> _fetchPrayerRequests(
      String communityId) async {
    final uid = SupabaseService.currentUserId;

    final rows = await SupabaseService.client
        .from('prayer_requests')
        .select(
            '*, profiles!author_id(full_name, avatar_url)')
        .eq('community_id', communityId)
        .order('created_at', ascending: false)
        .limit(20) as List<dynamic>;

    Set<String> prayedIds = {};
    if (uid != null && rows.isNotEmpty) {
      final ids = rows.map((r) => r['id'] as String).toList();
      final prayed = await SupabaseService.client
          .from('prayer_request_prays')
          .select('prayer_request_id')
          .eq('user_id', uid)
          .inFilter('prayer_request_id', ids) as List<dynamic>;
      prayedIds = prayed
          .map((r) => r['prayer_request_id'] as String)
          .toSet();
    }

    return rows.map((r) {
      final map = Map<String, dynamic>.from(r as Map);
      final profile = map['profiles'] as Map<String, dynamic>?;
      map['author_name'] = profile?['full_name'] as String?;
      map['author_avatar'] = profile?['avatar_url'] as String?;
      map['has_prayed'] = prayedIds.contains(map['id'] as String);
      return PrayerRequestModel.fromMap(map);
    }).toList();
  }

  /// Switch the active church when user has multiple
  Future<void> selectChurch(CommunityModel church) async {
    if (church.id == state.primaryChurch?.id) return;

    state = state.copyWith(
        primaryChurch: church, isLoading: true);

    try {
      final results = await Future.wait([
        _repo.fetchAnnouncements(church.id),
        _fetchPrayerRequests(church.id),
      ]);

      state = state.copyWith(
        announcements: results[0] as List<AnnouncementModel>,
        prayerRequests: results[1] as List<PrayerRequestModel>,
        isLoading: false,
      );
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  /// Submit a new prayer request
  Future<void> submitPrayerRequest({
    required String content,
    bool isAnonymous = false,
  }) async {
    final community = state.primaryChurch;
    final uid = SupabaseService.currentUserId;
    if (community == null || uid == null) return;

    state = state.copyWith(isSubmittingPrayer: true);

    try {
      final row = await SupabaseService.client
          .from('prayer_requests')
          .insert({
            'community_id': community.id,
            'author_id': uid,
            'content': content,
            'is_anonymous': isAnonymous,
          })
          .select('*, profiles!author_id(full_name, avatar_url)')
          .single();

      final profile = row['profiles'] as Map<String, dynamic>?;
      final map = Map<String, dynamic>.from(row);
      map['author_name'] = profile?['full_name'];
      map['author_avatar'] = profile?['avatar_url'];
      map['has_prayed'] = false;

      final newRequest = PrayerRequestModel.fromMap(map);
      state = state.copyWith(
        prayerRequests: [newRequest, ...state.prayerRequests],
        isSubmittingPrayer: false,
      );
    } catch (e) {
      state = state.copyWith(
          isSubmittingPrayer: false, errorMessage: e.toString());
    }
  }

  /// Toggle "I prayed" for a request
  Future<void> togglePrayer(PrayerRequestModel request) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    // Optimistic update
    final updated = request.copyWith(
      hasPrayed: !request.hasPrayed,
      prayerCount: request.hasPrayed
          ? request.prayerCount - 1
          : request.prayerCount + 1,
    );
    _updateRequestInState(updated);

    try {
      if (request.hasPrayed) {
        await SupabaseService.client
            .from('prayer_request_prays')
            .delete()
            .eq('prayer_request_id', request.id)
            .eq('user_id', uid);
        await SupabaseService.client
            .from('prayer_requests')
            .update({'prayer_count': updated.prayerCount})
            .eq('id', request.id);
      } else {
        await SupabaseService.client
            .from('prayer_request_prays')
            .insert(
                {'prayer_request_id': request.id, 'user_id': uid});
        await SupabaseService.client
            .from('prayer_requests')
            .update({'prayer_count': updated.prayerCount})
            .eq('id', request.id);
      }
    } catch (_) {
      // Revert on error
      _updateRequestInState(request);
    }
  }

  /// Mark a prayer request as answered (admin/author only)
  Future<void> markAnswered(PrayerRequestModel request) async {
    try {
      await SupabaseService.client
          .from('prayer_requests')
          .update({'is_answered': true})
          .eq('id', request.id);
      _updateRequestInState(request.copyWith(isAnswered: true));
    } catch (_) {}
  }

  void _updateRequestInState(PrayerRequestModel updated) {
    final list = state.prayerRequests.map((r) {
      return r.id == updated.id ? updated : r;
    }).toList();
    state = state.copyWith(prayerRequests: list);
  }
}

// ── Provider ───────────────────────────────────────────────────────

final myChurchProvider =
    StateNotifierProvider.autoDispose<MyChurchNotifier, MyChurchState>(
  (_) => MyChurchNotifier(),
);

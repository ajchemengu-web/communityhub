import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/communities_repository.dart';
import '../../domain/models/community_model.dart';

// ── Communities List State ─────────────────────────────────────

class CommunitiesState {
  const CommunitiesState({
    this.myCommunities = const [],
    this.discoverCommunities = const [],
    this.isLoadingMine = true,
    this.isLoadingDiscover = true,
    this.activeHubFilter = 'all',
    this.searchQuery = '',
    this.errorMessage,
  });

  final List<CommunityModel> myCommunities;
  final List<CommunityModel> discoverCommunities;
  final bool isLoadingMine;
  final bool isLoadingDiscover;
  final String activeHubFilter;
  final String searchQuery;
  final String? errorMessage;

  CommunitiesState copyWith({
    List<CommunityModel>? myCommunities,
    List<CommunityModel>? discoverCommunities,
    bool? isLoadingMine,
    bool? isLoadingDiscover,
    String? activeHubFilter,
    String? searchQuery,
    String? errorMessage,
  }) =>
      CommunitiesState(
        myCommunities: myCommunities ?? this.myCommunities,
        discoverCommunities:
            discoverCommunities ?? this.discoverCommunities,
        isLoadingMine: isLoadingMine ?? this.isLoadingMine,
        isLoadingDiscover: isLoadingDiscover ?? this.isLoadingDiscover,
        activeHubFilter: activeHubFilter ?? this.activeHubFilter,
        searchQuery: searchQuery ?? this.searchQuery,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class CommunitiesNotifier extends StateNotifier<CommunitiesState> {
  CommunitiesNotifier() : super(const CommunitiesState()) {
    _loadAll();
  }

  final _repo = CommunitiesRepository.instance;

  Future<void> _loadAll() async {
    await Future.wait([_loadMine(), _loadDiscover()]);
  }

  Future<void> _loadMine() async {
    try {
      final mine = await _repo.fetchMyCommunities();
      state = state.copyWith(myCommunities: mine, isLoadingMine: false);
    } catch (e) {
      state = state.copyWith(
          isLoadingMine: false, errorMessage: e.toString());
    }
  }

  Future<void> _loadDiscover() async {
    try {
      final discover = await _repo.fetchDiscover(
        hubType: state.activeHubFilter,
        query: state.searchQuery.isEmpty ? null : state.searchQuery,
      );
      state = state.copyWith(
          discoverCommunities: discover, isLoadingDiscover: false);
    } catch (e) {
      state = state.copyWith(
          isLoadingDiscover: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoadingMine: true, isLoadingDiscover: true);
    await _loadAll();
  }

  Future<void> setHubFilter(String hub) async {
    state = state.copyWith(activeHubFilter: hub, isLoadingDiscover: true);
    await _loadDiscover();
  }

  Future<void> setSearch(String q) async {
    state = state.copyWith(searchQuery: q, isLoadingDiscover: true);
    await _loadDiscover();
  }

  /// Called after joining/leaving a community so both lists stay consistent.
  void updateCommunity(CommunityModel updated) {
    final mine = List<CommunityModel>.from(state.myCommunities);
    final discover = List<CommunityModel>.from(state.discoverCommunities);

    final mineIdx = mine.indexWhere((c) => c.id == updated.id);
    final discoverIdx = discover.indexWhere((c) => c.id == updated.id);

    if (updated.isMember && updated.isApproved) {
      if (mineIdx == -1) {
        mine.insert(0, updated);
      } else {
        mine[mineIdx] = updated;
      }
    } else {
      if (mineIdx != -1) mine.removeAt(mineIdx);
    }

    if (discoverIdx != -1) discover[discoverIdx] = updated;

    state = state.copyWith(
        myCommunities: mine, discoverCommunities: discover);
  }
}

// ── Provider ───────────────────────────────────────────────────

final communitiesProvider =
    StateNotifierProvider.autoDispose<CommunitiesNotifier, CommunitiesState>(
  (_) => CommunitiesNotifier(),
);

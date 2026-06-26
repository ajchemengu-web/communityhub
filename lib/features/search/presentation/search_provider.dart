import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/search_repository.dart';
import '../../home/domain/models/post_model.dart';

// ── Search Tab ─────────────────────────────────────────────────

enum SearchTab { posts, people, communities }

// ── Search State ───────────────────────────────────────────────

class SearchState {
  const SearchState({
    this.query = '',
    this.tab = SearchTab.posts,
    this.trendingPosts = const [],
    this.postResults = const [],
    this.userResults = const [],
    this.communityResults = const [],
    this.isLoadingTrending = true,
    this.isSearching = false,
  });

  final String query;
  final SearchTab tab;
  final List<PostModel> trendingPosts;
  final List<PostModel> postResults;
  final List<UserResult> userResults;
  final List<CommunityResult> communityResults;
  final bool isLoadingTrending;
  final bool isSearching;

  bool get hasQuery => query.trim().isNotEmpty;

  SearchState copyWith({
    String? query,
    SearchTab? tab,
    List<PostModel>? trendingPosts,
    List<PostModel>? postResults,
    List<UserResult>? userResults,
    List<CommunityResult>? communityResults,
    bool? isLoadingTrending,
    bool? isSearching,
  }) =>
      SearchState(
        query: query ?? this.query,
        tab: tab ?? this.tab,
        trendingPosts: trendingPosts ?? this.trendingPosts,
        postResults: postResults ?? this.postResults,
        userResults: userResults ?? this.userResults,
        communityResults: communityResults ?? this.communityResults,
        isLoadingTrending: isLoadingTrending ?? this.isLoadingTrending,
        isSearching: isSearching ?? this.isSearching,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(const SearchState()) {
    _loadTrending();
  }

  final _repo = SearchRepository.instance;

  Future<void> _loadTrending() async {
    try {
      final posts = await _repo.fetchTrending();
      state = state.copyWith(
          trendingPosts: posts, isLoadingTrending: false);
    } catch (_) {
      state = state.copyWith(isLoadingTrending: false);
    }
  }

  void setTab(SearchTab tab) => state = state.copyWith(tab: tab);

  Future<void> search(String query) async {
    state = state.copyWith(query: query, isSearching: true);
    if (query.trim().isEmpty) {
      state = state.copyWith(
        postResults: [],
        userResults: [],
        communityResults: [],
        isSearching: false,
      );
      return;
    }

    try {
      final results = await Future.wait([
        _repo.searchPosts(query),
        _repo.searchUsers(query),
        _repo.searchCommunities(query),
      ]);

      state = state.copyWith(
        postResults: results[0] as List<PostModel>,
        userResults: results[1] as List<UserResult>,
        communityResults: results[2] as List<CommunityResult>,
        isSearching: false,
      );
    } catch (_) {
      state = state.copyWith(isSearching: false);
    }
  }

  void clear() => state = state.copyWith(
        query: '',
        postResults: [],
        userResults: [],
        communityResults: [],
      );
}

// ── Provider ───────────────────────────────────────────────────

final searchProvider =
    StateNotifierProvider.autoDispose<SearchNotifier, SearchState>(
  (_) => SearchNotifier(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/search_repository.dart';
import '../../../core/services/youtube_service.dart';
import '../../home/domain/models/post_model.dart';

enum SearchTab { posts, videos, people, communities }

class SearchState {
  const SearchState({
    this.query = '',
    this.tab = SearchTab.posts,
    this.trendingPosts = const [],
    this.suggestedUsers = const [],
    this.postResults = const [],
    this.videoResults = const [],
    this.userResults = const [],
    this.communityResults = const [],
    this.recentSearches = const [],
    this.isLoadingTrending = true,
    this.isSearching = false,
  });

  final String query;
  final SearchTab tab;
  final List<PostModel> trendingPosts;
  final List<UserResult> suggestedUsers;
  final List<PostModel> postResults;
  final List<YouTubeVideo> videoResults;
  final List<UserResult> userResults;
  final List<CommunityResult> communityResults;
  final List<String> recentSearches;
  final bool isLoadingTrending;
  final bool isSearching;

  bool get hasQuery => query.trim().isNotEmpty;

  int get totalResults =>
      postResults.length +
      videoResults.length +
      userResults.length +
      communityResults.length;

  SearchState copyWith({
    String? query,
    SearchTab? tab,
    List<PostModel>? trendingPosts,
    List<UserResult>? suggestedUsers,
    List<PostModel>? postResults,
    List<YouTubeVideo>? videoResults,
    List<UserResult>? userResults,
    List<CommunityResult>? communityResults,
    List<String>? recentSearches,
    bool? isLoadingTrending,
    bool? isSearching,
  }) =>
      SearchState(
        query: query ?? this.query,
        tab: tab ?? this.tab,
        trendingPosts: trendingPosts ?? this.trendingPosts,
        suggestedUsers: suggestedUsers ?? this.suggestedUsers,
        postResults: postResults ?? this.postResults,
        videoResults: videoResults ?? this.videoResults,
        userResults: userResults ?? this.userResults,
        communityResults: communityResults ?? this.communityResults,
        recentSearches: recentSearches ?? this.recentSearches,
        isLoadingTrending: isLoadingTrending ?? this.isLoadingTrending,
        isSearching: isSearching ?? this.isSearching,
      );
}

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier() : super(const SearchState()) {
    _loadTrending();
  }

  final _repo = SearchRepository.instance;

  Future<void> _loadTrending() async {
    try {
      final results = await Future.wait([
        _repo.fetchTrending(),
        _repo.fetchSuggestedUsers(),
      ]);
      state = state.copyWith(
        trendingPosts: results[0] as List<PostModel>,
        suggestedUsers: results[1] as List<UserResult>,
        isLoadingTrending: false,
      );
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
        videoResults: [],
        userResults: [],
        communityResults: [],
        isSearching: false,
      );
      return;
    }

    try {
      final results = await Future.wait([
        _repo.searchPosts(query),
        _repo.searchVideos(query),
        _repo.searchUsers(query),
        _repo.searchCommunities(query),
      ]);

      // Save to recent searches (max 8, no duplicates)
      final recent = [
        query.trim(),
        ...state.recentSearches
            .where((s) => s.toLowerCase() != query.trim().toLowerCase()),
      ].take(8).toList();

      state = state.copyWith(
        postResults: results[0] as List<PostModel>,
        videoResults: results[1] as List<YouTubeVideo>,
        userResults: results[2] as List<UserResult>,
        communityResults: results[3] as List<CommunityResult>,
        recentSearches: recent,
        isSearching: false,
      );
    } catch (_) {
      state = state.copyWith(isSearching: false);
    }
  }

  void removeRecentSearch(String query) {
    state = state.copyWith(
      recentSearches:
          state.recentSearches.where((s) => s != query).toList(),
    );
  }

  void clearRecentSearches() =>
      state = state.copyWith(recentSearches: []);

  void clear() => state = state.copyWith(
        query: '',
        postResults: [],
        videoResults: [],
        userResults: [],
        communityResults: [],
      );

  Future<void> toggleSuggestedFollow(String userId) async {
    final users = state.suggestedUsers.toList();
    final idx = users.indexWhere((u) => u.id == userId);
    if (idx == -1) return;
    final user = users[idx];
    users[idx] = UserResult(
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      avatarUrl: user.avatarUrl,
      isVerified: user.isVerified,
      isFollowing: !user.isFollowing,
    );
    state = state.copyWith(suggestedUsers: List.from(users));
    final result = await _repo.toggleFollow(userId,
        isCurrentlyFollowing: user.isFollowing);
    users[idx] = UserResult(
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      avatarUrl: user.avatarUrl,
      isVerified: user.isVerified,
      isFollowing: result,
    );
    state = state.copyWith(suggestedUsers: List.from(users));
  }

  Future<void> toggleFollow(String userId) async {
    final users = state.userResults.toList();
    final idx = users.indexWhere((u) => u.id == userId);
    if (idx == -1) return;

    final user = users[idx];
    // Optimistic update
    users[idx] = UserResult(
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      avatarUrl: user.avatarUrl,
      isVerified: user.isVerified,
      isFollowing: !user.isFollowing,
    );
    state = state.copyWith(userResults: users);

    final result = await _repo.toggleFollow(userId,
        isCurrentlyFollowing: user.isFollowing);

    users[idx] = UserResult(
      id: user.id,
      username: user.username,
      fullName: user.fullName,
      avatarUrl: user.avatarUrl,
      isVerified: user.isVerified,
      isFollowing: result,
    );
    state = state.copyWith(userResults: List.from(users));
  }
}

final searchProvider =
    StateNotifierProvider.autoDispose<SearchNotifier, SearchState>(
  (_) => SearchNotifier(),
);

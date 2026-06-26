import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../home/domain/models/post_model.dart';
import '../../data/profile_detail_repository.dart';

// ── Profile State ──────────────────────────────────────────────

class ProfileState {
  const ProfileState({
    this.profileData,
    this.posts = const [],
    this.isLoading = true,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.isTogglingFollow = false,
    this.errorMessage,
  });

  final Map<String, dynamic>? profileData;
  final List<PostModel> posts;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final bool isTogglingFollow;
  final String? errorMessage;

  bool get isFollowing =>
      (profileData?['is_following'] as bool?) ?? false;
  bool get isOwnProfile =>
      profileData?['id'] == SupabaseService.currentUserId;
  int get followerCount =>
      (profileData?['follower_count'] as int?) ?? 0;
  int get followingCount =>
      (profileData?['following_count'] as int?) ?? 0;
  int get postCount => (profileData?['post_count'] as int?) ?? 0;

  ProfileState copyWith({
    Map<String, dynamic>? profileData,
    List<PostModel>? posts,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    bool? isTogglingFollow,
    String? errorMessage,
  }) =>
      ProfileState(
        profileData: profileData ?? this.profileData,
        posts: posts ?? this.posts,
        isLoading: isLoading ?? this.isLoading,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        hasMore: hasMore ?? this.hasMore,
        isTogglingFollow: isTogglingFollow ?? this.isTogglingFollow,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class ProfileNotifier extends StateNotifier<ProfileState> {
  ProfileNotifier(this.userId) : super(const ProfileState()) {
    _load();
  }

  final String userId;
  final _repo = ProfileDetailRepository.instance;
  static const _pageSize = 18;

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.fetchProfile(userId),
        _repo.fetchUserPosts(userId, page: 0, pageSize: _pageSize),
      ]);

      final profile = results[0] as Map<String, dynamic>;
      final posts = results[1] as List<PostModel>;

      state = state.copyWith(
        profileData: profile,
        posts: posts,
        isLoading: false,
        hasMore: posts.length == _pageSize,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final page = state.posts.length ~/ _pageSize;
      final more = await _repo.fetchUserPosts(userId,
          page: page, pageSize: _pageSize);

      state = state.copyWith(
        posts: [...state.posts, ...more],
        isLoadingMore: false,
        hasMore: more.length == _pageSize,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> toggleFollow() async {
    if (state.isTogglingFollow) return;
    state = state.copyWith(isTogglingFollow: true);

    final wasFollowing = state.isFollowing;
    final currentCount = state.followerCount;

    // Optimistic
    final updated = Map<String, dynamic>.from(state.profileData ?? {});
    updated['is_following'] = !wasFollowing;
    updated['follower_count'] =
        wasFollowing ? currentCount - 1 : currentCount + 1;
    state = state.copyWith(profileData: updated, isTogglingFollow: false);

    final result = await _repo.toggleFollow(userId,
        isCurrentlyFollowing: wasFollowing);

    // Confirm with server result
    final confirmed = Map<String, dynamic>.from(state.profileData ?? {});
    confirmed['is_following'] = result;
    confirmed['follower_count'] =
        result ? currentCount + 1 : currentCount - 1;
    state = state.copyWith(profileData: confirmed);
  }
}

// ── Provider ───────────────────────────────────────────────────

final profileProvider = StateNotifierProvider.autoDispose
    .family<ProfileNotifier, ProfileState, String>(
  (_, userId) => ProfileNotifier(userId),
);

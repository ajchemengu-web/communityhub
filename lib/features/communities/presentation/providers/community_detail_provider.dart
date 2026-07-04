import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../home/domain/models/post_model.dart';
import '../../data/communities_repository.dart';
import '../../domain/models/announcement_model.dart';
import '../../domain/models/community_model.dart';

// ── Community Detail State ─────────────────────────────────────

class CommunityDetailState {
  const CommunityDetailState({
    this.community,
    this.posts = const [],
    this.announcements = const [],
    this.members = const [],
    this.isLoading = true,
    this.isJoining = false,
    this.hasMorePosts = true,
    this.isLoadingPosts = false,
    this.errorMessage,
  });

  final CommunityModel? community;
  final List<PostModel> posts;
  final List<AnnouncementModel> announcements;
  final List<Map<String, dynamic>> members;
  final bool isLoading;
  final bool isJoining;
  final bool hasMorePosts;
  final bool isLoadingPosts;
  final String? errorMessage;

  CommunityDetailState copyWith({
    CommunityModel? community,
    List<PostModel>? posts,
    List<AnnouncementModel>? announcements,
    List<Map<String, dynamic>>? members,
    bool? isLoading,
    bool? isJoining,
    bool? hasMorePosts,
    bool? isLoadingPosts,
    String? errorMessage,
  }) =>
      CommunityDetailState(
        community: community ?? this.community,
        posts: posts ?? this.posts,
        announcements: announcements ?? this.announcements,
        members: members ?? this.members,
        isLoading: isLoading ?? this.isLoading,
        isJoining: isJoining ?? this.isJoining,
        hasMorePosts: hasMorePosts ?? this.hasMorePosts,
        isLoadingPosts: isLoadingPosts ?? this.isLoadingPosts,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class CommunityDetailNotifier
    extends StateNotifier<CommunityDetailState> {
  CommunityDetailNotifier(this.communityId)
      : super(const CommunityDetailState()) {
    _load();
  }

  final String communityId;
  final _repo = CommunitiesRepository.instance;
  static const _pageSize = 15;

  Future<void> _load() async {
    try {
      // Fetch community first — if this fails, show error immediately
      final community = await _repo.fetchCommunity(communityId);

      // Fetch supporting data independently — failures don't block the page
      final announcements = await _repo
          .fetchAnnouncements(communityId)
          .catchError((_) => <AnnouncementModel>[]);
      final members = await _repo
          .fetchMembers(communityId)
          .catchError((_) => <Map<String, dynamic>>[]);
      final postRows = await _repo
          .fetchCommunityPosts(communityId, limit: _pageSize)
          .catchError((_) => <Map<String, dynamic>>[]);

      final hasMore = postRows.length > _pageSize;
      final postSlice = hasMore ? postRows.sublist(0, _pageSize) : postRows;
      final currentUid = SupabaseService.currentUserId;

      // Check liked IDs
      Set<String> likedIds = {};
      if (currentUid != null && postSlice.isNotEmpty) {
        final ids = postSlice.map((r) => r['id'] as String).toList();
        final liked = await SupabaseService.client
            .from('post_likes')
            .select('post_id')
            .eq('user_id', currentUid)
            .inFilter('post_id', ids) as List<dynamic>;
        likedIds =
            liked.map((r) => r['post_id'] as String).toSet();
      }

      final posts = postSlice.map((r) {
        r['is_liked'] = likedIds.contains(r['id'] as String);
        return PostModel.fromMap(r);
      }).toList();

      state = state.copyWith(
        community: community,
        announcements: announcements,
        members: members,
        posts: posts,
        hasMorePosts: hasMore,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  // ── Load more posts ──────────────────────────────────────

  Future<void> loadMorePosts() async {
    if (!state.hasMorePosts || state.isLoadingPosts) return;
    final cursor = state.posts.isNotEmpty
        ? state.posts.last.createdAt
        : null;

    state = state.copyWith(isLoadingPosts: true);

    try {
      final rows = await _repo.fetchCommunityPosts(
        communityId,
        limit: _pageSize,
        cursor: cursor,
      );

      final hasMore = rows.length > _pageSize;
      final slice = hasMore ? rows.sublist(0, _pageSize) : rows;
      final more = slice.map(PostModel.fromMap).toList();

      state = state.copyWith(
        posts: [...state.posts, ...more],
        hasMorePosts: hasMore,
        isLoadingPosts: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingPosts: false);
    }
  }

  // ── Join / Leave ─────────────────────────────────────────

  Future<void> toggleMembership() async {
    final c = state.community;
    if (c == null || state.isJoining) return;

    state = state.copyWith(isJoining: true);

    try {
      final updated = c.isMember
          ? await _repo.leaveCommunity(c)
          : await _repo.joinCommunity(c);

      state = state.copyWith(community: updated, isJoining: false);
    } catch (e) {
      state = state.copyWith(
          isJoining: false, errorMessage: e.toString());
    }
  }

  // ── Post announcement ─────────────────────────────────────

  Future<void> postAnnouncement({
    required String title,
    required String content,
    bool isPinned = false,
  }) async {
    final a = await _repo.postAnnouncement(
      communityId: communityId,
      title: title,
      content: content,
      isPinned: isPinned,
    );
    final updated = List<AnnouncementModel>.from(state.announcements);
    if (isPinned) {
      updated.insert(0, a);
    } else {
      final firstNonPinned =
          updated.indexWhere((x) => !x.isPinned);
      if (firstNonPinned == -1) {
        updated.add(a);
      } else {
        updated.insert(firstNonPinned, a);
      }
    }
    state = state.copyWith(announcements: updated);
  }
}

// ── Provider ───────────────────────────────────────────────────

final communityDetailProvider = StateNotifierProvider.autoDispose
    .family<CommunityDetailNotifier, CommunityDetailState, String>(
  (_, communityId) => CommunityDetailNotifier(communityId),
);

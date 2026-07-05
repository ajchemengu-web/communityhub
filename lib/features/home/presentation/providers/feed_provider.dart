import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/youtube_service.dart';
import '../../../boosts/data/boosts_repository.dart';
import '../../data/feed_repository.dart';
import '../../domain/models/post_model.dart';

// ── Feed Item (unified post + YouTube) ────────────────────────

class FeedItem {
  const FeedItem({
    this.post,
    this.youtubeVideo,
    this.isBoosted = false,
    this.isAd = false,
  });
  final PostModel? post;
  final YouTubeVideo? youtubeVideo;
  final bool isBoosted;
  final bool isAd;
  bool get isYouTube => youtubeVideo != null;
}

// ── Feed Notifier (paginated) ──────────────────────────────────

class FeedNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<FeedItem>, String> {
  final _repo = FeedRepository.instance;

  // Pagination state
  final List<PostModel> _posts = [];
  final List<YouTubeVideo> _videos = [];
  final Set<String> _boostedPostIds = {};
  bool _postsHasMore = true;
  bool _ytHasMore = true;
  bool _isLoadingMore = false;
  DateTime? _cursor;
  int _ytOffset = 0;
  static const int _ytPageSize = 10;

  bool get hasMore => _postsHasMore || _ytHasMore;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<FeedItem>> build(String hubType) async {
    // Reset on rebuild (hub switch or refresh)
    _posts.clear();
    _videos.clear();
    _postsHasMore = true;
    _ytHasMore = true;
    _isLoadingMore = false;
    _cursor = null;
    _ytOffset = 0;

    // Parallel fetch: first page of posts + YouTube
    final results = await Future.wait([
      _repo.fetchPosts(hubType: hubType, limit: AppConstants.feedPageSize)
          .catchError((_) => const FeedPage(posts: [], hasMore: false)),
      _repo.fetchCachedVideos(hubType: hubType, limit: _ytPageSize, offset: 0),
    ]);

    final page = results[0] as FeedPage;
    final ytPage = results[1] as List<YouTubeVideo>;

    _postsHasMore = page.hasMore;
    _ytHasMore = ytPage.length >= _ytPageSize;
    _posts.addAll(page.posts);
    _videos.addAll(ytPage);
    _ytOffset = ytPage.length;
    if (_posts.isNotEmpty) _cursor = _posts.last.createdAt;

    // Surface actively-boosted posts at the top of the first page.
    await _applyBoosts();

    // Subscribe to realtime new posts
    _subscribeToRealtime(hubType);

    return _buildFeedItems();
  }

  // ── Load more (infinite scroll) ───────────────────────────

  Future<void> loadMore() async {
    if (!hasMore || _isLoadingMore) return;
    if (state is AsyncLoading) return;

    _isLoadingMore = true;

    try {
      await Future.wait([
        if (_postsHasMore)
          _repo.fetchPosts(
            hubType: arg,
            cursor: _cursor,
            limit: AppConstants.feedPageSize,
          ).then((page) {
            _postsHasMore = page.hasMore;
            _posts.addAll(page.posts);
            if (page.posts.isNotEmpty) _cursor = _posts.last.createdAt;
          }).catchError((_) {}),

        if (_ytHasMore)
          _repo.fetchCachedVideos(
            hubType: arg,
            limit: _ytPageSize,
            offset: _ytOffset,
          ).then((ytPage) {
            _ytHasMore = ytPage.length >= _ytPageSize;
            _videos.addAll(ytPage);
            _ytOffset += ytPage.length;
          }).catchError((_) {}),
      ]);

      state = AsyncData(_buildFeedItems());
    } catch (_) {
      // Silently fail; don't clear existing data
    } finally {
      _isLoadingMore = false;
    }
  }

  // ── Optimistic like toggle ─────────────────────────────────

  Future<void> toggleLike(String postId) async {
    final postIndex = _posts.indexWhere((p) => p.id == postId);
    if (postIndex == -1) return;

    final post = _posts[postIndex];
    final wasLiked = post.isLikedByCurrentUser;

    // Optimistic update
    _posts[postIndex] = post.copyWith(
      isLikedByCurrentUser: !wasLiked,
      likesCount: wasLiked
          ? (post.likesCount - 1).clamp(0, 999999)
          : post.likesCount + 1,
    );
    state = AsyncData(_buildFeedItems());

    // Persist to Supabase
    final newCount =
        await _repo.toggleLike(postId, isCurrentlyLiked: wasLiked);

    if (newCount != null) {
      // Confirm with server count
      _posts[postIndex] = _posts[postIndex].copyWith(likesCount: newCount);
      state = AsyncData(_buildFeedItems());
    } else {
      // Revert on failure
      _posts[postIndex] = post;
      state = AsyncData(_buildFeedItems());
    }
  }

  // ── Optimistic bookmark toggle ────────────────────────────

  Future<void> toggleBookmark(String postId) async {
    final postIndex = _posts.indexWhere((p) => p.id == postId);
    if (postIndex == -1) return;

    final post = _posts[postIndex];
    final wasBookmarked = post.isBookmarkedByCurrentUser;

    // Optimistic update
    _posts[postIndex] =
        post.copyWith(isBookmarkedByCurrentUser: !wasBookmarked);
    state = AsyncData(_buildFeedItems());

    final result = await _repo.toggleBookmark(postId,
        isCurrentlyBookmarked: wasBookmarked);

    _posts[postIndex] =
        _posts[postIndex].copyWith(isBookmarkedByCurrentUser: result);
    state = AsyncData(_buildFeedItems());
  }

  // ── Realtime subscription ─────────────────────────────────

  void _subscribeToRealtime(String hubType) {
    final channel = SupabaseService.client.channel('feed:$hubType');

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'posts',
      callback: (payload) async {
        final newRow = payload.newRecord;
        if (hubType != AppConstants.hubAll &&
            newRow['hub_type'] != hubType) {
          return;
        }

        // Fetch the full row with user join
        try {
          final row = await SupabaseService.client
              .from('posts')
              .select('*')
              .eq('id', newRow['id'] as String)
              .single();
          final newPost =
              PostModel.fromMap(Map<String, dynamic>.from(row));
          _posts.insert(0, newPost);
          state = AsyncData(_buildFeedItems());
        } catch (_) {}
      },
    );

    channel.subscribe();

    // Clean up when provider is disposed
    ref.onDispose(() => channel.unsubscribe());
  }

  // ── Boosted posts (self-serve promotion) ──────────────────

  /// Fetches actively-boosted post ids and moves them to the front of
  /// `_posts` — fetching any that aren't already in the loaded page.
  /// Only applied to the first page; re-ranking across paginated cursor
  /// pages isn't worth the complexity for a v1.
  Future<void> _applyBoosts() async {
    try {
      final boostedIds = await BoostsRepository.instance.fetchActiveBoostedPostIds();
      if (boostedIds.isEmpty) return;

      _boostedPostIds
        ..clear()
        ..addAll(boostedIds);

      final present = _posts.map((p) => p.id).toSet();
      final missingIds =
          boostedIds.where((id) => !present.contains(id)).toList();
      if (missingIds.isNotEmpty) {
        final boostedPosts = await _repo.fetchPostsByIds(missingIds);
        _posts.insertAll(0, boostedPosts);
      }

      _posts.sort((a, b) {
        final aBoosted = _boostedPostIds.contains(a.id) ? 1 : 0;
        final bBoosted = _boostedPostIds.contains(b.id) ? 1 : 0;
        return bBoosted - aBoosted;
      });
    } catch (_) {
      // Boosting is best-effort — never block the feed on it.
    }
  }

  // ── Build interleaved list ────────────────────────────────

  /// Interleaves YouTube videos every 4 posts.
  /// When there are no posts, shows all YouTube videos directly.
  List<FeedItem> _buildFeedItems() {
    if (_posts.isEmpty) {
      return _videos.map((v) => FeedItem(youtubeVideo: v)).toList();
    }

    final result = <FeedItem>[];
    int ytIndex = 0;

    for (int i = 0; i < _posts.length; i++) {
      result.add(FeedItem(
        post: _posts[i],
        isBoosted: _boostedPostIds.contains(_posts[i].id),
      ));
      if ((i + 1) % 4 == 0 && ytIndex < _videos.length) {
        result.add(FeedItem(youtubeVideo: _videos[ytIndex++]));
      }
      if ((i + 1) % AppConstants.adFrequency == 0) {
        result.add(const FeedItem(isAd: true));
      }
    }

    // Append remaining YouTube videos after all posts
    while (ytIndex < _videos.length) {
      result.add(FeedItem(youtubeVideo: _videos[ytIndex++]));
    }

    return result;
  }
}

// ── Provider ──────────────────────────────────────────────────

final feedProvider = AsyncNotifierProvider.autoDispose
    .family<FeedNotifier, List<FeedItem>, String>(FeedNotifier.new);



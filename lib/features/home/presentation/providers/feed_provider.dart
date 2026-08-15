import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/youtube_service.dart';
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

/// Home feed is YouTube-only now (general posting retired — `_posts`
/// stays empty forever, kept only so [toggleLike]/[toggleBookmark]
/// remain harmless no-ops for whatever UI still calls them).
///
/// The real content comes from YouTube, and — same root cause already
/// fixed for Reels — `FeedRepository.fetchCachedVideos` alone hits a
/// hard wall almost immediately: `youtube_cache` is typically empty, so
/// every call falls through to a live YouTube API request that, without
/// a real page token, just returns the same "first page" every time.
/// This tracks a real `nextPageToken` per hub and front-loads a deep
/// buffer up front, exactly like `ReelsFeedNotifier`.
class FeedNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<FeedItem>, String> {
  final _repo = FeedRepository.instance;
  final _yt = YouTubeService.instance;

  final List<PostModel> _posts = [];
  // Videos are kept per-hub (rather than one flat list) so [_buildFeedItems]
  // can interleave hubs deliberately — weighting STEM hubs (Science,
  // Engineering, ...) more heavily — instead of whatever order the
  // parallel network fetches happened to complete in.
  final Map<String, List<YouTubeVideo>> _hubBuffers = {};
  final Set<String> _seenVideoIds = {};
  final Map<String, String?> _nextPageTokens = {};
  final Map<String, int> _hubCounts = {};
  final Set<String> _exhaustedHubs = {};
  List<String> _hubs = const [];
  String _hubType = AppConstants.hubAll;

  int get _totalVideos =>
      _hubBuffers.values.fold(0, (sum, list) => sum + list.length);

  static const bool _postsHasMore = false;
  bool _isLoadingMore = false;
  // search.list costs the same 100-unit quota per call regardless of
  // maxResults (up to the API max of 50) — request the max every time
  // so _minPerHub is usually reached in a single call per hub instead
  // of 5+ (see reels_feed_provider.dart for the same fix + rationale).
  static const int _perHubResults = 50;
  static const int _minPerHub = 40;

  bool get hasMore => _postsHasMore || _exhaustedHubs.length < _hubs.length;
  bool get isLoadingMore => _isLoadingMore;

  /// Which real YouTube hub queries feed a given tab. Mirrors the same
  /// parent/sub-hub expansion `FeedRepository.fetchPosts` used for posts,
  /// so a parent tab (e.g. "Science") pulls from all its sub-hubs too.
  List<String> _hubSetFor(String hubType) {
    if (hubType == AppConstants.hubAll) {
      return const [
        AppConstants.hubFaith,
        AppConstants.hubTechnology,
        AppConstants.hubScience,
        // Engineering previously had no query of its own on the home feed —
        // it only ever rode along inside the generic "technology" query,
        // whose keywords never even mention engineering. Give it its own
        // slot so engineering-specific content actually gets fetched.
        AppConstants.hubEngineering,
        AppConstants.hubLanguages,
        AppConstants.hubCareer,
      ];
    }
    if (hubType == AppConstants.hubScience) {
      return [AppConstants.hubScience, ...AppConstants.scienceSubHubs];
    }
    if (hubType == AppConstants.hubTechnology) {
      return [AppConstants.hubTechnology, ...AppConstants.technologySubHubs];
    }
    if (hubType == AppConstants.hubLanguages) {
      return [AppConstants.hubLanguages, ...AppConstants.languageSubHubs];
    }
    return [hubType];
  }

  @override
  Future<List<FeedItem>> build(String hubType) async {
    _posts.clear();
    _hubBuffers.clear();
    _seenVideoIds.clear();
    _nextPageTokens.clear();
    _hubCounts.clear();
    _exhaustedHubs.clear();
    _isLoadingMore = false;
    _hubType = hubType;
    _hubs = _hubSetFor(hubType);

    // Cache first — cheap, forward-compatible if it's ever populated by a
    // background refresh job. Today this is typically a no-op fallthrough.
    // These cached rows aren't tagged with which of our synthetic _hubs
    // they belong to, so file them under the requested hubType itself
    // (harmless for a specific-hub screen; for "All" they just count
    // toward hubAll's own — otherwise-unused — bucket).
    try {
      final cached = await _repo.fetchCachedVideos(
          hubType: hubType, limit: 20, offset: 0);
      _appendUnique(hubType, cached);
    } catch (_) {}

    // Front-load a real, deep buffer per hub in parallel instead of
    // relying entirely on scroll-timed loadMore() calls.
    await Future.wait(_hubs.map((hub) => _fetchHubUntil(hub, _minPerHub)));

    debugPrint(
      '[HomeFeed] hub=$hubType initial load complete — total unique videos: $_totalVideos',
    );

    return _buildFeedItems();
  }

  // ── Load more (infinite scroll) ───────────────────────────

  Future<void> loadMore() async {
    if (!hasMore || _isLoadingMore) return;
    if (state is AsyncLoading) return;

    _isLoadingMore = true;
    try {
      final before = _totalVideos;
      await Future.wait(_hubs
          .where((h) => !_exhaustedHubs.contains(h))
          .map((hub) => _fetchOnePage(hub)));
      if (_totalVideos > before) {
        state = AsyncData(_buildFeedItems());
      }
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Fetches pages for [hub] (following its own `nextPageToken` chain)
  /// until it has accumulated at least [target] unique videos or is
  /// exhausted, then logs the final count for that hub.
  Future<void> _fetchHubUntil(String hub, int target) async {
    while ((_hubCounts[hub] ?? 0) < target && !_exhaustedHubs.contains(hub)) {
      await _fetchOnePage(hub);
    }
    debugPrint(
      '[HomeFeed] hub=$hub fetched=${_hubCounts[hub] ?? 0}/$target '
      'exhausted=${_exhaustedHubs.contains(hub)}',
    );
  }

  Future<void> _fetchOnePage(String hub) async {
    if (_exhaustedHubs.contains(hub)) return;
    try {
      final page = await _yt.getHubFeedPage(
        hubType: hub,
        maxResults: _perHubResults,
        pageToken: _nextPageTokens[hub],
      );
      final added = _appendUnique(hub, page.videos);
      _hubCounts[hub] = (_hubCounts[hub] ?? 0) + added;
      _nextPageTokens[hub] = page.nextPageToken;
      if (page.nextPageToken == null) _exhaustedHubs.add(hub);
    } catch (e) {
      // A hub that keeps failing (quota, network) shouldn't be retried
      // forever — treat it as exhausted rather than spinning on it.
      debugPrint('[HomeFeed] hub=$hub fetch failed, marking exhausted: $e');
      _exhaustedHubs.add(hub);
    }
  }

  int _appendUnique(String hub, List<YouTubeVideo> page) {
    var added = 0;
    final buf = _hubBuffers.putIfAbsent(hub, () => []);
    for (final v in page) {
      if (_seenVideoIds.add(v.id)) {
        buf.add(v);
        added++;
      }
    }
    return added;
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

  // ── Build interleaved list ────────────────────────────────

  /// Home feed is YouTube-only now (general posting retired). Hubs are
  /// mixed via weighted round-robin — rather than however the parallel
  /// network fetches for each hub happened to complete, which gave no
  /// control over ordering and could bury an entire hub's videos in one
  /// block wherever its fetch happened to land — so every hub is spread
  /// evenly across the scroll. STEM hubs (Science, Engineering, and their
  /// sub-hubs — see [AppConstants.isStemHub]) get double weight, so
  /// deep engineering/science content actually shows up more often
  /// rather than being diluted 1-of-N among Faith/Languages/Career.
  /// Interleaves an ad slide every [AppConstants.adFrequency] videos.
  List<FeedItem> _buildFeedItems() {
    final result = <FeedItem>[];

    // Merge order: the hubs this build/hub-screen fetched, plus the
    // hubType's own cache bucket (relevant only for the "All" tab, where
    // the initial cache read is filed under "all" — a key not otherwise
    // present in _hubs — so it would silently be dropped without this).
    final mixOrder = <String>[
      for (final h in _hubs) h,
      if (!_hubs.contains(_hubType) && (_hubBuffers[_hubType]?.isNotEmpty ?? false))
        _hubType,
    ];
    if (mixOrder.isEmpty) return result;

    final cursors = <String, int>{for (final h in mixOrder) h: 0};
    var videoCount = 0;
    var addedAny = true;
    while (addedAny) {
      addedAny = false;
      for (final hub in mixOrder) {
        final buf = _hubBuffers[hub] ?? const [];
        final weight = AppConstants.isStemHub(hub) ? 2 : 1;
        var taken = 0;
        while (taken < weight && (cursors[hub] ?? 0) < buf.length) {
          final idx = cursors[hub]!;
          result.add(FeedItem(youtubeVideo: buf[idx]));
          cursors[hub] = idx + 1;
          videoCount++;
          taken++;
          addedAny = true;
          if (videoCount % AppConstants.adFrequency == 0) {
            result.add(const FeedItem(isAd: true));
          }
        }
      }
    }
    return result;
  }
}

// ── Provider ──────────────────────────────────────────────────

final feedProvider = AsyncNotifierProvider.autoDispose
    .family<FeedNotifier, List<FeedItem>, String>(FeedNotifier.new);

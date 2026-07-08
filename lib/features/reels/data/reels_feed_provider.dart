import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/youtube_service.dart';
import '../../home/data/feed_repository.dart';

/// Paginated Reels video feed.
///
/// `youtube_cache` (the Supabase cache table) is typically empty — nothing
/// in this codebase populates it — so relying on it alone hits a hard
/// wall almost immediately: every `loadMore()` would fall through to a
/// live YouTube API call that, without a real page token, just returns
/// the exact same "first page" every time, which then gets deduped down
/// to zero new videos.
///
/// The real fix tracks YouTube's own `nextPageToken` per hub and walks
/// forward through it. On top of that, the initial load front-loads a
/// real buffer — at least [_minPerHub] videos per hub, fetched in
/// parallel across hubs — instead of depending entirely on scroll-timed
/// `loadMore()` calls to keep up. Each hub's fetch count is logged via
/// `debugPrint` (visible in `flutter logs`) so the buffer is verifiable,
/// not just assumed.
class ReelsFeedNotifier extends AutoDisposeAsyncNotifier<List<YouTubeVideo>> {
  final _repo = FeedRepository.instance;
  final _yt = YouTubeService.instance;

  static const _hubs = [
    AppConstants.hubFaith,
    AppConstants.hubTechnology,
    AppConstants.hubScience,
    AppConstants.hubLanguages,
    AppConstants.hubCareer,
  ];
  // YouTube's search.list costs the same quota (100 units) per call no
  // matter how many results you ask for (up to the API max of 50) — so
  // requesting fewer than 50 just wastes quota headroom for no reason.
  // With this, reaching _minPerHub usually takes a single call per hub
  // instead of 6+, which matters a lot given the daily quota is shared
  // across every user of the app (see feed_provider.dart for the full
  // story — the same fix applies there).
  static const _perHubResults = 50;
  static const _minPerHub = 50;

  final List<YouTubeVideo> _videos = [];
  final Set<String> _seenIds = {};
  final Map<String, String?> _nextPageTokens = {};
  final Map<String, int> _hubCounts = {};
  final Set<String> _exhaustedHubs = {};
  bool _isLoadingMore = false;

  bool get hasMore => _exhaustedHubs.length < _hubs.length;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<YouTubeVideo>> build() async {
    _videos.clear();
    _seenIds.clear();
    _nextPageTokens.clear();
    _hubCounts.clear();
    _exhaustedHubs.clear();
    _isLoadingMore = false;

    // Try the cache first — cheap, and forward-compatible if a background
    // refresh job ever starts populating it. Today this is typically a
    // no-op fallthrough since the table sits empty.
    try {
      final cached = await _repo.fetchCachedVideos(
        hubType: AppConstants.hubAll,
        limit: 20,
        offset: 0,
      );
      _appendUnique(cached);
    } catch (_) {}

    // Fetch a real buffer per hub up front, in parallel, instead of
    // relying entirely on scroll-timed loadMore() calls.
    await Future.wait(_hubs.map((hub) => _fetchHubUntil(hub, _minPerHub)));

    debugPrint(
      '[ReelsFeed] initial load complete — total unique videos: ${_videos.length}',
    );

    // Shuffle only this first batch for variety. Later batches are
    // appended in fetch order (never reshuffled) so already-displayed
    // PageView indices never move out from under the user mid-scroll.
    _videos.shuffle();

    return List.unmodifiable(_videos);
  }

  Future<void> loadMore() async {
    if (!hasMore || _isLoadingMore) return;
    if (state is AsyncLoading) return;

    _isLoadingMore = true;
    try {
      final before = _videos.length;
      await Future.wait(_hubs
          .where((h) => !_exhaustedHubs.contains(h))
          .map((hub) => _fetchOnePage(hub)));
      if (_videos.length > before) {
        state = AsyncData(List.unmodifiable(_videos));
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
      '[ReelsFeed] hub=$hub fetched=${_hubCounts[hub] ?? 0}/$target '
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
      final added = _appendUnique(page.videos);
      _hubCounts[hub] = (_hubCounts[hub] ?? 0) + added;
      _nextPageTokens[hub] = page.nextPageToken;
      if (page.nextPageToken == null) _exhaustedHubs.add(hub);
    } catch (e) {
      // A hub that keeps failing (quota, network) shouldn't be retried
      // forever — treat it as exhausted rather than spinning on it.
      debugPrint('[ReelsFeed] hub=$hub fetch failed, marking exhausted: $e');
      _exhaustedHubs.add(hub);
    }
  }

  int _appendUnique(List<YouTubeVideo> page) {
    var added = 0;
    for (final v in page) {
      if (_seenIds.add(v.id)) {
        _videos.add(v);
        added++;
      }
    }
    return added;
  }
}

final reelsFeedProvider = AsyncNotifierProvider.autoDispose<ReelsFeedNotifier,
    List<YouTubeVideo>>(ReelsFeedNotifier.new);

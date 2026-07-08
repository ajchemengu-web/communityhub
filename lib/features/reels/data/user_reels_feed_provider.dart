import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/data/feed_repository.dart';
import '../../home/domain/models/post_model.dart';

/// Paginated feed of user-generated reels (posts flagged `is_reel`),
/// mixed into the Reels screen alongside YouTube content.
class UserReelsFeedNotifier extends AutoDisposeAsyncNotifier<List<PostModel>> {
  final _repo = FeedRepository.instance;

  final List<PostModel> _reels = [];
  DateTime? _cursor;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<PostModel>> build() async {
    _reels.clear();
    _cursor = null;
    _hasMore = true;
    _isLoadingMore = false;

    try {
      final page = await _repo.fetchUserReels(limit: 10);
      _reels.addAll(page.posts);
      _hasMore = page.hasMore;
      if (_reels.isNotEmpty) _cursor = _reels.last.createdAt;
    } catch (_) {
      // A missing/failed user-reels fetch shouldn't block the YouTube
      // side of the Reels feed — just show none for now.
    }

    return List.unmodifiable(_reels);
  }

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    if (state is AsyncLoading) return;

    _isLoadingMore = true;
    try {
      final page = await _repo.fetchUserReels(cursor: _cursor, limit: 10);
      _reels.addAll(page.posts);
      _hasMore = page.hasMore;
      if (page.posts.isNotEmpty) _cursor = _reels.last.createdAt;
      state = AsyncData(List.unmodifiable(_reels));
    } catch (_) {
    } finally {
      _isLoadingMore = false;
    }
  }
}

final userReelsFeedProvider = AsyncNotifierProvider.autoDispose<
    UserReelsFeedNotifier, List<PostModel>>(UserReelsFeedNotifier.new);

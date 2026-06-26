import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/youtube_service.dart';
import '../../data/feed_repository.dart';
import '../../domain/models/post_model.dart';

// ── Feed Item (unified post + YouTube) ────────────────────────

class FeedItem {
  const FeedItem({this.post, this.youtubeVideo});
  final PostModel? post;
  final YouTubeVideo? youtubeVideo;
  bool get isYouTube => youtubeVideo != null;
}

// ── Feed Notifier (paginated) ──────────────────────────────────

class FeedNotifier
    extends AutoDisposeFamilyAsyncNotifier<List<FeedItem>, String> {
  final _repo = FeedRepository.instance;

  // Pagination state
  final List<PostModel> _posts = [];
  List<YouTubeVideo> _videos = [];
  bool _hasMore = true;
  bool _isLoadingMore = false;
  DateTime? _cursor;

  bool get hasMore => _hasMore;
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<FeedItem>> build(String hubType) async {
    // Reset on rebuild (hub switch or refresh)
    _posts.clear();
    _videos = [];
    _hasMore = true;
    _isLoadingMore = false;
    _cursor = null;

    // Parallel fetch: first page of posts + YouTube cache
    final results = await Future.wait([
      _repo.fetchPosts(hubType: hubType, limit: AppConstants.feedPageSize),
      _repo.fetchCachedVideos(hubType: hubType),
    ]);

    final page = results[0] as dynamic;
    _videos = results[1] as List<YouTubeVideo>;

    _hasMore = (page as dynamic).hasMore as bool;
    final posts = page.posts as List<PostModel>;
    _posts.addAll(posts);
    if (_posts.isNotEmpty) _cursor = _posts.last.createdAt;

    // Subscribe to realtime new posts
    _subscribeToRealtime(hubType);

    return _buildFeedItems();
  }

  // ── Load more (infinite scroll) ───────────────────────────

  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    final currentState = state;
    if (currentState is AsyncLoading) return;

    _isLoadingMore = true;

    try {
      final page = await _repo.fetchPosts(
        hubType: arg,
        cursor: _cursor,
        limit: AppConstants.feedPageSize,
      );

      _hasMore = page.hasMore;
      _posts.addAll(page.posts);
      if (page.posts.isNotEmpty) _cursor = _posts.last.createdAt;

      state = AsyncData(_buildFeedItems());
    } catch (_) {
      // Silently fail load-more; don't clear existing data
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
            newRow['hub_type'] != hubType) return;

        // Fetch the full row with user join
        try {
          final row = await SupabaseService.client
              .from('posts')
              .select('*, users(username, full_name, avatar_url, is_verified)')
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

  // ── Build interleaved list ────────────────────────────────

  /// Interleaves YouTube videos every 4 posts: [p,p,p,p,yt, p,p,p,p,yt, …]
  List<FeedItem> _buildFeedItems() {
    final result = <FeedItem>[];
    int ytIndex = 0;

    for (int i = 0; i < _posts.length; i++) {
      result.add(FeedItem(post: _posts[i]));
      // Insert a YT card after every 4th post
      if ((i + 1) % 4 == 0 && ytIndex < _videos.length) {
        result.add(FeedItem(youtubeVideo: _videos[ytIndex++]));
      }
    }

    return result;
  }
}

// ── Provider ──────────────────────────────────────────────────

final feedProvider = AsyncNotifierProvider.autoDispose
    .family<FeedNotifier, List<FeedItem>, String>(FeedNotifier.new);

// Convenience alias used by _FeedTab to check loading-more state
final feedLoadingMoreProvider =
    Provider.autoDispose.family<bool, String>((ref, hubType) {
  final notifier = ref.watch(feedProvider(hubType).notifier);
  return notifier.isLoadingMore;
});


import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/feed_repository.dart';
import '../../domain/models/story_model.dart';

/// Active stories from followed users.
final storyProvider = FutureProvider.autoDispose<List<StoryModel>>((ref) {
  return FeedRepository.instance.fetchStories();
});

/// The current user's own single latest active story (for the ring on
/// the "My Status" row — full playback uses [myStoriesProvider]).
final myStoryProvider = FutureProvider.autoDispose<StoryModel?>((ref) {
  return FeedRepository.instance.fetchMyStory();
});

/// All of the current user's own active stories, for viewing them
/// back-to-back rather than only ever seeing the latest one.
final myStoriesProvider = FutureProvider.autoDispose<List<StoryModel>>((ref) {
  return FeedRepository.instance.fetchMyStories();
});

/// Ids of users whose story updates the current user has muted.
final mutedStoryUserIdsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) {
  return FeedRepository.instance.fetchMutedUserIds();
});

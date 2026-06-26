import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/feed_repository.dart';
import '../../domain/models/story_model.dart';

/// Active stories from followed users (or recent users if no follows yet).
final storyProvider = FutureProvider.autoDispose<List<StoryModel>>((ref) {
  return FeedRepository.instance.fetchStories();
});

/// The current user's own active story, if any.
final myStoryProvider = FutureProvider.autoDispose<StoryModel?>((ref) {
  return FeedRepository.instance.fetchMyStory();
});

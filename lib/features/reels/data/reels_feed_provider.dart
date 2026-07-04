import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/youtube_service.dart';
import '../../home/data/feed_repository.dart';

/// Loads a mixed Faith + Career YouTube feed for the Reels tab.
final reelsFeedProvider =
    FutureProvider.autoDispose<List<YouTubeVideo>>((ref) async {
  final repo = FeedRepository.instance;
  final results = await Future.wait([
    repo.fetchCachedVideos(hubType: AppConstants.hubFaith, limit: 10),
    repo.fetchCachedVideos(hubType: AppConstants.hubCareer, limit: 10),
  ]);
  final merged = [...results[0], ...results[1]];
  merged.shuffle();
  return merged;
});

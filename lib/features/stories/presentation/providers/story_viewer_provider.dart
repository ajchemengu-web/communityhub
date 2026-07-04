import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';

class StoryViewerNotifier extends StateNotifier<void> {
  StoryViewerNotifier() : super(null);

  Future<void> markSeen(String storyId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      await SupabaseService.client.from('story_views').upsert({
        'story_id': storyId,
        'user_id': uid,
      });
    } catch (_) {}
  }
}

final storyViewerProvider =
    StateNotifierProvider<StoryViewerNotifier, void>(
  (_) => StoryViewerNotifier(),
);

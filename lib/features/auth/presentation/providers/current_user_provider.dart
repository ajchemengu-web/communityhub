import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';

/// Fetches the current user's profile row (id, religion, hub_preference, etc.)
/// Returns null if not logged in or profile not yet created.
final currentUserProfileProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final uid = SupabaseService.currentUserId;
  if (uid == null) return null;
  final row = await SupabaseService.client
      .from('users')
      .select('id, religion, hub_preference, full_name, username, avatar_url')
      .eq('id', uid)
      .maybeSingle();
  return row;
});

/// Convenience: returns 'christian' | 'muslim' | ''
final currentReligionProvider = Provider.autoDispose<AsyncValue<String>>((ref) {
  return ref.watch(currentUserProfileProvider).whenData(
        (profile) => (profile?['religion'] as String?) ?? '',
      );
});

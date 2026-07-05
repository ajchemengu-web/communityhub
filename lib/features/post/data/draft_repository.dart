import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists a single in-progress post draft locally (one slot, matching
/// the "Drafts · 1" chip already in the picker screen) so backing out of
/// New Post doesn't lose everything. Media is stored as file paths —
/// best-effort, since the OS can clear app cache/temp files between
/// sessions; a path that no longer resolves to a real file is silently
/// dropped from the restored draft rather than crashing.
class DraftRepository {
  DraftRepository._();
  static final instance = DraftRepository._();

  static const _key = 'post_draft_v1';

  Future<void> saveDraft({
    required String caption,
    required String hubType,
    required List<String> mediaFilePaths,
    required String mediaType,
    required List<String> tags,
    String? youtubeUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'caption': caption,
        'hub_type': hubType,
        'media_file_paths': mediaFilePaths,
        'media_type': mediaType,
        'tags': tags,
        'youtube_url': youtubeUrl,
      }),
    );
  }

  Future<bool> hasDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_key);
  }

  /// Returns null if there's no draft. Media paths that no longer exist
  /// on disk are filtered out rather than causing a load failure.
  Future<Map<String, dynamic>?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final paths = (decoded['media_file_paths'] as List?)?.cast<String>() ?? [];
    final existingPaths = paths.where((p) => File(p).existsSync()).toList();

    return {
      ...decoded,
      'media_file_paths': existingPaths,
    };
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

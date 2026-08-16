import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists a single in-progress post draft locally (one slot, matching
/// the "Drafts · 1" chip already in the picker screen) so backing out of
/// New Post doesn't lose the caption/hub/tags/etc.
///
/// Media attachments are intentionally NOT restored from a saved draft.
/// The original implementation stored raw file-path strings and
/// reconstructed `File` objects from them on load — that only ever
/// worked on native platforms with a persistent filesystem. Flutter Web
/// has no such thing (picked images live as in-memory bytes / blob URLs
/// that don't survive a page reload), and even on native the OS can
/// clear app cache/temp files between sessions, so restoring media was
/// already best-effort at best. Rather than have drafts behave
/// differently per platform, media bytes are simply never persisted;
/// [hadMedia] on the saved draft lets the UI say "you had media
/// attached — please re-select it" instead of silently restoring
/// nothing (native) or crashing (web).
class DraftRepository {
  DraftRepository._();
  static final instance = DraftRepository._();

  static const _key = 'post_draft_v1';

  Future<void> saveDraft({
    required String caption,
    required String hubType,
    required bool hadMedia,
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
        'had_media': hadMedia,
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

  /// Returns null if there's no draft. `had_media` on the result tells
  /// the caller whether to show a "you had media attached" hint — the
  /// media itself is never included (see class doc).
  Future<Map<String, dynamic>?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

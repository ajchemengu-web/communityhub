import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

/// All Supabase interactions for profile creation & management.
class ProfileRepository {
  ProfileRepository._();
  static final ProfileRepository instance = ProfileRepository._();

  final _client = SupabaseService.client;

  // ── Username availability ─────────────────────────────────

  /// Returns true when [username] is not already taken.
  Future<bool> isUsernameAvailable(String username) async {
    final res = await _client
        .from('users')
        .select('username')
        .eq('username', username.toLowerCase().trim())
        .maybeSingle();
    return res == null;
  }

  // ── Avatar upload ─────────────────────────────────────────

  /// Uploads [imageBytes] to the `avatars` storage bucket under the
  /// current user's id and returns the public URL.
  Future<String> uploadAvatar(Uint8List imageBytes,
      {String extension = 'jpg'}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final path = '$uid/avatar.$extension';

    // Ensure bucket exists
    try {
      await SupabaseService.storage
          .createBucket('avatars', const BucketOptions(public: true));
    } catch (_) {}

    await SupabaseService.storage.from('avatars').uploadBinary(
          path,
          imageBytes,
          fileOptions: FileOptions(
            contentType: 'image/$extension',
            upsert: true,
          ),
        );

    return SupabaseService.storage.from('avatars').getPublicUrl(path);
  }

  // ── Create / upsert profile ───────────────────────────────

  /// Inserts (or upserts) the user's profile row in `public.users`.
  /// Call this once the user completes the setup wizard.
  Future<void> createProfile({
    required String fullName,
    required String username,
    String bio = '',
    String avatarUrl = '',
    String website = '',
    String churchName = '',
    String hubPreference = 'all',
    String religion = '',
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    await _client.from('users').upsert({
      'id': uid,
      'full_name': fullName.trim(),
      'username': username.toLowerCase().trim(),
      'bio': bio.trim(),
      'avatar_url': avatarUrl,
      'website': website.trim(),
      'church_name': churchName.trim(),
      'hub_preference': hubPreference,
      'religion': religion,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  // ── Check if profile already exists ──────────────────────

  /// Returns true when the current user already has a profile row.
  Future<bool> profileExists() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return false;
    final res =
        await _client.from('users').select('id').eq('id', uid).maybeSingle();
    return res != null;
  }
}

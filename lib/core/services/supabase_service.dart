import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';
import 'secure_local_storage.dart';

/// Singleton wrapper around the Supabase client.
/// All features access Supabase through this service.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService _instance = SupabaseService._();
  static SupabaseService get instance => _instance;

  // ── Client Accessors ──────────────────────────────────────
  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
  static SupabaseStorageClient get storage => client.storage;
  static RealtimeClient get realtime => client.realtime;

  // ── Current User ──────────────────────────────────────────
  static User? get currentUser => auth.currentUser;
  static String? get currentUserId => currentUser?.id;
  static bool get isAuthenticated => currentUser != null;

  // ── Auth State Stream ─────────────────────────────────────
  static Stream<AuthState> get authStateChanges => auth.onAuthStateChange;

  // ── Initialise (call once in main) ───────────────────────
  static Future<void> initialize() async {
    // Secure, Keychain/Keystore-backed session storage on the
    // platforms where flutter_secure_storage works without any extra
    // native setup. Left as the library default (plain SharedPreferences
    // via SharedPreferencesLocalStorage) on web — where "secure storage"
    // is just obfuscated browser storage anyway, no real gain — and on
    // Windows/Linux desktop, where flutter_secure_storage needs native
    // dependencies (libsecret on Linux) this app doesn't currently
    // configure and this project doesn't actively ship to.
    final useSecureStorage = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      publishableKey: AppConstants.supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
        // Leaving this null on web/desktop lets supabase_flutter fall
        // back to its own default (SharedPreferencesLocalStorage) —
        // deliberately not constructing that class ourselves here, so
        // this doesn't have to track its constructor across package
        // versions.
        localStorage: useSecureStorage ? SecureLocalStorage() : null,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  // ── Google Sign-In ────────────────────────────────────────
  //
  // The custom URL scheme only means anything on Android/iOS, where a
  // registered intent-filter (Android) or URL type (iOS) can catch it
  // and bring the app back to the foreground. A browser has no such
  // handler — Supabase would send it right back to
  // io.communityhub://login-callback after the user picks a Google
  // account, the browser has nothing to open that with, and the flow
  // just dead-ends with no error and no redirect. On web this passes
  // the page's own origin instead, which is what a Supabase OAuth
  // flow on a single-page app is actually supposed to redirect back
  // to — supabase_flutter picks the auth code up from the URL itself
  // on load (detectSessionInUri, already on by default) and exchanges
  // it for a session.
  //
  // For this to work, every origin the app is actually served from
  // (the production domain and any Vercel preview domains in use)
  // needs to be added to Supabase Dashboard → Authentication → URL
  // Configuration → Redirect URLs — Supabase rejects a redirect_to
  // that isn't on that list.
  Future<bool> signInWithGoogle() async {
    return await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : 'io.communityhub://login-callback',
    );
  }

  // ── Sign Out ──────────────────────────────────────────────
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // ── Storage Helpers ───────────────────────────────────────
  Future<String> uploadFile({
    required String bucket,
    required String path,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    await storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, upsert: true),
    );
    return storage.from(bucket).getPublicUrl(path);
  }

  Future<void> deleteFile(String bucket, String path) async {
    await storage.from(bucket).remove([path]);
  }

  // ── Realtime Channel Helpers ──────────────────────────────
  RealtimeChannel subscribeToTable({
    required String table,
    required String channelName,
    Map<String, String>? filter,
    required void Function(Map<String, dynamic> payload) onInsert,
    void Function(Map<String, dynamic> payload)? onUpdate,
    void Function(Map<String, dynamic> payload)? onDelete,
  }) {
    final channel = client.channel(channelName);

    if (filter != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: table,
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: filter.keys.first,
          value: filter.values.first,
        ),
        callback: (payload) => onInsert(payload.newRecord),
      );
    } else {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: table,
        callback: (payload) => onInsert(payload.newRecord),
      );
    }

    if (onUpdate != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: table,
        callback: (payload) => onUpdate(payload.newRecord),
      );
    }

    if (onDelete != null) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.delete,
        schema: 'public',
        table: table,
        callback: (payload) => onDelete(payload.oldRecord),
      );
    }

    channel.subscribe();
    return channel;
  }
}

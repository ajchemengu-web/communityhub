import 'package:supabase_flutter/supabase_flutter.dart';
import '../constants/app_constants.dart';

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
    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }

  // ── Google Sign-In ────────────────────────────────────────
  Future<AuthResponse> signInWithGoogle() async {
    return await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.communityhub://login-callback',
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
    required List<int> bytes,
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

    final opts = RealtimeChannelConfig(self: true);

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

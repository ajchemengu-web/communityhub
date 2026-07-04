import 'package:uuid/uuid.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/models/live_stream_model.dart';

class LiveRepository {
  LiveRepository._();
  static final instance = LiveRepository._();

  final _db = SupabaseService.client;

  static const _streamSelect = '''
    id, host_id, channel_name, title, hub_type,
    viewer_count, is_active, started_at, ended_at,
    host:users!host_id(full_name, avatar_url)
  ''';

  static const _commentSelect = '''
    id, stream_id, user_id, content, created_at,
    user:users!user_id(full_name, avatar_url)
  ''';

  // ── Start a live stream ────────────────────────────────────

  Future<LiveStreamModel> startStream({
    required String title,
    String? hubType,
  }) async {
    final uid = SupabaseService.currentUserId!;
    final channelName = 'live_${const Uuid().v4().replaceAll('-', '').substring(0, 12)}';

    final row = await _db
        .from('live_streams')
        .insert({
          'host_id': uid,
          'channel_name': channelName,
          'title': title,
          'hub_type': hubType,
          'is_active': true,
        })
        .select(_streamSelect)
        .single() as Map<String, dynamic>;

    return LiveStreamModel.fromMap(row);
  }

  // ── End a live stream ──────────────────────────────────────

  Future<void> endStream(String streamId) async {
    await _db.from('live_streams').update({
      'is_active': false,
      'ended_at': DateTime.now().toIso8601String(),
    }).eq('id', streamId);
  }

  // ── Fetch active streams ───────────────────────────────────

  Future<List<LiveStreamModel>> fetchActiveStreams() async {
    final rows = await _db
        .from('live_streams')
        .select(_streamSelect)
        .eq('is_active', true)
        .order('viewer_count', ascending: false)
        .limit(20) as List<dynamic>;

    return rows
        .map((r) => LiveStreamModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  // ── LiveKit access token ───────────────────────────────────

  /// Fetches a LiveKit access token for [channelName] scoped to [isHost]
  /// (host can publish audio/video, viewer can only subscribe). Minted
  /// server-side by the `livekit-generate-token` Edge Function — the
  /// API key/secret never touch the client.
  Future<String> fetchLiveKitToken(String channelName, {required bool isHost}) async {
    final res = await _db.functions.invoke('livekit-generate-token', body: {
      'roomName': channelName,
      'role': isHost ? 'host' : 'viewer',
    });
    final data = res.data as Map<String, dynamic>;
    return data['token'] as String;
  }

  // ── Viewer count ───────────────────────────────────────────

  Future<void> joinStream(String streamId) async {
    await _db.rpc('increment_stream_viewers', params: {'stream_id': streamId});
  }

  Future<void> leaveStream(String streamId) async {
    await _db.rpc('decrement_stream_viewers', params: {'stream_id': streamId});
  }

  // ── Comments ───────────────────────────────────────────────

  Future<LiveCommentModel> sendComment(String streamId, String content) async {
    final uid = SupabaseService.currentUserId!;
    final row = await _db
        .from('live_stream_comments')
        .insert({
          'stream_id': streamId,
          'user_id': uid,
          'content': content,
        })
        .select(_commentSelect)
        .single() as Map<String, dynamic>;

    return LiveCommentModel.fromMap(row);
  }

  Future<List<LiveCommentModel>> fetchComments(String streamId) async {
    final rows = await _db
        .from('live_stream_comments')
        .select(_commentSelect)
        .eq('stream_id', streamId)
        .order('created_at', ascending: true)
        .limit(100) as List<dynamic>;

    return rows
        .map((r) => LiveCommentModel.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}

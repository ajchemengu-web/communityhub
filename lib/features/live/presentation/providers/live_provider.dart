import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/live_repository.dart';
import '../../domain/models/live_stream_model.dart';

// ── Active streams list ────────────────────────────────────────────

class LiveStreamsNotifier extends StateNotifier<AsyncValue<List<LiveStreamModel>>> {
  LiveStreamsNotifier() : super(const AsyncLoading()) {
    _load();
    _subscribe();
  }

  final _repo = LiveRepository.instance;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    try {
      final streams = await _repo.fetchActiveStreams();
      state = AsyncData(streams);
    } catch (e) {
      state = AsyncError(e, StackTrace.current);
    }
  }

  void _subscribe() {
    _channel = SupabaseService.client
        .channel('live_streams_list')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'live_streams',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  Future<void> refresh() => _load();

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final liveStreamsProvider = StateNotifierProvider.autoDispose<
    LiveStreamsNotifier, AsyncValue<List<LiveStreamModel>>>(
  (_) => LiveStreamsNotifier(),
);

// ── Single stream comments ─────────────────────────────────────────

class LiveCommentsNotifier extends StateNotifier<List<LiveCommentModel>> {
  LiveCommentsNotifier(this.streamId) : super([]) {
    _load();
    _subscribe();
  }

  final String streamId;
  final _repo = LiveRepository.instance;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    try {
      final comments = await _repo.fetchComments(streamId);
      state = comments;
    } catch (_) {}
  }

  void _subscribe() {
    _channel = SupabaseService.client
        .channel('live_comments_$streamId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'live_stream_comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'stream_id',
            value: streamId,
          ),
          callback: (payload) async {
            try {
              final row = await SupabaseService.client
                  .from('live_stream_comments')
                  .select('''
                    id, stream_id, user_id, content, created_at,
                    user:users!user_id(full_name, avatar_url)
                  ''')
                  .eq('id', payload.newRecord['id'] as String)
                  .single();

              state = [...state, LiveCommentModel.fromMap(row)];
            } catch (_) {}
          },
        )
        .subscribe();
  }

  Future<void> sendComment(String content) async {
    if (content.trim().isEmpty) return;
    await _repo.sendComment(streamId, content.trim());
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

final liveCommentsProvider = StateNotifierProvider.autoDispose
    .family<LiveCommentsNotifier, List<LiveCommentModel>, String>(
  (_, streamId) => LiveCommentsNotifier(streamId),
);

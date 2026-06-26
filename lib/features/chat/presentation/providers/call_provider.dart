import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/chat_repository.dart';
import '../../domain/models/call_model.dart';

// ── State ──────────────────────────────────────────────────────────

class CallState {
  const CallState({
    this.activeCall,
    this.incomingCall,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isCameraOff = false,
    this.isFrontCamera = true,
    this.callDuration = 0,
    this.isJoining = false,
    this.errorMessage,
  });

  final CallModel? activeCall;

  /// An incoming ringing call from another user
  final CallModel? incomingCall;

  // ── Controls ──────────────────────────────────────────────
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isCameraOff;
  final bool isFrontCamera;

  final int callDuration; // seconds
  final bool isJoining;
  final String? errorMessage;

  bool get hasActiveCall => activeCall != null;
  bool get hasIncomingCall => incomingCall != null;

  CallState copyWith({
    CallModel? activeCall,
    bool clearActive = false,
    CallModel? incomingCall,
    bool clearIncoming = false,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isCameraOff,
    bool? isFrontCamera,
    int? callDuration,
    bool? isJoining,
    String? errorMessage,
  }) =>
      CallState(
        activeCall: clearActive ? null : (activeCall ?? this.activeCall),
        incomingCall:
            clearIncoming ? null : (incomingCall ?? this.incomingCall),
        isMuted: isMuted ?? this.isMuted,
        isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
        isCameraOff: isCameraOff ?? this.isCameraOff,
        isFrontCamera: isFrontCamera ?? this.isFrontCamera,
        callDuration: callDuration ?? this.callDuration,
        isJoining: isJoining ?? this.isJoining,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────────

class CallNotifier extends StateNotifier<CallState> {
  CallNotifier() : super(const CallState()) {
    _listenForIncomingCalls();
  }

  final _repo = ChatRepository.instance;
  RealtimeChannel? _callChannel;
  Timer? _durationTimer;

  // ── Incoming call listener ─────────────────────────────────

  void _listenForIncomingCalls() {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    _callChannel = SupabaseService.client
        .channel('incoming_calls_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: FilterType.eq,
            column: 'receiver_id',
            value: uid,
          ),
          callback: (payload) async {
            final row =
                Map<String, dynamic>.from(payload.newRecord);
            // Fetch with caller profile
            try {
              final full = await SupabaseService.client
                  .from('calls')
                  .select('''
                    id, conversation_id, caller_id, receiver_id,
                    type, status, channel_name, created_at, started_at, ended_at,
                    caller:profiles!caller_id(full_name, avatar_url),
                    receiver:profiles!receiver_id(full_name, avatar_url)
                  ''')
                  .eq('id', row['id'] as String)
                  .single() as Map<String, dynamic>;

              final call = CallModel.fromMap(full);
              if (call.isRinging) {
                state = state.copyWith(incomingCall: call);
              }
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'calls',
          callback: (payload) {
            final row = payload.newRecord;
            final callId = row['id'] as String?;
            final status = row['status'] as String?;

            // If the active or incoming call was updated
            if (callId == state.activeCall?.id) {
              if (status == 'ended' || status == 'declined') {
                _endCallLocally();
              }
            }
            if (callId == state.incomingCall?.id &&
                (status == 'ended' || status == 'declined')) {
              state = state.copyWith(clearIncoming: true);
            }
          },
        )
        .subscribe();
  }

  // ── Initiate outgoing call ─────────────────────────────────

  Future<CallModel?> startCall({
    required String conversationId,
    required String receiverId,
    required CallType type,
  }) async {
    state = state.copyWith(isJoining: true);
    try {
      final call = await _repo.initiateCall(
        conversationId: conversationId,
        receiverId: receiverId,
        type: type,
      );
      state = state.copyWith(
        activeCall: call,
        isJoining: false,
        isMuted: false,
        isCameraOff: false,
        isFrontCamera: true,
        callDuration: 0,
      );
      return call;
    } catch (e) {
      state =
          state.copyWith(isJoining: false, errorMessage: e.toString());
      return null;
    }
  }

  // ── Accept incoming call ───────────────────────────────────

  Future<void> acceptCall() async {
    final incoming = state.incomingCall;
    if (incoming == null) return;

    state = state.copyWith(isJoining: true);
    try {
      final active =
          await _repo.updateCallStatus(incoming.id, CallStatus.active);
      state = state.copyWith(
        activeCall: active,
        clearIncoming: true,
        isJoining: false,
        callDuration: 0,
      );
      _startDurationTimer();
    } catch (e) {
      state =
          state.copyWith(isJoining: false, errorMessage: e.toString());
    }
  }

  /// Called when the callee answers — for the caller side.
  void onCallAccepted() {
    _startDurationTimer();
  }

  // ── Decline incoming call ──────────────────────────────────

  Future<void> declineCall() async {
    final incoming = state.incomingCall;
    if (incoming == null) return;
    await _repo.updateCallStatus(incoming.id, CallStatus.declined);
    state = state.copyWith(clearIncoming: true);
  }

  // ── End active call ────────────────────────────────────────

  Future<void> endCall() async {
    final call = state.activeCall;
    if (call == null) return;
    try {
      await _repo.updateCallStatus(call.id, CallStatus.ended);
    } catch (_) {}
    _endCallLocally();
  }

  void _endCallLocally() {
    _durationTimer?.cancel();
    state = state.copyWith(clearActive: true, callDuration: 0);
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(callDuration: state.callDuration + 1);
    });
  }

  // ── Call controls ──────────────────────────────────────────

  void toggleMute() =>
      state = state.copyWith(isMuted: !state.isMuted);

  void toggleSpeaker() =>
      state = state.copyWith(isSpeakerOn: !state.isSpeakerOn);

  void toggleCamera() =>
      state = state.copyWith(isCameraOff: !state.isCameraOff);

  void flipCamera() =>
      state = state.copyWith(isFrontCamera: !state.isFrontCamera);

  @override
  void dispose() {
    _callChannel?.unsubscribe();
    _durationTimer?.cancel();
    super.dispose();
  }
}

// ── Providers ──────────────────────────────────────────────────────

final callProvider =
    StateNotifierProvider<CallNotifier, CallState>(
  (_) => CallNotifier(),
);

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/livekit_constants.dart';
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
    this.localVideoTrack,
    this.remoteVideoTrack,
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

  // ── Media (LiveKit) ───────────────────────────────────────
  /// Our own camera preview, once the local track is publishing.
  final lk.VideoTrack? localVideoTrack;

  /// The other participant's camera feed, once subscribed.
  final lk.VideoTrack? remoteVideoTrack;

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
    bool clearError = false,
    lk.VideoTrack? localVideoTrack,
    bool clearLocalVideo = false,
    lk.VideoTrack? remoteVideoTrack,
    bool clearRemoteVideo = false,
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
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        localVideoTrack:
            clearLocalVideo ? null : (localVideoTrack ?? this.localVideoTrack),
        remoteVideoTrack: clearRemoteVideo
            ? null
            : (remoteVideoTrack ?? this.remoteVideoTrack),
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

  // LiveKit room for the active call's audio/video. Lives on the
  // notifier (not the CallScreen widget) because the call itself is
  // notifier-scoped state — the room must survive navigation the same
  // way activeCall does.
  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomListener;

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
            type: PostgresChangeFilterType.eq,
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
                  .single();

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
              } else if (status == 'active' &&
                  state.activeCall?.status != CallStatus.active) {
                // The callee just accepted — this is the CALLER's client
                // finding out. (The callee's own client already moved to
                // `active` directly inside acceptCall(); this echoes back
                // to them too since this listener has no per-call filter,
                // but the status-already-active check above makes that a
                // no-op for them.)
                final startedAt = row['started_at'] as String?;
                final updated = state.activeCall!.copyWith(
                  status: CallStatus.active,
                  startedAt: startedAt != null
                      ? DateTime.tryParse(startedAt)
                      : DateTime.now(),
                );
                state = state.copyWith(activeCall: updated, clearError: true);
                _startDurationTimer();
                unawaited(_connectMedia(updated));
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
    state = state.copyWith(isJoining: true, clearError: true);
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
        clearLocalVideo: true,
        clearRemoteVideo: true,
      );
      // Media connects once the callee accepts (see the 'active' branch
      // in _listenForIncomingCalls above) — not here, since LiveKit
      // publishing before anyone can subscribe just wastes a connection
      // while the phone is still ringing.
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

    state = state.copyWith(isJoining: true, clearError: true);
    try {
      final active =
          await _repo.updateCallStatus(incoming.id, CallStatus.active);
      state = state.copyWith(
        activeCall: active,
        clearIncoming: true,
        isJoining: false,
        callDuration: 0,
        clearLocalVideo: true,
        clearRemoteVideo: true,
      );
      _startDurationTimer();
      unawaited(_connectMedia(active));
    } catch (e) {
      state =
          state.copyWith(isJoining: false, errorMessage: e.toString());
    }
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
    unawaited(_disconnectMedia());
    state = state.copyWith(clearActive: true, callDuration: 0);
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer =
        Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(callDuration: state.callDuration + 1);
    });
  }

  // ── LiveKit media ────────────────────────────────────────────
  //
  // Calls the `livekit-call-token` Edge Function — purpose-built for 1:1
  // calls, already deployed (found while wiring this up; it predates
  // this fix and wasn't in this repo's source tree). It looks up the
  // call by callId with a service-role client and rejects the request
  // unless the requester is actually the call's caller_id or
  // receiver_id. That's the property that matters here: the live
  // streaming feature's `livekit-generate-token` mints a token for any
  // room name an authenticated user asks for, which is correct for a
  // public stream audience but would let any user request a token for
  // someone else's private call channel if they got hold of the
  // channel_name — this function can't be used that way.

  Future<void> _connectMedia(CallModel call) async {
    if (_room != null) return; // already connecting/connected

    final room = lk.Room();
    _room = room;
    _roomListener = room.createListener()
      ..on<lk.TrackSubscribedEvent>((event) {
        if (event.track is lk.VideoTrack) {
          state = state.copyWith(
              remoteVideoTrack: event.track as lk.VideoTrack);
        }
      })
      ..on<lk.TrackUnsubscribedEvent>((event) {
        if (event.track == state.remoteVideoTrack) {
          state = state.copyWith(clearRemoteVideo: true);
        }
      });

    try {
      final token = await _repo.fetchLiveKitCallToken(call.id);
      await room.connect(LiveKitConstants.serverUrl, token);
      await room.localParticipant?.setMicrophoneEnabled(!state.isMuted);
      if (call.isVideo && !state.isCameraOff) {
        await room.localParticipant?.setCameraEnabled(true);
        final localTrack =
            room.localParticipant?.videoTrackPublications.firstOrNull?.track;
        state = state.copyWith(
            localVideoTrack: localTrack as lk.VideoTrack?, clearError: true);
      } else {
        state = state.copyWith(clearError: true);
      }
    } catch (e) {
      state = state.copyWith(errorMessage: 'Call audio/video failed: $e');
    }
  }

  Future<void> _disconnectMedia() async {
    await _roomListener?.dispose();
    _roomListener = null;
    final room = _room;
    _room = null;
    await room?.disconnect();
    state = state.copyWith(clearLocalVideo: true, clearRemoteVideo: true);
  }

  // ── Call controls ──────────────────────────────────────────
  // These now drive the real LiveKit room, not just the icon shown.

  Future<void> toggleMute() async {
    final muted = !state.isMuted;
    await _room?.localParticipant?.setMicrophoneEnabled(!muted);
    state = state.copyWith(isMuted: muted);
  }

  /// Loudspeaker vs earpiece routing. NOT wired to real audio output yet —
  /// LiveKit's Room API doesn't expose device audio routing directly, and
  /// doing this properly needs a platform audio-routing call we haven't
  /// verified against the installed livekit_client version. Toggling this
  /// currently only changes the icon; audio keeps playing through
  /// whichever output the OS is already using.
  void toggleSpeaker() =>
      state = state.copyWith(isSpeakerOn: !state.isSpeakerOn);

  Future<void> toggleCamera() async {
    final camOff = !state.isCameraOff;
    await _room?.localParticipant?.setCameraEnabled(!camOff);
    state = state.copyWith(
      isCameraOff: camOff,
      clearLocalVideo: camOff,
    );
    if (!camOff) {
      final localTrack =
          _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
      state = state.copyWith(localVideoTrack: localTrack as lk.VideoTrack?);
    }
  }

  /// Switches between front/back camera by restarting the local video
  /// track with the opposite CameraPosition. NOTE: this specific call
  /// (CameraCaptureOptions/CameraPosition) hasn't been verified against
  /// the installed livekit_client version in a real build — if this
  /// throws, mute/camera/video still work fine, only the flip button
  /// won't; check this call first if it doesn't compile.
  Future<void> flipCamera() async {
    final front = !state.isFrontCamera;
    try {
      await _room?.localParticipant?.setCameraEnabled(
        true,
        cameraCaptureOptions: lk.CameraCaptureOptions(
          cameraPosition: front ? lk.CameraPosition.front : lk.CameraPosition.back,
        ),
      );
      final localTrack =
          _room?.localParticipant?.videoTrackPublications.firstOrNull?.track;
      state = state.copyWith(
        isFrontCamera: front,
        localVideoTrack: localTrack as lk.VideoTrack?,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Could not switch camera: $e');
    }
  }

  @override
  void dispose() {
    _callChannel?.unsubscribe();
    _durationTimer?.cancel();
    _roomListener?.dispose();
    _room?.disconnect();
    super.dispose();
  }
}

// ── Providers ──────────────────────────────────────────────────────

final callProvider =
    StateNotifierProvider<CallNotifier, CallState>(
  (_) => CallNotifier(),
);

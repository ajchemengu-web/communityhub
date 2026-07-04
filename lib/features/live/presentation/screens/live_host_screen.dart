import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../../../core/constants/livekit_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../live/domain/models/live_stream_model.dart';
import '../../../live/data/live_repository.dart';
import '../providers/live_provider.dart';

class LiveHostScreen extends ConsumerStatefulWidget {
  const LiveHostScreen({super.key, required this.stream});
  final LiveStreamModel stream;

  @override
  ConsumerState<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends ConsumerState<LiveHostScreen> {
  final _commentCtrl = TextEditingController();
  final _room = lk.Room();
  lk.EventsListener<lk.RoomEvent>? _listener;

  bool _isConnecting = true;
  bool _isMicMuted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listener = _room.createListener();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final token = await LiveRepository.instance
          .fetchLiveKitToken(widget.stream.channelName, isHost: true);
      await _room.connect(LiveKitConstants.serverUrl, token);
      await _room.localParticipant?.setCameraEnabled(true);
      await _room.localParticipant?.setMicrophoneEnabled(true);
      if (mounted) setState(() => _isConnecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _error = 'Could not start the camera: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _listener?.dispose();
    _room.disconnect();
    LiveRepository.instance.endStream(widget.stream.id);
    super.dispose();
  }

  Future<void> _toggleMic() async {
    final muted = !_isMicMuted;
    await _room.localParticipant?.setMicrophoneEnabled(!muted);
    setState(() => _isMicMuted = muted);
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(liveCommentsProvider(widget.stream.id));
    final localVideoTrack =
        _room.localParticipant?.videoTrackPublications.firstOrNull?.track;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _isConnecting
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70)),
                        ),
                      )
                    : localVideoTrack != null
                        ? lk.VideoTrackRenderer(localVideoTrack as lk.VideoTrack)
                        : const Center(
                            child: Text('Waiting for camera…',
                                style: TextStyle(color: Colors.white54)),
                          ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(widget.stream.title,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  IconButton(
                    icon: Icon(_isMicMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: Colors.white),
                    onPressed: _toggleMic,
                  ),
                  TextButton(
                    onPressed: () => _confirmEnd(context),
                    child: const Text('End',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 80,
            left: 12,
            right: 12,
            child: _CommentsList(comments: comments),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _CommentInput(
              ctrl: _commentCtrl,
              onSend: () async {
                final text = _commentCtrl.text.trim();
                if (text.isEmpty) return;
                _commentCtrl.clear();
                await LiveRepository.instance.sendComment(widget.stream.id, text);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('End stream?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop();
  }
}

// ── Live Viewer Screen ─────────────────────────────────────────────

class LiveViewerScreen extends ConsumerStatefulWidget {
  const LiveViewerScreen({super.key, required this.stream});
  final LiveStreamModel stream;

  @override
  ConsumerState<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends ConsumerState<LiveViewerScreen> {
  final _commentCtrl = TextEditingController();
  final _room = lk.Room();
  lk.EventsListener<lk.RoomEvent>? _listener;

  lk.VideoTrack? _remoteVideoTrack;
  bool _isConnecting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    LiveRepository.instance.joinStream(widget.stream.id);
    _listener = _room.createListener()
      ..on<lk.TrackSubscribedEvent>((event) {
        if (event.track is lk.VideoTrack && mounted) {
          setState(() => _remoteVideoTrack = event.track as lk.VideoTrack);
        }
      })
      ..on<lk.TrackUnsubscribedEvent>((event) {
        if (mounted && event.track == _remoteVideoTrack) {
          setState(() => _remoteVideoTrack = null);
        }
      });
    _connect();
  }

  Future<void> _connect() async {
    try {
      final token = await LiveRepository.instance
          .fetchLiveKitToken(widget.stream.channelName, isHost: false);
      await _room.connect(LiveKitConstants.serverUrl, token);
      if (mounted) setState(() => _isConnecting = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _error = 'Could not connect to this stream: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _listener?.dispose();
    _room.disconnect();
    LiveRepository.instance.leaveStream(widget.stream.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = widget.stream;
    final comments = ref.watch(liveCommentsProvider(stream.id));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: _remoteVideoTrack != null
                ? lk.VideoTrackRenderer(_remoteVideoTrack!)
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundImage: stream.hostAvatar != null
                              ? NetworkImage(stream.hostAvatar!)
                              : null,
                          backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                          child: stream.hostAvatar == null
                              ? const Icon(Icons.person, color: Colors.white, size: 40)
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Text(stream.hostName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(stream.title,
                            style: const TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 24),
                        if (_isConnecting)
                          const CircularProgressIndicator()
                        else if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(_error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white38, fontSize: 13)),
                          )
                        else ...[
                          const Icon(Icons.live_tv_rounded, color: Colors.white24, size: 48),
                          const SizedBox(height: 12),
                          const Text('Waiting for host video…',
                              style: TextStyle(color: Colors.white38, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.remove_red_eye_rounded,
                      color: Colors.white70, size: 14),
                  const SizedBox(width: 4),
                  Text('${stream.viewerCount}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),

          Positioned(
            bottom: 80,
            left: 12,
            right: 12,
            child: _CommentsList(comments: comments),
          ),

          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _CommentInput(
              ctrl: _commentCtrl,
              onSend: () async {
                final text = _commentCtrl.text.trim();
                if (text.isEmpty) return;
                _commentCtrl.clear();
                await LiveRepository.instance.sendComment(stream.id, text);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────

class _CommentsList extends StatelessWidget {
  const _CommentsList({required this.comments});
  final List<LiveCommentModel> comments;

  @override
  Widget build(BuildContext context) {
    final list = comments;
    if (list.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: list.reversed.take(6).map((c) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: RichText(
            text: TextSpan(children: [
              TextSpan(
                text: '${c.userName}  ',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
              TextSpan(
                text: c.content,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}

class _CommentInput extends StatelessWidget {
  const _CommentInput({required this.ctrl, required this.onSend});
  final TextEditingController ctrl;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      padding: EdgeInsets.fromLTRB(
          12, 8, 12, 8 + MediaQuery.of(context).viewInsets.bottom),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Say something…',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSend,
            child: const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.primary,
              child: Icon(Icons.send_rounded, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

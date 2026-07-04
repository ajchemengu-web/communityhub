import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../live/domain/models/live_stream_model.dart';
import '../../../live/data/live_repository.dart';
import '../providers/live_provider.dart';

// Agora RTC integration is stubbed pending resolution of the
// io.agora.rtc namespace conflict in agora_rtc_engine on AGP 8.x.
// Database, provider, routing, and comment infrastructure are all intact.

class LiveHostScreen extends ConsumerStatefulWidget {
  const LiveHostScreen({super.key, required this.stream});
  final LiveStreamModel stream;

  @override
  ConsumerState<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends ConsumerState<LiveHostScreen> {
  final _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    LiveRepository.instance.endStream(widget.stream.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comments = ref.watch(liveCommentsProvider(widget.stream.id));

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.videocam_off_rounded, color: Colors.white24, size: 64),
                SizedBox(height: 16),
                Text('Live camera coming soon',
                    style: TextStyle(color: Colors.white54, fontSize: 16)),
                SizedBox(height: 8),
                Text('Agora SDK re-integration in progress',
                    style: TextStyle(color: Colors.white30, fontSize: 12)),
              ],
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
    if (confirmed == true && mounted) Navigator.of(context).pop();
  }
}

// ── Live Viewer Screen ─────────────────────────────────────────────

class LiveViewerScreen extends ConsumerWidget {
  const LiveViewerScreen({super.key, required this.stream});
  final LiveStreamModel stream;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comments = ref.watch(liveCommentsProvider(stream.id));
    final commentCtrl = TextEditingController();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
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
                const Icon(Icons.live_tv_rounded, color: Colors.white24, size: 48),
                const SizedBox(height: 12),
                const Text('Live video coming soon',
                    style: TextStyle(color: Colors.white38, fontSize: 13)),
              ],
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
              ctrl: commentCtrl,
              onSend: () async {
                final text = commentCtrl.text.trim();
                if (text.isEmpty) return;
                commentCtrl.clear();
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

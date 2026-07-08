import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:video_player/video_player.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../chat/data/chat_repository.dart';
import '../../../home/data/feed_repository.dart';
import '../../../home/domain/models/story_model.dart';
import '../providers/story_viewer_provider.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.userId,
    required this.stories,
    this.initialIndex = 0,
  });

  final String userId;
  final List<StoryModel> stories;
  final int initialIndex;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late PageController _pageCtrl;
  late AnimationController _progressCtrl;
  int _currentIndex = 0;
  VideoPlayerController? _videoCtrl;
  bool _isPaused = false;

  static const _storyDuration = Duration(seconds: 6);

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _currentIndex);
    _progressCtrl = AnimationController(vsync: this, duration: _storyDuration);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _loadStory(_currentIndex);
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    _pageCtrl.dispose();
    _videoCtrl?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _loadStory(int index) {
    _videoCtrl?.dispose();
    _videoCtrl = null;
    _progressCtrl.reset();

    final story = widget.stories[index];

    // Mark as seen
    ref.read(storyViewerProvider.notifier).markSeen(story.id);

    if (story.isVideo) {
      _videoCtrl =
          VideoPlayerController.networkUrl(Uri.parse(story.mediaUrl))
            ..initialize().then((_) {
              if (mounted) {
                setState(() {});
                _videoCtrl!.play();
                _progressCtrl.duration = _videoCtrl!.value.duration;
                _startProgress();
              }
            });
    } else {
      _progressCtrl.duration = _storyDuration;
      _startProgress();
    }
  }

  void _startProgress() {
    _progressCtrl.forward(from: 0).then((_) {
      if (mounted && !_isPaused) _nextStory();
    });
  }

  void _nextStory() {
    if (_currentIndex < widget.stories.length - 1) {
      setState(() => _currentIndex++);
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      _loadStory(_currentIndex);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prevStory() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex--);
      _pageCtrl.previousPage(
          duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      _loadStory(_currentIndex);
    }
  }

  void _onLongPressStart(_) {
    _isPaused = true;
    _progressCtrl.stop();
    _videoCtrl?.pause();
  }

  void _onLongPressEnd(_) {
    _isPaused = false;
    _progressCtrl.forward();
    _videoCtrl?.play();
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.stories[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressEnd: _onLongPressEnd,
        onTapUp: (details) {
          final half = MediaQuery.of(context).size.width / 2;
          if (details.globalPosition.dx < half) {
            _prevStory();
          } else {
            _nextStory();
          }
        },
        onVerticalDragEnd: (details) {
          if (details.primaryVelocity != null &&
              details.primaryVelocity! > 200) {
            Navigator.of(context).pop();
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── Media ──────────────────────────────────────
            PageView.builder(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.stories.length,
              itemBuilder: (_, i) {
                final s = widget.stories[i];
                if (s.isVideo && _videoCtrl != null && i == _currentIndex) {
                  return _videoCtrl!.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _videoCtrl!.value.size.width,
                            height: _videoCtrl!.value.size.height,
                            child: VideoPlayer(_videoCtrl!),
                          ),
                        )
                      : const Center(child: CircularProgressIndicator());
                }
                return s.mediaUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: s.mediaUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.black),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.black26),
                      )
                    : Container(color: Colors.black);
              },
            ),

            // ── Gradient overlays ──────────────────────────
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
              ),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: [Colors.black45, Colors.transparent],
                  ),
                ),
              ),
            ),

            // ── Progress bars ──────────────────────────────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: List.generate(widget.stories.length, (i) {
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: _ProgressBar(
                          filled: i < _currentIndex,
                          active: i == _currentIndex,
                          animation: i == _currentIndex
                              ? _progressCtrl
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),

            // ── Header: avatar + name + time + close ───────
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 24, 12, 0),
                child: Row(
                  children: [
                    // Avatar
                    Container(
                      width: 38,
                      height: 38,
                      padding: const EdgeInsets.all(1.5),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AppColors.storyGradient,
                      ),
                      child: ClipOval(
                        child: story.avatarUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: story.avatarUrl,
                                fit: BoxFit.cover)
                            : Container(
                                color: AppColors.primaryLight,
                                child: Center(
                                  child: Text(
                                    story.username.isNotEmpty
                                        ? story.username[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Username + time
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(
                                story.username,
                                style: AppTextStyles.labelMedium.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (story.isVerified) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.verified,
                                    size: 13, color: AppColors.primary),
                              ],
                            ],
                          ),
                          Text(
                            timeago.format(story.createdAt),
                            style: AppTextStyles.labelSmall
                                .copyWith(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),

                    // Close
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.close,
                          color: Colors.white, size: 26),
                    ),
                  ],
                ),
              ),
            ),

            // ── Caption / text overlay ─────────────────────
            if (story.caption != null && story.caption!.isNotEmpty)
              Positioned(
                bottom: 60,
                left: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    story.caption!,
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: Colors.white, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // ── Reply input (others' stories) or viewer count (yours) ──
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: story.userId != SupabaseService.currentUserId
                    ? _ReplyInput(story: story)
                    : _ViewerCountPill(story: story),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Progress Bar
// ─────────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.filled,
    required this.active,
    this.animation,
  });
  final bool filled;
  final bool active;
  final AnimationController? animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2.5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: active && animation != null
            ? AnimatedBuilder(
                animation: animation!,
                builder: (_, __) => LinearProgressIndicator(
                  value: animation!.value,
                  backgroundColor: Colors.white30,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : LinearProgressIndicator(
                value: filled ? 1.0 : 0.0,
                backgroundColor: Colors.white30,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Reply Input
// ─────────────────────────────────────────────────────────────────

class _ReplyInput extends StatefulWidget {
  const _ReplyInput({required this.story});
  final StoryModel story;

  @override
  State<_ReplyInput> createState() => _ReplyInputState();
}

class _ReplyInputState extends State<_ReplyInput> {
  final _ctrl = TextEditingController();
  bool _hasFocus = false;
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final convo = await ChatRepository.instance
          .getOrCreateDirectConversation(widget.story.userId);
      await ChatRepository.instance.sendMessage(
        conversationId: convo.id,
        content: text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Replied to ${widget.story.username}'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
        _ctrl.clear();
        FocusScope.of(context).unfocus();
        setState(() => _hasFocus = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not send reply: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              onTap: () => setState(() => _hasFocus = true),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Reply to ${widget.story.username}…',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Colors.white),
                ),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
          if (_hasFocus || _ctrl.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded,
                        color: Colors.white, size: 18),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Viewer Count Pill — shown instead of the reply input when this is
// your own story. Tap to see who's viewed it.
// ─────────────────────────────────────────────────────────────────

class _ViewerCountPill extends StatefulWidget {
  const _ViewerCountPill({required this.story});
  final StoryModel story;

  @override
  State<_ViewerCountPill> createState() => _ViewerCountPillState();
}

class _ViewerCountPillState extends State<_ViewerCountPill> {
  List<Map<String, dynamic>>? _viewers;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ViewerCountPill old) {
    super.didUpdateWidget(old);
    if (old.story.id != widget.story.id) {
      setState(() => _viewers = null);
      _load();
    }
  }

  Future<void> _load() async {
    final viewers =
        await FeedRepository.instance.fetchStoryViewers(widget.story.id);
    if (mounted) setState(() => _viewers = viewers);
  }

  void _showViewers() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _ViewersSheet(viewers: _viewers ?? []),
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _viewers?.length ?? 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: GestureDetector(
        onTap: _viewers == null ? null : _showViewers,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.remove_red_eye_outlined,
                color: Colors.white70, size: 18),
            const SizedBox(width: 6),
            Text(
              _viewers == null ? 'Loading…' : '$count views',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewersSheet extends StatelessWidget {
  const _ViewersSheet({required this.viewers});
  final List<Map<String, dynamic>> viewers;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 14),
          Text('${viewers.length} views',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Expanded(
            child: viewers.isEmpty
                ? const Center(
                    child: Text('No views yet',
                        style: TextStyle(color: Colors.white38)),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    itemCount: viewers.length,
                    itemBuilder: (_, i) {
                      final v = viewers[i];
                      final user =
                          Map<String, dynamic>.from(v['users'] as Map? ?? {});
                      final avatarUrl = user['avatar_url'] as String?;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF2A2A2A),
                          backgroundImage:
                              (avatarUrl?.isNotEmpty ?? false)
                                  ? NetworkImage(avatarUrl!)
                                  : null,
                          child: (avatarUrl?.isEmpty ?? true)
                              ? const Icon(Icons.person,
                                  color: Colors.white38)
                              : null,
                        ),
                        title: Text(user['username'] as String? ?? '',
                            style: const TextStyle(color: Colors.white)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

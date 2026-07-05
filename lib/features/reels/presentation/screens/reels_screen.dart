import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:share_plus/share_plus.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/youtube_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../ads/presentation/widgets/reel_ad_overlay.dart';
import '../../data/reels_feed_provider.dart';

// ─── YouTube OAuth ────────────────────────────────────────────────

final _googleSignIn = GoogleSignIn(scopes: [
  'https://www.googleapis.com/auth/youtube.force-ssl',
]);

Future<String?> _getYouTubeToken() async {
  try {
    var account = _googleSignIn.currentUser ??
        await _googleSignIn.signInSilently() ??
        await _googleSignIn.signIn();
    if (account == null) return null;
    return (await account.authentication).accessToken;
  } catch (_) {
    return null;
  }
}

final _dio = Dio();
const _ytBase = 'https://www.googleapis.com/youtube/v3';

Future<void> _ytLike(String videoId) async {
  final token = await _getYouTubeToken();
  if (token == null) return;
  try {
    await _dio.post('$_ytBase/videos/rate',
        queryParameters: {'id': videoId, 'rating': 'like'},
        options: Options(headers: {'Authorization': 'Bearer $token'}));
  } catch (_) {}
}

Future<void> _ytSubscribe(String channelId) async {
  final token = await _getYouTubeToken();
  if (token == null) return;
  try {
    await _dio.post(
        '$_ytBase/subscriptions',
        queryParameters: {'part': 'snippet'},
        data: jsonEncode({
          'snippet': {
            'resourceId': {'kind': 'youtube#channel', 'channelId': channelId}
          }
        }),
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }));
  } catch (_) {}
}

Future<void> _ytComment(String videoId, String text) async {
  final token = await _getYouTubeToken();
  if (token == null) return;
  try {
    await _dio.post(
        '$_ytBase/commentThreads',
        queryParameters: {'part': 'snippet'},
        data: jsonEncode({
          'snippet': {
            'videoId': videoId,
            'topLevelComment': {
              'snippet': {'textOriginal': text}
            }
          }
        }),
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }));
  } catch (_) {}
}

// ─────────────────────────────────────────────────────────────────
// Reels Screen
// ─────────────────────────────────────────────────────────────────

/// A slot in the reels PageView — either a real video or an ad slide.
class _ReelFeedEntry {
  const _ReelFeedEntry._(this.video, this.isAd);
  final YouTubeVideo? video;
  final bool isAd;
  factory _ReelFeedEntry.video(YouTubeVideo v) => _ReelFeedEntry._(v, false);
  factory _ReelFeedEntry.ad() => const _ReelFeedEntry._(null, true);
}

class ReelsScreen extends ConsumerStatefulWidget {
  const ReelsScreen({super.key, this.initialIndex = 0, this.initialVideos});
  final int initialIndex;
  final List<YouTubeVideo>? initialVideos;

  @override
  ConsumerState<ReelsScreen> createState() => _ReelsScreenState();
}

class _ReelsScreenState extends ConsumerState<ReelsScreen> {
  late final PageController _pageCtrl;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _goNext(int total) {
    if (_currentIndex < total - 1) {
      _pageCtrl.animateToPage(
        _currentIndex + 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goPrev() {
    if (_currentIndex > 0) {
      _pageCtrl.animateToPage(
        _currentIndex - 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialVideos != null) {
      return _buildReels(widget.initialVideos!);
    }
    final feedAsync = ref.watch(reelsFeedProvider);
    return feedAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (_, __) => const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: Text('Could not load reels',
                style: TextStyle(color: Colors.white))),
      ),
      data: _buildReels,
    );
  }

  /// Inserts an ad slide every [AppConstants.adFrequency] videos.
  List<_ReelFeedEntry> _interleaveAds(List<YouTubeVideo> videos) {
    final result = <_ReelFeedEntry>[];
    for (int i = 0; i < videos.length; i++) {
      result.add(_ReelFeedEntry.video(videos[i]));
      if ((i + 1) % AppConstants.adFrequency == 0) {
        result.add(_ReelFeedEntry.ad());
      }
    }
    return result;
  }

  /// Same swipe-up/down gesture wiring as `_ReelItem._swipeZone`, reused
  /// for the ad slide since it isn't a `_ReelItem`.
  Widget _swipeZoneForAd({
    required VoidCallback onSwipeUp,
    required VoidCallback onSwipeDown,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) onSwipeUp();
        if (v > 300) onSwipeDown();
      },
      child: child,
    );
  }

  Widget _buildReels(List<YouTubeVideo> videos) {
    if (videos.isEmpty) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
            child: Text('No videos available',
                style: TextStyle(color: Colors.white))),
      );
    }

    final items = _interleaveAds(videos);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // PageView uses NeverScrollableScrollPhysics — we drive it manually
          // from swipe zones inside each _ReelItem (which are pure Flutter,
          // not WebViews, so gesture detection is reliable).
          PageView.builder(
            controller: _pageCtrl,
            scrollDirection: Axis.vertical,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _currentIndex = i),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item.isAd) {
                return _swipeZoneForAd(
                  onSwipeUp: () => _goNext(items.length),
                  onSwipeDown: _goPrev,
                  child: const ReelAdOverlay(),
                );
              }
              return _ReelItem(
                key: ValueKey(item.video!.id),
                video: item.video!,
                isActive: i == _currentIndex,
                onSwipeUp: () => _goNext(items.length),
                onSwipeDown: _goPrev,
              );
            },
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 22),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Single Reel Item
//
// Layout (top → bottom):
//   [Top zone — Flutter only, detects swipes — channel info]
//   [Video — 16:9 WebView, full screen width]
//   [Bottom zone — Flutter only, detects swipes — title + actions]
//
// Swipe zones are pure Flutter widgets, so they reliably receive
// vertical drag gestures even on Android where WebViews absorb touches.
// ─────────────────────────────────────────────────────────────────

class _ReelItem extends StatefulWidget {
  const _ReelItem({
    super.key,
    required this.video,
    required this.isActive,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  final YouTubeVideo video;
  final bool isActive;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  @override
  State<_ReelItem> createState() => _ReelItemState();
}

class _ReelItemState extends State<_ReelItem>
    with AutomaticKeepAliveClientMixin {
  late YoutubePlayerController _ctrl;
  bool _liked = false;
  bool _saved = false;
  bool _subscribed = false;
  int _likeCount = 0;
  bool _paused = false;
  // Start muted so Android's autoplay policy allows immediate playback.
  // User can tap the sound icon to unmute.
  bool _muted = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.video.likeCount ?? 0;
    _ctrl = YoutubePlayerController.fromVideoId(
      videoId: widget.video.id,
      // Always autoplay — muted autoplay is allowed by browser policy.
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: false,
        showFullscreenButton: false,
        playsInline: true,
        mute: true,   // muted = autoplay works on Android WebView
        loop: true,
        enableCaption: false,
        showVideoAnnotations: false,
      ),
    );
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      final row = await SupabaseService.client
          .from('saved_reels')
          .select('id')
          .eq('user_id', uid)
          .eq('youtube_id', widget.video.id)
          .maybeSingle();
      if (mounted) setState(() => _saved = row != null);
    } catch (_) {}
  }

  @override
  void didUpdateWidget(_ReelItem old) {
    super.didUpdateWidget(old);
    if (widget.isActive && !old.isActive) {
      _ctrl.playVideo();
      setState(() => _paused = false);
    } else if (!widget.isActive && old.isActive) {
      _ctrl.pauseVideo();
    }
  }

  @override
  void dispose() {
    _ctrl.close();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_paused) {
      _ctrl.playVideo();
    } else {
      _ctrl.pauseVideo();
    }
    setState(() => _paused = !_paused);
  }

  void _toggleMute() {
    if (_muted) {
      _ctrl.unMute();
    } else {
      _ctrl.mute();
    }
    setState(() => _muted = !_muted);
  }

  Future<void> _toggleLike() async {
    setState(() {
      _liked = !_liked;
      _likeCount += _liked ? 1 : -1;
    });
    if (_liked) await _ytLike(widget.video.id);
  }

  Future<void> _toggleSave() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    setState(() => _saved = !_saved);
    try {
      if (_saved) {
        await SupabaseService.client.from('saved_reels').upsert({
          'user_id': uid,
          'youtube_id': widget.video.id,
          'title': widget.video.title,
          'thumbnail_url': widget.video.thumbnailUrl,
          'channel_title': widget.video.channelTitle,
        });
      } else {
        await SupabaseService.client
            .from('saved_reels')
            .delete()
            .eq('user_id', uid)
            .eq('youtube_id', widget.video.id);
      }
    } catch (_) {}
  }

  Future<void> _toggleSubscribe() async {
    setState(() => _subscribed = !_subscribed);
    if (_subscribed) await _ytSubscribe(widget.video.channelId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_subscribed
            ? 'Subscribed to ${widget.video.channelTitle} on YouTube ✓'
            : 'Unsubscribed'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ));
    }
  }

  void _share() => Share.share(
        'Watch "${widget.video.title}" on YouTube: https://youtu.be/${widget.video.id}',
      );

  void _showComments() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _CommentsSheet(video: widget.video),
    );
  }

  // ── Gesture detection helper ───────────────────────────────────
  // Wraps a child in a GestureDetector that fires swipe up/down.
  // Used on the TOP and BOTTOM Flutter-only zones (not the WebView).
  Widget _swipeZone({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -300) widget.onSwipeUp();
        if (v > 300) widget.onSwipeDown();
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    // 16:9 video height at full screen width
    final videoHeight = screenWidth * 9 / 16;
    // Remaining height split between top and bottom zones
    final zoneHeight = (screenHeight - videoHeight) / 2;

    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          Column(
            children: [
              // ── TOP ZONE — pure Flutter, swipe zone ────────────
              _swipeZone(
                child: _TopZone(
                  video: widget.video,
                  subscribed: _subscribed,
                  onSubscribe: _toggleSubscribe,
                  height: zoneHeight,
                  muted: _muted,
                  onToggleMute: _toggleMute,
                ),
              ),

              // ── VIDEO — 16:9 WebView at full screen width ──────
              // Tap the video to pause/play; swipes here won't work
              // reliably (WebView absorbs them) — users swipe in the
              // top/bottom zones instead.
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _togglePlayPause,
                child: SizedBox(
                  width: screenWidth,
                  height: videoHeight,
                  child: YoutubePlayer(
                    controller: _ctrl,
                    aspectRatio: 16 / 9,
                  ),
                ),
              ),

              // ── BOTTOM ZONE — pure Flutter, swipe zone ─────────
              // Action buttons live INSIDE this zone so they are never
              // overlapped by the WebView (which renders above Flutter
              // widgets on Android with Hybrid Composition).
              _swipeZone(
                child: _BottomZone(
                  video: widget.video,
                  height: zoneHeight,
                  liked: _liked,
                  likeCount: _likeCount,
                  saved: _saved,
                  subscribed: _subscribed,
                  onLike: _toggleLike,
                  onComment: _showComments,
                  onShare: _share,
                  onSave: _toggleSave,
                  onSubscribe: _toggleSubscribe,
                ),
              ),
            ],
          ),

        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Top zone — channel info
// ─────────────────────────────────────────────────────────────────

class _TopZone extends StatelessWidget {
  const _TopZone({
    required this.video,
    required this.subscribed,
    required this.onSubscribe,
    required this.height,
    required this.muted,
    required this.onToggleMute,
  });
  final YouTubeVideo video;
  final bool subscribed;
  final VoidCallback onSubscribe;
  final double height;
  final bool muted;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 48,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: Colors.red,
                child: Icon(Icons.smart_display,
                    color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  video.channelTitle,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onSubscribe,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: subscribed ? Colors.white24 : Colors.red,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    subscribed ? 'Subscribed' : 'Subscribe',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.keyboard_arrow_up_rounded,
                  color: Colors.white54, size: 22),
              const SizedBox(width: 4),
              const Text('Swipe up for next',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              const Spacer(),
              // Mute/unmute button — starts muted for autoplay
              GestureDetector(
                onTap: onToggleMute,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Bottom zone — title, views, action buttons, swipe hint
// All Flutter widgets — never overlapped by the WebView.
// ─────────────────────────────────────────────────────────────────

class _BottomZone extends StatelessWidget {
  const _BottomZone({
    required this.video,
    required this.height,
    required this.liked,
    required this.likeCount,
    required this.saved,
    required this.subscribed,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onSubscribe,
  });

  final YouTubeVideo video;
  final double height;
  final bool liked;
  final int likeCount;
  final bool saved;
  final bool subscribed;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: height,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Left: title + views + swipe hint ──────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (video.viewCount != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${_fmt(video.viewCount!)} views',
                    style:
                        const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
                const Spacer(),
                const Text('↓  Swipe down for previous',
                    style:
                        TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // ── Right: action buttons (fully in Flutter zone) ──
          _SideActions(
            liked: liked,
            likeCount: likeCount,
            saved: saved,
            subscribed: subscribed,
            onLike: onLike,
            onComment: onComment,
            onShare: onShare,
            onSave: onSave,
            onSubscribe: onSubscribe,
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}


// ─────────────────────────────────────────────────────────────────
// Side action buttons
// ─────────────────────────────────────────────────────────────────

class _SideActions extends StatelessWidget {
  const _SideActions({
    required this.liked,
    required this.likeCount,
    required this.saved,
    required this.subscribed,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onSubscribe,
  });
  final bool liked;
  final int likeCount;
  final bool saved;
  final bool subscribed;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SideBtn(
          icon: liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
          label: _fmt(likeCount),
          color: liked ? AppColors.primary : Colors.white,
          onTap: onLike,
        ),
        const SizedBox(height: 22),
        _SideBtn(
          icon: Icons.comment_outlined,
          label: 'Comment',
          color: Colors.white,
          onTap: onComment,
        ),
        const SizedBox(height: 22),
        _SideBtn(
          icon: Icons.reply_rounded,
          label: 'Share',
          color: Colors.white,
          onTap: onShare,
        ),
        const SizedBox(height: 22),
        _SideBtn(
          icon: saved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded,
          label: 'Save',
          color: saved ? AppColors.secondary : Colors.white,
          onTap: onSave,
        ),
        const SizedBox(height: 22),
        _SideBtn(
          icon: subscribed
              ? Icons.notifications_active_rounded
              : Icons.add_circle_outline_rounded,
          label: subscribed ? 'Following' : 'Follow',
          color: subscribed ? Colors.red : Colors.white,
          onTap: onSubscribe,
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _SideBtn extends StatelessWidget {
  const _SideBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Comments sheet
// ─────────────────────────────────────────────────────────────────

class _CommentsSheet extends StatefulWidget {
  const _CommentsSheet({required this.video});
  final YouTubeVideo video;

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  final _ctrl = TextEditingController();
  bool _posting = false;
  final List<Map<String, String>> _localComments = [];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _posting = true);

    await _ytComment(widget.video.id, text);

    final uid = SupabaseService.currentUserId;
    if (uid != null) {
      try {
        await SupabaseService.client.from('reel_comments').insert({
          'user_id': uid,
          'youtube_id': widget.video.id,
          'content': text,
        });
      } catch (_) {}
    }

    setState(() {
      _localComments.insert(0, {'text': text, 'user': 'You'});
      _posting = false;
    });
    _ctrl.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Comment posted on YouTube!'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (_, scrollCtrl) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Text('Comments',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                SizedBox(width: 8),
                Icon(Icons.youtube_searched_for_rounded,
                    color: Colors.red, size: 18),
                SizedBox(width: 4),
                Text('syncs to YouTube',
                    style: TextStyle(color: Colors.red, fontSize: 11)),
              ],
            ),
          ),
          const Divider(color: Colors.white12),
          Expanded(
            child: _localComments.isEmpty
                ? const Center(
                    child: Text('Be the first to comment!',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 13)),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    itemCount: _localComments.length,
                    itemBuilder: (_, i) {
                      final c = _localComments[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.primary,
                              child: Icon(Icons.person,
                                  color: Colors.white, size: 16),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c['user'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12)),
                                  const SizedBox(height: 2),
                                  Text(c['text'] ?? '',
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Container(
            color: const Color(0xFF0A0A0A),
            padding: EdgeInsets.fromLTRB(
                12, 8, 12,
                MediaQuery.of(context).viewInsets.bottom + 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    style:
                        const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Add a comment…',
                      hintStyle: const TextStyle(
                          color: Colors.white38, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    onSubmitted: (_) => _post(),
                  ),
                ),
                const SizedBox(width: 8),
                _posting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary))
                    : GestureDetector(
                        onTap: _post,
                        child: const Icon(Icons.send_rounded,
                            color: AppColors.primary, size: 26),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

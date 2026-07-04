import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../core/services/youtube_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/models/post_model.dart';
import '../providers/feed_provider.dart';

// ─────────────────────────────────────────────────────────────────
// Extracts a YouTube video ID from various URL formats
// ─────────────────────────────────────────────────────────────────
String? extractYoutubeId(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.length == 11 && !url.contains('/') && !url.contains('.')) return url;
  final uri = Uri.tryParse(url);
  if (uri == null) return null;
  if (uri.host.contains('youtu.be')) return uri.pathSegments.firstOrNull;
  if (uri.queryParameters.containsKey('v')) return uri.queryParameters['v'];
  if (uri.pathSegments.length >= 2) {
    final last2 = uri.pathSegments[uri.pathSegments.length - 2];
    if (last2 == 'embed' || last2 == 'shorts') {
      return uri.pathSegments.last;
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────
// Unified data class so both PostModel and YouTubeVideo can be shown
// ─────────────────────────────────────────────────────────────────
class _VideoData {
  final String videoId;
  final String title;
  final String channelName;
  final String? channelAvatar;
  final int likesCount;
  final int commentsCount;
  final int? viewCount;
  final DateTime createdAt;
  final List<String> tags;

  const _VideoData({
    required this.videoId,
    required this.title,
    required this.channelName,
    this.channelAvatar,
    this.likesCount = 0,
    this.commentsCount = 0,
    this.viewCount,
    required this.createdAt,
    this.tags = const [],
  });

  factory _VideoData.fromPost(PostModel p) {
    final id = extractYoutubeId(p.youtubeUrl) ??
        extractYoutubeId(p.mediaUrls.isNotEmpty ? p.mediaUrls.first : null) ??
        '';
    return _VideoData(
      videoId: id,
      title: p.caption.isNotEmpty ? p.caption : 'Video',
      channelName: p.displayName,
      channelAvatar: p.avatarUrl,
      likesCount: p.likesCount,
      commentsCount: p.commentsCount,
      createdAt: p.createdAt,
      tags: p.tags,
    );
  }

  factory _VideoData.fromYouTube(YouTubeVideo v) {
    return _VideoData(
      videoId: v.id,
      title: v.title,
      channelName: v.channelTitle,
      likesCount: v.likeCount ?? 0,
      viewCount: v.viewCount,
      createdAt: v.publishedAt,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// YouTube-style video detail screen
// Open with either a PostModel or a YouTubeVideo
// ─────────────────────────────────────────────────────────────────

class YoutubePlayerScreen extends ConsumerStatefulWidget {
  const YoutubePlayerScreen.fromPost({
    super.key,
    required PostModel post,
    required this.hubType,
  })  : _post = post,
        _ytVideo = null;

  const YoutubePlayerScreen.fromVideo({
    super.key,
    required YouTubeVideo video,
    this.hubType = 'all',
  })  : _ytVideo = video,
        _post = null;

  final PostModel? _post;
  final YouTubeVideo? _ytVideo;
  final String hubType;

  @override
  ConsumerState<YoutubePlayerScreen> createState() =>
      _YoutubePlayerScreenState();
}

class _YoutubePlayerScreenState extends ConsumerState<YoutubePlayerScreen> {
  late YoutubePlayerController _ctrl;
  late _VideoData _data;
  bool _descExpanded = false;
  bool _subscribed = false;
  bool _disliked = false;

  @override
  void initState() {
    super.initState();
    if (widget._post != null) {
      _data = _VideoData.fromPost(widget._post!);
    } else {
      _data = _VideoData.fromYouTube(widget._ytVideo!);
    }

    _ctrl = YoutubePlayerController.fromVideoId(
      videoId: _data.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        playsInline: true,
        mute: false,
        loop: false,
        enableCaption: true,
        strictRelatedVideos: true,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.close();
    super.dispose();
  }

  void _toggleLike() {
    if (widget._post != null) {
      ref.read(feedProvider(widget.hubType).notifier).toggleLike(widget._post!.id);
    }
  }

  void _share() {
    final url = 'https://www.youtube.com/watch?v=${_data.videoId}';
    Share.share('$url\n${_data.title}');
  }

  Future<void> _openYouTube() async {
    final url = Uri.parse('https://www.youtube.com/watch?v=${_data.videoId}');
    if (await canLaunchUrl(url)) launchUrl(url, mode: LaunchMode.externalApplication);
  }

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    // If we have a post, read live like state from provider
    int likesCount = _data.likesCount;
    bool isLiked = false;
    if (widget._post != null) {
      final feedAsync = ref.watch(feedProvider(widget.hubType));
      final updated = (feedAsync.valueOrNull ?? [])
          .where((fi) => fi.post?.id == widget._post!.id)
          .map((fi) => fi.post!)
          .firstOrNull;
      if (updated != null) {
        likesCount = updated.likesCount;
        isLiked = updated.isLikedByCurrentUser;
      }
    }

    return YoutubePlayerControllerProvider(
      controller: _ctrl,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // ── Video player ────────────────────────────────────
              YoutubePlayer(controller: _ctrl),

              // ── Scrollable content ──────────────────────────────
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                      const SizedBox(height: 10),

                      // ── Title + meta ───────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: GestureDetector(
                          onTap: () => setState(
                              () => _descExpanded = !_descExpanded),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _data.title,
                                maxLines: _descExpanded ? null : 2,
                                overflow: _descExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 4,
                                children: [
                                  Text('@${_data.channelName}',
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12)),
                                  const Text('·',
                                      style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12)),
                                  Text(
                                    '${_fmtCount(likesCount)} likes',
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12),
                                  ),
                                  if (_data.viewCount != null) ...[
                                    const Text('·',
                                        style: TextStyle(
                                            color: Colors.white38,
                                            fontSize: 12)),
                                    Text(
                                      '${_fmtCount(_data.viewCount!)} views',
                                      style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12),
                                    ),
                                  ],
                                  const Text('·',
                                      style: TextStyle(
                                          color: Colors.white38,
                                          fontSize: 12)),
                                  Text(
                                    timeago.format(_data.createdAt),
                                    style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12),
                                  ),
                                  if (_data.tags.isNotEmpty)
                                    Text(
                                      _data.tags.map((t) => '#$t').join(' '),
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 12),
                                    ),
                                  Text(
                                    _descExpanded
                                        ? 'Show less'
                                        : '...more',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ── Action row ─────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _PillGroup(children: [
                                _PillItem(
                                  icon: isLiked
                                      ? Icons.thumb_up
                                      : Icons.thumb_up_alt_outlined,
                                  label: _fmtCount(likesCount),
                                  active: isLiked,
                                  onTap: _toggleLike,
                                ),
                                const _PillDivider(),
                                _PillItem(
                                  icon: _disliked
                                      ? Icons.thumb_down
                                      : Icons.thumb_down_alt_outlined,
                                  label: '',
                                  active: _disliked,
                                  onTap: () => setState(() => _disliked = !_disliked),
                                ),
                              ]),
                              const SizedBox(width: 8),
                              _ActionPill(
                                  icon: Icons.reply_outlined,
                                  label: 'Share',
                                  onTap: _share),
                              const SizedBox(width: 8),
                              _ActionPill(
                                  icon: Icons.open_in_new_rounded,
                                  label: 'YouTube',
                                  onTap: _openYouTube),
                              const SizedBox(width: 8),
                              _ActionPill(
                                  icon: Icons.more_horiz,
                                  label: '',
                                  onTap: () {}),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),
                      const Divider(color: Color(0xFF2A2A2A), height: 1),

                      // ── Channel + Subscribe ────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundImage: _data.channelAvatar != null
                                  ? CachedNetworkImageProvider(
                                      _data.channelAvatar!)
                                  : null,
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.3),
                              child: _data.channelAvatar == null
                                  ? Text(
                                      _data.channelName.isNotEmpty
                                          ? _data.channelName[0]
                                              .toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600))
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(_data.channelName,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                            ),
                            GestureDetector(
                              onTap: () => setState(
                                  () => _subscribed = !_subscribed),
                              child: AnimatedContainer(
                                duration:
                                    const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _subscribed
                                      ? const Color(0xFF2A2A2A)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _subscribed
                                      ? 'Subscribed'
                                      : 'Subscribe',
                                  style: TextStyle(
                                    color: _subscribed
                                        ? Colors.white
                                        : Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Divider(color: Color(0xFF2A2A2A), height: 1),
                      const SizedBox(height: 8),

                      // ── Comments preview ───────────────────────
                      _CommentsPreview(count: _data.commentsCount),

                      const SizedBox(height: 12),
                      const Divider(color: Color(0xFF2A2A2A), height: 1),
                      const SizedBox(height: 8),

                      // ── Related videos ─────────────────────────
                      _RelatedVideos(
                        hubType: widget.hubType,
                        excludeId: _data.videoId,
                      ),

                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────

class _PillGroup extends StatelessWidget {
  const _PillGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF272727),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: active ? Colors.white : Colors.white70, size: 20),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(label,
                    style: TextStyle(
                        color: active ? Colors.white : Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      );
}

class _PillDivider extends StatelessWidget {
  const _PillDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 20, color: Colors.white24);
}

class _ActionPill extends StatelessWidget {
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: label.isEmpty ? 12 : 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF272727),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              if (label.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
      );
}

class _CommentsPreview extends StatelessWidget {
  const _CommentsPreview({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Text('Comments',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('$count',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 13)),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white38, size: 20),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────
// Related videos — shows YouTube FeedItems from the feed provider
// ─────────────────────────────────────────────────────────────────

class _RelatedVideos extends ConsumerWidget {
  const _RelatedVideos(
      {required this.hubType, required this.excludeId});
  final String hubType;
  final String excludeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(feedProvider(hubType));
    final items = feedAsync.valueOrNull ?? [];
    // Collect related from both YouTube FeedItems and post FeedItems with YouTube URLs
    final List<_RelatedEntry> related = [];
    for (final fi in items) {
      if (fi.isYouTube && fi.youtubeVideo!.id != excludeId) {
        related.add(_RelatedEntry.fromYouTube(fi.youtubeVideo!));
      } else if (fi.post != null) {
        final id = extractYoutubeId(fi.post!.youtubeUrl);
        if (id != null && id != excludeId) {
          related.add(_RelatedEntry.fromPost(fi.post!));
        }
      }
      if (related.length >= 10) break;
    }

    if (related.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
            child: Text('No related videos',
                style: TextStyle(color: Colors.white38))),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: Text('Up next',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
        ),
        ...related.map((e) => _RelatedCard(entry: e, hubType: hubType)),
      ],
    );
  }
}

class _RelatedEntry {
  final String videoId;
  final String title;
  final String channel;
  final String thumbUrl;
  final int likes;
  final int? views;
  final DateTime date;
  final PostModel? post;
  final YouTubeVideo? ytVideo;

  const _RelatedEntry({
    required this.videoId,
    required this.title,
    required this.channel,
    required this.thumbUrl,
    required this.likes,
    this.views,
    required this.date,
    this.post,
    this.ytVideo,
  });

  factory _RelatedEntry.fromYouTube(YouTubeVideo v) => _RelatedEntry(
        videoId: v.id,
        title: v.title,
        channel: v.channelTitle,
        thumbUrl: v.thumbnailUrl,
        likes: v.likeCount ?? 0,
        views: v.viewCount,
        date: v.publishedAt,
        ytVideo: v,
      );

  factory _RelatedEntry.fromPost(PostModel p) {
    final id = extractYoutubeId(p.youtubeUrl) ??
        extractYoutubeId(
            p.mediaUrls.isNotEmpty ? p.mediaUrls.first : null) ??
        '';
    return _RelatedEntry(
      videoId: id,
      title: p.caption.isNotEmpty ? p.caption : 'Video',
      channel: p.displayName,
      thumbUrl: 'https://img.youtube.com/vi/$id/hqdefault.jpg',
      likes: p.likesCount,
      date: p.createdAt,
      post: p,
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.entry, required this.hubType});
  final _RelatedEntry entry;
  final String hubType;

  String _fmtCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => entry.ytVideo != null
              ? YoutubePlayerScreen.fromVideo(
                  video: entry.ytVideo!, hubType: hubType)
              : YoutubePlayerScreen.fromPost(
                  post: entry.post!, hubType: hubType),
        ));
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 160,
                height: 90,
                child: CachedNetworkImage(
                  imageUrl: entry.thumbUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: const Color(0xFF1E1E1E)),
                  errorWidget: (_, __, ___) => Container(
                    color: const Color(0xFF1E1E1E),
                    child: const Center(
                        child: Icon(Icons.play_circle_outline,
                            color: Colors.white24, size: 30)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          height: 1.3)),
                  const SizedBox(height: 4),
                  Text(entry.channel,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                  if (entry.views != null)
                    Text(
                        '${_fmtCount(entry.views!)} views  ·  ${timeago.format(entry.date)}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11))
                  else
                    Text(
                        '${_fmtCount(entry.likes)} likes  ·  ${timeago.format(entry.date)}',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.more_vert, color: Colors.white38, size: 18),
          ],
        ),
      ),
    );
  }
}

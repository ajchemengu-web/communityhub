import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/post_repository.dart';
import '../providers/new_post_provider.dart';

/// Web's post/reel creation screen.
///
/// `new_post_screen.dart` (the native flow) is built on `photo_manager`
/// for its gallery-grid picker — that plugin has no Flutter Web
/// implementation at all, not even a degraded one, so this isn't a
/// bytes-conversion job like the rest of the web-compat work. This is a
/// separate, deliberately simpler screen built on `image_picker`'s
/// web-compatible multi-file picker instead, selected at the router
/// level (see core/router/new_post_route.dart) via the same
/// conditional-export pattern used for video compression — native
/// platforms never see this file, web never sees new_post_screen.dart.
class NewPostScreenWeb extends ConsumerStatefulWidget {
  const NewPostScreenWeb({super.key, this.isReelMode = false});

  final bool isReelMode;

  @override
  ConsumerState<NewPostScreenWeb> createState() => _NewPostScreenWebState();
}

class _NewPostScreenWebState extends ConsumerState<NewPostScreenWeb> {
  final _captionCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();
  final _picker = ImagePicker();
  bool _pickingMedia = false;

  static const _hubs = [
    (AppConstants.hubAll, 'All', Icons.public),
    (AppConstants.hubFaith, 'Faith', Icons.church),
    (AppConstants.hubScience, 'Science', Icons.science_rounded),
    (AppConstants.hubTechnology, 'Technology', Icons.computer_rounded),
    (AppConstants.hubLanguages, 'Languages', Icons.language),
    (AppConstants.hubCareer, 'Career', Icons.work_outline),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.isReelMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(newPostProvider.notifier).setReelMode(true),
      );
    }
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _tagCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  Future<PostMediaFile?> _toMediaFile(XFile xfile) async {
    try {
      final bytes = await xfile.readAsBytes();
      final ext = xfile.name.contains('.') ? xfile.name.split('.').last : 'jpg';
      return PostMediaFile(bytes: bytes, extension: ext);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPhotos() async {
    setState(() => _pickingMedia = true);
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isEmpty) return;
      final remaining = 10 - ref.read(newPostProvider).mediaFiles.length;
      if (remaining <= 0) return;
      final media = <PostMediaFile>[];
      for (final xfile in picked.take(remaining)) {
        final m = await _toMediaFile(xfile);
        if (m != null) media.add(m);
      }
      if (!mounted || media.isEmpty) return;
      ref.read(newPostProvider.notifier).addMedia(media, 'image');
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  Future<void> _pickVideo() async {
    setState(() => _pickingMedia = true);
    try {
      final xfile = await _picker.pickVideo(source: ImageSource.gallery);
      if (xfile == null) return;
      final media = await _toMediaFile(xfile);
      if (!mounted || media == null) return;
      // A post is either all-photos or a single video, matching the
      // native flow's media_type semantics.
      ref.read(newPostProvider.notifier).addMedia([media], 'video');
    } finally {
      if (mounted) setState(() => _pickingMedia = false);
    }
  }

  void _addTag() {
    final tag = _tagCtrl.text.trim();
    if (tag.isEmpty) return;
    ref.read(newPostProvider.notifier).addTag(tag);
    _tagCtrl.clear();
  }

  Future<void> _submit() async {
    ref.read(newPostProvider.notifier).setYoutubeUrl(
        _youtubeCtrl.text.trim().isEmpty ? null : _youtubeCtrl.text.trim());
    await ref.read(newPostProvider.notifier).submit();
    final state = ref.read(newPostProvider);
    if (!mounted) return;
    if (state.status == NewPostStatus.success) {
      ref.read(newPostProvider.notifier).reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post shared!'), backgroundColor: Colors.green),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(newPostProvider);

    ref.listen<NewPostState>(newPostProvider, (_, next) {
      if (next.status == NewPostStatus.error && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? 'Failed to post'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    final isUploading = state.status == NewPostStatus.uploading;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(state.isReel ? 'New Reel' : 'New Post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: isUploading ? null : () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: state.canPost && !isUploading ? _submit : null,
            child: isUploading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Post'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (isUploading && state.uploadTotal > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Uploading ${state.uploadedCount} of ${state.uploadTotal}…',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),

            // ── Hub type ─────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _hubs.map((h) {
                final selected = state.hubType == h.$1;
                return ChoiceChip(
                  label: Text(h.$2),
                  avatar: Icon(h.$3, size: 16),
                  selected: selected,
                  onSelected: isUploading
                      ? null
                      : (_) => ref.read(newPostProvider.notifier).setHub(h.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // ── Caption ──────────────────────────────────────────
            TextField(
              controller: _captionCtrl,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              enabled: !isUploading,
              decoration: const InputDecoration(
                hintText: "What's on your mind?",
                hintStyle: TextStyle(color: Colors.white38),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => ref.read(newPostProvider.notifier).setCaption(v),
            ),
            const SizedBox(height: 16),

            // ── Media strip ──────────────────────────────────────
            if (state.mediaFiles.isNotEmpty)
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.mediaFiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final media = state.mediaFiles[i];
                    final isVideo = state.mediaType == 'video';
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: isVideo
                              ? Container(
                                  width: 100,
                                  height: 100,
                                  color: Colors.white10,
                                  child: const Icon(Icons.videocam,
                                      color: Colors.white54, size: 32),
                                )
                              : Image.memory(
                                  media.bytes,
                                  width: 100,
                                  height: 100,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: isUploading
                                ? null
                                : () => ref.read(newPostProvider.notifier).removeMedia(i),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.black87,
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 8),

            // ── Add media buttons ────────────────────────────────
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: (_pickingMedia || isUploading || state.mediaType == 'video')
                      ? null
                      : _pickPhotos,
                  icon: const Icon(Icons.photo_outlined),
                  label: const Text('Add Photos'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: (_pickingMedia || isUploading || state.mediaFiles.isNotEmpty)
                      ? null
                      : _pickVideo,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Add Video'),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Tags ─────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagCtrl,
                    enabled: !isUploading,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'Add a tag…',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: isUploading ? null : _addTag,
                  icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                ),
              ],
            ),
            if (state.tags.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: state.tags
                      .map((t) => Chip(
                            label: Text('#$t'),
                            onDeleted: isUploading
                                ? null
                                : () => ref.read(newPostProvider.notifier).removeTag(t),
                          ))
                      .toList(),
                ),
              ),
            const SizedBox(height: 20),

            // ── YouTube link (optional) ──────────────────────────
            TextField(
              controller: _youtubeCtrl,
              enabled: !isUploading,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'YouTube link (optional)',
                hintStyle: TextStyle(color: Colors.white38),
                prefixIcon: Icon(Icons.link),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

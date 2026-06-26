import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/new_post_provider.dart';

class NewPostScreen extends ConsumerStatefulWidget {
  const NewPostScreen({super.key});

  @override
  ConsumerState<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends ConsumerState<NewPostScreen> {
  final _captionCtrl = TextEditingController();
  final _tagCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _captionCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  // ── Media Pickers ─────────────────────────────────────────

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage(imageQuality: 80);
    if (files.isEmpty) return;
    ref.read(newPostProvider.notifier).addMedia(
          files.map((xf) => File(xf.path)).toList(),
          'image',
        );
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 3),
    );
    if (file == null) return;
    ref.read(newPostProvider.notifier).addMedia([File(file.path)], 'video');
  }

  Future<void> _pickCamera() async {
    final file =
        await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (file == null) return;
    ref.read(newPostProvider.notifier).addMedia([File(file.path)], 'image');
  }

  // ── Submit ────────────────────────────────────────────────

  Future<void> _submit() async {
    await ref.read(newPostProvider.notifier).submit();
    final state = ref.read(newPostProvider);
    if (!mounted) return;
    if (state.status == NewPostStatus.success) {
      ref.read(newPostProvider.notifier).reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post shared successfully! 🎉'),
          backgroundColor: AppColors.primary,
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final post = ref.watch(newPostProvider);
    final user = SupabaseService.currentUser;

    // Listen for errors
    ref.listen<NewPostState>(newPostProvider, (_, next) {
      if (next.status == NewPostStatus.error && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? 'Failed to post'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('New Post', style: AppTextStyles.titleSmall),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed:
                  post.canPost && post.status != NewPostStatus.uploading
                      ? _submit
                      : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: post.status == NewPostStatus.uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Post'),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Author row ────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(url: user?.userMetadata?['avatar_url'] as String?),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.userMetadata?['full_name'] as String? ?? 'You',
                        style: AppTextStyles.bodyMedium.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _HubPicker(
                        selected: post.hubType,
                        onChanged:
                            ref.read(newPostProvider.notifier).setHub,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Caption ───────────────────────────────────
            TextField(
              controller: _captionCtrl,
              onChanged: ref.read(newPostProvider.notifier).setCaption,
              maxLines: null,
              maxLength: 2200,
              style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
              decoration: const InputDecoration(
                hintText:
                    "What's on your mind? Share faith, tech, or inspiration…",
                hintStyle: TextStyle(color: AppColors.textMuted),
                border: InputBorder.none,
                counterStyle: TextStyle(color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 12),

            // ── Media preview ─────────────────────────────
            if (post.mediaFiles.isNotEmpty) ...[
              _MediaPreviewGrid(
                files: post.mediaFiles,
                onRemove:
                    ref.read(newPostProvider.notifier).removeMedia,
              ),
              const SizedBox(height: 16),
            ],

            const Divider(color: AppColors.darkDivider),
            const SizedBox(height: 12),

            // ── Tags ──────────────────────────────────────
            if (post.tags.isNotEmpty) ...[
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: post.tags
                    .map(
                      (tag) => Chip(
                        label: Text(
                          '#$tag',
                          style: AppTextStyles.labelSmall
                              .copyWith(color: AppColors.primary),
                        ),
                        deleteIcon: const Icon(Icons.close, size: 14),
                        onDeleted: () => ref
                            .read(newPostProvider.notifier)
                            .removeTag(tag),
                        backgroundColor:
                            AppColors.primary.withOpacity(0.12),
                        side: BorderSide(
                            color: AppColors.primary.withOpacity(0.3)),
                        padding: EdgeInsets.zero,
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 12),
            ],
            _TagInput(
              controller: _tagCtrl,
              onAdd: (tag) =>
                  ref.read(newPostProvider.notifier).addTag(tag),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      // ── Bottom toolbar ────────────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            border: Border(top: BorderSide(color: AppColors.darkDivider)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              _ToolbarButton(
                icon: Icons.image_rounded,
                label: 'Photo',
                onTap: _pickImages,
              ),
              _ToolbarButton(
                icon: Icons.videocam_rounded,
                label: 'Video',
                onTap: _pickVideo,
              ),
              _ToolbarButton(
                icon: Icons.camera_alt_rounded,
                label: 'Camera',
                onTap: _pickCamera,
              ),
              const Spacer(),
              Text(
                '${_captionCtrl.text.length}/2200',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Supporting Widgets ─────────────────────────────────────────

class _Avatar extends StatelessWidget {
  const _Avatar({this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundImage: url != null ? NetworkImage(url!) : null,
      backgroundColor: AppColors.primary.withOpacity(0.2),
      child: url == null
          ? const Icon(Icons.person, color: AppColors.primary, size: 20)
          : null,
    );
  }
}

class _HubPicker extends StatelessWidget {
  const _HubPicker({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  static const _hubs = [
    (AppConstants.hubAll, 'All', Icons.public),
    (AppConstants.hubFaith, 'Faith', Icons.church),
    (AppConstants.hubCareer, 'Career', Icons.work),
  ];

  @override
  Widget build(BuildContext context) {
    final hub = _hubs.firstWhere((h) => h.$1 == selected,
        orElse: () => _hubs.first);
    return PopupMenuButton<String>(
      initialValue: selected,
      onSelected: onChanged,
      color: AppColors.darkSurface,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(hub.$3, size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              hub.$2,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.primary),
            ),
            const Icon(Icons.arrow_drop_down,
                size: 16, color: AppColors.primary),
          ],
        ),
      ),
      itemBuilder: (_) => _hubs
          .map(
            (h) => PopupMenuItem<String>(
              value: h.$1,
              child: Row(
                children: [
                  Icon(h.$3, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(h.$2,
                      style: AppTextStyles.bodyMedium
                          .copyWith(color: Colors.white)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _MediaPreviewGrid extends StatelessWidget {
  const _MediaPreviewGrid(
      {required this.files, required this.onRemove});
  final List<File> files;
  final void Function(int) onRemove;

  @override
  Widget build(BuildContext context) {
    if (files.length == 1) {
      return _MediaTile(file: files[0], onRemove: () => onRemove(0));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
      ),
      itemCount: files.length,
      itemBuilder: (_, i) =>
          _MediaTile(file: files[i], onRemove: () => onRemove(i)),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.file, required this.onRemove});
  final File file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(file, fit: BoxFit.cover),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

class _TagInput extends StatelessWidget {
  const _TagInput({required this.controller, required this.onAdd});
  final TextEditingController controller;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Add a tag (e.g. faith, flutter)…',
        hintStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon:
            const Icon(Icons.tag, color: AppColors.textMuted, size: 18),
        suffixIcon: IconButton(
          icon: const Icon(Icons.add_circle_outline,
              color: AppColors.primary),
          onPressed: () {
            final tag = controller.text.trim().replaceAll('#', '');
            if (tag.isNotEmpty) {
              onAdd(tag);
              controller.clear();
            }
          },
        ),
        filled: true,
        fillColor: AppColors.darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      onSubmitted: (v) {
        final tag = v.trim().replaceAll('#', '');
        if (tag.isNotEmpty) {
          onAdd(tag);
          controller.clear();
        }
      },
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.primary, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.labelSmall
                  .copyWith(color: AppColors.textMuted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

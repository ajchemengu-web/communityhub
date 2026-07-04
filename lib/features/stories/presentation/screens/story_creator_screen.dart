import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class StoryCreatorScreen extends ConsumerStatefulWidget {
  const StoryCreatorScreen({super.key});

  @override
  ConsumerState<StoryCreatorScreen> createState() =>
      _StoryCreatorScreenState();
}

class _StoryCreatorScreenState extends ConsumerState<StoryCreatorScreen> {
  File? _mediaFile;
  bool _isVideo = false;
  bool _isUploading = false;
  final _captionCtrl = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1080,
    );
    if (file != null) {
      setState(() {
        _mediaFile = File(file.path);
        _isVideo = false;
      });
    }
  }

  Future<void> _pickVideo() async {
    final file = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(seconds: 30),
    );
    if (file != null) {
      setState(() {
        _mediaFile = File(file.path);
        _isVideo = true;
      });
    }
  }

  Future<void> _post() async {
    if (_mediaFile == null) return;
    setState(() => _isUploading = true);

    try {
      final uid = SupabaseService.currentUserId;
      if (uid == null) throw Exception('Not logged in');

      // Upload to Supabase Storage
      final ext = _isVideo ? 'mp4' : 'jpg';
      final path = 'stories/$uid/${const Uuid().v4()}.$ext';
      await SupabaseService.client.storage
          .from('media')
          .upload(path, _mediaFile!,
              fileOptions: FileOptions(
                  contentType: _isVideo ? 'video/mp4' : 'image/jpeg'));

      final mediaUrl = SupabaseService.client.storage
          .from('media')
          .getPublicUrl(path);

      // Insert into stories table
      await SupabaseService.client.from('stories').insert({
        'user_id': uid,
        'media_url': mediaUrl,
        'media_type': _isVideo ? 'video' : 'image',
        'caption': _captionCtrl.text.trim().isEmpty
            ? null
            : _captionCtrl.text.trim(),
        'expires_at': DateTime.now()
            .add(const Duration(hours: 24))
            .toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Story posted!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to post story: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _mediaFile == null
          ? _PickerView(onPickImage: _pickImage, onPickVideo: _pickVideo)
          : _PreviewView(
              file: _mediaFile!,
              isVideo: _isVideo,
              captionCtrl: _captionCtrl,
              isUploading: _isUploading,
              onRetake: () => setState(() => _mediaFile = null),
              onPost: _post,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Picker View
// ─────────────────────────────────────────────────────────────────

class _PickerView extends StatelessWidget {
  const _PickerView({
    required this.onPickImage,
    required this.onPickVideo,
  });
  final VoidCallback onPickImage;
  final VoidCallback onPickVideo;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                Text('New Story',
                    style: AppTextStyles.titleSmall
                        .copyWith(color: Colors.white)),
                const Spacer(),
                const SizedBox(width: 40),
              ],
            ),
          ),

          const Spacer(),

          // Camera icon
          const Icon(Icons.camera_alt_outlined,
              color: Colors.white30, size: 80),
          const SizedBox(height: 24),
          Text('Choose what to share',
              style: AppTextStyles.bodyLarge
                  .copyWith(color: Colors.white54)),

          const SizedBox(height: 48),

          // Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                _PickButton(
                  icon: Icons.image_outlined,
                  label: 'Choose Photo',
                  color: AppColors.primary,
                  onTap: onPickImage,
                ),
                const SizedBox(height: 16),
                _PickButton(
                  icon: Icons.videocam_outlined,
                  label: 'Choose Video',
                  color: AppColors.secondary,
                  onTap: onPickVideo,
                ),
              ],
            ),
          ),

          const Spacer(),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
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
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 22),
        label: Text(label, style: AppTextStyles.buttonText),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Preview View
// ─────────────────────────────────────────────────────────────────

class _PreviewView extends StatelessWidget {
  const _PreviewView({
    required this.file,
    required this.isVideo,
    required this.captionCtrl,
    required this.isUploading,
    required this.onRetake,
    required this.onPost,
  });
  final File file;
  final bool isVideo;
  final TextEditingController captionCtrl;
  final bool isUploading;
  final VoidCallback onRetake;
  final VoidCallback onPost;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview image
        Image.file(file, fit: BoxFit.cover),

        // Top gradient
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

        // Bottom gradient
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
              ),
            ),
          ),
        ),

        // Top bar
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white),
                  onPressed: onRetake,
                ),
                const Spacer(),
                if (isVideo)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.videocam, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('Video',
                            style: TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        // Bottom: caption + post button
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Caption field
                  TextField(
                    controller: captionCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    minLines: 1,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Add a caption…',
                      hintStyle:
                          const TextStyle(color: Colors.white60),
                      counterStyle:
                          const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black38,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                            color: Colors.white70),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Post button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: isUploading ? null : onPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: isUploading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white),
                            )
                          : const Text('Share Story',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

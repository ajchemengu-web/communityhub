import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:v_video_compressor/v_video_compressor.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/data/profile_detail_repository.dart';

class StoryCreatorScreen extends ConsumerStatefulWidget {
  const StoryCreatorScreen({super.key});

  @override
  ConsumerState<StoryCreatorScreen> createState() =>
      _StoryCreatorScreenState();
}

class _StoryCreatorScreenState extends ConsumerState<StoryCreatorScreen> {
  File? _mediaFile;
  bool _isVideo = false;
  bool _isBoomerang = false;
  bool _isUploading = false;
  final _captionCtrl = TextEditingController();

  // Audience — WhatsApp-style: all followers by default, narrowable to
  // "all except" or "only these" for this one status update.
  String _audienceMode = 'all_followers';
  List<Map<String, dynamic>> _audienceUsers = [];

  @override
  void dispose() {
    _captionCtrl.dispose();
    super.dispose();
  }

  String get _audienceLabel {
    switch (_audienceMode) {
      case 'all_except':
        return 'All Followers Except ${_audienceUsers.length}';
      case 'only_these':
        return 'Only ${_audienceUsers.length} Followers';
      default:
        return 'All Followers';
    }
  }

  Future<void> _pickAudience() async {
    final result = await showModalBottomSheet<(String, List<Map<String, dynamic>>)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      builder: (_) => _AudiencePickerSheet(
        initialMode: _audienceMode,
        initialUsers: _audienceUsers,
      ),
    );
    if (result != null) {
      setState(() {
        _audienceMode = result.$1;
        _audienceUsers = result.$2;
      });
    }
  }

  /// Compresses an image before upload — mirrors post_repository.dart's
  /// approach. Falls back to the original file on any failure.
  Future<File> _compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/story_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 82,
        minWidth: 1440,
        minHeight: 1440,
      );
      return result != null ? File(result.path) : file;
    } catch (_) {
      return file;
    }
  }

  Future<File> _compressVideo(File file) async {
    try {
      final result = await VVideoCompressor().compressVideo(
        file.path,
        const VVideoCompressionConfig.medium(),
      );
      return result != null ? File(result.compressedFilePath) : file;
    } catch (_) {
      return file;
    }
  }

  Future<void> _post() async {
    if (_mediaFile == null) return;
    setState(() => _isUploading = true);

    try {
      final uid = SupabaseService.currentUserId;
      if (uid == null) throw Exception('Not logged in');

      final uploadFile = _isVideo
          ? await _compressVideo(_mediaFile!)
          : await _compressImage(_mediaFile!);

      final ext = _isVideo ? 'mp4' : 'jpg';
      final path = 'stories/$uid/${const Uuid().v4()}.$ext';
      await SupabaseService.client.storage.from('media').upload(
            path,
            uploadFile,
            fileOptions: FileOptions(
                contentType: _isVideo ? 'video/mp4' : 'image/jpeg'),
          );

      final mediaUrl =
          SupabaseService.client.storage.from('media').getPublicUrl(path);

      final story = await SupabaseService.client.from('stories').insert({
        'user_id': uid,
        'media_url': mediaUrl,
        'media_type': _isVideo ? 'video' : 'image',
        'caption': _captionCtrl.text.trim().isEmpty
            ? null
            : _captionCtrl.text.trim(),
        'expires_at':
            DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
        'audience_mode': _audienceMode,
        'is_boomerang': _isBoomerang,
      }).select('id').single();

      if (_audienceMode != 'all_followers' && _audienceUsers.isNotEmpty) {
        final storyId = story['id'] as String;
        await SupabaseService.client.from('story_audience_exceptions').insert([
          for (final u in _audienceUsers)
            {'story_id': storyId, 'user_id': u['id']},
        ]);
      }

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
          ? _StoryCameraView(
              onCaptured: (file, isVideo, isBoomerang) => setState(() {
                _mediaFile = file;
                _isVideo = isVideo;
                _isBoomerang = isBoomerang;
              }),
              onClose: () => Navigator.of(context).pop(),
            )
          : _PreviewView(
              file: _mediaFile!,
              isVideo: _isVideo,
              isBoomerang: _isBoomerang,
              captionCtrl: _captionCtrl,
              isUploading: _isUploading,
              audienceLabel: _audienceLabel,
              onPickAudience: _pickAudience,
              onRetake: () => setState(() => _mediaFile = null),
              onPost: _post,
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Audience Picker Sheet — WhatsApp-style per-update visibility:
// All Followers (default) / All Followers Except… / Only Share With…
// ─────────────────────────────────────────────────────────────────

class _AudiencePickerSheet extends StatefulWidget {
  const _AudiencePickerSheet({
    required this.initialMode,
    required this.initialUsers,
  });
  final String initialMode;
  final List<Map<String, dynamic>> initialUsers;

  @override
  State<_AudiencePickerSheet> createState() => _AudiencePickerSheetState();
}

class _AudiencePickerSheetState extends State<_AudiencePickerSheet> {
  late String _mode = widget.initialMode;
  final List<Map<String, dynamic>> _selected = [];
  List<Map<String, dynamic>>? _followers;
  bool _loadingFollowers = false;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialUsers);
  }

  Future<void> _loadFollowersIfNeeded() async {
    if (_followers != null || _loadingFollowers) return;
    setState(() => _loadingFollowers = true);
    try {
      final rows = await ProfileDetailRepository.instance.fetchMyFollowers();
      if (mounted) {
        setState(() {
          _followers = rows
              .map((r) => Map<String, dynamic>.from(
                  r['follower'] as Map? ?? {}))
              .where((u) => u['id'] != null)
              .toList();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _followers = []);
    } finally {
      if (mounted) setState(() => _loadingFollowers = false);
    }
  }

  void _selectMode(String mode) {
    setState(() => _mode = mode);
    if (mode != 'all_followers') _loadFollowersIfNeeded();
  }

  void _toggleUser(Map<String, dynamic> user) {
    setState(() {
      final exists = _selected.any((u) => u['id'] == user['id']);
      if (exists) {
        _selected.removeWhere((u) => u['id'] == user['id']);
      } else {
        _selected.add(user);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
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
          const Text('Who can see this update?',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                _AudienceOption(
                  icon: Icons.groups_rounded,
                  title: 'All Followers',
                  subtitle: 'Your default audience',
                  selected: _mode == 'all_followers',
                  onTap: () => _selectMode('all_followers'),
                ),
                _AudienceOption(
                  icon: Icons.remove_circle_outline_rounded,
                  title: 'All Followers Except…',
                  subtitle: 'Hide from specific followers',
                  selected: _mode == 'all_except',
                  onTap: () => _selectMode('all_except'),
                ),
                _AudienceOption(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Only Share With…',
                  subtitle: 'Only selected followers can see it',
                  selected: _mode == 'only_these',
                  onTap: () => _selectMode('only_these'),
                ),
                if (_mode != 'all_followers') ...[
                  const Divider(color: Colors.white12, height: 24),
                  if (_loadingFollowers)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if ((_followers ?? []).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(
                        child: Text("You don't have any followers yet",
                            style: TextStyle(color: Colors.white38)),
                      ),
                    )
                  else
                    for (final u in _followers!)
                      CheckboxListTile(
                        value: _selected.any((s) => s['id'] == u['id']),
                        onChanged: (_) => _toggleUser(u),
                        activeColor: AppColors.primary,
                        title: Text(u['username'] as String? ?? '',
                            style: const TextStyle(color: Colors.white)),
                        secondary: CircleAvatar(
                          backgroundColor: const Color(0xFF2A2A2A),
                          backgroundImage:
                              ((u['avatar_url'] as String?)?.isNotEmpty ??
                                      false)
                                  ? NetworkImage(u['avatar_url'] as String)
                                  : null,
                          child: ((u['avatar_url'] as String?)?.isEmpty ??
                                  true)
                              ? const Icon(Icons.person,
                                  color: Colors.white38)
                              : null,
                        ),
                      ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop((_mode, _selected)),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text('Done'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AudienceOption extends StatelessWidget {
  const _AudienceOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon,
          color: selected ? AppColors.primary : Colors.white70),
      title: Text(title,
          style: TextStyle(
              color: selected ? AppColors.primary : Colors.white,
              fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.primary)
          : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Camera-first capture view — live viewfinder with left-side tools
// (text, boomerang, layout), matching Instagram's Story camera.
// Tap the shutter for a photo, hold it to record a short video.
// ─────────────────────────────────────────────────────────────────

class _StoryCameraView extends StatefulWidget {
  const _StoryCameraView({required this.onCaptured, required this.onClose});
  final void Function(File file, bool isVideo, bool isBoomerang) onCaptured;
  final VoidCallback onClose;

  @override
  State<_StoryCameraView> createState() => _StoryCameraViewState();
}

class _StoryCameraViewState extends State<_StoryCameraView>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _flashOn = false;
  bool _recording = false;
  bool _permDenied = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      ctrl.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera(index: _cameraIndex);
    }
  }

  Future<void> _initCamera({int index = 0}) async {
    final camPerm = await Permission.camera.request();
    final micPerm = await Permission.microphone.request();
    if (!camPerm.isGranted || !micPerm.isGranted) {
      if (mounted) setState(() => _permDenied = true);
      return;
    }
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;
    _cameraIndex = index.clamp(0, _cameras.length - 1);
    final ctrl = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    await ctrl.initialize();
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    setState(() => _controller = ctrl);
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    setState(() => _controller = null);
    await _initCamera(index: next);
  }

  Future<void> _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null) return;
    final next = !_flashOn;
    try {
      await ctrl.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      setState(() => _flashOn = next);
    } catch (_) {}
  }

  Future<void> _takePhoto() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || ctrl.value.isTakingPicture) {
      return;
    }
    try {
      final file = await ctrl.takePicture();
      widget.onCaptured(File(file.path), false, false);
    } catch (_) {}
  }

  Future<void> _startVideo() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _recording) return;
    try {
      await ctrl.prepareForVideoRecording();
      await ctrl.startVideoRecording();
      setState(() => _recording = true);
    } catch (_) {}
  }

  Future<void> _stopVideo() async {
    final ctrl = _controller;
    if (ctrl == null || !_recording) return;
    try {
      final file = await ctrl.stopVideoRecording();
      setState(() => _recording = false);
      widget.onCaptured(File(file.path), true, false);
    } catch (_) {
      setState(() => _recording = false);
    }
  }

  void _openTextStory() async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const _TextStoryComposer()),
    );
    if (file != null) widget.onCaptured(file, false, false);
  }

  void _openBoomerang() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        builder: (_) => _BoomerangCaptureScreen(controller: ctrl),
      ),
    );
    if (file != null) widget.onCaptured(file, true, true);
  }

  void _openLayout() async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const _LayoutComposer()),
    );
    if (file != null) widget.onCaptured(file, false, false);
  }

  @override
  Widget build(BuildContext context) {
    if (_permDenied) {
      return SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white38, size: 56),
            const SizedBox(height: 16),
            Text('Camera & microphone access needed',
                style: AppTextStyles.bodyMedium
                    .copyWith(color: Colors.white70)),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => openAppSettings(),
              child: const Text('Open Settings',
                  style: TextStyle(color: AppColors.primary)),
            ),
            TextButton(
              onPressed: widget.onClose,
              child:
                  const Text('Close', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      );
    }

    final ctrl = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Live viewfinder
        if (ctrl != null && ctrl.value.isInitialized)
          Center(child: CameraPreview(ctrl))
        else
          const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),

        // Top bar
        // Wrapped in Positioned: this Stack uses fit: StackFit.expand,
        // which forces non-positioned children to fill the whole Stack.
        // Without Positioned here, this SafeArea/Row gets stretched to
        // the full screen height and Row's default
        // crossAxisAlignment.center renders the close/flash/settings
        // icons vertically centered in the middle of the screen instead
        // of pinned to the top.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: widget.onClose,
                ),
                IconButton(
                  icon: Icon(
                    _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFlash,
                ),
                const Icon(Icons.settings_outlined,
                    color: Colors.white, size: 22),
              ],
            ),
          ),
          ),
        ),

        // Left-side tool column
        Positioned(
          left: 16,
          top: MediaQuery.of(context).size.height * 0.28,
          child: Column(
            children: [
              _StoryToolBtn(label: 'Aa', onTap: _openTextStory),
              const SizedBox(height: 20),
              _StoryToolIcon(icon: Icons.all_inclusive_rounded, onTap: _openBoomerang),
              const SizedBox(height: 20),
              _StoryToolIcon(icon: Icons.grid_view_rounded, onTap: _openLayout),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('More effects coming soon'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: Colors.white, size: 26),
              ),
            ],
          ),
        ),

        // Bottom capture bar
        Positioned(
          bottom: 24,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(width: 40),
              GestureDetector(
                onTap: _takePhoto,
                onLongPressStart: (_) => _startVideo(),
                onLongPressEnd: (_) => _stopVideo(),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _recording ? Colors.red : Colors.white,
                        width: 4),
                  ),
                  child: Center(
                    child: Container(
                      width: _recording ? 30 : 60,
                      height: _recording ? 30 : 60,
                      decoration: BoxDecoration(
                        color: _recording ? Colors.red : Colors.white,
                        borderRadius:
                            BorderRadius.circular(_recording ? 6 : 30),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 24),
              IconButton(
                icon: const Icon(Icons.flip_camera_ios_outlined,
                    color: Colors.white, size: 28),
                onPressed: _flipCamera,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StoryToolBtn extends StatelessWidget {
  const _StoryToolBtn({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700)),
    );
  }
}

class _StoryToolIcon extends StatelessWidget {
  const _StoryToolIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(icon, color: Colors.white, size: 26),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Text-only story — colored background + styled text, matching the
// "Aa" tool. Captured via RepaintBoundary, same technique as the post
// editor's filter/overlay export.
// ─────────────────────────────────────────────────────────────────

const List<Color> _kStoryBgColors = [
  Color(0xFF1A237E),
  Color(0xFF6A1B9A),
  Color(0xFFB71C1C),
  Color(0xFF1B5E20),
  Color(0xFFE65100),
  Color(0xFF000000),
];

class _TextStoryComposer extends StatefulWidget {
  const _TextStoryComposer();

  @override
  State<_TextStoryComposer> createState() => _TextStoryComposerState();
}

class _TextStoryComposerState extends State<_TextStoryComposer> {
  final _ctrl = TextEditingController();
  final _boundaryKey = GlobalKey();
  int _bgIndex = 0;
  bool _exporting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    if (_ctrl.text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _exporting = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/text_story_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (mounted) Navigator.of(context).pop(file);
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kStoryBgColors[_bgIndex],
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    onPressed: _exporting ? null : _done,
                    child: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Done',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Container(
                  width: double.infinity,
                  color: _kStoryBgColors[_bgIndex],
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    maxLines: null,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w700),
                    decoration: const InputDecoration(
                      hintText: 'Start typing',
                      hintStyle: TextStyle(color: Colors.white54),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _kStoryBgColors.length; i++)
                    GestureDetector(
                      onTap: () => setState(() => _bgIndex = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: _kStoryBgColors[i],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _bgIndex == i
                                ? Colors.white
                                : Colors.white24,
                            width: _bgIndex == i ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Boomerang — records a short clip, then plays it forward → reverse →
// forward on loop by manually scrubbing playback position (video_player
// has no native reverse-decode, so this drives it via repeated seekTo
// calls) and exports that looped sequence as a real video file... in
// practice, re-encoding a scrubbed sequence needs a video encoder we
// don't have, so instead this exports the original short forward clip
// and the PLAYER (story viewer) is responsible for the forward-reverse
// loop presentation. The capture screen just trims to a tight clip.
// ─────────────────────────────────────────────────────────────────

class _BoomerangCaptureScreen extends StatefulWidget {
  const _BoomerangCaptureScreen({required this.controller});
  final CameraController controller;

  @override
  State<_BoomerangCaptureScreen> createState() =>
      _BoomerangCaptureScreenState();
}

class _BoomerangCaptureScreenState extends State<_BoomerangCaptureScreen> {
  bool _recording = false;
  bool _processing = false;
  static const _clipDuration = Duration(seconds: 2);

  Future<void> _record() async {
    if (_recording) return;
    setState(() => _recording = true);
    try {
      await widget.controller.prepareForVideoRecording();
      await widget.controller.startVideoRecording();
      await Future.delayed(_clipDuration);
      final file = await widget.controller.stopVideoRecording();
      if (mounted) {
        setState(() => _processing = true);
        Navigator.of(context).pop(File(file.path));
      }
    } catch (_) {
      if (mounted) setState(() => _recording = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(widget.controller),
          // Wrapped in Positioned: this Stack uses fit: StackFit.expand,
          // which forces non-positioned children to fill the whole
          // Stack — without it, this SafeArea/Row gets stretched to the
          // full screen height and Row's default
          // crossAxisAlignment.center renders "Boomerang" and the close
          // button vertically centered on screen instead of at the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  const Text('Boomerang',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: (_recording || _processing) ? null : _record,
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _recording ? Colors.orange : Colors.white,
                        width: 4),
                  ),
                  child: Center(
                    child: (_recording || _processing)
                        ? const SizedBox(
                            width: 26,
                            height: 26,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5, color: Colors.orange),
                          )
                        : const Icon(Icons.all_inclusive_rounded,
                            color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Layout / split-screen — picks two photos from the gallery and
// composites them into a 2-cell grid, rather than true simultaneous
// dual-camera capture (which would need much more time to build).
// ─────────────────────────────────────────────────────────────────

class _LayoutComposer extends StatefulWidget {
  const _LayoutComposer();

  @override
  State<_LayoutComposer> createState() => _LayoutComposerState();
}

class _LayoutComposerState extends State<_LayoutComposer> {
  File? _top;
  File? _bottom;
  final _picker = ImagePicker();
  final _boundaryKey = GlobalKey();
  bool _exporting = false;

  Future<void> _pick(bool isTop) async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90, maxWidth: 1080);
    if (file == null) return;
    setState(() {
      if (isTop) {
        _top = File(file.path);
      } else {
        _bottom = File(file.path);
      }
    });
  }

  Future<void> _done() async {
    if (_top == null || _bottom == null) return;
    setState(() => _exporting = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) setState(() => _exporting = false);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        if (mounted) setState(() => _exporting = false);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/layout_story_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      if (mounted) Navigator.of(context).pop(file);
    } catch (_) {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Widget _cell(File? file, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          color: const Color(0xFF1A1A1A),
          width: double.infinity,
          child: file != null
              ? Image.file(file, fit: BoxFit.cover)
              : const Center(
                  child: Icon(Icons.add_photo_alternate_outlined,
                      color: Colors.white38, size: 36),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  TextButton(
                    onPressed:
                        (_top != null && _bottom != null && !_exporting)
                            ? _done
                            : null,
                    child: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('Done',
                            style: TextStyle(
                                color: (_top != null && _bottom != null)
                                    ? Colors.white
                                    : Colors.white24,
                                fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RepaintBoundary(
                key: _boundaryKey,
                child: Column(
                  children: [
                    _cell(_top, () => _pick(true)),
                    const SizedBox(height: 2),
                    _cell(_bottom, () => _pick(false)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Preview View
// ─────────────────────────────────────────────────────────────────

class _PreviewView extends StatefulWidget {
  const _PreviewView({
    required this.file,
    required this.isVideo,
    this.isBoomerang = false,
    required this.captionCtrl,
    required this.isUploading,
    required this.audienceLabel,
    required this.onPickAudience,
    required this.onRetake,
    required this.onPost,
  });
  final File file;
  final bool isVideo;
  final bool isBoomerang;
  final TextEditingController captionCtrl;
  final bool isUploading;
  final String audienceLabel;
  final VoidCallback onPickAudience;
  final VoidCallback onRetake;
  final VoidCallback onPost;

  @override
  State<_PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<_PreviewView> {
  VideoPlayerController? _videoCtrl;
  Timer? _boomerangTimer;
  bool _reversing = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _videoCtrl = VideoPlayerController.file(widget.file)
        ..initialize().then((_) {
          if (!mounted) return;
          setState(() {});
          if (widget.isBoomerang) {
            // video_player has no native reverse-decode, so the
            // forward→reverse→forward loop is driven manually by
            // scrubbing playback position backward via repeated
            // seekTo calls once forward playback hits the end.
            _videoCtrl!.play();
            _videoCtrl!.addListener(_onBoomerangTick);
          } else {
            _videoCtrl!.setLooping(true);
            _videoCtrl!.play();
          }
        });
    }
  }

  void _onBoomerangTick() {
    final ctrl = _videoCtrl;
    if (ctrl == null || !ctrl.value.isInitialized || _reversing) return;
    final pos = ctrl.value.position;
    final dur = ctrl.value.duration;
    if (pos >= dur - const Duration(milliseconds: 80)) {
      _reversing = true;
      ctrl.pause();
      _startReverseScrub();
    }
  }

  void _startReverseScrub() {
    const step = Duration(milliseconds: 33);
    _boomerangTimer?.cancel();
    _boomerangTimer = Timer.periodic(step, (timer) async {
      final ctrl = _videoCtrl;
      if (ctrl == null) {
        timer.cancel();
        return;
      }
      final pos = ctrl.value.position;
      if (pos <= step) {
        timer.cancel();
        await ctrl.seekTo(Duration.zero);
        await ctrl.play();
        _reversing = false;
        return;
      }
      await ctrl.seekTo(pos - step);
    });
  }

  @override
  void dispose() {
    _boomerangTimer?.cancel();
    _videoCtrl?.removeListener(_onBoomerangTick);
    _videoCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Preview
        if (widget.isVideo)
          (_videoCtrl?.value.isInitialized ?? false)
              ? FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoCtrl!.value.size.width,
                    height: _videoCtrl!.value.size.height,
                    child: VideoPlayer(_videoCtrl!),
                  ),
                )
              : const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
        else
          Image.file(widget.file, fit: BoxFit.cover),

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
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent
                ],
              ),
            ),
          ),
        ),

        // Top bar
        // Wrapped in Positioned: this Stack uses fit: StackFit.expand,
        // which forces non-positioned children to fill the whole
        // Stack — without it, this SafeArea/Row gets stretched to the
        // full screen height and Row's default
        // crossAxisAlignment.center renders the back button and
        // "Video" badge vertically centered on screen instead of at
        // the top.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon:
                      const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                  onPressed: widget.onRetake,
                ),
                const Spacer(),
                if (widget.isVideo)
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
                            style:
                                TextStyle(color: Colors.white, fontSize: 12)),
                      ],
                    ),
                  ),
              ],
            ),
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
                  // Audience selector — WhatsApp-style: who sees this
                  // particular update.
                  GestureDetector(
                    onTap: widget.onPickAudience,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.people_outline_rounded,
                              color: Colors.white70, size: 16),
                          const SizedBox(width: 6),
                          Text(widget.audienceLabel,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          const SizedBox(width: 4),
                          const Icon(Icons.keyboard_arrow_down_rounded,
                              color: Colors.white54, size: 18),
                        ],
                      ),
                    ),
                  ),
                  TextField(
                    controller: widget.captionCtrl,
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    minLines: 1,
                    maxLength: 200,
                    decoration: InputDecoration(
                      hintText: 'Add a caption…',
                      hintStyle: const TextStyle(color: Colors.white60),
                      counterStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: Colors.black38,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white70),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: widget.isUploading ? null : widget.onPost,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      child: widget.isUploading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5, color: Colors.white),
                            )
                          : const Text('Share Story',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
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

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

enum _CameraMode { video, short, live, post }

class CameraRecorderScreen extends StatefulWidget {
  const CameraRecorderScreen({
    super.key,
    this.onVideoSaved,
    this.maxDuration = const Duration(minutes: 3),
  });

  final void Function(String path)? onVideoSaved;
  final Duration maxDuration;

  @override
  State<CameraRecorderScreen> createState() => _CameraRecorderScreenState();
}

class _CameraRecorderScreenState extends State<CameraRecorderScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  bool _isRecording = false;
  bool _flashOn = false;
  Duration _elapsed = Duration.zero;
  Timer? _timer;
  _CameraMode _mode = _CameraMode.short;
  double _zoomLevel = 1.0;

  // Gallery thumbnail
  Uint8List? _lastThumb;

  // Preview after recording
  String? _recordedPath;
  VideoPlayerController? _previewCtrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _initCamera();
    _loadLastGalleryThumb();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _timer?.cancel();
    _controller?.dispose();
    _previewCtrl?.dispose();
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
      if (mounted) Navigator.pop(context);
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
    if (!mounted) { ctrl.dispose(); return; }
    setState(() { _controller = ctrl; _zoomLevel = 1.0; });
  }

  Future<void> _loadLastGalleryThumb() async {
    final result = await PhotoManager.requestPermissionExtend();
    if (!result.isAuth) return;
    final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common, onlyAll: true);
    if (albums.isEmpty) return;
    final assets = await albums.first.getAssetListPaged(page: 0, size: 1);
    if (assets.isEmpty) return;
    final thumb = await assets.first
        .thumbnailDataWithSize(const ThumbnailSize(120, 120));
    if (mounted) setState(() => _lastThumb = thumb);
  }

  Future<void> _toggleRecording() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    await _controller!.prepareForVideoRecording();
    await _controller!.startVideoRecording();
    _elapsed = Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
      if (_elapsed >= widget.maxDuration) _stopRecording();
    });
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final file = await _controller!.stopVideoRecording();
    setState(() { _isRecording = false; _recordedPath = file.path; });
    await _initPreview(file.path);
  }

  Future<void> _initPreview(String path) async {
    final ctrl = VideoPlayerController.file(File(path));
    await ctrl.initialize();
    await ctrl.setLooping(true);
    await ctrl.play();
    if (mounted) setState(() => _previewCtrl = ctrl);
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    await _controller?.dispose();
    setState(() => _controller = null);
    await _initCamera(index: next);
  }

  void _discardRecording() {
    _previewCtrl?.dispose();
    setState(() { _recordedPath = null; _previewCtrl = null; });
  }

  void _saveRecording() {
    widget.onVideoSaved?.call(_recordedPath!);
    // Go to the caption/share step with the recorded video
    context.push(AppRoutes.newPost);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Duration get _modeDuration {
    switch (_mode) {
      case _CameraMode.short: return const Duration(seconds: 60);
      case _CameraMode.video: return const Duration(minutes: 10);
      default: return widget.maxDuration;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_recordedPath != null) {
      return _PreviewScreen(
        path: _recordedPath!,
        previewCtrl: _previewCtrl,
        onDiscard: _discardRecording,
        onSave: _saveRecording,
      );
    }

    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ─────────────────────────────────────
          Center(
            child: GestureDetector(
              onScaleUpdate: (details) async {
                final newZoom = (_zoomLevel * details.scale).clamp(1.0, 8.0);
                await ctrl.setZoomLevel(newZoom);
                setState(() => _zoomLevel = newZoom);
              },
              child: CameraPreview(ctrl),
            ),
          ),

          // ── Progress bar ───────────────────────────────────────
          if (_isRecording)
            Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(
                value: _elapsed.inMilliseconds / _modeDuration.inMilliseconds,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                minHeight: 3,
              ),
            ),

          // ── Top bar ────────────────────────────────────────────
          // Must be wrapped in Positioned: this Stack uses
          // fit: StackFit.expand, which forces any *non*-positioned
          // child to fill the entire Stack. Without Positioned here,
          // this SafeArea/Row gets stretched to the full screen height
          // and Row's default crossAxisAlignment.center then renders
          // the close/sound/profile controls vertically centered in
          // the middle of the screen instead of pinned to the top.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  // Close
                  _TopButton(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white, size: 24),
                  ),
                  const Spacer(),

                  // Recording timer OR "Add sound" pill
                  if (_isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.circle, color: Colors.white, size: 8),
                          const SizedBox(width: 6),
                          Text(
                            _formatDuration(_elapsed),
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.music_note_rounded, color: Colors.white, size: 14),
                            SizedBox(width: 6),
                            Text('Add sound',
                                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),

                  const Spacer(),

                  // Profile/effects button
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF9C27B0), Color(0xFF3F51B5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                  ),
                ],
              ),
            ),
            ),
          ),

          // ── Right-side toolbar ─────────────────────────────────
          if (!_isRecording)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SideButton(
                      icon: Icons.flip_camera_ios_rounded,
                      onTap: _switchCamera,
                    ),
                    const SizedBox(height: 20),
                    _SideButton(
                      icon: Icons.timer_outlined,
                      onTap: () {},
                    ),
                    const SizedBox(height: 20),
                    // Duration label
                    GestureDetector(
                      onTap: () {},
                      child: Column(
                        children: [
                          Text(
                            _mode == _CameraMode.short ? '60s' : '10m',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SideButton(
                      icon: Icons.auto_fix_high_rounded,
                      onTap: () {},
                    ),
                    const SizedBox(height: 20),
                    // Zoom level
                    GestureDetector(
                      onTap: () async {
                        final next = _zoomLevel >= 2.0 ? 1.0 : _zoomLevel + 0.5;
                        await ctrl.setZoomLevel(next);
                        setState(() => _zoomLevel = next);
                      },
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30, width: 1),
                        ),
                        child: Center(
                          child: Text(
                            '${_zoomLevel.toStringAsFixed(1)}x',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _SideButton(
                      icon: Icons.face_retouching_natural,
                      onTap: () {},
                    ),
                    const SizedBox(height: 20),
                    _SideButton(
                      icon: Icons.keyboard_arrow_down_rounded,
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),

          // ── Flash button (top-left when recording) ─────────────
          if (_isRecording)
            Positioned(
              top: MediaQuery.of(context).padding.top + 56,
              left: 12,
              child: _SideButton(
                icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                onTap: () async {
                  _flashOn = !_flashOn;
                  await ctrl.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
                  setState(() {});
                },
              ),
            ),

          // ── Bottom controls ────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Controls row: gallery | record | spacer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 8, 28, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Gallery thumbnail
                        GestureDetector(
                          onTap: () => context.push(AppRoutes.newPost),
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: _lastThumb != null
                                    ? Image.memory(_lastThumb!, width: 48, height: 48, fit: BoxFit.cover)
                                    : Container(
                                        width: 48, height: 48,
                                        color: Colors.white12,
                                        child: const Icon(Icons.photo_library_outlined, color: Colors.white70, size: 24),
                                      ),
                              ),
                              const SizedBox(height: 4),
                              const Text('Add', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),

                        // Record button
                        GestureDetector(
                          onTap: _toggleRecording,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            width: _isRecording ? 68 : 76,
                            height: _isRecording ? 68 : 76,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.transparent,
                              border: Border.all(color: Colors.white, width: 3.5),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: _isRecording ? 28 : 58,
                                height: _isRecording ? 28 : 58,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(_isRecording ? 6 : 30),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Spacer (right side — mirror of gallery)
                        const SizedBox(width: 60),
                      ],
                    ),
                  ),

                  // Mode tabs: Video | Short | Live | Post
                  _ModeTabBar(
                    current: _mode,
                    onChanged: (m) => setState(() => _mode = m),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mode tab bar ───────────────────────────────────────────────────

class _ModeTabBar extends StatelessWidget {
  const _ModeTabBar({required this.current, required this.onChanged});
  final _CameraMode current;
  final ValueChanged<_CameraMode> onChanged;

  static const _modes = [
    (_CameraMode.video, 'Video'),
    (_CameraMode.short, 'Short'),
    (_CameraMode.live, 'Live'),
    (_CameraMode.post, 'Post'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: _modes.map((entry) {
          final isSelected = current == entry.$1;
          return GestureDetector(
            onTap: () => onChanged(entry.$1),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                entry.$2,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Small helpers ──────────────────────────────────────────────────

class _TopButton extends StatelessWidget {
  const _TopButton({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

// ── Preview screen ─────────────────────────────────────────────────

class _PreviewScreen extends StatelessWidget {
  const _PreviewScreen({
    required this.path,
    required this.previewCtrl,
    required this.onDiscard,
    required this.onSave,
  });

  final String path;
  final VideoPlayerController? previewCtrl;
  final VoidCallback onDiscard;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (previewCtrl != null && previewCtrl!.value.isInitialized)
            Center(
              child: AspectRatio(
                aspectRatio: previewCtrl!.value.aspectRatio,
                child: VideoPlayer(previewCtrl!),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Wrapped in Positioned for the same reason as the recorder's
          // top bar: fit: StackFit.expand forces non-positioned children
          // to fill the whole Stack, which would otherwise vertically
          // center this row in the middle of the screen instead of
          // pinning it to the top.
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
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: onDiscard,
                  ),
                  const Spacer(),
                  Text('Preview', style: AppTextStyles.titleSmall.copyWith(color: Colors.white)),
                  const Spacer(),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            ),
          ),

          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDiscard,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white60),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: onSave,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Use Video', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/draft_repository.dart';
import '../../data/post_repository.dart';
import '../providers/new_post_provider.dart';

// ── Step enum ─────────────────────────────────────────────────────
enum _Step { picker, edit, share }

// ─────────────────────────────────────────────────────────────────
// Root screen — drives the 3-step flow
// ─────────────────────────────────────────────────────────────────

class NewPostScreen extends ConsumerStatefulWidget {
  const NewPostScreen({super.key, this.isReelMode = false});

  /// Opens straight into Reel mode (Edits/Drafts/Templates pills, no
  /// preview pane, submits with `is_reel: true`) instead of Post mode.
  /// Switchable at runtime via the bottom Post/Reel tabs on the picker.
  final bool isReelMode;

  @override
  ConsumerState<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends ConsumerState<NewPostScreen> {
  _Step _step = _Step.picker;
  late bool _isReelMode = widget.isReelMode;
  AssetEntity? _selectedAsset;
  File? _selectedFile;
  Uint8List? _thumbnailBytes;
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String _audioLabel = 'Original Audio';
  bool _hasDraft = false;

  @override
  void initState() {
    super.initState();
    if (_isReelMode) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => ref.read(newPostProvider.notifier).setReelMode(true),
      );
    }
    DraftRepository.instance.hasDraft().then((v) {
      if (mounted) setState(() => _hasDraft = v);
    });
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    final draft = await DraftRepository.instance.loadDraft();
    if (draft == null || !mounted) return;

    final paths = ((draft['media_file_paths'] as List?) ?? []).cast<String>();
    File? file;
    Uint8List? thumb;
    if (paths.isNotEmpty) {
      file = File(paths.first);
      if (draft['media_type'] != 'video') {
        try {
          thumb = await file.readAsBytes();
        } catch (_) {}
      }
    }
    if (!mounted) return;

    ref.read(newPostProvider.notifier).loadFromDraft(draft);
    _captionCtrl.text = draft['caption'] as String? ?? '';

    setState(() {
      _selectedFile = file;
      _thumbnailBytes = thumb;
      _step = _Step.share;
    });
  }

  Future<void> _saveDraft() async {
    final state = ref.read(newPostProvider);
    await DraftRepository.instance.saveDraft(
      caption: state.caption,
      hubType: state.hubType,
      mediaFilePaths: state.mediaFiles.map((f) => f.path).toList(),
      mediaType: state.mediaType,
      tags: state.tags,
      youtubeUrl: state.youtubeUrl,
    );
  }

  Future<void> _onAssetSelected(AssetEntity asset) async {
    final file = await asset.loadFile();
    final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(400, 400));
    if (file == null) return;
    setState(() {
      _selectedAsset = asset;
      _selectedFile = file;
      _thumbnailBytes = thumb;
      _step = _Step.edit;
    });
    ref.read(newPostProvider.notifier).addMedia(
      [file],
      asset.type == AssetType.video ? 'video' : 'image',
    );
  }

  /// Called when the Edit step finishes. [editedFile] is the real
  /// composited image (filter/brightness/text overlays baked in) when one
  /// was produced, or null when there's nothing to bake in (video, no
  /// edits made, or the capture failed) — in that case the original file
  /// from the picker step is kept as-is.
  Future<void> _onEditNext(File? editedFile) async {
    if (editedFile != null) {
      final bytes = await editedFile.readAsBytes();
      ref.read(newPostProvider.notifier).replaceFirstMedia(editedFile);
      if (!mounted) return;
      setState(() {
        _selectedFile = editedFile;
        _thumbnailBytes = bytes;
      });
    }
    setState(() => _step = _Step.share);
  }

  /// Called when a track is chosen in the Audio tool. Previously this
  /// picker let you preview/play songs but never actually attached one to
  /// the post — selecting "Original Audio" (the sentinel entry with an
  /// empty preview URL) clears any attached track instead.
  void _onAudioSelected(_AudioTrack track) {
    if (track.previewUrl.isEmpty) {
      ref.read(newPostProvider.notifier).clearAudioTrack();
      setState(() => _audioLabel = 'Original Audio');
      return;
    }
    ref.read(newPostProvider.notifier).setAudioTrack(
          title: track.title,
          artist: track.artist,
          previewUrl: track.previewUrl,
        );
    setState(() => _audioLabel = '${track.title} · ${track.artist}');
  }

  Future<void> _submit() async {
    await ref.read(newPostProvider.notifier).submit();
    final state = ref.read(newPostProvider);
    if (!mounted) return;
    if (state.status == NewPostStatus.success) {
      ref.read(newPostProvider.notifier).reset();
      await DraftRepository.instance.clearDraft();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Post shared!'),
          backgroundColor: AppColors.primary,
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
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

    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_step) {
        _Step.picker => _GalleryPickerStep(
            onSelected: _onAssetSelected,
            onClose: () => context.pop(),
            hasDraft: _hasDraft,
            onLoadDraft: _loadDraft,
            isReelMode: _isReelMode,
            onModeChanged: (reel) {
              if (reel == _isReelMode) return;
              ref.read(newPostProvider.notifier).setReelMode(reel);
              setState(() => _isReelMode = reel);
            },
            // Story is a different content type entirely — replace this
            // route rather than pushing on top of it, so the nav stack
            // doesn't grow every time someone taps between tabs.
            onNavigateStory: () => context.pushReplacement('/story/create'),
          ),
        _Step.edit => _EditStep(
            asset: _selectedAsset,
            file: _selectedFile,
            thumbnailBytes: _thumbnailBytes,
            onBack: () {
              ref.read(newPostProvider.notifier).reset();
              setState(() {
                _selectedAsset = null;
                _selectedFile = null;
                _thumbnailBytes = null;
                _step = _Step.picker;
              });
            },
            onNext: _onEditNext,
            onAudioSelected: _onAudioSelected,
          ),
        _Step.share => _ShareStep(
            thumbnailBytes: _thumbnailBytes,
            file: _selectedFile,
            asset: _selectedAsset,
            captionCtrl: _captionCtrl,
            locationCtrl: _locationCtrl,
            audioLabel: _audioLabel,
            onAudioLabelChanged: (v) => setState(() => _audioLabel = v),
            onBack: () => setState(() => _step = _Step.edit),
            onSubmit: _submit,
            onSaveDraft: _saveDraft,
          ),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Step 1 — Gallery Picker (Instagram "New reel" style)
// ─────────────────────────────────────────────────────────────────

class _GalleryPickerStep extends StatefulWidget {
  const _GalleryPickerStep({
    required this.onSelected,
    required this.onClose,
    required this.hasDraft,
    required this.onLoadDraft,
    required this.isReelMode,
    required this.onModeChanged,
    required this.onNavigateStory,
  });
  final Future<void> Function(AssetEntity) onSelected;
  final VoidCallback onClose;
  final bool hasDraft;
  final VoidCallback onLoadDraft;
  final bool isReelMode;
  final ValueChanged<bool> onModeChanged;
  final VoidCallback onNavigateStory;

  @override
  State<_GalleryPickerStep> createState() => _GalleryPickerStepState();
}

class _GalleryPickerStepState extends State<_GalleryPickerStep> {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  AssetEntity? _previewAsset;
  Uint8List? _previewThumb;
  bool _loading = true;
  bool _permDenied = false;
  int _page = 0;
  static const _pageSize = 60;

  @override
  void initState() {
    super.initState();
    _requestAndLoad();
  }

  Future<void> _requestAndLoad() async {
    final result = await PhotoManager.requestPermissionExtend();
    if (!result.isAuth) {
      setState(() { _loading = false; _permDenied = true; });
      return;
    }
    final albums = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: false,
    );
    if (albums.isEmpty) {
      setState(() { _loading = false; });
      return;
    }
    _albums = albums;
    _currentAlbum = albums.first;
    await _loadAssets();
  }

  Future<void> _loadAssets({bool reset = false}) async {
    if (_currentAlbum == null) return;
    if (reset) { _assets = []; _page = 0; }
    final list = await _currentAlbum!.getAssetListPaged(
      page: _page,
      size: _pageSize,
    );
    final previewAsset = _assets.isEmpty && list.isNotEmpty ? list.first : _previewAsset;
    Uint8List? thumb = _previewThumb;
    if (previewAsset != null && _previewThumb == null) {
      thumb = await previewAsset.thumbnailDataWithSize(
          const ThumbnailSize(600, 600));
    }
    if (mounted) {
      setState(() {
        _assets.addAll(list);
        _previewAsset = previewAsset;
        _previewThumb = thumb;
        _loading = false;
      });
    }
  }

  Future<void> _selectPreview(AssetEntity asset) async {
    final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(600, 600));
    setState(() {
      _previewAsset = asset;
      _previewThumb = thumb;
    });
  }

  void _showAlbumPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ListView.builder(
        shrinkWrap: true,
        itemCount: _albums.length,
        itemBuilder: (_, i) {
          final album = _albums[i];
          return ListTile(
            onTap: () async {
              Navigator.pop(context);
              setState(() {
                _currentAlbum = album;
                _previewThumb = null;
                _loading = true;
              });
              await _loadAssets(reset: true);
            },
            title: Text(album.name,
                style: const TextStyle(color: Colors.white)),
            trailing: _currentAlbum?.id == album.id
                ? const Icon(Icons.check, color: AppColors.primary)
                : null,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isReel = widget.isReelMode;
    return Column(
      children: [
        // ── AppBar ─────────────────────────────────────────────
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 12, 0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: widget.onClose,
                    ),
                    Expanded(
                      child: Text(isReel ? 'New reel' : 'New post',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                    ),
                    // Reel mode keeps a settings icon; Post mode shows a
                    // real "Next" button, enabled once a preview is picked.
                    if (isReel)
                      const Icon(Icons.settings_outlined,
                          color: Colors.white, size: 22)
                    else
                      TextButton(
                        onPressed: _previewAsset != null
                            ? () => widget.onSelected(_previewAsset!)
                            : null,
                        child: Text('Next',
                            style: TextStyle(
                              color: _previewAsset != null
                                  ? const Color(0xFF0095F6)
                                  : Colors.white24,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                  ],
                ),
              ),
              // Edits / Drafts / Templates chips — reel mode only.
              if (isReel)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                  child: Row(
                    children: [
                      const _Chip(
                          label: 'Edits', icon: Icons.auto_fix_high_rounded),
                      const SizedBox(width: 10),
                      _Chip(
                        label: widget.hasDraft ? 'Drafts · 1' : 'Drafts · 0',
                        icon: Icons.layers_outlined,
                        onTap: widget.hasDraft ? widget.onLoadDraft : null,
                      ),
                      const SizedBox(width: 10),
                      const _Chip(
                          label: 'Templates',
                          icon: Icons.auto_awesome_mosaic_outlined),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // ── Preview pane ─────────────────────────────────────
        // Post mode only — reel mode skips straight to the grid, matching
        // Instagram's reel picker (a single tap on a thumbnail there
        // moves straight to editing rather than staging a preview first).
        if (!isReel)
          AspectRatio(
            aspectRatio: 1,
            child: _permDenied
                ? _PermDeniedBanner()
                : _previewThumb != null
                    ? Image.memory(_previewThumb!, fit: BoxFit.cover)
                    : const Center(
                        child: Icon(Icons.photo_library_outlined,
                            color: Colors.white24, size: 48)),
          ),

        // ── Recents / Select bar ───────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: Row(
            children: [
              GestureDetector(
                onTap: _showAlbumPicker,
                child: Row(
                  children: [
                    Text(
                      _currentAlbum?.name ?? 'Recents',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down,
                        color: Colors.white, size: 20),
                  ],
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.layers_outlined,
                    size: 14, color: Colors.white),
                label: const Text('Select',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white38),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),

        // ── Grid ──────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _assets.isEmpty
                  ? const Center(
                      child: Text('No media found',
                          style: TextStyle(color: Colors.white38)))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 1.5,
                        mainAxisSpacing: 1.5,
                      ),
                      itemCount: _assets.length,
                      itemBuilder: (_, i) {
                        final asset = _assets[i];
                        return _GridThumbnail(
                          asset: asset,
                          isSelected: _previewAsset?.id == asset.id,
                          // Reel mode: a single tap jumps straight to
                          // editing. Post mode: single tap stages the
                          // preview, "Next" (or double-tap) proceeds.
                          onTap: isReel
                              ? () => widget.onSelected(asset)
                              : () => _selectPreview(asset),
                          onDoubleTap: () => widget.onSelected(asset),
                        );
                      },
                    ),
        ),

        // ── Bottom mode switcher: POST | STORY | REEL | LIVE ──
        SafeArea(
          top: false,
          child: Container(
            color: const Color(0xFF111111),
            height: 48,
            child: Row(
              children: [
                _ModeTab(
                  label: 'POST',
                  selected: !isReel,
                  onTap: () => widget.onModeChanged(false),
                ),
                _ModeTab(
                  label: 'STORY',
                  selected: false,
                  onTap: widget.onNavigateStory,
                ),
                _ModeTab(
                  label: 'REEL',
                  selected: isReel,
                  onTap: () => widget.onModeChanged(true),
                ),
                // LIVE mode tab removed along with the live-streaming
                // feature (see the same note in home_screen.dart).
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white38,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
      ),
    );
  }
}

class _GridThumbnail extends StatefulWidget {
  const _GridThumbnail({
    required this.asset,
    required this.isSelected,
    required this.onTap,
    required this.onDoubleTap,
  });
  final AssetEntity asset;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  State<_GridThumbnail> createState() => _GridThumbnailState();
}

class _GridThumbnailState extends State<_GridThumbnail> {
  Uint8List? _thumb;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final t = await widget.asset
        .thumbnailDataWithSize(const ThumbnailSize(200, 200));
    if (mounted) setState(() => _thumb = t);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onDoubleTap: widget.onDoubleTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _thumb != null
              ? Image.memory(_thumb!, fit: BoxFit.cover)
              : const ColoredBox(color: Color(0xFF1A1A1A)),
          // Video duration badge
          if (widget.asset.type == AssetType.video)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  _formatDuration(
                      Duration(seconds: widget.asset.duration)),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          // Selected highlight
          if (widget.isSelected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2.5),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _PermDeniedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined,
              color: Colors.white24, size: 48),
          const SizedBox(height: 12),
          const Text('Gallery access required',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => PhotoManager.openSetting(),
            child: const Text('Open Settings',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Step 2 — Edit (Instagram-style editor with tool panel)
// ─────────────────────────────────────────────────────────────────

class _EditStep extends StatefulWidget {
  const _EditStep({
    required this.asset,
    required this.file,
    required this.thumbnailBytes,
    required this.onBack,
    required this.onNext,
    required this.onAudioSelected,
  });
  final AssetEntity? asset;
  final File? file;
  final Uint8List? thumbnailBytes;
  final VoidCallback onBack;
  /// Receives the composited (filter/brightness/overlays baked in) file
  /// for image posts, or null when there's nothing to bake in (video, or
  /// export failed) — the caller keeps the original file in that case.
  final ValueChanged<File?> onNext;
  final ValueChanged<_AudioTrack> onAudioSelected;

  @override
  State<_EditStep> createState() => _EditStepState();
}

class _EditStepState extends State<_EditStep> {
  VideoPlayerController? _videoCtrl;
  bool _isVideo = false;
  bool _videoReady = false;
  bool _playing = false;
  bool _exporting = false;

  // Overlays added by tools
  final List<_TextOverlay> _textOverlays = [];
  double _currentFilter = 0; // index into _filterNames / _kFilterMatrices
  double _filterStrength = 1.0; // 0 (no effect) – 1 (full effect)
  BoxFit _fit = BoxFit.cover;
  double _brightness = 0;

  // Freehand drawing (pen tool)
  final List<_DrawStroke> _strokes = [];
  bool _isDrawing = false;
  Color _drawColor = Colors.white;

  // Scopes exactly what gets captured when exporting the edited image.
  final GlobalKey _previewBoundaryKey = GlobalKey();

  static const _filterNames = [
    'Normal', 'Clarendon', 'Gingham', 'Moon', 'Lark',
    'Juno', 'Ludwig', 'Aden', 'Valencia', 'Willow', 'Mayfair',
  ];

  /// Applies the selected filter + brightness to a preview widget. Used
  /// for both the image and video layers so the preview is honest about
  /// what's actually selected (previously only brightness affected the
  /// image layer, and the video layer got no color effects at all).
  Widget _withColorEffects(Widget child) {
    // Blend between identity (no effect) and the selected filter's full
    // matrix by _filterStrength, matching Instagram's filter-intensity
    // slider rather than an all-or-nothing toggle.
    final identity = _kFilterMatrices[0];
    final full = _kFilterMatrices[_currentFilter.toInt()];
    final blended = List.generate(
      20,
      (i) => identity[i] + (full[i] - identity[i]) * _filterStrength,
    );
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_brightnessMatrix(_brightness)),
      child: ColorFiltered(
        colorFilter: ColorFilter.matrix(blended),
        child: child,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _isVideo = widget.asset?.type == AssetType.video;
    if (_isVideo && widget.file != null) {
      _videoCtrl = VideoPlayerController.file(widget.file!)
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _videoReady = true);
            _videoCtrl!.play();
            _videoCtrl!.setLooping(true);
            setState(() => _playing = true);
          }
        });
    }
  }

  @override
  void dispose() {
    _videoCtrl?.dispose();
    super.dispose();
  }

  void _togglePlayPause() {
    if (_videoCtrl == null) return;
    setState(() {
      _playing ? _videoCtrl!.pause() : _videoCtrl!.play();
      _playing = !_playing;
    });
  }

  /// Adds an overlay staggered below whatever's already placed, so new
  /// text/stickers don't all land stacked exactly on top of each other.
  void _addOverlay(_TextOverlay overlay) {
    overlay.position =
        Offset(0.5, (0.2 + _textOverlays.length * 0.1).clamp(0.05, 0.85));
    setState(() => _textOverlays.add(overlay));
  }

  // ── Audio picker ────────────────────────────────────────────────
  void _showAudioTool() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AudioPickerSheet(onSelected: widget.onAudioSelected),
    );
  }

  // ── Overlay / Sticker picker ─────────────────────────────────────
  void _showOverlayTool() {
    const stickers = [
      '😍', '🔥', '❤️', '💫', '✨', '🎉', '👏', '🙌',
      '💯', '🎵', '🌟', '💪', '🤩', '😎', '🌈', '🎶',
      '📍', '💬', '❓', '💡', '🏆', '🙏', '😂', '🤣',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          const Text('Add Overlay',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: stickers.length,
              itemBuilder: (_, i) => GestureDetector(
                onTap: () {
                  _addOverlay(_TextOverlay(text: stickers[i], isSticker: true));
                  Navigator.pop(context);
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(stickers[i],
                        style: const TextStyle(fontSize: 26)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _showTextTool() {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (_) => _TextStylerSheet(
        controller: ctrl,
        onAdd: _addOverlay,
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSS) => SizedBox(
          height: 230,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Filter',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
              Expanded(
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: _filterNames.length,
                  itemBuilder: (_, i) {
                    final selected = _currentFilter == i.toDouble();
                    return GestureDetector(
                      onTap: () {
                        setSS(() {
                          _currentFilter = i.toDouble();
                          _filterStrength = 1.0;
                        });
                        setState(() {});
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
                                    : Colors.white24,
                                width: selected ? 2 : 1,
                              ),
                              color: const Color(0xFF2A2A2A),
                            ),
                            child: widget.thumbnailBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(7),
                                    child: Image.memory(
                                        widget.thumbnailBytes!,
                                        fit: BoxFit.cover),
                                  )
                                : const Icon(Icons.image,
                                    color: Colors.white38),
                          ),
                          const SizedBox(height: 4),
                          Text(_filterNames[i],
                              style: TextStyle(
                                  color: selected
                                      ? AppColors.primary
                                      : Colors.white54,
                                  fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Strength slider — blends between no effect and the
              // selected filter's full matrix, like Instagram's filter
              // intensity control (disabled on "Normal", which has no
              // effect to scale in the first place).
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.opacity_rounded,
                        color: Colors.white54, size: 18),
                    Expanded(
                      child: Slider(
                        value: _filterStrength,
                        min: 0,
                        max: 1,
                        activeColor: AppColors.primary,
                        inactiveColor: Colors.white24,
                        onChanged: _currentFilter == 0
                            ? null
                            : (v) {
                                setSS(() => _filterStrength = v);
                                setState(() {});
                              },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRatioSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Ratio',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15)),
          ),
          for (final entry in {
            'Original': BoxFit.contain,
            'Fill': BoxFit.cover,
          }.entries)
            ListTile(
              title: Text(entry.key,
                  style: const TextStyle(color: Colors.white)),
              trailing: _fit == entry.value
                  ? const Icon(Icons.check, color: AppColors.primary)
                  : null,
              onTap: () {
                setState(() => _fit = entry.value);
                Navigator.pop(context);
              },
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _showAdjustSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSS) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Adjust',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.brightness_6_outlined,
                      color: Colors.white54, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: _brightness,
                      min: -1,
                      max: 1,
                      activeColor: AppColors.primary,
                      inactiveColor: Colors.white24,
                      onChanged: (v) {
                        setSS(() => _brightness = v);
                        setState(() => _brightness = v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _onDrawStart(DragStartDetails details, Size boxSize) {
    final stroke = _DrawStroke(color: _drawColor);
    stroke.points.add(Offset(
      details.localPosition.dx / boxSize.width,
      details.localPosition.dy / boxSize.height,
    ));
    setState(() => _strokes.add(stroke));
  }

  void _onDrawUpdate(DragUpdateDetails details, Size boxSize) {
    if (_strokes.isEmpty) return;
    setState(() {
      _strokes.last.points.add(Offset(
        details.localPosition.dx / boxSize.width,
        details.localPosition.dy / boxSize.height,
      ));
    });
  }

  /// Renders one text/sticker overlay at its fractional position within
  /// [boxSize], centered on that point (via [FractionalTranslation]) so
  /// it doesn't need to know its own rendered size up front. Draggable —
  /// panning updates the overlay's stored fractional position directly.
  Widget _buildOverlay(int i, Size boxSize) {
    final overlay = _textOverlays[i];
    final font = _kTextFonts[overlay.fontIndex];

    Widget content = overlay.isSticker
        ? Text(overlay.text, style: const TextStyle(fontSize: 48))
        : Text(
            overlay.text,
            textAlign: overlay.textAlign,
            style: TextStyle(
              color: overlay.color,
              fontFamily: font.fontFamily,
              fontWeight: font.fontWeight,
              fontStyle: font.fontStyle,
              fontSize: 22,
            ),
          );

    if (!overlay.isSticker && overlay.hasBackground) {
      content = Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: content,
      );
    }

    return Positioned(
      left: overlay.position.dx * boxSize.width,
      top: overlay.position.dy * boxSize.height,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: GestureDetector(
          onLongPress: () => setState(() => _textOverlays.removeAt(i)),
          onPanUpdate: (details) {
            setState(() {
              overlay.position += Offset(
                details.delta.dx / boxSize.width,
                details.delta.dy / boxSize.height,
              );
            });
          },
          child: content,
        ),
      ),
    );
  }

  /// Captures the RepaintBoundary-scoped preview (media + filter +
  /// brightness + text/sticker overlays) as a real PNG and hands it to
  /// the caller to replace the original file. Videos can't have pixel
  /// edits baked in without a video re-encoder (out of scope here — the
  /// preview above still shows the chosen filter/brightness live, but
  /// only the display, not the uploaded file), so this only applies to
  /// images; any capture failure falls back to the original file too.
  Future<void> _handleNext() async {
    final hasEdits = _currentFilter != 0 ||
        _brightness != 0 ||
        _textOverlays.isNotEmpty ||
        _strokes.isNotEmpty ||
        _fit != BoxFit.cover;
    if (_isVideo || !hasEdits) {
      widget.onNext(null);
      return;
    }

    setState(() => _exporting = true);
    try {
      final boundary = _previewBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        widget.onNext(null);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        widget.onNext(null);
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File(path);
      await file.writeAsBytes(byteData.buffer.asUint8List());
      widget.onNext(file);
    } catch (_) {
      widget.onNext(null);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
              child: Row(
                children: [
                  // Back
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: Colors.white, size: 24),
                    onPressed: widget.onBack,
                  ),
                  const Spacer(),
                  // Audio track pill
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A2A2A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.music_note,
                            color: Colors.white70, size: 15),
                        SizedBox(width: 6),
                        Text('Original Audio',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500)),
                        SizedBox(width: 8),
                        Icon(Icons.add, color: Colors.white, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // "Suggested Audio" subtitle
            const Text(
              'Suggested Audio',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),

            const SizedBox(height: 6),

            // ── Media preview ────────────────────────────────────
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boxSize = constraints.biggest;
                  return GestureDetector(
                    onTap: (_isVideo && !_isDrawing) ? _togglePlayPause : null,
                    onPanStart: _isDrawing
                        ? (d) => _onDrawStart(d, boxSize)
                        : null,
                    onPanUpdate: _isDrawing
                        ? (d) => _onDrawUpdate(d, boxSize)
                        : null,
                    child: Container(
                      color: Colors.black,
                      width: double.infinity,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // RepaintBoundary scopes exactly what gets
                          // captured when exporting the edited image
                          // (media + filter + brightness + text/sticker
                          // overlays) — the play/pause icon below is
                          // deliberately outside it since that's transient
                          // UI chrome, not part of the photo/video itself.
                          RepaintBoundary(
                            key: _previewBoundaryKey,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Media
                                if (widget.thumbnailBytes != null)
                                  Positioned.fill(
                                    child: _withColorEffects(
                                      Image.memory(
                                        widget.thumbnailBytes!,
                                        fit: _fit,
                                      ),
                                    ),
                                  ),
                                // Video on top once ready
                                if (_isVideo && _videoReady)
                                  Positioned.fill(
                                    child: _withColorEffects(
                                      FittedBox(
                                        fit: _fit,
                                        child: SizedBox(
                                          width: _videoCtrl!.value.size.width,
                                          height:
                                              _videoCtrl!.value.size.height,
                                          child: VideoPlayer(_videoCtrl!),
                                        ),
                                      ),
                                    ),
                                  ),
                                // Freehand drawing strokes
                                if (_strokes.isNotEmpty)
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _DrawPainter(_strokes),
                                    ),
                                  ),
                                // Text / sticker overlays
                                for (int i = 0; i < _textOverlays.length; i++)
                                  _buildOverlay(i, boxSize),
                              ],
                            ),
                          ),
                          // Play/pause icon — UI-only, not part of the export
                          if (_isVideo && !_playing && !_isDrawing)
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: const BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 48),
                            ),
                          // Drawing-mode controls — UI-only, not exported
                          if (_isDrawing)
                            Positioned(
                              top: 8,
                              left: 8,
                              right: 8,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: SizedBox(
                                      height: 32,
                                      child: ListView(
                                        scrollDirection: Axis.horizontal,
                                        children: [
                                          for (final c in _kTextColors)
                                            GestureDetector(
                                              onTap: () => setState(
                                                  () => _drawColor = c),
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                    right: 8),
                                                width: 28,
                                                height: 28,
                                                decoration: BoxDecoration(
                                                  color: c,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: _drawColor == c
                                                        ? AppColors.primary
                                                        : Colors.white38,
                                                    width: _drawColor == c
                                                        ? 2.5
                                                        : 1,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.undo_rounded,
                                        color: Colors.white),
                                    onPressed: _strokes.isEmpty
                                        ? null
                                        : () => setState(
                                            () => _strokes.removeLast()),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.check_circle,
                                        color: AppColors.primary),
                                    onPressed: () =>
                                        setState(() => _isDrawing = false),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // ── Tool bar ─────────────────────────────────────────
            Container(
              color: const Color(0xFF111111),
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _EditTool(
                    icon: Icons.music_note_outlined,
                    label: 'Audio',
                    onTap: _showAudioTool,
                  ),
                  _EditTool(
                    icon: Icons.text_fields_rounded,
                    label: 'Text',
                    onTap: _showTextTool,
                  ),
                  _EditTool(
                    icon: Icons.layers_outlined,
                    label: 'Overlay',
                    onTap: _showOverlayTool,
                  ),
                  _EditTool(
                    icon: Icons.edit_rounded,
                    label: 'Draw',
                    onTap: () => setState(() => _isDrawing = true),
                  ),
                  _EditTool(
                    icon: Icons.tune_outlined,
                    label: 'Filter',
                    onTap: _showFilterSheet,
                  ),
                  _EditTool(
                    icon: Icons.brightness_6_outlined,
                    label: 'Edit',
                    onTap: _showAdjustSheet,
                  ),
                  _EditTool(
                    icon: Icons.crop_free_outlined,
                    label: 'Ratio',
                    onTap: _showRatioSheet,
                  ),
                ],
              ),
            ),

            // ── Thumbnail strip + Next button ────────────────────
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
              child: Row(
                children: [
                  // Thumbnail of selected media
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: widget.thumbnailBytes != null
                        ? Image.memory(
                            widget.thumbnailBytes!,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 48,
                            height: 48,
                            color: const Color(0xFF2A2A2A),
                            child: const Icon(Icons.image,
                                color: Colors.white38, size: 24)),
                  ),
                  const SizedBox(width: 8),
                  // Add more media
                  GestureDetector(
                    onTap: widget.onBack, // go back to picker to add more
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.white24, width: 1),
                      ),
                      child: const Icon(Icons.add,
                          color: Colors.white, size: 24),
                    ),
                  ),
                  const Spacer(),
                  // Next button
                  FilledButton(
                    onPressed: _exporting ? null : _handleNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0095F6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _exporting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Next',
                            style: TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
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

List<double> _brightnessMatrix(double brightness) {
  // ColorFilter matrix for brightness adjustment (5x4 matrix flattened)
  final b = brightness * 255;
  return [
    1, 0, 0, 0, b,
    0, 1, 0, 0, b,
    0, 0, 1, 0, b,
    0, 0, 0, 1, 0,
  ];
}

/// Real per-filter color matrices, indexed the same as `_filterNames`
/// (Normal, Clarendon, Gingham, Moon, Lark) — approximations of the
/// named Instagram-style looks, applied for real (not just cosmetic
/// labels) to both the live preview and the final exported image.
const List<List<double>> _kFilterMatrices = [
  // Normal — identity
  [
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ],
  // Clarendon — punchier contrast + cooler shadows
  [
    1.15, 0, 0, 0, -18,
    0, 1.12, 0.05, 0, -18,
    0.05, 0, 1.18, 0, -10,
    0, 0, 0, 1, 0,
  ],
  // Gingham — warm, slightly washed-out/faded
  [
    0.95, 0.05, 0.05, 0, 18,
    0.05, 0.92, 0.05, 0, 14,
    0.05, 0.05, 0.85, 0, 10,
    0, 0, 0, 1, 0,
  ],
  // Moon — desaturated / black & white with a cool tint
  [
    0.35, 0.4, 0.15, 0, 5,
    0.35, 0.4, 0.15, 0, 5,
    0.4, 0.45, 0.2, 0, 15,
    0, 0, 0, 1, 0,
  ],
  // Lark — bright, airy, cool-leaning highlights
  [
    1.05, 0, 0.05, 0, 8,
    0, 1.08, 0.05, 0, 8,
    0, 0.05, 1.1, 0, 4,
    0, 0, 0, 1, 0,
  ],
  // Juno — warm and rich with boosted reds
  [
    1.2, -0.05, 0, 0, 6,
    0, 1.08, 0, 0, 2,
    0, -0.05, 0.95, 0, 0,
    0, 0, 0, 1, 0,
  ],
  // Ludwig — muted, slightly desaturated with a subtle contrast lift
  [
    1.05, 0.02, 0.02, 0, -6,
    0.02, 1.0, 0.02, 0, -6,
    0.02, 0.02, 0.95, 0, -6,
    0, 0, 0, 1, 0,
  ],
  // Aden — soft pastel wash, blue-green tint
  [
    1.0, 0, 0.08, 0, 20,
    0.05, 1.0, 0.05, 0, 18,
    0.05, 0.05, 1.0, 0, 22,
    0, 0, 0, 1, 0,
  ],
  // Valencia — warm vintage glow, lifted shadows
  [
    1.15, 0.05, 0, 0, 12,
    0.05, 1.05, 0, 0, 6,
    0, 0, 0.9, 0, 4,
    0, 0, 0, 1, 0,
  ],
  // Willow — near-monochrome with a faint lavender cast
  [
    0.45, 0.35, 0.2, 0, 20,
    0.4, 0.4, 0.2, 0, 15,
    0.45, 0.35, 0.25, 0, 25,
    0, 0, 0, 1, 0,
  ],
  // Mayfair — punchy warm contrast with a soft pink vignette tone
  [
    1.18, 0, 0.02, 0, 4,
    0, 1.1, 0, 0, 0,
    0.05, 0, 1.05, 0, 6,
    0, 0, 0, 1, 0,
  ],
];

/// A single freehand pen stroke. Points are stored fractionally (0.0–1.0
/// on each axis), same scheme as `_TextOverlay.position`, so drawings
/// stay correctly placed regardless of preview size or the RepaintBoundary
/// capture's pixel ratio.
class _DrawStroke {
  _DrawStroke({required this.color});
  final Color color;
  final double strokeWidth = 4;
  final List<Offset> points = [];
}

class _DrawPainter extends CustomPainter {
  const _DrawPainter(this.strokes);
  final List<_DrawStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.length < 2) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(
          stroke.points.first.dx * size.width,
          stroke.points.first.dy * size.height,
        );
      for (final p in stroke.points.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DrawPainter oldDelegate) => true;
}

class _TextOverlay {
  _TextOverlay({
    required this.text,
    this.isSticker = false,
    this.color = Colors.white,
    this.hasBackground = false,
    this.fontIndex = 0,
    this.textAlign = TextAlign.center,
    Offset? position,
  }) : position = position ?? const Offset(0.5, 0.25);

  final String text;
  final bool isSticker;
  Color color;
  bool hasBackground;
  int fontIndex;
  TextAlign textAlign;

  /// Fractional position (0.0–1.0 on each axis) within the preview —
  /// resolution-independent, so it captures correctly at any
  /// RepaintBoundary pixel ratio and survives the preview being resized.
  Offset position;
}

/// A curated set of visually distinct looks built from fonts already
/// bundled with the app (Poppins/Inter) plus a system monospace option —
/// deliberately not using google_fonts' network font-fetching for a
/// picker that should feel instant while editing.
class _TextFontStyle {
  const _TextFontStyle(this.label, this.fontFamily, this.fontWeight, this.fontStyle);
  final String label;
  final String? fontFamily;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
}

const List<_TextFontStyle> _kTextFonts = [
  _TextFontStyle('Classic', 'Inter', FontWeight.w500, FontStyle.normal),
  _TextFontStyle('Bold', 'Poppins', FontWeight.w800, FontStyle.normal),
  _TextFontStyle('Elegant', 'Inter', FontWeight.w400, FontStyle.italic),
  _TextFontStyle('Strong', 'Poppins', FontWeight.w700, FontStyle.normal),
  _TextFontStyle('Typewriter', 'monospace', FontWeight.w600, FontStyle.normal),
];

const List<Color> _kTextColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFF3B30),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF007AFF),
  Color(0xFFAF52DE),
  Color(0xFFFF2D55),
];

// ─────────────────────────────────────────────────────────────────
// Text Styler Sheet — live-previewed color/font/background/alignment
// controls for a new text overlay.
// ─────────────────────────────────────────────────────────────────

class _TextStylerSheet extends StatefulWidget {
  const _TextStylerSheet({required this.controller, required this.onAdd});
  final TextEditingController controller;
  final ValueChanged<_TextOverlay> onAdd;

  @override
  State<_TextStylerSheet> createState() => _TextStylerSheetState();
}

class _TextStylerSheetState extends State<_TextStylerSheet> {
  Color _color = Colors.white;
  bool _hasBackground = false;
  int _fontIndex = 0;
  TextAlign _align = TextAlign.center;

  TextStyle get _previewStyle {
    final font = _kTextFonts[_fontIndex];
    return TextStyle(
      color: _color,
      fontFamily: font.fontFamily,
      fontWeight: font.fontWeight,
      fontStyle: font.fontStyle,
      fontSize: 22,
    );
  }

  void _add() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) {
      Navigator.pop(context);
      return;
    }
    widget.onAdd(_TextOverlay(
      text: text,
      color: _color,
      hasBackground: _hasBackground,
      fontIndex: _fontIndex,
      textAlign: _align,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Live preview of the text as styled so far
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              controller: widget.controller,
              autofocus: true,
              textAlign: _align,
              style: _previewStyle,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Add text…',
                hintStyle: _previewStyle.copyWith(
                    color: _previewStyle.color?.withValues(alpha: 0.4)),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Color swatches
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kTextColors.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final c = _kTextColors[i];
                final selected = c == _color;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? AppColors.primary : Colors.white24,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Font styles
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kTextFonts.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _kTextFonts[i];
                final selected = i == _fontIndex;
                return GestureDetector(
                  onTap: () => setState(() => _fontIndex = i),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.2)
                          : const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected ? AppColors.primary : Colors.white12,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      f.label,
                      style: TextStyle(
                        color: selected ? AppColors.primary : Colors.white70,
                        fontFamily: f.fontFamily,
                        fontWeight: f.fontWeight,
                        fontStyle: f.fontStyle,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // Background toggle + alignment
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _hasBackground = !_hasBackground),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _hasBackground
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          _hasBackground ? AppColors.primary : Colors.white12,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.format_color_fill_rounded,
                          size: 15,
                          color: _hasBackground
                              ? AppColors.primary
                              : Colors.white70),
                      const SizedBox(width: 5),
                      Text('Background',
                          style: TextStyle(
                              fontSize: 12,
                              color: _hasBackground
                                  ? AppColors.primary
                                  : Colors.white70)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              for (final entry in {
                TextAlign.left: Icons.format_align_left_rounded,
                TextAlign.center: Icons.format_align_center_rounded,
                TextAlign.right: Icons.format_align_right_rounded,
              }.entries)
                IconButton(
                  onPressed: () => setState(() => _align = entry.key),
                  icon: Icon(
                    entry.value,
                    color: _align == entry.key
                        ? AppColors.primary
                        : Colors.white38,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          FilledButton(
            onPressed: _add,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              minimumSize: const Size.fromHeight(44),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _EditTool extends StatelessWidget {
  const _EditTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 26),
          const SizedBox(height: 5),
          Text(label,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Audio Picker Sheet  (Instagram-style: search + tabs + iTunes API)
// ─────────────────────────────────────────────────────────────────

class _AudioTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String artworkUrl;
  final String previewUrl;
  final int durationMs;
  bool saved;

  _AudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
    required this.previewUrl,
    required this.durationMs,
  }) : saved = false;

  String get durationLabel {
    final s = (durationMs / 1000).round();
    final m = s ~/ 60;
    final sec = s % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  factory _AudioTrack.fromItunes(Map<String, dynamic> j) {
    return _AudioTrack(
      id: '${j['trackId'] ?? j['collectionId'] ?? UniqueKey().hashCode}',
      title: j['trackName'] as String? ?? j['collectionName'] as String? ?? '',
      artist: j['artistName'] as String? ?? '',
      album: j['collectionName'] as String? ?? '',
      artworkUrl: (j['artworkUrl100'] as String? ?? '').replaceAll('100x100', '300x300'),
      previewUrl: j['previewUrl'] as String? ?? '',
      durationMs: j['trackTimeMillis'] as int? ?? 0,
    );
  }
}

class _AudioPickerSheet extends StatefulWidget {
  const _AudioPickerSheet({required this.onSelected});
  final ValueChanged<_AudioTrack> onSelected;

  @override
  State<_AudioPickerSheet> createState() => _AudioPickerSheetState();
}

class _AudioPickerSheetState extends State<_AudioPickerSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _searchCtrl = TextEditingController();
  final _dio = Dio();
  final _player = AudioPlayer();

  List<_AudioTrack> _forYou = [];
  List<_AudioTrack> _trending = [];
  final List<_AudioTrack> _saved = [];
  List<_AudioTrack> _searchResults = [];
  bool _searching = false;
  bool _loadingForYou = true;
  bool _loadingTrending = true;
  String? _playingId;
  Timer? _debounce;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _fetchForYou();
    _fetchTrending();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingId = null);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _player.dispose();
    _debounce?.cancel();
    _dio.close();
    super.dispose();
  }

  Future<List<_AudioTrack>> _itunesSearch(String term,
      {int limit = 20}) async {
    try {
      final res = await _dio.get(
        'https://itunes.apple.com/search',
        queryParameters: {
          'term': term,
          'media': 'music',
          'entity': 'song',
          'limit': limit,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      if (res.statusCode != 200) return [];
      final raw = res.data;
      final resultList = raw is Map ? (raw['results'] as List<dynamic>? ?? []) : <dynamic>[];
      final results = resultList
          .cast<Map<String, dynamic>>()
          .where((j) => (j['previewUrl'] as String? ?? '').isNotEmpty)
          .map(_AudioTrack.fromItunes)
          .toList();
      return results;
    } catch (_) {
      return [];
    }
  }

  Future<void> _fetchForYou() async {
    if (mounted) setState(() => _loadingForYou = true);
    // No pre-seeded fallback data — a previous version showed hardcoded
    // tracks instantly, but their preview URLs go stale (iTunes CDN links
    // aren't permanent) and users ended up tapping play on dead links.
    // Honest loading state instead; empty result shows a retry option.
    final tracks = await _itunesSearch('top hits pop', limit: 25);
    if (mounted) setState(() { _forYou = tracks; _loadingForYou = false; });
  }

  Future<void> _fetchTrending() async {
    if (mounted) setState(() => _loadingTrending = true);
    final tracks = await _itunesSearch('trending afrobeats viral 2024', limit: 25);
    if (mounted) setState(() { _trending = tracks; _loadingTrending = false; });
  }

  void _onSearchChanged(String q) {
    setState(() => _query = q);
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() { _searchResults = []; _searching = false; });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await _itunesSearch(q.trim(), limit: 30);
      if (mounted) setState(() { _searchResults = results; _searching = false; });
    });
  }

  Future<void> _togglePlay(_AudioTrack track) async {
    if (track.previewUrl.isEmpty) return;
    if (_playingId == track.id) {
      await _player.stop();
      setState(() => _playingId = null);
    } else {
      await _player.stop();
      await _player.play(UrlSource(track.previewUrl));
      setState(() => _playingId = track.id);
    }
  }

  void _toggleSave(_AudioTrack track) {
    setState(() {
      track.saved = !track.saved;
      if (track.saved) {
        if (!_saved.any((t) => t.id == track.id)) _saved.add(track);
      } else {
        _saved.removeWhere((t) => t.id == track.id);
      }
    });
  }

  void _selectTrack(_AudioTrack track) {
    _player.stop();
    widget.onSelected(track);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 14),
            // Title
            const Text('Add Audio',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            // Search bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(Icons.search, color: Colors.white38),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, color: Colors.white38),
                          onPressed: () {
                            _searchCtrl.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF2A2A2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Tabs (hidden when searching)
            if (_query.isEmpty)
              TabBar(
                controller: _tab,
                isScrollable: true,
                tabs: const [
                  Tab(text: 'For you'),
                  Tab(text: 'Trending'),
                  Tab(text: 'Saved'),
                  Tab(text: 'Original audio'),
                ],
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white38,
                indicatorColor: AppColors.primary,
                labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                dividerColor: Colors.white12,
                tabAlignment: TabAlignment.start,
              ),
            const SizedBox(height: 4),
            // Body
            Expanded(
              child: _query.isNotEmpty
                  ? _searching
                      ? const Center(child: CircularProgressIndicator())
                      : _searchResults.isEmpty
                          ? const Center(
                              child: Text('No results found',
                                  style: TextStyle(color: Colors.white38)))
                          : _TrackList(
                              tracks: _searchResults,
                              playingId: _playingId,
                              onPlay: _togglePlay,
                              onSave: _toggleSave,
                              onSelect: _selectTrack,
                            )
                  : TabBarView(
                      controller: _tab,
                      children: [
                        // For You
                        _loadingForYou
                            ? const Center(child: CircularProgressIndicator())
                            : _forYou.isEmpty
                                ? _AudioLoadError(onRetry: _fetchForYou)
                                : _TrackList(
                                    tracks: _forYou,
                                    playingId: _playingId,
                                    onPlay: _togglePlay,
                                    onSave: _toggleSave,
                                    onSelect: _selectTrack,
                                  ),
                        // Trending
                        _loadingTrending
                            ? const Center(child: CircularProgressIndicator())
                            : _trending.isEmpty
                                ? _AudioLoadError(onRetry: _fetchTrending)
                                : _TrackList(
                                    tracks: _trending,
                                    playingId: _playingId,
                                    onPlay: _togglePlay,
                                    onSave: _toggleSave,
                                    onSelect: _selectTrack,
                                  ),
                        // Saved
                        _saved.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bookmark_border,
                                        color: Colors.white24, size: 48),
                                    SizedBox(height: 12),
                                    Text('No saved audio yet',
                                        style: TextStyle(color: Colors.white38)),
                                  ],
                                ),
                              )
                            : _TrackList(
                                tracks: _saved,
                                playingId: _playingId,
                                onPlay: _togglePlay,
                                onSave: _toggleSave,
                                onSelect: _selectTrack,
                              ),
                        // Original audio
                        _TrackList(
                          tracks: [
                            _AudioTrack(
                              id: 'original',
                              title: 'Original Audio',
                              artist: 'From your video',
                              album: '',
                              artworkUrl: '',
                              previewUrl: '',
                              durationMs: 0,
                            ),
                          ],
                          playingId: _playingId,
                          onPlay: _togglePlay,
                          onSave: _toggleSave,
                          onSelect: _selectTrack,
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

class _AudioLoadError extends StatelessWidget {
  const _AudioLoadError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, color: Colors.white24, size: 40),
          const SizedBox(height: 12),
          const Text("Couldn't load songs",
              style: TextStyle(color: Colors.white38)),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.tracks,
    required this.playingId,
    required this.onPlay,
    required this.onSave,
    required this.onSelect,
  });

  final List<_AudioTrack> tracks;
  final String? playingId;
  final void Function(_AudioTrack) onPlay;
  final void Function(_AudioTrack) onSave;
  final void Function(_AudioTrack) onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: tracks.length,
      itemBuilder: (_, i) {
        final t = tracks[i];
        final isPlaying = playingId == t.id;
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          leading: GestureDetector(
            onTap: () => onPlay(t),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: t.artworkUrl.isNotEmpty
                      ? Image.network(
                          t.artworkUrl,
                          width: 48, height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _DefaultArt(isPlaying: isPlaying),
                        )
                      : _DefaultArt(isPlaying: isPlaying),
                ),
                if (isPlaying)
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.pause,
                        color: Colors.white, size: 22),
                  )
                else if (t.previewUrl.isNotEmpty)
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white70, size: 22),
                  ),
              ],
            ),
          ),
          title: Text(
            t.title,
            style: TextStyle(
              color: isPlaying ? AppColors.primary : Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            t.durationMs > 0
                ? '${t.artist}  ·  ${t.durationLabel}'
                : t.artist,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  t.saved ? Icons.bookmark : Icons.bookmark_border,
                  color: t.saved ? AppColors.primary : Colors.white54,
                  size: 22,
                ),
                onPressed: () => onSave(t),
              ),
            ],
          ),
          onTap: () => onSelect(t),
        );
      },
    );
  }
}

class _DefaultArt extends StatelessWidget {
  const _DefaultArt({required this.isPlaying});
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48, height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note,
          color: isPlaying ? AppColors.primary : Colors.white38, size: 22),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Step 3 — Share / Caption (Instagram "New reel" final screen)
// ─────────────────────────────────────────────────────────────────

class _ShareStep extends ConsumerWidget {
  const _ShareStep({
    required this.thumbnailBytes,
    required this.file,
    required this.asset,
    required this.captionCtrl,
    required this.locationCtrl,
    required this.audioLabel,
    required this.onAudioLabelChanged,
    required this.onBack,
    required this.onSubmit,
    required this.onSaveDraft,
  });
  final Uint8List? thumbnailBytes;
  final File? file;
  final AssetEntity? asset;
  final TextEditingController captionCtrl;
  final TextEditingController locationCtrl;
  final String audioLabel;
  final ValueChanged<String> onAudioLabelChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final Future<void> Function() onSaveDraft;

  /// Inserts '#' at the caption's current cursor position and focuses it —
  /// same behavior as Instagram's "Hashtags" quick-add chip.
  void _insertHashtag(WidgetRef ref) {
    final text = captionCtrl.text;
    final cursor = captionCtrl.selection.start >= 0
        ? captionCtrl.selection.start
        : text.length;
    final newText = text.replaceRange(cursor, cursor, '#');
    captionCtrl.value = captionCtrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor + 1),
    );
    ref.read(newPostProvider.notifier).setCaption(newText);
  }

  void _showTagPeopleSheet(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(newPostProvider.notifier);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111111),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _TagPeopleSheet(
        initiallyTagged: ref.read(newPostProvider).taggedUsers,
        onAdd: notifier.addTaggedUser,
        onRemove: notifier.removeTaggedUser,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(newPostProvider);
    final isUploading = post.status == NewPostStatus.uploading;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: onBack,
        ),
        title: const Text('New post',
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail + Edit cover ─────────────────────────
            Center(
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: thumbnailBytes != null
                        ? Image.memory(thumbnailBytes!,
                            width: 200, height: 200, fit: BoxFit.cover)
                        : Container(
                            width: 200,
                            height: 200,
                            color: const Color(0xFF1A1A1A),
                            child: const Icon(
                                Icons.play_circle_filled_rounded,
                                color: AppColors.primary,
                                size: 48)),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {},
                    child: const Text('Edit cover',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ── Caption field ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: captionCtrl,
                onChanged: ref.read(newPostProvider.notifier).setCaption,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                maxLines: 4,
                minLines: 2,
                maxLength: 2200,
                decoration: const InputDecoration(
                  hintText: 'Write a caption and add hashtags…',
                  hintStyle:
                      TextStyle(color: Colors.white38, fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  counterStyle:
                      TextStyle(color: Colors.white24, fontSize: 10),
                ),
              ),
            ),

            // ── Quick-add chips ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Wrap(
                spacing: 8,
                children: [
                  _QuickChip(
                      icon: Icons.tag,
                      label: 'Hashtags',
                      onTap: () => _insertHashtag(ref)),
                  _QuickChip(
                      icon: Icons.bar_chart_rounded,
                      label: 'Poll',
                      onTap: () {}),
                  _QuickChip(
                      icon: Icons.lightbulb_outline,
                      label: 'Prompt',
                      onTap: () {}),
                ],
              ),
            ),

            const Divider(color: Color(0xFF2A2A2A), height: 1),

            // ── Tag people ─────────────────────────────────────
            _ShareRow(
              icon: Icons.person_pin_outlined,
              label: 'Tag people',
              onTap: () => _showTagPeopleSheet(context, ref),
              subtitle: post.taggedUsers.isNotEmpty
                  ? 'with ${post.taggedUsers.map((u) => '@${u.username}').join(', ')}'
                  : null,
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),

            // ── Add location ───────────────────────────────────
            _ShareRow(
              icon: Icons.location_on_outlined,
              label: 'Add location',
              onTap: () {},
              subtitle:
                  'People you share this content with can see the location you\ntag and view this content on the map.',
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),

            // ── Hub ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.explore_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 14),
                  const Text('Hub',
                      style: TextStyle(
                          color: Colors.white, fontSize: 15)),
                  const Spacer(),
                  _HubPickerInline(
                    selected: post.hubType,
                    onChanged:
                        ref.read(newPostProvider.notifier).setHub,
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),

            // ── Rename audio ───────────────────────────────────
            _ShareRow(
              icon: Icons.audio_file_outlined,
              label: 'Rename audio',
              trailing: Text(audioLabel,
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 14)),
              onTap: () async {
                final ctrl = TextEditingController(text: audioLabel);
                await showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: const Color(0xFF1A1A1A),
                    title: const Text('Rename audio',
                        style: TextStyle(color: Colors.white)),
                    content: TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintStyle:
                            TextStyle(color: Colors.white38),
                        enabledBorder: UnderlineInputBorder(
                            borderSide:
                                BorderSide(color: Colors.white24)),
                        focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                                color: AppColors.primary)),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel',
                            style:
                                TextStyle(color: Colors.white54)),
                      ),
                      TextButton(
                        onPressed: () {
                          onAudioLabelChanged(ctrl.text.trim());
                          Navigator.pop(context);
                        },
                        child: const Text('Save',
                            style: TextStyle(
                                color: AppColors.primary)),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),

            // ── Add AI label ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_outlined,
                      color: Colors.white, size: 22),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Add AI label',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                                height: 1.4),
                            children: [
                              const TextSpan(
                                text:
                                    'We require you to label certain realistic content that\'s made with AI. ',
                              ),
                              WidgetSpan(
                                child: GestureDetector(
                                  onTap: () {},
                                  child: const Text('Learn more',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          decoration:
                                              TextDecoration
                                                  .underline)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: post.isAiGenerated,
                    onChanged:
                        ref.read(newPostProvider.notifier).setAiGenerated,
                    activeThumbColor: AppColors.primary,
                    activeTrackColor: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
            const Divider(color: Color(0xFF2A2A2A), height: 1),
          ],
        ),
      ),

      // ── Discard / Share buttons ───────────────────────────────
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isUploading && post.uploadTotal > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Uploading ${post.uploadedCount} of ${post.uploadTotal}…',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: isUploading
                          ? null
                          : () => _confirmDiscard(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('Discard',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: (post.canPost && !isUploading)
                          ? onSubmit
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0095F6),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: isUploading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Share',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(BuildContext context) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Leave this post?',
            style: TextStyle(color: Colors.white)),
        content: const Text(
          'Save it as a draft to finish later, or discard it.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'save'),
            child: const Text('Save draft'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      await onSaveDraft();
    }
    if ((choice == 'save' || choice == 'discard') && context.mounted) {
      context.pop();
    }
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailing,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(width: 14),
                Text(label,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w400)),
                const Spacer(),
                trailing ??
                    const Icon(Icons.chevron_right,
                        color: Colors.white38),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: Text(subtitle!,
                    style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                        height: 1.4)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Hub picker (reused from before)
// ─────────────────────────────────────────────────────────────────

class _HubPickerInline extends StatelessWidget {
  const _HubPickerInline(
      {required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  static const _hubs = [
    (AppConstants.hubAll, 'All', Icons.public),
    (AppConstants.hubFaith, 'Faith', Icons.church),
    (AppConstants.hubBiology, 'Biology', Icons.biotech_rounded),
    (AppConstants.hubChemistry, 'Chemistry', Icons.science_rounded),
    (AppConstants.hubPhysics, 'Physics', Icons.electric_bolt_rounded),
    (AppConstants.hubMathematics, 'Mathematics', Icons.calculate_rounded),
    (AppConstants.hubPsychology, 'Psychology', Icons.psychology_rounded),
    (AppConstants.hubGeography, 'Geography', Icons.public_rounded),
    (AppConstants.hubHistory, 'History', Icons.history_edu_rounded),
    (AppConstants.hubEngineering, 'Engineering', Icons.engineering_rounded),
    (AppConstants.hubRobotics, 'Robotics', Icons.smart_toy_rounded),
    (AppConstants.hubAviation, 'Aviation', Icons.flight_rounded),
    (AppConstants.hubComputerScience, 'Computer Science', Icons.computer_rounded),
    (AppConstants.hubFrench, 'French', Icons.language),
    (AppConstants.hubEnglish, 'English', Icons.language),
    (AppConstants.hubSpanish, 'Spanish', Icons.language),
    (AppConstants.hubGerman, 'German', Icons.language),
    (AppConstants.hubSwahili, 'Swahili', Icons.language),
    (AppConstants.hubChinese, 'Chinese', Icons.language),
    (AppConstants.hubJapanese, 'Japanese', Icons.language),
    (AppConstants.hubArabic, 'Arabic', Icons.language),
  ];

  @override
  Widget build(BuildContext context) {
    final hub = _hubs.firstWhere(
      (h) => h.$1 == selected,
      orElse: () => _hubs.first,
    );
    return PopupMenuButton<String>(
      initialValue: selected,
      onSelected: onChanged,
      color: const Color(0xFF1C1C1C),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(hub.$3, size: 14, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(hub.$2,
              style: const TextStyle(
                  color: AppColors.primary, fontSize: 13)),
          const Icon(Icons.arrow_drop_down,
              size: 16, color: AppColors.primary),
        ],
      ),
      itemBuilder: (_) => _hubs
          .map(
            (h) => PopupMenuItem<String>(
              value: h.$1,
              child: Row(
                children: [
                  Icon(h.$3, size: 16, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(h.$2,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Tag People Sheet — search + multi-select, mirrors Instagram's
// "Tag people" picker.
// ─────────────────────────────────────────────────────────────────

class _TagPeopleSheet extends StatefulWidget {
  const _TagPeopleSheet({
    required this.initiallyTagged,
    required this.onAdd,
    required this.onRemove,
  });
  final List<TaggedUser> initiallyTagged;
  final ValueChanged<TaggedUser> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<_TagPeopleSheet> createState() => _TagPeopleSheetState();
}

class _TagPeopleSheetState extends State<_TagPeopleSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  late List<TaggedUser> _tagged;

  @override
  void initState() {
    super.initState();
    _tagged = List.from(widget.initiallyTagged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final results =
          await PostRepository.instance.searchUsersForTagging(q.trim());
      if (mounted) setState(() { _results = results; _searching = false; });
    });
  }

  void _toggle(Map<String, dynamic> user) {
    final id = user['id'] as String;
    final already = _tagged.any((u) => u.id == id);
    setState(() {
      if (already) {
        _tagged.removeWhere((u) => u.id == id);
        widget.onRemove(id);
      } else {
        final tagged = TaggedUser(
          id: id,
          username: user['username'] as String? ?? '',
          fullName: user['full_name'] as String?,
          avatarUrl: user['avatar_url'] as String?,
        );
        _tagged.add(tagged);
        widget.onAdd(tagged);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 60),
                const Text('Tag people',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          if (_tagged.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                height: 32,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: _tagged.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final t = _tagged[i];
                    return Chip(
                      backgroundColor: const Color(0xFF2A2A2A),
                      label: Text('@${t.username}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      deleteIconColor: Colors.white54,
                      onDeleted: () => _toggle({'id': t.id}),
                    );
                  },
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search for people',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF2A2A2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searchCtrl.text.trim().isEmpty
                              ? 'Search by username or name'
                              : 'No users found',
                          style: const TextStyle(color: Colors.white38),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final u = _results[i];
                          final id = u['id'] as String;
                          final isTagged = _tagged.any((t) => t.id == id);
                          final avatarUrl = u['avatar_url'] as String?;
                          return ListTile(
                            leading: CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF2A2A2A),
                              backgroundImage: (avatarUrl != null &&
                                      avatarUrl.isNotEmpty)
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: (avatarUrl == null || avatarUrl.isEmpty)
                                  ? const Icon(Icons.person,
                                      color: Colors.white38)
                                  : null,
                            ),
                            title: Text(
                              u['username'] as String? ?? '',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                            ),
                            subtitle: (u['full_name'] as String?)
                                        ?.isNotEmpty ==
                                    true
                                ? Text(u['full_name'] as String,
                                    style: const TextStyle(
                                        color: Colors.white38, fontSize: 12))
                                : null,
                            trailing: Icon(
                              isTagged
                                  ? Icons.check_circle
                                  : Icons.circle_outlined,
                              color: isTagged
                                  ? AppColors.primary
                                  : Colors.white24,
                            ),
                            onTap: () => _toggle(u),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

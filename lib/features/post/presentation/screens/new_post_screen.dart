import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/draft_repository.dart';
import '../providers/new_post_provider.dart';

// ── Step enum ─────────────────────────────────────────────────────
enum _Step { picker, edit, share }

// ─────────────────────────────────────────────────────────────────
// Root screen — drives the 3-step flow
// ─────────────────────────────────────────────────────────────────

class NewPostScreen extends ConsumerStatefulWidget {
  const NewPostScreen({super.key});

  @override
  ConsumerState<NewPostScreen> createState() => _NewPostScreenState();
}

class _NewPostScreenState extends ConsumerState<NewPostScreen> {
  _Step _step = _Step.picker;
  AssetEntity? _selectedAsset;
  File? _selectedFile;
  Uint8List? _thumbnailBytes;
  final _captionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  String _audioLabel = 'Original Audio';
  bool _aiLabel = false;
  bool _hasDraft = false;

  @override
  void initState() {
    super.initState();
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
            onNext: () => setState(() => _step = _Step.share),
          ),
        _Step.share => _ShareStep(
            thumbnailBytes: _thumbnailBytes,
            file: _selectedFile,
            asset: _selectedAsset,
            captionCtrl: _captionCtrl,
            locationCtrl: _locationCtrl,
            audioLabel: _audioLabel,
            aiLabel: _aiLabel,
            onAiLabelChanged: (v) => setState(() => _aiLabel = v),
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
  });
  final Future<void> Function(AssetEntity) onSelected;
  final VoidCallback onClose;
  final bool hasDraft;
  final VoidCallback onLoadDraft;

  @override
  State<_GalleryPickerStep> createState() => _GalleryPickerStepState();
}

class _GalleryPickerStepState extends State<_GalleryPickerStep>
    with SingleTickerProviderStateMixin {
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  List<AssetEntity> _assets = [];
  AssetEntity? _previewAsset;
  Uint8List? _previewThumb;
  bool _loading = true;
  bool _permDenied = false;
  int _page = 0;
  static const _pageSize = 60;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _requestAndLoad();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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
                    const Expanded(
                      child: Text('New reel',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600)),
                    ),
                    const Icon(Icons.settings_outlined,
                        color: Colors.white, size: 22),
                  ],
                ),
              ),
              // Drafts / Templates chips
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
                child: Row(
                  children: [
                    _Chip(
                      label: widget.hasDraft ? 'Drafts · 1' : 'Drafts · 0',
                      icon: Icons.layers_outlined,
                      onTap: widget.hasDraft ? widget.onLoadDraft : null,
                    ),
                    const SizedBox(width: 10),
                    const _Chip(
                        label: 'Templates', icon: Icons.auto_awesome_mosaic_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Preview pane ───────────────────────────────────────
        AspectRatio(
          aspectRatio: 1,
          child: _permDenied
              ? _PermDeniedBanner()
              : _previewThumb != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(_previewThumb!, fit: BoxFit.cover),
                        // Tap to proceed
                        if (_previewAsset != null)
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: GestureDetector(
                              onTap: () {
                                if (_previewAsset != null) {
                                  widget.onSelected(_previewAsset!);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white38),
                                ),
                                child: const Text('Use this',
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 13)),
                              ),
                            ),
                          ),
                      ],
                    )
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
                          onTap: () => _selectPreview(asset),
                          onDoubleTap: () => widget.onSelected(asset),
                        );
                      },
                    ),
        ),

        // ── Bottom tab bar: REEL | TEMPLATES ──────────────────
        SafeArea(
          top: false,
          child: Container(
            color: const Color(0xFF111111),
            child: TabBar(
              controller: _tabCtrl,
              tabs: const [
                Tab(text: 'REEL'),
                Tab(text: 'TEMPLATES'),
              ],
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              indicatorColor: Colors.white,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
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
  });
  final AssetEntity? asset;
  final File? file;
  final Uint8List? thumbnailBytes;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  State<_EditStep> createState() => _EditStepState();
}

class _EditStepState extends State<_EditStep> {
  VideoPlayerController? _videoCtrl;
  bool _isVideo = false;
  bool _videoReady = false;
  bool _playing = false;

  // Overlays added by tools
  final List<_TextOverlay> _textOverlays = [];
  double _currentFilter = 0; // 0–4 index
  BoxFit _fit = BoxFit.cover;
  double _brightness = 0;

  static const _filterNames = ['Normal', 'Clarendon', 'Gingham', 'Moon', 'Lark'];

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

  // ── Audio picker ────────────────────────────────────────────────
  void _showAudioTool() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AudioPickerSheet(),
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
                  setState(() => _textOverlays
                      .add(_TextOverlay(text: stickers[i], isSticker: true)));
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
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 16,
          right: 16,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Add text…',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  setState(() => _textOverlays.add(
                        _TextOverlay(text: ctrl.text.trim()),
                      ));
                }
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111111),
      builder: (_) => SizedBox(
        height: 160,
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
                      setState(() => _currentFilter = i.toDouble());
                      Navigator.pop(context);
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
          ],
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
              child: GestureDetector(
                onTap: _isVideo ? _togglePlayPause : null,
                child: Container(
                  color: Colors.black,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Media
                      if (widget.thumbnailBytes != null)
                        Positioned.fill(
                          child: ColorFiltered(
                            colorFilter: ColorFilter.matrix(
                              _brightnessMatrix(_brightness),
                            ),
                            child: Image.memory(
                              widget.thumbnailBytes!,
                              fit: _fit,
                            ),
                          ),
                        ),
                      // Video on top once ready
                      if (_isVideo && _videoReady)
                        Positioned.fill(
                          child: FittedBox(
                            fit: _fit,
                            child: SizedBox(
                              width: _videoCtrl!.value.size.width,
                              height: _videoCtrl!.value.size.height,
                              child: VideoPlayer(_videoCtrl!),
                            ),
                          ),
                        ),
                      // Play/pause icon
                      if (_isVideo && !_playing)
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 48),
                        ),
                      // Text / sticker overlays
                      for (int i = 0; i < _textOverlays.length; i++)
                        Positioned(
                          top: 80.0 + i * 60,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onLongPress: () =>
                                  setState(() => _textOverlays.removeAt(i)),
                              child: _textOverlays[i].isSticker
                                  ? Text(_textOverlays[i].text,
                                      style: const TextStyle(fontSize: 48))
                                  : Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(_textOverlays[i].text,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight:
                                                  FontWeight.w700)),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
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
                    onPressed: widget.onNext,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0095F6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 28, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text(
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

class _TextOverlay {
  final String text;
  final bool isSticker;
  _TextOverlay({required this.text, this.isSticker = false});
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
  const _AudioPickerSheet();

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

  // Fallback tracks shown instantly while API loads
  static final _fallbackForYou = [
    _AudioTrack(id: 'f1', title: 'Blinding Lights', artist: 'The Weeknd', album: 'After Hours', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/1f/2f/33/1f2f3327-83a5-a6d7-43c7-c7b5c2e83bfe/20UMGIM38660.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/bb/94/fc/bb94fc7a-7b6d-9e15-a0bf-87c3e2bdcfa7/mzaf_15502931167594576430.plus.aac.p.m4a', durationMs: 200040),
    _AudioTrack(id: 'f2', title: 'As It Was', artist: 'Harry Styles', album: 'Harry\'s House', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/23/ed/0e/23ed0e4d-4a6e-3ba2-a1e1-b98079dc0af6/886449990061.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview122/v4/ea/97/44/ea9744da-7f5c-6b93-c79f-2c4e35ee4e0e/mzaf_12373444088091449813.plus.aac.p.m4a', durationMs: 167303),
    _AudioTrack(id: 'f3', title: 'Flowers', artist: 'Miley Cyrus', album: 'Endless Summer Vacation', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/68/2e/c2/682ec261-de8d-8f76-f3b7-a24ab2b0e36c/196589525406.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/7a/20/ab/7a20ab4d-b5c0-cead-c8e8-d2fbba1f16ec/mzaf_14756451590905478680.plus.aac.p.m4a', durationMs: 200626),
    _AudioTrack(id: 'f4', title: 'Anti-Hero', artist: 'Taylor Swift', album: 'Midnights', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music122/v4/bc/93/8a/bc938a66-e540-b337-2c6e-0df37d2e02de/22UMGIM92929.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview112/v4/56/72/80/567280b0-b7d9-84ed-6a0c-ae6dcca7a0ca/mzaf_1152296432419474017.plus.aac.p.m4a', durationMs: 200690),
    _AudioTrack(id: 'f5', title: 'Cruel Summer', artist: 'Taylor Swift', album: 'Lover', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/fc/f4/82/fcf48261-b458-a376-ea49-0de9e4fc5df2/19UMGIM61052.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/92/e6/50/92e65050-5fa9-49bb-eecc-b54c7ee0f36f/mzaf_14836984832580789527.plus.aac.p.m4a', durationMs: 178426),
    _AudioTrack(id: 'f6', title: 'Levitating', artist: 'Dua Lipa', album: 'Future Nostalgia', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/56/f1/19/56f1195a-b3be-21dc-ab26-ee48c7ad6ef0/20UMGIM11766.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/7b/ba/39/7bba3940-1c39-cc19-b07b-d0be5e93bd1a/mzaf_16700673813977649.plus.aac.p.m4a', durationMs: 203062),
    _AudioTrack(id: 'f7', title: 'Essence', artist: 'Wizkid ft. Tems', album: 'Made in Lagos', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/7a/91/f6/7a91f614-5a8b-e8c8-afbf-9a2b4f6f95a1/20UMGIM68696.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/2e/e4/e9/2ee4e9a3-3900-a7df-86d1-43e434c75e51/mzaf_9203703024226428498.plus.aac.p.m4a', durationMs: 255735),
    _AudioTrack(id: 'f8', title: 'Lover', artist: 'Taylor Swift', album: 'Lover', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music123/v4/fc/f4/82/fcf48261-b458-a376-ea49-0de9e4fc5df2/19UMGIM61052.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/48/27/e5/4827e5fe-72f3-5a2e-9ab8-db4f2a11e7e8/mzaf_4961930380688994948.plus.aac.p.m4a', durationMs: 221306),
  ];

  static final _fallbackTrending = [
    _AudioTrack(id: 't1', title: 'Calm Down', artist: 'Rema & Selena Gomez', album: 'Rave & Roses Ultra', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/d3/f3/76/d3f376ef-da55-0dce-5cd7-e28cf4b31a59/22UMGIM47023.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview126/v4/16/02/e1/1602e177-dbe3-0f63-dfc5-d8e10f1c5fbe/mzaf_13310658065399988455.plus.aac.p.m4a', durationMs: 239000),
    _AudioTrack(id: 't2', title: 'Ojuelegba', artist: 'Wizkid', album: 'Sounds From The Other Side', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music60/v4/e5/0b/b6/e50bb6c2-7bce-0248-ad35-6e7e1f6fc71f/source/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/a2/d6/01/a2d601e4-3d1b-a2f6-3b8a-5f2f19cf7bce/mzaf_6869052893891484987.plus.aac.p.m4a', durationMs: 230000),
    _AudioTrack(id: 't3', title: 'STAY', artist: 'The Kid LAROI & Justin Bieber', album: 'F*CK LOVE 3', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/4c/19/98/4c1998a5-dae6-0bab-a9c4-7e3e1d4d51be/21UMGIM76543.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/57/3d/53/573d5301-cc06-6bdc-33c2-a4c52b17e9fc/mzaf_7723628696429765484.plus.aac.p.m4a', durationMs: 141000),
    _AudioTrack(id: 't4', title: 'Watermelon Sugar', artist: 'Harry Styles', album: 'Fine Line', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/d8/d3/06/d8d306de-a5ee-f023-e0ff-9da858b80b5b/19UMGIM100060.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/54/10/03/54100302-ae91-3f9b-8895-05e3b72e5a7d/mzaf_8619668882038234000.plus.aac.p.m4a', durationMs: 174000),
    _AudioTrack(id: 't5', title: 'good 4 u', artist: 'Olivia Rodrigo', album: 'SOUR', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music114/v4/ac/97/47/ac9747f9-c58d-f00f-2df2-6e7a785f2c15/21UMGIM23680.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/68/7b/e0/687be0e8-5e5c-20ec-f18e-a91d4a6d4018/mzaf_3834527660421049621.plus.aac.p.m4a', durationMs: 178000),
    _AudioTrack(id: 't6', title: 'Electric Touch', artist: 'Taylor Swift ft. Fall Out Boy', album: '1989 (Taylor\'s Version)', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/a4/f9/2e/a4f92ee2-2c74-4eac-1d2f-c19a2b4cf5d5/23UMGIM89215.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview116/v4/33/45/cd/3345cdd8-15de-7c9e-6680-18741484e558/mzaf_8748124516025989987.plus.aac.p.m4a', durationMs: 231000),
    _AudioTrack(id: 't7', title: 'Peaches', artist: 'Justin Bieber ft. Daniel Caesar', album: 'Justice', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/2a/30/3b/2a303b28-cf54-2ccd-6b7a-e8c9a087f66c/21UMGIM17219.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview115/v4/5b/1a/c0/5b1ac051-60f9-5001-49e0-adb9f62fd7ee/mzaf_5793527023052059023.plus.aac.p.m4a', durationMs: 198000),
    _AudioTrack(id: 't8', title: 'Heat Waves', artist: 'Glass Animals', album: 'Dreamland', artworkUrl: 'https://is1-ssl.mzstatic.com/image/thumb/Music124/v4/27/27/f5/2727f584-9064-93a8-af60-bb3cd2af1428/20UMGIM89513.rgb.jpg/300x300bb.jpg', previewUrl: 'https://audio-ssl.itunes.apple.com/itunes-assets/AudioPreview125/v4/35/23/b5/3523b559-d80e-b9b5-8ca7-1b6dc29f9571/mzaf_4034268754399019083.plus.aac.p.m4a', durationMs: 238000),
  ];

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
    // Pre-seed immediately with fallback
    if (mounted) setState(() { _forYou = List.from(_fallbackForYou); _loadingForYou = false; });
    // Then try to load from API and replace
    final tracks = await _itunesSearch('top hits pop', limit: 25);
    if (mounted && tracks.isNotEmpty) setState(() => _forYou = tracks);
  }

  Future<void> _fetchTrending() async {
    if (mounted) setState(() { _trending = List.from(_fallbackTrending); _loadingTrending = false; });
    final tracks = await _itunesSearch('trending afrobeats viral 2024', limit: 25);
    if (mounted && tracks.isNotEmpty) setState(() => _trending = tracks);
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
    required this.aiLabel,
    required this.onAiLabelChanged,
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
  final bool aiLabel;
  final ValueChanged<bool> onAiLabelChanged;
  final ValueChanged<String> onAudioLabelChanged;
  final VoidCallback onBack;
  final VoidCallback onSubmit;
  final Future<void> Function() onSaveDraft;

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
                      onTap: () {}),
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
              onTap: () {},
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
                    value: aiLabel,
                    onChanged: onAiLabelChanged,
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

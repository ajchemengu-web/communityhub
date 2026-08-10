import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/data/quran_surahs.dart';
import '../../data/quran_audio_repository.dart';

class QuranScreen extends StatefulWidget {
  const QuranScreen({super.key});

  @override
  State<QuranScreen> createState() => _QuranScreenState();
}

class _QuranScreenState extends State<QuranScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _search.dispose();
    super.dispose();
  }

  List<QuranSurah> _filtered(String type) {
    final all = quranSurahs.where((s) => s.type == type).toList();
    if (_query.isEmpty) return all;
    return all.where((s) {
      final q = _query.toLowerCase();
      return s.arabic.toLowerCase().contains(q) ||
          s.english.toLowerCase().contains(q) ||
          s.number.toString() == _query;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Row(
          children: [
            Icon(Icons.mosque_outlined, color: Color(0xFF4CAF50), size: 22),
            SizedBox(width: 8),
            Text('The Holy Quran',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search surahs…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF142038),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              TabBar(
                controller: _tab,
                tabs: const [
                  Tab(text: 'Meccan (86)'),
                  Tab(text: 'Medinan (28)'),
                ],
                labelColor: const Color(0xFF4CAF50),
                unselectedLabelColor: Colors.white38,
                indicatorColor: const Color(0xFF4CAF50),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _SurahList(surahs: _filtered('Meccan')),
          _SurahList(surahs: _filtered('Medinan')),
        ],
      ),
    );
  }
}

class _SurahList extends StatelessWidget {
  const _SurahList({required this.surahs});
  final List<QuranSurah> surahs;

  @override
  Widget build(BuildContext context) {
    if (surahs.isEmpty) {
      return const Center(
          child: Text('No surahs found',
              style: TextStyle(color: Colors.white38)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: surahs.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Color(0xFF142038), height: 1),
      itemBuilder: (_, i) {
        final surah = surahs[i];
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${surah.number}',
                style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(surah.arabic,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              Text(
                surah.arabic, // Arabic name rendered right-to-left
                style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 16,
                    fontFamily: 'Amiri'),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
          subtitle: Text(
            '${surah.english}  ·  ${surah.verses} verses  ·  ${surah.type}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _SurahDetailScreen(surah: surah),
            ),
          ),
        );
      },
    );
  }
}

/// Which audio track is currently loaded in the surah detail player.
enum _QuranAudioSegment { arabic, swahili }

class _SurahDetailScreen extends StatefulWidget {
  const _SurahDetailScreen({required this.surah});
  final QuranSurah surah;

  @override
  State<_SurahDetailScreen> createState() => _SurahDetailScreenState();
}

class _SurahDetailScreenState extends State<_SurahDetailScreen> {
  // Each entry: { arabic: String, translation: String, number: int }
  List<Map<String, String>> _ayahs = [];
  bool _loading = true;
  String? _error;

  // --- Audio (Arabic recitation + Swahili translation narration) ---
  final _player = AudioPlayer();
  List<ReciterModel> _reciters = QuranAudioRepository.fallbackReciters;
  ReciterModel _reciter = QuranAudioRepository.fallbackReciters.first;
  _QuranAudioSegment? _segment;
  bool _sequential = true; // auto-advance Arabic -> Swahili
  PlayerState _playerState = PlayerState.stopped;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _audioBusy = false;
  String? _audioError;

  @override
  void initState() {
    super.initState();
    _fetch();
    _loadReciters();

    // Keep the native player "warm" between the recitation and translation
    // tracks instead of fully tearing it down on completion (the default
    // ReleaseMode.release). Releasing and immediately re-playing a new
    // source back-to-back — exactly what the auto Arabic-to-Kiswahili
    // chain does — races the platform player's teardown and throws, which
    // otherwise surfaces as a spurious "check your internet connection"
    // error even though the network is fine.
    _player.setReleaseMode(ReleaseMode.stop);

    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playerState = state);
    });
    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
    _player.onDurationChanged.listen((dur) {
      if (!mounted) return;
      setState(() => _duration = dur);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      if (_sequential && _segment == _QuranAudioSegment.arabic) {
        _playSegment(_QuranAudioSegment.swahili);
      } else {
        setState(() {
          _segment = null;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _loadReciters() async {
    final reciters = await QuranAudioRepository.instance.fetchReciters();
    if (!mounted) return;
    setState(() {
      _reciters = reciters;
      final match = reciters.where((r) => r.id == _reciter.id);
      _reciter = match.isNotEmpty ? match.first : reciters.first;
    });
  }

  Future<void> _fetch() async {
    setState(() { _loading = true; _error = null; });
    try {
      // alquran.cloud — free, no key required
      // editions: quran-uthmani (Arabic) + en.asad (English translation)
      final url =
          'https://api.alquran.cloud/v1/surah/${widget.surah.number}/editions/quran-uthmani,en.asad';
      final res = await Dio().get(url);
      final editions = (res.data['data'] as List<dynamic>);
      final arabicAyahs =
          (editions[0]['ayahs'] as List<dynamic>).cast<Map<String, dynamic>>();
      final engAyahs =
          (editions[1]['ayahs'] as List<dynamic>).cast<Map<String, dynamic>>();

      final ayahs = List.generate(arabicAyahs.length, (i) {
        return {
          'number': '${arabicAyahs[i]['numberInSurah']}',
          'arabic': arabicAyahs[i]['text'] as String? ?? '',
          'translation': engAyahs[i]['text'] as String? ?? '',
        };
      });
      setState(() { _ayahs = ayahs; _loading = false; });
    } catch (e) {
      setState(() {
        _error = 'Could not load verses. Check your internet connection.';
        _loading = false;
      });
    }
  }

  Future<void> _playSegment(_QuranAudioSegment segment) async {
    final url = segment == _QuranAudioSegment.arabic
        ? QuranAudioRepository.instance
            .arabicSurahAudioUrl(_reciter, widget.surah.number)
        : QuranAudioRepository.instance
            .swahiliTranslationAudioUrl(widget.surah.number);
    setState(() {
      _segment = segment;
      _audioBusy = true;
      _audioError = null;
      _position = Duration.zero;
      _duration = Duration.zero;
    });
    try {
      // Defensively stop any in-flight/just-completed playback before
      // starting the next track — switching sources on a still-settling
      // player is what triggers the auto-chain failure (see initState).
      try {
        await _player.stop();
      } catch (_) {
        // Nothing was playing — fine to ignore.
      }
      await _player.play(UrlSource(url));
    } catch (e) {
      debugPrint('Quran audio playback error ($segment, surah ${widget.surah.number}): $e');
      if (!mounted) return;
      setState(() {
        _audioError = 'Could not play audio. Check your internet connection.';
      });
    } finally {
      if (mounted) setState(() => _audioBusy = false);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_segment == null) {
      await _playSegment(_QuranAudioSegment.arabic);
      return;
    }
    if (_playerState == PlayerState.playing) {
      await _player.pause();
    } else {
      await _player.resume();
    }
  }

  Future<void> _stopAudio() async {
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _segment = null;
      _position = Duration.zero;
    });
  }

  void _pickReciter() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F2040),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Choose reciter',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            ..._reciters.map((r) {
              return ListTile(
                title:
                    Text(r.name, style: const TextStyle(color: Colors.white)),
                trailing: r.id == _reciter.id
                    ? const Icon(Icons.check, color: Color(0xFF4CAF50))
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  final wasPlayingArabic = _segment == _QuranAudioSegment.arabic;
                  setState(() => _reciter = r);
                  if (wasPlayingArabic) {
                    _playSegment(_QuranAudioSegment.arabic);
                  }
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  /// Single entry point: always plays the Arabic recitation first, then
  /// (per [_sequential], which stays on) auto-continues straight into the
  /// Kiswahili translation of the same surah — one continuous playback
  /// rather than two separate tracks the user has to start by hand.
  Widget _buildAudioQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _playSegment(_QuranAudioSegment.arabic),
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: const Text('Play Recitation + Kiswahili'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: _pickReciter,
            icon: const Icon(Icons.person_outline, color: Colors.white38),
            tooltip: 'Choose reciter',
          ),
        ],
      ),
    );
  }

  Widget _buildAudioPlayerBar() {
    final isArabic = _segment == _QuranAudioSegment.arabic;
    final label =
        isArabic ? '${_reciter.name} · Recitation' : 'Kiswahili Translation';
    final totalMs = _duration.inMilliseconds > 0 ? _duration.inMilliseconds : 1;
    final posMs = _position.inMilliseconds.clamp(0, totalMs);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: const BoxDecoration(
        color: Color(0xFF0F2040),
        border: Border(top: BorderSide(color: Color(0xFF1A6B4A), width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_audioError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(_audioError!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 11)),
              ),
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('${_fmt(_position)} / ${_fmt(_duration)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: posMs.toDouble(),
                max: totalMs.toDouble(),
                activeColor: const Color(0xFF4CAF50),
                inactiveColor: Colors.white12,
                onChanged: (v) =>
                    _player.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _playSegment(_QuranAudioSegment.arabic),
                  icon: Icon(Icons.mic,
                      color:
                          isArabic ? const Color(0xFF4CAF50) : Colors.white38),
                  tooltip: 'Jump to Arabic recitation',
                ),
                IconButton(
                  iconSize: 40,
                  onPressed: _audioBusy ? null : _togglePlayPause,
                  icon: _audioBusy
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Color(0xFF4CAF50)),
                        )
                      : Icon(
                          _playerState == PlayerState.playing
                              ? Icons.pause_circle_filled
                              : Icons.play_circle_filled,
                          color: const Color(0xFF4CAF50)),
                ),
                IconButton(
                  onPressed: _stopAudio,
                  icon: const Icon(Icons.stop_circle_outlined,
                      color: Colors.white38),
                  tooltip: 'Stop',
                ),
                IconButton(
                  onPressed: () => _playSegment(_QuranAudioSegment.swahili),
                  icon: Icon(Icons.translate,
                      color:
                          !isArabic ? const Color(0xFF4CAF50) : Colors.white38),
                  tooltip: 'Jump to Kiswahili translation',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                isArabic
                    ? 'Kiswahili translation plays automatically next'
                    : 'Playing Kiswahili translation',
                style: const TextStyle(
                    color: Color(0xFF4CAF50),
                    fontSize: 10,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                QuranAudioRepository.swahiliTranslationLicenseNote,
                style: TextStyle(color: Colors.white24, fontSize: 9),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surah = widget.surah;
    return Scaffold(
      backgroundColor: const Color(0xFF0A1628),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1628),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(surah.arabic,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            Text(surah.english,
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54),
              onPressed: _fetch,
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF4CAF50)))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.wifi_off_rounded,
                            color: Colors.white38, size: 48),
                        const SizedBox(height: 16),
                        Text(_error!,
                            style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                                height: 1.6),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _fetch,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50)),
                          child: const Text('Retry',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              : CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _SurahHeader(surah: surah),
                    ),
                    SliverToBoxAdapter(
                      child: _buildAudioQuickActions(),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (_, i) {
                            final a = _ayahs[i];
                            final num = a['number']!;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 16),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F2040),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: const Color(0xFF1A6B4A)
                                        .withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  // Verse number badge
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1A6B4A),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          '${surah.number}:$num',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  // Arabic text
                                  Text(
                                    a['arabic']!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontFamily: 'Amiri',
                                      height: 2.0,
                                    ),
                                    textDirection: TextDirection.rtl,
                                    textAlign: TextAlign.right,
                                  ),
                                  const SizedBox(height: 10),
                                  const Divider(color: Color(0xFF1A6B4A)),
                                  const SizedBox(height: 8),
                                  // English translation
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      a['translation']!,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        height: 1.6,
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                          childCount: _ayahs.length,
                        ),
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _segment == null ? null : _buildAudioPlayerBar(),
    );
  }
}

class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.surah});
  final QuranSurah surah;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A6B4A), Color(0xFF0A3D2A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Text(
            surah.arabic,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                fontFamily: 'Amiri'),
            textDirection: TextDirection.rtl,
          ),
          const SizedBox(height: 4),
          Text(surah.english,
              style: const TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(label: 'Surah', value: '${surah.number}'),
              _StatChip(label: 'Verses', value: '${surah.verses}'),
              _StatChip(label: 'Type', value: surah.type),
            ],
          ),
          if (surah.number != 9) ...[
            const SizedBox(height: 16),
            const Text(
              'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontFamily: 'Amiri', height: 2),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
            ),
            const Text(
              'In the name of Allah, the Entirely Merciful, the Especially Merciful',
              style: TextStyle(color: Colors.white54, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}

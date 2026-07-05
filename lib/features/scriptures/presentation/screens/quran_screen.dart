import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/data/quran_surahs.dart';

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

  @override
  void initState() {
    super.initState();
    _fetch();
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

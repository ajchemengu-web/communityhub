import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../core/data/bible_books.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({super.key});

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen>
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

  List<BibleBook> _filtered(String testament) {
    final all = bibleBooks.where((b) => b.testament == testament).toList();
    if (_query.isEmpty) return all;
    return all
        .where((b) => b.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: const Row(
          children: [
            Icon(Icons.menu_book_rounded, color: Color(0xFFD4A847), size: 22),
            SizedBox(width: 8),
            Text('The Holy Bible',
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
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search books…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF1C2230),
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
                  Tab(text: 'Old Testament (39)'),
                  Tab(text: 'New Testament (27)'),
                ],
                labelColor: const Color(0xFFD4A847),
                unselectedLabelColor: Colors.white38,
                indicatorColor: const Color(0xFFD4A847),
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _BookList(books: _filtered('Old Testament')),
          _BookList(books: _filtered('New Testament')),
        ],
      ),
    );
  }
}

class _BookList extends StatelessWidget {
  const _BookList({required this.books});
  final List<BibleBook> books;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) {
      return const Center(
          child: Text('No books found',
              style: TextStyle(color: Colors.white38)));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: books.length,
      separatorBuilder: (_, __) =>
          const Divider(color: Color(0xFF1C2230), height: 1),
      itemBuilder: (_, i) {
        final book = books[i];
        final index =
            bibleBooks.indexOf(book) + 1; // canonical book number
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1C2230),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '$index',
                style: const TextStyle(
                    color: Color(0xFFD4A847),
                    fontWeight: FontWeight.w700,
                    fontSize: 13),
              ),
            ),
          ),
          title: Text(book.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500)),
          subtitle: Text('${book.chapters} chapters',
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
          trailing: const Icon(Icons.chevron_right, color: Colors.white24),
          onTap: () => _openBook(context, book),
        );
      },
    );
  }

  void _openBook(BuildContext context, BibleBook book) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ChapterListScreen(book: book),
      ),
    );
  }
}

class _ChapterListScreen extends StatelessWidget {
  const _ChapterListScreen({required this.book});
  final BibleBook book;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(book.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            Text('${book.testament} · ${book.chapters} chapters',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1,
        ),
        itemCount: book.chapters,
        itemBuilder: (_, i) {
          final ch = i + 1;
          return GestureDetector(
            onTap: () => _openChapter(context, ch),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2230),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text('$ch',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openChapter(BuildContext context, int chapter) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _VerseScreen(book: book, chapter: chapter),
      ),
    );
  }
}

class _VerseScreen extends StatefulWidget {
  const _VerseScreen({required this.book, required this.chapter});
  final BibleBook book;
  final int chapter;

  @override
  State<_VerseScreen> createState() => _VerseScreenState();
}

class _VerseScreenState extends State<_VerseScreen> {
  List<Map<String, dynamic>> _verses = [];
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
      // bible-api.com — free, no key required
      final bookEncoded = Uri.encodeComponent(widget.book.name);
      final url =
          'https://bible-api.com/$bookEncoded+${widget.chapter}?translation=kjv';
      final res = await Dio().get(url);
      final verses =
          (res.data['verses'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      setState(() { _verses = verses; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Could not load verses. Check your internet connection.'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Text('${widget.book.name} ${widget.chapter}',
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white54),
              onPressed: _fetch,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4A847)))
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
                                color: Colors.white54, fontSize: 14, height: 1.6),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton(
                          onPressed: _fetch,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD4A847)),
                          child: const Text('Retry',
                              style: TextStyle(color: Colors.black)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: _verses.length,
                  itemBuilder: (_, i) {
                    final v = _verses[i];
                    final num = v['verse'] as int? ?? (i + 1);
                    final text = (v['text'] as String? ?? '').trim();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 32,
                            child: Text(
                              '$num',
                              style: const TextStyle(
                                  color: Color(0xFFD4A847),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              text,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  height: 1.7),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

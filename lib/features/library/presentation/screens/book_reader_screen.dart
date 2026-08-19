import 'package:flutter/material.dart';

import '../../data/book_repository.dart';
import '../../data/library_books.dart';
import '../../domain/models/book_model.dart';
import '../widgets/book_cover_art.dart';

/// Table-of-contents screen for a single library book: hero header,
/// front matter, then a Part-grouped chapter list. Tapping a chapter
/// opens the paginated reader (_ChapterReaderScreen).
class BookReaderScreen extends StatefulWidget {
  const BookReaderScreen({super.key, required this.meta});
  final LibraryBookMeta meta;

  @override
  State<BookReaderScreen> createState() => _BookReaderScreenState();
}

class _BookReaderScreenState extends State<BookReaderScreen> {
  BookContent? _book;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final book = await BookRepository.instance.fetchBook(widget.meta.storageFile);
      if (mounted) setState(() => _book = book);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not load this book. Check your internet connection.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: meta.bgColor,
            expandedHeight: 240,
            pinned: true,
            leading: const BackButton(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      meta.bgColor,
                      meta.accentColor.withValues(alpha: 0.18),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 44, 20, 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        BookCoverArt(
                            meta: meta,
                            width: 84,
                            borderRadius: 10,
                            showText: false),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(meta.title,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2)),
                              const SizedBox(height: 4),
                              Text(meta.subtitle,
                                  style: TextStyle(
                                      color: meta.accentColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 6),
                              Text('by ${meta.author}',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_error != null)
            SliverFillRemaining(
              child: Center(
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
                        onPressed: _load,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: meta.accentColor),
                        child: const Text('Retry',
                            style: TextStyle(color: Colors.black)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (_book == null)
            SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: meta.accentColor)),
            )
          else
            _TableOfContents(meta: meta, book: _book!),
        ],
      ),
    );
  }
}

class _TableOfContents extends StatelessWidget {
  const _TableOfContents({required this.meta, required this.book});
  final LibraryBookMeta meta;
  final BookContent book;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<int>>{};
    for (var i = 0; i < book.chapters.length; i++) {
      final part = book.chapters[i].part ?? '';
      groups.putIfAbsent(part, () => []).add(i);
    }

    return SliverList(
      delegate: SliverChildListDelegate([
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(meta.stats,
              style: const TextStyle(color: Colors.white38, fontSize: 12)),
        ),
        for (final entry in groups.entries) ...[
          if (entry.key.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(
                entry.key.toUpperCase(),
                style: TextStyle(
                    color: meta.accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1),
              ),
            ),
          ...entry.value.map((i) => _ChapterRow(
                meta: meta,
                book: book,
                index: i,
              )),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _ChapterRow extends StatelessWidget {
  const _ChapterRow({required this.meta, required this.book, required this.index});
  final LibraryBookMeta meta;
  final BookContent book;
  final int index;

  @override
  Widget build(BuildContext context) {
    final chapter = book.chapters[index];
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: meta.accentColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Text('${index + 1}',
              style: TextStyle(
                  color: meta.accentColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ),
      ),
      title: Text(chapter.title,
          style: const TextStyle(
              color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white24),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _ChapterReaderScreen(meta: meta, book: book, initialIndex: index),
        ),
      ),
    );
  }
}

/// The actual reading view: renders one chapter's blocks with reading
/// typography, and lets the reader page straight to the next/previous
/// chapter without returning to the table of contents.
class _ChapterReaderScreen extends StatefulWidget {
  const _ChapterReaderScreen({
    required this.meta,
    required this.book,
    required this.initialIndex,
  });

  final LibraryBookMeta meta;
  final BookContent book;
  final int initialIndex;

  @override
  State<_ChapterReaderScreen> createState() => _ChapterReaderScreenState();
}

class _ChapterReaderScreenState extends State<_ChapterReaderScreen> {
  late int _index;
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _goTo(int newIndex) {
    setState(() => _index = newIndex);
    _scrollCtrl.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    final chapters = widget.book.chapters;
    final chapter = chapters[_index];
    final hasPrev = _index > 0;
    final hasNext = _index < chapters.length - 1;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              chapter.part ?? meta.subtitle,
              style: TextStyle(
                  color: meta.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
            ),
            Text('Chapter ${_index + 1} of ${chapters.length}',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Text(chapter.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          height: 1.3)),
                  const SizedBox(height: 18),
                  ...chapter.blocks.map((b) => _BlockView(block: b, meta: meta)),
                ],
              ),
            ),
            _ChapterNavBar(
              meta: meta,
              hasPrev: hasPrev,
              hasNext: hasNext,
              onPrev: hasPrev ? () => _goTo(_index - 1) : null,
              onNext: hasNext ? () => _goTo(_index + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.meta});
  final BookBlock block;
  final LibraryBookMeta meta;

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case 'h3':
        return Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(block.text,
              style: TextStyle(
                  color: meta.accentColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.4)),
        );
      case 'h4':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(block.text,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.4)),
        );
      case 'bullet':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                      color: meta.accentColor, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(block.text,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15, height: 1.6)),
              ),
            ],
          ),
        );
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(block.text,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 15.5, height: 1.75)),
        );
    }
  }
}

class _ChapterNavBar extends StatelessWidget {
  const _ChapterNavBar({
    required this.meta,
    required this.hasPrev,
    required this.hasNext,
    required this.onPrev,
    required this.onNext,
  });

  final LibraryBookMeta meta;
  final bool hasPrev;
  final bool hasNext;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0A),
        border: Border(top: BorderSide(color: Color(0xFF1C2230))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onPrev,
              style: OutlinedButton.styleFrom(
                foregroundColor: hasPrev ? Colors.white70 : Colors.white24,
                side: BorderSide(
                    color: hasPrev ? const Color(0xFF30363D) : const Color(0xFF21262D)),
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
              label: const Text('Previous'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FilledButton.icon(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                backgroundColor: hasNext ? meta.accentColor : const Color(0xFF21262D),
                foregroundColor: hasNext ? Colors.black : Colors.white24,
              ),
              icon: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              label: const Text('Next'),
              iconAlignment: IconAlignment.end,
            ),
          ),
        ],
      ),
    );
  }
}

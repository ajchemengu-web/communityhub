import 'package:flutter/material.dart';

/// Decorative background motif for a book's generated cover art (see
/// BookCoverArt). New patterns can be added here as new book genres
/// join the library.
enum BookCoverPattern { circuit, matrix }

/// A book offered in the Communities screen's library section, next to
/// the Bible and Quran. Metadata only -- the actual content is fetched
/// on demand from the public 'books' Storage bucket (see
/// BookRepository), keeping the catalog cheap to list and the app
/// binary small.
///
/// To add a new book: extract it with the same pipeline used for the
/// four below (heading-aware docx -> chapters/blocks JSON), upload the
/// JSON to the public 'books' Storage bucket, then add one entry here.
/// No other code changes needed -- the tile, cover art, and reader all
/// drive off this catalog.
class LibraryBookMeta {
  const LibraryBookMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.author,
    required this.emoji,
    required this.heroIcon,
    required this.pattern,
    required this.bgColor,
    required this.accentColor,
    required this.stats,
    required this.storageFile,
  });

  final String id;
  final String title;
  final String subtitle;
  final String author;
  final String emoji;

  /// Large watermark icon drawn faintly behind the cover's title block.
  final IconData heroIcon;
  final BookCoverPattern pattern;
  final Color bgColor;
  final Color accentColor;
  final String stats;

  /// Filename within the public 'books' Storage bucket.
  final String storageFile;
}

const libraryBooks = [
  LibraryBookMeta(
    id: 'fullstack-1',
    title: 'The Tale of a Fullstack Developer',
    subtitle: 'Book 1 · Frontend Development',
    author: 'Anonymous',
    emoji: '🖥️',
    heroIcon: Icons.code_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF001A1A),
    accentColor: Color(0xFF26C6DA),
    stats: '5 Parts • 21 Chapters • HTML, CSS & JavaScript',
    storageFile: 'tale-fullstack-1-frontend.json',
  ),
  LibraryBookMeta(
    id: 'fullstack-2',
    title: 'The Tale of a Fullstack Developer',
    subtitle: 'Book 2 · Backend Development',
    author: 'Anonymous',
    emoji: '🗄️',
    heroIcon: Icons.dns_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF0A1A00),
    accentColor: Color(0xFF9CCC65),
    stats: '5 Parts • 22 Chapters • Node.js, APIs & Databases',
    storageFile: 'tale-fullstack-2-backend.json',
  ),
  LibraryBookMeta(
    id: 'fullstack-3',
    title: 'The Tale of a Fullstack Developer',
    subtitle: 'Book 3 · Frameworks',
    author: 'Anonymous',
    emoji: '⚛️',
    heroIcon: Icons.widgets_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF08131A),
    accentColor: Color(0xFF64B5F6),
    stats: '5 Parts • 21 Chapters • TypeScript, React & Express',
    storageFile: 'tale-fullstack-3-frameworks.json',
  ),
  LibraryBookMeta(
    id: 'ethical-hacking',
    title: 'The Dawn of a Hacker',
    subtitle: 'The Ethical Hacking Handbook',
    author: 'Anonymous',
    emoji: '🛡️',
    heroIcon: Icons.security_rounded,
    pattern: BookCoverPattern.matrix,
    bgColor: Color(0xFF1A0000),
    accentColor: Color(0xFFEF5350),
    stats: '10 Parts • 23 Chapters • Recon to Defense',
    storageFile: 'ethical-hacking-handbook.json',
  ),
  LibraryBookMeta(
    id: 'rf-dsp-telecom',
    title: 'RF, DSP & Telecommunications Engineering',
    subtitle: 'From First Principles to Software-Defined Radio',
    author: 'Anonymous',
    emoji: '📡',
    heroIcon: Icons.cell_tower_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF0F0A1A),
    accentColor: Color(0xFFB388FF),
    stats: '17 Parts • 94 Chapters • 15 Hands-On Projects',
    storageFile: 'rf-dsp-telecom-engineering.json',
  ),
  LibraryBookMeta(
    id: 'prog-python',
    title: 'Programming Manuals',
    subtitle: 'Book 2 · Python',
    author: 'Anonymous',
    emoji: '🐍',
    heroIcon: Icons.terminal_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF1A1400),
    accentColor: Color(0xFFFFCA28),
    stats: '14 Chapters • Beginner to Advanced',
    storageFile: 'programming-manuals-2-python.json',
  ),
  LibraryBookMeta(
    id: 'prog-cpp',
    title: 'Programming Manuals',
    subtitle: 'Book 3 · C++',
    author: 'Anonymous',
    emoji: '⚙️',
    heroIcon: Icons.memory_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF1A0012),
    accentColor: Color(0xFFEC407A),
    stats: '14 Chapters • Beginner to Advanced',
    storageFile: 'programming-manuals-3-cpp.json',
  ),
  LibraryBookMeta(
    id: 'prog-flutter',
    title: 'Programming Manuals',
    subtitle: 'Book 4 · Flutter',
    author: 'Anonymous',
    emoji: '💙',
    heroIcon: Icons.flutter_dash,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF001220),
    accentColor: Color(0xFF42A5F5),
    stats: '14 Chapters • Beginner to Advanced',
    storageFile: 'programming-manuals-4-flutter.json',
  ),
  LibraryBookMeta(
    id: 'ku-macro',
    title: 'KU Economics Revision Series',
    subtitle: 'Book 2 · Macroeconomics',
    author: 'Anonymous',
    emoji: '📊',
    heroIcon: Icons.account_balance_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF1A1000),
    accentColor: Color(0xFFFFA726),
    stats: '16 Chapters • 4 Parts • Exam Revision Guide',
    storageFile: 'ku-econ-macroeconomics.json',
  ),
  LibraryBookMeta(
    id: 'ku-math',
    title: 'KU Economics Revision Series',
    subtitle: 'Book 3 · Mathematics for Economists',
    author: 'Anonymous',
    emoji: '📐',
    heroIcon: Icons.functions_rounded,
    pattern: BookCoverPattern.circuit,
    bgColor: Color(0xFF120A1A),
    accentColor: Color(0xFF7E57C2),
    stats: '12 Chapters • 3 Parts • Exam Revision Guide',
    storageFile: 'ku-econ-mathematics.json',
  ),
];

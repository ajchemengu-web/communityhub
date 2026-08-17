/// A selectable Bible translation.
class BibleVersion {
  const BibleVersion({
    required this.id,
    required this.abbreviation,
    required this.name,
  });

  /// wldeh/bible-api version id (e.g. "en-kjv") — see [chapterUrl].
  final String id;

  /// Short label shown in the version picker, e.g. "KJV".
  final String abbreviation;

  final String name;

  /// wldeh/bible-api's book folder slug: lowercase, spaces removed
  /// (e.g. "Song of Solomon" -> "songofsolomon", "1 Corinthians" ->
  /// "1corinthians") — confirmed against the live repo's directory
  /// listing for every one of this app's 66 canonical books.
  static String bookSlug(String bookName) =>
      bookName.toLowerCase().replaceAll(' ', '');

  /// Free, no-API-key-required source (cdn.jsdelivr.net mirroring
  /// github.com/wldeh/bible-api) — the same provider for every version
  /// below, so they all share one fetch/parse codepath in
  /// bible_screen.dart.
  String chapterUrl(String bookName, int chapter) =>
      'https://cdn.jsdelivr.net/gh/wldeh/bible-api/bibles/$id/books/'
      '${bookSlug(bookName)}/chapters/$chapter.json';
}

/// Versions offered in the Bible screen's version picker.
///
/// The genuinely most-read English translations worldwide (NIV, ESV,
/// NLT) are commercially copyrighted by their publishers (Biblica,
/// Crossway, Tyndale) and require a paid/licensed API key — not
/// available through any free, no-signup source. WEB (World English
/// Bible) and BSB (Berean Study Bible) are the modern, freely-licensed
/// alternatives free Bible apps commonly use in their place; KJV was
/// already in the app. All three are confirmed to have real per-verse
/// content on the same free provider (see BibleVersion.chapterUrl).
///
/// A Kiswahili version is intentionally NOT listed yet: the correct,
/// openly-licensed translation (Biblica's "Open Kiswahili Contemporary
/// Version") was identified, but no free, no-signup, live API serving
/// its actual verse content could be found/verified — see the
/// conversation this was added in for the full research trail. Wiring
/// it in needs either a working content source or a developer API key
/// the user obtains themselves (e.g. api.bible).
const bibleVersions = [
  BibleVersion(id: 'en-kjv', abbreviation: 'KJV', name: 'King James Version'),
  BibleVersion(id: 'en-web', abbreviation: 'WEB', name: 'World English Bible'),
  BibleVersion(id: 'en-bsb', abbreviation: 'BSB', name: 'Berean Study Bible'),
];

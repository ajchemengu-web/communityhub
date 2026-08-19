/// A single content block within a book chapter -- mirrors the
/// extraction pipeline's JSON shape (see the books storage bucket).
class BookBlock {
  const BookBlock({required this.type, required this.text});

  /// 'h3' | 'h4' | 'bullet' | 'p'
  final String type;
  final String text;

  factory BookBlock.fromMap(Map<String, dynamic> map) => BookBlock(
        type: map['type'] as String? ?? 'p',
        text: map['text'] as String? ?? '',
      );
}

class BookChapter {
  const BookChapter({required this.title, this.part, this.blocks = const []});

  final String title;

  /// The book's Part/Section this chapter belongs to, if any (used to
  /// group the table of contents).
  final String? part;
  final List<BookBlock> blocks;

  factory BookChapter.fromMap(Map<String, dynamic> map) => BookChapter(
        title: map['title'] as String? ?? 'Untitled',
        part: map['part'] as String?,
        blocks: (map['blocks'] as List<dynamic>? ?? [])
            .map((b) => BookBlock.fromMap(Map<String, dynamic>.from(b as Map)))
            .toList(),
      );
}

class BookContent {
  const BookContent({
    required this.title,
    this.author,
    this.frontMatter = '',
    this.chapters = const [],
  });

  final String title;
  final String? author;
  final String frontMatter;
  final List<BookChapter> chapters;

  factory BookContent.fromMap(Map<String, dynamic> map) => BookContent(
        title: map['title'] as String? ?? 'Untitled',
        author: map['author'] as String?,
        frontMatter: map['front_matter'] as String? ?? '',
        chapters: (map['chapters'] as List<dynamic>? ?? [])
            .map((c) => BookChapter.fromMap(Map<String, dynamic>.from(c as Map)))
            .toList(),
      );
}

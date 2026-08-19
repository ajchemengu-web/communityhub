import 'package:dio/dio.dart';

import '../../../core/services/supabase_service.dart';
import '../domain/models/book_model.dart';

/// Fetches book content from the public 'books' Storage bucket. Each
/// book is one JSON file (title/author/front matter/chapters) -- small
/// enough (a few hundred KB) to fetch whole and cache in memory rather
/// than chunk per-chapter like the Bible/Quran screens do.
class BookRepository {
  BookRepository._();
  static final instance = BookRepository._();

  final Map<String, BookContent> _cache = {};
  final _dio = Dio();

  Future<BookContent> fetchBook(String storageFile) async {
    final cached = _cache[storageFile];
    if (cached != null) return cached;

    final url = SupabaseService.client.storage.from('books').getPublicUrl(storageFile);
    final res = await _dio.get(url);
    final content = BookContent.fromMap(Map<String, dynamic>.from(res.data as Map));
    _cache[storageFile] = content;
    return content;
  }
}

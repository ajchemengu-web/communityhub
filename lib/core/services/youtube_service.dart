import 'package:dio/dio.dart';
import '../constants/app_constants.dart';

/// YouTube Data API v3 service.
/// All requests are filtered through content keywords to ensure
/// only faith or tech content enters the app.
class YouTubeService {
  YouTubeService._() {
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.youtubeBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ));
  }

  static final YouTubeService _instance = YouTubeService._();
  static YouTubeService get instance => _instance;

  late final Dio _dio;
  String _apiKey = ''; // Set via setApiKey()

  void setApiKey(String key) => _apiKey = key;

  // ── Search Videos ─────────────────────────────────────────
  Future<List<YouTubeVideo>> searchVideos({
    required String query,
    String type = 'video', // video | playlist | channel
    int maxResults = AppConstants.youtubeMaxResults,
    String? pageToken,
    String order = 'relevance', // relevance | date | viewCount | rating
    String? videoCategoryId,
  }) async {
    try {
      final response = await _dio.get('/search', queryParameters: {
        'part': 'snippet',
        'q': query,
        'type': type,
        'maxResults': maxResults,
        'order': order,
        'safeSearch': 'strict',
        if (pageToken != null) 'pageToken': pageToken,
        if (videoCategoryId != null) 'videoCategoryId': videoCategoryId,
        'key': _apiKey,
      });

      final items = response.data['items'] as List? ?? [];
      return items
          .map((item) => YouTubeVideo.fromSearchResult(item))
          .toList();
    } on DioException catch (e) {
      throw YouTubeException(e.message ?? 'YouTube API error', e.response?.statusCode);
    }
  }

  // ── Get Video Details ─────────────────────────────────────
  Future<List<YouTubeVideo>> getVideoDetails(List<String> videoIds) async {
    try {
      final response = await _dio.get('/videos', queryParameters: {
        'part': 'snippet,statistics,contentDetails',
        'id': videoIds.join(','),
        'key': _apiKey,
      });

      final items = response.data['items'] as List? ?? [];
      return items.map((item) => YouTubeVideo.fromVideoDetails(item)).toList();
    } on DioException catch (e) {
      throw YouTubeException(e.message ?? 'YouTube API error', e.response?.statusCode);
    }
  }

  // ── Faith Hub Feed ────────────────────────────────────────
  Future<List<YouTubeVideo>> getFaithFeed({
    int maxResults = AppConstants.youtubeMaxResults,
    String? pageToken,
  }) async {
    final query = AppConstants.faithKeywords.take(3).join(' OR ');
    return searchVideos(
      query: query,
      maxResults: maxResults,
      pageToken: pageToken,
      order: 'relevance',
    );
  }

  // ── Career Hub Feed ───────────────────────────────────────
  Future<List<YouTubeVideo>> getCareerFeed({
    int maxResults = AppConstants.youtubeMaxResults,
    String? pageToken,
  }) async {
    final query = AppConstants.techKeywords.take(3).join(' OR ');
    return searchVideos(
      query: query,
      maxResults: maxResults,
      pageToken: pageToken,
      order: 'relevance',
    );
  }

  // ── Channel Videos ────────────────────────────────────────
  Future<List<YouTubeVideo>> getChannelVideos({
    required String channelId,
    int maxResults = AppConstants.youtubeMaxResults,
    String? pageToken,
  }) async {
    return searchVideos(
      query: '',
      maxResults: maxResults,
      pageToken: pageToken,
    );
  }

  // ── AI Content Filter ─────────────────────────────────────
  /// Returns true if the video title/description passes content filter.
  bool passesContentFilter(YouTubeVideo video, String hubType) {
    final text = '${video.title} ${video.description}'.toLowerCase();
    final keywords = hubType == AppConstants.hubFaith
        ? AppConstants.faithKeywords
        : AppConstants.techKeywords;

    // Block list — content that is never acceptable
    const blockList = [
      'adult', 'explicit', 'xxx', 'nude', 'nsfw',
      'gambling', 'occult', 'witchcraft', 'satanic',
    ];

    for (final blocked in blockList) {
      if (text.contains(blocked)) return false;
    }

    // Must contain at least one relevant keyword
    return keywords.any((kw) => text.contains(kw));
  }
}

// ── Models ────────────────────────────────────────────────────
class YouTubeVideo {
  final String id;
  final String title;
  final String description;
  final String channelId;
  final String channelTitle;
  final String thumbnailUrl;
  final DateTime publishedAt;
  final int? viewCount;
  final int? likeCount;
  final String? duration;

  const YouTubeVideo({
    required this.id,
    required this.title,
    required this.description,
    required this.channelId,
    required this.channelTitle,
    required this.thumbnailUrl,
    required this.publishedAt,
    this.viewCount,
    this.likeCount,
    this.duration,
  });

  factory YouTubeVideo.fromSearchResult(Map<String, dynamic> json) {
    final snippet = json['snippet'] as Map<String, dynamic>;
    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>;
    final thumb = (thumbnails['high'] ?? thumbnails['medium'] ?? thumbnails['default'])
        as Map<String, dynamic>;

    return YouTubeVideo(
      id: json['id']['videoId'] as String? ?? '',
      title: snippet['title'] as String? ?? '',
      description: snippet['description'] as String? ?? '',
      channelId: snippet['channelId'] as String? ?? '',
      channelTitle: snippet['channelTitle'] as String? ?? '',
      thumbnailUrl: thumb['url'] as String? ?? '',
      publishedAt: DateTime.tryParse(snippet['publishedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  factory YouTubeVideo.fromVideoDetails(Map<String, dynamic> json) {
    final snippet = json['snippet'] as Map<String, dynamic>;
    final stats = json['statistics'] as Map<String, dynamic>? ?? {};
    final content = json['contentDetails'] as Map<String, dynamic>? ?? {};
    final thumbnails = snippet['thumbnails'] as Map<String, dynamic>;
    final thumb = (thumbnails['maxres'] ?? thumbnails['high'] ?? thumbnails['medium'])
        as Map<String, dynamic>;

    return YouTubeVideo(
      id: json['id'] as String? ?? '',
      title: snippet['title'] as String? ?? '',
      description: snippet['description'] as String? ?? '',
      channelId: snippet['channelId'] as String? ?? '',
      channelTitle: snippet['channelTitle'] as String? ?? '',
      thumbnailUrl: thumb['url'] as String? ?? '',
      publishedAt: DateTime.tryParse(snippet['publishedAt'] as String? ?? '') ?? DateTime.now(),
      viewCount: int.tryParse(stats['viewCount'] as String? ?? ''),
      likeCount: int.tryParse(stats['likeCount'] as String? ?? ''),
      duration: content['duration'] as String?,
    );
  }

  Map<String, dynamic> toSupabaseRecord(String hubType) => {
    'youtube_id': id,
    'title': title,
    'description': description,
    'channel_id': channelId,
    'channel_title': channelTitle,
    'thumbnail_url': thumbnailUrl,
    'published_at': publishedAt.toIso8601String(),
    'view_count': viewCount,
    'like_count': likeCount,
    'duration': duration,
    'hub_type': hubType,
  };
}

class YouTubeException implements Exception {
  final String message;
  final int? statusCode;
  const YouTubeException(this.message, [this.statusCode]);
  @override
  String toString() => 'YouTubeException($statusCode): $message';
}

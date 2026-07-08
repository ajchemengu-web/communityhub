import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:v_video_compressor/v_video_compressor.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/block_service.dart';
import '../../../core/services/supabase_service.dart';
import '../domain/models/comment_model.dart';

/// Handles all Supabase interactions for post creation, comments, and
/// individual post fetches.
class PostRepository {
  PostRepository._();
  static final PostRepository instance = PostRepository._();

  final _db = SupabaseService.client;

  // ── Create Post ───────────────────────────────────────────

  /// Creates a new post. Uploads media files first, then inserts the row.
  /// [onUploadProgress] fires after each file finishes uploading with
  /// (completed, total) — the UI shows this as "Uploading N of M…" since
  /// Supabase Storage's binary upload doesn't expose byte-level progress.
  Future<String> createPost({
    required String caption,
    required String hubType,
    List<File> mediaFiles = const [],
    String mediaType = 'text',
    List<String> tags = const [],
    String? youtubeUrl,
    bool isAiGenerated = false,
    bool isReel = false,
    List<String> taggedUserIds = const [],
    String? audioTitle,
    String? audioArtist,
    String? audioPreviewUrl,
    void Function(int completed, int total)? onUploadProgress,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final List<String> mediaUrls = [];

    // 1. Upload media to Supabase storage
    for (var i = 0; i < mediaFiles.length; i++) {
      final file = mediaFiles[i];
      final ext = file.path.split('.').last.toLowerCase();
      final isVideo = ext == 'mp4' || ext == 'mov';
      final fileName = '${uid}_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
      final contentType = isVideo ? 'video/mp4' : 'image/jpeg';

      // Compress before upload — cuts upload size/time and data usage
      // significantly on slower connections.
      final uploadFile = isVideo ? await _compressVideo(file) : await _compressImage(file);
      final bytes = await uploadFile.readAsBytes();

      await _db.storage.from(AppConstants.bucketPostMedia).uploadBinary(
            'posts/$fileName',
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      mediaUrls.add(
        _db.storage.from(AppConstants.bucketPostMedia).getPublicUrl('posts/$fileName'),
      );
      onUploadProgress?.call(i + 1, mediaFiles.length);
    }

    // 2. Insert the post row — strip unknown columns automatically
    final postPayload = <String, dynamic>{
      'author_id': uid,
      'content': caption.trim(),
      'media_url': mediaUrls.isNotEmpty ? mediaUrls.first : null,
      'media_type': mediaType,
      'media_thumbnail': mediaUrls.isNotEmpty ? mediaUrls.first : null,
      'hub_type': hubType,
      'tags': tags,
      'youtube_url': youtubeUrl,
      'moderation_status': 'approved',
      'is_ai_generated': isAiGenerated,
      'is_reel': isReel,
      'audio_title': audioTitle,
      'audio_artist': audioArtist,
      'audio_preview_url': audioPreviewUrl,
    };
    final postOptional = [
      'hub_type', 'media_url', 'media_type', 'media_thumbnail',
      'tags', 'youtube_url', 'moderation_status', 'is_ai_generated',
      'is_reel', 'audio_title', 'audio_artist', 'audio_preview_url',
    ];
    Map<String, dynamic> row;
    while (true) {
      try {
        row = await _db.from('posts').insert(postPayload).select('id').single();
        break;
      } catch (e) {
        final msg = e.toString();
        final badKey = postOptional.firstWhere(
          (k) => msg.contains("'$k'") && postPayload.containsKey(k),
          orElse: () => '',
        );
        if (badKey.isEmpty) rethrow;
        postPayload.remove(badKey);
      }
    }

    final postId = row['id'] as String? ?? '';

    // 3. Tag people — best-effort, never blocks the post itself.
    if (postId.isNotEmpty && taggedUserIds.isNotEmpty) {
      try {
        await _db.from('post_tags').insert([
          for (final taggedId in taggedUserIds)
            {'post_id': postId, 'tagged_user_id': taggedId},
        ]);
      } catch (_) {}
    }

    return postId;
  }

  // ── Tagged people ──────────────────────────────────────────

  /// Fetches the users tagged on a post (for display on the post card).
  Future<List<Map<String, dynamic>>> fetchTaggedUsers(String postId) async {
    try {
      final rows = await _db
          .from('post_tags')
          .select('tagged_user_id, users(id, username, full_name, avatar_url)')
          .eq('post_id', postId);
      return (rows as List)
          .map((r) => Map<String, dynamic>.from(r['users'] as Map))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Searches users by username/full name for the "Tag people" picker.
  /// Excludes anyone in a block relationship with the current user, same
  /// as every other user-search surface in the app.
  Future<List<Map<String, dynamic>>> searchUsersForTagging(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final excluded = await BlockService.instance.fetchExcludedUserIds();
      var q = _db
          .from('users')
          .select('id, username, full_name, avatar_url')
          .or('username.ilike.%$query%,full_name.ilike.%$query%');
      if (excluded.isNotEmpty) {
        q = q.not('id', 'in', excluded);
      }
      final rows = await q.limit(20);
      return (rows as List).map((r) => Map<String, dynamic>.from(r)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Compresses an image before upload. Falls back to the original file
  /// if compression fails for any reason — this should never block a post.
  Future<File> _compressImage(File file) async {
    try {
      final dir = await getTemporaryDirectory();
      final targetPath =
          '${dir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: 80,
        minWidth: 1440,
        minHeight: 1440,
      );
      return result != null ? File(result.path) : file;
    } catch (_) {
      return file;
    }
  }

  /// Compresses a video before upload. Falls back to the original file
  /// if compression fails for any reason — this should never block a post.
  Future<File> _compressVideo(File file) async {
    try {
      final result = await VVideoCompressor().compressVideo(
        file.path,
        const VVideoCompressionConfig.medium(),
      );
      return result != null ? File(result.compressedFilePath) : file;
    } catch (_) {
      return file;
    }
  }

  // ── Fetch single post ──────────────────────────────────────

  Future<Map<String, dynamic>> fetchPost(String postId) async {
    final uid = SupabaseService.currentUserId;

    final row = await _db
        .from('posts')
        .select('*, users(username, full_name, avatar_url, is_verified)')
        .eq('id', postId)
        .single();

    // Check if liked
    bool isLiked = false;
    if (uid != null) {
      final likeRow = await _db
          .from('post_likes')
          .select('id')
          .eq('post_id', postId)
          .eq('user_id', uid)
          .maybeSingle();
      isLiked = likeRow != null;
    }

    return {
      ...Map<String, dynamic>.from(row),
      'is_liked': isLiked,
    };
  }

  // ── Comments ──────────────────────────────────────────────

  /// Fetches top-level comments (no parent) for a post, with first-level replies.
  Future<List<CommentModel>> fetchComments(String postId) async {
    final uid = SupabaseService.currentUserId;

    // Top-level comments
    final rows = await _db
        .from('comments')
        .select('*, users(username, full_name, avatar_url, is_verified)')
        .eq('post_id', postId)
        .isFilter('parent_comment_id', null)
        .order('created_at', ascending: true)
        .limit(100);

    final comments = (rows as List<dynamic>)
        .map((r) => CommentModel.fromMap(Map<String, dynamic>.from(r)))
        .toList();

    // Fetch liked comment IDs
    Set<String> likedIds = {};
    if (uid != null && comments.isNotEmpty) {
      final ids = comments.map((c) => c.id).toList();
      final liked = await _db
          .from('comment_likes')
          .select('comment_id')
          .eq('user_id', uid)
          .inFilter('comment_id', ids);
      likedIds = (liked as List).map((r) => r['comment_id'] as String).toSet();
    }

    // Fetch replies (second level)
    final commentIds = comments.map((c) => c.id).toList();
    List<CommentModel> allReplies = [];
    if (commentIds.isNotEmpty) {
      final replyRows = await _db
          .from('comments')
          .select('*, users(username, full_name, avatar_url, is_verified)')
          .eq('post_id', postId)
          .inFilter('parent_comment_id', commentIds)
          .order('created_at', ascending: true);

      allReplies = (replyRows as List<dynamic>)
          .map((r) => CommentModel.fromMap(Map<String, dynamic>.from(r)))
          .toList();
    }

    // Assign liked + replies
    return comments.map((c) {
      final replies =
          allReplies.where((r) => r.parentCommentId == c.id).toList();
      return c.copyWith(
        isLikedByCurrentUser: likedIds.contains(c.id),
        replies: replies,
      );
    }).toList();
  }

  /// Posts a new comment.
  Future<CommentModel> addComment({
    required String postId,
    required String content,
    String? parentCommentId,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final row = await _db.from('comments').insert({
      'post_id': postId,
      'user_id': uid,
      'content': content.trim(),
      'parent_comment_id': parentCommentId,
    }).select('*, users(username, full_name, avatar_url, is_verified)').single();

    return CommentModel.fromMap(Map<String, dynamic>.from(row));
  }

  /// Toggles a like on a comment.
  Future<int?> toggleCommentLike(
    String commentId, {
    required bool isCurrentlyLiked,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return null;

    try {
      if (isCurrentlyLiked) {
        await _db
            .from('comment_likes')
            .delete()
            .eq('comment_id', commentId)
            .eq('user_id', uid);
      } else {
        await _db.from('comment_likes').upsert({
          'comment_id': commentId,
          'user_id': uid,
        });
      }
      final row = await _db
          .from('comments')
          .select('likes_count')
          .eq('id', commentId)
          .single();
      return row['likes_count'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Deletes a comment (only the owner can delete).
  Future<void> deleteComment(String commentId) async {
    await _db.from('comments').delete().eq('id', commentId);
  }

  // ── Bookmark ──────────────────────────────────────────────

  Future<bool> toggleBookmark(String postId,
      {required bool isCurrentlyBookmarked}) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return isCurrentlyBookmarked;
    try {
      if (isCurrentlyBookmarked) {
        await _db
            .from('bookmarks')
            .delete()
            .eq('post_id', postId)
            .eq('user_id', uid);
        return false;
      } else {
        await _db
            .from('bookmarks')
            .upsert({'post_id': postId, 'user_id': uid});
        return true;
      }
    } catch (_) {
      return isCurrentlyBookmarked;
    }
  }
}

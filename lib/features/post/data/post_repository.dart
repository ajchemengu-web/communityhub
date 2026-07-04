import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

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
  Future<String> createPost({
    required String caption,
    required String hubType,
    List<File> mediaFiles = const [],
    String mediaType = 'text',
    List<String> tags = const [],
    String? youtubeUrl,
  }) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) throw Exception('Not authenticated');

    final List<String> mediaUrls = [];

    // 1. Upload media to Supabase storage
    for (final file in mediaFiles) {
      final ext = file.path.split('.').last.toLowerCase();
      final fileName = '${uid}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final bytes = await file.readAsBytes();
      final contentType = ext == 'mp4' || ext == 'mov' ? 'video/mp4' : 'image/jpeg';

      // Try known bucket name variants in order
      final bucketCandidates = ['post-media', 'post_media', 'posts', 'media'];
      String? uploadedUrl;

      for (final bucket in bucketCandidates) {
        try {
          await _db.storage.from(bucket).uploadBinary(
                'posts/$fileName',
                bytes,
                fileOptions: FileOptions(
                  contentType: contentType,
                  upsert: true,
                ),
              );
          uploadedUrl = _db.storage.from(bucket).getPublicUrl('posts/$fileName');
          break; // success — stop trying
        } catch (e) {
          if (e.toString().contains('Bucket not found') ||
              e.toString().contains('404')) {
            continue; // try next bucket name
          }
          rethrow; // different error — surface it
        }
      }

      if (uploadedUrl == null) {
        throw Exception(
          'Storage bucket not found. Please create a bucket named "post-media" '
          'in your Supabase project under Storage.',
        );
      }
      mediaUrls.add(uploadedUrl);
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
    };
    final postOptional = [
      'hub_type', 'media_url', 'media_type', 'media_thumbnail',
      'tags', 'youtube_url', 'moderation_status',
    ];
    Map<String, dynamic> row;
    while (true) {
      try {
        row = await _db.from('posts').insert(postPayload).select('id').single()
            as Map<String, dynamic>;
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

    return row['id'] as String? ?? '';
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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/post_repository.dart';

// ── New Post State ─────────────────────────────────────────────

enum NewPostStatus { idle, uploading, success, error }

/// A user selected in the "Tag people" picker.
class TaggedUser {
  const TaggedUser({
    required this.id,
    required this.username,
    this.fullName,
    this.avatarUrl,
  });
  final String id;
  final String username;
  final String? fullName;
  final String? avatarUrl;
}

class NewPostState {
  const NewPostState({
    this.status = NewPostStatus.idle,
    this.caption = '',
    this.hubType = AppConstants.hubAll,
    this.mediaFiles = const <PostMediaFile>[],
    this.mediaType = 'text',
    this.tags = const [],
    this.youtubeUrl,
    this.isAiGenerated = false,
    this.isReel = false,
    this.taggedUsers = const [],
    this.audioTitle,
    this.audioArtist,
    this.audioPreviewUrl,
    this.errorMessage,
    this.createdPostId,
    this.uploadedCount = 0,
    this.uploadTotal = 0,
  });

  final NewPostStatus status;
  final String caption;
  final String hubType;
  final List<PostMediaFile> mediaFiles;
  final String mediaType;
  final List<String> tags;
  final String? youtubeUrl;
  final bool isAiGenerated;
  final bool isReel;
  final List<TaggedUser> taggedUsers;
  final String? audioTitle;
  final String? audioArtist;
  final String? audioPreviewUrl;
  final String? errorMessage;
  final String? createdPostId;

  /// Files uploaded so far / total this post needs — shown as
  /// "Uploading N of M…" since Supabase Storage doesn't expose
  /// byte-level progress for a binary upload.
  final int uploadedCount;
  final int uploadTotal;

  bool get canPost =>
      caption.trim().isNotEmpty && status != NewPostStatus.uploading;

  NewPostState copyWith({
    NewPostStatus? status,
    String? caption,
    String? hubType,
    List<PostMediaFile>? mediaFiles,
    String? mediaType,
    List<String>? tags,
    String? youtubeUrl,
    bool? isAiGenerated,
    bool? isReel,
    List<TaggedUser>? taggedUsers,
    String? audioTitle,
    String? audioArtist,
    String? audioPreviewUrl,
    String? errorMessage,
    String? createdPostId,
    int? uploadedCount,
    int? uploadTotal,
  }) =>
      NewPostState(
        status: status ?? this.status,
        caption: caption ?? this.caption,
        hubType: hubType ?? this.hubType,
        mediaFiles: mediaFiles ?? this.mediaFiles,
        mediaType: mediaType ?? this.mediaType,
        tags: tags ?? this.tags,
        youtubeUrl: youtubeUrl ?? this.youtubeUrl,
        isAiGenerated: isAiGenerated ?? this.isAiGenerated,
        isReel: isReel ?? this.isReel,
        taggedUsers: taggedUsers ?? this.taggedUsers,
        audioTitle: audioTitle ?? this.audioTitle,
        audioArtist: audioArtist ?? this.audioArtist,
        audioPreviewUrl: audioPreviewUrl ?? this.audioPreviewUrl,
        errorMessage: errorMessage ?? this.errorMessage,
        createdPostId: createdPostId ?? this.createdPostId,
        uploadedCount: uploadedCount ?? this.uploadedCount,
        uploadTotal: uploadTotal ?? this.uploadTotal,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class NewPostNotifier extends StateNotifier<NewPostState> {
  NewPostNotifier() : super(const NewPostState());

  final _repo = PostRepository.instance;

  void setCaption(String v) => state = state.copyWith(caption: v);
  void setHub(String hub) => state = state.copyWith(hubType: hub);
  void setTextOnly() =>
      state = state.copyWith(mediaFiles: const <PostMediaFile>[], mediaType: 'text');
  void setYoutubeUrl(String? url) => state = state.copyWith(youtubeUrl: url);
  void setAiGenerated(bool v) => state = state.copyWith(isAiGenerated: v);
  void setReelMode(bool v) => state = state.copyWith(isReel: v);

  void setAudioTrack({
    required String title,
    required String artist,
    required String previewUrl,
  }) {
    state = state.copyWith(
      audioTitle: title,
      audioArtist: artist,
      audioPreviewUrl: previewUrl,
    );
  }

  /// Resets to "no attached track" — used when the user picks "Original
  /// Audio" in the picker. `copyWith`'s `?? this.field` pattern can't
  /// express clearing a value back to null, so this goes through a fresh
  /// state instead.
  void clearAudioTrack() {
    state = NewPostState(
      status: state.status,
      caption: state.caption,
      hubType: state.hubType,
      mediaFiles: state.mediaFiles,
      mediaType: state.mediaType,
      tags: state.tags,
      youtubeUrl: state.youtubeUrl,
      isAiGenerated: state.isAiGenerated,
      taggedUsers: state.taggedUsers,
      errorMessage: state.errorMessage,
      createdPostId: state.createdPostId,
      uploadedCount: state.uploadedCount,
      uploadTotal: state.uploadTotal,
    );
  }

  void addTaggedUser(TaggedUser user) {
    if (state.taggedUsers.any((u) => u.id == user.id)) return;
    state = state.copyWith(taggedUsers: [...state.taggedUsers, user]);
  }

  void removeTaggedUser(String userId) {
    state = state.copyWith(
      taggedUsers: state.taggedUsers.where((u) => u.id != userId).toList(),
    );
  }

  /// Restores the text portion of a saved draft (caption, hub, tags,
  /// YouTube link). Media is intentionally NOT restored — see
  /// [DraftRepository]'s class doc for why: a saved draft never carries
  /// bytes, only a `had_media` flag the picker screen can use to prompt
  /// "you had media attached — please re-select it".
  void loadFromDraft(Map<String, dynamic> draft) {
    state = state.copyWith(
      caption: draft['caption'] as String? ?? '',
      hubType: draft['hub_type'] as String? ?? AppConstants.hubAll,
      mediaType: draft['media_type'] as String? ?? 'text',
      tags: ((draft['tags'] as List?) ?? []).cast<String>(),
      youtubeUrl: draft['youtube_url'] as String?,
    );
  }

  void addMedia(List<PostMediaFile> files, String type) {
    final current = List<PostMediaFile>.from(state.mediaFiles);
    current.addAll(files);
    // Limit to 10 items
    state = state.copyWith(
      mediaFiles: current.take(10).toList(),
      mediaType: type,
    );
  }

  void removeMedia(int index) {
    final files = List<PostMediaFile>.from(state.mediaFiles)..removeAt(index);
    state = state.copyWith(
      mediaFiles: files,
      mediaType: files.isEmpty ? 'text' : state.mediaType,
    );
  }

  /// Swaps the first media file for an edited/composited version (baked-in
  /// filter, brightness, text/sticker overlays) produced by the Edit step.
  void replaceFirstMedia(PostMediaFile file) {
    if (state.mediaFiles.isEmpty) return;
    final files = List<PostMediaFile>.from(state.mediaFiles);
    files[0] = file;
    state = state.copyWith(mediaFiles: files);
  }

  void addTag(String tag) {
    if (tag.isEmpty || state.tags.contains(tag)) return;
    state = state.copyWith(tags: [...state.tags, tag]);
  }

  void removeTag(String tag) {
    state = state.copyWith(tags: state.tags.where((t) => t != tag).toList());
  }

  Future<void> submit() async {
    if (!state.canPost) return;

    state = state.copyWith(
      status: NewPostStatus.uploading,
      uploadedCount: 0,
      uploadTotal: state.mediaFiles.length,
    );

    try {
      final postId = await _repo.createPost(
        caption: state.caption,
        hubType: state.hubType,
        mediaFiles: state.mediaFiles,
        mediaType: state.mediaType,
        tags: state.tags,
        youtubeUrl: state.youtubeUrl,
        isAiGenerated: state.isAiGenerated,
        isReel: state.isReel,
        taggedUserIds: state.taggedUsers.map((u) => u.id).toList(),
        audioTitle: state.audioTitle,
        audioArtist: state.audioArtist,
        audioPreviewUrl: state.audioPreviewUrl,
        onUploadProgress: (completed, total) =>
            state = state.copyWith(uploadedCount: completed, uploadTotal: total),
      );

      state = state.copyWith(
        status: NewPostStatus.success,
        createdPostId: postId,
      );
    } catch (e) {
      state = state.copyWith(
        status: NewPostStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  void reset() => state = const NewPostState();
}

// ── Provider ───────────────────────────────────────────────────

final newPostProvider =
    StateNotifierProvider.autoDispose<NewPostNotifier, NewPostState>(
  (_) => NewPostNotifier(),
);

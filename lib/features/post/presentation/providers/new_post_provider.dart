import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../data/post_repository.dart';

// ── New Post State ─────────────────────────────────────────────

enum NewPostStatus { idle, uploading, success, error }

class NewPostState {
  const NewPostState({
    this.status = NewPostStatus.idle,
    this.caption = '',
    this.hubType = AppConstants.hubAll,
    this.mediaFiles = const [],
    this.mediaType = 'text',
    this.tags = const [],
    this.youtubeUrl,
    this.errorMessage,
    this.createdPostId,
  });

  final NewPostStatus status;
  final String caption;
  final String hubType;
  final List<File> mediaFiles;
  final String mediaType;
  final List<String> tags;
  final String? youtubeUrl;
  final String? errorMessage;
  final String? createdPostId;

  bool get canPost =>
      caption.trim().isNotEmpty && status != NewPostStatus.uploading;

  NewPostState copyWith({
    NewPostStatus? status,
    String? caption,
    String? hubType,
    List<File>? mediaFiles,
    String? mediaType,
    List<String>? tags,
    String? youtubeUrl,
    String? errorMessage,
    String? createdPostId,
  }) =>
      NewPostState(
        status: status ?? this.status,
        caption: caption ?? this.caption,
        hubType: hubType ?? this.hubType,
        mediaFiles: mediaFiles ?? this.mediaFiles,
        mediaType: mediaType ?? this.mediaType,
        tags: tags ?? this.tags,
        youtubeUrl: youtubeUrl ?? this.youtubeUrl,
        errorMessage: errorMessage ?? this.errorMessage,
        createdPostId: createdPostId ?? this.createdPostId,
      );
}

// ── Notifier ───────────────────────────────────────────────────

class NewPostNotifier extends StateNotifier<NewPostState> {
  NewPostNotifier() : super(const NewPostState());

  final _repo = PostRepository.instance;

  void setCaption(String v) => state = state.copyWith(caption: v);
  void setHub(String hub) => state = state.copyWith(hubType: hub);
  void setYoutubeUrl(String? url) => state = state.copyWith(youtubeUrl: url);

  void addMedia(List<File> files, String type) {
    final current = List<File>.from(state.mediaFiles);
    current.addAll(files);
    // Limit to 10 items
    state = state.copyWith(
      mediaFiles: current.take(10).toList(),
      mediaType: type,
    );
  }

  void removeMedia(int index) {
    final files = List<File>.from(state.mediaFiles)..removeAt(index);
    state = state.copyWith(
      mediaFiles: files,
      mediaType: files.isEmpty ? 'text' : state.mediaType,
    );
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

    state = state.copyWith(status: NewPostStatus.uploading);

    try {
      final postId = await _repo.createPost(
        caption: state.caption,
        hubType: state.hubType,
        mediaFiles: state.mediaFiles,
        mediaType: state.mediaType,
        tags: state.tags,
        youtubeUrl: state.youtubeUrl,
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

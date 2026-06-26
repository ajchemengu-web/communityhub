import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/communities_repository.dart';
import '../../domain/models/community_model.dart';

enum CreateCommunityStatus { idle, uploading, success, error }

class CreateCommunityState {
  const CreateCommunityState({
    this.name = '',
    this.description = '',
    this.hubType = 'faith',
    this.isPrivate = true,
    this.denomination = '',
    this.location = '',
    this.website = '',
    this.coverFile,
    this.status = CreateCommunityStatus.idle,
    this.errorMessage,
    this.created,
  });

  final String name;
  final String description;
  final String hubType;
  final bool isPrivate;
  final String denomination;
  final String location;
  final String website;
  final File? coverFile;
  final CreateCommunityStatus status;
  final String? errorMessage;
  final CommunityModel? created;

  bool get canSubmit =>
      name.trim().length >= 3 &&
      status != CreateCommunityStatus.uploading;

  CreateCommunityState copyWith({
    String? name,
    String? description,
    String? hubType,
    bool? isPrivate,
    String? denomination,
    String? location,
    String? website,
    File? coverFile,
    bool clearCover = false,
    CreateCommunityStatus? status,
    String? errorMessage,
    CommunityModel? created,
  }) =>
      CreateCommunityState(
        name: name ?? this.name,
        description: description ?? this.description,
        hubType: hubType ?? this.hubType,
        isPrivate: isPrivate ?? this.isPrivate,
        denomination: denomination ?? this.denomination,
        location: location ?? this.location,
        website: website ?? this.website,
        coverFile: clearCover ? null : (coverFile ?? this.coverFile),
        status: status ?? this.status,
        errorMessage: errorMessage ?? this.errorMessage,
        created: created ?? this.created,
      );
}

class CreateCommunityNotifier
    extends StateNotifier<CreateCommunityState> {
  CreateCommunityNotifier() : super(const CreateCommunityState());

  final _repo = CommunitiesRepository.instance;

  void setName(String v) => state = state.copyWith(name: v);
  void setDescription(String v) => state = state.copyWith(description: v);
  void setHubType(String v) => state = state.copyWith(hubType: v);
  void setPrivate(bool v) => state = state.copyWith(isPrivate: v);
  void setDenomination(String v) => state = state.copyWith(denomination: v);
  void setLocation(String v) => state = state.copyWith(location: v);
  void setWebsite(String v) => state = state.copyWith(website: v);
  void setCoverFile(File? f) =>
      state = f == null ? state.copyWith(clearCover: true) : state.copyWith(coverFile: f);

  Future<void> submit() async {
    if (!state.canSubmit) return;
    state = state.copyWith(status: CreateCommunityStatus.uploading);

    try {
      final community = await _repo.createCommunity(
        name: state.name,
        description: state.description,
        hubType: state.hubType,
        isPrivate: state.isPrivate,
        coverFile: state.coverFile,
        denomination: state.denomination.isEmpty ? null : state.denomination,
        location: state.location.isEmpty ? null : state.location,
        website: state.website.isEmpty ? null : state.website,
      );

      state = state.copyWith(
          status: CreateCommunityStatus.success, created: community);
    } catch (e) {
      state = state.copyWith(
          status: CreateCommunityStatus.error, errorMessage: e.toString());
    }
  }
}

final createCommunityProvider = StateNotifierProvider.autoDispose<
    CreateCommunityNotifier, CreateCommunityState>(
  (_) => CreateCommunityNotifier(),
);

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/profile_repository.dart';

// ── Enums ─────────────────────────────────────────────────────

enum UsernameStatus { idle, checking, available, taken, invalid }

enum SetupSubmitStatus { idle, uploading, saving, success, error }

// ── State ─────────────────────────────────────────────────────

class ProfileSetupState {
  const ProfileSetupState({
    this.currentStep = 0,
    // Step 1
    this.fullName = '',
    this.username = '',
    this.avatarBytes,
    this.avatarUrl = '',
    this.usernameStatus = UsernameStatus.idle,
    // Step 2
    this.religion = '',
    this.bio = '',
    this.hubPreference = 'all',
    this.churchName = '',
    this.website = '',
    // Submit
    this.submitStatus = SetupSubmitStatus.idle,
    this.errorMessage,
  });

  final int currentStep;

  // Step 1
  final String fullName;
  final String username;
  final Uint8List? avatarBytes;
  final String avatarUrl;
  final UsernameStatus usernameStatus;

  // Step 2
  final String religion; // 'christian' | 'muslim' | ''
  final String bio;
  final String hubPreference; // 'all' | 'faith' | 'career' | 'christianity' | 'islam'
  final String churchName;
  final String website;

  // Submit
  final SetupSubmitStatus submitStatus;
  final String? errorMessage;

  // ── Helpers ───────────────────────────────────────────────

  bool get isStep1Valid =>
      fullName.trim().length >= 2 &&
      username.trim().length >= 3 &&
      usernameStatus == UsernameStatus.available;

  bool get isStep2Valid => religion.isNotEmpty; // religion is required

  bool get isLoading =>
      submitStatus == SetupSubmitStatus.uploading ||
      submitStatus == SetupSubmitStatus.saving;

  ProfileSetupState copyWith({
    int? currentStep,
    String? fullName,
    String? username,
    Uint8List? avatarBytes,
    bool clearAvatar = false,
    String? avatarUrl,
    UsernameStatus? usernameStatus,
    String? religion,
    String? bio,
    String? hubPreference,
    String? churchName,
    String? website,
    SetupSubmitStatus? submitStatus,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ProfileSetupState(
      currentStep: currentStep ?? this.currentStep,
      fullName: fullName ?? this.fullName,
      username: username ?? this.username,
      avatarBytes: clearAvatar ? null : (avatarBytes ?? this.avatarBytes),
      avatarUrl: avatarUrl ?? this.avatarUrl,
      usernameStatus: usernameStatus ?? this.usernameStatus,
      religion: religion ?? this.religion,
      bio: bio ?? this.bio,
      hubPreference: hubPreference ?? this.hubPreference,
      churchName: churchName ?? this.churchName,
      website: website ?? this.website,
      submitStatus: submitStatus ?? this.submitStatus,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

// ── Notifier ──────────────────────────────────────────────────

class ProfileSetupNotifier extends StateNotifier<ProfileSetupState> {
  ProfileSetupNotifier() : super(const ProfileSetupState());

  final _repo = ProfileRepository.instance;

  // Debounce timer for username checks
  Timer? _usernameDebounce;

  // ── Navigation ─────────────────────────────────────────────

  void nextStep() {
    if (state.currentStep < 1) {
      state = state.copyWith(currentStep: state.currentStep + 1);
    }
  }

  void prevStep() {
    if (state.currentStep > 0) {
      state = state.copyWith(currentStep: state.currentStep - 1);
    }
  }

  // ── Step 1 ─────────────────────────────────────────────────

  void setFullName(String value) =>
      state = state.copyWith(fullName: value, clearError: true);

  void setAvatarBytes(Uint8List bytes) =>
      state = state.copyWith(avatarBytes: bytes);

  void clearAvatar() => state = state.copyWith(clearAvatar: true);

  void setUsername(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^a-z0-9_.]'), '');
    state = state.copyWith(
      username: cleaned,
      usernameStatus: UsernameStatus.idle,
      clearError: true,
    );

    _usernameDebounce?.cancel();

    if (cleaned.length < 3) {
      state = state.copyWith(
        usernameStatus: cleaned.isEmpty
            ? UsernameStatus.idle
            : UsernameStatus.invalid,
      );
      return;
    }

    state = state.copyWith(usernameStatus: UsernameStatus.checking);

    _usernameDebounce = Timer(const Duration(milliseconds: 600), () {
      _checkUsername(cleaned);
    });
  }

  Future<void> _checkUsername(String username) async {
    try {
      final available = await _repo.isUsernameAvailable(username);
      // Only update if the username hasn't changed while we were checking
      if (state.username == username) {
        state = state.copyWith(
          usernameStatus:
              available ? UsernameStatus.available : UsernameStatus.taken,
        );
      }
    } catch (_) {
      if (state.username == username) {
        state = state.copyWith(usernameStatus: UsernameStatus.idle);
      }
    }
  }

  // ── Step 2 ─────────────────────────────────────────────────

  void setReligion(String value) {
    // Auto-set hub preference to match religion
    final hub = value == 'christian' ? 'christianity' : value == 'muslim' ? 'islam' : 'all';
    state = state.copyWith(religion: value, hubPreference: hub, clearError: true);
  }

  void setBio(String value) => state = state.copyWith(bio: value);

  void setHubPreference(String value) =>
      state = state.copyWith(hubPreference: value);

  void setChurchName(String value) => state = state.copyWith(churchName: value);

  void setWebsite(String value) => state = state.copyWith(website: value);

  // ── Submit ─────────────────────────────────────────────────

  Future<void> submit() async {
    if (!state.isStep1Valid) return;

    try {
      // 1. Upload avatar if selected
      String avatarUrl = '';
      if (state.avatarBytes != null) {
        state = state.copyWith(submitStatus: SetupSubmitStatus.uploading);
        avatarUrl = await _repo.uploadAvatar(state.avatarBytes!);
      }

      // 2. Save profile row
      state = state.copyWith(
        submitStatus: SetupSubmitStatus.saving,
        avatarUrl: avatarUrl,
      );

      await _repo.createProfile(
        fullName: state.fullName,
        username: state.username,
        bio: state.bio,
        avatarUrl: avatarUrl,
        website: state.website,
        churchName: state.churchName,
        hubPreference: state.hubPreference,
        religion: state.religion,
      );

      state = state.copyWith(submitStatus: SetupSubmitStatus.success);
    } catch (e) {
      state = state.copyWith(
        submitStatus: SetupSubmitStatus.error,
        errorMessage: _friendlyError(e),
      );
    }
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('unique') || msg.contains('duplicate')) {
      return 'That username is already taken. Please choose another.';
    }
    if (msg.contains('network') || msg.contains('socket')) {
      return 'No internet connection. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────

final profileSetupProvider =
    StateNotifierProvider.autoDispose<ProfileSetupNotifier, ProfileSetupState>(
  (ref) => ProfileSetupNotifier(),
);

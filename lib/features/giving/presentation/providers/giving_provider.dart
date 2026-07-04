import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/giving_repository.dart';
import '../../domain/models/donation_model.dart';

// ── Giving history state ────────────────────────────────────────────

class GivingHistoryState {
  const GivingHistoryState({
    this.donations = const [],
    this.isLoading = true,
    this.errorMessage,
  });

  final List<DonationModel> donations;
  final bool isLoading;
  final String? errorMessage;

  double get totalGiven => donations
      .where((d) => d.isSucceeded)
      .fold(0.0, (sum, d) => sum + d.amount);

  GivingHistoryState copyWith({
    List<DonationModel>? donations,
    bool? isLoading,
    String? errorMessage,
  }) =>
      GivingHistoryState(
        donations: donations ?? this.donations,
        isLoading: isLoading ?? this.isLoading,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ─────────────────────────────────────────────────────────

class GivingHistoryNotifier extends StateNotifier<GivingHistoryState> {
  GivingHistoryNotifier() : super(const GivingHistoryState()) {
    refresh();
  }

  final _repo = GivingRepository.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    try {
      final donations = await _repo.fetchMyDonations();
      state = state.copyWith(donations: donations, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final givingHistoryProvider =
    StateNotifierProvider.autoDispose<GivingHistoryNotifier, GivingHistoryState>(
  (_) => GivingHistoryNotifier(),
);

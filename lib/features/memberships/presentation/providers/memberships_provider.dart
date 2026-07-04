import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/memberships_repository.dart';
import '../../domain/models/membership_subscription_model.dart';

class MySubscriptionsState {
  const MySubscriptionsState({
    this.subscriptions = const [],
    this.isLoading = true,
  });

  final List<MembershipSubscriptionModel> subscriptions;
  final bool isLoading;

  MySubscriptionsState copyWith({
    List<MembershipSubscriptionModel>? subscriptions,
    bool? isLoading,
  }) =>
      MySubscriptionsState(
        subscriptions: subscriptions ?? this.subscriptions,
        isLoading: isLoading ?? this.isLoading,
      );
}

class MySubscriptionsNotifier extends StateNotifier<MySubscriptionsState> {
  MySubscriptionsNotifier() : super(const MySubscriptionsState()) {
    refresh();
  }

  final _repo = MembershipsRepository.instance;

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    final subscriptions = await _repo.fetchMySubscriptions();
    state = state.copyWith(subscriptions: subscriptions, isLoading: false);
  }
}

final mySubscriptionsProvider =
    StateNotifierProvider.autoDispose<MySubscriptionsNotifier, MySubscriptionsState>(
  (_) => MySubscriptionsNotifier(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';

// ── Auth State ────────────────────────────────────────────────
enum AuthStatus { initial, authenticated, unauthenticated, loading, error }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final User? user;
  final String? errorMessage;

  const AuthState.initial()
      : this(status: AuthStatus.initial);

  AuthState copyWith({
    AuthStatus? status,
    User? user,
    String? errorMessage,
  }) =>
      AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Auth Notifier ─────────────────────────────────────────────
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState.initial()) {
    _listenToAuthChanges();
  }

  void _listenToAuthChanges() {
    SupabaseService.authStateChanges.listen((authState) {
      if (authState.event == AuthChangeEvent.signedIn) {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: authState.session?.user,
        );
      } else if (authState.event == AuthChangeEvent.signedOut) {
        state = const AuthState(status: AuthStatus.unauthenticated);
      } else if (authState.event == AuthChangeEvent.tokenRefreshed) {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: authState.session?.user,
        );
      }
    });

    // Set initial state
    final currentUser = SupabaseService.currentUser;
    if (currentUser != null) {
      state = AuthState(
        status: AuthStatus.authenticated,
        user: currentUser,
      );
    } else {
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await SupabaseService.instance.signInWithGoogle();
      // Auth state listener will update state
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await SupabaseService.instance.signOut();
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

// ── Providers ─────────────────────────────────────────────────
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authNotifierProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authNotifierProvider).status == AuthStatus.authenticated;
});

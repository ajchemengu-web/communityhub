import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supa;

import '../../../../core/services/supabase_service.dart';
import '../../../../core/services/notification_service.dart';

// ── Auth State ────────────────────────────────────────────────
enum AuthStatus { initial, authenticated, unauthenticated, loading, error }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.errorMessage,
  });

  final AuthStatus status;
  final supa.User? user;
  final String? errorMessage;

  const AuthState.initial()
      : this(status: AuthStatus.initial);

  AuthState copyWith({
    AuthStatus? status,
    supa.User? user,
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

  StreamSubscription<supa.AuthState>? _authSubscription;

  void _listenToAuthChanges() {
    _authSubscription = SupabaseService.authStateChanges.listen((authState) {
      if (authState.event == supa.AuthChangeEvent.signedIn) {
        state = AuthState(
          status: AuthStatus.authenticated,
          user: authState.session?.user,
        );
        // Save FCM token now that we have a user ID
        NotificationService.instance.onLogin();
      } else if (authState.event == supa.AuthChangeEvent.signedOut) {
        state = const AuthState(status: AuthStatus.unauthenticated);
      } else if (authState.event == supa.AuthChangeEvent.tokenRefreshed) {
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
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Sign in with email + password directly.
  Future<void> signInWithEmailPassword(String email, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await SupabaseService.client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Sign in with username, phone, or email.
  /// For username/phone we first look up the associated email in the users table.
  Future<void> signInWithIdentifier(String identifier, String password) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final trimmed = identifier.trim();
      String email;

      if (_looksLikeEmail(trimmed)) {
        email = trimmed;
      } else {
        // Look up email by username or phone in the public users table
        email = await _lookupEmail(trimmed);
      }

      await SupabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Register a new account with email + password.
  /// Stores username and email in the public users table.
  Future<void> signUpWithEmail({
    required String email,
    required String password,
    required String username,
    String? fullName,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      final res = await SupabaseService.client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'username': username, 'full_name': fullName ?? username},
      );
      final uid = res.user?.id;
      if (uid != null) {
        // Persist username + email in public users table
        await SupabaseService.client.from('users').upsert({
          'id': uid,
          'username': username.trim(),
          'full_name': fullName ?? username,
          'email': email.trim(),
          'is_verified': false,
        });
      }
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  static bool _looksLikeEmail(String s) => s.contains('@');

  Future<String> _lookupEmail(String identifier) async {
    // Try username first, then phone
    final byUsername = await SupabaseService.client
        .from('users')
        .select('email')
        .eq('username', identifier)
        .maybeSingle();

    if (byUsername != null && byUsername['email'] != null) {
      return byUsername['email'] as String;
    }

    final normalized = identifier.startsWith('+') ? identifier : '+$identifier';
    final byPhone = await SupabaseService.client
        .from('users')
        .select('email')
        .eq('phone', normalized)
        .maybeSingle();

    if (byPhone != null && byPhone['email'] != null) {
      return byPhone['email'] as String;
    }

    throw Exception(
      'No account found for "$identifier". Please check your username or phone number.',
    );
  }

  /// Send OTP to phone number via Twilio Verify (Supabase phone auth)
  Future<void> signInWithPhone(String phone) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await SupabaseService.client.auth.signInWithOtp(phone: phone.trim());
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Verify OTP sent to phone
  Future<void> verifyPhoneOtp(String phone, String token) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await SupabaseService.client.auth.verifyOTP(
        phone: phone.trim(),
        token: token.trim(),
        type: supa.OtpType.sms,
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Sign up with phone number (sends OTP)
  Future<void> signUpWithPhone({
    required String phone,
    required String username,
    String? fullName,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);
    try {
      await SupabaseService.client.auth.signInWithOtp(
        phone: phone.trim(),
        data: {'username': username, 'full_name': fullName ?? username},
      );
    } catch (e) {
      state = state.copyWith(
        status: AuthStatus.error,
        errorMessage: e.toString(),
      );
      rethrow;
    }
  }

  /// Changes the current user's password. Supabase requires the user to
  /// already be signed in — no re-auth/current-password check is enforced
  /// here, matching Supabase Auth's own updateUser semantics.
  Future<void> changePassword(String newPassword) async {
    try {
      await SupabaseService.client.auth.updateUser(
        supa.UserAttributes(password: newPassword),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      rethrow;
    }
  }

  /// Starts an email change. Supabase sends a confirmation link to the
  /// new address (and, depending on project settings, to the old one
  /// too) — the email isn't updated until the user confirms it.
  Future<void> updateEmail(String newEmail) async {
    try {
      await SupabaseService.client.auth.updateUser(
        supa.UserAttributes(email: newEmail.trim()),
      );
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
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

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

// ── Providers ─────────────────────────────────────────────────
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<supa.User?>((ref) {
  return ref.watch(authNotifierProvider).user;
});

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(authNotifierProvider).status == AuthStatus.authenticated;
});

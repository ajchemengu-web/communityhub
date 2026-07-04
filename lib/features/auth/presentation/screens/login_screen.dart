import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/auth_provider.dart';
import 'otp_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;
  bool _showEmailForm = false;
  bool _showPhoneForm = false;

  final _formKey = GlobalKey<FormState>();
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    } catch (e) {
      _showError('Sign in failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    // Ensure international format
    final normalized = phone.startsWith('+') ? phone : '+$phone';
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithPhone(normalized);
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OtpScreen(phone: normalized),
          ),
        );
      }
    } catch (e) {
      _showError('Could not send code. Check the phone number and try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInWithCredentials() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithIdentifier(_identifierCtrl.text, _passwordCtrl.text);
    } catch (e) {
      _showError(_friendlyError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Invalid login credentials')) {
      return 'Incorrect password. Please try again.';
    }
    if (raw.contains('No account found')) return raw.replaceFirst('Exception: ', '');
    if (raw.contains('Email not confirmed')) {
      return 'Please verify your email before signing in.';
    }
    return 'Sign in failed. Please try again.';
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height -
                    MediaQuery.of(context).padding.top -
                    MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 60),

                  // ── Logo ─────────────────────────────────
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.secondary.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Icon(
                          Icons.hub_rounded,
                          color: AppColors.secondary,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        AppConstants.appName,
                        style: AppTextStyles.titleLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ).animate().fadeIn(duration: 400.ms),

                  const SizedBox(height: 48),

                  // ── Welcome ───────────────────────────────
                  Text(
                    'Welcome back',
                    style: AppTextStyles.headlineLarge.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  )
                      .animate(delay: 100.ms)
                      .slideY(begin: 0.3, end: 0, duration: 400.ms)
                      .fadeIn(),

                  const SizedBox(height: 6),

                  Text(
                    'Faith. Knowledge. Community.',
                    style: AppTextStyles.bodyLarge.copyWith(color: Colors.white60),
                  )
                      .animate(delay: 200.ms)
                      .slideY(begin: 0.3, end: 0, duration: 400.ms)
                      .fadeIn(),

                  const SizedBox(height: 48),

                  // ── Google ────────────────────────────────
                  _GoogleSignInButton(
                    isLoading: _isLoading && !_showEmailForm,
                    onPressed: _signInWithGoogle,
                  ).animate(delay: 300.ms).fadeIn(),

                  const SizedBox(height: 16),

                  // ── Divider ───────────────────────────────
                  Row(
                    children: [
                      const Expanded(
                          child: Divider(color: Colors.white24, thickness: 0.5)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('or',
                            style: AppTextStyles.labelMedium
                                .copyWith(color: Colors.white38)),
                      ),
                      const Expanded(
                          child: Divider(color: Colors.white24, thickness: 0.5)),
                    ],
                  ).animate(delay: 400.ms).fadeIn(),

                  const SizedBox(height: 16),

                  // ── Phone form or button ──────────────────
                  if (!_showEmailForm)
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      crossFadeState: _showPhoneForm
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: _ContinueWithPhoneButton(
                        onPressed: () =>
                            setState(() => _showPhoneForm = true),
                      ),
                      secondChild: _PhoneForm(
                        phoneCtrl: _phoneCtrl,
                        isLoading: _isLoading,
                        onSubmit: _sendPhoneOtp,
                        onBack: () => setState(() => _showPhoneForm = false),
                      ),
                    ).animate(delay: 430.ms).fadeIn(),

                  if (!_showPhoneForm) ...[
                    const SizedBox(height: 12),
                    // ── Email form or button ──────────────────
                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      crossFadeState: _showEmailForm
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: _ContinueWithEmailButton(
                        onPressed: () =>
                            setState(() => _showEmailForm = true),
                      ),
                      secondChild: _EmailForm(
                        formKey: _formKey,
                        identifierCtrl: _identifierCtrl,
                        passwordCtrl: _passwordCtrl,
                        obscurePassword: _obscurePassword,
                        isLoading: _isLoading,
                        onTogglePassword: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                        onSubmit: _signInWithCredentials,
                        onRegister: () => context.push(AppRoutes.register),
                      ),
                    ).animate(delay: 450.ms).fadeIn(),
                  ],

                  const SizedBox(height: 32),

                  // ── Terms ──────────────────────────────────
                  Text(
                    'By continuing, you agree to our Terms of Service and '
                    'Privacy Policy. CommunityHub is a faith-safe platform.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: Colors.white30,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ).animate(delay: 500.ms).fadeIn(),

                  const SizedBox(height: 16),

                  // ── Scripture ──────────────────────────────
                  Text(
                    '"The Lord gives wisdom; from his mouth come knowledge '
                    'and understanding." — Proverbs 2:6',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.secondary.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ).animate(delay: 600.ms).fadeIn(),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ContinueWithPhoneButton extends StatelessWidget {
  const _ContinueWithPhoneButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.phone_outlined, color: Colors.white70, size: 20),
      label: Text(
        'Continue with Phone',
        style: AppTextStyles.buttonText.copyWith(color: Colors.white),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}

class _PhoneForm extends StatelessWidget {
  const _PhoneForm({
    required this.phoneCtrl,
    required this.isLoading,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController phoneCtrl;
  final bool isLoading;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0x1AFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
          ),
          labelStyle: TextStyle(color: Colors.white54),
          hintStyle: TextStyle(color: Colors.white38),
          prefixIconColor: Colors.white54,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: phoneCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(
              labelText: 'Phone number',
              hintText: '+254712345678',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Include country code e.g. +254 for Kenya',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: isLoading ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.secondary.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text('Send Code',
                      style:
                          AppTextStyles.buttonText.copyWith(color: Colors.white)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onBack,
            child: Text('Use email instead',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _ContinueWithEmailButton extends StatelessWidget {
  const _ContinueWithEmailButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white38),
        minimumSize: const Size(double.infinity, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(
        'Continue with Email / Username',
        style: AppTextStyles.buttonText.copyWith(color: Colors.white),
      ),
    );
  }
}

class _EmailForm extends StatelessWidget {
  const _EmailForm({
    required this.formKey,
    required this.identifierCtrl,
    required this.passwordCtrl,
    required this.obscurePassword,
    required this.isLoading,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onRegister,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController identifierCtrl;
  final TextEditingController passwordCtrl;
  final bool obscurePassword;
  final bool isLoading;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0x1AFFFFFF),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Colors.white24),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: AppColors.secondary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: AppColors.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: AppColors.error),
          ),
          labelStyle: TextStyle(color: Colors.white54),
          hintStyle: TextStyle(color: Colors.white38),
          prefixIconColor: Colors.white54,
          suffixIconColor: Colors.white54,
          errorStyle: TextStyle(color: Color(0xFFFF6B6B)),
        ),
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: identifierCtrl,
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Email, username or phone',
                hintText: 'e.g. john@email.com  /  @john  /  +1234567890',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Enter your email, username or phone number';
                }
                return null;
              },
            ),

            const SizedBox(height: 14),

            TextFormField(
              controller: passwordCtrl,
              style: const TextStyle(color: Colors.white),
              obscureText: obscurePassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  icon: Icon(obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: onTogglePassword,
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please enter your password';
                return null;
              },
            ),

            const SizedBox(height: 22),

            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: isLoading ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.secondary.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : Text('Sign In',
                        style: AppTextStyles.buttonText
                            .copyWith(color: Colors.white)),
              ),
            ),

            const SizedBox(height: 14),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "Don't have an account? ",
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.white54),
                ),
                GestureDetector(
                  onTap: onRegister,
                  child: Text(
                    'Register',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.isLoading,
    required this.onPressed,
  });

  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.primary,
                ),
              )
            else ...[
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Center(
                  child: Text(
                    'G',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Continue with Google',
                style: AppTextStyles.buttonText.copyWith(
                  color: const Color(0xFF3C4043),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

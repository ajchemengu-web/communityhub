import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _isLoading = false;

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
      // Router redirect handles navigation to home
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sign in failed: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),

                // ── Logo + Name ────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: AppColors.secondary.withOpacity(0.5),
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

                const SizedBox(height: 60),

                // ── Welcome ────────────────────────────────
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

                const SizedBox(height: 8),

                Text(
                  'Faith. Knowledge. Community.',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: Colors.white60,
                  ),
                )
                    .animate(delay: 200.ms)
                    .slideY(begin: 0.3, end: 0, duration: 400.ms)
                    .fadeIn(),

                const Spacer(),

                // ── Google Sign In ─────────────────────────
                _GoogleSignInButton(
                  isLoading: _isLoading,
                  onPressed: _signInWithGoogle,
                ).animate(delay: 400.ms).slideY(
                      begin: 0.4,
                      end: 0,
                      duration: 500.ms,
                      curve: Curves.easeOut,
                    ).fadeIn(),

                const SizedBox(height: 16),

                // ── Divider ───────────────────────────────
                Row(
                  children: [
                    const Expanded(
                        child: Divider(color: Colors.white24, thickness: 0.5)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'or',
                        style: AppTextStyles.labelMedium.copyWith(
                          color: Colors.white38,
                        ),
                      ),
                    ),
                    const Expanded(
                        child: Divider(color: Colors.white24, thickness: 0.5)),
                  ],
                ).animate(delay: 500.ms).fadeIn(),

                const SizedBox(height: 16),

                // ── Email / Password (future) ──────────────
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    minimumSize: const Size(double.infinity, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'Continue with Email',
                    style: AppTextStyles.buttonText.copyWith(color: Colors.white),
                  ),
                ).animate(delay: 550.ms).fadeIn(),

                const SizedBox(height: 32),

                // ── Terms ──────────────────────────────────
                Text(
                  'By continuing, you agree to our Terms of Service and Privacy Policy. '
                  'CommunityHub is a faith-safe platform committed to your spiritual and '
                  'professional growth.',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white30,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ).animate(delay: 600.ms).fadeIn(),

                const SizedBox(height: 24),

                // ── Scripture ──────────────────────────────
                Text(
                  '"The Lord gives wisdom; from his mouth come knowledge and understanding." — Proverbs 2:6',
                  style: AppTextStyles.verseText.copyWith(
                    color: AppColors.secondary.withOpacity(0.6),
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.center,
                ).animate(delay: 700.ms).fadeIn(),

                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          ),
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
              color: Colors.black.withOpacity(0.2),
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
              // Google G logo using text (replace with actual SVG asset later)
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

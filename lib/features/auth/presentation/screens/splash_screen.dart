import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/app_routes.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigate();
  }

  Future<void> _navigate() async {
    // Allow splash animation to play
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;

    if (SupabaseService.isAuthenticated) {
      context.go(AppRoutes.home);
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.splashGradient,
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(flex: 2),

                // ── Logo ──────────────────────────────────
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: AppColors.secondary.withOpacity(0.4),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    size: 56,
                    color: AppColors.secondary,
                  ),
                )
                    .animate()
                    .scale(
                      duration: 600.ms,
                      curve: Curves.elasticOut,
                      begin: const Offset(0.3, 0.3),
                    )
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 28),

                // ── App Name ──────────────────────────────
                Text(
                  AppConstants.appName,
                  style: AppTextStyles.headlineMedium.copyWith(
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                )
                    .animate(delay: 300.ms)
                    .slideY(
                      begin: 0.5,
                      end: 0,
                      duration: 500.ms,
                      curve: Curves.easeOut,
                    )
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 8),

                // ── Tagline ───────────────────────────────
                Text(
                  AppConstants.appTagline,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.secondary,
                    letterSpacing: 2,
                  ),
                )
                    .animate(delay: 500.ms)
                    .fadeIn(duration: 400.ms),

                const Spacer(flex: 2),

                // ── Loading Indicator ─────────────────────
                SizedBox(
                  width: 120,
                  child: LinearProgressIndicator(
                    backgroundColor: Colors.white.withOpacity(0.1),
                    color: AppColors.secondary,
                    minHeight: 2,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
                    .animate(delay: 800.ms)
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 40),

                // ── Scripture ─────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    '"For we are God\'s handiwork, created in Christ Jesus to do good works"',
                    style: AppTextStyles.verseText.copyWith(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
                    .animate(delay: 1000.ms)
                    .fadeIn(duration: 600.ms),

                const SizedBox(height: 12),

                Text(
                  '— Ephesians 2:10',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.secondary.withOpacity(0.7),
                  ),
                )
                    .animate(delay: 1200.ms)
                    .fadeIn(duration: 400.ms),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

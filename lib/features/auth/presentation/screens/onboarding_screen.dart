import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pages = [
    _OnboardingPage(
      icon: Icons.church_rounded,
      iconColor: AppColors.faithTag,
      gradient: [Color(0xFF1A237E), Color(0xFF283593)],
      title: 'Faith Hub',
      subtitle: 'Grow spiritually with Gospel music,\nsermons, and scripture from\nbelievers worldwide.',
      verse: '"Your word is a lamp for my feet,\na light on my path." — Psalm 119:105',
    ),
    _OnboardingPage(
      icon: Icons.code_rounded,
      iconColor: AppColors.techTag,
      gradient: [Color(0xFF004D40), Color(0xFF00695C)],
      title: 'Career Hub',
      subtitle: 'Level up your tech skills with\ncoding, cybersecurity, data science\nand engineering tutorials.',
      verse: '"Whatever your hand finds to do,\ndo it with all your might." — Ecclesiastes 9:10',
    ),
    _OnboardingPage(
      icon: Icons.people_rounded,
      iconColor: AppColors.secondary,
      gradient: [Color(0xFF4A148C), Color(0xFF6A1B9A)],
      title: 'Communities',
      subtitle: 'Connect with your church,\njoin faith communities, and\nbuild meaningful relationships.',
      verse: '"Where two or three gather in my name,\nthere am I with them." — Matthew 18:20',
    ),
    _OnboardingPage(
      icon: Icons.chat_bubble_rounded,
      iconColor: AppColors.accent,
      gradient: [Color(0xFF0D1117), Color(0xFF1A237E)],
      title: 'Chat & Share',
      subtitle: 'Message peers, share testimonies,\npost reels and stories — all in\na faith-safe environment.',
      verse: '"Let your conversation be always full of grace." — Colossians 4:6',
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      context.go(AppRoutes.login);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Pages ─────────────────────────────────────────
          PageView.builder(
            controller: _controller,
            itemCount: _pages.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (ctx, i) => _OnboardingPageView(page: _pages[i]),
          ),

          // ── Bottom Controls ────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: MediaQuery.of(context).padding.bottom + 32,
                top: 24,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                children: [
                  // Page indicator
                  SmoothPageIndicator(
                    controller: _controller,
                    count: _pages.length,
                    effect: const WormEffect(
                      dotWidth: 8,
                      dotHeight: 8,
                      spacing: 6,
                      activeDotColor: AppColors.secondary,
                      dotColor: Colors.white30,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Next / Get Started button
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: AppColors.darkBackground,
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      textStyle: AppTextStyles.buttonText.copyWith(fontSize: 16),
                    ),
                    child: Text(
                      _currentPage == _pages.length - 1
                          ? 'Get Started'
                          : 'Next',
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Skip
                  if (_currentPage < _pages.length - 1)
                    TextButton(
                      onPressed: () => context.go(AppRoutes.login),
                      child: Text(
                        'Skip',
                        style: AppTextStyles.labelLarge.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});
  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: page.gradient,
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 60),

              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: page.iconColor.withOpacity(0.4),
                    width: 1,
                  ),
                ),
                child: Icon(page.icon, size: 44, color: page.iconColor),
              ).animate().scale(
                    duration: 500.ms,
                    curve: Curves.elasticOut,
                    begin: const Offset(0.5, 0.5),
                  ),

              const SizedBox(height: 40),

              // Title
              Text(
                page.title,
                style: AppTextStyles.headlineLarge.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ).animate().slideX(
                    begin: -0.3,
                    end: 0,
                    duration: 400.ms,
                    curve: Curves.easeOut,
                  ).fadeIn(),

              const SizedBox(height: 16),

              // Subtitle
              Text(
                page.subtitle,
                style: AppTextStyles.bodyLarge.copyWith(
                  color: Colors.white70,
                  height: 1.6,
                ),
              ).animate(delay: 100.ms).slideX(
                    begin: -0.3,
                    end: 0,
                    duration: 400.ms,
                    curve: Curves.easeOut,
                  ).fadeIn(),

              const Spacer(),

              // Scripture
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
                child: Text(
                  page.verse,
                  style: AppTextStyles.verseText.copyWith(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                ),
              ).animate(delay: 200.ms).fadeIn(duration: 600.ms),

              const SizedBox(height: 180),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.verse,
  });

  final IconData icon;
  final Color iconColor;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final String verse;
}

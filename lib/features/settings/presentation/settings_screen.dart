import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 8),

          // ── Account ───────────────────────────────────────
          _SectionHeader('Account'),
          _SettingsTile(
            icon: Icons.person_outline_rounded,
            title: 'Edit Profile',
            onTap: () => context.push('/edit-profile'),
          ),
          _SettingsTile(
            icon: Icons.lock_outline_rounded,
            title: 'Change Password',
            onTap: () => _showComingSoon(context),
          ),
          _SettingsTile(
            icon: Icons.phone_outlined,
            title: 'Phone Number',
            onTap: () => _showComingSoon(context),
          ),
          _SettingsTile(
            icon: Icons.email_outlined,
            title: 'Email Address',
            onTap: () => _showComingSoon(context),
          ),

          const SizedBox(height: 8),

          // ── Giving ──────────────────────────────────────────
          _SectionHeader('Giving'),
          _SettingsTile(
            icon: Icons.volunteer_activism_outlined,
            title: 'Give',
            onTap: () => context.push('/give'),
          ),
          _SettingsTile(
            icon: Icons.receipt_long_outlined,
            title: 'My Giving History',
            onTap: () => context.push('/give/history'),
          ),

          const SizedBox(height: 8),

          // ── Marketplace ─────────────────────────────────────
          _SectionHeader('Marketplace'),
          _SettingsTile(
            icon: Icons.storefront_outlined,
            title: 'Browse Marketplace',
            onTap: () => context.push('/marketplace'),
          ),
          _SettingsTile(
            icon: Icons.receipt_long_outlined,
            title: 'My Orders',
            onTap: () => context.push('/marketplace/orders'),
          ),
          _SettingsTile(
            icon: Icons.workspace_premium_outlined,
            title: 'My Memberships',
            onTap: () => context.push('/memberships'),
          ),

          const SizedBox(height: 8),

          // ── Privacy ───────────────────────────────────────
          _SectionHeader('Privacy & Safety'),
          _SettingsTile(
            icon: Icons.visibility_outlined,
            title: 'Account Privacy',
            onTap: () => _showComingSoon(context),
          ),
          _SettingsTile(
            icon: Icons.block_rounded,
            title: 'Blocked Accounts',
            onTap: () => _showComingSoon(context),
          ),

          const SizedBox(height: 8),

          // ── Notifications ─────────────────────────────────
          _SectionHeader('Notifications'),
          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Push Notifications',
            onTap: () => _showComingSoon(context),
          ),

          const SizedBox(height: 8),

          // ── Support ───────────────────────────────────────
          _SectionHeader('Support'),
          _SettingsTile(
            icon: Icons.help_outline_rounded,
            title: 'Help Center',
            onTap: () => _showComingSoon(context),
          ),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PrivacyPolicyScreen(),
              ),
            ),
          ),
          _SettingsTile(
            icon: Icons.info_outline_rounded,
            title: 'About CommunityHub',
            onTap: () => _showAbout(context),
          ),

          const SizedBox(height: 8),

          // ── Danger zone ───────────────────────────────────
          _SectionHeader('Account Actions'),
          _SettingsTile(
            icon: Icons.logout_rounded,
            title: 'Sign Out',
            titleColor: AppColors.error,
            iconColor: AppColors.error,
            onTap: () => _confirmSignOut(context, ref),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'CommunityHub',
      applicationVersion: '1.0.0',
      applicationLegalese: '© 2025 CommunityHub. Faith. Knowledge. Community.',
    );
  }

  void _confirmSignOut(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        title: const Text('Sign Out', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ref.read(authNotifierProvider.notifier).signOut();
            },
            child: Text(
              'Sign Out',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.textMuted,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.titleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? titleColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.darkSurface,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: iconColor ?? Colors.white70),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: titleColor ?? Colors.white,
                  ),
                ),
              ),
              if (titleColor == null)
                const Icon(Icons.chevron_right_rounded,
                    size: 20, color: Colors.white38),
            ],
          ),
        ),
      ),
    );
  }
}

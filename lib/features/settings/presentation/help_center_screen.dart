import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const _faqs = [
    (
      'How do I create a post?',
      'Tap the + button in the bottom navigation, choose a photo or video '
          'from your gallery, add a caption, and share.',
    ),
    (
      'How does giving/tithing work?',
      'Open Settings → Give, or tap the giving icon on a community page. '
          'You can pay with M-Pesa, card (Stripe), or Paystack.',
    ),
    (
      'How do I go live?',
      'Tap the live camera icon on the Home tab. Your stream starts '
          'immediately and viewers can join from the live streams row.',
    ),
    (
      'How do community memberships work?',
      'Communities can offer paid membership tiers with exclusive perks. '
          'Find them under a community\'s membership icon, or manage your own '
          'under Settings → My Memberships.',
    ),
    (
      'How do I report or block someone?',
      'Open the "···" menu on a post, comment, or profile and choose '
          'Report or Block.',
    ),
    (
      'How do I delete my account?',
      'Contact support below and we\'ll process the deletion request.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Help Center'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Frequently asked questions',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.secondary,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          ..._faqs.map((faq) => _FaqTile(question: faq.$1, answer: faq.$2)),
          const SizedBox(height: 24),
          Card(
            color: AppColors.darkSurface2,
            child: ListTile(
              leading: const Icon(Icons.email_outlined, color: Colors.white70),
              title: const Text('Contact support',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text('support@communityhub.app',
                  style: TextStyle(color: Colors.white54)),
              trailing: const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              onTap: () => launchUrl(
                Uri(
                  scheme: 'mailto',
                  path: 'support@communityhub.app',
                  query: 'subject=CommunityHub Support Request',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.question, required this.answer});
  final String question;
  final String answer;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(question,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        iconColor: AppColors.secondary,
        collapsedIconColor: Colors.white54,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(answer,
                style: const TextStyle(color: Colors.white70, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Privacy Policy'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: const [
          _PolicySection(
            title: 'Last Updated: June 29, 2025',
            body:
                'CommunityHub ("we", "our", or "us") is committed to protecting your privacy. '
                'This Privacy Policy explains how we collect, use, disclose, and safeguard your '
                'information when you use our mobile application and related services.',
          ),

          _PolicySection(
            title: '1. Information We Collect',
            body:
                'We collect information you provide directly to us, including:\n\n'
                '• Account information: name, username, email address, phone number, '
                'and profile photo when you register.\n\n'
                '• Profile data: biography, church/congregation name, website URL, '
                'and hub preferences (Faith or Career).\n\n'
                '• Content you create: posts, comments, stories, messages, and any '
                'media you upload.\n\n'
                '• Communication data: messages sent through our in-app chat feature.\n\n'
                '• Usage data: how you interact with features, which content you view, '
                'and the actions you take within the app.\n\n'
                '• Device information: device type, operating system version, unique '
                'device identifiers, and IP address.\n\n'
                '• Authentication data: sign-in credentials and OAuth tokens when you '
                'use Google Sign-In.',
          ),

          _PolicySection(
            title: '2. How We Use Your Information',
            body:
                'We use the information we collect to:\n\n'
                '• Create and manage your account.\n'
                '• Personalise your feed and content recommendations.\n'
                '• Enable you to connect with others in the community.\n'
                '• Send you notifications about activity relevant to you.\n'
                '• Maintain the security and integrity of our platform.\n'
                '• Detect and prevent fraud, abuse, and violations of our Terms.\n'
                '• Improve and develop new features and services.\n'
                '• Comply with applicable legal obligations.',
          ),

          _PolicySection(
            title: '3. Sharing of Information',
            body:
                'We do not sell your personal information. We may share your '
                'information in the following circumstances:\n\n'
                '• With other users: your profile (name, username, profile photo, bio) '
                'is visible to other users of the platform.\n\n'
                '• Service providers: we share data with trusted third-party services '
                '(e.g. Supabase for database and authentication, cloud storage providers) '
                'that assist us in operating the platform. These providers are bound by '
                'confidentiality agreements.\n\n'
                '• Legal requirements: we may disclose your information if required by '
                'law or in response to valid legal processes.\n\n'
                '• Business transfers: in the event of a merger or acquisition, your '
                'information may be transferred to the new entity.',
          ),

          _PolicySection(
            title: '4. Data Storage & Security',
            body:
                'Your data is stored on secure servers provided by Supabase, which uses '
                'industry-standard encryption (TLS in transit, AES-256 at rest). We '
                'implement access controls, monitoring, and regular security reviews.\n\n'
                'However, no method of transmission over the internet or electronic '
                'storage is 100% secure. We encourage you to use a strong, unique '
                'password and to keep your credentials confidential.',
          ),

          _PolicySection(
            title: '5. Data Retention',
            body:
                'We retain your personal information for as long as your account is '
                'active or as needed to provide services. You may delete your account at '
                'any time, which will remove your profile and content from public view. '
                'Some residual data may be retained in backups for up to 90 days for '
                'legal and operational purposes.',
          ),

          _PolicySection(
            title: '6. Your Rights',
            body:
                'Depending on your location, you may have the following rights:\n\n'
                '• Access: request a copy of the personal data we hold about you.\n'
                '• Correction: request that inaccurate data be corrected.\n'
                '• Deletion: request deletion of your personal data ("right to be forgotten").\n'
                '• Portability: request your data in a portable format.\n'
                '• Objection: object to certain types of data processing.\n\n'
                'To exercise these rights, contact us at privacy@communityhub.app.',
          ),

          _PolicySection(
            title: '7. Children\'s Privacy',
            body:
                'CommunityHub is not intended for children under the age of 13 (or 16 in '
                'the European Economic Area). We do not knowingly collect personal '
                'information from children. If we become aware that a child has provided '
                'us with personal information without parental consent, we will delete '
                'that information promptly.',
          ),

          _PolicySection(
            title: '8. Third-Party Services',
            body:
                'Our app integrates with third-party services including:\n\n'
                '• Google Sign-In (Google LLC) — for authentication.\n'
                '• YouTube IFrame API (Google LLC) — for in-app video playback.\n'
                '• Supabase — for backend, database, and storage.\n\n'
                'Each third party has its own privacy policy. We encourage you to '
                'review them independently.',
          ),

          _PolicySection(
            title: '9. Changes to This Policy',
            body:
                'We may update this Privacy Policy from time to time. We will notify '
                'you of significant changes by posting the new policy in the app and '
                'updating the "Last Updated" date at the top. Your continued use of '
                'the app after changes are posted constitutes your acceptance of the '
                'revised policy.',
          ),

          _PolicySection(
            title: '10. Contact Us',
            body:
                'If you have any questions or concerns about this Privacy Policy or '
                'our data practices, please contact us:\n\n'
                'Email: privacy@communityhub.app\n'
                'Website: https://communityhub.app/privacy\n\n'
                '"The Lord gives wisdom; from his mouth come knowledge and '
                'understanding." — Proverbs 2:6',
          ),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTextStyles.bodyMedium.copyWith(
              color: Colors.white70,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

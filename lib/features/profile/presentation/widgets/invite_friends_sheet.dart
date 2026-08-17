import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';

/// Opens the "Invite friends" bottom sheet from the profile screen's
/// person-add icon.
///
/// WhatsApp and Facebook both publish a real web share-intent URL that
/// accepts a pre-filled message/link (wa.me, and Facebook's own
/// sharer.php — though Facebook only actually honors the link there;
/// it drops custom "quote" text server-side for most callers, an
/// anti-spam measure it's had in place for years, so that one's
/// realistically link-only no matter what this sends).
///
/// Instagram and TikTok don't publish anything equivalent — neither has
/// a web endpoint that accepts arbitrary invite text the way wa.me
/// does. Their own in-app share sheets only forward content that's
/// already inside their app (a specific post/reel/video), not
/// third-party text. The realistic thing to do here, and what most
/// apps actually do for these two, is copy the invite message to the
/// clipboard and open the app/site, so the person can paste it
/// themselves into a DM, Story, or bio.
void showInviteFriendsSheet(BuildContext context, {required String username}) {
  // Captured before the sheet opens (and any async gap) so it stays
  // valid for a snackbar shown after the sheet has already closed —
  // the profile screen underneath stays mounted the whole time, even
  // though the sheet's own BuildContext doesn't survive being popped.
  final messenger = ScaffoldMessenger.of(context);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF0F172A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => _InviteFriendsSheet(
      username: username,
      messenger: messenger,
    ),
  );
}

String _inviteMessage(String username) {
  final handle = username.isNotEmpty ? '@$username' : 'me';
  return "Hey! I'm on CommunityHub — $handle here. Join faith, learning "
      "and career communities, events, scripture study and more, all in "
      "one app: ${AppConstants.appWebsiteUrl}";
}

class _InviteFriendsSheet extends StatelessWidget {
  const _InviteFriendsSheet({
    required this.username,
    required this.messenger,
  });

  final String username;
  final ScaffoldMessengerState messenger;

  Future<void> _openWhatsApp(BuildContext sheetContext) async {
    final text = Uri.encodeComponent(_inviteMessage(username));
    Navigator.of(sheetContext).pop();
    await _launch(Uri.parse('https://wa.me/?text=$text'), 'WhatsApp');
  }

  Future<void> _openFacebook(BuildContext sheetContext) async {
    final link = Uri.encodeComponent(AppConstants.appWebsiteUrl);
    final quote = Uri.encodeComponent(_inviteMessage(username));
    Navigator.of(sheetContext).pop();
    await _launch(
      Uri.parse(
          'https://www.facebook.com/sharer/sharer.php?u=$link&quote=$quote'),
      'Facebook',
    );
  }

  Future<void> _openInstagram(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    await _copyThenOpen(Uri.parse('https://www.instagram.com/'), 'Instagram');
  }

  Future<void> _openTikTok(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    await _copyThenOpen(Uri.parse('https://www.tiktok.com/'), 'TikTok');
  }

  Future<void> _copyThenOpen(Uri uri, String appName) async {
    await Clipboard.setData(ClipboardData(text: _inviteMessage(username)));
    messenger.showSnackBar(
      SnackBar(
        content: Text(
            'Invite message copied — paste it into a DM or your Story on $appName.'),
        backgroundColor: AppColors.info,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // $appName isn't installed/reachable from here — the message is
      // already on the clipboard, so the invite still got as far as it
      // can without it.
    }
  }

  Future<void> _launch(Uri uri, String appName) async {
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) throw Exception('launchUrl returned false');
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text("Couldn't open $appName — try 'More' instead."),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openMore(BuildContext sheetContext) {
    Navigator.of(sheetContext).pop();
    Share.share(_inviteMessage(username));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Invite friends',
              style: TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Share CommunityHub with people you know',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _InviteTile(
                  iconWidget: const FaIcon(FontAwesomeIcons.whatsapp,
                      color: Color(0xFF25D366), size: 22),
                  label: 'WhatsApp',
                  onTap: () => _openWhatsApp(context),
                ),
                _InviteTile(
                  iconWidget: const FaIcon(FontAwesomeIcons.facebook,
                      color: Color(0xFF1877F2), size: 22),
                  label: 'Facebook',
                  onTap: () => _openFacebook(context),
                ),
                _InviteTile(
                  iconWidget: const FaIcon(FontAwesomeIcons.instagram,
                      color: Color(0xFFE1306C), size: 22),
                  label: 'Instagram',
                  onTap: () => _openInstagram(context),
                ),
                _InviteTile(
                  iconWidget: const FaIcon(FontAwesomeIcons.tiktok,
                      color: Colors.white, size: 22),
                  label: 'TikTok',
                  onTap: () => _openTikTok(context),
                ),
                _InviteTile(
                  iconWidget: const Icon(Icons.more_horiz_rounded,
                      color: Colors.white70, size: 24),
                  label: 'More',
                  onTap: () => _openMore(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  const _InviteTile({
    required this.iconWidget,
    required this.label,
    required this.onTap,
  });

  final Widget iconWidget;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: Colors.white10,
              shape: BoxShape.circle,
            ),
            child: Center(child: iconWidget),
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }
}

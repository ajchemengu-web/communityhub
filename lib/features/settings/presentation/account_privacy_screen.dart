import 'package:flutter/material.dart';

import '../../../core/services/supabase_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../profile/data/profile_detail_repository.dart';
import '../../profile/presentation/screens/follow_requests_screen.dart';

class AccountPrivacyScreen extends StatefulWidget {
  const AccountPrivacyScreen({super.key});

  @override
  State<AccountPrivacyScreen> createState() => _AccountPrivacyScreenState();
}

class _AccountPrivacyScreenState extends State<AccountPrivacyScreen> {
  final _repo = ProfileDetailRepository.instance;
  bool _isPrivate = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final profile = await _repo.fetchProfile(uid);
    if (!mounted) return;
    setState(() {
      _isPrivate = (profile['is_private'] as bool?) ?? false;
      _isLoading = false;
    });
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _isPrivate = value;
      _isSaving = true;
    });
    await _repo.setPrivateAccount(value);
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Account Privacy'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  value: _isPrivate,
                  onChanged: _isSaving ? null : _toggle,
                  activeThumbColor: AppColors.secondary,
                  title: const Text('Private account',
                      style: TextStyle(color: Colors.white)),
                  subtitle: const Text(
                    'When your account is private, only people you approve can '
                    'see your posts. New followers will need your approval.',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                const Divider(color: AppColors.darkBorder, height: 1),
                ListTile(
                  leading: const Icon(Icons.person_add_alt_1_outlined,
                      color: Colors.white70),
                  title: const Text('Follow Requests',
                      style: TextStyle(color: Colors.white)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white38),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
                  ),
                ),
              ],
            ),
    );
  }
}

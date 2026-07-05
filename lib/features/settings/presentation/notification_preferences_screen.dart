import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../notifications/data/notifications_repository.dart';

class NotificationPreferencesScreen extends StatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  State<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends State<NotificationPreferencesScreen> {
  final _repo = NotificationsRepository.instance;
  Map<String, bool> _prefs = {};
  bool _isLoading = true;

  static const _labels = {
    'likes': ('Likes', 'When someone likes your posts or comments'),
    'comments': ('Comments', 'When someone comments on your posts'),
    'follows': ('Follows', 'New followers and follow requests'),
    'messages': ('Messages', 'New chat messages and missed calls'),
    'events': ('Events', 'RSVPs to events you organize'),
    'communities': ('Communities', 'New members joining your communities'),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await _repo.fetchPreferences();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _isLoading = false;
    });
  }

  Future<void> _toggle(String category, bool value) async {
    setState(() => _prefs[category] = value);
    await _repo.setPreference(category, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Push Notifications'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: _labels.entries.map((entry) {
                final category = entry.key;
                final (title, subtitle) = entry.value;
                return SwitchListTile(
                  value: _prefs[category] ?? true,
                  onChanged: (v) => _toggle(category, v),
                  activeThumbColor: AppColors.secondary,
                  title: Text(title, style: const TextStyle(color: Colors.white)),
                  subtitle:
                      Text(subtitle, style: const TextStyle(color: Colors.white54)),
                );
              }).toList(),
            ),
    );
  }
}

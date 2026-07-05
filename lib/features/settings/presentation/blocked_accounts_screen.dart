import 'package:flutter/material.dart';

import '../../../core/services/block_service.dart';
import '../../../core/theme/app_colors.dart';

class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  List<Map<String, dynamic>> _blocked = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final blocked = await BlockService.instance.fetchBlockedByMe();
    if (!mounted) return;
    setState(() {
      _blocked = blocked;
      _isLoading = false;
    });
  }

  Future<void> _unblock(String userId) async {
    await BlockService.instance.unblockUser(userId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Blocked Accounts'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blocked.isEmpty
              ? const Center(
                  child: Text('No blocked accounts',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _blocked.length,
                  itemBuilder: (context, i) {
                    final row = _blocked[i];
                    final user = row['blocked'] as Map?;
                    final name = user?['full_name'] as String? ??
                        user?['username'] as String? ??
                        'User';
                    final avatarUrl = user?['avatar_url'] as String?;

                    return Card(
                      color: AppColors.darkSurface2,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage:
                              avatarUrl != null ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null
                              ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?')
                              : null,
                        ),
                        title: Text(name, style: const TextStyle(color: Colors.white)),
                        trailing: OutlinedButton(
                          onPressed: () => _unblock(row['blocked_id'] as String),
                          child: const Text('Unblock'),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

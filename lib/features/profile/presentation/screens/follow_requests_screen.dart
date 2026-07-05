import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/profile_detail_repository.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  final _repo = ProfileDetailRepository.instance;
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final requests = await _repo.fetchFollowRequests();
    if (!mounted) return;
    setState(() {
      _requests = requests;
      _isLoading = false;
    });
  }

  Future<void> _respond(String followerId, {required bool accept}) async {
    setState(() => _requests.removeWhere((r) => r['follower_id'] == followerId));
    if (accept) {
      await _repo.acceptFollowRequest(followerId);
    } else {
      await _repo.rejectFollowRequest(followerId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        title: const Text('Follow Requests'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? const Center(
                  child: Text('No pending follow requests',
                      style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _requests.length,
                  itemBuilder: (context, i) {
                    final row = _requests[i];
                    final follower = row['follower'] as Map?;
                    final followerId = row['follower_id'] as String;
                    final name = follower?['full_name'] as String? ??
                        follower?['username'] as String? ??
                        'User';
                    final avatarUrl = follower?['avatar_url'] as String?;

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
                        subtitle: const Text('wants to follow you',
                            style: TextStyle(color: Colors.white54)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton(
                              onPressed: () => _respond(followerId, accept: false),
                              child: const Text('Reject'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _respond(followerId, accept: true),
                              child: const Text('Accept'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

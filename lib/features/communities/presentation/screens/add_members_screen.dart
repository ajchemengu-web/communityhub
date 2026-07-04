import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/communities_repository.dart';

class AddMembersScreen extends ConsumerStatefulWidget {
  const AddMembersScreen({super.key, required this.communityId});
  final String communityId;

  @override
  ConsumerState<AddMembersScreen> createState() => _AddMembersScreenState();
}

class _AddMembersScreenState extends ConsumerState<AddMembersScreen> {
  List<Map<String, dynamic>> _users = [];
  final Set<String> _selected = {};
  bool _loading = true;
  bool _adding = false;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final users = await CommunitiesRepository.instance.fetchFollowedUsers();
    if (mounted) setState(() { _users = users; _loading = false; });
  }

  Future<void> _confirm() async {
    if (_selected.isEmpty) return;
    setState(() => _adding = true);
    try {
      await CommunitiesRepository.instance.addMembers(
        widget.communityId,
        _selected.toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_selected.length} member${_selected.length == 1 ? '' : 's'} added'),
            backgroundColor: AppColors.primary,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add members: $e'), backgroundColor: Colors.red),
        );
        setState(() => _adding = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _users;
    final q = _query.toLowerCase();
    return _users.where((u) {
      final name = (u['full_name'] as String? ?? '').toLowerCase();
      final username = (u['username'] as String? ?? '').toLowerCase();
      return name.contains(q) || username.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Add members',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600)),
            if (_selected.isNotEmpty)
              Text('${_selected.length} selected',
                  style: const TextStyle(
                      color: Colors.white54, fontSize: 12)),
          ],
        ),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: _adding ? null : _confirm,
              child: _adding
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : const Text('Add',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Search bar ────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search, color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),

          // ── Selected chips ────────────────────────────────────
          if (_selected.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                children: _users
                    .where((u) => _selected.contains(u['id'] as String?))
                    .map((u) {
                  final avatar = u['avatar_url'] as String?;
                  final name = (u['full_name'] as String? ??
                      u['username'] as String? ??
                      '?');
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            CircleAvatar(
                              radius: 22,
                              backgroundImage: avatar != null
                                  ? CachedNetworkImageProvider(avatar)
                                  : null,
                              backgroundColor: AppColors.primary.withValues(alpha: 0.3),
                              child: avatar == null
                                  ? Text(name[0].toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600))
                                  : null,
                            ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                onTap: () => setState(
                                    () => _selected.remove(u['id'] as String)),
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      size: 11, color: Colors.black),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(name.split(' ').first,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

          if (_selected.isNotEmpty)
            const Divider(color: Colors.white10, height: 1),

          // ── User list ─────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.people_outline,
                                color: Colors.white24, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              _query.isNotEmpty
                                  ? 'No results for "$_query"'
                                  : 'Follow people to add them as members',
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final u = filtered[i];
                          final uid = u['id'] as String? ?? '';
                          final avatar = u['avatar_url'] as String?;
                          final name = u['full_name'] as String? ??
                              u['username'] as String? ??
                              'User';
                          final username = u['username'] as String? ?? '';
                          final verified =
                              u['is_verified'] as bool? ?? false;
                          final isSelected = _selected.contains(uid);

                          return ListTile(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selected.remove(uid);
                                } else {
                                  _selected.add(uid);
                                }
                              });
                            },
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage: avatar != null
                                  ? CachedNetworkImageProvider(avatar)
                                  : null,
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.3),
                              child: avatar == null
                                  ? Text(name[0].toUpperCase(),
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600))
                                  : null,
                            ),
                            title: Row(
                              children: [
                                Text(name,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500)),
                                if (verified) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.verified,
                                      size: 14, color: AppColors.primary),
                                ],
                              ],
                            ),
                            subtitle: username.isNotEmpty
                                ? Text('@$username',
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12))
                                : null,
                            trailing: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                border: Border.all(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.white38,
                                  width: 2,
                                ),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check,
                                      color: Colors.white, size: 14)
                                  : null,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      // ── Floating Add button ───────────────────────────────────
      floatingActionButton: _selected.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _adding ? null : _confirm,
              backgroundColor: AppColors.primary,
              icon: _adding
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check),
              label: Text('Add ${_selected.length} member${_selected.length == 1 ? '' : 's'}'),
            )
          : null,
    );
  }
}

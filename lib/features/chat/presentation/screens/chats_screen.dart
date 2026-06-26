import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/services/supabase_service.dart';
import '../providers/chats_provider.dart';
import '../../data/chat_repository.dart';
import '../../domain/models/conversation_model.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  final _searchCtrl = TextEditingController();
  bool _searchActive = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: _searchActive
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textDarkPrimary),
                decoration: InputDecoration(
                  hintText: 'Search conversations…',
                  hintStyle: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textMuted),
                  border: InputBorder.none,
                ),
                onChanged: (q) {
                  ref.read(chatsProvider.notifier).setSearch(q);
                },
              )
            : Row(
                children: [
                  Text(
                    'Messages',
                    style: AppTextStyles.heading3
                        .copyWith(color: AppColors.textDarkPrimary),
                  ),
                  if (state.totalUnread > 0) ...[
                    const SizedBox(width: 8),
                    _UnreadBadge(count: state.totalUnread),
                  ],
                ],
              ),
        actions: [
          IconButton(
            icon: Icon(
              _searchActive ? Icons.close : Icons.search,
              color: AppColors.textDarkPrimary,
            ),
            onPressed: () {
              setState(() {
                _searchActive = !_searchActive;
                if (!_searchActive) {
                  _searchCtrl.clear();
                  ref.read(chatsProvider.notifier).setSearch('');
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit_square,
                color: AppColors.textDarkPrimary),
            tooltip: 'New message',
            onPressed: () => _showNewChatSheet(context),
          ),
        ],
      ),
      body: state.isLoading
          ? const _LoadingShimmer()
          : RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.darkSurface,
              onRefresh: () => ref.read(chatsProvider.notifier).refresh(),
              child: state.filtered.isEmpty
                  ? _EmptyState(
                      isSearch: _searchActive,
                      onNew: () => _showNewChatSheet(context),
                    )
                  : ListView.separated(
                      itemCount: state.filtered.length,
                      separatorBuilder: (_, __) => const Divider(
                        color: AppColors.darkDivider,
                        height: 1,
                        indent: 80,
                      ),
                      itemBuilder: (_, i) {
                        final c = state.filtered[i];
                        return _ConversationTile(
                          conversation: c,
                          onTap: () {
                            ref
                                .read(chatsProvider.notifier)
                                .markConversationRead(c.id);
                            context.push('/chat/${c.id}');
                          },
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.message_outlined, color: Colors.white),
        onPressed: () => _showNewChatSheet(context),
      ),
    );
  }

  void _showNewChatSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _NewChatSheet(),
    );
  }
}

// ── Conversation tile ──────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  final ConversationModel conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = conversation.hasUnread;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // ── Avatar ───────────────────────────────────────
            Stack(
              children: [
                _ConvoAvatar(conversation: conversation),
                if (conversation.isDirect && conversation.isOnline)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.darkBackground, width: 2),
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // ── Name + last message ───────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.displayName,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textDarkPrimary,
                            fontWeight: hasUnread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (conversation.lastMessageAt != null)
                        Text(
                          timeago.format(conversation.lastMessageAt!,
                              allowFromNow: true),
                          style: AppTextStyles.overline.copyWith(
                            color: hasUnread
                                ? AppColors.primary
                                : AppColors.textMuted,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.lastMessage ?? 'No messages yet',
                          style: AppTextStyles.captionText.copyWith(
                            color: hasUnread
                                ? AppColors.textDarkPrimary
                                : AppColors.textMuted,
                            fontWeight: hasUnread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) _UnreadBadge(count: conversation.unreadCount),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Conversation avatar ────────────────────────────────────────────

class _ConvoAvatar extends StatelessWidget {
  const _ConvoAvatar({required this.conversation});

  final ConversationModel conversation;

  @override
  Widget build(BuildContext context) {
    final displayAvatar = conversation.displayAvatar;
    final name = conversation.displayName;

    if (displayAvatar != null) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: displayAvatar,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          placeholder: (_, __) => _InitialAvatar(name: name, size: 52),
          errorWidget: (_, __, ___) => _InitialAvatar(name: name, size: 52),
        ),
      );
    }

    if (conversation.isGroup) {
      // Group: overlapping mini avatars from first 2 participants
      final parts = conversation.participants.take(2).toList();
      return SizedBox(
        width: 52,
        height: 52,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              child: _InitialAvatar(
                name: parts.isNotEmpty ? parts[0].displayName : '?',
                size: 38,
                color: AppColors.primary,
              ),
            ),
            if (parts.length > 1)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.darkBackground, width: 2),
                  ),
                  child: _InitialAvatar(
                    name: parts[1].displayName,
                    size: 30,
                    color: AppColors.primaryLight,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return _InitialAvatar(name: name, size: 52);
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({
    required this.name,
    required this.size,
    this.color,
  });

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color ?? AppColors.primary.withOpacity(0.8),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Unread badge ───────────────────────────────────────────────────

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ── New chat bottom sheet ──────────────────────────────────────────

class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet();

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final _ctrl = TextEditingController();
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);

    try {
      final rows = await SupabaseService.client
          .from('profiles')
          .select('id, full_name, username, avatar_url')
          .or('full_name.ilike.%$q%,username.ilike.%$q%')
          .neq('id', SupabaseService.currentUserId ?? '')
          .limit(20) as List<dynamic>;
      setState(() {
        _results = rows.cast<Map<String, dynamic>>();
        _searching = false;
      });
    } catch (_) {
      setState(() => _searching = false);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.darkDivider,
                  borderRadius: BorderRadius.circular(2)),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'New Message',
                    style: AppTextStyles.heading3
                        .copyWith(color: AppColors.textDarkPrimary),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textDarkSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textDarkPrimary),
                decoration: InputDecoration(
                  hintText: 'Search people…',
                  hintStyle: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textMuted),
                  prefixIcon: const Icon(Icons.search,
                      color: AppColors.textDarkSecondary),
                  filled: true,
                  fillColor: AppColors.darkBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.darkBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.darkBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppColors.primary, width: 1.5),
                  ),
                ),
                onChanged: _search,
              ),
            ),

            if (_searching)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (_, i) {
                    final user = _results[i];
                    final name = user['full_name'] as String? ??
                        user['username'] as String? ?? 'User';
                    final avatar = user['avatar_url'] as String?;

                    return ListTile(
                      leading: ClipOval(
                        child: avatar != null
                            ? CachedNetworkImage(
                                imageUrl: avatar,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover)
                            : _InitialAvatar(name: name, size: 44),
                      ),
                      title: Text(
                        name,
                        style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textDarkPrimary,
                            fontWeight: FontWeight.w600),
                      ),
                      subtitle: user['username'] != null
                          ? Text('@${user['username']}',
                              style: AppTextStyles.captionText.copyWith(
                                  color: AppColors.textMuted))
                          : null,
                      onTap: () async {
                        Navigator.pop(context);
                        // Open or create conversation
                        final repo = ChatRepository.instance;
                        final convo = await repo
                            .getOrCreateDirectConversation(
                                user['id'] as String);
                        if (context.mounted) {
                          context.push('/chat/${convo.id}');
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Loading shimmer ────────────────────────────────────────────────

class _LoadingShimmer extends StatelessWidget {
  const _LoadingShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      itemCount: 8,
      separatorBuilder: (_, __) => const Divider(
          color: AppColors.darkDivider, height: 1, indent: 80),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      height: 14,
                      width: 120,
                      color: AppColors.darkSurface,
                      margin: const EdgeInsets.only(bottom: 8)),
                  Container(
                      height: 12,
                      color: AppColors.darkSurface),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isSearch, required this.onNew});

  final bool isSearch;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.chat_bubble_outline,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              isSearch
                  ? 'No results found'
                  : 'No conversations yet',
              style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textDarkPrimary,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isSearch
                  ? 'Try a different name or keyword'
                  : 'Start a conversation with someone in your community.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textDarkSecondary),
              textAlign: TextAlign.center,
            ),
            if (!isSearch) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onNew,
                icon: const Icon(Icons.add, color: Colors.white),
                label: const Text('New Message',
                    style: TextStyle(color: Colors.white)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

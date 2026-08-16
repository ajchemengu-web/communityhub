import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/call_model.dart';
import '../../domain/models/conversation_model.dart';
import '../../domain/models/message_model.dart';
import '../providers/call_provider.dart';
import '../providers/chat_detail_provider.dart';
import '../providers/chats_provider.dart';

class ChatDetailScreen extends ConsumerStatefulWidget {
  const ChatDetailScreen({super.key, required this.chatId});

  final String chatId;

  @override
  ConsumerState<ChatDetailScreen> createState() =>
      _ChatDetailScreenState();
}

class _ChatDetailScreenState extends ConsumerState<ChatDetailScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      ref.read(chatDetailProvider(widget.chatId).notifier).loadMore();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    ref
        .read(chatDetailProvider(widget.chatId).notifier)
        .broadcastTyping(false);
    await ref
        .read(chatDetailProvider(widget.chatId).notifier)
        .sendMessage(text);
    _scrollToBottom();
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      final ext = picked.name.contains('.') ? picked.name.split('.').last : 'jpg';
      if (!mounted) return;
      await ref
          .read(chatDetailProvider(widget.chatId).notifier)
          .sendMediaMessage(bytes, ext, MessageType.image);
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatDetailProvider(widget.chatId));
    final chatsState = ref.watch(chatsProvider);

    // Find conversation metadata
    final convo = chatsState.conversations
        .where((c) => c.id == widget.chatId)
        .firstOrNull;

    // Listen for new messages and scroll
    ref.listen(chatDetailProvider(widget.chatId), (prev, next) {
      if (prev != null && next.messages.length > prev.messages.length) {
        _scrollToBottom();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: _buildAppBar(convo),
      body: Column(
        children: [
          // Loading more indicator
          if (state.isLoadingMore)
            const LinearProgressIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.darkSurface,
              minHeight: 2,
            ),

          // Messages list
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                : state.messages.isEmpty
                    ? const _EmptyConvo()
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: state.messages.length,
                        itemBuilder: (_, i) {
                          final msg = state.messages[i];
                          final prev = i > 0 ? state.messages[i - 1] : null;
                          final next = i < state.messages.length - 1
                              ? state.messages[i + 1]
                              : null;

                          // Date separator
                          final showDate = prev == null ||
                              !_isSameDay(prev.createdAt, msg.createdAt);

                          return Column(
                            children: [
                              if (showDate)
                                _DateDivider(date: msg.createdAt),
                              _MessageBubble(
                                message: msg,
                                showAvatar: !msg.isCurrentUser &&
                                    (next == null ||
                                        next.senderId != msg.senderId),
                                isGrouped: prev != null &&
                                    prev.senderId == msg.senderId &&
                                    _isSameDay(prev.createdAt, msg.createdAt),
                                onReply: () => ref
                                    .read(chatDetailProvider(widget.chatId)
                                        .notifier)
                                    .setReplyTo(msg),
                                onReact: (emoji) => ref
                                    .read(chatDetailProvider(widget.chatId)
                                        .notifier)
                                    .toggleReaction(msg, emoji),
                                onDelete: msg.isCurrentUser
                                    ? () => ref
                                        .read(chatDetailProvider(widget.chatId)
                                            .notifier)
                                        .deleteMessage(msg.id)
                                    : null,
                              ),
                            ],
                          );
                        },
                      ),
          ),

          // Typing indicator
          if (state.typingUsers.isNotEmpty) _TypingIndicator(state.typingUsers),

          // Reply banner
          if (state.replyTo != null)
            _ReplyBanner(
              message: state.replyTo!,
              onDismiss: () => ref
                  .read(chatDetailProvider(widget.chatId).notifier)
                  .setReplyTo(null),
            ),

          // Input bar
          _InputBar(
            controller: _inputCtrl,
            isSending: state.isSending,
            onChanged: (v) {
              ref
                  .read(chatDetailProvider(widget.chatId).notifier)
                  .broadcastTyping(v.isNotEmpty);
            },
            onSend: _sendMessage,
            onPickMedia: _pickMedia,
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(ConversationModel? convo) {
    final displayName = convo?.displayName ?? 'Chat';
    final displayAvatar = convo?.displayAvatar;
    final isOnline = convo?.isDirect == true && convo?.isOnline == true;

    return AppBar(
      backgroundColor: AppColors.darkSurface,
      titleSpacing: 0,
      leading: BackButton(
        color: AppColors.textDarkPrimary,
        onPressed: () => context.pop(),
      ),
      title: Row(
        children: [
          displayAvatar != null
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: displayAvatar,
                    width: 38,
                    height: 38,
                    fit: BoxFit.cover,
                  ),
                )
              : Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha:0.8),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      displayName.isNotEmpty
                          ? displayName[0].toUpperCase()
                          : '?',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textDarkPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isOnline)
                  Text(
                    'Online',
                    style: AppTextStyles.overline
                        .copyWith(color: AppColors.success),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        // Audio call
        IconButton(
          icon: const Icon(Icons.call_outlined,
              color: AppColors.textDarkPrimary),
          onPressed: convo != null
              ? () => _initiateCall(CallType.audio, convo)
              : null,
        ),
        // Video call
        IconButton(
          icon: const Icon(Icons.videocam_outlined,
              color: AppColors.textDarkPrimary),
          onPressed: convo != null
              ? () => _initiateCall(CallType.video, convo)
              : null,
        ),
      ],
    );
  }

  Future<void> _initiateCall(CallType type, ConversationModel convo) async {
    if (convo.participants.isEmpty) return;
    final receiver = convo.participants.first;
    final call = await ref.read(callProvider.notifier).startCall(
          conversationId: convo.id,
          receiverId: receiver.userId,
          type: type,
        );
    if (call != null && mounted) {
      context.push('/call/${call.id}');
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Message bubble ─────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showAvatar,
    required this.isGrouped,
    required this.onReply,
    required this.onReact,
    this.onDelete,
  });

  final MessageModel message;
  final bool showAvatar;
  final bool isGrouped;
  final VoidCallback onReply;
  final void Function(String emoji) onReact;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isMe = message.isCurrentUser;

    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: Padding(
        padding: EdgeInsets.only(
          top: isGrouped ? 2 : 8,
          bottom: 2,
          left: isMe ? 60 : 0,
          right: isMe ? 0 : 60,
        ),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Other user avatar ──────────────────────────────
            if (!isMe)
              SizedBox(
                width: 34,
                child: showAvatar
                    ? ClipOval(
                        child: message.senderAvatar != null
                            ? CachedNetworkImage(
                                imageUrl: message.senderAvatar!,
                                width: 30,
                                height: 30,
                                fit: BoxFit.cover)
                            : Container(
                                width: 30,
                                height: 30,
                                color: AppColors.primary.withValues(alpha:0.6),
                                child: Center(
                                  child: Text(
                                    (message.senderName ?? '?')[0]
                                        .toUpperCase(),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                      )
                    : null,
              ),

            const SizedBox(width: 4),

            // ── Bubble ─────────────────────────────────────────
            Flexible(
              child: Column(
                crossAxisAlignment: isMe
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  // Sender name (group only)
                  if (!isMe && !isGrouped && message.senderName != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: Text(
                        message.senderName!,
                        style: AppTextStyles.overline.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600),
                      ),
                    ),

                  // Reply preview
                  if (message.replyTo != null)
                    _ReplyPreviewChip(reply: message.replyTo!),

                  // Bubble itself
                  Container(
                    padding: _bubblePadding(message.type),
                    decoration: BoxDecoration(
                      color: _bubbleColor(isMe, message),
                      borderRadius: _bubbleRadius(isMe, isGrouped),
                    ),
                    child: message.isDeleted
                        ? Text(
                            'This message was deleted',
                            style: AppTextStyles.captionText.copyWith(
                              color: AppColors.textMuted,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : _BubbleContent(message: message),
                  ),

                  // Reactions row
                  if (message.reactions.isNotEmpty)
                    _ReactionsRow(reactions: message.reactions),

                  // Timestamp + status
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DateFormat.jm().format(message.createdAt),
                          style: AppTextStyles.overline
                              .copyWith(color: AppColors.textMuted),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          _StatusIcon(status: message.status),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  EdgeInsets _bubblePadding(MessageType t) {
    if (t == MessageType.image || t == MessageType.video) {
      return EdgeInsets.zero;
    }
    return const EdgeInsets.symmetric(horizontal: 12, vertical: 8);
  }

  Color _bubbleColor(bool isMe, MessageModel msg) {
    if (msg.type == MessageType.callLog) return AppColors.darkSurface2;
    if (isMe) return AppColors.primary;
    return AppColors.darkSurface;
  }

  BorderRadius _bubbleRadius(bool isMe, bool isGrouped) {
    const r = Radius.circular(18);
    const small = Radius.circular(4);
    if (isMe) {
      return BorderRadius.only(
        topLeft: r,
        topRight: r,
        bottomLeft: r,
        bottomRight: isGrouped ? r : small,
      );
    } else {
      return BorderRadius.only(
        topLeft: isGrouped ? r : small,
        topRight: r,
        bottomLeft: r,
        bottomRight: r,
      );
    }
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Emoji reactions
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['❤️', '😂', '😮', '😢', '🙏', '👍']
                    .map(
                      (e) => GestureDetector(
                        onTap: () {
                          Navigator.pop(context);
                          onReact(e);
                        },
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    )
                    .toList(),
              ),
            ),
            const Divider(color: AppColors.darkDivider, height: 1),
            ListTile(
              leading: const Icon(Icons.reply, color: AppColors.textDarkPrimary),
              title: Text('Reply',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textDarkPrimary)),
              onTap: () {
                Navigator.pop(context);
                onReply();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: AppColors.textDarkPrimary),
              title: Text('Copy',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textDarkPrimary)),
              onTap: () {
                Navigator.pop(context);
                if (message.content != null) {
                  Clipboard.setData(
                      ClipboardData(text: message.content!));
                }
              },
            ),
            if (onDelete != null)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.error),
                title: Text('Delete',
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.error)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

// ── Bubble content (switches on type) ─────────────────────────────

class _BubbleContent extends StatelessWidget {
  const _BubbleContent({required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: CachedNetworkImage(
            imageUrl: message.mediaUrl!,
            width: 220,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              width: 220,
              height: 160,
              color: AppColors.darkSurface2,
              child: const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2)),
            ),
          ),
        );

      case MessageType.audio:
        return _VoiceNoteBubble(message: message);

      case MessageType.callLog:
        return _CallLogBubble(message: message);

      default:
        return Text(
          message.content ?? '',
          style: AppTextStyles.bodyMedium.copyWith(
            color: message.isCurrentUser
                ? Colors.white
                : AppColors.textDarkPrimary,
          ),
        );
    }
  }
}

// ── Voice note bubble ──────────────────────────────────────────────

class _VoiceNoteBubble extends StatelessWidget {
  const _VoiceNoteBubble({required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.play_arrow_rounded,
          color: message.isCurrentUser
              ? Colors.white
              : AppColors.textDarkPrimary,
          size: 28,
        ),
        const SizedBox(width: 8),
        Container(
          width: 120,
          height: 3,
          decoration: BoxDecoration(
            color: (message.isCurrentUser ? Colors.white : AppColors.primary)
                .withValues(alpha:0.5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '0:12',
          style: AppTextStyles.captionText.copyWith(
            color: message.isCurrentUser
                ? Colors.white70
                : AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Call log bubble ────────────────────────────────────────────────

class _CallLogBubble extends StatelessWidget {
  const _CallLogBubble({required this.message});

  final MessageModel message;

  @override
  Widget build(BuildContext context) {
    final isVideo = message.callType == 'video';
    final isMissed = message.callStatus == 'missed';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isVideo ? Icons.videocam : Icons.call,
          color: isMissed ? AppColors.error : AppColors.success,
          size: 20,
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMissed
                  ? 'Missed ${isVideo ? 'video' : 'audio'} call'
                  : '${isVideo ? 'Video' : 'Audio'} call',
              style: AppTextStyles.captionText.copyWith(
                  color: AppColors.textDarkPrimary,
                  fontWeight: FontWeight.w600),
            ),
            if (message.callDuration != null && message.callDuration! > 0)
              Text(
                _formatDuration(message.callDuration!),
                style: AppTextStyles.overline
                    .copyWith(color: AppColors.textMuted),
              ),
          ],
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m}m ${s}s';
  }
}

// ── Reply preview chip ─────────────────────────────────────────────

class _ReplyPreviewChip extends StatelessWidget {
  const _ReplyPreviewChip({required this.reply});

  final ReplyPreview reply;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.darkBackground.withValues(alpha:0.6),
        borderRadius: BorderRadius.circular(8),
        border: const Border(
            left: BorderSide(color: AppColors.primary, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reply.senderName ?? 'Unknown',
            style: AppTextStyles.overline.copyWith(
                color: AppColors.primary, fontWeight: FontWeight.w700),
          ),
          Text(
            reply.content ?? reply.type.name,
            style: AppTextStyles.captionText
                .copyWith(color: AppColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Reactions row ──────────────────────────────────────────────────

class _ReactionsRow extends StatelessWidget {
  const _ReactionsRow({required this.reactions});

  final Map<String, List<String>> reactions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: reactions.entries.map((e) {
          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.darkSurface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.key, style: const TextStyle(fontSize: 13)),
                if (e.value.length > 1) ...[
                  const SizedBox(width: 3),
                  Text(
                    '${e.value.length}',
                    style: AppTextStyles.overline
                        .copyWith(color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Status icon ────────────────────────────────────────────────────

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final MessageStatus status;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
                color: AppColors.textMuted, strokeWidth: 1.5));
      case MessageStatus.failed:
        return const Icon(Icons.error_outline,
            size: 12, color: AppColors.error);
      case MessageStatus.read:
        return const Icon(Icons.done_all,
            size: 12, color: AppColors.primary);
      case MessageStatus.delivered:
        return const Icon(Icons.done_all,
            size: 12, color: AppColors.textMuted);
      default:
        return const Icon(Icons.done, size: 12, color: AppColors.textMuted);
    }
  }
}

// ── Date divider ───────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateDay = DateTime(date.year, date.month, date.day);
    String label;
    if (dateDay == today) {
      label = 'Today';
    } else if (dateDay == yesterday) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(
              child: Divider(color: AppColors.darkDivider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: AppTextStyles.overline
                  .copyWith(color: AppColors.textMuted),
            ),
          ),
          const Expanded(
              child: Divider(color: AppColors.darkDivider)),
        ],
      ),
    );
  }
}

// ── Typing indicator ───────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator(this.users);

  final List<String> users;

  @override
  Widget build(BuildContext context) {
    final label = users.length == 1
        ? '${users.first} is typing…'
        : '${users.join(', ')} are typing…';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: AppTextStyles.captionText.copyWith(
            color: AppColors.textMuted, fontStyle: FontStyle.italic),
      ),
    );
  }
}

// ── Reply banner ───────────────────────────────────────────────────

class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.message, required this.onDismiss});

  final MessageModel message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.reply, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Container(
            width: 3,
            height: 36,
            color: AppColors.primary,
            margin: const EdgeInsets.only(right: 8),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.senderName ?? 'You',
                  style: AppTextStyles.captionText.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  message.displayText,
                  style: AppTextStyles.captionText
                      .copyWith(color: AppColors.textMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close,
                color: AppColors.textDarkSecondary, size: 18),
          ),
        ],
      ),
    );
  }
}

// ── Input bar ──────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.isSending,
    required this.onChanged,
    required this.onSend,
    required this.onPickMedia,
  });

  final TextEditingController controller;
  final bool isSending;
  final void Function(String) onChanged;
  final VoidCallback onSend;
  final VoidCallback onPickMedia;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.darkSurface,
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Attachment
          IconButton(
            icon: const Icon(Icons.attach_file,
                color: AppColors.textDarkSecondary),
            onPressed: onPickMedia,
          ),

          // Text field
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: AppColors.darkBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: TextField(
                controller: controller,
                maxLines: null,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textDarkPrimary),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  hintStyle: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textMuted),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined,
                        color: AppColors.textDarkSecondary, size: 20),
                    onPressed: () {},
                  ),
                ),
                onChanged: onChanged,
                textInputAction: TextInputAction.newline,
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Send button
          GestureDetector(
            onTap: onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: isSending
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty conversation ─────────────────────────────────────────────

class _EmptyConvo extends StatelessWidget {
  const _EmptyConvo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.waving_hand_outlined,
              size: 48, color: AppColors.textDarkTertiary),
          const SizedBox(height: 16),
          Text(
            'Say hello!',
            style: AppTextStyles.bodyLarge.copyWith(
                color: AppColors.textDarkSecondary,
                fontWeight: FontWeight.w600),
          ),
          Text(
            'Send the first message.',
            style: AppTextStyles.captionText
                .copyWith(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

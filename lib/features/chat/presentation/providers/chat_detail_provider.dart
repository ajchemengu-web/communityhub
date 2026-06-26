import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/chat_repository.dart';
import '../../domain/models/message_model.dart';

// ── State ──────────────────────────────────────────────────────────

class ChatDetailState {
  const ChatDetailState({
    this.messages = const [],
    this.isLoading = true,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.isSending = false,
    this.replyTo,
    this.errorMessage,
    this.typingUsers = const [],
  });

  final List<MessageModel> messages;
  final bool isLoading;
  final bool hasMore;
  final bool isLoadingMore;
  final bool isSending;
  final MessageModel? replyTo;
  final String? errorMessage;
  final List<String> typingUsers; // display names

  ChatDetailState copyWith({
    List<MessageModel>? messages,
    bool? isLoading,
    bool? hasMore,
    bool? isLoadingMore,
    bool? isSending,
    MessageModel? replyTo,
    bool clearReply = false,
    String? errorMessage,
    List<String>? typingUsers,
  }) =>
      ChatDetailState(
        messages: messages ?? this.messages,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        isSending: isSending ?? this.isSending,
        replyTo: clearReply ? null : (replyTo ?? this.replyTo),
        errorMessage: errorMessage ?? this.errorMessage,
        typingUsers: typingUsers ?? this.typingUsers,
      );
}

// ── Notifier ───────────────────────────────────────────────────────

class ChatDetailNotifier extends StateNotifier<ChatDetailState> {
  ChatDetailNotifier(this.conversationId)
      : super(const ChatDetailState()) {
    _load();
    _subscribeToMessages();
    _subscribeToTyping();
  }

  final String conversationId;
  final _repo = ChatRepository.instance;
  static const _pageSize = 30;

  RealtimeChannel? _messageChannel;
  RealtimeChannel? _typingChannel;
  Timer? _typingTimer;

  Future<void> _load() async {
    try {
      final msgs = await _repo.fetchMessages(
          conversationId, limit: _pageSize);
      state = state.copyWith(
        messages: msgs,
        hasMore: msgs.length >= _pageSize,
        isLoading: false,
      );
      await _repo.markAsRead(conversationId);
    } catch (e) {
      state =
          state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void _subscribeToMessages() {
    _messageChannel = SupabaseService.client
        .channel('chat_messages_$conversationId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: FilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) async {
            final uid = SupabaseService.currentUserId ?? '';
            final row =
                Map<String, dynamic>.from(payload.newRecord);

            // Don't re-add messages the current user already sent optimistically
            if (row['sender_id'] == uid) return;

            // Fetch with profile join
            try {
              final full = await SupabaseService.client
                  .from('messages')
                  .select(
                      'id, conversation_id, sender_id, content, type, media_url, media_thumbnail_url, reply_to_id, is_deleted, reactions, call_type, call_duration, call_status, created_at, profiles!sender_id(full_name, username, avatar_url)')
                  .eq('id', row['id'] as String)
                  .single() as Map<String, dynamic>;

              final msg = MessageModel.fromMap(full, currentUserId: uid);
              state = state.copyWith(
                  messages: [...state.messages, msg]);
              await _repo.markAsRead(conversationId);
            } catch (_) {}
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: FilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (payload) {
            final uid = SupabaseService.currentUserId ?? '';
            final row =
                Map<String, dynamic>.from(payload.newRecord);
            final msgId = row['id'] as String;

            final updated =
                state.messages.map((m) {
              if (m.id != msgId) return m;
              // Re-parse just the changed fields
              final isDeleted = (row['is_deleted'] as bool?) ?? false;
              Map<String, List<String>> reactions = m.reactions;
              final rawReactions = row['reactions'];
              if (rawReactions is Map) {
                reactions = rawReactions.map(
                  (k, v) => MapEntry(
                    k as String,
                    (v as List).map((e) => e as String).toList(),
                  ),
                );
              }
              return m.copyWith(
                  isDeleted: isDeleted, reactions: reactions);
            }).toList();

            state = state.copyWith(messages: updated);
          },
        )
        .subscribe();
  }

  void _subscribeToTyping() {
    _typingChannel = SupabaseService.client
        .channel('typing_$conversationId')
        .onBroadcast(
          event: 'typing',
          callback: (payload) {
            final uid = SupabaseService.currentUserId;
            final senderId = payload['user_id'] as String?;
            if (senderId == null || senderId == uid) return;
            final name = payload['name'] as String? ?? 'Someone';
            final isTyping = payload['typing'] as bool? ?? false;

            final list = List<String>.from(state.typingUsers);
            if (isTyping && !list.contains(name)) {
              list.add(name);
            } else if (!isTyping) {
              list.remove(name);
            }
            state = state.copyWith(typingUsers: list);
          },
        )
        .subscribe();
  }

  // ── Load older messages ────────────────────────────────────

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final cursor = state.messages.isNotEmpty
          ? state.messages.first.createdAt
          : null;
      final older = await _repo.fetchMessages(
        conversationId,
        limit: _pageSize,
        cursor: cursor,
      );
      state = state.copyWith(
        messages: [...older, ...state.messages],
        hasMore: older.length >= _pageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  // ── Send text message ──────────────────────────────────────

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final uid = SupabaseService.currentUserId!;
    state = state.copyWith(isSending: true);

    // Optimistic: add a "sending" bubble
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final optimistic = MessageModel(
      id: tempId,
      conversationId: conversationId,
      senderId: uid,
      createdAt: DateTime.now(),
      content: text.trim(),
      status: MessageStatus.sending,
      isCurrentUser: true,
      replyTo: state.replyTo != null
          ? ReplyPreview(
              id: state.replyTo!.id,
              senderId: state.replyTo!.senderId,
              senderName: state.replyTo!.senderName,
              content: state.replyTo!.content,
              type: state.replyTo!.type,
            )
          : null,
    );

    state = state.copyWith(
      messages: [...state.messages, optimistic],
      isSending: false,
      clearReply: true,
    );

    try {
      final sent = await _repo.sendMessage(
        conversationId: conversationId,
        content: text.trim(),
        replyToId: optimistic.replyTo?.id,
      );

      // Replace optimistic with real message
      final msgs = state.messages
          .map((m) => m.id == tempId ? sent : m)
          .toList();
      state = state.copyWith(messages: msgs);
    } catch (_) {
      // Mark as failed
      final msgs = state.messages.map((m) {
        return m.id == tempId ? m.copyWith(status: MessageStatus.failed) : m;
      }).toList();
      state = state.copyWith(messages: msgs);
    }
  }

  // ── Send media ─────────────────────────────────────────────

  Future<void> sendMediaMessage(File file, MessageType type) async {
    final uid = SupabaseService.currentUserId!;
    state = state.copyWith(isSending: true);

    try {
      final url = await _repo.uploadChatMedia(file, conversationId);
      final msg = await _repo.sendMessage(
        conversationId: conversationId,
        content: '',
        type: type,
        mediaUrl: url,
      );

      state = state.copyWith(
          messages: [...state.messages, msg], isSending: false);
    } catch (e) {
      state = state.copyWith(
          isSending: false, errorMessage: e.toString());
    }
  }

  // ── Reactions ──────────────────────────────────────────────

  Future<void> toggleReaction(MessageModel message, String emoji) async {
    final updated = await _repo.toggleReaction(
        message.id, message.reactions, emoji);

    final msgs = state.messages.map((m) {
      return m.id == message.id ? m.copyWith(reactions: updated) : m;
    }).toList();
    state = state.copyWith(messages: msgs);
  }

  // ── Reply ──────────────────────────────────────────────────

  void setReplyTo(MessageModel? msg) =>
      state = msg == null
          ? state.copyWith(clearReply: true)
          : state.copyWith(replyTo: msg);

  // ── Delete ─────────────────────────────────────────────────

  Future<void> deleteMessage(String messageId) async {
    await _repo.deleteMessage(messageId);
    // Realtime will update state via subscription
  }

  // ── Typing broadcast ───────────────────────────────────────

  void broadcastTyping(bool isTyping) {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    _typingChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': uid, 'typing': isTyping, 'name': 'You'},
    );

    if (isTyping) {
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 3), () {
        broadcastTyping(false);
      });
    }
  }

  @override
  void dispose() {
    _messageChannel?.unsubscribe();
    _typingChannel?.unsubscribe();
    _typingTimer?.cancel();
    super.dispose();
  }
}

// ── Providers ──────────────────────────────────────────────────────

final chatDetailProvider = StateNotifierProvider.autoDispose.family<
    ChatDetailNotifier, ChatDetailState, String>(
  (_, conversationId) => ChatDetailNotifier(conversationId),
);

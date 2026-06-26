import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/chat_repository.dart';
import '../../domain/models/conversation_model.dart';

// ── State ──────────────────────────────────────────────────────────

class ChatsState {
  const ChatsState({
    this.conversations = const [],
    this.isLoading = true,
    this.searchQuery = '',
    this.errorMessage,
  });

  final List<ConversationModel> conversations;
  final bool isLoading;
  final String searchQuery;
  final String? errorMessage;

  int get totalUnread =>
      conversations.fold(0, (sum, c) => sum + c.unreadCount);

  List<ConversationModel> get filtered {
    if (searchQuery.isEmpty) return conversations;
    final q = searchQuery.toLowerCase();
    return conversations
        .where((c) =>
            c.displayName.toLowerCase().contains(q) ||
            (c.lastMessage?.toLowerCase().contains(q) ?? false))
        .toList();
  }

  ChatsState copyWith({
    List<ConversationModel>? conversations,
    bool? isLoading,
    String? searchQuery,
    String? errorMessage,
  }) =>
      ChatsState(
        conversations: conversations ?? this.conversations,
        isLoading: isLoading ?? this.isLoading,
        searchQuery: searchQuery ?? this.searchQuery,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────────

class ChatsNotifier extends StateNotifier<ChatsState> {
  ChatsNotifier() : super(const ChatsState()) {
    _load();
    _subscribeToNewMessages();
  }

  final _repo = ChatRepository.instance;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    try {
      final convos = await _repo.fetchConversations();
      state = state.copyWith(conversations: convos, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  void _subscribeToNewMessages() {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    // Listen for any new message inserts
    _channel = SupabaseService.client
        .channel('chats_messages_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          callback: (payload) {
            final row = payload.newRecord;
            final convoId = row['conversation_id'] as String?;
            if (convoId == null) return;

            // Refresh just that conversation's last_message preview
            _updateConversationPreview(
              convoId: convoId,
              lastMessage: row['content'] as String? ?? '',
              lastMessageAt: row['created_at'] as String?,
              senderId: row['sender_id'] as String?,
            );
          },
        )
        .subscribe();
  }

  void _updateConversationPreview({
    required String convoId,
    required String lastMessage,
    String? lastMessageAt,
    String? senderId,
  }) {
    final list = List<ConversationModel>.from(state.conversations);
    final idx = list.indexWhere((c) => c.id == convoId);
    if (idx == -1) {
      // Unknown conversation — full refresh
      refresh();
      return;
    }

    final uid = SupabaseService.currentUserId;
    final isFromMe = senderId == uid;

    final updated = list[idx].copyWith(
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt != null
          ? DateTime.tryParse(lastMessageAt)
          : null,
      lastMessageSenderId: senderId,
      unreadCount: isFromMe
          ? list[idx].unreadCount
          : list[idx].unreadCount + 1,
    );

    list.removeAt(idx);
    list.insert(0, updated); // Bubble to top
    state = state.copyWith(conversations: list);
  }

  /// Called when the user opens a chat — clear unread badge
  void markConversationRead(String conversationId) {
    final list = List<ConversationModel>.from(state.conversations);
    final idx = list.indexWhere((c) => c.id == conversationId);
    if (idx == -1) return;
    list[idx] = list[idx].copyWith(unreadCount: 0);
    state = state.copyWith(conversations: list);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true);
    await _load();
  }

  void setSearch(String q) => state = state.copyWith(searchQuery: q);

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

// ── Providers ──────────────────────────────────────────────────────

final chatsProvider =
    StateNotifierProvider.autoDispose<ChatsNotifier, ChatsState>(
  (_) => ChatsNotifier(),
);

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
    this.hasMore = true,
    this.isLoadingMore = false,
    this.searchQuery = '',
    this.errorMessage,
  });

  final List<ConversationModel> conversations;
  final bool isLoading;
  final bool hasMore;
  final bool isLoadingMore;
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
    bool? hasMore,
    bool? isLoadingMore,
    String? searchQuery,
    String? errorMessage,
  }) =>
      ChatsState(
        conversations: conversations ?? this.conversations,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
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
  static const _pageSize = 30;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    try {
      final convos = await _repo.fetchConversations(limit: _pageSize);
      state = state.copyWith(
        conversations: convos,
        hasMore: convos.length >= _pageSize,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final cursor = state.conversations.isNotEmpty
          ? state.conversations.last.lastMessageAt
          : null;
      final older = await _repo.fetchConversations(
        limit: _pageSize,
        cursor: cursor,
      );
      state = state.copyWith(
        conversations: [...state.conversations, ...older],
        hasMore: older.length >= _pageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  void _subscribeToNewMessages() {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

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
      refresh();
      return;
    }

    final uid = SupabaseService.currentUserId;
    final isFromMe = senderId == uid;

    final updated = list[idx].copyWith(
      lastMessage: lastMessage,
      lastMessageAt:
          lastMessageAt != null ? DateTime.tryParse(lastMessageAt) : null,
      lastMessageSenderId: senderId,
      unreadCount: isFromMe ? list[idx].unreadCount : list[idx].unreadCount + 1,
    );

    list.removeAt(idx);
    list.insert(0, updated);
    state = state.copyWith(conversations: list);
  }

  void markConversationRead(String conversationId) {
    final list = List<ConversationModel>.from(state.conversations);
    final idx = list.indexWhere((c) => c.id == conversationId);
    if (idx == -1) return;
    list[idx] = list[idx].copyWith(unreadCount: 0);
    state = state.copyWith(conversations: list);
  }

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, hasMore: true);
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

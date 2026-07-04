import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_service.dart';
import '../../data/notifications_repository.dart';
import '../../domain/models/notification_model.dart';

// ── State ──────────────────────────────────────────────────────────

class NotificationsState {
  const NotificationsState({
    this.notifications = const [],
    this.isLoading = true,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  final List<NotificationModel> notifications;
  final bool isLoading;
  final bool hasMore;
  final bool isLoadingMore;
  final String? errorMessage;

  int get unreadCount =>
      notifications.where((n) => !n.isRead).length;

  bool get hasUnread => unreadCount > 0;

  /// Group notifications into Today / Yesterday / Earlier
  Map<String, List<NotificationModel>> get grouped {
    final today = <NotificationModel>[];
    final yesterday = <NotificationModel>[];
    final earlier = <NotificationModel>[];

    for (final n in notifications) {
      if (n.isToday) {
        today.add(n);
      } else if (n.isYesterday) {
        yesterday.add(n);
      } else {
        earlier.add(n);
      }
    }

    return {
      if (today.isNotEmpty) 'Today': today,
      if (yesterday.isNotEmpty) 'Yesterday': yesterday,
      if (earlier.isNotEmpty) 'Earlier': earlier,
    };
  }

  NotificationsState copyWith({
    List<NotificationModel>? notifications,
    bool? isLoading,
    bool? hasMore,
    bool? isLoadingMore,
    String? errorMessage,
  }) =>
      NotificationsState(
        notifications: notifications ?? this.notifications,
        isLoading: isLoading ?? this.isLoading,
        hasMore: hasMore ?? this.hasMore,
        isLoadingMore: isLoadingMore ?? this.isLoadingMore,
        errorMessage: errorMessage ?? this.errorMessage,
      );
}

// ── Notifier ───────────────────────────────────────────────────────

class NotificationsNotifier extends StateNotifier<NotificationsState> {
  NotificationsNotifier() : super(const NotificationsState()) {
    _load();
    _subscribeToNew();
  }

  final _repo = NotificationsRepository.instance;
  static const _pageSize = 30;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    try {
      final items = await _repo.fetchNotifications(limit: _pageSize);
      state = state.copyWith(
        notifications: items,
        hasMore: items.length >= _pageSize,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
          isLoading: false, errorMessage: e.toString());
    }
  }

  void _subscribeToNew() {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    _channel = SupabaseService.client
        .channel('notifications_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) async {
            final row =
                Map<String, dynamic>.from(payload.newRecord);
            // Fetch with actor profile
            try {
              final full = await SupabaseService.client
                  .from('notifications')
                  .select('''
                    id, user_id, type, title, body, data, is_read,
                    created_at, actor_id,
                    actor:users!actor_id(full_name, avatar_url)
                  ''')
                  .eq('id', row['id'] as String)
                  .single() as Map<String, dynamic>;

              final notification = NotificationModel.fromMap(full);
              state = state.copyWith(notifications: [
                notification,
                ...state.notifications,
              ]);
            } catch (_) {}
          },
        )
        .subscribe();
  }

  // ── Load more (pagination) ─────────────────────────────────────

  Future<void> loadMore() async {
    if (!state.hasMore || state.isLoadingMore || state.isLoading) return;
    state = state.copyWith(isLoadingMore: true);

    try {
      final cursor = state.notifications.isNotEmpty
          ? state.notifications.last.createdAt
          : null;
      final older = await _repo.fetchNotifications(
          limit: _pageSize, cursor: cursor);
      state = state.copyWith(
        notifications: [...state.notifications, ...older],
        hasMore: older.length >= _pageSize,
        isLoadingMore: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  // ── Mark single as read ────────────────────────────────────────

  Future<void> markRead(String notificationId) async {
    // Optimistic
    state = state.copyWith(
      notifications: state.notifications.map((n) {
        return n.id == notificationId ? n.copyWith(isRead: true) : n;
      }).toList(),
    );
    await _repo.markRead(notificationId);
  }

  // ── Mark all as read ───────────────────────────────────────────

  Future<void> markAllRead() async {
    state = state.copyWith(
      notifications:
          state.notifications.map((n) => n.copyWith(isRead: true)).toList(),
    );
    await _repo.markAllRead();
  }

  // ── Delete ─────────────────────────────────────────────────────

  Future<void> deleteNotification(String notificationId) async {
    state = state.copyWith(
      notifications: state.notifications
          .where((n) => n.id != notificationId)
          .toList(),
    );
    await _repo.deleteNotification(notificationId);
  }

  Future<void> refresh() => _load();

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }
}

// ── Provider ───────────────────────────────────────────────────────

/// NOT autoDispose — persists across navigation so unread badge stays live.
final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, NotificationsState>(
  (_) => NotificationsNotifier(),
);

/// Convenience provider for the badge count only.
final unreadNotificationsCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).unreadCount,
);

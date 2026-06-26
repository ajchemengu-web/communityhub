import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/notification_model.dart';
import '../providers/notifications_provider.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        title: Text('Notifications', style: AppTextStyles.titleLarge),
        actions: [
          if (state.hasUnread)
            TextButton(
              onPressed: () =>
                  ref.read(notificationsProvider.notifier).markAllRead(),
              child: Text(
                'Mark all read',
                style: AppTextStyles.labelMedium
                    .copyWith(color: AppColors.primary),
              ),
            ),
        ],
      ),
      body: state.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : state.notifications.isEmpty
              ? const _EmptyState()
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.darkSurface,
                  onRefresh: () =>
                      ref.read(notificationsProvider.notifier).refresh(),
                  child: _GroupedList(state: state),
                ),
    );
  }
}

// ── Grouped list ───────────────────────────────────────────────────

class _GroupedList extends ConsumerWidget {
  const _GroupedList({required this.state});
  final NotificationsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = state.grouped;
    final groups = grouped.entries.toList();

    return ListView.builder(
      itemCount: groups.length + (state.isLoadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == groups.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child:
                  CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final entry = groups[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GroupHeader(label: entry.key),
            ...entry.value.map((n) => _NotificationTile(notification: n)),
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: AppTextStyles.labelMedium
            .copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

// ── Notification tile ──────────────────────────────────────────────

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.notification});
  final NotificationModel notification;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withOpacity(0.8),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => ref
          .read(notificationsProvider.notifier)
          .deleteNotification(notification.id),
      child: InkWell(
        onTap: () => _handleTap(context, ref),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          color: notification.isRead
              ? Colors.transparent
              : AppColors.primary.withOpacity(0.07),
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar with type badge
              _NotifAvatar(notification: notification),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          if (notification.actorName != null)
                            TextSpan(
                              text: '${notification.actorName} ',
                              style: AppTextStyles.bodyMedium
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          TextSpan(
                            text: notification.title,
                            style: AppTextStyles.bodyMedium.copyWith(
                              fontWeight: notification.isRead
                                  ? FontWeight.normal
                                  : FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (notification.body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notification.body,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.textSecondary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      timeago.format(notification.createdAt),
                      style: AppTextStyles.caption
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              // Unread dot
              if (!notification.isRead)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    // Mark as read
    if (!notification.isRead) {
      ref
          .read(notificationsProvider.notifier)
          .markRead(notification.id);
    }

    // Navigate based on type
    final data = notification.data;
    switch (notification.type) {
      case NotificationType.message:
        final convoId = data['conversation_id'] as String?;
        if (convoId != null) context.push('/chat/$convoId');
        break;
      case NotificationType.postLike:
      case NotificationType.postComment:
        final postId = data['post_id'] as String?;
        if (postId != null) context.push('/post/$postId');
        break;
      case NotificationType.eventRsvp:
        final eventId = data['event_id'] as String?;
        if (eventId != null) context.push('/events/$eventId');
        break;
      case NotificationType.communityJoin:
        final communityId = data['community_id'] as String?;
        if (communityId != null) context.push('/community/$communityId');
        break;
      case NotificationType.missedCall:
        // Could open chat or show missed call info
        final convoId = data['conversation_id'] as String?;
        if (convoId != null) context.push('/chat/$convoId');
        break;
      case NotificationType.prayerRequest:
        // Navigate to my church screen
        context.push('/my-church');
        break;
      case NotificationType.general:
        break;
    }
  }
}

// ── Notification avatar ────────────────────────────────────────────

class _NotifAvatar extends StatelessWidget {
  const _NotifAvatar({required this.notification});
  final NotificationModel notification;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Actor avatar
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.darkSurface,
          backgroundImage: notification.actorAvatar != null
              ? CachedNetworkImageProvider(notification.actorAvatar!)
              : null,
          child: notification.actorAvatar == null
              ? Text(
                  _initial,
                  style: AppTextStyles.titleSmall,
                )
              : null,
        ),
        // Type badge
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _badgeColor,
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.darkBackground, width: 1.5),
            ),
            child: Icon(_badgeIcon, size: 11, color: Colors.white),
          ),
        ),
      ],
    );
  }

  String get _initial {
    final name = notification.actorName ?? notification.title;
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color get _badgeColor {
    switch (notification.type) {
      case NotificationType.message:
        return AppColors.primary;
      case NotificationType.postLike:
        return Colors.pink;
      case NotificationType.postComment:
        return Colors.blue;
      case NotificationType.prayerRequest:
        return AppColors.gold;
      case NotificationType.eventRsvp:
        return Colors.green;
      case NotificationType.communityJoin:
        return Colors.purple;
      case NotificationType.missedCall:
        return Colors.red;
      case NotificationType.general:
        return AppColors.textSecondary;
    }
  }

  IconData get _badgeIcon {
    switch (notification.type) {
      case NotificationType.message:
        return Icons.chat_bubble_outline;
      case NotificationType.postLike:
        return Icons.favorite;
      case NotificationType.postComment:
        return Icons.comment_outlined;
      case NotificationType.prayerRequest:
        return Icons.volunteer_activism;
      case NotificationType.eventRsvp:
        return Icons.event_available;
      case NotificationType.communityJoin:
        return Icons.group_add;
      case NotificationType.missedCall:
        return Icons.call_missed;
      case NotificationType.general:
        return Icons.notifications_outlined;
    }
  }
}

// ── Empty state ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.notifications_none_outlined,
              size: 40,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "You're all caught up!",
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            "New activity will appear here",
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

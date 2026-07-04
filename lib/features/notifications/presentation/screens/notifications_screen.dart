import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/notification_model.dart';
import '../providers/notifications_provider.dart';

// ── Filter ─────────────────────────────────────────────────────────

enum _Filter { all, likes, comments, follows, mentions }

extension _FilterLabel on _Filter {
  String get label {
    switch (this) {
      case _Filter.all:
        return 'All';
      case _Filter.likes:
        return 'Likes';
      case _Filter.comments:
        return 'Comments';
      case _Filter.follows:
        return 'Follows';
      case _Filter.mentions:
        return 'Mentions';
    }
  }
}

// ── Screen ─────────────────────────────────────────────────────────

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends ConsumerState<NotificationsScreen> {
  _Filter _activeFilter = _Filter.all;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(notificationsProvider.notifier).loadMore();
    }
  }

  List<NotificationModel> _filtered(List<NotificationModel> all) {
    switch (_activeFilter) {
      case _Filter.all:
        return all;
      case _Filter.likes:
        return all
            .where((n) =>
                n.type == NotificationType.postLike ||
                n.type == NotificationType.commentLike)
            .toList();
      case _Filter.comments:
        return all
            .where((n) => n.type == NotificationType.postComment)
            .toList();
      case _Filter.follows:
        return all
            .where((n) => n.type == NotificationType.follow)
            .toList();
      case _Filter.mentions:
        // No dedicated mention type yet — show general notifications
        return all
            .where((n) => n.type == NotificationType.general)
            .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsProvider);
    final filtered = _filtered(state.notifications);

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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: _FilterBar(
            active: _activeFilter,
            onChanged: (f) => setState(() => _activeFilter = f),
          ),
        ),
      ),
      body: state.isLoading
          ? const Center(
              child:
                  CircularProgressIndicator(color: AppColors.primary))
          : filtered.isEmpty
              ? RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.darkSurface,
                  onRefresh: () =>
                      ref.read(notificationsProvider.notifier).refresh(),
                  child: ListView(
                    children: const [
                      SizedBox(height: 120),
                      _EmptyState(),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.darkSurface,
                  onRefresh: () =>
                      ref.read(notificationsProvider.notifier).refresh(),
                  child: _NotifList(
                    state: state,
                    notifications: filtered,
                    scrollController: _scrollController,
                  ),
                ),
    );
  }
}

// ── Filter bar ─────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.active, required this.onChanged});
  final _Filter active;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: _Filter.values.map((f) {
          final isActive = f == active;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onChanged(f),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.primary
                      : AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  f.label,
                  style: AppTextStyles.labelMedium.copyWith(
                    color: isActive
                        ? Colors.white
                        : AppColors.textSecondary,
                    fontWeight: isActive
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── List ───────────────────────────────────────────────────────────

class _NotifList extends StatelessWidget {
  const _NotifList({
    required this.state,
    required this.notifications,
    required this.scrollController,
  });
  final NotificationsState state;
  final List<NotificationModel> notifications;
  final ScrollController scrollController;

  Map<String, List<NotificationModel>> _grouped() {
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

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();
    final groups = grouped.entries.toList();

    return ListView.builder(
      controller: scrollController,
      itemCount: groups.length + (state.isLoadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == groups.length) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        final entry = groups[i];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _GroupHeader(label: entry.key),
            ...entry.value
                .map((n) => _NotificationTile(notification: n)),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
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

  bool get _hasPostThumbnail {
    return (notification.type == NotificationType.postLike ||
            notification.type == NotificationType.postComment ||
            notification.type == NotificationType.commentLike) &&
        notification.data['post_image'] != null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withValues(alpha: 0.85),
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
              : AppColors.primary.withValues(alpha: 0.07),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _NotifAvatar(notification: notification),
              const SizedBox(width: 12),
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
                              style: AppTextStyles.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w700),
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
              // Right side: post thumbnail OR unread dot
              if (_hasPostThumbnail)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl:
                          notification.data['post_image'] as String,
                      width: 52,
                      height: 52,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(
                        width: 52,
                        height: 52,
                        color: AppColors.darkSurface,
                        child: const Icon(
                          Icons.image_not_supported_outlined,
                          size: 20,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                )
              else if (!notification.isRead)
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
    if (!notification.isRead) {
      ref
          .read(notificationsProvider.notifier)
          .markRead(notification.id);
    }

    final data = notification.data;
    switch (notification.type) {
      case NotificationType.message:
        final convoId = data['conversation_id'] as String?;
        if (convoId != null) context.push('/chat/$convoId');
        break;
      case NotificationType.postLike:
      case NotificationType.postComment:
      case NotificationType.commentLike:
        final postId = data['post_id'] as String?;
        if (postId != null) context.push('/post/$postId');
        break;
      case NotificationType.follow:
        final actorId = notification.actorId;
        if (actorId != null) context.push('/user/$actorId');
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
        final convoId = data['conversation_id'] as String?;
        if (convoId != null) context.push('/chat/$convoId');
        break;
      case NotificationType.prayerRequest:
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
        CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.darkSurface,
          backgroundImage: notification.actorAvatar != null
              ? CachedNetworkImageProvider(notification.actorAvatar!)
              : null,
          child: notification.actorAvatar == null
              ? Text(_initial, style: AppTextStyles.titleSmall)
              : null,
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: _badgeColor,
              shape: BoxShape.circle,
              border:
                  Border.all(color: AppColors.darkBackground, width: 1.5),
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
      case NotificationType.commentLike:
        return Colors.pink;
      case NotificationType.postComment:
        return Colors.blue;
      case NotificationType.follow:
        return Colors.green;
      case NotificationType.prayerRequest:
        return AppColors.gold;
      case NotificationType.eventRsvp:
        return Colors.orange;
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
      case NotificationType.commentLike:
        return Icons.favorite;
      case NotificationType.postComment:
        return Icons.comment_outlined;
      case NotificationType.follow:
        return Icons.person_add_outlined;
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
            decoration: const BoxDecoration(
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
          Text("You're all caught up!", style: AppTextStyles.titleMedium),
          const SizedBox(height: 8),
          Text(
            'New activity will appear here',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

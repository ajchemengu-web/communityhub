import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/event_model.dart';
import '../providers/events_provider.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(eventsProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            backgroundColor: AppColors.darkBackground,
            pinned: true,
            title: Text('Events', style: AppTextStyles.titleLarge),
            actions: [
              IconButton(
                icon: const Icon(Icons.add, color: AppColors.primary),
                onPressed: () => context.push('/events/create'),
                tooltip: 'Create Event',
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(92),
              child: Column(
                children: [
                  _TypeFilterRow(state: state),
                  TabBar(
                    controller: _tabs,
                    indicatorColor: AppColors.primary,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondary,
                    labelStyle: AppTextStyles.labelMedium
                        .copyWith(fontWeight: FontWeight.w600),
                    tabs: const [
                      Tab(text: 'Upcoming'),
                      Tab(text: 'My Events'),
                      Tab(text: 'Past'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
        body: state.isLoading
            ? const _LoadingShimmer()
            : TabBarView(
                controller: _tabs,
                children: [
                  _EventList(
                    events: state.filteredUpcoming,
                    emptyMessage: 'No upcoming events',
                    emptyIcon: Icons.event_outlined,
                  ),
                  _EventList(
                    events: state.myEvents,
                    emptyMessage: "You haven't RSVPed to any events",
                    emptyIcon: Icons.bookmark_outline,
                  ),
                  _EventList(
                    events: state.filteredPast,
                    emptyMessage: 'No past events',
                    emptyIcon: Icons.history,
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Type filter chips ──────────────────────────────────────────────

class _TypeFilterRow extends ConsumerWidget {
  const _TypeFilterRow({required this.state});
  final EventsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const types = [
      (null, 'All'),
      (EventType.service, 'Service'),
      (EventType.study, 'Study'),
      (EventType.outreach, 'Outreach'),
      (EventType.social, 'Social'),
    ];

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: types.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (type, label) = types[i];
          final selected = state.selectedType == type;
          return FilterChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) =>
                ref.read(eventsProvider.notifier).setTypeFilter(type),
            backgroundColor: AppColors.darkSurface,
            selectedColor: AppColors.primary.withOpacity(0.2),
            checkmarkColor: AppColors.primary,
            labelStyle: AppTextStyles.labelMedium.copyWith(
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            side: BorderSide(
              color: selected ? AppColors.primary : AppColors.darkBorder,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          );
        },
      ),
    );
  }
}

// ── Event list ─────────────────────────────────────────────────────

class _EventList extends StatelessWidget {
  const _EventList({
    required this.events,
    required this.emptyMessage,
    required this.emptyIcon,
  });

  final List<EventModel> events;
  final String emptyMessage;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return _EmptyState(message: emptyMessage, icon: emptyIcon);
    }

    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.darkSurface,
      onRefresh: () =>
          // ignore: invalid_use_of_protected_member
          (context as dynamic).findAncestorStateOfType<_EventsScreenState>() !=
                  null
              ? Future.value()
              : Future.value(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: events.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (_, i) => _EventCard(event: events[i]),
      ),
    );
  }
}

// ── Event card ─────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/events/${event.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            _EventCover(event: event),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type + online badge row
                  Row(
                    children: [
                      _TypeBadge(type: event.type),
                      if (event.isOnline) ...[
                        const SizedBox(width: 6),
                        _OnlineBadge(),
                      ],
                      const Spacer(),
                      if (event.userRsvp != null)
                        _RsvpBadge(status: event.userRsvp!),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Title
                  Text(
                    event.title,
                    style: AppTextStyles.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),

                  // Date & time
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    text: _formatDate(event),
                  ),
                  const SizedBox(height: 4),

                  // Location or online
                  _InfoRow(
                    icon: event.isOnline
                        ? Icons.videocam_outlined
                        : Icons.location_on_outlined,
                    text: event.isOnline
                        ? 'Online Event'
                        : (event.location ?? 'No location set'),
                  ),
                  const SizedBox(height: 10),

                  // Community + attendee count
                  Row(
                    children: [
                      if (event.communityName != null) ...[
                        Icon(Icons.group_outlined,
                            size: 14,
                            color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            event.communityName!,
                            style: AppTextStyles.caption
                                .copyWith(color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      Icon(Icons.people_outline,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        '${event.goingCount} going',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
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

  String _formatDate(EventModel event) {
    final df = DateFormat('EEE, MMM d • h:mm a');
    if (event.isToday) {
      return 'Today • ${DateFormat('h:mm a').format(event.startTime)}';
    }
    return df.format(event.startTime);
  }
}

// ── Event cover ────────────────────────────────────────────────────

class _EventCover extends StatelessWidget {
  const _EventCover({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 160,
          width: double.infinity,
          child: event.coverUrl != null
              ? CachedNetworkImage(
                  imageUrl: event.coverUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _PlaceholderCover(event: event),
                )
              : _PlaceholderCover(event: event),
        ),
        // Date badge
        Positioned(
          top: 12,
          left: 12,
          child: _DateBadge(date: event.startTime),
        ),
      ],
    );
  }
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context) {
    final colors = _typeGradient(event.type);
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: colors)),
      child: Center(
        child: Icon(
          _typeIcon(event.type),
          size: 48,
          color: Colors.white.withOpacity(0.5),
        ),
      ),
    );
  }

  List<Color> _typeGradient(EventType t) {
    switch (t) {
      case EventType.service:
        return [const Color(0xFF1a3a6b), const Color(0xFF0d2145)];
      case EventType.study:
        return [const Color(0xFF1a4a2e), const Color(0xFF0d2a1a)];
      case EventType.outreach:
        return [const Color(0xFF4a2a1a), const Color(0xFF2a150a)];
      case EventType.social:
        return [const Color(0xFF3a1a4a), const Color(0xFF1f0d2a)];
      case EventType.other:
        return [AppColors.darkSurface, AppColors.darkBackground];
    }
  }

  IconData _typeIcon(EventType t) {
    switch (t) {
      case EventType.service:
        return Icons.church_outlined;
      case EventType.study:
        return Icons.menu_book_outlined;
      case EventType.outreach:
        return Icons.volunteer_activism_outlined;
      case EventType.social:
        return Icons.celebration_outlined;
      case EventType.other:
        return Icons.event_outlined;
    }
  }
}

// ── Date badge ─────────────────────────────────────────────────────

class _DateBadge extends StatelessWidget {
  const _DateBadge({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.darkBackground.withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            DateFormat('MMM').format(date).toUpperCase(),
            style: AppTextStyles.overline.copyWith(
              color: AppColors.primary,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            DateFormat('d').format(date),
            style: AppTextStyles.titleLarge.copyWith(height: 1),
          ),
        ],
      ),
    );
  }
}

// ── Small badge widgets ────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});
  final EventType type;

  String get _label {
    switch (type) {
      case EventType.service:
        return 'Service';
      case EventType.study:
        return 'Bible Study';
      case EventType.outreach:
        return 'Outreach';
      case EventType.social:
        return 'Social';
      case EventType.other:
        return 'Event';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label,
        style: AppTextStyles.caption.copyWith(color: AppColors.primary),
      ),
    );
  }
}

class _OnlineBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Online',
        style: AppTextStyles.caption.copyWith(color: Colors.green),
      ),
    );
  }
}

class _RsvpBadge extends StatelessWidget {
  const _RsvpBadge({required this.status});
  final RsvpStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      RsvpStatus.going => ('Going ✓', Colors.green),
      RsvpStatus.maybe => ('Maybe', Colors.orange),
      RsvpStatus.notGoing => ('Not Going', AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(color: color),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.bodySmall
                .copyWith(color: AppColors.textSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.icon});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textSecondary),
          const SizedBox(height: 16),
          Text(message,
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Text('Check back later or create one!',
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.textSecondary)),
        ],
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
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, __) => Container(
        height: 280,
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

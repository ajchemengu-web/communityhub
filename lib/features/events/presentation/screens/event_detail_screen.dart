import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../boosts/domain/models/boost_model.dart';
import '../../../boosts/presentation/widgets/promote_post_sheet.dart';
import '../../domain/models/event_model.dart';
import '../providers/events_provider.dart';

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(eventDetailProvider(eventId));

    if (state.isLoading) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (state.event == null) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(backgroundColor: AppColors.darkBackground),
        body: const Center(child: Text('Event not found')),
      );
    }

    final event = state.event!;

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: CustomScrollView(
        slivers: [
          _EventSliverAppBar(event: event),
          SliverPadding(
            padding: const EdgeInsets.all(20),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _RsvpSection(event: event, state: state),
                const SizedBox(height: 24),
                _MetaSection(event: event),
                const SizedBox(height: 24),
                if (event.description != null &&
                    event.description!.isNotEmpty) ...[
                  _SectionLabel('About'),
                  const SizedBox(height: 10),
                  Text(
                    event.description!,
                    style: AppTextStyles.bodyMedium
                        .copyWith(color: AppColors.textSecondary, height: 1.6),
                  ),
                  const SizedBox(height: 24),
                ],
                _AttendeesSection(state: state),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sliver AppBar ──────────────────────────────────────────────────

class _EventSliverAppBar extends StatelessWidget {
  const _EventSliverAppBar({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: AppColors.darkBackground,
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.darkBackground.withOpacity(0.7),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.arrow_back, size: 20),
        ),
        onPressed: () => context.pop(),
      ),
      actions: [
        if (event.organizerId == SupabaseService.currentUserId)
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.darkBackground.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.trending_up_rounded, size: 20),
            ),
            tooltip: 'Promote event',
            onPressed: () => showPromoteSheet(
              context,
              targetType: BoostTargetType.event,
              targetId: event.id,
            ),
          ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.darkBackground.withOpacity(0.7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.share_outlined, size: 20),
          ),
          onPressed: () {
            // TODO: share event
          },
        ),
        const SizedBox(width: 8),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Cover
            event.coverUrl != null
                ? CachedNetworkImage(
                    imageUrl: event.coverUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        _GradientCover(type: event.type),
                  )
                : _GradientCover(type: event.type),
            // Gradient overlay
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.5, 1],
                  colors: [Colors.transparent, AppColors.darkBackground],
                ),
              ),
            ),
            // Bottom info
            Positioned(
              left: 20,
              right: 20,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _TypeChip(event.typeLabel),
                      if (event.isOnline) ...[
                        const SizedBox(width: 8),
                        _TypeChip('Online', color: Colors.green),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(event.title,
                      style: AppTextStyles.headlineSmall
                          .copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientCover extends StatelessWidget {
  const _GradientCover({required this.type});
  final EventType type;

  @override
  Widget build(BuildContext context) {
    final colors = switch (type) {
      EventType.service => [
          const Color(0xFF1a3a6b),
          const Color(0xFF0d2145)
        ],
      EventType.study => [const Color(0xFF1a4a2e), const Color(0xFF0d2a1a)],
      EventType.outreach => [
          const Color(0xFF4a2a1a),
          const Color(0xFF2a150a)
        ],
      EventType.social => [const Color(0xFF3a1a4a), const Color(0xFF1f0d2a)],
      _ => [AppColors.darkSurface, AppColors.darkBackground],
    };
    return Container(
      decoration:
          BoxDecoration(gradient: LinearGradient(colors: colors)),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip(this.label, {this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: AppTextStyles.caption.copyWith(color: c)),
    );
  }
}

// ── RSVP section ───────────────────────────────────────────────────

class _RsvpSection extends ConsumerWidget {
  const _RsvpSection({required this.event, required this.state});
  final EventModel event;
  final EventDetailState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Will you attend?'),
        const SizedBox(height: 12),
        Row(
          children: [
            _RsvpButton(
              label: 'Going',
              icon: Icons.check_circle_outline,
              isSelected: event.userRsvp == RsvpStatus.going,
              count: event.goingCount,
              color: Colors.green,
              isLoading: state.isRsvping,
              onTap: () => ref
                  .read(eventDetailProvider(event.id).notifier)
                  .toggleRsvp(RsvpStatus.going),
            ),
            const SizedBox(width: 10),
            _RsvpButton(
              label: 'Maybe',
              icon: Icons.help_outline,
              isSelected: event.userRsvp == RsvpStatus.maybe,
              count: event.maybeCount,
              color: Colors.orange,
              isLoading: state.isRsvping,
              onTap: () => ref
                  .read(eventDetailProvider(event.id).notifier)
                  .toggleRsvp(RsvpStatus.maybe),
            ),
            const SizedBox(width: 10),
            _RsvpButton(
              label: "Can't Go",
              icon: Icons.cancel_outlined,
              isSelected: event.userRsvp == RsvpStatus.notGoing,
              count: null,
              color: AppColors.textSecondary,
              isLoading: state.isRsvping,
              onTap: () => ref
                  .read(eventDetailProvider(event.id).notifier)
                  .toggleRsvp(RsvpStatus.notGoing),
            ),
          ],
        ),
      ],
    );
  }
}

class _RsvpButton extends StatelessWidget {
  const _RsvpButton({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.count,
    required this.color,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool isSelected;
  final int? count;
  final Color color;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withOpacity(0.2)
                : AppColors.darkSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : AppColors.darkBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  size: 22, color: isSelected ? color : AppColors.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppTextStyles.labelSmall.copyWith(
                  color: isSelected ? color : AppColors.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              if (count != null) ...[
                const SizedBox(height: 2),
                Text(
                  '$count',
                  style: AppTextStyles.caption.copyWith(
                    color: isSelected ? color : AppColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Meta info ──────────────────────────────────────────────────────

class _MetaSection extends StatelessWidget {
  const _MetaSection({required this.event});
  final EventModel event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        children: [
          _MetaRow(
            icon: Icons.calendar_today_outlined,
            iconColor: AppColors.primary,
            title: _dateString(),
            subtitle: _timeString(),
          ),
          const Divider(color: AppColors.darkBorder, height: 24),
          if (event.isOnline) ...[
            _MetaRow(
              icon: Icons.videocam_outlined,
              iconColor: Colors.green,
              title: 'Online Event',
              subtitle: event.meetingUrl ?? 'Link will be shared',
              onTap: event.meetingUrl != null
                  ? () => _launchUrl(event.meetingUrl!)
                  : null,
              trailingIcon: event.meetingUrl != null
                  ? Icons.open_in_new
                  : null,
            ),
          ] else ...[
            _MetaRow(
              icon: Icons.location_on_outlined,
              iconColor: Colors.redAccent,
              title: event.location ?? 'Location TBD',
              subtitle: 'In-person event',
            ),
          ],
          if (event.communityName != null) ...[
            const Divider(color: AppColors.darkBorder, height: 24),
            _MetaRow(
              icon: Icons.group_outlined,
              iconColor: AppColors.secondary,
              title: event.communityName!,
              subtitle: 'Hosted by community',
            ),
          ],
          if (event.organizerName != null) ...[
            const Divider(color: AppColors.darkBorder, height: 24),
            _MetaRow(
              icon: Icons.person_outline,
              iconColor: AppColors.textSecondary,
              title: event.organizerName!,
              subtitle: 'Organizer',
            ),
          ],
        ],
      ),
    );
  }

  String _dateString() {
    final start = DateFormat('EEEE, MMMM d, yyyy').format(event.startTime);
    if (event.isMultiDay) {
      final end = DateFormat('MMMM d, yyyy').format(event.endTime);
      return '$start – $end';
    }
    return start;
  }

  String _timeString() {
    final start = DateFormat('h:mm a').format(event.startTime);
    final end = DateFormat('h:mm a').format(event.endTime);
    return '$start – $end';
  }

  void _launchUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailingIcon,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppTextStyles.bodyMedium
                        .copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (trailingIcon != null)
            Icon(trailingIcon, size: 16, color: AppColors.primary),
        ],
      ),
    );
  }
}

// ── Attendees ──────────────────────────────────────────────────────

class _AttendeesSection extends StatelessWidget {
  const _AttendeesSection({required this.state});
  final EventDetailState state;

  @override
  Widget build(BuildContext context) {
    final going = state.goingList;
    if (going.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel('Attendees (${going.length} going)'),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: going.length > 10 ? 11 : going.length,
            itemBuilder: (_, i) {
              if (i == 10) {
                return Center(
                  child: Container(
                    width: 44,
                    height: 44,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurface,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Center(
                      child: Text('+${going.length - 10}',
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                  ),
                );
              }
              final a = going[i];
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Tooltip(
                  message: a.userName ?? 'Member',
                  child: CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.darkSurface,
                    backgroundImage: a.userAvatar != null
                        ? CachedNetworkImageProvider(a.userAvatar!)
                        : null,
                    child: a.userAvatar == null
                        ? Text(
                            (a.userName ?? 'M')[0].toUpperCase(),
                            style: AppTextStyles.labelMedium,
                          )
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Section label ──────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: AppTextStyles.titleSmall
            .copyWith(color: AppColors.textSecondary));
  }
}

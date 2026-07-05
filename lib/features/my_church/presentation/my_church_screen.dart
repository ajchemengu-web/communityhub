import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../communities/domain/models/announcement_model.dart';
import '../../communities/domain/models/community_model.dart';
import '../../communities/domain/models/prayer_request_model.dart';
import '../../communities/presentation/providers/my_church_provider.dart';

class MyChurchScreen extends ConsumerWidget {
  const MyChurchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myChurchProvider);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: RefreshIndicator(
        color: AppColors.primary,
        backgroundColor: AppColors.darkSurface,
        onRefresh: () => ref.read(myChurchProvider.notifier).refresh(),
        child: state.isLoading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : state.churches.isEmpty
                ? _EmptyChurchState(
                    onExplore: () => context.push(AppRoutes.communities))
                : CustomScrollView(
                    slivers: [
                      // ── AppBar with church hero ────────────────────
                      _ChurchSliverAppBar(church: state.primaryChurch!),

                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Church switcher (if multiple) ──────────
                            if (state.churches.length > 1)
                              _ChurchSwitcher(
                                churches: state.churches,
                                selected: state.primaryChurch!,
                                onSelect: ref
                                    .read(myChurchProvider.notifier)
                                    .selectChurch,
                              ),

                            // ── Quick actions ──────────────────────────
                            _QuickActions(church: state.primaryChurch!),

                            const SizedBox(height: 24),

                            // ── Pinned announcements ───────────────────
                            if (state.announcements.isNotEmpty) ...[
                              _SectionHeader(
                                title: 'Announcements',
                                icon: Icons.campaign_outlined,
                                onSeeAll: () => context.push(
                                    '/community/${state.primaryChurch!.id}'),
                              ),
                              ...state.announcements
                                  .where((a) => a.isPinned)
                                  .take(1)
                                  .map((a) => _AnnouncementCard(a)),
                              ...state.announcements
                                  .where((a) => !a.isPinned)
                                  .take(2)
                                  .map((a) => _AnnouncementCard(a)),
                              const SizedBox(height: 24),
                            ],

                            // ── Prayer wall ───────────────────────────
                            _SectionHeader(
                              title: 'Prayer Wall',
                              icon: Icons.volunteer_activism_outlined,
                              trailing: _AddPrayerButton(
                                communityId: state.primaryChurch!.id,
                                isSubmitting: state.isSubmittingPrayer,
                              ),
                            ),

                            if (state.prayerRequests.isEmpty)
                              const _EmptyPrayerState()
                            else
                              ...state.prayerRequests
                                  .take(5)
                                  .map((p) => _PrayerCard(prayer: p)),

                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ── Sliver App Bar ─────────────────────────────────────────────────

class _ChurchSliverAppBar extends StatelessWidget {
  const _ChurchSliverAppBar({required this.church});

  final CommunityModel church;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 220,
      pinned: true,
      backgroundColor: AppColors.darkBackground,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding:
            const EdgeInsets.only(left: 16, bottom: 56),
        title: Row(
          children: [
            Flexible(
              child: Text(
                church.name,
                style: AppTextStyles.heading3.copyWith(
                  color: Colors.white,
                  shadows: [
                    const Shadow(
                        color: Colors.black45,
                        blurRadius: 4,
                        offset: Offset(0, 2))
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (church.isVerified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified,
                  color: AppColors.verifiedBadge, size: 16),
            ],
          ],
        ),
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (church.coverUrl != null)
              CachedNetworkImage(
                imageUrl: church.coverUrl!,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                    color: AppColors.primary.withValues(alpha: 0.3)),
                errorWidget: (_, __, ___) =>
                    Container(color: AppColors.primary.withValues(alpha: 0.3)),
              )
            else
              Container(
                decoration: const BoxDecoration(
                  gradient: AppColors.brandGradient,
                ),
              ),
            // Gradient overlay
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Color(0xCC000000)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
            // Member count + denomination chip row
            Positioned(
              bottom: 60,
              left: 16,
              child: Row(
                children: [
                  if (church.denomination != null)
                    _InfoChip(
                        icon: Icons.church_outlined,
                        label: church.denomination!),
                  if (church.denomination != null && church.location != null)
                    const SizedBox(width: 8),
                  if (church.location != null)
                    _InfoChip(
                        icon: Icons.location_on_outlined,
                        label: church.location!),
                ],
              ),
            ),
          ],
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(40),
        child: _MembersCountBar(membersCount: church.membersCount),
      ),
      leading: const BackButton(color: Colors.white),
      actions: [
        IconButton(
          icon: const Icon(Icons.open_in_new, color: Colors.white),
          tooltip: 'Full page',
          onPressed: () => context.push('/community/${church.id}'),
        ),
      ],
    );
  }
}

class _MembersCountBar extends StatelessWidget {
  const _MembersCountBar({required this.membersCount});

  final int membersCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppColors.darkSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.people_outline,
              size: 16, color: AppColors.textDarkSecondary),
          const SizedBox(width: 6),
          Text(
            '$membersCount ${membersCount == 1 ? 'member' : 'members'}',
            style: AppTextStyles.captionText
                .copyWith(color: AppColors.textDarkSecondary),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(label,
              style: AppTextStyles.captionText
                  .copyWith(color: Colors.white70)),
        ],
      ),
    );
  }
}

// ── Church switcher ────────────────────────────────────────────────

class _ChurchSwitcher extends StatelessWidget {
  const _ChurchSwitcher({
    required this.churches,
    required this.selected,
    required this.onSelect,
  });

  final List<CommunityModel> churches;
  final CommunityModel selected;
  final void Function(CommunityModel) onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      color: AppColors.darkSurface,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: churches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = churches[i];
          final isActive = c.id == selected.id;
          return GestureDetector(
            onTap: () => onSelect(c),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isActive
                          ? AppColors.secondary
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(
                    child: c.coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: c.coverUrl!,
                            fit: BoxFit.cover)
                        : Container(
                            color: AppColors.primary,
                            child: Center(
                              child: Text(
                                c.name[0].toUpperCase(),
                                style: AppTextStyles.bodyLarge.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 52,
                  child: Text(
                    c.name,
                    style: AppTextStyles.overline.copyWith(
                      color: isActive
                          ? AppColors.secondary
                          : AppColors.textDarkSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Quick actions ──────────────────────────────────────────────────

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.church});

  final CommunityModel church;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.darkSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _QuickAction(
            icon: Icons.article_outlined,
            label: 'Posts',
            onTap: () => context.push('/community/${church.id}'),
          ),
          _QuickAction(
            icon: Icons.campaign_outlined,
            label: 'Announcements',
            onTap: () =>
                context.push('/community/${church.id}?tab=announcements'),
          ),
          _QuickAction(
            icon: Icons.people_outline,
            label: 'Members',
            onTap: () =>
                context.push('/community/${church.id}?tab=members'),
          ),
          _QuickAction(
            icon: Icons.volunteer_activism_outlined,
            label: 'Give',
            onTap: () {
              if (church.website != null) {
                // url_launcher would handle this
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Giving portal coming soon!')),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: AppTextStyles.overline
                .copyWith(color: AppColors.textDarkSecondary),
          ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    this.onSeeAll,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final VoidCallback? onSeeAll;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: AppTextStyles.heading3
                .copyWith(color: AppColors.textDarkPrimary),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'See all',
                style: AppTextStyles.captionText
                    .copyWith(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Announcement card ──────────────────────────────────────────────

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard(this.announcement);

  final AnnouncementModel announcement;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: announcement.isPinned
            ? Border.all(color: AppColors.secondary.withValues(alpha: 0.6))
            : Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pin banner
          if (announcement.isPinned)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.15),
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.push_pin,
                      size: 12, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  Text(
                    'Pinned',
                    style: AppTextStyles.overline
                        .copyWith(color: AppColors.secondary),
                  ),
                ],
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author row
                Row(
                  children: [
                    _MiniAvatar(
                        avatarUrl: announcement.authorAvatar,
                        name: announcement.authorName ?? 'Admin'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            announcement.authorName ?? 'Admin',
                            style: AppTextStyles.captionText.copyWith(
                              color: AppColors.textDarkPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            timeago.format(announcement.createdAt),
                            style: AppTextStyles.overline.copyWith(
                                color: AppColors.textDarkSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                Text(
                  announcement.title,
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textDarkPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 6),

                Text(
                  announcement.content,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textDarkSecondary),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Prayer card ────────────────────────────────────────────────────

class _PrayerCard extends ConsumerWidget {
  const _PrayerCard({required this.prayer});

  final PrayerRequestModel prayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(myChurchProvider.notifier);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: prayer.isAnswered
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: prayer.isAnswered
              ? AppColors.success.withValues(alpha: 0.4)
              : AppColors.darkDivider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              _MiniAvatar(
                  avatarUrl: prayer.isAnonymous
                      ? null
                      : prayer.authorAvatar,
                  name: prayer.displayName),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          prayer.displayName,
                          style: AppTextStyles.captionText.copyWith(
                            color: AppColors.textDarkPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (prayer.isAnswered) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Answered',
                              style: AppTextStyles.overline
                                  .copyWith(color: AppColors.success),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      timeago.format(prayer.createdAt),
                      style: AppTextStyles.overline.copyWith(
                          color: AppColors.textDarkSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          Text(
            prayer.content,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textDarkPrimary),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),

          const SizedBox(height: 12),

          // Pray button
          Row(
            children: [
              GestureDetector(
                onTap: () => notifier.togglePrayer(prayer),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: prayer.hasPrayed
                        ? AppColors.primary.withValues(alpha: 0.2)
                        : AppColors.darkSurface2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: prayer.hasPrayed
                          ? AppColors.primary
                          : AppColors.darkBorder,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        prayer.hasPrayed
                            ? Icons.volunteer_activism
                            : Icons.volunteer_activism_outlined,
                        size: 14,
                        color: prayer.hasPrayed
                            ? AppColors.primary
                            : AppColors.textDarkSecondary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        prayer.hasPrayed ? 'Praying' : 'Pray',
                        style: AppTextStyles.captionText.copyWith(
                          color: prayer.hasPrayed
                              ? AppColors.primary
                              : AppColors.textDarkSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (prayer.prayerCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '${prayer.prayerCount}',
                          style: AppTextStyles.captionText.copyWith(
                            color: prayer.hasPrayed
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Add prayer button ──────────────────────────────────────────────

class _AddPrayerButton extends ConsumerWidget {
  const _AddPrayerButton({
    required this.communityId,
    required this.isSubmitting,
  });

  final String communityId;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: isSubmitting
          ? null
          : () => _showPrayerDialog(context, ref),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add,
                size: 14, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              'Request',
              style: AppTextStyles.captionText.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPrayerDialog(
      BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    bool isAnonymous = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.darkDivider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Row(
                children: [
                  const Icon(Icons.volunteer_activism_outlined,
                      color: AppColors.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Share a Prayer Request',
                    style: AppTextStyles.heading3.copyWith(
                        color: AppColors.textDarkPrimary),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              TextField(
                controller: controller,
                autofocus: true,
                maxLines: 5,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textDarkPrimary),
                decoration: InputDecoration(
                  hintText:
                      'Share what\'s on your heart. The community will pray with you…',
                  hintStyle: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textMuted),
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
              ),

              const SizedBox(height: 12),

              // Anonymous toggle
              GestureDetector(
                onTap: () => setInner(() => isAnonymous = !isAnonymous),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: isAnonymous
                            ? AppColors.primary
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: isAnonymous
                              ? AppColors.primary
                              : AppColors.darkBorder,
                        ),
                      ),
                      child: isAnonymous
                          ? const Icon(Icons.check,
                              size: 14, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Post anonymously',
                      style: AppTextStyles.bodyMedium.copyWith(
                          color: AppColors.textDarkSecondary),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    Navigator.pop(ctx);
                    await ref
                        .read(myChurchProvider.notifier)
                        .submitPrayerRequest(
                          content: text,
                          isAnonymous: isAnonymous,
                        );
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Share with community',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty states ───────────────────────────────────────────────────

class _EmptyChurchState extends StatelessWidget {
  const _EmptyChurchState({required this.onExplore});

  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.church_outlined,
                  size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'You haven\'t joined a church community yet',
              style: AppTextStyles.bodyLarge.copyWith(
                  color: AppColors.textDarkPrimary,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Find and join a faith community to see announcements, prayer requests, and more.',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textDarkSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: onExplore,
              icon: const Icon(Icons.search, color: Colors.white),
              label: const Text('Explore Communities',
                  style: TextStyle(color: Colors.white)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPrayerState extends StatelessWidget {
  const _EmptyPrayerState();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkDivider),
      ),
      child: Column(
        children: [
          const Icon(Icons.volunteer_activism_outlined,
              size: 36, color: AppColors.textDarkTertiary),
          const SizedBox(height: 10),
          Text(
            'No prayer requests yet',
            style: AppTextStyles.bodyMedium.copyWith(
              color: AppColors.textDarkSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Be the first to share a request with your community.',
            style: AppTextStyles.captionText
                .copyWith(color: AppColors.textMuted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Mini avatar ────────────────────────────────────────────────────

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({required this.avatarUrl, required this.name});

  final String? avatarUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: avatarUrl != null
          ? CachedNetworkImage(
              imageUrl: avatarUrl!,
              width: 32,
              height: 32,
              fit: BoxFit.cover)
          : Container(
              width: 32,
              height: 32,
              color: AppColors.primary.withValues(alpha: 0.4),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: AppTextStyles.captionText.copyWith(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
    );
  }
}

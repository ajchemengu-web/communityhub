import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../home/data/feed_repository.dart';
import '../../../home/domain/models/story_model.dart';
import '../../../home/presentation/providers/story_provider.dart';

/// WhatsApp-style Updates screen — "My Status" at top, then
/// "Recent updates" (has something unseen), "Viewed updates" (all
/// seen), and "Muted updates" as its own section regardless of seen
/// status, matching WhatsApp's Status tab exactly.
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storyProvider);
    final mutedIds = ref.watch(mutedStoryUserIdsProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        title: Text('Updates', style: AppTextStyles.titleLarge.copyWith(color: Colors.white)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(storyProvider);
          ref.invalidate(myStoryProvider);
          ref.invalidate(myStoriesProvider);
          ref.invalidate(mutedStoryUserIdsProvider);
        },
        child: storiesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (_, __) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(
                child: Text('Could not load updates',
                    style: TextStyle(color: Colors.white54)),
              ),
            ],
          ),
          data: (stories) {
            final grouped = <String, List<StoryModel>>{};
            for (final s in stories) {
              grouped.putIfAbsent(s.userId, () => []).add(s);
            }

            final recent = <MapEntry<String, List<StoryModel>>>[];
            final viewed = <MapEntry<String, List<StoryModel>>>[];
            final muted = <MapEntry<String, List<StoryModel>>>[];

            for (final entry in grouped.entries) {
              if (mutedIds.contains(entry.key)) {
                muted.add(entry);
              } else if (entry.value.any((s) => !s.isSeen)) {
                recent.add(entry);
              } else {
                viewed.add(entry);
              }
            }

            DateTime latestOf(List<StoryModel> l) =>
                l.map((s) => s.createdAt).reduce((a, b) => a.isAfter(b) ? a : b);
            int byLatestDesc(MapEntry<String, List<StoryModel>> a,
                    MapEntry<String, List<StoryModel>> b) =>
                latestOf(b.value).compareTo(latestOf(a.value));

            recent.sort(byLatestDesc);
            viewed.sort(byLatestDesc);
            muted.sort(byLatestDesc);

            final isEmpty = recent.isEmpty && viewed.isEmpty && muted.isEmpty;

            return ListView(
              children: [
                const _MyStatusRow(),
                const Divider(color: AppColors.darkBorder, height: 24),
                if (recent.isNotEmpty) ...[
                  const _SectionHeader('Recent updates'),
                  for (final e in recent)
                    _UpdateRow(userStories: e.value, isMuted: false),
                ],
                if (viewed.isNotEmpty) ...[
                  const _SectionHeader('Viewed updates'),
                  for (final e in viewed)
                    _UpdateRow(userStories: e.value, isMuted: false),
                ],
                if (muted.isNotEmpty) ...[
                  const _SectionHeader('Muted updates'),
                  for (final e in muted)
                    _UpdateRow(userStories: e.value, isMuted: true),
                ],
                if (isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: Center(
                      child: Text(
                        'No updates from people you follow yet',
                        style: TextStyle(color: Colors.white38),
                      ),
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        label,
        style: AppTextStyles.labelMedium.copyWith(
          color: AppColors.textDarkSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MyStatusRow extends ConsumerWidget {
  const _MyStatusRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myStory = ref.watch(myStoryProvider).valueOrNull;
    final hasStory = myStory != null;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Stack(
        children: [
          Container(
            width: 54,
            height: 54,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasStory ? AppColors.storyGradient : null,
              color: hasStory ? null : AppColors.darkSurface2,
            ),
            child: ClipOval(
              child: (myStory?.avatarUrl.isNotEmpty ?? false)
                  ? CachedNetworkImage(
                      imageUrl: myStory!.avatarUrl, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.primaryLight,
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
            ),
          ),
          if (!hasStory)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColors.darkBackground, width: 1.5),
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 12),
              ),
            ),
        ],
      ),
      title: Text('My Status',
          style: AppTextStyles.bodyMedium
              .copyWith(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(
        hasStory ? 'Tap to view your status' : 'Tap to add a status update',
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      ),
      onTap: () async {
        if (!hasStory) {
          context.push('/story/create');
          return;
        }
        final myStories = await ref.read(myStoriesProvider.future);
        if (myStories.isEmpty || !context.mounted) return;
        context.push('/stories/${myStories.first.userId}', extra: {
          'stories': myStories,
          'index': 0,
        });
      },
    );
  }
}

class _UpdateRow extends ConsumerWidget {
  const _UpdateRow({required this.userStories, required this.isMuted});
  final List<StoryModel> userStories;
  final bool isMuted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = userStories.reduce(
        (a, b) => a.createdAt.isAfter(b.createdAt) ? a : b);
    final hasUnseen = userStories.any((s) => !s.isSeen);

    return GestureDetector(
      onLongPress: () => _showContextMenu(context, ref),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Container(
          width: 54,
          height: 54,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: hasUnseen ? AppColors.storyGradient : null,
            color: hasUnseen ? null : AppColors.darkSurface2,
          ),
          child: ClipOval(
            child: latest.avatarUrl.isNotEmpty
                ? CachedNetworkImage(imageUrl: latest.avatarUrl, fit: BoxFit.cover)
                : Container(
                    color: AppColors.primaryLight,
                    child: Center(
                      child: Text(
                        latest.username.isNotEmpty
                            ? latest.username[0].toUpperCase()
                            : '?',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(latest.username,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
            if (latest.isVerified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, size: 13, color: AppColors.primary),
            ],
            if (isMuted) ...[
              const SizedBox(width: 6),
              const Icon(Icons.volume_off_rounded,
                  size: 14, color: Colors.white38),
            ],
          ],
        ),
        subtitle: Text(timeago.format(latest.createdAt),
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        onTap: () => context.push('/stories/${latest.userId}', extra: {
          'stories': userStories,
          'index': 0,
        }),
      ),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                color: Colors.white,
              ),
              title: Text(
                isMuted
                    ? "Unmute ${userStories.first.username}"
                    : "Mute ${userStories.first.username}",
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(context);
                final userId = userStories.first.userId;
                if (isMuted) {
                  await FeedRepository.instance.unmuteStoryUser(userId);
                } else {
                  await FeedRepository.instance.muteStoryUser(userId);
                }
                ref.invalidate(mutedStoryUserIdsProvider);
              },
            ),
          ],
        ),
      ),
    );
  }
}

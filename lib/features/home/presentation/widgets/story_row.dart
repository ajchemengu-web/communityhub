import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../domain/models/story_model.dart';
import '../providers/story_provider.dart';

class StoryRow extends ConsumerWidget {
  const StoryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storyProvider);
    final myStoryAsync = ref.watch(myStoryProvider);

    return SizedBox(
      height: 96,
      child: storiesAsync.when(
        loading: () => _StoryRowSkeleton(),
        error: (_, __) => _buildList(context, [], null),
        data: (stories) => myStoryAsync.when(
          loading: () => _buildList(context, stories, null),
          error: (_, __) => _buildList(context, stories, null),
          data: (myStory) => _buildList(context, stories, myStory),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<StoryModel> stories,
    StoryModel? myStory,
  ) {
    // Group stories by userId for the viewer
    final grouped = <String, List<StoryModel>>{};
    for (final s in stories) {
      grouped.putIfAbsent(s.userId, () => []).add(s);
    }
    final userIds = grouped.keys.toList();

    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: 1 + userIds.length,
      separatorBuilder: (_, __) => const SizedBox(width: 12),
      itemBuilder: (ctx, i) {
        if (i == 0) {
          return _AddStoryBubble(
            hasActiveStory: myStory != null,
            myStory: myStory,
          );
        }
        final uid = userIds[i - 1];
        final userStories = grouped[uid]!;
        return _StoryBubble(
          story: userStories.first,
          allStories: userStories,
        );
      },
    );
  }
}

// ── Add Story Bubble ──────────────────────────────────────────

class _AddStoryBubble extends StatelessWidget {
  const _AddStoryBubble({
    required this.hasActiveStory,
    this.myStory,
  });
  final bool hasActiveStory;
  final StoryModel? myStory;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (hasActiveStory && myStory != null) {
          context.push('/stories/${myStory!.userId}', extra: {
            'stories': [myStory!],
            'index': 0,
          });
        } else {
          context.push('/story/create');
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.darkSurface2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: hasActiveStory
                        ? AppColors.secondary
                        : AppColors.darkBorder,
                    width: 1.5,
                  ),
                ),
                child: hasActiveStory
                    ? const Icon(
                        Icons.auto_stories_rounded,
                        color: AppColors.secondary,
                        size: 26,
                      )
                    : const Icon(
                        Icons.person_rounded,
                        color: AppColors.textDarkSecondary,
                        size: 26,
                      ),
              ),
              // "+" badge
              if (!hasActiveStory)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.secondary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.darkBackground,
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.add, color: Colors.black, size: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasActiveStory ? 'Your Story' : 'Add Story',
            style: AppTextStyles.labelSmall.copyWith(
              color: hasActiveStory
                  ? AppColors.secondary
                  : AppColors.textDarkSecondary,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Story Bubble ──────────────────────────────────────────────

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.story,
    required this.allStories,
  });
  final StoryModel story;
  final List<StoryModel> allStories;

  @override
  Widget build(BuildContext context) {
    final hasUnseen = allStories.any((s) => !s.isSeen);

    return GestureDetector(
      onTap: () => context.push(
        '/stories/${story.userId}',
        extra: {'stories': allStories, 'index': 0},
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ring + avatar
          Container(
            width: 64,
            height: 64,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: hasUnseen ? AppColors.storyGradient : null,
              color: hasUnseen ? null : AppColors.darkSurface2,
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.darkBackground,
              ),
              padding: const EdgeInsets.all(2),
              child: ClipOval(
                child: story.avatarUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: story.avatarUrl,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: AppColors.darkSurface2),
                        errorWidget: (_, __, ___) => _DefaultAvatar(
                          username: story.username,
                        ),
                      )
                    : _DefaultAvatar(username: story.username),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(
              story.username,
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.textDarkPrimary,
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DefaultAvatar extends StatelessWidget {
  const _DefaultAvatar({required this.username});
  final String username;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight,
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: AppTextStyles.titleSmall.copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

// ── Skeleton loader ───────────────────────────────────────────

class _StoryRowSkeleton extends StatefulWidget {
  @override
  State<_StoryRowSkeleton> createState() => _StoryRowSkeletonState();
}

class _StoryRowSkeletonState extends State<_StoryRowSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: 6,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, __) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.darkSurface2.withValues(alpha: _anim.value),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 48,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: AppColors.darkSurface2.withValues(alpha: _anim.value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

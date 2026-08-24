import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../domain/models/story_model.dart';
import '../providers/story_provider.dart';

class StoryRow extends ConsumerWidget {
  const StoryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storiesAsync = ref.watch(storyProvider);
    // myStoriesProvider (plural, oldest-first) replaces the old
    // myStoryProvider (singular) here -- that meant tapping your own
    // ring only ever passed a single-item list to the viewer, so a
    // second/third story from today was silently unreachable even
    // though [myStoriesProvider] already existed to fetch all of them.
    final myStoriesAsync = ref.watch(myStoriesProvider);
    // The current user's own avatar for the "Add Story"/"Your Story"
    // bubble -- previously that bubble never rendered any photo at
    // all, just a generic person/book icon regardless of who was
    // looking at it.
    final myAvatarUrl = ref
        .watch(currentUserProfileProvider)
        .whenOrNull(data: (p) => p?['avatar_url'] as String?);

    return SizedBox(
      height: 96,
      child: storiesAsync.when(
        loading: () => _StoryRowSkeleton(),
        error: (_, __) => _buildList(context, [], const [], myAvatarUrl),
        data: (stories) => myStoriesAsync.when(
          loading: () => _buildList(context, stories, const [], myAvatarUrl),
          error: (_, __) => _buildList(context, stories, const [], myAvatarUrl),
          data: (myStories) =>
              _buildList(context, stories, myStories, myAvatarUrl),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<StoryModel> stories,
    List<StoryModel> myStories,
    String? myAvatarUrl,
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
            myStories: myStories,
            avatarUrl:
                (myStories.isNotEmpty ? myStories.last.avatarUrl : null) ??
                    myAvatarUrl,
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
    required this.myStories,
    this.avatarUrl,
  });

  /// Oldest-first, from [myStoriesProvider] -- empty when the current
  /// user has no active story right now.
  final List<StoryModel> myStories;
  final String? avatarUrl;

  bool get hasActiveStory => myStories.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (hasActiveStory) {
          context.push('/stories/${myStories.first.userId}', extra: {
            'stories': myStories,
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
                // Previously this always showed a generic placeholder
                // icon (person/book) no matter who was looking at it --
                // now shows the current user's own profile photo, same
                // as every other story bubble does for its owner.
                child: ClipOval(
                  child: (avatarUrl?.isNotEmpty ?? false)
                      ? CachedNetworkImage(
                          imageUrl: avatarUrl!,
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const _DefaultPersonIcon(),
                          errorWidget: (_, __, ___) =>
                              const _DefaultPersonIcon(),
                        )
                      : const _DefaultPersonIcon(),
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

class _DefaultPersonIcon extends StatelessWidget {
  const _DefaultPersonIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(
      Icons.person_rounded,
      color: AppColors.textDarkSecondary,
      size: 26,
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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../../library/data/library_books.dart';
import '../../../library/presentation/screens/book_reader_screen.dart';
import '../../../library/presentation/widgets/book_cover_art.dart';
import '../../../scriptures/presentation/screens/bible_screen.dart';
import '../../../scriptures/presentation/screens/quran_screen.dart';
import '../../domain/models/community_model.dart';
import '../providers/communities_provider.dart';

class CommunitiesScreen extends ConsumerWidget {
  const CommunitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communitiesProvider);
    final religionAsync = ref.watch(currentReligionProvider);
    final religion = religionAsync.valueOrNull ?? '';

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        backgroundColor: AppColors.darkBackground,
        elevation: 0,
        title: const Text(
          'Communities',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () => _showMenu(context, ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => ref.read(communitiesProvider.notifier).refresh(),
        child: ListView(
          children: [
            // ── Scripture Communities (always pinned at top) ────────
            _ScriptureSection(religion: religion),
            const Divider(color: Colors.white10, height: 1),

            // ── Author's Library (same page as Scripture, per product
            //    decision: visible to everyone, no membership needed) ──
            const _LibrarySection(),
            const Divider(color: Colors.white10, height: 1),

            // ── New community tile ─────────────────────────────────
            _NewCommunityTile(
              onTap: () => context.push(AppRoutes.createCommunity),
            ),
            const Divider(color: Colors.white10, height: 1),

            // ── My communities label ───────────────────────────────
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                'MY COMMUNITIES',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),

            // ── Joined communities ─────────────────────────────────
            if (state.isLoadingMine)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.myCommunities.isEmpty)
              _EmptyState(
                onCreateTap: () => context.push(AppRoutes.createCommunity),
              )
            else
              ...state.myCommunities.map(
                (c) => _CommunityRow(community: c),
              ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.add_circle_outline, color: Colors.white),
            title: const Text('New community',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              context.push(AppRoutes.createCommunity);
            },
          ),
          ListTile(
            leading: const Icon(Icons.search, color: Colors.white),
            title: const Text('Discover communities',
                style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _showDiscover(context, ref);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _showDiscover(BuildContext context, WidgetRef ref) {
    final state = ref.read(communitiesProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.darkBackground,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (ctx, scrollCtrl) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Text('Discover Communities',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (state.isLoadingDiscover)
              const Expanded(
                  child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: state.discoverCommunities.length,
                  itemBuilder: (_, i) =>
                      _CommunityRow(community: state.discoverCommunities[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// New community tile
// ─────────────────────────────────────────────────────────────────

class _NewCommunityTile extends StatelessWidget {
  const _NewCommunityTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white12),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 28),
      ),
      title: const Text(
        'New community',
        style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500),
      ),
      subtitle: const Text(
        'Create a community with groups',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Community row (WhatsApp-style)
// ─────────────────────────────────────────────────────────────────

class _CommunityRow extends StatelessWidget {
  const _CommunityRow({required this.community});
  final CommunityModel community;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          onTap: () => context.push('/community/${community.id}'),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: _CommunityIcon(
            avatarUrl: community.avatarUrl ?? community.coverUrl,
            hubType: community.hubType,
            size: 52,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  community.name,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (community.isVerified) ...[
                const SizedBox(width: 4),
                const Icon(Icons.verified, size: 14, color: AppColors.primary),
              ],
            ],
          ),
          subtitle: Text(
            '${community.membersCount} member${community.membersCount == 1 ? '' : 's'}',
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          trailing: community.userRole == 'admin'
              ? Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Admin',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                )
              : null,
        ),
        const Divider(color: Colors.white10, height: 1, indent: 84),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Community icon (rounded square with hub colour)
// ─────────────────────────────────────────────────────────────────

class _CommunityIcon extends StatelessWidget {
  const _CommunityIcon({
    required this.hubType,
    this.avatarUrl,
    this.size = 48,
  });
  final String? avatarUrl;
  final String hubType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = hubType == 'islam'
        ? const Color(0xFF1A6B4A)   // green — Islamic
        : (hubType == 'faith' || hubType == 'christianity')
            ? const Color(0xFF1A7A6B) // teal — Christian/Faith
            : hubType == 'career'
                ? const Color(0xFF1A5F8A)
                : AppColors.primary;

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.26),
        child: CachedNetworkImage(
          imageUrl: avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => _placeholder(color, size),
        ),
      );
    }
    return _placeholder(color, size);
  }

  Widget _placeholder(Color color, double sz) => Container(
        width: sz,
        height: sz,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(sz * 0.26),
        ),
        child: Icon(Icons.groups_rounded,
            color: Colors.white, size: sz * 0.52),
      );
}

// ─────────────────────────────────────────────────────────────────
// Scripture Communities Section (pinned at top of communities list)
// ─────────────────────────────────────────────────────────────────

class _ScriptureSection extends StatelessWidget {
  const _ScriptureSection({required this.religion});
  final String religion; // 'christian' | 'muslim' | ''

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            'SCRIPTURE COMMUNITIES',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        // Show the user's own scripture first, then the other
        if (religion == 'muslim') ...[
          _ScriptureTile.quran(context),
          _ScriptureTile.bible(context),
        ] else ...[
          _ScriptureTile.bible(context),
          _ScriptureTile.quran(context),
        ],
      ],
    );
  }
}

class _ScriptureTile extends StatelessWidget {
  const _ScriptureTile({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.bgColor,
    required this.accentColor,
    required this.stats,
    required this.onTap,
  }) : isDefault = false;

  final String title;
  final String subtitle;
  final String emoji;
  final Color bgColor;
  final Color accentColor;
  final String stats;
  final VoidCallback onTap;
  final bool isDefault;

  factory _ScriptureTile.bible(BuildContext context) => _ScriptureTile(
        title: 'The Holy Bible',
        subtitle: 'King James Version • Genesis to Revelation',
        emoji: '✝️',
        bgColor: const Color(0xFF1A0F00),
        accentColor: const Color(0xFFD4A847),
        stats: '66 Books • 1,189 Chapters • Old & New Testament',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BibleScreen()),
        ),
      );

  factory _ScriptureTile.quran(BuildContext context) => _ScriptureTile(
        title: 'The Holy Quran',
        subtitle: 'Al-Fatiha to An-Nas • Complete Scripture',
        emoji: '☪️',
        bgColor: const Color(0xFF001A0A),
        accentColor: const Color(0xFF4CAF50),
        stats: '114 Surahs • 6,236 Verses • Meccan & Medinan',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuranScreen()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Icon container
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: accentColor.withValues(alpha: 0.4), width: 1),
                ),
                child: Center(
                  child: Text(emoji,
                      style: const TextStyle(fontSize: 26)),
                ),
              ),
              const SizedBox(width: 12),
              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('YOUR BOOK',
                                style: TextStyle(
                                    color: accentColor,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: TextStyle(
                            color: accentColor.withValues(alpha: 0.8),
                            fontSize: 12)),
                    const SizedBox(height: 5),
                    Text(stats,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: accentColor.withValues(alpha: 0.6), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Author's Library (books, alongside Scripture)
// ─────────────────────────────────────────────────────────────────

class _LibrarySection extends StatelessWidget {
  const _LibrarySection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 10),
          child: Text(
            "AUTHOR'S LIBRARY",
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
        for (final book in libraryBooks) _LibraryTile(meta: book),
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.meta});
  final LibraryBookMeta meta;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => BookReaderScreen(meta: meta)),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              meta.bgColor,
              Color.lerp(meta.bgColor, meta.accentColor, 0.12)!,
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: meta.accentColor.withValues(alpha: 0.35),
            width: 1.2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BookCoverArt(meta: meta, width: 56, borderRadius: 8, showText: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(meta.subtitle,
                        style: TextStyle(
                            color: meta.accentColor.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 5),
                    Text(meta.stats,
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right,
                  color: meta.accentColor.withValues(alpha: 0.6), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreateTap});
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_rounded,
                size: 42, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Stay connected with your\ncommunities',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                height: 1.4),
          ),
          const SizedBox(height: 10),
          const Text(
            'Start a community to connect with\npeople who share your interests.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white54, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onCreateTap,
            icon: const Icon(Icons.add),
            label: const Text('New community'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

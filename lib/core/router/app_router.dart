import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../constants/app_routes.dart';
import '../services/supabase_service.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/auth/presentation/screens/setup_profile_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/reels/presentation/screens/reels_screen.dart';
import '../../features/post/presentation/screens/new_post_screen.dart';
import '../../features/post/presentation/screens/post_detail_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/events/presentation/screens/events_screen.dart';
import '../../features/events/presentation/screens/event_detail_screen.dart';
import '../../features/events/presentation/screens/create_event_screen.dart';
import '../../features/chat/presentation/screens/call_screen.dart';
import '../../features/communities/presentation/screens/communities_screen.dart';
import '../../features/communities/presentation/screens/community_detail_screen.dart';
import '../../features/communities/presentation/screens/create_community_screen.dart';
import '../../features/my_church/presentation/my_church_screen.dart';
import '../../features/profile/presentation/screens/edit_profile_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/giving/presentation/screens/giving_screen.dart';
import '../../features/giving/presentation/screens/giving_history_screen.dart';
import '../../features/marketplace/presentation/screens/marketplace_home_screen.dart';
import '../../features/marketplace/presentation/screens/create_product_screen.dart';
import '../../features/marketplace/presentation/screens/product_detail_screen.dart';
import '../../features/marketplace/presentation/screens/seller_orders_screen.dart';
import '../../features/marketplace/presentation/screens/shop_screen.dart';
import '../../features/marketplace/presentation/screens/manage_shop_screen.dart';
import '../../features/marketplace/presentation/screens/shop_admin_screen.dart';
import '../../features/portfolio/presentation/screens/portfolio_screen.dart';
import '../../features/memberships/presentation/screens/tier_picker_screen.dart';
import '../../features/memberships/presentation/screens/manage_subscription_screen.dart';
import '../../features/chat/presentation/screens/chats_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';
import '../services/youtube_service.dart';
import '../../features/home/presentation/screens/video_player_screen.dart';
import '../../features/stories/presentation/screens/story_viewer_screen.dart';
import '../../features/stories/presentation/screens/story_creator_screen.dart';
import '../../features/stories/presentation/screens/updates_screen.dart';
import '../../features/home/domain/models/story_model.dart';
import '../../features/live/data/live_repository.dart';
import '../../features/live/presentation/screens/live_host_screen.dart';
import '../../features/camera/presentation/screens/camera_recorder_screen.dart';
import '../../shared/widgets/main_shell.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter appRouter(AppRouterRef ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final isAuthenticated = SupabaseService.isAuthenticated;
      final location = state.matchedLocation;

      final isGoingToAuth = location == AppRoutes.splash ||
          location == AppRoutes.login ||
          location == AppRoutes.register ||
          location == AppRoutes.onboarding ||
          location.startsWith(AppRoutes.setupProfile);

      // Not authenticated → redirect to login
      if (!isAuthenticated && !isGoingToAuth) {
        return AppRoutes.login;
      }

      // Authenticated and going to auth routes → redirect home
      if (isAuthenticated && isGoingToAuth && location != AppRoutes.splash) {
        return AppRoutes.home;
      }

      return null; // No redirect
    },
    routes: [
      // ── Auth Routes ──────────────────────────────────────────
      GoRoute(
        path: AppRoutes.splash,
        builder: (ctx, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (ctx, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (ctx, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (ctx, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.setupProfile,
        builder: (ctx, state) => const SetupProfileScreen(),
      ),

      // ── Main Shell (Bottom Navigation) ───────────────────────
      // All 4 nav-bar destinations live inside the shell so the
      // bottom bar remains visible during tab switches.
      ShellRoute(
        builder: (ctx, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: HomeScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.search,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: SearchScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.reels,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: ReelsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.updates,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: UpdatesScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.chats,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: ChatsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.notifications,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: NotificationsScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.profile,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.communities,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: CommunitiesScreen(),
            ),
          ),
        ],
      ),

      // ── Post ──────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.newPost,
        builder: (ctx, state) => NewPostScreen(
          isReelMode: state.uri.queryParameters['mode'] == 'reel',
        ),
      ),
      GoRoute(
        path: '/post/:postId',
        builder: (ctx, state) => PostDetailScreen(
          postId: state.pathParameters['postId']!,
        ),
      ),

      // ── Communities ───────────────────────────────────────────
      GoRoute(
        path: '/community/:communityId',
        builder: (ctx, state) => CommunityDetailScreen(
          communityId: state.pathParameters['communityId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.createCommunity,
        builder: (ctx, state) => const CreateCommunityScreen(),
      ),
      GoRoute(
        path: AppRoutes.myChurch,
        builder: (ctx, state) => const MyChurchScreen(),
      ),

      // ── Chat ──────────────────────────────────────────────────
      GoRoute(
        path: '/chat/:chatId',
        builder: (ctx, state) => ChatDetailScreen(
          chatId: state.pathParameters['chatId']!,
        ),
      ),
      GoRoute(
        path: '/call/:callId',
        builder: (ctx, state) => CallScreen(
          callId: state.pathParameters['callId']!,
        ),
      ),

      // ── Events ────────────────────────────────────────────────
      GoRoute(
        path: '/events',
        builder: (ctx, state) => const EventsScreen(),
      ),
      GoRoute(
        path: '/events/create',
        builder: (ctx, state) => const CreateEventScreen(),
      ),
      GoRoute(
        path: '/events/:eventId',
        builder: (ctx, state) => EventDetailScreen(
          eventId: state.pathParameters['eventId']!,
        ),
      ),

      // ── YouTube Video Player (legacy direct link) ─────────────
      GoRoute(
        path: '/video/:videoId',
        builder: (ctx, state) {
          final extra = state.extra;
          return VideoPlayerScreen(
            videoId: state.pathParameters['videoId']!,
            video: extra is YouTubeVideo ? extra : null,
          );
        },
      ),

      // ── Reels push (from feed card tap) ──────────────────────
      GoRoute(
        path: '/reels',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final videos = extra?['videos'] as List<YouTubeVideo>?;
          final index = extra?['index'] as int? ?? 0;
          return ReelsScreen(
            initialIndex: index,
            initialVideos: videos,
          );
        },
      ),

      // ── Edit Profile ──────────────────────────────────────────
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (ctx, state) => const EditProfileScreen(),
      ),

      // ── Settings ──────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.settings,
        builder: (ctx, state) => const SettingsScreen(),
      ),

      // ── Giving ──────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.give,
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return GivingScreen(
            communityId: extra?['communityId'] as String?,
            communityName: extra?['communityName'] as String?,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.givingHistory,
        builder: (ctx, state) => const GivingHistoryScreen(),
      ),

      // ── Marketplace ─────────────────────────────────────────
      GoRoute(
        path: AppRoutes.marketplace,
        builder: (ctx, state) => const MarketplaceHomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.createProduct,
        builder: (ctx, state) => const CreateProductScreen(),
      ),
      GoRoute(
        path: AppRoutes.sellerOrders,
        builder: (ctx, state) => const SellerOrdersScreen(),
      ),
      GoRoute(
        path: '/marketplace/:productId',
        builder: (ctx, state) => ProductDetailScreen(
          productId: state.pathParameters['productId']!,
        ),
      ),

      // ── Shops ────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.manageShop,
        builder: (ctx, state) => const ManageShopScreen(),
      ),
      // Must be registered before '/shop/:ownerId' below -- go_router
      // matches path segments in list order, so the dynamic route would
      // otherwise swallow this one (treating "admin" as an ownerId).
      GoRoute(
        path: AppRoutes.shopAdmin,
        builder: (ctx, state) {
          const tabNames = ['overview', 'listings', 'orders', 'settings'];
          final tab = state.uri.queryParameters['tab'];
          final index = tab == null ? 0 : tabNames.indexOf(tab);
          return ShopAdminScreen(initialTab: index < 0 ? 0 : index);
        },
      ),
      GoRoute(
        path: '/shop/:ownerId',
        builder: (ctx, state) => ShopScreen(
          ownerId: state.pathParameters['ownerId']!,
        ),
      ),

      // ── Portfolio (Profolio integration) ─────────────────────
      GoRoute(
        path: AppRoutes.myPortfolio,
        builder: (ctx, state) => const PortfolioScreen(),
      ),
      GoRoute(
        path: '/portfolio/:userId',
        builder: (ctx, state) => PortfolioScreen(
          userId: state.pathParameters['userId'],
        ),
      ),

      // ── Memberships ─────────────────────────────────────────
      GoRoute(
        path: AppRoutes.mySubscriptions,
        builder: (ctx, state) => const ManageSubscriptionScreen(),
      ),
      GoRoute(
        path: '/community/:communityId/memberships',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return TierPickerScreen(
            communityId: state.pathParameters['communityId']!,
            communityName: extra?['communityName'] as String?,
            isOwner: extra?['isOwner'] as bool? ?? false,
          );
        },
      ),

      // ── Stories ───────────────────────────────────────────────
      GoRoute(
        path: '/story/create',
        builder: (ctx, state) => const StoryCreatorScreen(),
      ),
      GoRoute(
        path: '/stories/:userId',
        builder: (ctx, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final stories = extra?['stories'] as List<StoryModel>? ?? [];
          final index = extra?['index'] as int? ?? 0;
          return StoryViewerScreen(
            userId: state.pathParameters['userId']!,
            stories: stories,
            initialIndex: index,
          );
        },
      ),

      // ── User Profile (other users) ────────────────────────────
      GoRoute(
        path: '/user/:userId',
        builder: (ctx, state) => ProfileScreen(
          userId: state.pathParameters['userId'],
        ),
      ),

      // ── Live streaming ────────────────────────────────────────
      // Routes unregistered for now — live streaming is temporarily
      // disabled (1:1 audio/video calls remain fully available). The
      // _LiveStartScreen class and the live/ feature's screens, models,
      // and repository below are left in place, unlinked from routing
      // and nav, so this can be turned back on later by re-adding these
      // two GoRoutes and the "Go Live"/LIVE-tab entry points removed
      // from home_screen.dart, new_post_screen.dart, and
      // camera_recorder_screen.dart.
      //
      // GoRoute(
      //   path: AppRoutes.liveStart,
      //   builder: (ctx, state) => const _LiveStartScreen(),
      // ),
      // GoRoute(
      //   path: '/live/:streamId/watch',
      //   builder: (ctx, state) {
      //     final stream = state.extra as LiveStreamModel;
      //     return LiveViewerScreen(stream: stream);
      //   },
      // ),

      // ── Camera recorder ───────────────────────────────────────
      GoRoute(
        path: AppRoutes.cameraRecorder,
        builder: (ctx, state) {
          final onSaved =
              state.extra as void Function(String)? ;
          return CameraRecorderScreen(onVideoSaved: onSaved);
        },
      ),
    ],

    // ── Error Handler ──────────────────────────────────────────
    errorBuilder: (ctx, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.amber),
            const SizedBox(height: 16),
            Text('Page not found', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ctx.go(AppRoutes.home),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── Go Live setup screen ───────────────────────────────────────────

class _LiveStartScreen extends StatefulWidget {
  const _LiveStartScreen();
  @override
  State<_LiveStartScreen> createState() => _LiveStartScreenState();
}

class _LiveStartScreenState extends State<_LiveStartScreen> {
  final _titleCtrl = TextEditingController();
  bool _starting = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _goLive() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _starting = true);
    try {
      final stream = await LiveRepository.instance.startStream(title: title);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
              builder: (_) => LiveHostScreen(stream: stream)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e')));
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Go Live',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Stream title',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: Colors.white),
              maxLength: 80,
              decoration: InputDecoration(
                hintText: 'What are you streaming about?',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                counterStyle: const TextStyle(color: Colors.white38),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _starting ? null : _goLive,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _starting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.live_tv, color: Colors.white),
                          SizedBox(width: 8),
                          Text('Start Streaming',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

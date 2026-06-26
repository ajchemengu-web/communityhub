import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../constants/app_routes.dart';
import '../services/supabase_service.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/auth/presentation/screens/onboarding_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
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
import '../../features/chat/presentation/screens/chats_screen.dart';
import '../../features/chat/presentation/screens/chat_detail_screen.dart';
import '../../shared/widgets/main_shell.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final isAuthenticated = SupabaseService.isAuthenticated;
      final location = state.matchedLocation;

      final authRoutes = [
        AppRoutes.login,
        AppRoutes.onboarding,
        AppRoutes.splash,
        AppRoutes.register,
        AppRoutes.setupProfile,
      ];

      final isGoingToAuth = authRoutes.any((r) => location.startsWith(r));

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
      // ── Auth Routes ─────────────────────────────────────
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
        path: AppRoutes.setupProfile,
        builder: (ctx, state) => const SetupProfileScreen(),
      ),

      // ── Main Shell (Bottom Navigation) ──────────────────
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
            path: AppRoutes.profile,
            pageBuilder: (ctx, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
        ],
      ),

      // ── Post ─────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.newPost,
        builder: (ctx, state) => const NewPostScreen(),
      ),
      GoRoute(
        path: '/post/:postId',
        builder: (ctx, state) => PostDetailScreen(
          postId: state.pathParameters['postId']!,
        ),
      ),

      // ── Notifications ─────────────────────────────────────
      GoRoute(
        path: AppRoutes.notifications,
        builder: (ctx, state) => const NotificationsScreen(),
      ),

      // ── Communities ───────────────────────────────────────
      GoRoute(
        path: AppRoutes.communities,
        builder: (ctx, state) => const CommunitiesScreen(),
      ),
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

      // ── Chat ──────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.chats,
        builder: (ctx, state) => const ChatsScreen(),
      ),
      GoRoute(
        path: '/chat/:chatId',
        builder: (ctx, state) => ChatDetailScreen(
          chatId: state.pathParameters['chatId']!,
        ),
      ),
      GoRoute(
        path: '/call/:callId',
        builder: (ctx, state) => const CallScreen(),
      ),

      // ── Events ────────────────────────────────────────────
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

      // ── Profile ───────────────────────────────────────────
      GoRoute(
        path: '/user/:userId',
        builder: (ctx, state) => ProfileScreen(
          userId: state.pathParameters['userId'],
        ),
      ),
    ],

    // ── Error Handler ─────────────────────────────────────
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

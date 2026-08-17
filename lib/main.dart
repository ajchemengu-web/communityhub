import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import 'core/services/supabase_service.dart';
import 'core/services/youtube_service.dart';
import 'core/services/notification_service.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'features/ads/data/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── Error fallback ────────────────────────────────────────
  // Flutter's default ErrorWidget.builder, in a release build (which is
  // what every real user of the deployed web app is running), renders a
  // widget whose text is stripped out entirely -- an empty Container with
  // no background color of its own. Any *build-time* exception anywhere
  // in the tree (a bad cast on unexpected data, a null field the UI
  // didn't guard against, etc.) therefore doesn't show an error at all:
  // it shows nothing, indistinguishable from the screen simply being
  // blank. That silence is exactly why bugs like this are so hard for
  // users to describe or for us to diagnose from a screenshot -- there's
  // no error text, icon, or anything else to go on.
  //
  // This doesn't fix whatever throws -- it just makes sure a thrown
  // exception is never invisible again: it still logs the real error to
  // the console (visible via browser devtools / `flutter logs`), and
  // shows a small, layout-safe icon in place of whatever failed to
  // build, instead of a silent gap.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    return Container(
      color: const Color(0xFF11151C),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: const FittedBox(
        fit: BoxFit.scaleDown,
        child: Icon(Icons.error_outline_rounded,
            color: Colors.white38, size: 28),
      ),
    );
  };

  // ── System UI ─────────────────────────────────────────────
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D1117),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Lock to portrait (can unlock for tablets later)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ── Supabase ──────────────────────────────────────────────
  await SupabaseService.initialize();

  // ── Stripe ────────────────────────────────────────────────
  // Payment providers are best-effort at startup — a missing/placeholder
  // key shouldn't block the rest of the app from launching. Giving,
  // marketplace checkout, memberships and boosts will simply fail (with
  // a user-visible error) if a provider wasn't configured.
  try {
    Stripe.publishableKey = AppConstants.stripePublishableKey;
    await Stripe.instance.applySettings();
  } catch (e) {
    debugPrint('Stripe init skipped: $e');
  }

  // ── Ads ───────────────────────────────────────────────────
  try {
    await AdService.instance.initialize();
  } catch (e) {
    debugPrint('AdMob init skipped: $e');
  }

  // ── Push Notifications (Firebase) ────────────────────────
  await NotificationService.instance.initialize();

  // ── YouTube ───────────────────────────────────────────────
  YouTubeService.instance.setApiKey(AppConstants.youtubeApiKey);

  // ── Run App ───────────────────────────────────────────────
  runApp(
    const ProviderScope(
      child: CommunityHubApp(),
    ),
  );
}

class CommunityHubApp extends ConsumerWidget {
  const CommunityHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'CommunityHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark, // Default dark; user can toggle in settings
      routerConfig: router,
      builder: (context, child) {
        // Enforce text scale factor for consistent UI across devices
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.85, 1.15),
            ),
          ),
          child: child!,
        );
      },
    );
  }
}

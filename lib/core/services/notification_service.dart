import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import 'supabase_service.dart';

// Background handler — must be top-level
@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  // Firebase is already initialised by the time this runs on Android.
  // No extra work needed; the OS shows the notification automatically.
}

class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  // Lazily assigned after Firebase.initializeApp() succeeds
  FirebaseMessaging? _fcm;
  final _local = FlutterLocalNotificationsPlugin();

  static const _channelId = 'communityhub_high';
  static const _channelName = 'CommunityHub';

  bool _ready = false;

  // ── Initialise ─────────────────────────────────────────────────

  Future<void> initialize() async {
    // firebase_options.dart has no web config (throws UnsupportedError,
    // caught below either way), and flutter_local_notifications has no
    // web implementation at all — skip straight past both rather than
    // relying on the throw/catch round trip on every web page load.
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _fcm = FirebaseMessaging.instance;
    } catch (e) {
      // Firebase not configured — push notifications disabled.
      return;
    }

    _ready = true;

    // Background handler
    FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

    // Request permission (iOS prompts; Android 13+ prompts)
    await _fcm!.requestPermission(alert: true, badge: true, sound: true);

    // Android notification channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
      playSound: true,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Local notifications init (for foreground display)
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    // Show local notification when app is in foreground
    FirebaseMessaging.onMessage.listen(_showLocal);

    // Save token on first run
    await _saveToken();
    _fcm!.onTokenRefresh.listen(_saveToken);
  }

  // ── Save FCM token to users table ──────────────────────────────

  Future<void> _saveToken([String? token]) async {
    if (!_ready) return;
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    try {
      token ??= await _fcm?.getToken();
      if (token == null) return;
      await SupabaseService.client
          .from('users')
          .update({'fcm_token': token})
          .eq('id', uid);
    } catch (_) {}
  }

  // Call this after login so the token is saved for a freshly-authed user.
  Future<void> onLogin() => _saveToken();

  // ── Show local notification (foreground) ───────────────────────

  void _showLocal(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    _local.show(
      n.hashCode,
      n.title,
      n.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

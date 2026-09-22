import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/detail_screen.dart';
import '../screens/live_tv_screen.dart';
import 'update_service.dart';
import '../widgets/update_dialog.dart';

/// Top-level background message handler required by Firebase Messaging
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  debugPrint('FCM background message received: ${message.messageId}');
}

class FcmService {
  FcmService._internal();
  static final FcmService instance = FcmService._internal();

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  // Default Topics for Broadcasting
  static const String topicAllUsers = 'all_users';
  static const String topicNewMovies = 'new_movies';
  static const String topicPopularSeries = 'popular_series';
  static const String topicLiveTvEvents = 'live_tv_events';

  bool _isInitialized = false;
  String? _fcmToken;

  bool get isInitialized => _isInitialized;
  String? get fcmToken => _fcmToken;

  /// Initialize Firebase Cloud Messaging, request permissions, and subscribe to default topics.
  static Future<void> init() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // 1. Request Notification Permissions (Handles Android 13+ & iOS)
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      debugPrint('FCM permission authorizationStatus: ${settings.authorizationStatus}');

      // 2. Fetch Device Registration Token (for targeting this device directly)
      try {
        final token = await messaging.getToken();
        instance._fcmToken = token;
        debugPrint('FCM Device Token: $token');
      } catch (e) {
        debugPrint('Could not fetch FCM token: $e');
      }

      // 3. Automatically subscribe to broadcast topics
      await _subscribeToDefaultTopics(messaging);

      // 4. Configure foreground presentation options (alert sound/banner)
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 5. Handle foreground notification arrivals
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('FCM Foreground message: ${message.notification?.title}');
        instance._showInAppNotification(message);
      });

      // 6. Handle notification click when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('FCM onMessageOpenedApp clicked: ${message.data}');
        instance._handleNotificationNavigation(message.data);
      });

      // 7. Check if app was opened from terminated state by a notification click
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('FCM App opened from initialMessage: ${initialMessage.data}');
        Timer(const Duration(milliseconds: 1000), () {
          instance._handleNotificationNavigation(initialMessage.data);
        });
      }

      instance._isInitialized = true;
      debugPrint('FcmService initialized successfully.');
    } catch (e) {
      debugPrint('FcmService initialization error (running safely): $e');
      instance._isInitialized = false;
    }
  }

  /// Subscribe to global broadcast topics
  static Future<void> _subscribeToDefaultTopics(FirebaseMessaging messaging) async {
    final topics = [
      topicAllUsers,
      topicNewMovies,
      topicPopularSeries,
      topicLiveTvEvents,
    ];
    for (final topic in topics) {
      try {
        await messaging.subscribeToTopic(topic);
        debugPrint('Subscribed to FCM topic: $topic');
      } catch (e) {
        debugPrint('Failed to subscribe to FCM topic $topic: $e');
      }
    }
  }

  /// Display a stylish TV-friendly in-app notification banner when message arrives while app is open
  void _showInAppNotification(RemoteMessage message) {
    final title = message.notification?.title ?? message.data['title'] ?? 'MovieBox Notification';
    final body = message.notification?.body ?? message.data['body'] ?? '';
    final data = message.data;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF1F1F1F),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE50914), width: 1.5),
        ),
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Color(0xFFE50914), size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      body,
                      style: GoogleFonts.outfit(color: Colors.grey.shade300, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        action: data.isNotEmpty
            ? SnackBarAction(
                label: 'BUKA',
                textColor: const Color(0xFFE50914),
                onPressed: () {
                  _handleNotificationNavigation(data);
                },
              )
            : null,
      ),
    );
  }

  /// Route user directly to the targeted media or update screen based on notification payload
  void _handleNotificationNavigation(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    final type = (data['type'] ?? '').toString().toLowerCase().trim();
    final subjectId = (data['subjectId'] ?? data['id'] ?? '').toString().trim();
    final provider = (data['provider'] ?? 'moviebox').toString().trim();

    // 1. Movie or Series details
    if ((type == 'movie' || type == 'series' || type == 'detail') && subjectId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: RouteSettings(name: '/detail/$subjectId'),
          builder: (context) => DetailScreen(
            subjectId: subjectId,
            provider: provider,
          ),
        ),
      );
      return;
    }

    // 2. Live TV Screen
    if (type == 'live_tv' || type == 'livetv' || type == 'channel') {
      Navigator.push(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/live_tv'),
          builder: (context) => const LiveTvScreen(),
        ),
      );
      return;
    }

    // 3. New App Update Prompt
    if (type == 'update') {
      UpdateService.instance.checkForUpdate().then((release) {
        if (release != null && navigatorKey.currentContext != null) {
          UpdateDialog.show(navigatorKey.currentContext!, release);
        }
      });
      return;
    }
  }
}

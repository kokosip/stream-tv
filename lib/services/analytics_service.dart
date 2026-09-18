import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';

class AnalyticsService {
  static bool get _isAvailable => Firebase.apps.isNotEmpty;
  static String? _cachedDeviceId;
  static String? get deviceId => _cachedDeviceId;

  /// Initialize persistent unique device identifier and attach to Crashlytics and Analytics.
  static Future<String> initDeviceUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? id = prefs.getString('app_device_id');
      if (id == null || id.isEmpty) {
        final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
        final randomBytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
        final randomHash = sha256.convert(randomBytes).toString().substring(0, 10);
        id = 'tv_${timestamp}_$randomHash';
        await prefs.setString('app_device_id', id);
      }
      _cachedDeviceId = id;

      // Attach to Firebase Analytics
      final analytics = _analytics;
      if (analytics != null) {
        await analytics.setUserId(id: id);
      }

      // Attach to Firebase Crashlytics
      try {
        await FirebaseCrashlytics.instance.setUserIdentifier(id);
        await FirebaseCrashlytics.instance.setCustomKey('device_id', id);
      } catch (_) {}

      debugPrint('[Analytics] Initialized device user ID: $id');
      return id;
    } catch (e) {
      debugPrint('[Analytics] Error initializing device user ID: $e');
      return '';
    }
  }

  static FirebaseAnalytics? get _analytics {
    if (!_isAvailable) return null;
    try {
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  /// Observer to automatically track screen transitions in MaterialApp.
  static NavigatorObserver get observer {
    final analytics = _analytics;
    if (analytics == null) return NavigatorObserver();
    return FirebaseAnalyticsObserver(analytics: analytics);
  }

  /// Log a manual screen view.
  static Future<void> logScreenView(String screenName) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logScreenView(screenName: screenName);
      debugPrint('[Analytics] Screen viewed: $screenName');
    } catch (e) {
      debugPrint('[Analytics] Error logging screen view: $e');
    }
  }

  /// Log playback event (Movies, TV Shows, IPTV Channels).
  static Future<void> logPlayContent({
    required String title,
    required String contentType, // e.g., 'movie', 'series', 'iptv'
    String? category,
    String? episode,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      final Map<String, Object> params = {
        'content_title': title.length > 100 ? title.substring(0, 100) : title,
        'content_type': contentType,
      };
      if (category != null) params['category'] = category;
      if (episode != null) params['episode'] = episode;

      await analytics.logEvent(
        name: 'play_content',
        parameters: params,
      );
      debugPrint('[Analytics] Play content: $title ($contentType)');
    } catch (e) {
      debugPrint('[Analytics] Error logging play content: $e');
    }
  }

  /// Log search query.
  static Future<void> logSearch(String searchTerm) async {
    if (searchTerm.trim().isEmpty) return;
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logSearch(searchTerm: searchTerm.trim());
      debugPrint('[Analytics] Search query: $searchTerm');
    } catch (e) {
      debugPrint('[Analytics] Error logging search: $e');
    }
  }

  /// Log favorite toggle.
  static Future<void> logFavoriteToggle({
    required String title,
    required bool isFavorite,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logEvent(
        name: isFavorite ? 'add_to_favorites' : 'remove_from_favorites',
        parameters: {
          'content_title': title.length > 100 ? title.substring(0, 100) : title,
        },
      );
    } catch (e) {
      debugPrint('[Analytics] Error logging favorite toggle: $e');
    }
  }

  /// Set user property (e.g. app language, device type).
  static Future<void> setUserProperty({
    required String name,
    required String? value,
  }) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.setUserProperty(name: name, value: value);
    } catch (e) {
      debugPrint('[Analytics] Error setting user property: $e');
    }
  }
}


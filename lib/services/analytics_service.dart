import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  static bool get _isAvailable => Firebase.apps.isNotEmpty;

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


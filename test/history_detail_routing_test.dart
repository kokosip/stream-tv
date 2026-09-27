import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:MovieBox/services/playback_progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('History & Detail Provider Self-Healing Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('getRecentPlays auto-heals MovieBox 64-bit subjectId mistakenly saved as tmdb', () async {
      final prefs = await SharedPreferences.getInstance();
      final mockHistory = [
        {
          'subjectId': '6571618275791621816',
          'provider': 'tmdb',
          'title': 'Test Movie',
          'season': 1,
          'episode': 1,
          'positionMs': 10000,
          'durationMs': 100000,
        },
        {
          'subjectId': 'tmdb_12345',
          'provider': 'tmdb',
          'title': 'Real TMDB Item',
          'season': 0,
          'episode': 0,
          'positionMs': 50000,
          'durationMs': 100000,
        }
      ];
      await prefs.setString('recent_plays_list', jsonEncode(mockHistory));

      final result = await PlaybackProgressService.getRecentPlays();
      expect(result.length, equals(2));

      // First item with 64-bit ID must be healed to moviebox
      expect(result[0]['subjectId'], equals('6571618275791621816'));
      expect(result[0]['provider'], equals('moviebox'));

      // Real TMDB item must remain tmdb
      expect(result[1]['subjectId'], equals('tmdb_12345'));
      expect(result[1]['provider'], equals('tmdb'));
    });

    test('saveProgress sanitizes provider to moviebox if subjectId is a MovieBox 64-bit ID', () async {
      await PlaybackProgressService.saveProgress(
        '6571618275791621816',
        1,
        1,
        25000,
        120000,
        title: 'Breaking Bad Episode',
        provider: 'tmdb', // passed by mistake
      );

      final recents = await PlaybackProgressService.getRecentPlays();
      expect(recents.isNotEmpty, isTrue);
      expect(recents.first['provider'], equals('moviebox'));
      expect(recents.first['subjectId'], equals('6571618275791621816'));
    });

    test('series 64-bit ID is recognized as MovieBox and sanitized properly', () async {
      const seriesId = '1382465867459478920';
      await PlaybackProgressService.saveProgress(
        seriesId,
        2,
        4,
        60000,
        300000,
        title: 'Better Call Saul',
        provider: 'tmdb',
      );

      final recents = await PlaybackProgressService.getRecentPlays();
      expect(recents.first['subjectId'], equals(seriesId));
      expect(recents.first['provider'], equals('moviebox'));
      expect(recents.first['season'], equals(2));
      expect(recents.first['episode'], equals(4));
    });
  });
}

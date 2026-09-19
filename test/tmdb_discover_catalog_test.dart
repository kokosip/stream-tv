import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/tmdb_service.dart';

void main() {
  group('TMDB Discover Catalog with_original_language & newest sort tests', () {
    final tmdbService = TmdbService();

    test('normalizeItem properly retains releaseDate and creates standard structure', () {
      final rawIndoMovie = {
        "id": 123456,
        "title": "Film Indonesia Terbaru",
        "original_title": "Film Indonesia Terbaru",
        "original_language": "id",
        "release_date": "2026-09-18",
        "poster_path": "/poster123.jpg",
        "vote_average": 8.0,
        "vote_count": 12,
        "overview": "Sinopsis film Indonesia",
      };

      final normalized = tmdbService.normalizeItem(rawIndoMovie, mediaType: 'movie');
      expect(normalized['subjectId'], equals('tmdb_123456'));
      expect(normalized['title'], equals('Film Indonesia Terbaru'));
      expect(normalized['releaseDate'], equals('2026-09-18'));
      expect(normalized['provider'], equals('tmdb'));
      expect(normalized['subjectType'], equals(1));
    });

    test('normalizeItem handles Korean TV show with first_air_date', () {
      final rawDrama = {
        "id": 99999,
        "name": "Drakor Terbaru",
        "original_name": "Drakor Terbaru",
        "original_language": "ko",
        "first_air_date": "2026-09-19",
        "poster_path": "/drakor.jpg",
        "vote_average": 8.5,
        "vote_count": 25,
        "overview": "Sinopsis drakor",
      };

      final normalized = tmdbService.normalizeItem(rawDrama, mediaType: 'tv');
      expect(normalized['subjectId'], equals('tmdb_99999'));
      expect(normalized['title'], equals('Drakor Terbaru'));
      expect(normalized['subjectType'], equals(2));
    });

    test('normalizeItem handles Filipino / Tagalog movie correctly', () {
      final rawTagalog = {
        "id": 55555,
        "title": "String Bean Boy",
        "original_title": "String Bean Boy",
        "original_language": "tl",
        "release_date": "2026-09-18",
        "poster_path": "/philippines.jpg",
        "vote_average": 7.0,
        "vote_count": 5,
        "overview": "Sinopsis film Filipina",
      };

      final normalized = tmdbService.normalizeItem(rawTagalog, mediaType: 'movie');
      expect(normalized['subjectId'], equals('tmdb_55555'));
      expect(normalized['title'], equals('String Bean Boy'));
      expect(normalized['releaseDate'], equals('2026-09-18'));
      expect(normalized['provider'], equals('tmdb'));
      expect(normalized['subjectType'], equals(1));
    });

    test('normalizeItem handles Taiwanese drama correctly', () {
      final rawTaiwan = {
        "id": 77777,
        "name": "The Fixers",
        "original_name": "The Fixers",
        "origin_country": ["TW"],
        "original_language": "zh",
        "first_air_date": "2026-09-17",
        "poster_path": "/taiwan.jpg",
        "vote_average": 8.1,
        "vote_count": 10,
        "overview": "Sinopsis drama Taiwan",
      };

      final normalized = tmdbService.normalizeItem(rawTaiwan, mediaType: 'tv');
      expect(normalized['subjectId'], equals('tmdb_77777'));
      expect(normalized['title'], equals('The Fixers'));
      expect(normalized['releaseDate'], equals('2026-09-17'));
      expect(normalized['provider'], equals('tmdb'));
      expect(normalized['subjectType'], equals(2));
    });

    test('TmdbService.includeAdult can be toggled to control adult content', () {
      TmdbService.includeAdult = true;
      expect(TmdbService.includeAdult, isTrue);
      TmdbService.includeAdult = false;
      expect(TmdbService.includeAdult, isFalse);
    });
  });
}

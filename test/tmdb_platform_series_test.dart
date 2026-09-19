import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/tmdb_service.dart';

void main() {
  group('TMDB Platform TV Series vs Movie Normalization Tests', () {
    final tmdbService = TmdbService();

    test('Loki TV Series from /discover/tv is normalized as TV show (subjectType: 2)', () {
      final rawLokiFromDiscoverTv = {
        "backdrop_path": "/kEl2t3PbpPuIiEBQyoH0h2v1B94.jpg",
        "first_air_date": "2021-06-09",
        "genre_ids": [18, 10765],
        "id": 84958,
        "name": "Loki",
        "origin_country": ["US"],
        "original_language": "en",
        "original_name": "Loki",
        "overview": "After stealing the Tesseract during the events of Avengers: Endgame...",
        "popularity": 123.456,
        "poster_path": "/voHUmlvfztv5jHCm25a4rMizq2y.jpg",
        "vote_average": 8.164,
        "vote_count": 11370
      };

      // 1. When mediaType: 'tv' is specified
      final normalizedWithMediaType = tmdbService.normalizeItem(rawLokiFromDiscoverTv, mediaType: 'tv');
      expect(normalizedWithMediaType['subjectType'], equals(2));
      expect(normalizedWithMediaType['title'], equals('Loki'));
      expect(normalizedWithMediaType['subjectId'], equals('tmdb_84958'));
      expect(normalizedWithMediaType['description'], contains('Tesseract'));

      // 2. Even when mediaType is omitted, first_air_date & name identify it as TV
      final normalizedWithoutMediaType = tmdbService.normalizeItem(rawLokiFromDiscoverTv);
      expect(normalizedWithoutMediaType['subjectType'], equals(2));
      expect(normalizedWithoutMediaType['title'], equals('Loki'));

      // 3. When re-normalizing an already normalized map
      final reNormalized = tmdbService.normalizeItem(normalizedWithMediaType);
      expect(reNormalized['subjectType'], equals(2));
      expect(reNormalized['title'], equals('Loki'));
    });

    test('Movie from /discover/movie is normalized as Movie (subjectType: 1)', () {
      final rawAvatarFromDiscoverMovie = {
        "backdrop_path": "/vL5LR6WdxWPjLPFRLe133jXWsh5.jpg",
        "release_date": "2009-12-15",
        "genre_ids": [28, 12, 14, 878],
        "id": 19995,
        "title": "Avatar",
        "original_title": "Avatar",
        "overview": "In the 22nd century, a paraplegic Marine...",
        "popularity": 89.123,
        "poster_path": "/kyeqWdyUXW608qlYkRqosgbbJyK.jpg",
        "vote_average": 7.58,
        "vote_count": 31000
      };

      final normalizedMovie = tmdbService.normalizeItem(rawAvatarFromDiscoverMovie, mediaType: 'movie');
      expect(normalizedMovie['subjectType'], equals(1));
      expect(normalizedMovie['title'], equals('Avatar'));
      expect(normalizedMovie['subjectId'], equals('tmdb_19995'));
      expect(normalizedMovie['description'], contains('paraplegic Marine'));
    });
  });
}

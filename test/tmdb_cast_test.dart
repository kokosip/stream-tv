import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/tmdb_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('TmdbService Cast & Credits Tests', () {
    final tmdb = TmdbService();

    test('getCredits with direct Movie TMDB ID returns valid cast', () async {
      // Inception TMDB ID = 27205
      final cast = await tmdb.getCredits(tmdbId: 27205, isTv: false);
      expect(cast, isNotEmpty);
      final first = cast.first;
      expect(first['name'], isNotNull);
      expect(first['character'], isNotNull);
      print('Inception top cast: ${first['name']} as ${first['character']} (${first['profileUrl']})');
    });

    test('getCredits with direct TV TMDB ID returns valid cast', () async {
      // Breaking Bad TMDB ID = 1396
      final cast = await tmdb.getCredits(tmdbId: 1396, isTv: true);
      expect(cast, isNotEmpty);
      final first = cast.first;
      expect(first['name'], isNotNull);
      expect(first['character'], isNotNull);
      print('Breaking Bad top cast: ${first['name']} as ${first['character']} (${first['profileUrl']})');
    });

    test('findTmdbId and getCredits by title and year', () async {
      final cast = await tmdb.getCredits(title: 'Interstellar', year: 2014, isTv: false);
      expect(cast, isNotEmpty);
      print('Interstellar top cast count: ${cast.length}, first: ${cast.first['name']}');
    });
  });
}

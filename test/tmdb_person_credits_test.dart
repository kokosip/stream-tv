import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/tmdb_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('TmdbService Person Credits Tests', () {
    final tmdb = TmdbService();

    test('getPersonDetails and getPersonCredits for Robert Downey Jr. (3223)', () async {
      final person = await tmdb.getPersonDetails(3223);
      expect(person, isNotNull);
      expect(person!['name'], equals('Robert Downey Jr.'));
      print('Person name: ${person['name']}, birthday: ${person['birthday']}');

      final credits = await tmdb.getPersonCredits(3223);
      expect(credits, isNotEmpty);
      print('Robert Downey Jr. credits count: ${credits.length}');

      // Check if Iron Man or Oppenheimer is present
      final titles = credits.map((c) => (c['title'] ?? c['name']).toString().toLowerCase()).toList();
      expect(titles.any((t) => t.contains('iron man') || t.contains('oppenheimer')), isTrue);

      final first = credits.first;
      print('Top credit: ${first['title']} (${first['releaseDate']}) as ${first['character']} [Rating: ${first['imdbRate']}]');
    });
  });
}

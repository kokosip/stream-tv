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
    test('searchPerson for Tom Holland and verify credits', () async {
      final people = await tmdb.searchPeople('Tom Holland');
      expect(people, isNotEmpty);
      // Check deduplication: only 1 Tom Holland for Acting
      final actingTomHollands = people.where((p) => p['name'] == 'Tom Holland' && p['department'] == 'Acting').toList();
      expect(actingTomHollands.length, equals(1));
      final person = people.first;
      print('Found person: ${person['name']}, ID: ${person['id']}');

      final credits = await tmdb.getPersonCredits(person['id']);
      print('Total credits for ${person['name']}: ${credits.length}');
      final titles = credits.take(5).map((c) => "${c['title']} as ${c['character']}").toList();
      expect(credits, isNotEmpty);
      final titlesLower = credits.map((c) => (c['title'] ?? '').toString().toLowerCase()).toList();
      expect(titlesLower.any((t) => t.contains('spider-man')), isTrue);

      final spiderManCredit = credits.firstWhere((c) => (c['title'] ?? '').toString().toLowerCase().contains('spider-man'));
      expect(spiderManCredit['character'], isNotNull);
      expect((spiderManCredit['character'] as String).toLowerCase(), contains('peter parker'));
    });

    test('searchPerson for non-actor query', () async {
      final people = await tmdb.searchPeople('Inception');
      print('Inception people: ${people.map((p) => p['name']).toList()}');
      final spiderman = await tmdb.searchPeople('Spider-Man');
      print('Spider-Man people: ${spiderman.map((p) => "${p['name']} (pop: ${p['popularity']})").toList()}');
    });
  });
}

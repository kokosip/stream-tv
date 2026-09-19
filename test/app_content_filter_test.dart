import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/app_content_filter_service.dart';

void main() {
  group('AppContentFilterService Tests', () {
    test('Correctly identifies titles with [Hindi] tags', () {
      expect(AppContentFilterService.hasHindiTag("A Shop for Killers [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("A Love Other Than Yours [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Bigg Boss [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Lanterns [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Fear Factor: Khatron Ke Khiladi [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Reborn Rich [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Operation Safed Sagar [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Matka King [Hindi]"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Money Heist (Hindi Dubbed)"), isTrue);
      expect(AppContentFilterService.hasHindiTag("[Hindi] Stranger Things"), isTrue);
      expect(AppContentFilterService.hasHindiTag("Squid Game [Hindi - Org]"), isTrue);
    });

    test('Does not falsely flag original titles or legitimate Indian movies without [Hindi] tag', () {
      expect(AppContentFilterService.hasHindiTag("Prince of Mollywood"), isFalse);
      expect(AppContentFilterService.hasHindiTag("Inception"), isFalse);
      expect(AppContentFilterService.hasHindiTag("Loki"), isFalse);
      expect(AppContentFilterService.hasHindiTag("Hindi Medium"), isFalse);
      expect(AppContentFilterService.hasHindiTag("Jawan"), isFalse);
      expect(AppContentFilterService.hasHindiTag("RRR"), isFalse);
    });

    test('filterList hides Hindi-tagged items when filter is active', () {
      AppContentFilterService.filterHindi.value = true;

      final items = [
        {"title": "Prince of Mollywood", "id": 1},
        {"title": "A Shop for Killers [Hindi]", "id": 2},
        {"title": "Lanterns [Hindi]", "id": 3},
        {"title": "Breaking Bad", "id": 4},
      ];

      final filtered = AppContentFilterService.filterList(items);
      expect(filtered.length, equals(2));
      expect(filtered.map((e) => e['title']).toList(), equals(["Prince of Mollywood", "Breaking Bad"]));

      // When filter is disabled, all items remain
      AppContentFilterService.filterHindi.value = false;
      final unfiltered = AppContentFilterService.filterList(items);
      expect(unfiltered.length, equals(4));
    });
  });
}

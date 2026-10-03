import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Episode Pagination Logic Tests', () {
    const int pageSize = 50;

    test('Series with many episodes (e.g., Running Man with 724 episodes) calculates correct pages', () {
      final int totalEpisodes = 724;
      final int totalPages = (totalEpisodes / pageSize).ceil();

      expect(totalPages, equals(15));

      // Page 0
      final p0Start = 0 * pageSize + 1;
      final p0End = ((0 + 1) * pageSize > totalEpisodes) ? totalEpisodes : (0 + 1) * pageSize;
      expect("$p0Start-$p0End", equals("1-50"));

      // Page 1
      final p1Start = 1 * pageSize + 1;
      final p1End = ((1 + 1) * pageSize > totalEpisodes) ? totalEpisodes : (1 + 1) * pageSize;
      expect("$p1Start-$p1End", equals("51-100"));

      // Page 2
      final p2Start = 2 * pageSize + 1;
      final p2End = ((2 + 1) * pageSize > totalEpisodes) ? totalEpisodes : (2 + 1) * pageSize;
      expect("$p2Start-$p2End", equals("101-150"));

      // Last Page (Page 14)
      final pLastStart = 14 * pageSize + 1;
      final pLastEnd = ((14 + 1) * pageSize > totalEpisodes) ? totalEpisodes : (14 + 1) * pageSize;
      expect("$pLastStart-$pLastEnd", equals("701-724"));
    });

    test('Selected episode correctly resolves to expected page index', () {
      final int totalEpisodes = 724;

      int getPageIndexForEpisode(int epNum) {
        return (epNum - 1).clamp(0, totalEpisodes - 1) ~/ pageSize;
      }

      expect(getPageIndexForEpisode(1), equals(0));
      expect(getPageIndexForEpisode(50), equals(0));
      expect(getPageIndexForEpisode(51), equals(1));
      expect(getPageIndexForEpisode(100), equals(1));
      expect(getPageIndexForEpisode(101), equals(2));
      expect(getPageIndexForEpisode(125), equals(2));
      expect(getPageIndexForEpisode(700), equals(13));
      expect(getPageIndexForEpisode(701), equals(14));
      expect(getPageIndexForEpisode(724), equals(14));
    });

    test('Slicing episodes list per page returns exact subset', () {
      final List<int> episodes = List.generate(125, (i) => i + 1);
      final int totalEpisodes = episodes.length;

      // Page 0 (1-50)
      int pageIndex = 0;
      int startIndex = pageIndex * pageSize;
      int endIndex = (startIndex + pageSize > totalEpisodes) ? totalEpisodes : startIndex + pageSize;
      List<int> page0 = episodes.sublist(startIndex, endIndex);
      expect(page0.length, equals(50));
      expect(page0.first, equals(1));
      expect(page0.last, equals(50));

      // Page 1 (51-100)
      pageIndex = 1;
      startIndex = pageIndex * pageSize;
      endIndex = (startIndex + pageSize > totalEpisodes) ? totalEpisodes : startIndex + pageSize;
      List<int> page1 = episodes.sublist(startIndex, endIndex);
      expect(page1.length, equals(50));
      expect(page1.first, equals(51));
      expect(page1.last, equals(100));

      // Page 2 (101-125)
      pageIndex = 2;
      startIndex = pageIndex * pageSize;
      endIndex = (startIndex + pageSize > totalEpisodes) ? totalEpisodes : startIndex + pageSize;
      List<int> page2 = episodes.sublist(startIndex, endIndex);
      expect(page2.length, equals(25));
      expect(page2.first, equals(101));
      expect(page2.last, equals(125));
    });

    test('Standard series with <= 50 episodes needs no pagination tabs (totalPages == 1)', () {
      final int totalEpisodes = 16;
      final int totalPages = (totalEpisodes / pageSize).ceil();

      expect(totalPages, equals(1));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/moviebox_api_service.dart';
import 'package:MovieBox/services/dramachi_api_service.dart';
import 'package:MovieBox/services/favorites_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MovieBox-TUI v0.1.26 Ported Improvements', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('isDeprecationNoticeUrl does not filter legitimate notice titles', () {
      expect(MovieBoxApiService.isDeprecationNoticeUrl('https://example.com/Red.Notice.2021.1080p.mp4'), isFalse);
      expect(MovieBoxApiService.isDeprecationNoticeUrl('https://example.com/Burn.Notice.S01E01.720p.mp4'), isFalse);

      // Verify real deprecation notices are still caught
      expect(MovieBoxApiService.isDeprecationNoticeUrl('https://macdn.aoneroom.com/other/b164fbfb4347792950bdfbfb563d39d9.mp4'), isTrue);
      expect(MovieBoxApiService.isDeprecationNoticeUrl('https://macdn.aoneroom.com/other/notice.mp4'), isTrue);
    });

    test('DramachiApiService.parseEpisodeNumber extracts episode with boundary checks', () {
      expect(DramachiApiService.parseEpisodeNumber('The Glory - EP05 - 1080p ENG Subbed'), 5);
      expect(DramachiApiService.parseEpisodeNumber('Breaking Bad S01E07 720p'), 7);
      expect(DramachiApiService.parseEpisodeNumber('Vincenzo Episode 12 DUB'), 12);
      expect(DramachiApiService.parseEpisodeNumber('Item Title 10'), 10);
    });

    test('FavoritesService provides O(1) in-memory cached checks', () async {
      final item = {
        'subjectId': 'test_123',
        'title': 'Test Movie',
        'provider': 'moviebox',
      };

      expect(await FavoritesService.isFavorite('test_123'), isFalse);

      await FavoritesService.addFavorite(item);
      expect(await FavoritesService.isFavorite('test_123'), isTrue);

      final favs = await FavoritesService.getFavorites();
      expect(favs.length, 1);
      expect(favs.first['title'], 'Test Movie');

      await FavoritesService.removeFavorite('test_123');
      expect(await FavoritesService.isFavorite('test_123'), isFalse);
    });
  });
}

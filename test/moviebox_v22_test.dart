import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/moviebox_api_service.dart';
import 'package:MovieBox/services/fourkhdhub_api_service.dart';
import 'package:MovieBox/services/online_subtitle_service.dart';
import 'package:MovieBox/services/dramachi_api_service.dart';

void main() {
  group('MovieBox-TUI v0.1.22 Updates', () {
    test('MovieBoxApiService extracts DASH manifest from Edge-Cache-Cookie urlprefix', () {
      const rawPrefixUrl = 'https://stream.example.com/videos/dash_manifest';
      final base64Prefix = base64UrlEncode(utf8.encode(rawPrefixUrl)).replaceAll('=', '');
      final cookieHeader = 'Edge-Cache-Cookie=urlprefix=$base64Prefix:sign=xyz123:t=999999999';

      final resolved = MovieBoxApiService.resolveDashManifestFromPolicy(cookieHeader);
      expect(resolved, '$rawPrefixUrl/index.mpd');
    });

    test('MovieBoxApiService filters deprecation notice video URLs', () {
      const noticeUrl = 'https://macdn.aoneroom.com/other/b164fbfb4347792950bdfbfb563d39d9.mp4';
      const validUrl = 'https://macdn.aoneroom.com/media/2024/09/avatar_1080p.mp4';

      expect(MovieBoxApiService.isDeprecationNoticeUrl(noticeUrl), isTrue);
      expect(MovieBoxApiService.isDeprecationNoticeUrl(validUrl), isFalse);
    });

    test('FourKHdHubApiService detects various quality tokens', () {
      expect(FourKHdHubApiService.detectQuality('Interstellar.2014.2160p.UHD.BluRay.x265'), '2160p');
      expect(FourKHdHubApiService.detectQuality('Breaking.Bad.S01E01.1080p.FHD.WEB-DL'), '1080p');
      expect(FourKHdHubApiService.detectQuality('Movie.2023.720p.HD.WEBRip'), '720p');
      expect(FourKHdHubApiService.detectQuality('Old.Show.480p.SD'), '480p');
      expect(FourKHdHubApiService.detectQuality('Random.Video.NoQualityTag'), isNull);
    });

    test('OnlineSubtitleItem cleans and formats subtitle filename correctly', () {
      // Episode subtitle
      final epSub = OnlineSubtitleItem.fromJson({
        'id': 'sub1',
        'url': 'https://example.com/sub1.srt',
        'lang': 'en',
      }, mediaTitle: 'Stranger Things', defaultSeason: 4, defaultEpisode: 1);

      expect(epSub.fileName, 'Stranger Things - S04E01.srt');

      // Movie subtitle
      final movieSub = OnlineSubtitleItem.fromJson({
        'id': 'sub2',
        'url': 'https://example.com/sub2.srt',
        'lang': 'id',
      }, mediaTitle: 'Inception');

      expect(movieSub.fileName, 'Inception.srt');
    });

    test('DramachiApiService handles ID and dub track parsing', () {
      const subjectId = '654321::korean_dub';
      final parts = subjectId.split('::');
      expect(parts.length, 2);
      expect(parts[0], '654321');
      expect(parts[1], 'korean_dub');

      final api = DramachiApiService();
      expect(api.baseUrl, 'https://api.nodeobjects.com/');
    });
  });
}

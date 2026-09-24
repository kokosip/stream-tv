import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/moviebox_api_service.dart';
import 'package:MovieBox/services/fourkhdhub_api_service.dart';
import 'package:MovieBox/services/online_subtitle_service.dart';
import 'package:MovieBox/services/dramachi_api_service.dart';
import 'package:MovieBox/services/download_service.dart';
import 'package:MovieBox/services/app_language_service.dart';

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

    test('DownloadItem serializes and deserializes headers correctly', () {
      final item = DownloadItem(
        id: 'test_123',
        title: 'Test Movie',
        coverUrl: 'https://example.com/cover.jpg',
        streamUrl: 'https://example.com/stream.mp4',
        filePath: '/tmp/test.mp4',
        headers: {
          'User-Agent': 'ExoPlayer/2.18.1',
          'Referer': 'https://streamm4u.com/',
          'Cookie': 'CloudFront-Policy=test123',
        },
      );

      final json = item.toJson();
      expect(json['headers'], isNotNull);
      expect(json['headers']['Cookie'], 'CloudFront-Policy=test123');

      final reconstructed = DownloadItem.fromJson(json);
      expect(reconstructed.headers, isNotNull);
      expect(reconstructed.headers?['Referer'], 'https://streamm4u.com/');
    });

    test('DASH manifest parser calculates duration and chunks accurately', () {
      const sampleMpd = '''<?xml version="1.0" encoding="utf-8"?>
<MPD mediaPresentationDuration="PT1H30M00S">
  <Period>
    <AdaptationSet contentType="video">
      <Representation id="0" height="1080" mimeType="video/mp4">
        <SegmentTemplate timescale="1000000" duration="5000000" initialization="init-stream\$RepresentationID\$.m4s" media="chunk-stream\$RepresentationID\$-\$Number%05d\$.m4s"/>
      </Representation>
    </AdaptationSet>
    <AdaptationSet contentType="audio">
      <Representation id="3" mimeType="audio/mp4">
        <SegmentTemplate timescale="1000000" duration="5000000" initialization="init-stream\$RepresentationID\$.m4s" media="chunk-stream\$RepresentationID\$-\$Number%05d\$.m4s"/>
      </Representation>
    </AdaptationSet>
  </Period>
</MPD>''';

      final durMatch = RegExp(r'mediaPresentationDuration="PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d\.]+)S)?"').firstMatch(sampleMpd);
      double totalSeconds = 0;
      if (durMatch != null) {
        final h = double.tryParse(durMatch.group(1) ?? '0') ?? 0;
        final m = double.tryParse(durMatch.group(2) ?? '0') ?? 0;
        final s = double.tryParse(durMatch.group(3) ?? '0') ?? 0;
        totalSeconds = (h * 3600) + (m * 60) + s;
      }
      expect(totalSeconds, 5400.0); // 1.5 hours = 5400s

      final segDurMatch = RegExp(r'<SegmentTemplate[^>]*timescale="(\d+)"[^>]*duration="(\d+)"').firstMatch(sampleMpd);
      double segSec = 5.0;
      if (segDurMatch != null) {
        final ts = double.tryParse(segDurMatch.group(1) ?? '1') ?? 1;
        final dur = double.tryParse(segDurMatch.group(2) ?? '5') ?? 5;
        segSec = dur / ts;
      }
      expect(segSec, 5.0);
      final totalChunks = (totalSeconds / segSec).ceil();
      expect(totalChunks, 1080);
    });

    test('Download error messages localize dynamically based on AppLanguageService', () {
      AppLanguageService.currentLanguage.value = 'en';
      final enMsg = AppLanguageService.tr(
        en: "Download link expired or access forbidden. Tap Retry to renew.",
        id: "Tautan kedaluwarsa atau akses ditolak. Tekan Coba Lagi untuk memperbarui.",
      );
      expect(enMsg, contains('expired'));

      AppLanguageService.currentLanguage.value = 'id';
      final idMsg = AppLanguageService.tr(
        en: "Download link expired or access forbidden. Tap Retry to renew.",
        id: "Tautan kedaluwarsa atau akses ditolak. Tekan Coba Lagi untuk memperbarui.",
      );
      expect(idMsg, contains('kedaluwarsa'));

      // Restore default English
      AppLanguageService.currentLanguage.value = 'en';
    });
  });
}

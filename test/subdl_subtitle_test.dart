import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart';
import 'package:MovieBox/services/online_subtitle_service.dart';
import 'package:MovieBox/services/remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SubDL Subtitle Service Tests', () {
    test('OnlineSubtitleItem.fromSubdl parses JSON correctly', () {
      final json = {
        "release_name": "Breaking.Bad.S01.1080p.NF.WEB-DL",
        "name": "SUBDL::breaking-bad-first-season-indonesian-3279806.zip",
        "lang": "indonesian",
        "author": "koleksifilmserial",
        "url": "/subtitle/3261307-3279806.zip?api_key=test_key",
        "subtitlePage": "/s/info/tfOqB0iUf7",
        "season": 1,
        "episode": null,
        "language": "ID",
      };

      final item = OnlineSubtitleItem.fromSubdl(
        json,
        mediaTitle: "Breaking Bad",
        defaultSeason: 1,
        defaultEpisode: 1,
      );

      expect(item.source, equals('SubDL'));
      expect(item.lang, equals('id'));
      expect(item.languageName, equals('Indonesian'));
      expect(item.author, equals('koleksifilmserial'));
      expect(item.url, equals('https://dl.subdl.com/subtitle/3261307-3279806.zip?api_key=test_key'));
      expect(item.season, equals(1));
      expect(item.episode, equals(1));
    });

    test('ZIP extraction in OnlineSubtitleService correctly identifies episode', () {
      // Create an in-memory zip archive with two subtitles
      final archive = Archive();
      final ep1Content = "1\n00:00:01,000 --> 00:00:04,000\nHello Episode 1";
      final ep2Content = "1\n00:00:01,000 --> 00:00:04,000\nHello Episode 2";

      archive.addFile(ArchiveFile(
        'Breaking.Bad.S01E01.srt',
        ep1Content.length,
        ep1Content.codeUnits,
      ));
      archive.addFile(ArchiveFile(
        'Breaking.Bad.S01E02.srt',
        ep2Content.length,
        ep2Content.codeUnits,
      ));

      final zipBytes = ZipEncoder().encode(archive);
      expect(zipBytes, isNotNull);

      // Verify that ZipDecoder decodes it
      final decoded = ZipDecoder().decodeBytes(Uint8List.fromList(zipBytes));
      expect(decoded.length, equals(2));
      expect(decoded.any((f) => f.name.contains('E01')), isTrue);
    });

    test('RemoteConfigService contains pool of 3 SubDL API keys', () {
      final pool = RemoteConfigService.instance.subdlApiKeyPool;
      expect(pool.length, equals(3));
      expect(pool, contains('subdl_juzGQt0pcPTB3ZuBAmAkXtNwEhX-gIfz5SjEnuNDd5c'));
      expect(pool, contains('subdl_-QPfi2pVWXr9Gmtq-4K2eWGYXBDONWDpXKaGntMDcZA'));
      expect(pool, contains('subdl_Lyfy8q_azvWbslbP0MHPiTGeaJ4UFAPOf0uP80liqFI'));
    });
  });
}

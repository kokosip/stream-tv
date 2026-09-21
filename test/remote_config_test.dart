import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/remote_config_service.dart';
import 'package:MovieBox/services/fourkhdhub_api_service.dart';
import 'package:MovieBox/services/dramachi_api_service.dart';
import 'package:MovieBox/services/moviebox_api_service.dart';
import 'package:MovieBox/services/iptv_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RemoteConfigService Offline Fallbacks', () {
    test('provides correct default URLs when uninitialized (offline / tests)', () {
      final config = RemoteConfigService.instance;
      expect(config.isInitialized, isFalse);

      expect(config.fourKHdHubBaseUrl, equals('https://4khdhub.one/'));
      expect(config.dramachiBaseUrl, equals('https://api.nodeobjects.com/'));
      expect(config.dramachiImageCdn, equals('https://static.nodeobjects.com/thumbnail/'));
      expect(config.movieboxStreamReferer, equals('https://sportslive.wine'));
      expect(config.iptvDefaultIndonesiaUrl, equals('https://iptv-org.github.io/iptv/countries/id.m3u'));
      expect(config.movieboxHostPool, isNotEmpty);
      expect(config.movieboxHostPool.contains('https://api6.aoneroom.com'), isTrue);
    });

    test('FourKHdHubApiService uses RemoteConfigService defaults', () {
      final api = FourKHdHubApiService();
      expect(api.baseUrl, equals(RemoteConfigService.instance.fourKHdHubBaseUrl));
    });

    test('DramachiApiService uses RemoteConfigService defaults', () {
      final api = DramachiApiService();
      expect(api.baseUrl, equals(RemoteConfigService.instance.dramachiBaseUrl));
      expect(DramachiApiService.IMAGE_CDN_BASE, equals(RemoteConfigService.instance.dramachiImageCdn));
    });

    test('MovieBoxApiService uses RemoteConfigService defaults', () {
      expect(MovieBoxApiService.hostPool, equals(RemoteConfigService.instance.movieboxHostPool));
      expect(MovieBoxApiService.streamReferer, equals(RemoteConfigService.instance.movieboxStreamReferer));
    });

    test('IptvService defaultIndonesiaUrl uses RemoteConfigService defaults', () {
      expect(IptvService.defaultIndonesiaUrl, equals(RemoteConfigService.instance.iptvDefaultIndonesiaUrl));
    });

    test('refreshConfigOnFailure handles uninitialized Firebase gracefully', () async {
      final res = await RemoteConfigService.instance.refreshConfigOnFailure(reason: 'unit_test');
      // In unit test without Firebase App, it safely returns false without throwing
      expect(res, isFalse);
    });
  });
}

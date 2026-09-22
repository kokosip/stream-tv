import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/fcm_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FcmService Unit Tests', () {
    test('defines required broadcast topic constants', () {
      expect(FcmService.topicAllUsers, equals('all_users'));
      expect(FcmService.topicNewMovies, equals('new_movies'));
      expect(FcmService.topicPopularSeries, equals('popular_series'));
      expect(FcmService.topicLiveTvEvents, equals('live_tv_events'));
    });

    test('navigatorKey is properly instantiated for global routing', () {
      expect(FcmService.navigatorKey, isNotNull);
    });

    test('isInitialized is safely false in uninitialized test environment', () {
      expect(FcmService.instance.isInitialized, isFalse);
    });
  });
}

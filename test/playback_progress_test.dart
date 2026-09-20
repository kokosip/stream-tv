import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:MovieBox/services/playback_progress_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PlaybackProgressService Episode Progress Tests', () {
    test('Save in-progress episode and verify progress and ratio', () async {
      // 18 minutes into a 45-minute episode (1,080,000 ms / 2,700,000 ms = 40%)
      await PlaybackProgressService.saveProgress(
        'test_series_1',
        1,
        4,
        1080000,
        2700000,
        title: 'Episode 4',
      );

      final progress = await PlaybackProgressService.getEpisodeProgress('test_series_1', 1, 4);
      expect(progress.isFinished, isFalse);
      expect(progress.hasProgress, isTrue);
      expect(progress.positionMs, equals(1080000));
      expect(progress.durationMs, equals(2700000));
      expect(progress.ratio, closeTo(0.4, 0.05));
      expect(progress.positionFormatted, equals('18m'));
    });

    test('Save completed episode and verify 100% progress and isFinished', () async {
      // 44 minutes into a 45-minute episode (>90% -> completed)
      await PlaybackProgressService.saveProgress(
        'test_series_1',
        1,
        3,
        2640000,
        2700000,
        title: 'Episode 3',
      );

      final progress = await PlaybackProgressService.getEpisodeProgress('test_series_1', 1, 3);
      expect(progress.isFinished, isTrue);
      expect(progress.hasProgress, isTrue);
      expect(progress.ratio, equals(1.0));
    });

    test('Batch fetch season progress returns map of episodes with progress', () async {
      // Episode 3: finished
      await PlaybackProgressService.saveProgress(
        'test_series_2',
        1,
        3,
        2650000,
        2700000,
        title: 'Episode 3',
      );

      // Episode 4: 80% watched (2,160,000 / 2,700,000)
      await PlaybackProgressService.saveProgress(
        'test_series_2',
        1,
        4,
        2160000,
        2700000,
        title: 'Episode 4',
      );

      // Episode 5: 60% watched (1,620,000 / 2,700,000)
      await PlaybackProgressService.saveProgress(
        'test_series_2',
        1,
        5,
        1620000,
        2700000,
        title: 'Episode 5',
      );

      final seasonProgress = await PlaybackProgressService.getSeasonProgress(
        'test_series_2',
        1,
        [1, 2, 3, 4, 5, 6],
      );

      expect(seasonProgress.containsKey(1), isFalse);
      expect(seasonProgress.containsKey(2), isFalse);
      expect(seasonProgress.containsKey(6), isFalse);

      expect(seasonProgress.containsKey(3), isTrue);
      expect(seasonProgress[3]!.isFinished, isTrue);
      expect(seasonProgress[3]!.ratio, equals(1.0));

      expect(seasonProgress.containsKey(4), isTrue);
      expect(seasonProgress[4]!.isFinished, isFalse);
      expect(seasonProgress[4]!.ratio, closeTo(0.8, 0.05));
      expect(seasonProgress[4]!.positionFormatted, equals('36m'));

      expect(seasonProgress.containsKey(5), isTrue);
      expect(seasonProgress[5]!.isFinished, isFalse);
      expect(seasonProgress[5]!.ratio, closeTo(0.6, 0.05));
      expect(seasonProgress[5]!.positionFormatted, equals('27m'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:MovieBox/services/performance_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PerformanceService Unit Tests', () {
    test('initializes safely when uninitialized in test environment', () {
      final service = PerformanceService.instance;
      expect(service.isInitialized, isFalse);
    });

    test('startTrace and stopTrace handle uninitialized state gracefully', () async {
      final service = PerformanceService.instance;
      final trace = await service.startTrace('test_trace');
      expect(trace, isNull);

      // Should not throw when stopping null trace
      await expectLater(
        service.stopTrace(trace, attributes: {'test': 'true'}, metrics: {'latency': 100}),
        completes,
      );
    });

    test('traceAction executes action and returns result without crashing', () async {
      final service = PerformanceService.instance;
      final result = await service.traceAction('test_action', () async {
        return 'success_payload';
      }, attributes: {'category': 'test'});

      expect(result, equals('success_payload'));
    });

    test('startAppStartupTrace and stopAppStartupTrace execute safely', () {
      final service = PerformanceService.instance;
      service.startAppStartupTrace();
      service.stopAppStartupTrace();
      // Verifies no exception thrown
    });
  });
}

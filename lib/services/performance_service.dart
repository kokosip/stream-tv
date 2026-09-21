import 'package:flutter/foundation.dart';
import 'package:firebase_performance/firebase_performance.dart';

class PerformanceService {
  PerformanceService._internal();
  static final PerformanceService instance = PerformanceService._internal();

  FirebasePerformance? _performance;
  bool _isInitialized = false;

  Trace? _appStartupTrace;
  final Stopwatch _startupStopwatch = Stopwatch();

  bool get isInitialized => _isInitialized;

  /// Initialize Firebase Performance Monitoring.
  /// Automatically enabled on release builds and safely disabled in debug/test environments.
  static Future<void> init() async {
    try {
      final perf = FirebasePerformance.instance;
      // Enable performance data collection only on release builds
      await perf.setPerformanceCollectionEnabled(kReleaseMode);
      instance._performance = perf;
      instance._isInitialized = true;
      debugPrint('PerformanceService initialized (enabled: $kReleaseMode)');
    } catch (e) {
      debugPrint('PerformanceService init warning (disabled): $e');
      instance._isInitialized = false;
    }
  }

  /// Start a custom performance trace by name (e.g. 'search_query', 'stream_resolution').
  Future<Trace?> startTrace(String name) async {
    if (!_isInitialized || _performance == null) return null;
    try {
      final trace = _performance!.newTrace(name);
      await trace.start();
      return trace;
    } catch (e) {
      debugPrint('PerformanceService: Failed to start trace "$name": $e');
      return null;
    }
  }

  /// Stop a custom trace and optionally attach attributes or numeric metrics.
  Future<void> stopTrace(
    Trace? trace, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    if (trace == null) return;
    try {
      if (attributes != null) {
        attributes.forEach((key, value) {
          try {
            trace.putAttribute(key, value);
          } catch (_) {}
        });
      }
      if (metrics != null) {
        metrics.forEach((key, value) {
          try {
            trace.setMetric(key, value);
          } catch (_) {}
        });
      }
      await trace.stop();
    } catch (e) {
      debugPrint('PerformanceService: Failed to stop trace: $e');
    }
  }

  /// Convenience wrapper to measure an asynchronous action.
  Future<T> traceAction<T>(
    String traceName,
    Future<T> Function() action, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    final trace = await startTrace(traceName);
    try {
      final result = await action();
      await stopTrace(trace, attributes: attributes, metrics: metrics);
      return result;
    } catch (e) {
      final errorAttributes = Map<String, String>.from(attributes ?? {});
      errorAttributes['has_error'] = 'true';
      await stopTrace(trace, attributes: errorAttributes, metrics: metrics);
      rethrow;
    }
  }

  /// Starts measuring app boot time from main()
  void startAppStartupTrace() {
    _startupStopwatch.start();
    startTrace('app_startup_duration').then((trace) {
      _appStartupTrace = trace;
    });
  }

  /// Stops measuring app boot time once HomeScreen catalog has rendered
  void stopAppStartupTrace() {
    if (_startupStopwatch.isRunning) {
      _startupStopwatch.stop();
      final elapsedMs = _startupStopwatch.elapsedMilliseconds;
      debugPrint('App startup completed in ${elapsedMs}ms');

      if (_appStartupTrace != null) {
        stopTrace(
          _appStartupTrace,
          metrics: {'elapsed_ms': elapsedMs},
        );
        _appStartupTrace = null;
      }
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteConfigService {
  RemoteConfigService._internal();
  static final RemoteConfigService instance = RemoteConfigService._internal();

  // Remote Config Cloud Keys
  static const String keyFourKHdHubBaseUrl = 'fourkhdhub_base_url';
  static const String keyDramachiBaseUrl = 'dramachi_base_url';
  static const String keyDramachiImageCdn = 'dramachi_image_cdn';
  static const String keyMovieBoxHostPool = 'moviebox_host_pool';
  static const String keyMovieBoxStreamReferer = 'moviebox_stream_referer';
  static const String keyIptvDefaultUrl = 'iptv_default_url';

  // SharedPreferences Local Storage Keys
  static const String _prefFourKHdHub = 'rc_local_fourkhdhub_base_url';
  static const String _prefDramachiBase = 'rc_local_dramachi_base_url';
  static const String _prefDramachiCdn = 'rc_local_dramachi_image_cdn';
  static const String _prefMovieBoxPool = 'rc_local_moviebox_host_pool';
  static const String _prefMovieBoxReferer = 'rc_local_moviebox_stream_referer';
  static const String _prefIptvUrl = 'rc_local_iptv_default_url';

  // Hardcoded default fallbacks
  static const String defaultFourKHdHubBaseUrl = 'https://4khdhub.one/';
  static const String defaultDramachiBaseUrl = 'https://api.nodeobjects.com/';
  static const String defaultDramachiImageCdn = 'https://static.nodeobjects.com/thumbnail/';
  static const List<String> defaultMovieBoxHostPool = [
    'https://api6.aoneroom.com',
    'https://api5.aoneroom.com',
    'https://api4.aoneroom.com',
    'https://api4sg.aoneroom.com',
    'https://api3.aoneroom.com',
    'https://api6sg.aoneroom.com',
    'https://api.inmoviebox.com',
  ];
  static const String defaultMovieBoxStreamReferer = 'https://sportslive.wine';
  static const String defaultIptvUrl = 'https://iptv-org.github.io/iptv/countries/id.m3u';

  FirebaseRemoteConfig? _remoteConfig;
  bool _isInitialized = false;

  // In-memory active configurations loaded from SharedPreferences or defaults
  String? _activeFourKHdHubBaseUrl;
  String? _activeDramachiBaseUrl;
  String? _activeDramachiImageCdn;
  List<String>? _activeMovieBoxHostPool;
  String? _activeMovieBoxStreamReferer;
  String? _activeIptvDefaultUrl;

  DateTime? _lastFetchAttempt;
  Future<bool>? _activeRefreshFuture;

  bool get isInitialized => _isInitialized;

  /// Map of default values for Firebase Remote Config
  static Map<String, dynamic> get _defaults => {
        keyFourKHdHubBaseUrl: defaultFourKHdHubBaseUrl,
        keyDramachiBaseUrl: defaultDramachiBaseUrl,
        keyDramachiImageCdn: defaultDramachiImageCdn,
        keyMovieBoxHostPool: jsonEncode(defaultMovieBoxHostPool),
        keyMovieBoxStreamReferer: defaultMovieBoxStreamReferer,
        keyIptvDefaultUrl: defaultIptvUrl,
      };

  /// Initialize local configurations from SharedPreferences and prepare Remote Config instance.
  /// Does NOT trigger network fetch at startup (0 Firebase quota used).
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      instance._loadFromPrefs(prefs);

      // Setup Firebase Remote Config without fetching
      final rc = FirebaseRemoteConfig.instance;
      await rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(hours: 1),
      ));
      await rc.setDefaults(_defaults);

      instance._remoteConfig = rc;
      instance._isInitialized = true;
      debugPrint('RemoteConfigService initialized locally (0 network fetch).');
    } catch (e) {
      debugPrint('RemoteConfigService init warning (using defaults): $e');
      instance._isInitialized = false;
    }
  }

  void _loadFromPrefs(SharedPreferences prefs) {
    _activeFourKHdHubBaseUrl = prefs.getString(_prefFourKHdHub);
    _activeDramachiBaseUrl = prefs.getString(_prefDramachiBase);
    _activeDramachiImageCdn = prefs.getString(_prefDramachiCdn);

    final rawPool = prefs.getString(_prefMovieBoxPool);
    if (rawPool != null && rawPool.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPool);
        if (decoded is List) {
          final list = decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
          if (list.isNotEmpty) _activeMovieBoxHostPool = list;
        }
      } catch (_) {}
    }

    _activeMovieBoxStreamReferer = prefs.getString(_prefMovieBoxReferer);
    _activeIptvDefaultUrl = prefs.getString(_prefIptvUrl);
  }

  /// On-Demand Fetch: Called only when a provider request fails.
  /// Fetches fresh URLs from Firebase Remote Config, saves them into SharedPreferences,
  /// and updates the active URLs in memory.
  ///
  /// Protected with a 15-minute cooldown and request deduplication.
  Future<bool> refreshConfigOnFailure({String? reason, bool force = false}) async {
    if (_activeRefreshFuture != null) {
      return _activeRefreshFuture!;
    }
    _activeRefreshFuture = _performRefresh(reason: reason, force: force);
    try {
      return await _activeRefreshFuture!;
    } finally {
      _activeRefreshFuture = null;
    }
  }

  Future<bool> _performRefresh({String? reason, bool force = false}) async {
    final now = DateTime.now();
    // 15 minutes cooldown to avoid spamming if device is offline
    if (!force && _lastFetchAttempt != null && now.difference(_lastFetchAttempt!) < const Duration(minutes: 15)) {
      debugPrint('RemoteConfigService: Refresh skipped (cooldown active, reason: $reason)');
      return false;
    }
    _lastFetchAttempt = now;

    if (_remoteConfig == null) {
      try {
        _remoteConfig = FirebaseRemoteConfig.instance;
      } catch (e) {
        debugPrint('RemoteConfigService: Cannot access Firebase instance: $e');
        return false;
      }
    }

    try {
      debugPrint('RemoteConfigService: Fetching config from cloud due to error (reason: $reason)...');
      await _remoteConfig!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero,
      ));

      final updated = await _remoteConfig!.fetchAndActivate();
      debugPrint('RemoteConfigService: Cloud fetch completed (updated: $updated)');

      final prefs = await SharedPreferences.getInstance();
      await _persistAndApplyValues(prefs);
      return true;
    } catch (e) {
      debugPrint('RemoteConfigService: Failed to fetch cloud config: $e');
      return false;
    }
  }

  Future<void> _persistAndApplyValues(SharedPreferences prefs) async {
    if (_remoteConfig == null) return;

    // 4KHDHub
    final new4k = _remoteConfig!.getString(keyFourKHdHubBaseUrl).trim();
    if (new4k.isNotEmpty && new4k != defaultFourKHdHubBaseUrl) {
      final formatted = new4k.endsWith('/') ? new4k : '$new4k/';
      _activeFourKHdHubBaseUrl = formatted;
      await prefs.setString(_prefFourKHdHub, formatted);
    }

    // Dramachi API
    final newDramachi = _remoteConfig!.getString(keyDramachiBaseUrl).trim();
    if (newDramachi.isNotEmpty && newDramachi != defaultDramachiBaseUrl) {
      final formatted = newDramachi.endsWith('/') ? newDramachi : '$newDramachi/';
      _activeDramachiBaseUrl = formatted;
      await prefs.setString(_prefDramachiBase, formatted);
    }

    // Dramachi CDN
    final newDramachiCdn = _remoteConfig!.getString(keyDramachiImageCdn).trim();
    if (newDramachiCdn.isNotEmpty && newDramachiCdn != defaultDramachiImageCdn) {
      final formatted = newDramachiCdn.endsWith('/') ? newDramachiCdn : '$newDramachiCdn/';
      _activeDramachiImageCdn = formatted;
      await prefs.setString(_prefDramachiCdn, formatted);
    }

    // MovieBox Host Pool
    final rawPool = _remoteConfig!.getString(keyMovieBoxHostPool).trim();
    if (rawPool.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawPool);
        if (decoded is List) {
          final list = decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
          if (list.isNotEmpty) {
            _activeMovieBoxHostPool = list;
            await prefs.setString(_prefMovieBoxPool, rawPool);
          }
        }
      } catch (_) {}
    }

    // MovieBox Stream Referer
    final newReferer = _remoteConfig!.getString(keyMovieBoxStreamReferer).trim();
    if (newReferer.isNotEmpty && newReferer != defaultMovieBoxStreamReferer) {
      _activeMovieBoxStreamReferer = newReferer;
      await prefs.setString(_prefMovieBoxReferer, newReferer);
    }

    // IPTV Default URL
    final newIptv = _remoteConfig!.getString(keyIptvDefaultUrl).trim();
    if (newIptv.isNotEmpty && newIptv != defaultIptvUrl) {
      _activeIptvDefaultUrl = newIptv;
      await prefs.setString(_prefIptvUrl, newIptv);
    }

    debugPrint('RemoteConfigService: Saved updated provider URLs to local storage.');
  }

  /// 4KHDHub base URL (reads from local storage cache, then fallback default)
  String get fourKHdHubBaseUrl {
    return _activeFourKHdHubBaseUrl ?? defaultFourKHdHubBaseUrl;
  }

  /// Dramachi API base URL
  String get dramachiBaseUrl {
    return _activeDramachiBaseUrl ?? defaultDramachiBaseUrl;
  }

  /// Dramachi Image CDN base URL
  String get dramachiImageCdn {
    return _activeDramachiImageCdn ?? defaultDramachiImageCdn;
  }

  /// MovieBox API host pool
  List<String> get movieboxHostPool {
    return _activeMovieBoxHostPool ?? defaultMovieBoxHostPool;
  }

  /// MovieBox stream referer header URL
  String get movieboxStreamReferer {
    return _activeMovieBoxStreamReferer ?? defaultMovieBoxStreamReferer;
  }

  /// Default Indonesia IPTV playlist URL
  String get iptvDefaultIndonesiaUrl {
    return _activeIptvDefaultUrl ?? defaultIptvUrl;
  }
}

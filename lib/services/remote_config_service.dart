import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RemoteConfigService {
  RemoteConfigService._internal();
  static final RemoteConfigService instance = RemoteConfigService._internal();

  // Remote Config Cloud Keys
  static const String keyFourKHdHubBaseUrl = 'fourkhdhub_base_url';
  static const String keyPusatfilmBaseUrl = 'pusatfilm_base_url';
  static const String keyJuraganfilmBaseUrl = 'juraganfilm_base_url';
  static const String keySamehadakuBaseUrl = 'samehadaku_base_url';
  static const String keyOtakudesuBaseUrl = 'otakudesu_base_url';
  static const String keyAnichinBaseUrl = 'anichin_base_url';
  static const String keyDracinsiBaseUrl = 'dracinsi_base_url';
  static const String keyDrakorkitaBaseUrl = 'drakorkita_base_url';
  static const String keyDramachiBaseUrl = 'dramachi_base_url';
  static const String keyDramachiImageCdn = 'dramachi_image_cdn';
  static const String keyMovieBoxHostPool = 'moviebox_host_pool';
  static const String keyMovieBoxStreamReferer = 'moviebox_stream_referer';
  static const String keyIptvDefaultUrl = 'iptv_default_url';
  static const String keySubdlApiKey = 'subdl_api_key';

  // SharedPreferences Local Storage Keys
  static const String _prefFourKHdHub = 'rc_local_fourkhdhub_base_url';
  static const String _prefPusatfilm = 'rc_local_pusatfilm_base_url';
  static const String _prefJuraganfilm = 'rc_local_juraganfilm_base_url';
  static const String _prefSamehadaku = 'rc_local_samehadaku_base_url';
  static const String _prefOtakudesu = 'rc_local_otakudesu_base_url';
  static const String _prefAnichin = 'rc_local_anichin_base_url';
  static const String _prefDracinsi = 'rc_local_dracinsi_base_url';
  static const String _prefDrakorkita = 'rc_local_drakorkita_base_url';
  static const String _prefDramachiBase = 'rc_local_dramachi_base_url';
  static const String _prefDramachiCdn = 'rc_local_dramachi_image_cdn';
  static const String _prefMovieBoxPool = 'rc_local_moviebox_host_pool';
  static const String _prefMovieBoxReferer = 'rc_local_moviebox_stream_referer';
  static const String _prefIptvUrl = 'rc_local_iptv_default_url';
  static const String _prefSubdlApiKey = 'rc_local_subdl_api_key';

  // Hardcoded default fallbacks
  static const String defaultFourKHdHubBaseUrl = 'https://4khdhub.one/';
  static const String defaultPusatfilmBaseUrl = 'https://v5.pusatfilm21info.com/';
  static const String defaultJuraganfilmBaseUrl = 'https://tv50.juragan.film/';
  static const String defaultSamehadakuBaseUrl = 'https://v2.samehadaku.how/';
  static const String defaultOtakudesuBaseUrl = 'https://otakudesu.blog/';
  static const String defaultAnichinBaseUrl = 'https://anichin.moe/';
  static const String defaultDracinsiBaseUrl = 'https://dramacinasubindo.com/';
  static const String defaultDrakorkitaBaseUrl = 'https://drakorkita.lat/';
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
  static const List<String> defaultSubdlApiKeyPool = [
    'subdl_juzGQt0pcPTB3ZuBAmAkXtNwEhX-gIfz5SjEnuNDd5c',
    'subdl_-QPfi2pVWXr9Gmtq-4K2eWGYXBDONWDpXKaGntMDcZA',
    'subdl_Lyfy8q_azvWbslbP0MHPiTGeaJ4UFAPOf0uP80liqFI',
  ];
  static const String defaultSubdlApiKey = 'subdl_juzGQt0pcPTB3ZuBAmAkXtNwEhX-gIfz5SjEnuNDd5c';

  FirebaseRemoteConfig? _remoteConfig;
  bool _isInitialized = false;

  // In-memory active configurations loaded from SharedPreferences or defaults
  String? _activeFourKHdHubBaseUrl;
  String? _activePusatfilmBaseUrl;
  String? _activeJuraganfilmBaseUrl;
  String? _activeSamehadakuBaseUrl;
  String? _activeOtakudesuBaseUrl;
  String? _activeAnichinBaseUrl;
  String? _activeDracinsiBaseUrl;
  String? _activeDrakorkitaBaseUrl;
  String? _activeDramachiBaseUrl;
  String? _activeDramachiImageCdn;
  List<String>? _activeMovieBoxHostPool;
  String? _activeMovieBoxStreamReferer;
  String? _activeIptvDefaultUrl;
  String? _activeSubdlApiKey;

  DateTime? _lastFetchAttempt;
  Future<bool>? _activeRefreshFuture;

  bool get isInitialized => _isInitialized;

  /// Map of default values for Firebase Remote Config
  static Map<String, dynamic> get _defaults => {
        keyFourKHdHubBaseUrl: defaultFourKHdHubBaseUrl,
        keyPusatfilmBaseUrl: defaultPusatfilmBaseUrl,
        keyJuraganfilmBaseUrl: defaultJuraganfilmBaseUrl,
        keySamehadakuBaseUrl: defaultSamehadakuBaseUrl,
        keyOtakudesuBaseUrl: defaultOtakudesuBaseUrl,
        keyAnichinBaseUrl: defaultAnichinBaseUrl,
        keyDracinsiBaseUrl: defaultDracinsiBaseUrl,
        keyDrakorkitaBaseUrl: defaultDrakorkitaBaseUrl,
        keyDramachiBaseUrl: defaultDramachiBaseUrl,
        keyDramachiImageCdn: defaultDramachiImageCdn,
        keyMovieBoxHostPool: jsonEncode(defaultMovieBoxHostPool),
        keyMovieBoxStreamReferer: defaultMovieBoxStreamReferer,
        keyIptvDefaultUrl: defaultIptvUrl,
        keySubdlApiKey: defaultSubdlApiKeyPool.join(','),
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
    _activePusatfilmBaseUrl = prefs.getString(_prefPusatfilm);
    _activeJuraganfilmBaseUrl = prefs.getString(_prefJuraganfilm);
    _activeSamehadakuBaseUrl = prefs.getString(_prefSamehadaku);
    _activeOtakudesuBaseUrl = prefs.getString(_prefOtakudesu);
    _activeAnichinBaseUrl = prefs.getString(_prefAnichin);
    _activeDracinsiBaseUrl = prefs.getString(_prefDracinsi);
    _activeDrakorkitaBaseUrl = prefs.getString(_prefDrakorkita);
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
    _activeSubdlApiKey = prefs.getString(_prefSubdlApiKey);
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

    // PusatFilm
    final newPf = _remoteConfig!.getString(keyPusatfilmBaseUrl).trim();
    if (newPf.isNotEmpty && newPf != defaultPusatfilmBaseUrl) {
      final formatted = newPf.endsWith('/') ? newPf : '$newPf/';
      _activePusatfilmBaseUrl = formatted;
      await prefs.setString(_prefPusatfilm, formatted);
    }

    // JuraganFilm
    final newJf = _remoteConfig!.getString(keyJuraganfilmBaseUrl).trim();
    if (newJf.isNotEmpty && newJf != defaultJuraganfilmBaseUrl) {
      final formatted = newJf.endsWith('/') ? newJf : '$newJf/';
      _activeJuraganfilmBaseUrl = formatted;
      await prefs.setString(_prefJuraganfilm, formatted);
    }

    // Samehadaku
    final newSm = _remoteConfig!.getString(keySamehadakuBaseUrl).trim();
    if (newSm.isNotEmpty && newSm != defaultSamehadakuBaseUrl) {
      final formatted = newSm.endsWith('/') ? newSm : '$newSm/';
      _activeSamehadakuBaseUrl = formatted;
      await prefs.setString(_prefSamehadaku, formatted);
    }

    // Otakudesu
    final newOt = _remoteConfig!.getString(keyOtakudesuBaseUrl).trim();
    if (newOt.isNotEmpty && newOt != defaultOtakudesuBaseUrl) {
      final formatted = newOt.endsWith('/') ? newOt : '$newOt/';
      _activeOtakudesuBaseUrl = formatted;
      await prefs.setString(_prefOtakudesu, formatted);
    }

    // Anichin
    final newAn = _remoteConfig!.getString(keyAnichinBaseUrl).trim();
    if (newAn.isNotEmpty && newAn != defaultAnichinBaseUrl) {
      final formatted = newAn.endsWith('/') ? newAn : '$newAn/';
      _activeAnichinBaseUrl = formatted;
      await prefs.setString(_prefAnichin, formatted);
    }

    // DracinSI
    final newDs = _remoteConfig!.getString(keyDracinsiBaseUrl).trim();
    if (newDs.isNotEmpty && newDs != defaultDracinsiBaseUrl) {
      final formatted = newDs.endsWith('/') ? newDs : '$newDs/';
      _activeDracinsiBaseUrl = formatted;
      await prefs.setString(_prefDracinsi, formatted);
    }

    // DrakorKita
    final newDk = _remoteConfig!.getString(keyDrakorkitaBaseUrl).trim();
    if (newDk.isNotEmpty && newDk != defaultDrakorkitaBaseUrl) {
      final formatted = newDk.endsWith('/') ? newDk : '$newDk/';
      _activeDrakorkitaBaseUrl = formatted;
      await prefs.setString(_prefDrakorkita, formatted);
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

    // SubDL API Key
    final newSubdlKey = _remoteConfig!.getString(keySubdlApiKey).trim();
    if (newSubdlKey.isNotEmpty) {
      _activeSubdlApiKey = newSubdlKey;
      await prefs.setString(_prefSubdlApiKey, newSubdlKey);
    }

    debugPrint('RemoteConfigService: Saved updated provider URLs to local storage.');
  }

  /// 4KHDHub base URL (reads from local storage cache, then fallback default)
  String get fourKHdHubBaseUrl {
    return _activeFourKHdHubBaseUrl ?? defaultFourKHdHubBaseUrl;
  }

  /// PusatFilm base URL (reads from local storage cache, then fallback default)
  String get pusatfilmBaseUrl {
    return _activePusatfilmBaseUrl ?? defaultPusatfilmBaseUrl;
  }

  /// JuraganFilm base URL
  String get juraganfilmBaseUrl {
    return _activeJuraganfilmBaseUrl ?? defaultJuraganfilmBaseUrl;
  }

  /// Samehadaku base URL
  String get samehadakuBaseUrl {
    return _activeSamehadakuBaseUrl ?? defaultSamehadakuBaseUrl;
  }

  /// Otakudesu base URL
  String get otakudesuBaseUrl {
    return _activeOtakudesuBaseUrl ?? defaultOtakudesuBaseUrl;
  }

  /// Anichin base URL
  String get anichinBaseUrl {
    return _activeAnichinBaseUrl ?? defaultAnichinBaseUrl;
  }

  /// DracinSI base URL
  String get dracinsiBaseUrl {
    return _activeDracinsiBaseUrl ?? defaultDracinsiBaseUrl;
  }

  /// DrakorKita base URL
  String get drakorkitaBaseUrl {
    return _activeDrakorkitaBaseUrl ?? defaultDrakorkitaBaseUrl;
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

  /// SubDL API Key Pool (supports comma-separated list, JSON array, or default pool)
  List<String> get subdlApiKeyPool {
    final raw = _activeSubdlApiKey;
    if (raw != null && raw.trim().isNotEmpty) {
      if (raw.startsWith('[') && raw.endsWith(']')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            final list = decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
            if (list.isNotEmpty) return list;
          }
        } catch (_) {}
      }
      final split = raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      if (split.isNotEmpty) return split;
    }
    return defaultSubdlApiKeyPool;
  }

  /// Active or first SubDL API Key
  String get subdlApiKey {
    final pool = subdlApiKeyPool;
    return pool.isNotEmpty ? pool.first : defaultSubdlApiKey;
  }
}

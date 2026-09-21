import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'remote_config_service.dart';

class RateLimitException implements Exception {
  final String message;
  final Duration? retryAfter;
  RateLimitException(this.message, {this.retryAfter});
  @override
  String toString() => message;
}

class NetworkConnectionException implements Exception {
  final String message;
  NetworkConnectionException(this.message);
  @override
  String toString() => message;
}

class NoStreamAvailableException implements Exception {
  final String message;
  NoStreamAvailableException(this.message);
  @override
  String toString() => message;
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, {required this.statusCode});
  @override
  String toString() => message;
}

class MovieBoxApiService {
  static final Random _rng = Random();

  static List<String> get hostPool => RemoteConfigService.instance.movieboxHostPool;
  static String get streamReferer => RemoteConfigService.instance.movieboxStreamReferer;

  static const List<String> DEFAULT_HOST_POOL = RemoteConfigService.defaultMovieBoxHostPool;
  static const List<String> HOST_POOL = DEFAULT_HOST_POOL;

  static const String DEFAULT_STREAM_REFERER = RemoteConfigService.defaultMovieBoxStreamReferer;
  static const String STREAM_REFERER = DEFAULT_STREAM_REFERER;

  static const String SECRET_KEY_DEFAULT = "76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O";
  static const String SECRET_KEY_ALT = "Xqn2nnO41/L92o1iuXhSLHTbXvY4Z5ZZ62m8mSLA";

  static const String _sessionTokenKey = 'moviebox_session_token';
  static const String _sessionExpKey = 'moviebox_session_exp';
  static const String _sessionUidKey = 'moviebox_session_uid';
  static const String _sessionCreatedKey = 'moviebox_session_created';

  // Global in-memory token shared across instances
  static String? _globalRuntimeToken;

  // Active base host which we rotate on failure
  String _activeBase = RemoteConfigService.instance.movieboxHostPool.first;

  String? get _runtimeToken => _globalRuntimeToken;
  set _runtimeToken(String? val) => _globalRuntimeToken = val;
  Future<void>? _tokenFetchFuture;

  late final String _userAgent;
  late final String _clientInfo;
  late final String _spoofedIp;

  String get userAgent => _userAgent;
  String get clientInfo => _clientInfo;
  String get spoofedIp => _spoofedIp;

  MovieBoxApiService() {
    _initDeviceIdentity();
  }

  void _initDeviceIdentity() {
    const androidVersions = [
      ["9", "PQ3A.190605.03081104"],
      ["10", "QP1A.191005.007.A3"],
      ["11", "RP1A.200720.011"],
      ["12", "S1B.220414.015"],
      ["13", "TQ2A.230405.003"],
    ];
    const redmiDevices = [
      ["23078RKD5C", "Redmi"],
      ["2201117TY", "Redmi"],
      ["2201117TG", "Redmi"],
      ["22101316G", "Redmi"],
      ["21121210G", "Redmi"],
      ["M2012K11AG", "Redmi"],
      ["M2007J20CG", "Redmi"],
    ];
    const versionCodes = [50020117, 50020118, 50020119, 50020120, 50020121];
    const networkTypes = ["NETWORK_WIFI", "NETWORK_MOBILE"];
    const timezones = [
      "Asia/Kolkata",
      "Asia/Shanghai",
      "Asia/Tokyo",
      "America/New_York",
      "Europe/London",
    ];

    final android = androidVersions[_rng.nextInt(androidVersions.length)];
    final device = redmiDevices[_rng.nextInt(redmiDevices.length)];
    final versionCode = versionCodes[_rng.nextInt(versionCodes.length)];
    final network = networkTypes[_rng.nextInt(networkTypes.length)];
    final timezone = timezones[_rng.nextInt(timezones.length)];
    final gaid = _randomUuid();
    final deviceId = _randomHex(32);

    _userAgent =
        "com.community.oneroom/$versionCode (Linux; U; Android ${android[0]}; en_US; ${device[0]}; Build/${android[1]}; Cronet/135.0.7012.3)";

    _clientInfo =
        '{"package_name":"com.community.oneroom","version_name":"4.0.01.0813.03","version_code":$versionCode,"os":"android","os_version":"${android[0]}","install_ch":"ps","device_id":"$deviceId","install_store":"ps","gaid":"$gaid","brand":"${device[1]}","model":"${device[0]}","system_language":"en","net":"$network","region":"US","timezone":"$timezone","sp_code":"40401","X-Play-Mode":"2"}';

    const ipPrefixes = [
      "103.241", "49.36", "117.195", "106.198", "122.162", "157.32", "182.70", "103.58", "27.60", "59.90"
    ];
    final prefix = ipPrefixes[_rng.nextInt(ipPrefixes.length)];
    final c = 1 + _rng.nextInt(253);
    final d = 1 + _rng.nextInt(253);
    _spoofedIp = "$prefix.$c.$d";
  }

  static String _randomHex(int len) {
    const chars = '0123456789abcdef';
    final sb = StringBuffer();
    for (int i = 0; i < len; i++) {
      sb.write(chars[_rng.nextInt(16)]);
    }
    return sb.toString();
  }

  static String _randomUuid() {
    return "${_randomHex(8)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(4)}-${_randomHex(12)}";
  }

  void _absorbXUser(Map<String, String> headers) {
    String xUser = "";
    headers.forEach((key, value) {
      if (key.toLowerCase() == 'x-user') {
        xUser = value;
      }
    });
    if (xUser.isEmpty) return;
    try {
      final payload = jsonDecode(xUser);
      final token = payload['token']?.toString() ?? "";
      if (token.isNotEmpty) {
        _runtimeToken = token;
        savePersistedSession(token, uid: payload['uid']?.toString() ?? payload['userId']?.toString());
        print("ABSORBED DART RUNTIME TOKEN: $_runtimeToken");
      }
    } catch (_) {}
  }

  /// Parse JWT claims (userId/uid, exp)
  static Map<String, dynamic> parseJwtClaims(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return {};
      var payload = parts[1].trim();
      final pad = (4 - (payload.length % 4)) % 4;
      if (pad > 0) {
        payload += '=' * pad;
      }
      payload = payload.replaceAll('-', '+').replaceAll('_', '/');
      final decodedBytes = base64.decode(payload);
      final jsonStr = utf8.decode(decodedBytes);
      final map = jsonDecode(jsonStr);
      if (map is Map<String, dynamic>) {
        return map;
      }
    } catch (_) {}
    return {};
  }

  /// Check if a cached token is still valid (at least 60 seconds buffer before expiration)
  static bool isSessionValid({required String token, int? expiresAt, int? createdAt}) {
    if (token.trim().isEmpty) return false;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (expiresAt != null && expiresAt > 0) {
      return (nowSec + 60) < expiresAt;
    }
    if (createdAt != null && createdAt > 0) {
      return nowSec < (createdAt + (7 * 24 * 3600));
    }
    return false;
  }

  /// Save token session to SharedPreferences
  static Future<void> savePersistedSession(String token, {String? uid}) async {
    try {
      final claims = parseJwtClaims(token);
      final exp = int.tryParse(claims['exp']?.toString() ?? '');
      final userId = uid ?? claims['userId']?.toString() ?? claims['uid']?.toString();
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionTokenKey, token);
      if (exp != null) await prefs.setInt(_sessionExpKey, exp);
      if (userId != null) await prefs.setString(_sessionUidKey, userId);
      await prefs.setInt(_sessionCreatedKey, nowSec);
    } catch (_) {}
  }

  /// Load persisted session token if still valid
  static Future<String?> loadPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_sessionTokenKey);
      if (token == null || token.isEmpty) return null;
      final exp = prefs.getInt(_sessionExpKey);
      final created = prefs.getInt(_sessionCreatedKey);

      if (isSessionValid(token: token, expiresAt: exp, createdAt: created)) {
        return token;
      }
    } catch (_) {}
    return null;
  }

  /// Invalidate / clear persisted session
  static Future<void> clearPersistedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionTokenKey);
      await prefs.remove(_sessionExpKey);
      await prefs.remove(_sessionUidKey);
      await prefs.remove(_sessionCreatedKey);
    } catch (_) {}
  }

  /// MD5 Helper
  static String _md5Hex(String data) {
    return md5.convert(utf8.encode(data)).toString().toLowerCase();
  }

  /// Generate X-Client-Token: ts,md5(reverse(ts))
  static String _generateXClientToken(int timestampMs) {
    final tsStr = timestampMs.toString();
    final reversedTs = tsStr.split('').reversed.join('');
    final hash = _md5Hex(reversedTs);
    return "$tsStr,$hash";
  }

  /// Helper to sort query parameters key-alphabetically without encoding values
  static String _sortedQueryString(String url) {
    final uri = Uri.parse(url);
    if (uri.queryParameters.isEmpty) return "";
    
    // Sort keys
    final sortedKeys = uri.queryParametersAll.keys.toList()..sort();
    final List<String> parts = [];
    for (final key in sortedKeys) {
      for (final value in uri.queryParametersAll[key]!) {
        parts.add("$key=$value");
      }
    }
    return parts.join("&");
  }

  /// Build canonical signature string
  static String _buildCanonicalString({
    required String method,
    required String? accept,
    required String? contentType,
    required String url,
    required String? body,
    required int timestampMs,
  }) {
    final uri = Uri.parse(url);
    final path = uri.path;
    final query = _sortedQueryString(url);
    final canonicalUrl = query.isNotEmpty ? "$path?$query" : path;

    String bodyHash = "";
    String bodyLength = "";

    if (body != null) {
      final bodyBytes = utf8.encode(body);
      final truncated = bodyBytes.sublist(
        0,
        bodyBytes.length > 102400 ? 102400 : bodyBytes.length,
      );
      bodyHash = md5.convert(truncated).toString().toLowerCase();
      bodyLength = bodyBytes.length.toString();
    }

    return "${method.toUpperCase()}\n"
        "${accept ?? ''}\n"
        "${contentType ?? ''}\n"
        "$bodyLength\n"
        "$timestampMs\n"
        "$bodyHash\n"
        "$canonicalUrl";
  }

  /// Generate x-tr-signature: ts|2|b64(hmac-md5(canonical, secret))
  static String _generateXTrSignature({
    required String method,
    required String? accept,
    required String? contentType,
    required String url,
    required String? body,
    required int timestampMs,
    bool useAltKey = false,
  }) {
    final canonical = _buildCanonicalString(
      method: method,
      accept: accept,
      contentType: contentType,
      url: url,
      body: body,
      timestampMs: timestampMs,
    );
    
    print("DART CANONICAL:\n$canonical\n--------------");

    final secretB64 = useAltKey ? SECRET_KEY_ALT : SECRET_KEY_DEFAULT;
    final secretBytes = base64.decode(secretB64);
    
    final hmac = Hmac(md5, secretBytes);
    final digest = hmac.convert(utf8.encode(canonical));
    final sigB64 = base64.encode(digest.bytes);

    return "$timestampMs|2|$sigB64";
  }

  /// Assemble final request headers
  Map<String, String> _buildSignedHeaders({
    required String method,
    required String url,
    String accept = "application/json",
    String contentType = "application/json",
    String? body,
    String? authToken,
  }) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final clientToken = _generateXClientToken(ts);
    final signature = _generateXTrSignature(
      method: method,
      accept: accept,
      contentType: contentType,
      url: url,
      body: body,
      timestampMs: ts,
    );

    final Map<String, String> headers = {
      "User-Agent": _userAgent,
      "Accept": accept,
      "Content-Type": contentType,
      "Connection": "keep-alive",
      "X-Client-Token": clientToken,
      "x-tr-signature": signature,
      "X-Client-Info": _clientInfo,
      "x-client-info": _clientInfo,
      "X-Client-Status": "0",
      "x-client-status": "0",
      "x-forwarded-for": _spoofedIp,
      "X-Forwarded-For": _spoofedIp,
      "Accept-Language": "en-US,en;q=0.9,id;q=0.8,*;q=0.5",
      "X-Language": "en",
      "x-language": "en",
      "X-Locale": "en-US",
      "x-locale": "en-US",
      "X-Region": "US",
      "X-Country": "US",
    };

    if (authToken != null) {
      headers["Authorization"] = "Bearer $authToken";
    }

    return headers;
  }

  Future<void> _ensureToken() async {
    if (_runtimeToken != null) return;
    if (_tokenFetchFuture != null) {
      return _tokenFetchFuture;
    }
    
    _tokenFetchFuture = () async {
      // 1. Check persisted session in SharedPreferences
      final cachedToken = await loadPersistedSession();
      if (cachedToken != null) {
        _runtimeToken = cachedToken;
        print("Reusing valid persisted MovieBox token session");
        return;
      }

      print("No valid persisted token found. Fetching token via visitor-login...");

      // 2. Try visitor-login first (official guest session endpoint)
      try {
        final res = await _request(
          "POST",
          "/wefeed-mobile-bff/user-api/visitor-login",
          body: {},
        );
        final data = res['data'] is Map ? res['data'] : res;
        final token = data['token']?.toString();
        if (token != null && token.isNotEmpty) {
          _runtimeToken = token;
          await savePersistedSession(token, uid: data['uid']?.toString() ?? data['userId']?.toString());
          print("Obtained runtime token via visitor-login: $_runtimeToken");
          return;
        }
      } catch (e) {
        print("visitor-login error: $e, falling back to getHomepage");
      }

      // 3. Fallback: getHomepage to absorb from x-user
      try {
        await getHomepage(page: 1, tabId: 0);
        print("Token fetched successfully via getHomepage: $_runtimeToken");
      } catch (e) {
        print("Failed to fetch token: $e");
      }
    }().whenComplete(() {
      _tokenFetchFuture = null;
    });
    return _tokenFetchFuture;
  }

  /// Generic request handler with pool fallback
  Future<Map<String, dynamic>> _request(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
    bool isRetryAfterRefresh = false,
  }) async {
    final isAuthExempt = pathAndQuery.contains("tab-operating") || pathAndQuery.contains("visitor-login");
    if (_runtimeToken == null && !isAuthExempt) {
      await _ensureToken();
    }

    Object? lastError;
    
    // Order hosts starting with the active base
    final pool = hostPool;
    final orderedHosts = [
      _activeBase,
      ...pool.where((element) => element != _activeBase)
    ];
 
    for (final base in orderedHosts) {
      final url = "$base$pathAndQuery";
      final bodyStr = body != null ? jsonEncode(body) : null;
      final contentType = method == "POST" ? "application/json; charset=utf-8" : "application/json";
      final headers = _buildSignedHeaders(
        method: method,
        url: url,
        contentType: contentType,
        body: bodyStr,
        authToken: _runtimeToken,
      );

      try {
        final http.Response response;
        if (method == "GET") {
          response = await http.get(Uri.parse(url), headers: headers)
              .timeout(const Duration(seconds: 8));
        } else {
          response = await http.post(
            Uri.parse(url),
            headers: headers,
            body: bodyStr,
          ).timeout(const Duration(seconds: 8));
        }

        // Always try to absorb token if present in response headers
        _absorbXUser(response.headers);

        if (response.statusCode == 200) {
          final resData = jsonDecode(response.body);
          _activeBase = base; // Lock in successful base
          
          if (resData is Map && resData.containsKey("data")) {
            return Map<String, dynamic>.from(resData["data"]);
          }
          return Map<String, dynamic>.from(resData);
        } else if (response.statusCode == 429) {
          int retryAfterSec = 2;
          final retryHeader = response.headers['retry-after'];
          if (retryHeader != null) {
            retryAfterSec = int.tryParse(retryHeader) ?? 2;
          }
          print("Rate limited (429) on $url. Waiting ${retryAfterSec}s before retrying...");
          await Future.delayed(Duration(seconds: retryAfterSec));
          
          final retryHeaders = _buildSignedHeaders(
            method: method,
            url: url,
            contentType: contentType,
            body: bodyStr,
            authToken: _runtimeToken,
          );
          final http.Response retryResponse;
          if (method == "GET") {
            retryResponse = await http.get(Uri.parse(url), headers: retryHeaders)
                .timeout(const Duration(seconds: 8));
          } else {
            retryResponse = await http.post(
              Uri.parse(url),
              headers: retryHeaders,
              body: bodyStr,
            ).timeout(const Duration(seconds: 8));
          }

          _absorbXUser(retryResponse.headers);

          if (retryResponse.statusCode == 200) {
            final resData = jsonDecode(retryResponse.body);
            _activeBase = base;
            if (resData is Map && resData.containsKey("data")) {
              return Map<String, dynamic>.from(resData["data"]);
            }
            return Map<String, dynamic>.from(resData);
          } else {
            lastError = RateLimitException(
              "Server membatasi akses (Rate Limited oleh server). Silakan tunggu beberapa saat.",
              retryAfter: Duration(seconds: retryAfterSec),
            );
            continue;
          }
        } else {
          if (response.statusCode == 401 || response.statusCode == 403 || response.statusCode == 441) {
            _runtimeToken = null; // Clear token to force refresh
            clearPersistedSession();
            if (!isAuthExempt) {
              print("Auth failed with ${response.statusCode}. Retrying with a new token...");
              await _ensureToken();
              if (_runtimeToken != null) {
                final retryHeaders = _buildSignedHeaders(
                  method: method,
                  url: url,
                  contentType: contentType,
                  body: bodyStr,
                  authToken: _runtimeToken,
                );
                final http.Response retryResponse;
                if (method == "GET") {
                  retryResponse = await http.get(Uri.parse(url), headers: retryHeaders)
                      .timeout(const Duration(seconds: 8));
                } else {
                  retryResponse = await http.post(
                    Uri.parse(url),
                    headers: retryHeaders,
                    body: bodyStr,
                  ).timeout(const Duration(seconds: 8));
                }

                _absorbXUser(retryResponse.headers);

                if (retryResponse.statusCode == 200) {
                  final resData = jsonDecode(retryResponse.body);
                  _activeBase = base; // Lock in successful base
                  if (resData is Map && resData.containsKey("data")) {
                    return Map<String, dynamic>.from(resData["data"]);
                  }
                  return Map<String, dynamic>.from(resData);
                } else {
                  lastError = ApiException(
                    "Server mengembalikan kode ${retryResponse.statusCode} untuk $url",
                    statusCode: retryResponse.statusCode,
                  );
                  continue; // Try next host
                }
              }
            }
          }
          lastError = ApiException(
            "Server mengembalikan kode ${response.statusCode} untuk $url",
            statusCode: response.statusCode,
          );
        }
      } catch (e) {
        if (e is RateLimitException || e is ApiException) {
          lastError = e;
        } else {
          lastError = NetworkConnectionException(
            "Koneksi jaringan gagal ke $url. Periksa koneksi internet Anda.",
          );
        }
      }
    }
    // If all hosts in the pool failed and we haven't retried yet,
    // trigger on-demand Remote Config refresh to get updated host pool
    if (!isRetryAfterRefresh) {
      final refreshed = await RemoteConfigService.instance
          .refreshConfigOnFailure(reason: 'moviebox_hosts_exhausted');
      if (refreshed) {
        final newPool = hostPool;
        if (newPool.isNotEmpty) {
          _activeBase = newPool.first;
          return _request(
            method,
            pathAndQuery,
            body: body,
            isRetryAfterRefresh: true,
          );
        }
      }
    }

    throw lastError ?? NetworkConnectionException("Semua host server gagal merespons. Periksa koneksi internet Anda.");
  }

  // --- API Endpoints ---

  /// Get Homepage items
  Future<Map<String, dynamic>> getHomepage({int page = 1, int tabId = 0}) async {
    return _request(
      "GET",
      "/wefeed-mobile-bff/tab-operating?page=$page&tabId=$tabId&version=",
    );
  }

  /// Decode CloudFront-Policy or Edge-Cache-Cookie from signed cookie string to obtain MPEG-DASH manifest URL
  static String? resolveDashManifestFromPolicy(String signCookie) {
    if (signCookie.isEmpty) return null;
    for (final part in signCookie.split(';')) {
      final trimmed = part.trim();

      // MovieBox-TUI v0.1.22: Edge-Cache-Cookie urlprefix decoding
      if (trimmed.contains('urlprefix=')) {
        final idx = trimmed.indexOf('urlprefix=');
        final prefixPart = trimmed.substring(idx + 'urlprefix='.length);
        final b64Token = prefixPart.split(':').first.trim();
        var normalized = b64Token
            .replaceAll('-', '+')
            .replaceAll('_', '/');
        final pad = (4 - (normalized.length % 4)) % 4;
        if (pad > 0 && pad < 4) {
          normalized += '=' * pad;
        }
        try {
          final decodedBytes = base64.decode(normalized);
          final urlStr = utf8.decode(decodedBytes);
          var baseResource = urlStr.trim();
          while (baseResource.endsWith('*') || baseResource.endsWith('/')) {
            baseResource = baseResource.substring(0, baseResource.length - 1).trim();
          }
          if (baseResource.isNotEmpty &&
              (baseResource.startsWith('http://') || baseResource.startsWith('https://'))) {
            return '$baseResource/index.mpd';
          }
        } catch (_) {}
      }

      // CloudFront-Policy decoding
      if (trimmed.startsWith('CloudFront-Policy=')) {
        final raw = trimmed.substring('CloudFront-Policy='.length).trim();
        String normalized = raw
            .replaceAll('-', '+')
            .replaceAll('_', '=')
            .replaceAll('~', '/');
        final pad = (4 - (normalized.length % 4)) % 4;
        if (pad > 0 && pad < 4) {
          normalized += '=' * pad;
        }
        try {
          final decodedBytes = base64.decode(normalized);
          final jsonStr = utf8.decode(decodedBytes);
          final data = jsonDecode(jsonStr);
          final statements = data['Statement'] as List?;
          if (statements != null && statements.isNotEmpty) {
            final resource = statements[0]['Resource']?.toString() ?? '';
            var clean = resource;
            if (clean.endsWith('*')) clean = clean.substring(0, clean.length - 1);
            if (clean.endsWith('/')) clean = clean.substring(0, clean.length - 1);
            if (clean.startsWith('http://') || clean.startsWith('https://')) {
              return '$clean/index.mpd';
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }

  /// Check whether a given URL points to the deprecated version notification MP4 video
  static bool isDeprecationNoticeUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    return lower.contains("1c7de0bd3393702d9191801f15f88f8d") ||
           lower.contains("9a0461bc39da389663bf3dbb17091d3f") ||
           lower.contains("b164fbfb4347792950bdfbfb563d39d9") ||
           lower.contains("/notice.mp4") ||
           lower.contains("notice") ||
           (lower.contains("macdn.aoneroom.com") && lower.contains("/other/"));
  }

  /// Clean titles by removing tags, season prefixes, resolution tags, brackets
  static String cleanMovieBoxTitle(String rawTitle) {
    var title = rawTitle.trim();
    if (title.isEmpty) return "";

    while (title.startsWith('[')) {
      final closePos = title.indexOf(']');
      if (closePos != -1) {
        final remainder = title.substring(closePos + 1).trim();
        if (remainder.isNotEmpty) {
          title = remainder;
        } else {
          break;
        }
      } else {
        break;
      }
    }

    final openBracket = title.indexOf('[');
    if (openBracket > 0) {
      title = title.substring(0, openBracket).trim();
    }

    final openParen = title.indexOf('(');
    if (openParen > 0) {
      final inside = title.substring(openParen + 1);
      final insideContent = inside.split(')').first.trim();
      final year = int.tryParse(insideContent);
      final isYear = insideContent.length == 4 && year != null && year >= 1900 && year <= 2099;
      if (!isYear) {
        title = title.substring(0, openParen).trim();
      }
    }

    final dashPos = title.lastIndexOf(" - ");
    if (dashPos != -1) {
      final suffix = title.substring(dashPos + 3).toLowerCase();
      const tags = [
        "hindi", "tamil", "telugu", "kannada", "malayalam", "bengali",
        "marathi", "punjabi", "gujarati", "urdu", "english", "spanish",
        "french", "german", "italian", "japanese", "korean", "chinese",
        "russian", "portuguese", "turkish", "arabic", "dub", "audio",
        "multi", "season"
      ];
      if (tags.any((t) => suffix.contains(t))) {
        title = title.substring(0, dashPos).trim();
      }
    }

    return title.trim();
  }

  /// Search movies & TV shows
  Future<Map<String, dynamic>> search({
    required String query,
    int page = 1,
    int perPage = 20,
    int subjectType = 0, // 0 = ALL, 1 = MOVIES, 2 = TV_SERIES
  }) async {
    final payload = {
      "keyword": query,
      "page": page,
      "perPage": perPage,
      "subjectType": subjectType,
    };
    Map<String, dynamic> res;
    try {
      res = await _request(
        "POST",
        "/wefeed-mobile-bff/subject-api/search/v2",
        body: payload,
      );
    } catch (_) {
      res = await _request(
        "POST",
        "/wefeed-mobile-bff/subject-api/search",
        body: payload,
      );
    }

    // Normalize subjects across API schema variations
    // v2: { results: [ { subjects: [ ... ] } ] }
    // v1: { list: [ ... ] } or { items: [ ... ] }
    List<dynamic> subjects = [];
    if (res['results'] is List && (res['results'] as List).isNotEmpty) {
      final firstGroup = (res['results'] as List).first;
      if (firstGroup is Map && firstGroup['subjects'] is List) {
        subjects = List<dynamic>.from(firstGroup['subjects'] as List);
      }
    }
    if (subjects.isEmpty && res['items'] is List) {
      subjects = List<dynamic>.from(res['items'] as List);
    }
    if (subjects.isEmpty && res['list'] is List) {
      subjects = List<dynamic>.from(res['list'] as List);
    }

    return {
      ...res,
      'items': subjects,
      'list': subjects,
    };
  }

  /// Get Details of a Movie/TV show
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    return _request(
      "GET",
      "/wefeed-mobile-bff/subject-api/get?subjectId=$subjectId",
    );
  }

  /// Get Season details for a TV show
  Future<Map<String, dynamic>> getSeasonInfo({required String subjectId}) async {
    return _request(
      "GET",
      "/wefeed-mobile-bff/subject-api/season-info?subjectId=$subjectId",
    );
  }

  /// Get Playback Info (v2 API for MPEG-DASH streams with CloudFront signed cookies)
  Future<Map<String, dynamic>> getPlayInfo({
    required String subjectId,
    int se = 0,
    int ep = 0,
  }) async {
    final path = (se > 0 || ep > 0)
        ? "/wefeed-mobile-bff/subject-api/play-info/v2?subjectId=$subjectId&se=$se&ep=$ep"
        : "/wefeed-mobile-bff/subject-api/play-info/v2?subjectId=$subjectId";
    return _request("GET", path);
  }

  /// Legacy raw resource endpoint (M3U8 / MP4 files)
  Future<Map<String, dynamic>> _getRawResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
    int resolution = 1080,
  }) async {
    final queryParams = (se > 0 || ep > 0)
        ? "subjectId=$subjectId&se=$se&ep=$ep&page=1&perPage=20${resolution > 0 ? '&resolution=$resolution' : ''}"
        : "subjectId=$subjectId&page=1&perPage=20${resolution > 0 ? '&resolution=$resolution' : ''}";
    return _request(
      "GET",
      "/wefeed-mobile-bff/subject-api/resource?$queryParams",
    );
  }

  /// Get Streaming video resources (MPEG-DASH / MP4 files)
  /// Prioritizes play-info/v2 DASH streams, decodes CloudFront signed policy,
  /// attaches authentication headers, links resourceId for captions,
  /// and automatically filters out deprecation notice videos.
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
    int resolution = 1080,
  }) async {
    // 1. Fetch play-info/v2 and raw resources in parallel
    final playInfoFuture = getPlayInfo(subjectId: subjectId, se: se, ep: ep)
        .catchError((_) => <String, dynamic>{});
    final rawResourceFuture = _getRawResources(
      subjectId: subjectId,
      se: se,
      ep: ep,
      resolution: resolution,
    ).catchError((_) => <String, dynamic>{});

    final results = await Future.wait([playInfoFuture, rawResourceFuture]);
    final playInfo = results[0];
    final rawRes = results[1];

    // Grab raw resources list to extract matching resourceId (needed for captions)
    final rawList = (rawRes['list'] ?? (rawRes['data'] is Map ? rawRes['data']['list'] : null) ?? []) as List<dynamic>;
    String? matchedResourceId;
    for (final item in rawList) {
      if (item is Map) {
        final itemSe = int.tryParse(item['se']?.toString() ?? '') ?? 0;
        final itemEp = int.tryParse(item['ep']?.toString() ?? '') ?? 0;
        if ((se == 0 && ep == 0) || (itemSe == se && itemEp == ep)) {
          matchedResourceId = item['resourceId']?.toString() ?? item['id']?.toString();
          if (matchedResourceId != null && matchedResourceId.isNotEmpty) break;
        }
      }
    }
    if (matchedResourceId == null && rawList.isNotEmpty && rawList.first is Map) {
      matchedResourceId = rawList.first['resourceId']?.toString() ?? rawList.first['id']?.toString();
    }

    final playData = playInfo['data'] is Map ? playInfo['data'] as Map<String, dynamic> : playInfo;
    final rawStreams = (playData['streams'] as List<dynamic>?) ?? [];
    final List<Map<String, dynamic>> adaptedStreams = [];

    for (final st in rawStreams) {
      if (st is! Map) continue;
      final signCookie = (st['signCookie'] ?? '').toString();
      final streamUrl = (st['url'] ?? '').toString();

      // Attempt DASH manifest extraction from signCookie
      String? playableUrl = resolveDashManifestFromPolicy(signCookie);

      // If no DASH manifest, fallback to direct streamUrl if not a notice video
      if (playableUrl == null) {
        if (!isDeprecationNoticeUrl(streamUrl) && streamUrl.startsWith('http')) {
          playableUrl = streamUrl;
        }
      }

      if (playableUrl == null) continue;

      final isDash = playableUrl.endsWith('.mpd') || (st['format'] ?? '').toString().toUpperCase() == 'DASH';
      final resStr = (st['resolutions'] ?? playData['displayResolutions'] ?? '1080,720,480').toString();
      final resList = resStr
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
      final maxRes = resList.isNotEmpty ? resList.reduce(max) : 1080;

      final headers = <String, String>{
        "User-Agent": _userAgent,
        "Referer": streamReferer,
      };
      final cleanCookie = signCookie
          .split(';')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join('; ');
      if (cleanCookie.isNotEmpty) {
        headers["Cookie"] = cleanCookie;
      }

      final streamId = st['id']?.toString() ?? matchedResourceId ?? '';
      final codec = (st['codecName'] ?? st['codec'] ?? 'hevc').toString();
      final rawTitle = (playData['title'] ?? 'MovieBox Stream').toString();
      final title = cleanMovieBoxTitle(rawTitle);

      if (isDash && resList.length > 1) {
        for (final r in resList) {
          adaptedStreams.add({
            'resourceId': streamId,
            'resourceLink': playableUrl,
            'resource_link': playableUrl,
            'url': playableUrl,
            'resolution': r,
            'codecName': codec,
            'codec_name': codec,
            'format': 'DASH',
            'size': st['size'] ?? 0,
            'fileName': se > 0 && ep > 0
                ? "$title S${se.toString().padLeft(2, '0')}E${ep.toString().padLeft(2, '0')} ${r}p $codec"
                : "$title ${r}p $codec",
            'headers': headers,
            'signCookie': signCookie,
            'se': se,
            'ep': ep,
          });
        }
      } else {
        adaptedStreams.add({
          'resourceId': streamId,
          'resourceLink': playableUrl,
          'resource_link': playableUrl,
          'url': playableUrl,
          'resolution': maxRes,
          'codecName': codec,
          'codec_name': codec,
          'format': isDash ? 'DASH' : 'MP4',
          'size': st['size'] ?? 0,
          'fileName': se > 0 && ep > 0
              ? "$title S${se.toString().padLeft(2, '0')}E${ep.toString().padLeft(2, '0')} ${maxRes}p $codec"
              : "$title ${maxRes}p $codec",
          'headers': headers,
          'signCookie': signCookie,
          'se': se,
          'ep': ep,
        });
      }
    }

    // MovieBox-TUI v0.1.22: Concurrently merge play-info/v2 DASH streams and
    // high-bitrate server files, deduplicate links, and sort numerically by resolution & size.
    final Set<String> seenBaseUrls = {};
    final List<Map<String, dynamic>> combinedReleases = [];

    for (final st in adaptedStreams) {
      final link = (st['resourceLink'] ?? st['resource_link'] ?? st['url'] ?? '').toString();
      final base = link.split('?').first.trim();
      if (base.isNotEmpty) {
        seenBaseUrls.add(base);
      }
      combinedReleases.add(st);
    }

    for (final item in rawList) {
      if (item is! Map) continue;
      final rawMap = Map<String, dynamic>.from(item);
      final link = (rawMap['resourceLink'] ?? rawMap['resource_link'] ?? rawMap['url'] ?? '').toString();
      if (link.isEmpty || isDeprecationNoticeUrl(link)) continue;

      final itemSe = int.tryParse(rawMap['se']?.toString() ?? '') ?? 0;
      final itemEp = int.tryParse(rawMap['ep']?.toString() ?? '') ?? 0;
      final matchesEpisode = (se == 0 && ep == 0) ||
          (itemSe == se && itemEp == ep) ||
          (itemSe == 0 && itemEp == 0);
      if (!matchesEpisode) continue;

      final base = link.split('?').first.trim();
      if (base.isNotEmpty && seenBaseUrls.contains(base)) continue;
      if (base.isNotEmpty) seenBaseUrls.add(base);

      // Ensure standard keys
      rawMap['resourceLink'] ??= link;
      rawMap['resource_link'] ??= link;
      rawMap['url'] ??= link;
      combinedReleases.add(rawMap);
    }

    // Sort by resolution descending (numeric), then size descending
    combinedReleases.sort((a, b) {
      final resA = int.tryParse(a['resolution']?.toString() ?? '') ?? 0;
      final resB = int.tryParse(b['resolution']?.toString() ?? '') ?? 0;
      if (resB != resA) return resB.compareTo(resA);
      final sizeA = int.tryParse(a['size']?.toString() ?? '') ?? 0;
      final sizeB = int.tryParse(b['size']?.toString() ?? '') ?? 0;
      return sizeB.compareTo(sizeA);
    });

    return {
      'code': 0,
      'message': 'ok',
      'list': combinedReleases,
      'data': {'list': combinedReleases},
    };
  }

  /// Get Subtitles (external captions) for a selected resource
  Future<Map<String, dynamic>> getExtCaptions({
    required String subjectId,
    required String resourceId,
  }) async {
    return _request(
      "GET",
      "/wefeed-mobile-bff/subject-api/get-ext-captions?subjectId=$subjectId&resourceId=$resourceId",
    );
  }

  /// Get clean, valid external captions with cross-dub aggregation and filtering.
  /// Filters dummy/corrupted placeholder files (size <= 50 bytes or placeholder hashes)
  /// and normalizes Indonesian/other language tags.
  Future<List<dynamic>> getCleanExtCaptions({
    required String subjectId,
    required String resourceId,
    List<String> siblingSubjectIds = const [],
    int se = 0,
    int ep = 0,
  }) async {
    final List<dynamic> allCaptions = [];
    final Set<String> seenUrls = {};

    void appendCaptions(dynamic rawList) {
      if (rawList is! List) return;
      for (final cap in rawList) {
        if (cap is! Map) continue;
        final url = (cap['url'] ?? '').toString();
        if (url.isEmpty || url.contains('aa348f2541d13ffe')) continue;

        final rawSize = cap['size'];
        int size = 0;
        if (rawSize is num) {
          size = rawSize.toInt();
        } else if (rawSize != null) {
          size = int.tryParse(rawSize.toString()) ?? 0;
        }

        // Filter out dummy/empty 34-50 byte caption placeholder files
        if (size > 0 && size <= 50) continue;

        String lanName = (cap['lanName'] ?? cap['lan'] ?? cap['language'] ?? 'Unknown').toString().trim();
        if (lanName.isEmpty) lanName = 'Unknown';

        // Normalize Indonesian language naming
        final lanLower = lanName.toLowerCase();
        if (lanLower == 'in' || lanLower == 'in_id' || lanLower == 'id' || lanLower == 'ina') {
          if (size > 0 && size <= 100) continue; // Filter corrupted in captions
          lanName = 'Indonesian';
        } else if (lanLower == 'en' || lanLower == 'eng') {
          lanName = 'English';
        }

        if (seenUrls.add(url)) {
          final cleanCap = Map<String, dynamic>.from(cap);
          cleanCap['lanName'] = lanName;
          cleanCap['url'] = url;
          allCaptions.add(cleanCap);
        }
      }
    }

    // 1. Fetch from active stream's resourceId & subjectId
    try {
      if (resourceId.isNotEmpty) {
        final res = await getExtCaptions(subjectId: subjectId, resourceId: resourceId);
        final list = res['extCaptions'] ?? (res['data'] is Map ? res['data']['extCaptions'] : null);
        appendCaptions(list);
      }
    } catch (e) {
      print("Primary caption fetch error: $e");
    }

    // 1b. If primary resource had no captions, query other resources of the same subject
    if (allCaptions.isEmpty && subjectId.isNotEmpty) {
      try {
        final resList = await getResources(subjectId: subjectId, se: se, ep: ep, resolution: 1080);
        final files = resList['list'] ?? (resList['data'] is Map ? resList['data']['list'] : null) ?? [];
        if (files is List && files.isNotEmpty) {
          for (final f in files) {
            if (f is Map) {
              final rid = f['resourceId']?.toString() ?? f['id']?.toString() ?? '';
              if (rid.isNotEmpty && rid != resourceId) {
                final extRes = await getExtCaptions(subjectId: subjectId, resourceId: rid);
                final list = extRes['extCaptions'] ?? (extRes['data'] is Map ? extRes['data']['extCaptions'] : null);
                appendCaptions(list);
                if (allCaptions.isNotEmpty) break;
              }
            }
          }
        }
      } catch (_) {}
    }

    // 2. Cross-dub fallback: If active dub has few/no captions (< 5), query sibling dubs
    if (allCaptions.length < 5 && siblingSubjectIds.isNotEmpty) {
      final validSiblings = siblingSubjectIds
          .where((id) => id.isNotEmpty && id != subjectId)
          .take(3)
          .toList();

      if (validSiblings.isNotEmpty) {
        final siblingResults = await Future.wait(validSiblings.map((sibId) async {
          try {
            final resList = await getResources(subjectId: sibId, se: se, ep: ep, resolution: 1080);
            final files = resList['list'] ?? (resList['data'] is Map ? resList['data']['list'] : null) ?? [];
            if (files is List && files.isNotEmpty) {
              // Find matching episode or fallback to first
              dynamic matchItem;
              for (final f in files) {
                if (f is Map) {
                  final fSe = int.tryParse(f['se']?.toString() ?? '') ?? 0;
                  final fEp = int.tryParse(f['ep']?.toString() ?? '') ?? 0;
                  if (se == 0 && ep == 0) {
                    matchItem = f;
                    break;
                  }
                  if (fSe == se && fEp == ep) {
                    matchItem = f;
                    break;
                  }
                }
              }
              matchItem ??= files[0];
              if (matchItem is Map) {
                final sibRid = matchItem['resourceId']?.toString() ?? matchItem['id']?.toString() ?? '';
                if (sibRid.isNotEmpty) {
                  final sibSubs = await getExtCaptions(subjectId: sibId, resourceId: sibRid);
                  return sibSubs['extCaptions'] ?? (sibSubs['data'] is Map ? sibSubs['data']['extCaptions'] : null);
                }
              }
            }
          } catch (_) {}
          return null;
        }));

        for (final sList in siblingResults) {
          if (sList != null) {
            appendCaptions(sList);
          }
        }
      }
    }

    // Deduplicate by language name so user doesn't see duplicate tracks for the same language
    final List<dynamic> deduplicated = [];
    final Set<String> seenLanguages = {};
    for (final cap in allCaptions) {
      final lang = (cap['lanName'] ?? '').toString().toLowerCase();
      if (seenLanguages.add(lang)) {
        deduplicated.add(cap);
      }
    }

    return deduplicated;
  }
}

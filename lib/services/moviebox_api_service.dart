import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

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

  static const List<String> HOST_POOL = [
    "https://api6.aoneroom.com",
    "https://api5.aoneroom.com",
    "https://api4.aoneroom.com",
    "https://api4sg.aoneroom.com",
    "https://api3.aoneroom.com",
    "https://api6sg.aoneroom.com",
    "https://api.inmoviebox.com",
  ];

  static const String SECRET_KEY_DEFAULT = "76iRl07s0xSN9jqmEWAt79EBJZulIQIsV64FZr2O";
  static const String SECRET_KEY_ALT = "Xqn2nnO41/L92o1iuXhSLHTbXvY4Z5ZZ62m8mSLA";

  // Active base host which we rotate on failure
  String _activeBase = HOST_POOL[0];

  // Token absorbed from the server dynamically
  String? _runtimeToken;
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
      final token = payload['token'] ?? "";
      if (token.isNotEmpty) {
        _runtimeToken = token;
        print("ABSORBED DART RUNTIME TOKEN: $_runtimeToken");
      }
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
    
    print("No token found. Fetching token...");
    _tokenFetchFuture = () async {
      try {
        await getHomepage(page: 1, tabId: 0);
        print("Token fetched successfully: $_runtimeToken");
      } catch (e) {
        print("Failed to fetch token: $e");
      } finally {
        _tokenFetchFuture = null;
      }
    }();
    return _tokenFetchFuture;
  }

  /// Generic request handler with pool fallback
  Future<Map<String, dynamic>> _request(
    String method,
    String pathAndQuery, {
    Map<String, dynamic>? body,
  }) async {
    if (_runtimeToken == null && !pathAndQuery.contains("tab-operating")) {
      await _ensureToken();
    }

    Object? lastError;
    
    // Order hosts starting with the active base
    final orderedHosts = [
      _activeBase,
      ...HOST_POOL.where((element) => element != _activeBase)
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
            if (!pathAndQuery.contains("tab-operating")) {
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
    return _request(
      "POST",
      "/wefeed-mobile-bff/subject-api/search",
      body: payload,
    );
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

  /// Get Streaming video resources (M3U8 / MP4 files)
  /// For Movies: se = 0, ep = 0
  /// For Series: pass actual se (season) and ep (episode)
  Future<Map<String, dynamic>> getResources({
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

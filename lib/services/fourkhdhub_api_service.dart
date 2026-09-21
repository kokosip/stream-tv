import 'dart:convert';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as html_dom;
import 'package:http/http.dart' as http;

class FourKHdHubApiService {
  static const String DEFAULT_BASE_URL = "https://4khdhub.one/";
  static const String BROWSER_UA =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  final String baseUrl;
  final http.Client _client = http.Client();

  FourKHdHubApiService({this.baseUrl = DEFAULT_BASE_URL});

  Map<String, String> get _headers => {
        "User-Agent": BROWSER_UA,
        "Referer": baseUrl,
      };

  /// Clean path to relative subjectId
  String _normalizeSubjectId(String href) {
    Uri? uri = Uri.tryParse(href);
    if (uri != null) {
      return uri.path;
    }
    return href;
  }

  /// Search movies and TV shows on 4KHDHub
  Future<Map<String, dynamic>> search({
    required String query,
    int page = 1,
    int subjectType = 0,
  }) async {
    final searchUrl = Uri.parse(baseUrl).replace(
      queryParameters: {"s": query},
    );

    try {
      final response = await _client
          .get(searchUrl, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception("4KHDHub search server error: ${response.statusCode}");
      }

      final doc = html_parser.parse(response.body);
      final cards = doc.querySelectorAll("a.movie-card");
      final List<Map<String, dynamic>> items = [];

      for (final card in cards) {
        final href = card.attributes['href'] ?? "";
        if (href.isEmpty) continue;

        final subjectId = _normalizeSubjectId(href);
        final titleEl = card.querySelector(".movie-card-title");
        final title = titleEl?.text.trim() ?? "";
        if (title.isEmpty) continue;

        final metaEl = card.querySelector(".movie-card-meta");
        final metaText = metaEl?.text.trim() ?? "";
        final year = _extractFourDigitYear(metaText) ?? _extractFourDigitYear(title);

        final imgEl = card.querySelector("img");
        final posterUrl = imgEl?.attributes['src'];

        final isSeries = href.contains("-series-");
        final typeInt = isSeries ? 2 : 1;

        if (subjectType > 0 && typeInt != subjectType) {
          continue;
        }

        items.add({
          "subjectId": subjectId,
          "id": subjectId,
          "title": title,
          "subjectTitle": title,
          "subjectType": typeInt,
          "releaseDate": year ?? "",
          "cover": {"url": posterUrl ?? ""},
          "imdbRate": "",
          "provider": "4khdhub",
          "seasonCount": _parseSeasonCount(metaText),
        });
      }

      return {
        "items": items,
        "results": [
          {"subjects": items}
        ]
      };
    } catch (e) {
      print("4KHDHub Search Error: $e");
      rethrow;
    }
  }

  /// Get Homepage items from 4KHDHub latest posts
  Future<Map<String, dynamic>> getHomepage({int page = 1, int tabId = 0}) async {
    try {
      final response = await _client
          .get(Uri.parse(baseUrl), headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception("4KHDHub home server error: ${response.statusCode}");
      }

      final doc = html_parser.parse(response.body);
      final cards = doc.querySelectorAll("a.movie-card");
      final List<Map<String, dynamic>> movieItems = [];
      final List<Map<String, dynamic>> seriesItems = [];

      for (final card in cards) {
        final href = card.attributes['href'] ?? "";
        if (href.isEmpty) continue;

        final subjectId = _normalizeSubjectId(href);
        final titleEl = card.querySelector(".movie-card-title");
        final title = titleEl?.text.trim() ?? "";
        if (title.isEmpty) continue;

        final metaEl = card.querySelector(".movie-card-meta");
        final metaText = metaEl?.text.trim() ?? "";
        final year = _extractFourDigitYear(metaText) ?? _extractFourDigitYear(title);

        final imgEl = card.querySelector("img");
        final posterUrl = imgEl?.attributes['src'];

        final isSeries = href.contains("-series-");
        final typeInt = isSeries ? 2 : 1;

        final item = {
          "subjectId": subjectId,
          "id": subjectId,
          "title": title,
          "subjectTitle": title,
          "subjectType": typeInt,
          "releaseDate": year ?? "",
          "cover": {"url": posterUrl ?? ""},
          "imdbRate": "",
          "provider": "4khdhub",
        };

        if (isSeries) {
          seriesItems.add(item);
        } else {
          movieItems.add(item);
        }
      }

      final List<Map<String, dynamic>> homeSections = [];
      if (movieItems.isNotEmpty) {
        homeSections.add({
          "type": "SUBJECTS_MOVIE",
          "title": "4KHDHub Latest Movies",
          "subjects": movieItems,
        });
      }
      if (seriesItems.isNotEmpty) {
        homeSections.add({
          "type": "SUBJECTS_MOVIE",
          "title": "4KHDHub Latest Series",
          "subjects": seriesItems,
        });
      }

      return {"items": homeSections};
    } catch (e) {
      print("4KHDHub Homepage Error: $e");
      rethrow;
    }
  }

  /// Get Details of a Movie/TV show from 4KHDHub
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    final cleanPath = subjectId.startsWith("/") ? subjectId.substring(1) : subjectId;
    final detailUrl = Uri.parse(baseUrl).resolve(cleanPath);

    try {
      final response = await _client
          .get(detailUrl, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception("4KHDHub detail server error: ${response.statusCode}");
      }

      final doc = html_parser.parse(response.body);

      final h1 = doc.querySelector("h1");
      final ogTitle = doc.querySelector('meta[property="og:title"]')?.attributes['content'];
      final rawTitle = h1?.text.trim() ?? ogTitle ?? "Untitled";
      final title = _stripTrailingYear(rawTitle);

      final isSeries = subjectId.contains("-series-");
      final subjectType = isSeries ? 2 : 1;

      final descEl = doc.querySelector(".content-section p.mt-4") ??
          doc.querySelector('meta[name="description"]');
      final description = descEl?.text.trim() ?? descEl?.attributes['content'] ?? "";

      final ogImage = doc.querySelector('meta[property="og:image"]')?.attributes['content'];

      final releaseMeta = _findMetadata(doc, "Release:") ??
          _findMetadata(doc, "Last Air:");
      final year = releaseMeta != null
          ? _extractFourDigitYear(releaseMeta)
          : _extractFourDigitYear(rawTitle);

      final director = _findMetadata(doc, "Director:");
      final stars = _findMetadata(doc, "Stars:");
      final prints = _findMetadata(doc, "Prints:") ?? _findMetadata(doc, "Print:");
      final audios = _findMetadata(doc, "Audios:");
      final imdbRating = doc.querySelector(".imdb-score")?.text.trim();

      final List<String> genres = [];
      for (final gNode in doc.querySelectorAll(".badge-outline a")) {
        final text = gNode.text.trim();
        if (_isGenre(text)) {
          genres.add(text);
        }
      }

      // Parse seasons & episodes for series
      final List<Map<String, dynamic>> seasonsList = [];
      if (isSeries) {
        final episodeItems = doc.querySelectorAll("#episodes .episode-download-item");
        final Map<int, Set<int>> seasonMap = {};

        for (final item in episodeItems) {
          final fileTitleEl = item.querySelector(".episode-file-title");
          final filename = fileTitleEl?.text.trim() ?? "";
          final seEp = _parseSeasonEpisode(filename);
          if (seEp != null) {
            seasonMap.putIfAbsent(seEp[0], () => {}).add(seEp[1]);
          }
        }

        final sortedSeasons = seasonMap.keys.toList()..sort();
        for (final sNum in sortedSeasons) {
          final epNumbers = seasonMap[sNum]!.toList()..sort();
          seasonsList.add({
            "se": sNum,
            "seasonNumber": sNum,
            "maxEp": epNumbers.length,
            "episodeNumbers": epNumbers,
          });
        }
      }

      return {
        "id": subjectId,
        "subjectId": subjectId,
        "title": title,
        "subjectTitle": title,
        "subjectType": subjectType,
        "releaseDate": year ?? "",
        "description": description,
        "imdbRatingValue": imdbRating ?? "",
        "director": director ?? "",
        "stars": stars ?? "",
        "prints": prints ?? "",
        "audios": audios ?? "",
        "cover": {"url": ogImage ?? ""},
        "genre": genres.join(", "),
        "provider": "4khdhub",
        "seasons": {"seasons": seasonsList},
      };
    } catch (e) {
      print("4KHDHub Details Error: $e");
      rethrow;
    }
  }

  /// Get Resources / Stream Releases for a Movie or TV Episode
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
  }) async {
    final cleanPath = subjectId.startsWith("/") ? subjectId.substring(1) : subjectId;
    final detailUrl = Uri.parse(baseUrl).resolve(cleanPath);

    try {
      final response = await _client
          .get(detailUrl, headers: _headers)
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw Exception("4KHDHub resource fetch error: ${response.statusCode}");
      }

      final doc = html_parser.parse(response.body);
      final isSeries = se > 0;

      final itemSelector = isSeries ? "#episodes .episode-download-item" : ".download-item";
      final filenameSelector = isSeries ? ".episode-file-title" : ".file-title";

      final items = doc.querySelectorAll(itemSelector);
      final List<Map<String, dynamic>> releases = [];

      for (final item in items) {
        final titleEl = item.querySelector(filenameSelector);
        final filename = titleEl?.text.trim() ?? "";
        if (filename.isEmpty || _isArchive(filename)) continue;

        if (isSeries) {
          final parsedSeEp = _parseSeasonEpisode(filename);
          if (parsedSeEp == null || parsedSeEp[0] != se || parsedSeEp[1] != ep) {
            continue;
          }
        }

        final List<Map<String, String>> mirrors = [];
        final linkEls = item.querySelectorAll("a[href]");
        for (final link in linkEls) {
          final href = link.attributes['href'] ?? "";
          if (!href.startsWith("https://") || href.contains("logout")) continue;

          final label = link.text.trim().isNotEmpty ? link.text.trim() : "Source";
          mirrors.add({
            "label": label,
            "resolverUrl": href,
          });
        }

        if (mirrors.isEmpty) continue;

        final sizeText = item.querySelector(".badge-size, .badge")?.text.trim();
        final quality = _detectQuality(filename);
        final codec = _detectCodec(filename);

        int resNum = 1080;
        if (quality != null) {
          final cleanedRes = quality.replaceAll(RegExp(r'[^0-9]'), '');
          resNum = int.tryParse(cleanedRes) ?? 1080;
        }

        releases.add({
          "resourceId": "4khd-${releases.length}",
          "title": filename,
          "fileName": filename,
          "size": sizeText ?? "",
          "resolution": resNum,
          "codecName": codec ?? "",
          "uploadBy": "4KHDHub",
          "se": se,
          "ep": ep,
          "mirrors": mirrors,
          "provider": "4khdhub",
        });
      }

      // MovieBox-TUI v0.1.22: Sort numerically by resolution descending, then size
      releases.sort((a, b) {
        final resA = (a['resolution'] as int?) ?? 0;
        final resB = (b['resolution'] as int?) ?? 0;
        if (resB != resA) return resB.compareTo(resA);
        final sizeA = a['size']?.toString() ?? '';
        final sizeB = b['size']?.toString() ?? '';
        return sizeB.compareTo(sizeA);
      });

      return {
        "list": releases,
      };
    } catch (e) {
      print("4KHDHub Resources Error: $e");
      rethrow;
    }
  }

  /// Resolve HubDrive / HubCloud / Mediator / PixelDrain release mirror to a playable direct video URL
  Future<Map<String, dynamic>?> resolveRelease(
    Map<String, dynamic> resourceItem, {
    bool isPlayback = true,
  }) async {
    final List<dynamic> mirrors = resourceItem["mirrors"] ?? [];
    if (mirrors.isEmpty) return null;

    final List<Map<String, String>> allCandidates = [];
    String? lastError;

    for (final mirror in mirrors) {
      final String resolverUrl = mirror["resolverUrl"] ?? "";
      if (resolverUrl.isEmpty) continue;

      try {
        List<Map<String, String>> candidates = [];

        if (resolverUrl.contains("greenmotors.") ||
            resolverUrl.contains("greenmountmotors.") ||
            _isMediatorUrl(resolverUrl)) {
          candidates = await _resolveGreenMotors(resolverUrl, isPlayback: isPlayback);
        } else if (resolverUrl.contains("hubcloud.")) {
          candidates = await _resolveHubCloud(resolverUrl, isPlayback: isPlayback);
        } else if (resolverUrl.contains("hubdrive.")) {
          candidates = await _resolveHubDrive(resolverUrl, isPlayback: isPlayback);
        } else {
          final validated = _validatePlaybackUrl(resolverUrl);
          if (validated != null) {
            candidates = [
              {"url": validated, "label": mirror["label"] ?? "Direct"}
            ];
          }
        }

        allCandidates.addAll(candidates);
      } catch (e) {
        print("Mirror candidate fetch failed for $resolverUrl: $e");
        lastError = e.toString();
      }
    }

    if (allCandidates.isEmpty) {
      throw Exception(lastError ?? "No candidate mirrors found on 4KHDHub");
    }

    // Sort candidates according to MovieBox-TUI v0.1.21 prioritization
    allCandidates.sort((a, b) {
      final scoreA = _scoreCandidate(a["url"] ?? "", a["label"] ?? "", isPlayback: isPlayback);
      final scoreB = _scoreCandidate(b["url"] ?? "", b["label"] ?? "", isPlayback: isPlayback);
      return scoreA.compareTo(scoreB);
    });

    // Deduplicate candidate URLs
    final List<Map<String, String>> uniqueCandidates = [];
    final Set<String> seenUrls = {};
    for (final c in allCandidates) {
      final url = c["url"] ?? "";
      if (url.isNotEmpty && seenUrls.add(url)) {
        uniqueCandidates.add(c);
      }
    }

    for (final candidate in uniqueCandidates) {
      final url = candidate["url"]!;
      final label = candidate["label"]!;

      final Map<String, String> streamHeaders = {
        "User-Agent": BROWSER_UA,
        "Referer": baseUrl,
      };

      // Preflight stream probe (MovieBox-TUI v0.1.21 range probe & dead stream detection)
      final playable = await _probeStreamUrl(url, streamHeaders);
      if (playable != null) {
        print("4KHDHub resolved playable stream: $playable ($label)");
        return {
          "mediaUrl": playable,
          "headers": streamHeaders,
          "sourceLabel": label,
        };
      }
    }

    throw Exception(lastError ?? "Mirrors for this release are dead or expired on 4KHDHub.");
  }

  /// Checks if URL belongs to an intermediate mediator domain
  bool _isMediatorUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains("greenmotors.") ||
        lower.contains("greenmountmotors.") ||
        lower.contains("homelander") ||
        lower.contains("bonus") ||
        (!lower.contains("hubcloud") && !lower.contains("hubdrive") && lower.contains("?id="));
  }

  /// Resolve greenmotors / intermediate mediator redirector (MovieBox-TUI v0.1.21)
  Future<List<Map<String, String>>> _resolveGreenMotors(
    String mediatorUrl, {
    bool isPlayback = true,
  }) async {
    final response = await _client
        .get(Uri.parse(mediatorUrl), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception("Mediator redirector returned status ${response.statusCode}");
    }

    final targetUrl = _unpackGreenMotorsUrl(response.body);
    if (targetUrl == null || targetUrl.isEmpty) {
      throw Exception("Failed to decode mediator redirect target");
    }

    if (targetUrl.contains("hubcloud.")) {
      return _resolveHubCloud(targetUrl, isPlayback: isPlayback);
    } else if (targetUrl.contains("hubdrive.")) {
      return _resolveHubDrive(targetUrl, isPlayback: isPlayback);
    } else {
      final validated = _validatePlaybackUrl(targetUrl);
      if (validated != null) {
        return [
          {"url": validated, "label": "Direct"}
        ];
      }
      return [];
    }
  }

  /// Multi-stage unpacking pipeline: Base64 -> Base64 -> ROT13 -> Base64 -> JSON -> Base64
  String? _unpackGreenMotorsUrl(String html) {
    final payload = _extractGreenMotorsPayload(html);
    if (payload == null || payload.isEmpty) return null;
    return _decodeGreenMotorsPayload(payload);
  }

  String? _extractGreenMotorsPayload(String html) {
    try {
      final match = RegExp(r"""s\(\s*['"]o['"]\s*,\s*['"]([^'"]+)['"]""").firstMatch(html);
      if (match != null) {
        return match.group(1);
      }
    } catch (e) {
      print("Error extracting mediator payload: $e");
    }
    return null;
  }

  String _rot13(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        buffer.writeCharCode((code - 65 + 13) % 26 + 65);
      } else if (code >= 97 && code <= 122) {
        buffer.writeCharCode((code - 97 + 13) % 26 + 97);
      } else {
        buffer.writeCharCode(code);
      }
    }
    return buffer.toString();
  }

  String? _decodeGreenMotorsPayload(String payload) {
    try {
      // 1. Base64 decode
      final s1 = utf8.decode(base64.decode(payload));
      // 2. Base64 decode
      final s2 = utf8.decode(base64.decode(s1));
      // 3. ROT13
      final s3 = _rot13(s2);
      // 4. Base64 decode
      final s4 = utf8.decode(base64.decode(s3));
      // 5. JSON parse
      final Map<String, dynamic> data = jsonDecode(s4);
      final oVal = data['o']?.toString();
      if (oVal != null && oVal.isNotEmpty) {
        // 6. Base64 decode target downstream URL
        return utf8.decode(base64.decode(oVal));
      }
    } catch (e) {
      print("Error decoding mediator token: $e");
    }
    return null;
  }

  /// Unwrap base64 Watch Online redirector e.g. vdplay.pages.dev/?u=...
  String? _unwrapWatchOnlineUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.host.contains("pages.dev")) return null;

    final uParam = uri.queryParameters['u'];
    if (uParam == null || uParam.isEmpty) return null;

    try {
      final decoded = utf8.decode(base64.decode(uParam));
      if (decoded.startsWith("https://")) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  /// Resolve HubDrive link -> returns HubCloud link candidates
  Future<List<Map<String, String>>> _resolveHubDrive(
    String driveUrl, {
    bool isPlayback = true,
  }) async {
    final response = await _client
        .get(Uri.parse(driveUrl), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception("HubDrive returned status ${response.statusCode}");
    }

    final doc = html_parser.parse(response.body);
    final links = doc.querySelectorAll("a[href]");

    for (final link in links) {
      final href = link.attributes['href'] ?? "";
      final uri = Uri.tryParse(href);
      if (uri != null &&
          uri.host.contains("hubcloud.") &&
          uri.path.startsWith("/drive/")) {
        return _resolveHubCloud(href, isPlayback: isPlayback);
      }
    }
    throw Exception("HubDrive HubCloud mirror missing");
  }

  /// Resolve HubCloud link -> returns direct candidates (PixelDrain / CDN / Seekable Stream)
  Future<List<Map<String, String>>> _resolveHubCloud(
    String hubCloudUrl, {
    bool isPlayback = true,
  }) async {
    final driveRes = await _client
        .get(Uri.parse(hubCloudUrl), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (driveRes.statusCode != 200) {
      throw Exception("HubCloud drive page status ${driveRes.statusCode}");
    }

    // Check if intermediate shortener payload s('o', ...) is inside HubCloud response
    if (driveRes.body.contains("s('o'") || driveRes.body.contains('s("o"')) {
      final unpacked = _unpackGreenMotorsUrl(driveRes.body);
      if (unpacked != null && unpacked.isNotEmpty && unpacked != hubCloudUrl) {
        return _resolveHubCloud(unpacked, isPlayback: isPlayback);
      }
    }

    final driveDoc = html_parser.parse(driveRes.body);
    // Expanded button selector matching MovieBox-TUI v0.1.21
    final downloadAnchor = driveDoc.querySelector(
      "a#download, a.btn-primary, a.btn-success, a.btn[href*='/download/'], a[href*='/download/'], a[href*='gamerxyt.com'], a[href*='hubcloud.php']",
    );
    final resolverUrl = downloadAnchor?.attributes['href'];

    if (resolverUrl == null || !resolverUrl.startsWith("https://")) {
      throw Exception("HubCloud resolver link missing");
    }

    final resolverRes = await _client
        .get(Uri.parse(resolverUrl), headers: {
          ..._headers,
          "Referer": hubCloudUrl,
        })
        .timeout(const Duration(seconds: 10));

    if (resolverRes.statusCode != 200) {
      throw Exception("HubCloud resolver status ${resolverRes.statusCode}");
    }

    final htmlBody = resolverRes.body;
    final List<Map<String, String>> candidates = [];

    // 1. Extract PixelDrain URLs from script / text
    final pixelDrainUrls = _extractPixelDrainUrls(htmlBody);
    for (final pUrl in pixelDrainUrls) {
      candidates.add({
        "url": pUrl,
        "label": "PixelDrain",
      });
    }

    // 2. Extract anchor links & unwrap Watch Online links
    final resolverDoc = html_parser.parse(htmlBody);
    final linkEls = resolverDoc.querySelectorAll("a[href]");
    for (final link in linkEls) {
      final href = link.attributes['href'] ?? "";
      final label = link.text.trim();

      if (!href.startsWith("https://") ||
          href.endsWith(".zip") ||
          href.contains("login") ||
          href.contains("logout")) {
        continue;
      }

      // Check Watch Online unwrapper
      final unwrapped = _unwrapWatchOnlineUrl(href);
      if (unwrapped != null) {
        final validated = _validatePlaybackUrl(unwrapped);
        if (validated != null && !candidates.any((c) => c["url"] == validated)) {
          candidates.add({
            "url": validated,
            "label": "Watch Online",
          });
        }
        continue;
      }

      // Pixel redirect links e.g. pixel.hubcloud.cx / pixel.hubcloud.ist
      if (href.contains("pixel.hubcloud.") || href.contains("/pixel.")) {
        final resolvedPixel = await _resolvePixelRedirect(href);
        if (resolvedPixel != null && !candidates.any((c) => c["url"] == resolvedPixel)) {
          candidates.add({
            "url": resolvedPixel,
            "label": label.isNotEmpty ? label : "Google Video CDN",
          });
        }
        continue;
      }

      final pApiUrl = _transformPixelDrainUrl(href) ?? href;
      final validated = _validatePlaybackUrl(pApiUrl);
      if (validated != null && !candidates.any((c) => c["url"] == validated)) {
        candidates.add({
          "url": validated,
          "label": label.isNotEmpty ? label : "Direct CDN",
        });
      }
    }

    if (candidates.isEmpty) {
      throw Exception("No stream candidates found in HubCloud resolver");
    }

    return candidates;
  }

  /// Follows pixel.hubcloud.* 302 redirects to direct Google Video CDN / R2 URL
  Future<String?> _resolvePixelRedirect(String pixelUrl) async {
    try {
      String targetUrl = pixelUrl;
      for (int i = 0; i < 5; i++) {
        final req = http.Request("GET", Uri.parse(targetUrl))
          ..headers.addAll(_headers)
          ..followRedirects = false;

        final streamed = await _client.send(req).timeout(const Duration(seconds: 8));
        final location = streamed.headers['location'];

        final uriToCheck = location != null ? Uri.tryParse(location) : Uri.tryParse(targetUrl);
        if (uriToCheck != null) {
          final linkParam = uriToCheck.queryParameters['link'];
          if (linkParam != null && linkParam.startsWith("https://")) {
            return _validatePlaybackUrl(linkParam);
          }
        }

        if (streamed.statusCode >= 300 && streamed.statusCode < 400 && location != null && location.isNotEmpty) {
          targetUrl = location;
          if (targetUrl.startsWith("https://video-downloads.googleusercontent.com") ||
              targetUrl.contains("storage.googleapis.com") ||
              targetUrl.contains("cloudflarestorage.com")) {
            return _validatePlaybackUrl(targetUrl);
          }
          continue;
        }

        if (targetUrl.startsWith("https://video-downloads.googleusercontent.com") ||
            targetUrl.contains("storage.googleapis.com") ||
            targetUrl.contains("cloudflarestorage.com")) {
          return _validatePlaybackUrl(targetUrl);
        }
        break;
      }
    } catch (_) {}
    return null;
  }

  /// Score candidates matching MovieBox-TUI v0.1.21 prioritization
  int _scoreCandidate(String url, String label, {bool isPlayback = true}) {
    final value = "$url $label".toLowerCase();
    if (isPlayback) {
      // For playback: prioritize seekable multi-connection CDNs; deprioritize workers.dev to avoid 403 token burn
      if (value.contains("pixel.hubcloud.") ||
          value.contains("googleusercontent.com") ||
          value.contains("googlevideo.com") ||
          value.contains("cloudflarestorage.com") ||
          value.contains("r2.cloudflarestorage.com") ||
          value.contains("fsl server") ||
          value.contains("r2.dev") ||
          value.contains("watch online")) {
        return 0;
      } else if (value.contains("storage.googleapis.com") ||
          value.contains("hubcloud.cx/re/") ||
          value.contains("hubcloud.fans/re/")) {
        return 1;
      } else if (value.contains("pixeldrain.com") ||
          value.contains("pixeldrain.dev") ||
          value.contains("pixeldrain")) {
        return 2;
      } else if (value.contains("testzip.php") ||
          value.contains("vcloud.php") ||
          value.contains("drive.php") ||
          value.contains("gpdl.")) {
        return 3;
      } else {
        // workers.dev and unknown mirrors are scored 4 for playback
        return 4;
      }
    } else {
      // For download: workers.dev is allowed for high speed
      if (value.contains("pixel.hubcloud.") ||
          value.contains("googleusercontent.com") ||
          value.contains("cloudflarestorage.com") ||
          value.contains("r2.cloudflarestorage.com") ||
          value.contains("fsl server") ||
          value.contains("r2.dev") ||
          value.contains("workers.dev") ||
          value.contains("watch online")) {
        return 0;
      } else if (value.contains("storage.googleapis.com") ||
          value.contains("hubcloud.cx/re/") ||
          value.contains("hubcloud.fans/re/")) {
        return 1;
      } else if (value.contains("pixeldrain.com") ||
          value.contains("pixeldrain.dev") ||
          value.contains("pixeldrain")) {
        return 2;
      } else {
        return 3;
      }
    }
  }

  /// Normalizes playback URL and encodes spaces/special characters
  String? _validatePlaybackUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != "https" || uri.host.isEmpty) return null;

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();

    if (host == "localhost" ||
        host.endsWith(".local") ||
        path.endsWith(".zip") ||
        path.contains("login.php") ||
        path.contains("logout") ||
        host.contains("greenmotors.") ||
        host.contains("greenmountmotors.")) {
      return null;
    }

    return uri.toString();
  }

  /// Extract PixelDrain URLs from page HTML text
  List<String> _extractPixelDrainUrls(String html) {
    final List<String> urls = [];
    final regExp = RegExp(
      r'https://pixeldrain\.(?:com|dev)/(?:u|api/file)/([a-zA-Z0-9_-]+)',
      caseSensitive: false,
    );

    final matches = regExp.allMatches(html);
    for (final match in matches) {
      final fileId = match.group(1);
      if (fileId != null && fileId.isNotEmpty) {
        final apiUrl = "https://pixeldrain.com/api/file/$fileId?download";
        if (!urls.contains(apiUrl)) {
          urls.add(apiUrl);
        }
      }
    }
    return urls;
  }

  /// Convert PixelDrain view URL to API download stream URL
  String? _transformPixelDrainUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.host.contains("pixeldrain.")) return null;

    String? fileId;
    if (uri.path.startsWith("/u/")) {
      fileId = uri.path.substring(3).replaceAll("/", "");
    } else if (uri.path.startsWith("/api/file/")) {
      fileId = uri.path.substring(10).replaceAll("/", "");
    }

    if (fileId != null && fileId.isNotEmpty) {
      return "https://${uri.host}/api/file/$fileId?download";
    }
    return null;
  }

  /// Probe stream URL with byte range check & fail-fast dead stream detection (MovieBox-TUI v0.1.21)
  Future<String?> _probeStreamUrl(String url, Map<String, String> headers) async {
    try {
      final req = http.Request("GET", Uri.parse(url));
      req.headers.addAll(headers);
      req.headers["Range"] = "bytes=0-8191";

      final streamedRes = await _client.send(req).timeout(const Duration(seconds: 8));

      if (streamedRes.statusCode == 200 || streamedRes.statusCode == 206) {
        final contentType = (streamedRes.headers['content-type'] ?? "").toLowerCase();
        final finalUrl = streamedRes.headers['location'] ?? url;

        // Follow link= wrapper if present
        if (contentType.contains("text/html") && finalUrl.contains("link=")) {
          final uri = Uri.tryParse(finalUrl);
          final wrapped = uri?.queryParameters['link'];
          if (wrapped != null && wrapped.startsWith("https://")) {
            return _probeStreamUrl(wrapped, headers);
          }
          return null;
        }

        // If response is HTML or plain text, inspect body for expired mirror error markers
        if (contentType.contains("text/html") ||
            contentType.contains("text/plain") ||
            contentType.contains("application/json") ||
            contentType.contains("application/zip")) {
          final bodyBytes = await streamedRes.stream.toBytes();
          final bodyLower = utf8.decode(bodyBytes, allowMalformed: true).toLowerCase();

          if (bodyLower.contains("failed to extract link") ||
              bodyLower.contains("token expired") ||
              bodyLower.contains("file not found") ||
              bodyLower.contains("404 not found") ||
              bodyLower.contains("link has expired") ||
              bodyLower.contains("expired") ||
              bodyLower.contains("access denied") ||
              bodyLower.contains("downloadquotaexceeded") ||
              bodyLower.contains("generate link again")) {
            print("4KHDHub preflight rejected dead/expired stream: $url");
            return null;
          }

          if (contentType.contains("application/zip")) {
            return null;
          }
        }

        return url;
      }
    } catch (e) {
      print("Probe error for $url: $e");
    }
    return null;
  }

  // --- Regex & Parsing Helpers ---

  String? _extractFourDigitYear(String text) {
    final match = RegExp(r'\b(19\d{2}|20\d{2})\b').firstMatch(text);
    return match?.group(1);
  }

  int? _parseSeasonCount(String text) {
    final matches = RegExp(r'S(\d+)', caseSensitive: false).allMatches(text);
    int maxSeason = 0;
    for (final m in matches) {
      final s = int.tryParse(m.group(1) ?? '0') ?? 0;
      if (s > maxSeason) maxSeason = s;
    }
    return maxSeason > 0 ? maxSeason : null;
  }

  List<int>? _parseSeasonEpisode(String text) {
    final match = RegExp(r'S(\d+)\s*E(\d+)', caseSensitive: false).firstMatch(text);
    if (match != null) {
      final s = int.tryParse(match.group(1) ?? '0') ?? 0;
      final e = int.tryParse(match.group(2) ?? '0') ?? 0;
      if (s > 0 && e > 0) {
        return [s, e];
      }
    }
    return null;
  }

  String _stripTrailingYear(String text) {
    final trimmed = text.trim();
    final regExp = RegExp(r'\s*\((19\d{2}|20\d{2})\)\s*$');
    return trimmed.replaceAll(regExp, '').trim();
  }

  String? _findMetadata(html_dom.Document doc, String prefix) {
    for (final el in doc.querySelectorAll("p, span, div, li")) {
      final text = el.text.trim();
      if (text.startsWith(prefix)) {
        return text.substring(prefix.length).trim();
      }
    }
    return null;
  }

  bool _isGenre(String val) {
    final lower = val.toLowerCase();
    const validGenres = [
      "action", "adventure", "animation", "comedy", "crime", "documentary",
      "drama", "family", "fantasy", "history", "horror", "music", "mystery",
      "romance", "science fiction", "sci-fi", "thriller", "war", "western"
    ];
    return validGenres.contains(lower);
  }

  bool _isArchive(String val) {
    final lower = val.toLowerCase();
    return lower.endsWith(".zip") || lower.contains("complete season") || lower.contains("season pack");
  }

  static String? detectQuality(String text) {
    final lower = text.toLowerCase();
    if (lower.contains("2160p") || lower.contains("2160") || lower.contains("4k") || lower.contains("uhd")) {
      return "2160p";
    } else if (lower.contains("1080p") || lower.contains("1080") || lower.contains("fhd")) {
      return "1080p";
    } else if (lower.contains("720p") || lower.contains("720") || lower.contains("hd")) {
      return "720p";
    } else if (lower.contains("480p") || lower.contains("480") || lower.contains("sd")) {
      return "480p";
    }
    return null;
  }

  String? _detectQuality(String text) => detectQuality(text);

  String? _detectCodec(String text) {
    final lower = text.toLowerCase();
    if (lower.contains("av1")) return "AV1";
    if (lower.contains("h.265") || lower.contains("h265") || lower.contains("x265")) return "H.265";
    if (lower.contains("hevc")) return "HEVC";
    if (lower.contains("h.264") || lower.contains("h264") || lower.contains("x264")) return "H.264";
    if (lower.contains("remux")) return "REMUX";
    return null;
  }
}

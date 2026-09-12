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

      return {
        "list": releases,
      };
    } catch (e) {
      print("4KHDHub Resources Error: $e");
      rethrow;
    }
  }

  /// Resolve HubDrive / HubCloud / PixelDrain release mirror to a playable direct video URL
  Future<Map<String, dynamic>?> resolveRelease(Map<String, dynamic> resourceItem) async {
    final List<dynamic> mirrors = resourceItem["mirrors"] ?? [];
    if (mirrors.isEmpty) return null;

    String? lastError;

    for (final mirror in mirrors) {
      final String resolverUrl = mirror["resolverUrl"] ?? "";
      if (resolverUrl.isEmpty) continue;

      try {
        List<Map<String, String>> candidates = [];

        if (resolverUrl.contains("hubcloud.")) {
          candidates = await _resolveHubCloud(resolverUrl);
        } else if (resolverUrl.contains("hubdrive.")) {
          candidates = await _resolveHubDrive(resolverUrl);
        } else {
          candidates = [
            {"url": resolverUrl, "label": mirror["label"] ?? "Direct"}
          ];
        }

        for (final candidate in candidates) {
          final url = candidate["url"]!;
          final label = candidate["label"]!;

          final Map<String, String> streamHeaders = {
            "User-Agent": BROWSER_UA,
            "Referer": baseUrl,
          };

          // Preflight stream probe
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
      } catch (e) {
        print("Mirror resolution failed for $resolverUrl: $e");
        lastError = e.toString();
      }
    }

    throw Exception(lastError ?? "No playable stream mirror found on 4KHDHub");
  }

  /// Resolve HubDrive link -> returns HubCloud link candidates
  Future<List<Map<String, String>>> _resolveHubDrive(String driveUrl) async {
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
        return _resolveHubCloud(href);
      }
    }
    throw Exception("HubDrive HubCloud mirror missing");
  }

  /// Resolve HubCloud link -> returns direct candidates (PixelDrain / CDN)
  Future<List<Map<String, String>>> _resolveHubCloud(String hubCloudUrl) async {
    final driveRes = await _client
        .get(Uri.parse(hubCloudUrl), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (driveRes.statusCode != 200) {
      throw Exception("HubCloud drive page status ${driveRes.statusCode}");
    }

    final driveDoc = html_parser.parse(driveRes.body);
    final downloadAnchor = driveDoc.querySelector("a#download");
    final resolverUrl = downloadAnchor?.attributes['href'];

    if (resolverUrl == null || !resolverUrl.startsWith("https://")) {
      throw Exception("HubCloud resolver link missing");
    }

    final resolverRes = await _client
        .get(Uri.parse(resolverUrl), headers: _headers)
        .timeout(const Duration(seconds: 10));

    if (resolverRes.statusCode != 200) {
      throw Exception("HubCloud resolver status ${resolverRes.statusCode}");
    }

    final htmlBody = resolverRes.body;
    final List<Map<String, String>> candidates = [];

    // Extract PixelDrain URLs from script / text
    final pixelDrainUrls = _extractPixelDrainUrls(htmlBody);
    for (final pUrl in pixelDrainUrls) {
      candidates.add({
        "url": pUrl,
        "label": "PixelDrain",
      });
    }

    // Extract anchor links
    final resolverDoc = html_parser.parse(htmlBody);
    final linkEls = resolverDoc.querySelectorAll("a[href]");
    for (final link in linkEls) {
      final href = link.attributes['href'] ?? "";
      final label = link.text.trim();

      if (href.startsWith("https://") &&
          !href.endsWith(".zip") &&
          !href.contains("login") &&
          !href.contains("logout")) {
        final pApiUrl = _transformPixelDrainUrl(href) ?? href;
        if (!candidates.any((c) => c["url"] == pApiUrl)) {
          candidates.add({
            "url": pApiUrl,
            "label": label.isNotEmpty ? label : "Direct CDN",
          });
        }
      }
    }

    if (candidates.isEmpty) {
      throw Exception("No stream candidates found in HubCloud resolver");
    }

    return candidates;
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

  /// Probe stream URL with byte range check
  Future<String?> _probeStreamUrl(String url, Map<String, String> headers) async {
    try {
      final req = http.Request("GET", Uri.parse(url));
      req.headers.addAll(headers);
      req.headers["Range"] = "bytes=0-";

      final streamedRes = await _client.send(req).timeout(const Duration(seconds: 8));

      if (streamedRes.statusCode == 200 || streamedRes.statusCode == 206) {
        final contentType = streamedRes.headers['content-type'] ?? "";
        final finalUrl = streamedRes.headers['location'] ?? url;

        if (contentType.contains("text/html") && finalUrl.contains("link=")) {
          final uri = Uri.tryParse(finalUrl);
          final wrapped = uri?.queryParameters['link'];
          if (wrapped != null && wrapped.startsWith("https://")) {
            return _probeStreamUrl(wrapped, headers);
          }
          return null;
        }

        if (!contentType.contains("text/html") && !contentType.contains("application/zip")) {
          return url;
        }
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

  String? _detectQuality(String text) {
    for (final q in ["2160p", "1080p", "720p", "480p"]) {
      if (text.toLowerCase().contains(q)) return q;
    }
    return null;
  }

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

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

class FourKHdHubService {
  static const String defaultBaseUrl = 'https://4khdhub.one/';
  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  final http.Client _client;
  final String _baseUrl;

  FourKHdHubService({http.Client? client, String? baseUrl})
      : _client = client ?? http.Client(),
        _baseUrl = (baseUrl ?? defaultBaseUrl).endsWith('/')
            ? (baseUrl ?? defaultBaseUrl)
            : '${baseUrl ?? defaultBaseUrl}/';

  Map<String, String> get _headers => {
        'User-Agent': browserUserAgent,
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
      };

  /// Search movies and series on 4KHDHub
  Future<List<Map<String, dynamic>>> search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final url = Uri.parse(_baseUrl).replace(queryParameters: {'s': cleanQuery});
    try {
      final response = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return [];

      final document = html_parser.parse(response.body);
      final cards = document.querySelectorAll('a.movie-card');
      final List<Map<String, dynamic>> results = [];

      for (final card in cards) {
        final href = card.attributes['href'] ?? '';
        if (href.isEmpty) continue;

        final titleEl = card.querySelector('.movie-card-title');
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final metaEl = card.querySelector('.movie-card-meta');
        final metaText = metaEl?.text.trim() ?? '';
        final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(metaText);
        final year = yearMatch != null ? int.tryParse(yearMatch.group(1)!) : null;

        final imgEl = card.querySelector('img');
        final posterUrl = imgEl?.attributes['src'] ?? '';

        final isTv = href.contains('-series-');
        
        // Extract quality badges like 4K, HDR, 1080p
        final formatEls = card.querySelectorAll('.movie-card-format, .quality-badge');
        final formats = formatEls.map((e) => e.text.trim()).where((s) => s.isNotEmpty).toSet().toList();

        results.add({
          'id': href,
          'subjectId': href,
          'title': title,
          'subjectTitle': title,
          'year': year,
          'cover': {'url': posterUrl},
          'coverUrl': posterUrl,
          'subjectType': isTv ? 2 : 1,
          'provider': '4khdhub',
          'formats': formats,
          'is4k': formats.any((f) => f.contains('4K') || f.contains('2160')),
        });
      }

      return results;
    } catch (e) {
      print("4KHDHub search error: $e");
      return [];
    }
  }

  /// Get movie or series details
  Future<Map<String, dynamic>> getDetails(String pathId) async {
    final cleanPath = pathId.replaceAll(RegExp(r'^/+'), '');
    final url = Uri.parse(_baseUrl).resolve(cleanPath);

    try {
      final response = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception("Failed to load 4KHDHub details (${response.statusCode})");
      }

      final document = html_parser.parse(response.body);

      // Extract Title
      final h1 = document.querySelector('h1');
      String rawTitle = h1?.text.trim() ?? '';
      if (rawTitle.isEmpty) {
        final ogTitle = document.querySelector('meta[property="og:title"]')?.attributes['content'];
        rawTitle = ogTitle?.trim() ?? cleanPath;
      }
      // Remove trailing year if present in parentheses e.g. "Avatar (2009)" -> "Avatar"
      final title = rawTitle.replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '').trim();

      final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(rawTitle);
      final year = yearMatch != null ? int.tryParse(yearMatch.group(1)!) : null;

      final isTv = cleanPath.contains('-series-');

      // Description & Tagline
      final descEl = document.querySelector('.content-section p.mt-4') ??
          document.querySelector('meta[name="description"]');
      final description = descEl is dom.Element && descEl.localName == 'meta'
          ? descEl.attributes['content']?.trim() ?? ''
          : descEl?.text.trim() ?? '';

      final tagline = document.querySelector('.movie-tagline')?.text.trim() ?? '';
      final imdbRating = document.querySelector('.imdb-score')?.text.trim() ?? '';

      // Poster & Backdrop
      final ogImage = document.querySelector('meta[property="og:image"]')?.attributes['content'];
      final posterUrl = ogImage ?? '';

      // Genres
      final genreEls = document.querySelectorAll('.badge-outline a');
      final genres = genreEls.map((e) => e.text.trim()).where((s) => s.isNotEmpty).toList();

      // Metadata items (Director, Stars, Audios, Prints)
      final metadataItems = document.querySelectorAll('.metadata-item');
      String? director;
      String? stars;
      String? audios;
      String? prints;

      for (final item in metadataItems) {
        final label = item.querySelector('.metadata-label')?.text.trim() ?? '';
        final value = item.querySelector('.metadata-value')?.text.trim() ?? '';
        if (label.startsWith('Director')) director = value;
        if (label.startsWith('Stars')) stars = value;
        if (label.startsWith('Audios')) audios = value;
        if (label.startsWith('Prints') || label.startsWith('Print')) prints = value;
      }

      // Parse Seasons if Series
      List<Map<String, dynamic>> seasons = [];
      if (isTv) {
        seasons = _parseSeasons(document);
      }

      return {
        'id': pathId,
        'subjectId': pathId,
        'title': title,
        'subjectTitle': title,
        'year': year,
        'description': description,
        'tagline': tagline,
        'imdbRating': imdbRating,
        'cover': {'url': posterUrl},
        'coverUrl': posterUrl,
        'subjectType': isTv ? 2 : 1,
        'genres': genres,
        'director': director,
        'stars': stars,
        'audios': audios,
        'prints': prints,
        'seasons': seasons,
        'provider': '4khdhub',
        'rawHtml': response.body,
      };
    } catch (e) {
      print("4KHDHub getDetails error: $e");
      rethrow;
    }
  }

  /// Parse seasons and episode counts for a TV series
  List<Map<String, dynamic>> _parseSeasons(dom.Document document) {
    final episodeItems = document.querySelectorAll('#episodes .episode-download-item, .episode-file-title');
    final Map<int, int> seasonEpisodes = {};

    for (final item in episodeItems) {
      final text = item.text.trim().toUpperCase();
      final match = RegExp(r'S(\d+)E(\d+)').firstMatch(text);
      if (match != null) {
        final sNum = int.tryParse(match.group(1)!) ?? 1;
        final epNum = int.tryParse(match.group(2)!) ?? 1;
        final currentMax = seasonEpisodes[sNum] ?? 0;
        if (epNum > currentMax) {
          seasonEpisodes[sNum] = epNum;
        }
      }
    }

    if (seasonEpisodes.isEmpty) {
      return [
        {'se': 1, 'maxEp': 1}
      ];
    }

    final sortedKeys = seasonEpisodes.keys.toList()..sort();
    return sortedKeys.map((sNum) {
      return {
        'se': sNum,
        'maxEp': seasonEpisodes[sNum] ?? 1,
      };
    }).toList();
  }

  /// Get releases (download streams) for a movie or TV episode
  Future<List<Map<String, dynamic>>> getReleases(
    String pathId, {
    String? rawHtml,
    int season = 0,
    int episode = 0,
  }) async {
    dom.Document document;
    if (rawHtml != null && rawHtml.isNotEmpty) {
      document = html_parser.parse(rawHtml);
    } else {
      final cleanPath = pathId.replaceAll(RegExp(r'^/+'), '');
      final url = Uri.parse(_baseUrl).resolve(cleanPath);
      final response = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      document = html_parser.parse(response.body);
    }

    final isTv = season > 0;
    final itemSelector = isTv ? '#episodes .episode-download-item' : '.download-item';
    final titleSelector = isTv ? '.episode-file-title' : '.file-title';

    final items = document.querySelectorAll(itemSelector);
    final List<Map<String, dynamic>> releases = [];

    for (final item in items) {
      final titleEl = item.querySelector(titleSelector);
      final filename = titleEl?.text.trim() ?? '';
      if (filename.isEmpty || filename.toLowerCase().endsWith('.zip') || filename.toLowerCase().endsWith('.rar')) {
        continue;
      }

      // If series, check if it matches target season and episode
      if (isTv) {
        final match = RegExp(r'S(\d+)E(\d+)', caseSensitive: false).firstMatch(filename);
        if (match != null) {
          final s = int.tryParse(match.group(1)!) ?? 0;
          final ep = int.tryParse(match.group(2)!) ?? 0;
          if (s != season || ep != episode) {
            continue;
          }
        }
      }

      // Extract mirror links
      final linkEls = item.querySelectorAll('a[href]');
      final List<Map<String, String>> mirrors = [];
      for (final l in linkEls) {
        final href = l.attributes['href'] ?? '';
        if (!href.startsWith('https://') || href.contains('logout')) continue;
        final label = l.text.trim().isEmpty ? 'HubCloud' : l.text.trim();
        mirrors.add({'label': label, 'url': href});
      }
      if (mirrors.isEmpty) continue;

      // Extract size
      final sizeEl = item.querySelector('.badge-size, .badge');
      final sizeText = sizeEl?.text.trim() ?? '';

      // Detect Quality & Codec
      final quality = _detectQuality(filename);
      final codec = _detectCodec(filename);
      final resNumber = _extractResolutionNumber(quality);

      releases.add({
        'filename': filename,
        'quality': quality,
        'resolution': resNumber,
        'codecName': codec,
        'size': sizeText,
        'mirrors': mirrors,
        'provider': '4khdhub',
        'season': season,
        'episode': episode,
      });
    }

    // Sort releases: 4K/2160p first, then 1080p, then 720p; REMUX before WEB-DL
    releases.sort((a, b) {
      final resComp = (b['resolution'] as int? ?? 0).compareTo(a['resolution'] as int? ?? 0);
      if (resComp != 0) return resComp;

      final codecA = (a['codecName'] ?? '').toString().toUpperCase();
      final codecB = (b['codecName'] ?? '').toString().toUpperCase();
      if (codecA.contains('REMUX') && !codecB.contains('REMUX')) return -1;
      if (!codecA.contains('REMUX') && codecB.contains('REMUX')) return 1;

      return 0;
    });

    return releases;
  }

  /// Resolve a release mirror to a high-speed playable direct video stream URL
  Future<String?> resolveReleaseStream(Map<String, dynamic> release) async {
    final mirrors = (release['mirrors'] as List<dynamic>?) ?? [];
    if (mirrors.isEmpty) return null;

    for (final m in mirrors) {
      final url = m['url']?.toString() ?? '';
      if (url.isEmpty) continue;

      try {
        final resolved = await _resolveHubCloud(url);
        if (resolved != null && resolved.isNotEmpty) {
          // Preflight probe to ensure CDN stream is alive
          final isValid = await _preflightProbe(resolved);
          if (isValid) {
            return resolved;
          }
        }
      } catch (e) {
        print("Error resolving mirror $url: $e");
      }
    }

    return null;
  }

  /// Resolve HubCloud drive page or shortener (greenmotors.cc)
  Future<String?> _resolveHubCloud(String driveUrl) async {
    try {
      String currentUrl = driveUrl;

      // 1. If URL is an ad-shortener / mediator (e.g. greenmotors.cc), bypass it first
      if (_isShortenerUrl(currentUrl)) {
        final bypassed = await _bypassShortener(currentUrl);
        if (bypassed != null && bypassed.isNotEmpty) {
          currentUrl = bypassed;
        }
      }

      final response = await _client.get(
        Uri.parse(currentUrl),
        headers: {
          ..._headers,
          'Referer': _baseUrl,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      // 2. If the response HTML contains the obfuscated shortener token s('o', ...), decode it
      if (response.body.contains("s('o'") || response.body.contains('s("o"')) {
        final bypassed = _extractAndDecodeShortener(response.body);
        if (bypassed != null && bypassed.isNotEmpty && bypassed != currentUrl) {
          return _resolveHubCloud(bypassed);
        }
      }

      final doc = html_parser.parse(response.body);
      final downloadBtn = doc.querySelector(
        "a#download, a.btn-primary, a.btn-success, a.btn[href*='/download/'], a[href*='/download/'], a[href*='gamerxyt.com'], a[href*='hubcloud.php']",
      );

      String? resolverUrl = downloadBtn?.attributes['href'];
      if (resolverUrl == null || resolverUrl.isEmpty) {
        // Fallback: check any <a> tag pointing to gamerxyt or hubcloud.php
        final altLink = doc.querySelector("a[href*='gamerxyt.com'], a[href*='hubcloud.php']");
        resolverUrl = altLink?.attributes['href'];
      }

      if (resolverUrl == null || resolverUrl.isEmpty) return null;

      return await _resolveGamerxyt(resolverUrl, currentUrl);
    } catch (e) {
      print("HubCloud resolver error: $e");
      return null;
    }
  }

  /// Checks if URL belongs to an intermediary shortener
  bool _isShortenerUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('greenmotors') ||
        lower.contains('homelander') ||
        lower.contains('bonus') ||
        (!lower.contains('hubcloud') && !lower.contains('drive') && lower.contains('?id='));
  }

  /// Bypass shortener by fetching the page and decoding its obfuscated payload
  Future<String?> _bypassShortener(String shortenerUrl) async {
    try {
      final response = await _client.get(
        Uri.parse(shortenerUrl),
        headers: {
          ..._headers,
          'Referer': _baseUrl,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      return _extractAndDecodeShortener(response.body);
    } catch (e) {
      print("Shortener bypass fetch error for $shortenerUrl: $e");
      return null;
    }
  }

  /// Extracts and decodes token from body e.g. `s('o', '<base64>', ...)`
  String? _extractAndDecodeShortener(String body) {
    try {
      final match = RegExp(r"""s\(\s*['"]o['"]\s*,\s*['"]([^'"]+)['"]""").firstMatch(body);
      if (match != null) {
        final token = match.group(1);
        if (token != null && token.isNotEmpty) {
          return _decodeGreenMotorsToken(token);
        }
      }
    } catch (e) {
      print("Error extracting shortener token: $e");
    }
    return null;
  }

  /// Decodes: Base64 -> Base64 -> ROT13 -> Base64 -> JSON -> Base64('o')
  String? _decodeGreenMotorsToken(String token) {
    try {
      // 1. Base64 decode
      final s1 = utf8.decode(base64.decode(token));
      // 2. Base64 decode
      final s2 = utf8.decode(base64.decode(s1));
      // 3. ROT13 decode
      final s3 = _rot13(s2);
      // 4. Base64 decode
      final s4 = utf8.decode(base64.decode(s3));
      // 5. JSON parse
      final Map<String, dynamic> data = jsonDecode(s4);
      final oVal = data['o']?.toString();
      if (oVal != null && oVal.isNotEmpty) {
        // 6. Base64 decode the destination HubCloud URL
        return utf8.decode(base64.decode(oVal));
      }
    } catch (e) {
      print("Error decoding greenmotors token: $e");
    }
    return null;
  }

  /// ROT13 cipher implementation
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

  /// Resolve Gamerxyt / HubCloud download page
  Future<String?> _resolveGamerxyt(String resolverUrl, String referer) async {
    try {
      final response = await _client.get(
        Uri.parse(resolverUrl),
        headers: {
          ..._headers,
          'Referer': referer,
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final html = response.body;
      final doc = html_parser.parse(html);
      final links = doc.querySelectorAll('a[href]');

      final List<String> candidateUrls = [];

      for (final a in links) {
        final href = a.attributes['href'] ?? '';
        if (!href.startsWith('https://')) continue;

        // Pixel HubCloud redirect link e.g. https://pixel.hubcloud.cx/?id=... or pixel.hubcloud.ist/?id=...
        if (href.contains('pixel.hubcloud.') || href.contains('pixel.')) {
          final directRedirect = await _resolvePixelHubCloudRedirect(href);
          if (directRedirect != null) {
            candidateUrls.add(directRedirect);
          }
        } else if (href.contains('pixeldrain.com/u/') || href.contains('pixeldrain.dev/u/')) {
          final pId = _extractPixeldrainId(href);
          if (pId != null) {
            candidateUrls.add('https://pixeldrain.com/api/file/$pId?download');
          }
        } else if (href.contains('workers.dev') ||
            href.contains('snvhost.') ||
            href.contains('storage.googleapis.com') ||
            href.contains('cloudflarestorage.com') ||
            href.contains('r2.')) {
          candidateUrls.add(href);
        }
      }

      // Sort candidate URLs by reliability score
      candidateUrls.sort((a, b) => _scoreMirror(a).compareTo(_scoreMirror(b)));

      for (final cand in candidateUrls) {
        final ok = await _preflightProbe(cand);
        if (ok) return cand;
      }

      return null;
    } catch (e) {
      print("Gamerxyt resolve error: $e");
      return null;
    }
  }

  /// Resolves pixel redirect link (following intermediate 302 redirects) to direct video CDN URL
  Future<String?> _resolvePixelHubCloudRedirect(String pixelUrl) async {
    try {
      String targetUrl = pixelUrl;
      for (int i = 0; i < 5; i++) {
        final request = http.Request('GET', Uri.parse(targetUrl))
          ..headers.addAll(_headers)
          ..followRedirects = false;

        final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 8));
        final statusCode = streamedResponse.statusCode;
        final location = streamedResponse.headers['location'];

        // Check if query parameter has link=
        final uriToCheck = location != null ? Uri.tryParse(location) : Uri.tryParse(targetUrl);
        if (uriToCheck != null) {
          final linkParam = uriToCheck.queryParameters['link'];
          if (linkParam != null && linkParam.startsWith('https://')) {
            return linkParam;
          }
        }

        if (statusCode >= 300 && statusCode < 400 && location != null && location.isNotEmpty) {
          targetUrl = location;
          if (targetUrl.startsWith('https://video-downloads.googleusercontent.com') ||
              targetUrl.contains('storage.googleapis.com') ||
              targetUrl.contains('cloudflarestorage.com')) {
            return targetUrl;
          }
          continue;
        }

        final finalUri = Uri.parse(targetUrl);
        final linkParam = finalUri.queryParameters['link'];
        if (linkParam != null && linkParam.startsWith('https://')) {
          return linkParam;
        }

        if (targetUrl.startsWith('https://video-downloads.googleusercontent.com') ||
            targetUrl.contains('storage.googleapis.com') ||
            targetUrl.contains('cloudflarestorage.com')) {
          return targetUrl;
        }

        break;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Preflight probe HTTP Range bytes=0-8191 to verify the CDN video stream is accessible
  Future<bool> _preflightProbe(String streamUrl) async {
    try {
      final request = http.Request('GET', Uri.parse(streamUrl))
        ..headers.addAll({
          ..._headers,
          'Range': 'bytes=0-8191',
        })
        ..followRedirects = true
        ..maxRedirects = 5;

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 6));
      final statusCode = streamedResponse.statusCode;
      if (statusCode != 200 && statusCode != 206) {
        return false;
      }

      final contentType = (streamedResponse.headers['content-type'] ?? '').toLowerCase();
      if (contentType.contains('text/html') || contentType.contains('application/json')) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  int _scoreMirror(String url) {
    final lower = url.toLowerCase();
    // Prioritize high-speed CDNs that support HTTP Range (206 Partial Content) for seeking/forwarding
    if (lower.contains('workers.dev') ||
        lower.contains('cloudflarestorage.com') ||
        lower.contains('r2.') ||
        lower.contains('snvhost.') ||
        lower.contains('pixeldrain.com')) {
      return 0;
    }
    if (lower.contains('storage.googleapis.com') || lower.contains('hubcloud.cx/re/')) {
      return 1;
    }
    // googleusercontent download server does not support HTTP Range requests
    if (lower.contains('googleusercontent.com')) {
      return 2;
    }
    return 3;
  }

  String? _extractPixeldrainId(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final segs = uri.pathSegments;
    if (segs.length >= 2 && (segs[0] == 'u' || segs[0] == 'file')) {
      return segs[1];
    }
    return null;
  }

  String _detectQuality(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('2160p') || lower.contains('4k') || lower.contains('uhd')) return '2160p 4K UHD';
    if (lower.contains('1080p') || lower.contains('fhd')) return '1080p Full HD';
    if (lower.contains('720p') || lower.contains('hd')) return '720p HD';
    if (lower.contains('480p') || lower.contains('sd')) return '480p SD';
    return 'HD';
  }

  int _extractResolutionNumber(String quality) {
    if (quality.contains('2160')) return 2160;
    if (quality.contains('1080')) return 1080;
    if (quality.contains('720')) return 720;
    if (quality.contains('480')) return 480;
    return 720;
  }

  String _detectCodec(String filename) {
    final lower = filename.toLowerCase();
    if (lower.contains('remux')) return 'REMUX';
    if (lower.contains('hevc') || lower.contains('h265') || lower.contains('h.265') || lower.contains('x265')) {
      return 'HEVC (H.265)';
    }
    if (lower.contains('av1')) return 'AV1';
    if (lower.contains('h264') || lower.contains('h.264') || lower.contains('x264') || lower.contains('avc')) {
      return 'AVC (H.264)';
    }
    return 'MP4/MKV';
  }
}

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'safe_http_client.dart';
import 'remote_config_service.dart';

class DracinSiApiService {
  static final DracinSiApiService _instance = DracinSiApiService._internal();
  factory DracinSiApiService() => _instance;
  DracinSiApiService._internal();

  String get _baseUrl {
    var url = RemoteConfigService.instance.dracinsiBaseUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  String _resolvePageUrl(String subjectId) {
    var s = subjectId.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return s;
    }
    if (s.startsWith('dracinsi_')) {
      s = s.substring('dracinsi_'.length);
    }
    if (s.startsWith('drama_')) {
      s = 'drama/${s.substring(6)}';
    }
    if (!s.startsWith('/')) {
      s = '/$s';
    }
    if (!s.endsWith('/')) {
      s = '$s/';
    }
    return '$_baseUrl$s';
  }

  String _createSubjectId(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (segments.isEmpty) return 'dracinsi_unknown';
      if (segments.contains('drama')) {
        return 'dracinsi_drama_${segments.last}';
      }
      return 'dracinsi_${segments.last}';
    } catch (_) {
      return 'dracinsi_${url.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    }
  }

  /// Search chinese drama catalog
  Future<List<Map<String, dynamic>>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final searchUrl = page > 1
          ? '$_baseUrl/page/$page/?s=${Uri.encodeComponent(cleanQuery)}'
          : '$_baseUrl/?s=${Uri.encodeComponent(cleanQuery)}';

      final res = await SafeHttpClient.get(
        Uri.parse(searchUrl),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) return [];

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final entries = doc.querySelectorAll('article.animposx, .animepost, .relat article, .bsx, .post-item, .film-item');

      for (final art in entries) {
        final linkEl = art.querySelector('a');
        final pageLink = linkEl?.attributes['href'] ?? '';
        final titleEl = art.querySelector('.title, .entry-title, .tt, h2, h3') ?? linkEl;
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty || pageLink.isEmpty) continue;

        final imgEl = art.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final scoreEl = art.querySelector('.rating, .score');
        final score = scoreEl?.text.trim() ?? '';

        final typeEl = art.querySelector('.typez, .type');
        final typeStr = typeEl?.text.trim() ?? 'Dracin';

        items.add({
          'subjectId': _createSubjectId(pageLink),
          'subjectTitle': title,
          'title': title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': pageLink,
          'rating': score,
          'quality': typeStr,
          'subjectType': 2,
          'media_type': 'tv',
          'provider': 'dracinsi',
        });
      }

      return items;
    } catch (e) {
      debugPrint('DracinSiApiService.search error: $e');
      return [];
    }
  }

  /// Get Homepage items (Latest Dracin)
  Future<Map<String, dynamic>> getHomepage({int page = 1}) async {
    try {
      final url = page > 1
          ? '$_baseUrl/page/$page/'
          : '$_baseUrl/';

      final res = await SafeHttpClient.get(
        Uri.parse(url),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        return {'code': 0, 'list': [], 'items': []};
      }

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final entries = doc.querySelectorAll('.listupd article, .animposx, .bsx, .post-item, .film-item');

      for (final el in entries) {
        final linkEl = el.querySelector('a');
        final pageLink = linkEl?.attributes['href'] ?? '';
        final titleEl = el.querySelector('.tt, .entry-title, .title, h2, h3') ?? linkEl;
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty || pageLink.isEmpty) continue;

        final imgEl = el.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final epEl = el.querySelector('.epx, .bt .ep, .episode');
        final epText = epEl?.text.trim() ?? '';

        items.add({
          'subjectId': _createSubjectId(pageLink),
          'subjectTitle': title,
          'title': title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': pageLink,
          'quality': epText,
          'subjectType': 2,
          'media_type': 'tv',
          'provider': 'dracinsi',
        });
      }

      return {
        'code': 0,
        'list': items,
        'items': items,
        'data': {'list': items},
      };
    } catch (e) {
      debugPrint('DracinSiApiService.getHomepage error: $e');
      return {'code': 0, 'list': [], 'items': []};
    }
  }

  /// Get Details of Drama or Episode
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    final pageUrl = _resolvePageUrl(subjectId);
    try {
      final res = await SafeHttpClient.get(
        Uri.parse(pageUrl),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        return {'subjectId': subjectId, 'title': 'Unknown', 'episodes': []};
      }

      final doc = html_parser.parse(res.body);

      final titleEl = doc.querySelector('h1.entry-title, .infox h1, h1');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = doc.querySelector('.thumb img, .infox img, .entry-content img, .poster img');
      var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
      if (cover.startsWith('//')) cover = 'https:$cover';

      final descEl = doc.querySelector('.entry-content, .sinopsis, .desc');
      final description = descEl?.text.trim() ?? '';

      final ratingEl = doc.querySelector('.rating strong, .score');
      final rating = ratingEl?.text.trim() ?? '';

      final episodes = <Map<String, dynamic>>[];
      final epLinks = doc.querySelectorAll('.eplist ul li a, .episodelist ul li a, .listeps ul li a, .episodes a');

      for (var i = 0; i < epLinks.length; i++) {
        final a = epLinks[i];
        final href = a.attributes['href'] ?? '';
        final text = a.text.trim();
        if (href.isEmpty) continue;

        final epNumMatch = RegExp(r'(?:episode|eps|ep)\.?\s*(\d+)', caseSensitive: false).firstMatch(text) ??
            RegExp(r'(\d+)').firstMatch(text);
        final epNum = epNumMatch != null ? int.tryParse(epNumMatch.group(1)!) ?? (i + 1) : (i + 1);

        episodes.add({
          'episodeId': _createSubjectId(href),
          'episodeNumber': epNum,
          'title': text.isNotEmpty ? text : 'Episode $epNum',
          'url': href,
        });
      }

      if (episodes.isEmpty && (pageUrl.contains('-episode-') || pageUrl.contains('/episode/'))) {
        episodes.add({
          'episodeId': subjectId,
          'episodeNumber': 1,
          'title': title,
          'url': pageUrl,
        });
      }

      return {
        'subjectId': subjectId,
        'subjectTitle': title,
        'title': title,
        'description': description,
        'cover': cover,
        'coverUrl': cover,
        'poster_path': cover,
        'backdrop_path': cover,
        'rating': rating,
        'subjectType': 2,
        'media_type': 'tv',
        'provider': 'dracinsi',
        'pageUrl': pageUrl,
        'episodes': episodes,
      };
    } catch (e) {
      debugPrint('DracinSiApiService.getDetails error: $e');
      return {'subjectId': subjectId, 'title': 'Error', 'episodes': []};
    }
  }

  /// Get Season info
  Future<Map<String, dynamic>> getSeasonInfo({required String subjectId}) async {
    final details = await getDetails(subjectId: subjectId);
    final episodes = details['episodes'] as List? ?? [];
    return {
      'seasons': [
        {
          'seasonNumber': 1,
          'season_number': 1,
          'name': 'Season 1',
          'episode_count': episodes.length,
          'episodes': episodes,
        }
      ]
    };
  }

  /// Get stream resources for episode
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
  }) async {
    try {
      String targetUrl = _resolvePageUrl(subjectId);

      if (ep > 0 || targetUrl.contains('/drama/')) {
        final details = await getDetails(subjectId: subjectId);
        final episodes = details['episodes'] as List? ?? [];
        if (episodes.isNotEmpty) {
          final matchedEp = episodes.firstWhere(
            (e) => (e['episodeNumber'] == ep),
            orElse: () => episodes.first,
          );
          if (matchedEp != null && matchedEp['url'] != null) {
            targetUrl = matchedEp['url'];
          }
        }
      }

      final pageRes = await SafeHttpClient.get(
        Uri.parse(targetUrl),
        headers: _defaultHeaders,
      );

      if (pageRes.statusCode != 200) {
        return {'streams': []};
      }

      final streams = <Map<String, dynamic>>[];
      final doc = html_parser.parse(pageRes.body);

      // 1. Direct <video><source> or <video src="...">
      final videoSources = doc.querySelectorAll('video source, video[src]');
      for (final vs in videoSources) {
        var src = vs.attributes['src'] ?? '';
        if (src.startsWith('//')) src = 'https:$src';
        if (src.isNotEmpty && src.startsWith('http')) {
          streams.add({
            'url': src,
            'quality': 'CDN MP4',
            'format': src.contains('.m3u8') ? 'm3u8' : 'mp4',
            'headers': {
              'Referer': '$_baseUrl/',
              'User-Agent': _defaultHeaders['User-Agent']!,
            },
          });
        }
      }

      // 2. Direct iframes
      final iframes = doc.querySelectorAll('iframe');
      for (final iframe in iframes) {
        var src = iframe.attributes['src'] ?? '';
        if (src.startsWith('//')) src = 'https:$src';
        if (src.isEmpty || !src.startsWith('http')) continue;

        streams.add({
          'url': src,
          'quality': 'Direct Embed',
          'format': src.contains('.m3u8') ? 'm3u8' : 'mp4',
          'headers': {
            'Referer': targetUrl,
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });
      }

      // 3. Match direct cdn urls in inline scripts
      final inlineScripts = doc.querySelectorAll('script').map((s) => s.text).join('\n');
      final cdnRegex = RegExp(r"""(https?://[^\s"'<>]+\.(?:mp4|m3u8)[^\s"'<>]*)""");
      for (final match in cdnRegex.allMatches(inlineScripts)) {
        final cdnUrl = match.group(1)!;
        if (!streams.any((s) => s['url'] == cdnUrl)) {
          streams.add({
            'url': cdnUrl,
            'quality': 'Direct Stream',
            'format': cdnUrl.contains('.m3u8') ? 'm3u8' : 'mp4',
            'headers': {
              'Referer': '$_baseUrl/',
              'User-Agent': _defaultHeaders['User-Agent']!,
            },
          });
        }
      }

      return {
        'streams': streams,
        'url': streams.isNotEmpty ? streams.first['url'] : '',
        'format': streams.isNotEmpty ? streams.first['format'] : 'mp4',
        'headers': streams.isNotEmpty ? streams.first['headers'] : {},
      };
    } catch (e) {
      debugPrint('DracinSiApiService.getResources error: $e');
      return {'streams': []};
    }
  }
}

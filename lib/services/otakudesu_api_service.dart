import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'safe_http_client.dart';
import 'remote_config_service.dart';

class OtakudesuApiService {
  static final OtakudesuApiService _instance = OtakudesuApiService._internal();
  factory OtakudesuApiService() => _instance;
  OtakudesuApiService._internal();

  String get _baseUrl {
    var url = RemoteConfigService.instance.otakudesuBaseUrl.trim();
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
    if (s.startsWith('otakudesu_')) {
      s = s.substring('otakudesu_'.length);
    }
    if (s.startsWith('anime_')) {
      s = 'anime/${s.substring(6)}';
    }
    if (s.startsWith('episode_')) {
      s = 'episode/${s.substring(8)}';
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
      if (segments.isEmpty) return 'otakudesu_unknown';
      if (segments.contains('anime')) {
        return 'otakudesu_anime_${segments.last}';
      }
      if (segments.contains('episode')) {
        return 'otakudesu_episode_${segments.last}';
      }
      return 'otakudesu_${segments.last}';
    } catch (_) {
      return 'otakudesu_${url.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    }
  }

  /// Search anime catalog
  Future<List<Map<String, dynamic>>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final searchUrl = '$_baseUrl/?s=${Uri.encodeComponent(cleanQuery)}&post_type=anime';
      final res = await SafeHttpClient.get(
        Uri.parse(searchUrl),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) return [];

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final entries = doc.querySelectorAll('ul.chivsrc li, .page li, .venz ul li');

      for (final el in entries) {
        final linkEl = el.querySelector('h2 a, a');
        final pageLink = linkEl?.attributes['href'] ?? '';
        final title = linkEl?.text.trim() ?? '';
        if (title.isEmpty || pageLink.isEmpty) continue;

        final imgEl = el.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final genres = el.querySelectorAll('.set a').map((g) => g.text.trim()).toList();
        final quality = el.querySelector('.set:contains("Status")')?.text.trim() ?? 'Anime';

        items.add({
          'subjectId': _createSubjectId(pageLink),
          'subjectTitle': title,
          'title': title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': pageLink,
          'genres': genres,
          'quality': quality,
          'subjectType': 2,
          'media_type': 'tv',
          'provider': 'otakudesu',
        });
      }

      return items;
    } catch (e) {
      debugPrint('OtakudesuApiService.search error: $e');
      return [];
    }
  }

  /// Get Homepage items (Ongoing anime / anime updates)
  Future<Map<String, dynamic>> getHomepage({int page = 1}) async {
    try {
      final url = page > 1
          ? '$_baseUrl/ongoing-anime/page/$page/'
          : '$_baseUrl/ongoing-anime/';

      final res = await SafeHttpClient.get(
        Uri.parse(url),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        return {'code': 0, 'list': [], 'items': []};
      }

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final entries = doc.querySelectorAll('.venz ul li, .rapi .venz li');

      for (final el in entries) {
        final linkEl = el.querySelector('a');
        final pageLink = linkEl?.attributes['href'] ?? '';
        final titleEl = el.querySelector('.jdlflm, h2') ?? linkEl;
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty || pageLink.isEmpty) continue;

        final imgEl = el.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final epEl = el.querySelector('.epz');
        final ep = epEl?.text.trim() ?? '';

        items.add({
          'subjectId': _createSubjectId(pageLink),
          'subjectTitle': title,
          'title': title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': pageLink,
          'quality': ep,
          'subjectType': 2,
          'media_type': 'tv',
          'provider': 'otakudesu',
        });
      }

      return {
        'code': 0,
        'list': items,
        'items': items,
        'data': {'list': items},
      };
    } catch (e) {
      debugPrint('OtakudesuApiService.getHomepage error: $e');
      return {'code': 0, 'list': [], 'items': []};
    }
  }

  /// Get Details of Anime or Episode
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

      final titleEl = doc.querySelector('.infozingle h2, .jdlhdr, h1');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = doc.querySelector('.fotoanime img, .cukder img');
      var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
      if (cover.startsWith('//')) cover = 'https:$cover';

      final descEl = doc.querySelector('.sinopc, .sinopsis');
      final description = descEl?.text.trim() ?? '';

      final scoreEl = doc.querySelector('.infozingle span:contains("Skor"), .infozingle span:contains("Score")');
      final score = scoreEl?.text.replaceAll(RegExp(r'[^0-9.]'), '').trim() ?? '';

      final episodes = <Map<String, dynamic>>[];
      final epLinks = doc.querySelectorAll('.episodelist ul li a');

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

      // If on episode page directly, provide single episode
      if (episodes.isEmpty && pageUrl.contains('/episode/')) {
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
        'rating': score,
        'subjectType': 2,
        'media_type': 'tv',
        'provider': 'otakudesu',
        'pageUrl': pageUrl,
        'episodes': episodes,
      };
    } catch (e) {
      debugPrint('OtakudesuApiService.getDetails error: $e');
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

      if (ep > 0 || targetUrl.contains('/anime/')) {
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

      // 1. Direct iframe stream
      final iframeEl = doc.querySelector('.responsive-embed-stream iframe, .player-embed iframe, iframe');
      if (iframeEl != null) {
        var src = iframeEl.attributes['src'] ?? '';
        if (src.startsWith('//')) src = 'https:$src';
        if (src.isNotEmpty) {
          streams.add({
            'url': src,
            'quality': 'Direct Player',
            'format': src.contains('.m3u8') ? 'm3u8' : 'mp4',
            'headers': {
              'Referer': targetUrl,
              'User-Agent': _defaultHeaders['User-Agent']!,
            },
          });
        }
      }

      // 2. Mirror stream links with data-content
      final mirrorLinks = doc.querySelectorAll('.mirrorstream ul li a[data-content], [data-content]');
      for (final m in mirrorLinks) {
        final dataContent = m.attributes['data-content'];
        final serverName = m.text.trim();
        if (dataContent != null && dataContent.isNotEmpty) {
          try {
            // Decode base64 payload to find action / args or post directly
            final ajaxRes = await SafeHttpClient.post(
              Uri.parse('$_baseUrl/wp-admin/admin-ajax.php'),
              headers: {
                ..._defaultHeaders,
                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                'X-Requested-With': 'XMLHttpRequest',
                'Referer': targetUrl,
              },
              body: 'action=aa120&data=${Uri.encodeComponent(dataContent)}',
            );

            if (ajaxRes.statusCode == 200 && ajaxRes.body.isNotEmpty) {
              final frameMatch = RegExp(r'<iframe[^>]+src="([^"]+)"').firstMatch(ajaxRes.body);
              if (frameMatch != null) {
                var streamSrc = frameMatch.group(1)!;
                if (streamSrc.startsWith('//')) streamSrc = 'https:$streamSrc';
                streams.add({
                  'url': streamSrc,
                  'quality': serverName.isNotEmpty ? serverName : 'Mirror',
                  'format': streamSrc.contains('.m3u8') ? 'm3u8' : 'mp4',
                  'headers': {
                    'Referer': targetUrl,
                    'User-Agent': _defaultHeaders['User-Agent']!,
                  },
                });
              }
            }
          } catch (_) {}
        }
      }

      return {
        'streams': streams,
        'url': streams.isNotEmpty ? streams.first['url'] : '',
        'format': streams.isNotEmpty ? streams.first['format'] : 'mp4',
        'headers': streams.isNotEmpty ? streams.first['headers'] : {},
      };
    } catch (e) {
      debugPrint('OtakudesuApiService.getResources error: $e');
      return {'streams': []};
    }
  }
}

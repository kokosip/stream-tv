import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'safe_http_client.dart';
import 'remote_config_service.dart';

class DrakorkitaApiService {
  static final DrakorkitaApiService _instance = DrakorkitaApiService._internal();
  factory DrakorkitaApiService() => _instance;
  DrakorkitaApiService._internal();

  String get _baseUrl {
    var url = RemoteConfigService.instance.drakorkitaBaseUrl.trim();
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
    if (s.startsWith('drakorkita_')) {
      s = s.substring('drakorkita_'.length);
    }
    if (s.startsWith('drama_')) {
      s = 'drama/${s.substring(6)}';
    }
    if (s.startsWith('movie_')) {
      s = 'movie/${s.substring(6)}';
    }
    if (!s.startsWith('/')) {
      s = '/$s';
    }
    return '$_baseUrl$s';
  }

  String _createSubjectId(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (segments.isEmpty) return 'drakorkita_unknown';
      if (segments.contains('drama')) {
        return 'drakorkita_drama_${segments.last}';
      }
      if (segments.contains('movie')) {
        return 'drakorkita_movie_${segments.last}';
      }
      return 'drakorkita_${segments.last}';
    } catch (_) {
      return 'drakorkita_${url.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    }
  }

  /// Decode DrakorKita's obfuscated inline JavaScript payload
  String _decodeInlineScript(String html) {
    try {
      final scriptMatch = RegExp(r"""<script[^>]*>([a-zA-Z0-9_$]+)=(['"][0-9a-zA-Z\./=]+['"]);?\s*</script>""").firstMatch(html);
      if (scriptMatch == null) return '';

      var rawPayload = scriptMatch.group(2) ?? '';
      if (rawPayload.startsWith("'") || rawPayload.startsWith('"')) {
        rawPayload = rawPayload.substring(1, rawPayload.length - 1);
      }

      final chunks = rawPayload.split('.');
      final chars = <String>[];

      for (final chunk in chunks) {
        if (chunk.isEmpty) continue;
        try {
          final normalized = base64.normalize(chunk);
          final decoded = utf8.decode(base64.decode(normalized));
          final digits = decoded.replaceAll(RegExp(r'\D'), '');
          if (digits.isNotEmpty) {
            final code = int.parse(digits);
            chars.add(String.fromCharCode(code));
          }
        } catch (_) {}
      }

      return Uri.decodeComponent(chars.join(''));
    } catch (e) {
      debugPrint('DrakorKita decodeInlineScript error: $e');
      return '';
    }
  }

  /// Search drakorkita catalog
  Future<List<Map<String, dynamic>>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      // POST search.php with form key
      final searchRes = await SafeHttpClient.post(
        Uri.parse('$_baseUrl/search.php'),
        headers: {
          ..._defaultHeaders,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Referer': '$_baseUrl/',
        },
        body: 'key=${Uri.encodeQueryComponent(cleanQuery)}',
      );

      if (searchRes.statusCode != 200) return [];

      final doc = html_parser.parse(searchRes.body);
      final items = <Map<String, dynamic>>[];
      final entries = doc.querySelectorAll('.search-item, .item, a[href*="/drama/"], a[href*="/movie/"]');

      final seenLinks = <String>{};

      for (final el in entries) {
        final linkEl = el.attributes.containsKey('href') ? el : el.querySelector('a');
        final pageLink = linkEl?.attributes['href'] ?? '';
        if (pageLink.isEmpty || !seenLinks.add(pageLink)) continue;

        final fullLink = pageLink.startsWith('http') ? pageLink : '$_baseUrl/$pageLink'.replaceAll('//', '/');
        final titleEl = el.querySelector('.title, h2, h3, .name') ?? linkEl;
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final imgEl = el.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final isMovie = pageLink.contains('/movie/');

        items.add({
          'subjectId': _createSubjectId(fullLink),
          'subjectTitle': title,
          'title': title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': fullLink,
          'subjectType': isMovie ? 1 : 2,
          'media_type': isMovie ? 'movie' : 'tv',
          'provider': 'drakorkita',
        });
      }

      return items;
    } catch (e) {
      debugPrint('DrakorkitaApiService.search error: $e');
      return [];
    }
  }

  /// Get Homepage items
  Future<Map<String, dynamic>> getHomepage({int page = 1}) async {
    try {
      final res = await SafeHttpClient.get(
        Uri.parse('$_baseUrl/'),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        return {'code': 0, 'list': [], 'items': []};
      }

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final entries = doc.querySelectorAll('.item, .col-item, .film-item, a[href*="/drama/"], a[href*="/movie/"]');
      final seenLinks = <String>{};

      for (final el in entries) {
        final linkEl = el.attributes.containsKey('href') ? el : el.querySelector('a');
        final pageLink = linkEl?.attributes['href'] ?? '';
        if (pageLink.isEmpty || !seenLinks.add(pageLink)) continue;

        final fullLink = pageLink.startsWith('http') ? pageLink : '$_baseUrl/$pageLink';
        final titleEl = el.querySelector('.title, h2, h3, .name') ?? linkEl;
        final title = titleEl?.text.trim() ?? '';
        if (title.isEmpty) continue;

        final imgEl = el.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final isMovie = pageLink.contains('/movie/');

        items.add({
          'subjectId': _createSubjectId(fullLink),
          'subjectTitle': title,
          'title': title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': fullLink,
          'subjectType': isMovie ? 1 : 2,
          'media_type': isMovie ? 'movie' : 'tv',
          'provider': 'drakorkita',
        });
      }

      return {
        'code': 0,
        'list': items,
        'items': items,
        'data': {'list': items},
      };
    } catch (e) {
      debugPrint('DrakorkitaApiService.getHomepage error: $e');
      return {'code': 0, 'list': [], 'items': []};
    }
  }

  /// Get Details of Drama/Movie
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

      final titleEl = doc.querySelector('.title, h1, .name');
      final title = titleEl?.text.trim() ?? '';

      final imgEl = doc.querySelector('.poster img, .thumb img, img');
      var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
      if (cover.startsWith('//')) cover = 'https:$cover';

      final descEl = doc.querySelector('.synopsis, .description, .desc');
      final description = descEl?.text.trim() ?? '';

      final ratingEl = doc.querySelector('.rating, .score');
      final rating = ratingEl?.text.trim() ?? '';

      final isMovie = pageUrl.contains('/movie/');

      // Decode inline script to get c, t, c_api_host, and drama id
      final decodedJs = _decodeInlineScript(res.body);
      final cMatch = RegExp(r'var\s+c\s*=\s*"([^"]+)"').firstMatch(decodedJs);
      final tMatch = RegExp(r'var\s+t\s*=\s*"([^"]+)"').firstMatch(decodedJs);
      final idMatch = RegExp(r'var\s+id\s*=\s*(\d+)').firstMatch(decodedJs);
      final cApiHostMatch = RegExp(r'var\s+c_api_host\s*=\s*"([^"]+)"').firstMatch(decodedJs);

      final c = cMatch?.group(1) ?? '';
      final t = tMatch?.group(1) ?? '';
      final internalId = idMatch?.group(1) ?? '';
      final cApiHost = cApiHostMatch?.group(1) ?? 'https://api.nonton.bid/c_api';

      final episodes = <Map<String, dynamic>>[];

      if (internalId.isNotEmpty && c.isNotEmpty) {
        try {
          final epApiUrl = '$cApiHost/episode.php?id=$internalId&c=$c&$t';
          final epRes = await SafeHttpClient.get(
            Uri.parse(epApiUrl),
            headers: {
              ..._defaultHeaders,
              'Referer': pageUrl,
            },
          );

          if (epRes.statusCode == 200 && epRes.body.isNotEmpty) {
            final parsedJson = jsonDecode(epRes.body);
            if (parsedJson is List) {
              for (var i = 0; i < parsedJson.length; i++) {
                final epItem = parsedJson[i];
                final epNum = int.tryParse('${epItem['ep']}') ?? (i + 1);
                final epName = epItem['ep_name'] ?? 'Episode $epNum';
                episodes.add({
                  'episodeId': '${subjectId}_ep_$epNum',
                  'episodeNumber': epNum,
                  'title': epName,
                  'internalId': internalId,
                  'c': c,
                  't': t,
                  'cApiHost': cApiHost,
                  'pageUrl': pageUrl,
                });
              }
            }
          }
        } catch (e) {
          debugPrint('DrakorKita fetch episodes error: $e');
        }
      }

      if (episodes.isEmpty) {
        episodes.add({
          'episodeId': '${subjectId}_ep_1',
          'episodeNumber': 1,
          'title': isMovie ? 'Full Movie' : 'Episode 1',
          'internalId': internalId,
          'c': c,
          't': t,
          'cApiHost': cApiHost,
          'pageUrl': pageUrl,
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
        'subjectType': isMovie ? 1 : 2,
        'media_type': isMovie ? 'movie' : 'tv',
        'provider': 'drakorkita',
        'pageUrl': pageUrl,
        'internalId': internalId,
        'c': c,
        't': t,
        'cApiHost': cApiHost,
        'episodes': episodes,
      };
    } catch (e) {
      debugPrint('DrakorkitaApiService.getDetails error: $e');
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
    int ep = 1,
  }) async {
    try {
      final details = await getDetails(subjectId: subjectId);
      final internalId = details['internalId'] ?? '';
      final c = details['c'] ?? '';
      final t = details['t'] ?? '';
      final cApiHost = details['cApiHost'] ?? 'https://api.nonton.bid/c_api';
      final pageUrl = details['pageUrl'] ?? _resolvePageUrl(subjectId);

      final streams = <Map<String, dynamic>>[];

      if (internalId.isNotEmpty && c.isNotEmpty) {
        // Try Loc video endpoint
        final videoUrls = [
          '$cApiHost/video.php?is_mob=0&is_uc=0&id=$internalId&qua=720&server_id=0&cat=1&tag=0&c=$c&$t',
          '$cApiHost/video.php?is_mob=0&is_uc=0&id=$internalId&qua=360&server_id=0&cat=1&tag=0&c=$c&$t',
          '$cApiHost/video_sb.php?is_mob=0&is_uc=0&id=$internalId&qua=360&res=0&server_id=1&cat=0&tag=0&c=$c&$t',
          '$cApiHost/video_hydrax.php?is_mob=0&is_uc=0&id=$internalId&qua=360&res=0&server_id=1&cat=0&tag=0&c=$c&$t',
        ];

        for (final vUrl in videoUrls) {
          try {
            final vRes = await SafeHttpClient.get(
              Uri.parse(vUrl),
              headers: {
                ..._defaultHeaders,
                'Referer': pageUrl,
              },
            );

            if (vRes.statusCode == 200 && vRes.body.isNotEmpty) {
              final json = jsonDecode(vRes.body);
              if (json is Map && json['url'] != null && '${json['url']}'.isNotEmpty) {
                var streamUrl = '${json['url']}';
                if (streamUrl.startsWith('//')) streamUrl = 'https:$streamUrl';

                streams.add({
                  'url': streamUrl,
                  'quality': json['quality'] ?? (vUrl.contains('720') ? '720p' : 'Auto'),
                  'format': streamUrl.contains('.m3u8') ? 'm3u8' : 'mp4',
                  'headers': {
                    'Referer': pageUrl,
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
      debugPrint('DrakorkitaApiService.getResources error: $e');
      return {'streams': []};
    }
  }
}

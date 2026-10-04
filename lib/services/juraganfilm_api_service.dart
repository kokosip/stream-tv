import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'safe_http_client.dart';
import 'remote_config_service.dart';

class JuraganfilmApiService {
  static final JuraganfilmApiService _instance = JuraganfilmApiService._internal();
  factory JuraganfilmApiService() => _instance;
  JuraganfilmApiService._internal();

  String get _baseUrl {
    var url = RemoteConfigService.instance.juraganfilmBaseUrl.trim();
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
    if (s.startsWith('juraganfilm_')) {
      s = s.substring('juraganfilm_'.length);
    }
    if (s.startsWith('series_')) {
      s = 'series/${s.substring(7)}';
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
      if (segments.isEmpty) return 'juraganfilm_unknown';
      if (segments.contains('series')) {
        return 'juraganfilm_series_${segments.last}';
      }
      return 'juraganfilm_${segments.last}';
    } catch (_) {
      return 'juraganfilm_${url.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    }
  }

  /// Search movies and series
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
      final articles = doc.querySelectorAll('article.item, div.item, .item-infinite');

      for (final art in articles) {
        final titleEl = art.querySelector('h2.entry-title a') ?? art.querySelector('a.title') ?? art.querySelector('h3 a') ?? art.querySelector('a[href*="/"]');
        final title = titleEl?.text.trim() ?? '';
        final pageLink = titleEl?.attributes['href'] ?? '';
        if (title.isEmpty || pageLink.isEmpty || !pageLink.startsWith('http')) continue;

        final imgEl = art.querySelector('img');
        var cover = imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final qualityEl = art.querySelector('.gmr-quality-item, .quality');
        final quality = qualityEl?.text.trim() ?? '';

        final ratingEl = art.querySelector('.gmr-rating-item, .rating');
        final rating = ratingEl?.text.trim() ?? '';

        final isTv = pageLink.contains('/series/') || pageLink.contains('/tv/') || quality.toLowerCase().contains('season');

        final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(title);
        final year = yearMatch != null ? yearMatch.group(1) : '';
        final cleanTitle = title.replaceAll(RegExp(r'\s*\(\d{4}\)\s*'), '').trim();

        items.add({
          'subjectId': _createSubjectId(pageLink),
          'subjectTitle': cleanTitle.isNotEmpty ? cleanTitle : title,
          'title': cleanTitle.isNotEmpty ? cleanTitle : title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': pageLink,
          'quality': quality,
          'rating': rating,
          'year': year,
          'subjectType': isTv ? 2 : 1,
          'media_type': isTv ? 'tv' : 'movie',
          'provider': 'juraganfilm',
        });
      }

      return items;
    } catch (e) {
      debugPrint('JuraganfilmApiService.search error: $e');
      return [];
    }
  }

  /// Get Homepage items
  Future<Map<String, dynamic>> getHomepage({int page = 1, int tabId = 0}) async {
    try {
      final url = page > 1 ? '$_baseUrl/page/$page/' : '$_baseUrl/';
      final res = await SafeHttpClient.get(
        Uri.parse(url),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        return {'code': 0, 'list': [], 'items': []};
      }

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final articles = doc.querySelectorAll('article.item, div.item, .item-infinite');

      for (final art in articles) {
        final titleEl = art.querySelector('h2.entry-title a') ?? art.querySelector('a.title') ?? art.querySelector('h3 a');
        final title = titleEl?.text.trim() ?? '';
        final pageLink = titleEl?.attributes['href'] ?? '';
        if (title.isEmpty || pageLink.isEmpty) continue;

        final imgEl = art.querySelector('img');
        var cover = imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final qualityEl = art.querySelector('.gmr-quality-item, .quality');
        final quality = qualityEl?.text.trim() ?? '';

        final ratingEl = art.querySelector('.gmr-rating-item, .rating');
        final rating = ratingEl?.text.trim() ?? '';

        final isTv = pageLink.contains('/series/') || pageLink.contains('/tv/');
        final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(title);
        final year = yearMatch != null ? yearMatch.group(1) : '';
        final cleanTitle = title.replaceAll(RegExp(r'\s*\(\d{4}\)\s*'), '').trim();

        items.add({
          'subjectId': _createSubjectId(pageLink),
          'subjectTitle': cleanTitle.isNotEmpty ? cleanTitle : title,
          'title': cleanTitle.isNotEmpty ? cleanTitle : title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': cover,
          'backdrop_path': cover,
          'pageUrl': pageLink,
          'quality': quality,
          'rating': rating,
          'year': year,
          'subjectType': isTv ? 2 : 1,
          'media_type': isTv ? 'tv' : 'movie',
          'provider': 'juraganfilm',
        });
      }

      return {
        'code': 0,
        'list': items,
        'items': items,
        'data': {'list': items},
      };
    } catch (e) {
      debugPrint('JuraganfilmApiService.getHomepage error: $e');
      return {'code': 0, 'list': [], 'items': []};
    }
  }

  /// Get Details of movie or series
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

      final titleEl = doc.querySelector('h1.entry-title') ?? doc.querySelector('h1');
      var rawTitle = titleEl?.text.trim() ?? '';
      rawTitle = rawTitle.replaceFirst(RegExp(r'^Nonton\s+', caseSensitive: false), '');
      final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(rawTitle);
      final year = yearMatch?.group(1) ?? '';
      final title = rawTitle.replaceAll(RegExp(r'\s*\(\d{4}\)\s*'), '').trim();

      final imgEl = doc.querySelector('.poster img, .entry-content img, article img');
      var cover = imgEl?.attributes['data-src'] ?? imgEl?.attributes['src'] ?? '';
      if (cover.startsWith('//')) cover = 'https:$cover';

      final descEl = doc.querySelector('.entry-content p, .synopsis p, .description p');
      final description = descEl?.text.trim() ?? '';

      final ratingEl = doc.querySelector('.gmr-rating-item, .rating, [itemprop="ratingValue"]');
      final rating = ratingEl?.text.trim() ?? '';

      final isTv = pageUrl.contains('/series/') || pageUrl.contains('/tv/') || doc.querySelector('.episodios, .gmr-listseries') != null;

      // Extract episodes if TV
      final episodes = <Map<String, dynamic>>[];
      if (isTv) {
        final epEls = doc.querySelectorAll('.episodios li a, .gmr-listseries a, .list-eps a');
        for (var i = 0; i < epEls.length; i++) {
          final epEl = epEls[i];
          final epUrl = epEl.attributes['href'] ?? '';
          final epText = epEl.text.trim();
          if (epUrl.isEmpty) continue;

          final epNumMatch = RegExp(r'(?:episode|eps|ep)\.?\s*(\d+)', caseSensitive: false).firstMatch(epText) ??
              RegExp(r'(\d+)').firstMatch(epText);
          final epNum = epNumMatch != null ? int.tryParse(epNumMatch.group(1)!) ?? (i + 1) : (i + 1);

          episodes.add({
            'episodeId': _createSubjectId(epUrl),
            'episodeNumber': epNum,
            'title': epText.isNotEmpty ? epText : 'Episode $epNum',
            'url': epUrl,
          });
        }
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
        'year': year,
        'rating': rating,
        'subjectType': isTv ? 2 : 1,
        'media_type': isTv ? 'tv' : 'movie',
        'provider': 'juraganfilm',
        'pageUrl': pageUrl,
        'episodes': episodes,
      };
    } catch (e) {
      debugPrint('JuraganfilmApiService.getDetails error: $e');
      return {'subjectId': subjectId, 'title': 'Error', 'episodes': []};
    }
  }

  /// Get season info for TV
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

  /// Get stream resources
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
  }) async {
    try {
      String targetUrl = _resolvePageUrl(subjectId);

      // If series and ep specified, resolve episode URL from details
      if (ep > 0 || targetUrl.contains('/series/')) {
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

      // Check for iframes
      final iframes = RegExp(r'<iframe[^>]+src="([^"]+)"', caseSensitive: false).allMatches(pageRes.body);
      final streams = <Map<String, dynamic>>[];

      for (final m in iframes) {
        var embedUrl = m.group(1) ?? '';
        if (embedUrl.startsWith('//')) embedUrl = 'https:$embedUrl';
        if (!embedUrl.startsWith('http')) continue;

        if (embedUrl.contains('juragan.film') || embedUrl.contains('/embed/')) {
          final embedRes = await SafeHttpClient.get(
            Uri.parse(embedUrl),
            headers: {
              ..._defaultHeaders,
              'Referer': targetUrl,
            },
          );

          if (embedRes.statusCode == 200) {
            final body = embedRes.body;
            // Look for SOURCES = [...]
            final sourcesMatch = RegExp(r'const\s+SOURCES\s*=\s*(\[[^\]]+\])', dotAll: true).firstMatch(body) ??
                RegExp(r'sources\s*:\s*(\[[^\]]+\])', dotAll: true).firstMatch(body);

            if (sourcesMatch != null) {
              try {
                final jsonStr = sourcesMatch.group(1)!;
                final parsed = jsonDecode(jsonStr);
                if (parsed is List) {
                  for (final item in parsed) {
                    final file = item['file'] ?? item['src'] ?? '';
                    final label = item['label'] ?? item['quality'] ?? 'Auto';
                    if (file.toString().isNotEmpty) {
                      streams.add({
                        'url': file.toString(),
                        'quality': label.toString(),
                        'format': file.toString().contains('.m3u8') ? 'm3u8' : 'mp4',
                        'headers': {
                          'Referer': embedUrl,
                          'User-Agent': _defaultHeaders['User-Agent']!,
                        },
                      });
                    }
                  }
                }
              } catch (_) {}
            }

            // Direct mp4 / m3u8 in embed script
            final directUrls = RegExp(r"""(https?://[^\s"']+\.(?:m3u8|mp4)[^\s"']*)""").allMatches(body);
            for (final u in directUrls) {
              final link = u.group(1)!;
              if (!streams.any((s) => s['url'] == link)) {
                streams.add({
                  'url': link,
                  'quality': 'Auto',
                  'format': link.contains('.m3u8') ? 'm3u8' : 'mp4',
                  'headers': {
                    'Referer': embedUrl,
                    'User-Agent': _defaultHeaders['User-Agent']!,
                  },
                });
              }
            }
          }
        }
      }

      return {
        'streams': streams,
        'url': streams.isNotEmpty ? streams.first['url'] : '',
        'format': streams.isNotEmpty ? streams.first['format'] : 'mp4',
        'headers': streams.isNotEmpty ? streams.first['headers'] : {},
      };
    } catch (e) {
      debugPrint('JuraganfilmApiService.getResources error: $e');
      return {'streams': []};
    }
  }
}

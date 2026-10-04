import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'safe_http_client.dart';
import 'remote_config_service.dart';

/// Unpacker for JavaScript packed with Dean Edwards p,a,c,k,e,r
class JsUnpacker {
  final String packedJs;
  JsUnpacker(this.packedJs);

  static bool detect(String js) {
    final cleaned = js.replaceAll(' ', '');
    return RegExp(r'eval\(function\(p,a,c,k,e,[rd]').hasMatch(cleaned);
  }

  String? unpack() {
    try {
      final match = RegExp(
        r"""\}\s*\('(.*)',\s*(.*?),\s*(\d+),\s*'(.*?)'\.split\('\|'\)""",
        dotAll: true,
      ).firstMatch(packedJs);

      if (match != null && match.groupCount >= 4) {
        var payload = match.group(1)!.replaceAll(r"\'", "'");
        final radixStr = match.group(2) ?? '36';
        final symtab = match.group(4)!.split('|');

        final radix = int.tryParse(radixStr) ?? 36;
        final unbase = _Unbase(radix);
        final wordRegex = RegExp(r'\b[a-zA-Z0-9_]+\b');
        final decoded = StringBuffer();
        var lastIndex = 0;

        for (final m in wordRegex.allMatches(payload)) {
          decoded.write(payload.substring(lastIndex, m.start));
          final word = m.group(0)!;
          final x = unbase.unbase(word);
          if (x >= 0 && x < symtab.length && symtab[x].isNotEmpty) {
            decoded.write(symtab[x]);
          } else {
            decoded.write(word);
          }
          lastIndex = m.end;
        }
        decoded.write(payload.substring(lastIndex));
        return decoded.toString();
      }
    } catch (e) {
      debugPrint('JsUnpacker error: $e');
    }
    return null;
  }
}

class _Unbase {
  final int radix;
  static const _alphabet62 = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _alphabet95 = ' !"#\$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~';
  String? alphabet;
  Map<String, int>? dictionary;

  _Unbase(this.radix) {
    if (radix > 36) {
      if (radix < 62) {
        alphabet = _alphabet62.substring(0, radix);
      } else if (radix >= 63 && radix <= 94) {
        alphabet = _alphabet95.substring(0, radix);
      } else if (radix == 62) {
        alphabet = _alphabet62;
      } else if (radix == 95) {
        alphabet = _alphabet95;
      }
      dictionary = {};
      for (var i = 0; i < (alphabet?.length ?? 0); i++) {
        dictionary![alphabet![i]] = i;
      }
    }
  }

  int unbase(String str) {
    if (alphabet == null || dictionary == null) {
      return int.tryParse(str, radix: radix) ?? 0;
    }
    var ret = 0;
    final reversed = str.split('').reversed.toList();
    for (var i = 0; i < reversed.length; i++) {
      final charVal = dictionary![reversed[i]] ?? 0;
      ret += (pow(radix.toDouble(), i.toDouble()) * charVal).toInt();
    }
    return ret;
  }
}

class PusatfilmApiService {
  static final PusatfilmApiService _instance = PusatfilmApiService._internal();
  factory PusatfilmApiService() => _instance;
  PusatfilmApiService._internal();

  String get _baseUrl {
    var url = RemoteConfigService.instance.pusatfilmBaseUrl.trim();
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'id-ID,id;q=0.9,en-US;q=0.8,en;q=0.7',
  };

  /// Clean or resolve subject ID to full page URL
  String _resolvePageUrl(String subjectId) {
    var s = subjectId.trim();
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return s;
    }
    if (s.startsWith('pusatfilm_')) {
      s = s.substring('pusatfilm_'.length);
    }
    if (s.startsWith('tv_')) {
      s = 'tv/${s.substring(3)}';
    }
    if (!s.startsWith('/')) {
      s = '/$s';
    }
    if (!s.endsWith('/')) {
      s = '$s/';
    }
    return '$_baseUrl$s';
  }

  /// Create clean subject ID from URL
  String _createSubjectId(String url) {
    try {
      final uri = Uri.parse(url);
      final pathSegments = uri.pathSegments.where((p) => p.isNotEmpty).toList();
      if (pathSegments.isEmpty) return 'pusatfilm_unknown';
      if (pathSegments.contains('tv')) {
        final last = pathSegments.last;
        return 'pusatfilm_tv_$last';
      }
      return 'pusatfilm_${pathSegments.last}';
    } catch (_) {
      return 'pusatfilm_${url.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    }
  }

  /// Search movies and TV shows
  Future<List<Map<String, dynamic>>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final searchUrl = page > 1
          ? '$_baseUrl/page/$page/?s=${Uri.encodeComponent(cleanQuery)}&post_type[]=post&post_type[]=tv'
          : '$_baseUrl/?s=${Uri.encodeComponent(cleanQuery)}&post_type[]=post&post_type[]=tv';

      final res = await SafeHttpClient.get(
        Uri.parse(searchUrl),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) return [];

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final articles = doc.querySelectorAll('article.item, .item-infinite');

      for (final art in articles) {
        final titleEl = art.querySelector('h2.entry-title a') ?? art.querySelector('a.title');
        final title = titleEl?.text.trim() ?? '';
        final pageLink = titleEl?.attributes['href'] ?? '';
        if (title.isEmpty || pageLink.isEmpty) continue;

        final imgEl = art.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final qualityEl = art.querySelector('.gmr-quality-item, .quality');
        final quality = qualityEl?.text.trim() ?? '';

        final ratingEl = art.querySelector('.gmr-rating-item, .rating');
        final rating = ratingEl?.text.trim() ?? '';

        final durationEl = art.querySelector('.gmr-duration-item, .duration');
        final duration = durationEl?.text.trim() ?? '';

        final isTv = pageLink.contains('/tv/') ||
            quality.toLowerCase().contains('season') ||
            quality.toLowerCase().contains('eps');

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
          'duration': duration,
          'year': year,
          'subjectType': isTv ? 2 : 1,
          'media_type': isTv ? 'tv' : 'movie',
          'provider': 'pusatfilm',
        });
      }

      return items;
    } catch (e) {
      debugPrint('Pusatfilm search error: $e');
      return [];
    }
  }

  /// Get Homepage items
  Future<Map<String, dynamic>> getHomepage({int page = 1}) async {
    try {
      final homeUrl = page > 1 ? '$_baseUrl/page/$page/' : '$_baseUrl/';
      final res = await SafeHttpClient.get(
        Uri.parse(homeUrl),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        return {'code': 0, 'list': [], 'items': []};
      }

      final doc = html_parser.parse(res.body);
      final items = <Map<String, dynamic>>[];
      final articles = doc.querySelectorAll('article.item');

      for (final art in articles) {
        final titleEl = art.querySelector('h2.entry-title a') ?? art.querySelector('a.title');
        final title = titleEl?.text.trim() ?? '';
        final pageLink = titleEl?.attributes['href'] ?? '';
        if (title.isEmpty || pageLink.isEmpty) continue;

        final imgEl = art.querySelector('img');
        var cover = imgEl?.attributes['src'] ?? imgEl?.attributes['data-src'] ?? '';
        if (cover.startsWith('//')) cover = 'https:$cover';

        final qualityEl = art.querySelector('.gmr-quality-item, .quality');
        final quality = qualityEl?.text.trim() ?? '';

        final ratingEl = art.querySelector('.gmr-rating-item, .rating');
        final rating = ratingEl?.text.trim() ?? '';

        final isTv = pageLink.contains('/tv/') ||
            quality.toLowerCase().contains('season') ||
            quality.toLowerCase().contains('eps');

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
          'provider': 'pusatfilm',
        });
      }

      return {
        'code': 0,
        'list': items,
        'items': items,
        'data': {
          'operating_list': [
            {
              'title': 'PusatFilm Terbaru (Indo Sub)',
              'movies': items,
            }
          ]
        }
      };
    } catch (e) {
      debugPrint('Pusatfilm getHomepage error: $e');
      return {'code': 0, 'list': [], 'items': []};
    }
  }

  /// Get Details of a Movie or TV Show
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    final pageUrl = _resolvePageUrl(subjectId);

    try {
      final res = await SafeHttpClient.get(
        Uri.parse(pageUrl),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        throw Exception('Pusatfilm HTTP ${res.statusCode}');
      }

      final doc = html_parser.parse(res.body);

      final titleEl = doc.querySelector('h1.entry-title');
      final rawTitle = titleEl?.text.trim() ?? '';

      final yearMatch = RegExp(r'\((\d{4})\)').firstMatch(rawTitle);
      final year = yearMatch != null ? yearMatch.group(1) : '';
      final cleanTitle = rawTitle.replaceAll(RegExp(r'\s*\(\d{4}\)\s*'), '').trim();

      // Synopsis / Description
      final descEl = doc.querySelector('.entry-content p') ??
          doc.querySelector('.synopsis') ??
          doc.querySelector('.gmr-moviedata p');
      final description = descEl?.text.trim() ?? '';

      // Cover / Poster
      final posterEl = doc.querySelector('.gmr-movie-poster img') ??
          doc.querySelector('.entry-content img') ??
          doc.querySelector('article img');
      var poster = posterEl?.attributes['src'] ?? posterEl?.attributes['data-src'] ?? '';
      if (poster.startsWith('//')) poster = 'https:$poster';

      // Genres
      final genreElements = doc.querySelectorAll('.gmr-moviedata a[rel="category tag"], .gmr-movie-genre a, a[href*="/genre/"]');
      final genres = genreElements.map((e) => e.text.trim()).where((g) => g.isNotEmpty).toSet().toList();

      // Rating
      final ratingEl = doc.querySelector('.gmr-rating-item, [itemprop="ratingValue"]');
      final rating = ratingEl?.text.trim() ?? '';

      final isTv = pageUrl.contains('/tv/') ||
          doc.querySelector('.season-accordion-wrap') != null ||
          doc.querySelector('.gmr-listseries') != null;

      // Extract Seasons and Episodes for TV Shows
      final seasonsList = <Map<String, dynamic>>[];
      final seasonWraps = doc.querySelectorAll('.season-accordion-wrap');

      if (seasonWraps.isNotEmpty) {
        for (final wrap in seasonWraps) {
          final sTitleEl = wrap.querySelector('.season-title');
          final sTitle = sTitleEl?.text.trim() ?? '';
          final sNumMatch = RegExp(r'(\d+)').firstMatch(sTitle);
          final seasonNumber = sNumMatch != null ? int.tryParse(sNumMatch.group(1)!) ?? 1 : 1;

          final epLinks = wrap.querySelectorAll('a[href*="/eps/"]');
          final epList = <Map<String, dynamic>>[];

          for (int i = 0; i < epLinks.length; i++) {
            final a = epLinks[i];
            final epText = a.text.trim();
            final epHref = a.attributes['href'] ?? '';
            final epMatch = RegExp(r'episode-(\d+)').firstMatch(epHref) ?? RegExp(r'(\d+)').firstMatch(epText);
            final epNumber = epMatch != null ? int.tryParse(epMatch.group(1)!) ?? (i + 1) : (i + 1);

            epList.add({
              'se': seasonNumber,
              'ep': epNumber,
              'title': 'Episode $epNumber',
              'pageUrl': epHref,
              'url': epHref,
            });
          }

          if (epList.isNotEmpty) {
            seasonsList.add({
              'se': seasonNumber,
              'season_number': seasonNumber,
              'name': sTitle.isNotEmpty ? sTitle : 'Season $seasonNumber',
              'maxEp': epList.length,
              'episodes': epList,
            });
          }
        }
      } else {
        // Fallback episode listing
        final epsLinks = doc.querySelectorAll('a[href*="/eps/"]');
        if (epsLinks.isNotEmpty) {
          final epList = <Map<String, dynamic>>[];
          for (int i = 0; i < epsLinks.length; i++) {
            final a = epsLinks[i];
            final epText = a.text.trim();
            final epHref = a.attributes['href'] ?? '';
            final epMatch = RegExp(r'episode-(\d+)').firstMatch(epHref) ?? RegExp(r'(\d+)').firstMatch(epText);
            final epNumber = epMatch != null ? int.tryParse(epMatch.group(1)!) ?? (i + 1) : (i + 1);

            epList.add({
              'se': 1,
              'ep': epNumber,
              'title': 'Episode $epNumber',
              'pageUrl': epHref,
              'url': epHref,
            });
          }
          seasonsList.add({
            'se': 1,
            'season_number': 1,
            'name': 'Season 1',
            'maxEp': epList.length,
            'episodes': epList,
          });
        }
      }

      return {
        'subjectId': subjectId,
        'subjectTitle': cleanTitle.isNotEmpty ? cleanTitle : rawTitle,
        'title': cleanTitle.isNotEmpty ? cleanTitle : rawTitle,
        'description': description,
        'overview': description,
        'cover': poster,
        'coverUrl': poster,
        'poster_path': poster,
        'backdrop_path': poster,
        'genres': genres,
        'year': year,
        'rating': rating,
        'subjectType': isTv ? 2 : 1,
        'media_type': isTv ? 'tv' : 'movie',
        'provider': 'pusatfilm',
        'pageUrl': pageUrl,
        'seasons': seasonsList,
        'dubs': [
          {
            'lanName': 'Indonesian Subtitle',
            'language': 'id',
            'subjectId': subjectId,
            'original': true,
          }
        ],
      };
    } catch (e) {
      debugPrint('Pusatfilm getDetails error: $e');
      rethrow;
    }
  }

  /// Get Season details for a TV show
  Future<Map<String, dynamic>> getSeasonInfo({required String subjectId}) async {
    final details = await getDetails(subjectId: subjectId);
    return {'seasons': details['seasons'] ?? []};
  }

  /// Get Seasons list for a TV show
  Future<List<Map<String, dynamic>>> getSeasons(String subjectId) async {
    final details = await getDetails(subjectId: subjectId);
    final seasons = details['seasons'] as List?;
    if (seasons != null) {
      return seasons
          .map((s) => s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{})
          .where((m) => m.isNotEmpty)
          .toList();
    }
    return [];
  }

  /// Decodes GDrivePlayer script payload (XOR cipher)
  static Map<String, dynamic>? _extractGdrivePlayer(String html, String referer) {
    try {
      final kMatch = RegExp(r'var\s+k="([^"]+)"').firstMatch(html);
      final bMatch = RegExp(r'b=atob\("([^"]+)"\)').firstMatch(html);
      if (kMatch == null || bMatch == null) return null;

      final k = kMatch.group(1)!;
      final b64 = bMatch.group(1)!.replaceAll(r'\/', '/');
      final bBytes = base64Decode(b64);
      final kBytes = utf8.encode(k);
      final decryptedBytes = <int>[];
      for (var i = 0; i < bBytes.length; i++) {
        decryptedBytes.add(bBytes[i] ^ kBytes[i % kBytes.length]);
      }
      final decrypted = utf8.decode(decryptedBytes, allowMalformed: true);

      // Extract HLS playlist
      final hlsMatch = RegExp(r'HLS="([^"]+)"').firstMatch(decrypted);
      String? streamUrl;
      if (hlsMatch != null) {
        final relHls = hlsMatch.group(1)!;
        streamUrl = relHls.startsWith('http') ? relHls : 'https://gdriveplayer.to/$relHls';
      }

      // Extract direct MP4 or sources
      if (streamUrl == null) {
        final mp4Match = RegExp(r'''(?:file|MP4BASE)\s*[:=]\s*["']([^"']+\.mp4[^"']*)["']''').firstMatch(decrypted);
        if (mp4Match != null) {
          streamUrl = mp4Match.group(1);
        }
      }

      // Extract Subtitles
      final tracks = <Map<String, dynamic>>[];
      final tracksMatch = RegExp(r'''tracks\s*:\s*(\[[^\]]+\])''').firstMatch(decrypted);
      if (tracksMatch != null) {
        try {
          final rawTracks = tracksMatch.group(1)!;
          final jsonTracks = jsonDecode(rawTracks) as List<dynamic>;
          for (final t in jsonTracks) {
            if (t is Map && t['file'] != null) {
              tracks.add({
                'label': t['label'] ?? 'Subtitle',
                'file': t['file'],
                'url': t['file'],
                'kind': t['kind'] ?? 'captions',
              });
            }
          }
        } catch (_) {}
      }

      if (streamUrl != null && streamUrl.isNotEmpty) {
        return {
          'streamUrl': streamUrl,
          'tracks': tracks,
          'referer': 'https://gdriveplayer.to/',
        };
      }
    } catch (e) {
      debugPrint('Gdriveplayer extract error: $e');
    }
    return null;
  }

  /// Resolve Kotakajaib embed player into streaming sources
  Future<List<Map<String, dynamic>>> _extractKotakajaib(String embedUrl, String referer) async {
    final List<Map<String, dynamic>> results = [];
    try {
      final res = await SafeHttpClient.get(
        Uri.parse(embedUrl),
        headers: {
          ..._defaultHeaders,
          'Referer': referer,
        },
      );
      if (res.statusCode != 200) return results;

      final doc = html_parser.parse(res.body);
      final buttons = doc.querySelectorAll('button.server-item');

      for (final btn in buttons) {
        final serverName = btn.text.trim();
        final rawFrame = btn.attributes['data-frame'] ?? '';
        if (rawFrame.isEmpty) continue;

        var frameUrl = '';
        try {
          frameUrl = utf8.decode(base64Decode(rawFrame));
        } catch (_) {
          try {
            frameUrl = latin1.decode(base64Decode(rawFrame));
          } catch (_) {}
        }
        if (frameUrl.isEmpty) continue;
        if (frameUrl.startsWith('//')) frameUrl = 'https:$frameUrl';

        // 1. GDrivePlayer
        if (frameUrl.contains('gdriveplayer') || frameUrl.contains('databasegdriveplayer')) {
          final gdRes = await SafeHttpClient.get(
            Uri.parse(frameUrl),
            headers: {
              ..._defaultHeaders,
              'Referer': embedUrl,
            },
          );
          if (gdRes.statusCode == 200) {
            final gdData = _extractGdrivePlayer(gdRes.body, frameUrl);
            if (gdData != null) {
              final streamUrl = gdData['streamUrl'] as String;
              results.add({
                'resourceId': 'pusatfilm_gdrive_${results.length + 1}',
                'resourceLink': streamUrl,
                'resource_link': streamUrl,
                'url': streamUrl,
                'resolution': 1080,
                'quality': '1080p ($serverName)',
                'direct_file': true,
                'provider': 'pusatfilm',
                'headers': {
                  'Referer': gdData['referer'] ?? 'https://gdriveplayer.to/',
                  'User-Agent': _defaultHeaders['User-Agent']!,
                },
                'captions': gdData['tracks'] ?? [],
              });
            }
          }
        }

        // 2. VidHide / Filelions / Vectorx / Hydrax
        else if (frameUrl.contains('vectorx') || frameUrl.contains('vidhide') || frameUrl.contains('filelions') || frameUrl.contains('playhydrax')) {
          final vRes = await SafeHttpClient.get(
            Uri.parse(frameUrl),
            headers: {
              ..._defaultHeaders,
              'Referer': embedUrl,
            },
          );
          if (vRes.statusCode == 200) {
            var body = vRes.body;
            if (JsUnpacker.detect(body)) {
              body = JsUnpacker(body).unpack() ?? body;
            }

            final m3u8Match = RegExp(r'''https?://[^\s"'<>]+\.m3u8[^\s"'<>]*''').firstMatch(body);
            final mp4Match = RegExp(r'''https?://[^\s"'<>]+\.mp4[^\s"'<>]*''').firstMatch(body);
            final directUrl = m3u8Match?.group(0) ?? mp4Match?.group(0);

            if (directUrl != null) {
              results.add({
                'resourceId': 'pusatfilm_vidhide_${results.length + 1}',
                'resourceLink': directUrl,
                'resource_link': directUrl,
                'url': directUrl,
                'resolution': 1080,
                'quality': '1080p ($serverName)',
                'direct_file': true,
                'provider': 'pusatfilm',
                'headers': {
                  'Referer': frameUrl,
                  'User-Agent': _defaultHeaders['User-Agent']!,
                },
                'captions': [],
              });
            }
          }
        }

        // 3. Direct video
        else if (frameUrl.contains('.m3u8') || frameUrl.contains('.mp4')) {
          results.add({
            'resourceId': 'pusatfilm_direct_${results.length + 1}',
            'resourceLink': frameUrl,
            'resource_link': frameUrl,
            'url': frameUrl,
            'resolution': 1080,
            'quality': '1080p ($serverName)',
            'direct_file': true,
            'provider': 'pusatfilm',
            'headers': {
              'Referer': embedUrl,
              'User-Agent': _defaultHeaders['User-Agent']!,
            },
            'captions': [],
          });
        }
      }
    } catch (e) {
      debugPrint('Pusatfilm extractKotakajaib error: $e');
    }
    return results;
  }

  /// Get video streaming resources for movie or specific TV episode
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
  }) async {
    try {
      String targetUrl = _resolvePageUrl(subjectId);

      // If it's a TV show and episode specified, resolve the episode URL
      if (se > 0 || ep > 0 || subjectId.contains('_tv_') || targetUrl.contains('/tv/')) {
        final details = await getDetails(subjectId: subjectId);
        final seasons = details['seasons'] as List? ?? [];
        final targetSe = se > 0 ? se : 1;
        final targetEp = ep > 0 ? ep : 1;

        String? foundEpUrl;
        for (final s in seasons) {
          if (s is Map && (s['se'] == targetSe || s['season_number'] == targetSe)) {
            final episodes = s['episodes'] as List? ?? [];
            for (final e in episodes) {
              if (e is Map && (e['ep'] == targetEp)) {
                foundEpUrl = e['pageUrl'] ?? e['url'];
                break;
              }
            }
            break;
          }
        }

        if (foundEpUrl != null && foundEpUrl.isNotEmpty) {
          targetUrl = foundEpUrl;
        }
      }

      final res = await SafeHttpClient.get(
        Uri.parse(targetUrl),
        headers: _defaultHeaders,
      );

      if (res.statusCode != 200) {
        return {'list': []};
      }

      final doc = html_parser.parse(res.body);

      // Find Kotakajaib or embed iframes
      final iframes = doc.querySelectorAll('iframe');
      final streamList = <Map<String, dynamic>>[];

      for (final iframe in iframes) {
        final src = iframe.attributes['src'] ?? iframe.attributes['data-src'] ?? '';
        if (src.isEmpty) continue;

        if (src.contains('kotakajaib.me') || src.contains('embed')) {
          final streams = await _extractKotakajaib(src, targetUrl);
          streamList.addAll(streams);
        }
      }

      return {
        'code': 0,
        'list': streamList,
        'streams': streamList,
      };
    } catch (e) {
      debugPrint('Pusatfilm getResources error: $e');
      return {'list': []};
    }
  }
}

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'remote_config_service.dart';

class DramachiApiService {
  static const String DEFAULT_BASE_URL = RemoteConfigService.defaultDramachiBaseUrl;
  static const String DEFAULT_IMAGE_CDN_BASE = RemoteConfigService.defaultDramachiImageCdn;
  static String get IMAGE_CDN_BASE => RemoteConfigService.instance.dramachiImageCdn;

  final String? _explicitBaseUrl;
  String get baseUrl => _explicitBaseUrl ?? RemoteConfigService.instance.dramachiBaseUrl;
  final http.Client _client = http.Client();

  DramachiApiService({String? baseUrl})
      : _explicitBaseUrl = baseUrl;

  Future<http.Response> _getSafe(Uri Function(String currentBase) uriBuilder) async {
    try {
      final res = await _client.get(uriBuilder(baseUrl)).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 400 && res.statusCode != 429) {
        throw Exception("Dramachi server error (${res.statusCode})");
      }
      return res;
    } catch (e) {
      if (_explicitBaseUrl == null) {
        final refreshed = await RemoteConfigService.instance
            .refreshConfigOnFailure(reason: 'dramachi_error: $e');
        if (refreshed) {
          return await _client.get(uriBuilder(baseUrl)).timeout(const Duration(seconds: 12));
        }
      }
      rethrow;
    }
  }

  static int? extractLeadingSeasonNumber(String name) {
    final lower = name.toLowerCase();
    if (!lower.startsWith('season')) return null;
    final afterSeason = lower.substring('season'.length).trim();
    final digits = afterSeason.split(RegExp(r'[^0-9]')).first;
    return int.tryParse(digits);
  }

  static int? parseEpisodeNumber(String fTitle) {
    final upper = fTitle.toUpperCase();
    final eIdx = upper.lastIndexOf('E');
    if (eIdx != -1) {
      final slice = upper.substring(eIdx + 1);
      final digits = StringBuffer();
      for (int i = 0; i < slice.length; i++) {
        final code = slice.codeUnitAt(i);
        if (code >= 48 && code <= 57) {
          digits.writeCharCode(code);
        } else {
          break;
        }
      }
      if (digits.isNotEmpty) {
        return int.tryParse(digits.toString());
      }
    }

    final tokens = fTitle.trim().split(RegExp(r'\s+'));
    if (tokens.isNotEmpty) {
      final last = int.tryParse(tokens.last);
      if (last != null) return last;
    }
    return null;
  }

  static String cleanEpisodeTitle(String fTitle) {
    var title = fTitle.trim();
    const suffixes = [
      " 1080p", " 720p", " 540p", " 480p", " 360p",
      " DUB", " hi DUB", " ENG Subbed Full", " Subbed",
    ];
    for (final s in suffixes) {
      if (title.endsWith(s)) {
        title = title.substring(0, title.length - s.length).trim();
      }
    }
    return title;
  }

  static int parseSizeToBytes(String sizeStr) {
    final trimmed = sizeStr.trim();
    if (trimmed.isEmpty) return 0;
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty) return 0;
    final numVal = double.tryParse(parts[0]) ?? 0.0;
    final unit = (parts.length > 1 ? parts[1] : 'MB').toUpperCase();
    if (unit.contains('GB') || unit.contains('GIB')) {
      return (numVal * 1024 * 1024 * 1024).toInt();
    } else if (unit.contains('MB') || unit.contains('MIB')) {
      return (numVal * 1024 * 1024).toInt();
    } else if (unit.contains('KB') || unit.contains('KIB')) {
      return (numVal * 1024).toInt();
    }
    return (numVal * 1024 * 1024).toInt();
  }

  static int parseQualityInt(String qualityStr) {
    final lower = qualityStr.toLowerCase();
    if (lower.contains('2160') || lower.contains('4k')) return 2160;
    if (lower.contains('1080')) return 1080;
    if (lower.contains('720')) return 720;
    if (lower.contains('540')) return 540;
    if (lower.contains('480')) return 480;
    if (lower.contains('360')) return 360;
    return 720;
  }

  /// Search movies, K-dramas, C-dramas, and anime
  Future<List<Map<String, dynamic>>> search(String query, {int page = 1}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    final response = await _getSafe((base) => Uri.parse(
      "$base?interface=search&q=${Uri.encodeComponent(trimmed)}&filter=all&page=${page > 0 ? page : 1}",
    ));
    if (response.statusCode != 200) {
      throw Exception("Dramachi search failed (${response.statusCode})");
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final rawItems = (data['data'] as List<dynamic>?) ?? [];
    final List<Map<String, dynamic>> results = [];

    for (final item in rawItems) {
      if (item is! Map) continue;
      final isMovie = (item['content']?.toString().toLowerCase() ?? '') == 'movies' ||
          (item['content']?.toString().toLowerCase() ?? '') == 'movie';
      final thumb = (item['thumb'] ?? '').toString().trim();
      final posterUrl = thumb.isNotEmpty ? "$IMAGE_CDN_BASE$thumb" : null;
      final id = (item['id'] ?? '').toString();

      results.add({
        'id': id,
        'subjectId': id,
        'title': (item['title'] ?? '').toString(),
        'subjectTitle': (item['title'] ?? '').toString(),
        'subjectType': isMovie ? 1 : 2,
        'year': (item['year'] ?? '').toString(),
        'releaseDate': (item['year'] ?? '').toString(),
        'cover': posterUrl,
        'poster_path': posterUrl,
        'backdrop_path': posterUrl,
        'category': item['category'],
        'provider': 'dramachi',
      });
    }

    return results;
  }

  /// Get Homepage items (featured Asian dramas and anime)
  Future<Map<String, dynamic>> getHomepage({int page = 1}) async {
    try {
      final results = await search('drama', page: page);
      return {
        'code': 0,
        'list': results,
        'data': {
          'operating_list': [
            {
              'title': 'Dramachi Trending Dramas',
              'movies': results,
            }
          ]
        }
      };
    } catch (_) {
      return {'code': 0, 'list': [], 'data': {'operating_list': []}};
    }
  }

  /// Fetch title details, seasons, and available audio dub versions
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    final rawId = subjectId.replaceFirst('dramachi_', '').trim();
    final parts = rawId.split('::');
    final titleId = parts[0].trim();
    final targetDubRip = parts.length > 1 ? parts[1].trim() : null;

    if (titleId.isEmpty) {
      throw Exception("Invalid Dramachi subjectId");
    }

    final response = await _getSafe((base) =>
        Uri.parse("$base?interface=title_v2&id=${Uri.encodeComponent(titleId)}"));
    if (response.statusCode != 200) {
      throw Exception("Failed to load Dramachi details (${response.statusCode})");
    }

    final Map<String, dynamic> data = jsonDecode(response.body);
    final albumList = (data['album'] as List<dynamic>?) ?? [];
    if (albumList.isEmpty || albumList.first is! Map) {
      throw Exception("Dramachi media not found");
    }

    final album = albumList.first as Map<String, dynamic>;
    final isMovie = (album['content']?.toString().toLowerCase() ?? '') == 'movies' ||
        (album['content']?.toString().toLowerCase() ?? '') == 'movie';

    final thumb = (album['thumb'] ?? '').toString().trim();
    final posterUrl = thumb.isNotEmpty ? "$IMAGE_CDN_BASE$thumb" : null;

    final rawGenres = (album['genres'] ?? '').toString();
    final genresList = rawGenres
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final castRaw = (data['cast'] as List<dynamic>?) ?? [];
    final List<Map<String, dynamic>> castList = [];
    for (final c in castRaw) {
      if (c is Map && c['name'] != null) {
        castList.add({
          'name': c['name'].toString(),
          'character': c['role']?.toString() ?? '',
          'profile_path': null,
        });
      }
    }

    // Process seasons and dubs
    final seasonsMap = (data['seasons'] is Map)
        ? (data['seasons'] as Map<String, dynamic>)
        : <String, dynamic>{};

    final List<Map<String, dynamic>> dubsList = [];
    final List<String> sortedSeasonKeys = seasonsMap.keys.toList()
      ..sort((a, b) => (extractLeadingSeasonNumber(a) ?? 999).compareTo(extractLeadingSeasonNumber(b) ?? 999));

    for (final seasonKey in seasonsMap.keys) {
      final group = seasonsMap[seasonKey];
      if (group is Map && group['versions'] is List) {
        for (final v in group['versions']) {
          if (v is Map) {
            final rip = (v['rip'] ?? '').toString();
            final vName = (v['version_name'] ?? '').toString();
            final label = seasonsMap.length > 1 ? "$seasonKey: $vName" : vName;
            final compId = "$titleId::$rip";
            dubsList.add({
              'subjectId': compId,
              'id': compId,
              'lanName': vName,
              'rip': rip,
              'label': label,
              'original': vName.toLowerCase().contains('original') || vName.toLowerCase() == 'orig',
            });
          }
        }
      }
    }

    // Sort dubs: Original > English > Dub > others
    dubsList.sort((a, b) {
      int priority(String s) {
        final l = s.toLowerCase();
        if (l.contains('original') || l == 'orig') return 0;
        if (l.contains('english') || l.contains('eng')) return 1;
        if (l.contains('dub')) return 2;
        return 3;
      }
      return priority(a['lanName'] ?? '').compareTo(priority(b['lanName'] ?? ''));
    });

    // Fetch episodes for all seasons in parallel
    final List<Map<String, dynamic>> seasonsList = [];
    if (!isMovie) {
      for (final key in sortedSeasonKeys) {
        final group = seasonsMap[key];
        String? ripForSeason;
        if (group is Map && group['versions'] is List) {
          final versions = group['versions'] as List;
          if (targetDubRip != null) {
            for (final v in versions) {
              if (v is Map && v['rip'] == targetDubRip) {
                ripForSeason = v['rip']?.toString();
                break;
              }
            }
          }
          if (ripForSeason == null && versions.isNotEmpty && versions.first is Map) {
            ripForSeason = versions.first['rip']?.toString();
          }
        }
        ripForSeason ??= key;

        final seasonNum = extractLeadingSeasonNumber(key) ?? 1;
        final episodes = await fetchEpisodes(titleId, ripForSeason);

        final Set<int> seenEpNums = {};
        final List<Map<String, dynamic>> uniqueEps = [];
        for (int i = 0; i < episodes.length; i++) {
          final ep = episodes[i];
          final fTitle = (ep['f_title'] ?? ep['title'] ?? '').toString();
          final epNum = parseEpisodeNumber(fTitle) ?? (i + 1);
          if (seenEpNums.add(epNum)) {
            uniqueEps.add({
              'se': seasonNum,
              'ep': epNum,
              'title': cleanEpisodeTitle(fTitle),
              'f_title': fTitle,
              'fid': ep['fid'],
              'disk': ep['disk'],
              'quality': ep['quality'],
              'size': ep['size'],
            });
          }
        }
        uniqueEps.sort((a, b) => (a['ep'] as int).compareTo(b['ep'] as int));

        seasonsList.add({
          'se': seasonNum,
          'season_number': seasonNum,
          'name': key,
          'maxEp': uniqueEps.isNotEmpty ? uniqueEps.length : 1,
          'episodes': uniqueEps,
          'rip': ripForSeason,
        });
      }
    }

    if (seasonsList.isEmpty && !isMovie) {
      seasonsList.add({
        'se': 1,
        'season_number': 1,
        'name': 'Season 1',
        'maxEp': 1,
        'episodes': [
          {'se': 1, 'ep': 1, 'title': 'Episode 1'}
        ],
      });
    }

    final resolvedSubjectId = targetDubRip != null ? "$titleId::$targetDubRip" : titleId;

    return {
      'id': resolvedSubjectId,
      'subjectId': resolvedSubjectId,
      'title': album['title'] ?? '',
      'subjectTitle': album['title'] ?? '',
      'name': album['title'] ?? '',
      'subjectType': isMovie ? 1 : 2,
      'year': album['year'] ?? '',
      'releaseDate': album['year'] ?? '',
      'description': album['storyline'] ?? album['content'] ?? '',
      'overview': album['storyline'] ?? album['content'] ?? '',
      'director': album['director'] ?? '',
      'genres': genresList,
      'cover': posterUrl,
      'poster_path': posterUrl,
      'backdrop_path': posterUrl,
      'cast': castList,
      'dubs': dubsList,
      'seasons': seasonsList,
      'provider': 'dramachi',
    };
  }

  /// Fetch episode list for a specific title and rip/season
  Future<List<Map<String, dynamic>>> fetchEpisodes(String titleId, String rip) async {
    try {
      final response = await _getSafe((base) => Uri.parse(
        "$base?interface=eplist&season=${Uri.encodeComponent(rip)}&id=${Uri.encodeComponent(titleId)}",
      ));
      if (response.statusCode != 200) return [];
      final Map<String, dynamic> data = jsonDecode(response.body);
      final list = (data['episode_list'] as List<dynamic>?) ?? [];
      return list.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Resolve direct HTTP byte-range stream from fid and disk index
  Future<Map<String, dynamic>?> fetchFileStream(String fid, String disk) async {
    try {
      final response = await _getSafe((base) => Uri.parse(
        "$base?interface=getFile&fid=${Uri.encodeComponent(fid)}&findex=${Uri.encodeComponent(disk)}",
      ));
      if (response.statusCode != 200) return null;

      final Map<String, dynamic> data = jsonDecode(response.body);
      final hostInfo = data['hostInfo'] is Map ? data['hostInfo'] as Map<String, dynamic> : null;
      final fileInfoList = (data['fileInfo'] as List<dynamic>?) ?? [];
      if (hostInfo == null || fileInfoList.isEmpty || fileInfoList.first is! Map) {
        return null;
      }

      final fileInfo = fileInfoList.first as Map<String, dynamic>;
      final rawUrl = (fileInfo['url'] ?? '').toString().trim();
      if (rawUrl.isEmpty) return null;

      final host = (hostInfo['host'] ?? '').toString().trim().replaceAll(RegExp(r'/+$'), '');
      final cleanPath = rawUrl.replaceAll(RegExp(r'^/+'), '');
      final streamUrl = "https://$host/cdn/$cleanPath";

      final filename = (fileInfo['filename'] ?? fileInfo['f_title'] ?? "$fid.mkv").toString();

      return {
        'streamUrl': streamUrl,
        'filename': filename,
        'fileInfo': fileInfo,
      };
    } catch (e) {
      print("Dramachi fetchFileStream error for fid $fid: $e");
      return null;
    }
  }

  /// Get Streaming video resources for a title and episode
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
  }) async {
    final rawId = subjectId.replaceFirst('dramachi_', '').trim();
    final parts = rawId.split('::');
    final titleId = parts[0].trim();
    var ripToQuery = parts.length > 1 ? parts[1].trim() : null;

    if (ripToQuery == null || ripToQuery.isEmpty) {
      // Query details to find rip for target season
      try {
        final details = await getDetails(subjectId: titleId);
        final seasons = details['seasons'] as List? ?? [];
        for (final s in seasons) {
          if (s is Map && (s['se'] == se || se == 0)) {
            ripToQuery = s['rip']?.toString();
            break;
          }
        }
      } catch (_) {}
      ripToQuery ??= se > 0 ? "Season ${se.toString().padLeft(2, '0')}" : "hd Rip";
    }

    final episodes = await fetchEpisodes(titleId, ripToQuery);
    if (episodes.isEmpty) {
      return {'code': 0, 'list': [], 'data': {'list': []}};
    }

    // Match episode
    List<Map<String, dynamic>> matchedItems = [];
    if (se == 0 && ep == 0) {
      matchedItems = episodes;
    } else {
      final exact = episodes.where((e) => parseEpisodeNumber((e['f_title'] ?? '').toString()) == ep).toList();
      if (exact.isNotEmpty) {
        matchedItems = exact;
      } else if (ep > 0 && ep <= episodes.length) {
        matchedItems = [episodes[ep - 1]];
      }
    }

    final List<Map<String, dynamic>> releases = [];

    // Resolve streams in parallel
    final futures = matchedItems.map((item) async {
      final fid = (item['fid'] ?? '').toString();
      final disk = (item['disk'] ?? '').toString();
      if (fid.isEmpty || disk.isEmpty) return null;

      final res = await fetchFileStream(fid, disk);
      if (res == null) return null;

      final streamUrl = res['streamUrl'] as String;
      final filename = res['filename'] as String;
      final qStr = (item['quality'] ?? '').toString();
      final qInt = parseQualityInt(qStr.isNotEmpty ? qStr : filename);
      final sizeStr = (item['size'] ?? '').toString();
      final sizeBytes = parseSizeToBytes(sizeStr);

      return {
        'resourceId': fid,
        'resourceLink': streamUrl,
        'resource_link': streamUrl,
        'url': streamUrl,
        'resolution': qInt,
        'quality': qStr.isNotEmpty ? qStr : "${qInt}p",
        'size': sizeBytes,
        'fileName': filename,
        'direct_file': true,
        'provider': 'dramachi',
        'headers': <String, String>{},
        'se': se,
        'ep': ep,
      };
    }).toList();

    final resolved = await Future.wait(futures);
    for (final r in resolved) {
      if (r != null) releases.add(r);
    }

    // Deduplicate and sort by resolution descending, then size descending
    final seenUrls = <String>{};
    final List<Map<String, dynamic>> deduped = [];
    for (final r in releases) {
      final url = r['url']?.toString() ?? '';
      if (url.isNotEmpty && seenUrls.add(url)) {
        deduped.add(r);
      }
    }

    deduped.sort((a, b) {
      final resA = (a['resolution'] as int?) ?? 0;
      final resB = (b['resolution'] as int?) ?? 0;
      if (resB != resA) return resB.compareTo(resA);
      final sizeA = (a['size'] as int?) ?? 0;
      final sizeB = (b['size'] as int?) ?? 0;
      return sizeB.compareTo(sizeA);
    });

    return {
      'code': 0,
      'message': 'ok',
      'list': deduped,
      'data': {'list': deduped},
    };
  }
}

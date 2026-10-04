import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AllMovielandApiService {
  static final AllMovielandApiService _instance = AllMovielandApiService._internal();
  factory AllMovielandApiService() => _instance;
  AllMovielandApiService._internal();

  static const String playerScriptUrl = "https://allmovieland.link/player.js?v=60%20128";
  static const String fallbackHost = "https://slast430did.com";
  static const String defaultReferer = "https://allmovieland.fun/";
  static const String userAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  String? _cachedHost;
  DateTime? _hostExpiry;

  /// Cache for media playlist data by IMDb ID (5 minutes)
  final Map<String, _MediaCacheEntry> _mediaCache = {};

  /// Dynamically discover the active streaming backend domain from player.js
  Future<String> getHost() async {
    if (_cachedHost != null && _hostExpiry != null && DateTime.now().isBefore(_hostExpiry!)) {
      return _cachedHost!;
    }

    try {
      final response = await http.get(
        Uri.parse(playerScriptUrl),
        headers: {
          'User-Agent': userAgent,
          'Referer': defaultReferer,
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final match = RegExp(r'''const\s+AwsIndStreamDomain\s*=\s*['"]([^'"]+)['"]''')
            .firstMatch(response.body);
        if (match != null) {
          final host = match.group(1)?.trim();
          if (host != null && host.startsWith('http')) {
            _cachedHost = host;
            _hostExpiry = DateTime.now().add(const Duration(hours: 1));
            return host;
          }
        }
      }
    } catch (e) {
      debugPrint("AllMovieland getHost error: $e");
    }

    // Fallback to known live host
    _cachedHost ??= fallbackHost;
    return _cachedHost!;
  }

  /// Retrieve raw media servers and CSRF key for a given IMDb ID
  Future<Map<String, dynamic>?> getMediaData(String imdbId) async {
    final cleanId = imdbId.trim();
    if (!cleanId.startsWith("tt")) return null;

    final cached = _mediaCache[cleanId];
    if (cached != null && DateTime.now().isBefore(cached.expiry)) {
      return cached.data;
    }

    try {
      final host = await getHost();
      final playUrl = Uri.parse("$host/play/$cleanId");

      final playResp = await http.get(
        playUrl,
        headers: {
          'User-Agent': userAgent,
          'Referer': defaultReferer,
        },
      ).timeout(const Duration(seconds: 10));

      if (playResp.statusCode != 200) {
        return null;
      }

      final body = playResp.body;
      final scriptMatch = RegExp(r"<script[^>]*>([\s\S]*?)<\/script>").allMatches(body);

      String? p3JsonStr;
      for (final sm in scriptMatch) {
        final scriptContent = sm.group(1) ?? "";
        if (scriptContent.contains("playlist") || scriptContent.contains("player-") || scriptContent.contains('"key"')) {
          final firstBrace = scriptContent.indexOf('{');
          final lastBrace = scriptContent.lastIndexOf('}');
          if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
            p3JsonStr = scriptContent.substring(firstBrace, lastBrace + 1);
            break;
          }
        }
      }

      if (p3JsonStr == null) return null;

      final Map<String, dynamic> p3Data = jsonDecode(p3JsonStr);
      final rawFile = p3Data['file']?.toString();
      final key = p3Data['key']?.toString();

      if (rawFile == null || key == null) return null;

      final fileUrlStr = rawFile.startsWith("http") ? rawFile : "$host$rawFile";

      final fileResp = await http.get(
        Uri.parse(fileUrlStr),
        headers: {
          'User-Agent': userAgent,
          'Referer': defaultReferer,
          'X-CSRF-TOKEN': key,
        },
      ).timeout(const Duration(seconds: 10));

      if (fileResp.statusCode != 200) return null;

      String cleanJson = fileResp.body
          .replaceAll(RegExp(r',\s*\]'), ']')
          .replaceAll(RegExp(r',\s*\}'), '}');

      final dynamic decoded = jsonDecode(cleanJson);
      if (decoded is! List) return null;

      final result = {
        'host': host,
        'key': key,
        'servers': decoded,
      };

      _mediaCache[cleanId] = _MediaCacheEntry(
        data: result,
        expiry: DateTime.now().add(const Duration(minutes: 10)),
      );

      return result;
    } catch (e) {
      debugPrint("AllMovieland getMediaData error for $imdbId: $e");
      return null;
    }
  }

  /// Check if media is available on AllMovieland
  Future<bool> checkAvailability(String imdbId) async {
    final data = await getMediaData(imdbId);
    return data != null && (data['servers'] as List).isNotEmpty;
  }

  /// Get season info for a TV show on AllMovieland
  Future<List<Map<String, dynamic>>> getSeasons(String imdbId) async {
    final data = await getMediaData(imdbId);
    if (data == null) return [];

    final servers = data['servers'] as List<dynamic>;
    final List<Map<String, dynamic>> seasons = [];

    for (final s in servers) {
      if (s is! Map) continue;
      final seId = int.tryParse(s['id']?.toString() ?? '') ?? seasons.length + 1;
      final sTitle = (s['title'] ?? 'Season $seId').toString();
      final folders = s['folder'] as List<dynamic>? ?? [];

      final List<Map<String, dynamic>> epList = [];
      for (int i = 0; i < folders.length; i++) {
        final ep = folders[i];
        if (ep is! Map) continue;
        final epNum = int.tryParse(ep['episode']?.toString() ?? '') ?? (i + 1);
        final epTitle = (ep['title'] ?? 'Episode $epNum').toString();
        epList.add({
          'se': seId,
          'ep': epNum,
          'title': epTitle,
          'tracks': ep['folder'] ?? [],
        });
      }

      seasons.add({
        'se': seId,
        'season_number': seId,
        'name': sTitle,
        'maxEp': epList.isNotEmpty ? epList.length : 1,
        'episodes': epList,
      });
    }

    return seasons;
  }

  /// Get Streaming video resources for a title (Movie or TV Episode)
  Future<Map<String, dynamic>> getResources({
    required String imdbId,
    int se = 0,
    int ep = 0,
    String? title,
  }) async {
    final mediaData = await getMediaData(imdbId);
    if (mediaData == null) {
      return {'code': 0, 'list': [], 'data': {'list': []}};
    }

    final String host = mediaData['host'];
    final String key = mediaData['key'];
    final List<dynamic> servers = mediaData['servers'];

    List<Map<String, dynamic>> targetTracks = [];

    if (se == 0 && ep == 0) {
      // Movie: servers list directly contains audio tracks
      for (final item in servers) {
        if (item is Map && item['file'] != null) {
          targetTracks.add(Map<String, dynamic>.from(item));
        }
      }
    } else {
      // TV Series: Season -> Episode -> Audio Tracks
      Map<String, dynamic>? matchedSeason;
      for (final s in servers) {
        if (s is Map && (s['id']?.toString() == "$se" || s['title']?.toString().contains("$se") == true)) {
          matchedSeason = Map<String, dynamic>.from(s);
          break;
        }
      }
      matchedSeason ??= servers.isNotEmpty && servers.first is Map
          ? Map<String, dynamic>.from(servers.first)
          : null;

      if (matchedSeason != null) {
        final episodeFolders = (matchedSeason['folder'] as List?) ?? [];
        Map<String, dynamic>? matchedEp;
        for (final e in episodeFolders) {
          if (e is Map &&
              (e['episode']?.toString() == "$ep" ||
                  e['id']?.toString() == "$se-$ep" ||
                  e['title']?.toString().contains("$ep") == true)) {
            matchedEp = Map<String, dynamic>.from(e);
            break;
          }
        }

        if (matchedEp != null) {
          final tracks = (matchedEp['folder'] as List?) ?? [];
          for (final t in tracks) {
            if (t is Map && t['file'] != null) {
              targetTracks.add(Map<String, dynamic>.from(t));
            }
          }
        }
      }
    }

    if (targetTracks.isEmpty) {
      return {'code': 0, 'list': [], 'data': {'list': []}};
    }

    // Resolve M3U8 URLs for each audio track in parallel
    final resolvedStreams = await Future.wait(targetTracks.map((track) async {
      final trackFile = track['file']?.toString();
      if (trackFile == null || trackFile.isEmpty) return null;

      try {
        final postUrl = Uri.parse("$host/playlist/$trackFile.txt");
        final postResp = await http.post(
          postUrl,
          headers: {
            'User-Agent': userAgent,
            'Referer': defaultReferer,
            'X-CSRF-TOKEN': key,
          },
        ).timeout(const Duration(seconds: 8));

        if (postResp.statusCode == 200) {
          final m3u8Url = postResp.body.trim();
          if (m3u8Url.startsWith("http")) {
            final audioTitle = (track['title'] ?? 'Original Audio').toString();
            final trackId = (track['id'] ?? 'aml_${se}_${ep}_$audioTitle').toString();
            final displayTitle = title != null && title.isNotEmpty ? title : "Media";

            return {
              'resourceId': trackId,
              'resourceLink': m3u8Url,
              'resource_link': m3u8Url,
              'url': m3u8Url,
              'resolution': 1080,
              'quality': '1080p (HLS)',
              'audio': audioTitle,
              'audioName': audioTitle,
              'language': audioTitle,
              'fileName': se > 0 ? "$displayTitle - S${se}E$ep [$audioTitle].m3u8" : "$displayTitle [$audioTitle].m3u8",
              'direct_file': false,
              'isHls': true,
              'provider': 'allmovieland',
              'headers': <String, String>{
                'User-Agent': userAgent,
                'Referer': defaultReferer,
              },
              'se': se,
              'ep': ep,
            };
          }
        }
      } catch (e) {
        debugPrint("Failed to resolve M3U8 for track ${track['title']}: $e");
      }
      return null;
    }));

    final List<Map<String, dynamic>> validStreams =
        resolvedStreams.whereType<Map<String, dynamic>>().toList();

    // Prioritize audio tracks:
    // 1. Original / Korean / Native audio tracks
    // 2. English dub/audio
    // 3. Other regional dubs (Hindi, Russian, etc.)
    validStreams.sort((a, b) {
      final nameA = (a['audioName'] ?? '').toString().toLowerCase();
      final nameB = (b['audioName'] ?? '').toString().toLowerCase();

      int score(String n) {
        if (n.contains('orig') || n.contains('korean') || n.contains('корейский')) return 3;
        if (n.contains('eng') || n.contains('английский')) return 2;
        return 1;
      }

      return score(nameB).compareTo(score(nameA));
    });

    return {
      'code': 0,
      'list': validStreams,
      'data': {'list': validStreams},
    };
  }

  /// Convenience wrapper to get streams list directly
  Future<List<Map<String, dynamic>>> getStreams({
    required String imdbId,
    int season = 0,
    int episode = 0,
    String? title,
  }) async {
    final res = await getResources(imdbId: imdbId, se: season, ep: episode, title: title);
    final list = res['list'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
}

class _MediaCacheEntry {
  final Map<String, dynamic> data;
  final DateTime expiry;
  _MediaCacheEntry({required this.data, required this.expiry});
}

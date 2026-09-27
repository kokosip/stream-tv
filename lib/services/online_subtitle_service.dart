import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'remote_config_service.dart';
import 'tmdb_service.dart';

class OnlineSubtitleItem {
  final String id;
  final String lang;
  final String languageName;
  final String fileName;
  final String releaseName;
  final String url;
  final int season;
  final int episode;
  final String source; // 'OpenSubtitles' or 'SubDL'
  final String? author;

  const OnlineSubtitleItem({
    required this.id,
    required this.lang,
    required this.languageName,
    required this.fileName,
    required this.releaseName,
    required this.url,
    this.season = 0,
    this.episode = 0,
    this.source = 'OpenSubtitles',
    this.author,
  });

  factory OnlineSubtitleItem.fromJson(
    Map<String, dynamic> json, {
    String? mediaTitle,
    int? defaultSeason,
    int? defaultEpisode,
  }) {
    return OnlineSubtitleItem.fromOpenSubtitles(
      json,
      mediaTitle: mediaTitle,
      defaultSeason: defaultSeason,
      defaultEpisode: defaultEpisode,
    );
  }

  factory OnlineSubtitleItem.fromOpenSubtitles(
    Map<String, dynamic> json, {
    String? mediaTitle,
    int? defaultSeason,
    int? defaultEpisode,
  }) {
    final rawLang = (json['lang'] ?? '').toString().trim().toLowerCase();
    final langName = OnlineSubtitleService.normalizeLanguageCode(rawLang);
    final rawFileName = (json['subtitleFileName'] ?? json['file'] ?? '').toString().trim();
    final release = (json['movieReleaseName'] ?? json['release'] ?? json['releaseFormat'] ?? '').toString().trim();
    final url = (json['url'] ?? '').toString().trim();
    final id = (json['id'] ?? '').toString();
    final season = json['season'] is int
        ? json['season'] as int
        : int.tryParse(json['season']?.toString() ?? '') ?? defaultSeason ?? 0;
    final episode = json['episode'] is int
        ? json['episode'] as int
        : int.tryParse(json['episode']?.toString() ?? '') ?? defaultEpisode ?? 0;

    // MovieBox-TUI Clean Subtitles: Title - S01E01.srt
    String cleanName = rawFileName;
    if (mediaTitle != null && mediaTitle.trim().isNotEmpty) {
      final title = mediaTitle.trim();
      if (season > 0 && episode > 0) {
        cleanName = "$title - S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}.srt";
      } else if (!cleanName.toLowerCase().endsWith('.srt') && !cleanName.toLowerCase().endsWith('.vtt')) {
        cleanName = "$title.srt";
      }
    }
    if (cleanName.isEmpty) {
      cleanName = "Subtitle_${rawLang.toUpperCase()}.srt";
    }

    return OnlineSubtitleItem(
      id: id,
      lang: rawLang,
      languageName: langName,
      fileName: cleanName,
      releaseName: release.isNotEmpty ? release : (rawFileName.isNotEmpty ? rawFileName : "Standard"),
      url: url,
      season: season,
      episode: episode,
      source: 'OpenSubtitles',
    );
  }

  factory OnlineSubtitleItem.fromSubdl(
    Map<String, dynamic> json, {
    String? mediaTitle,
    int? defaultSeason,
    int? defaultEpisode,
  }) {
    final rawLang = (json['language'] ?? json['lang'] ?? '').toString().trim().toLowerCase();
    final langName = OnlineSubtitleService.normalizeLanguageCode(rawLang);
    final rawFileName = (json['name'] ?? '').toString().trim();
    final release = (json['release_name'] ?? '').toString().trim();
    final path = (json['url'] ?? '').toString().trim();
    final author = (json['author'] ?? '').toString().trim();
    final url = path.startsWith('http') ? path : "https://dl.subdl.com$path";
    final id = (json['subtitlePage'] ?? json['url'] ?? '').toString();
    final season = json['season'] is int
        ? json['season'] as int
        : int.tryParse(json['season']?.toString() ?? '') ?? defaultSeason ?? 0;
    final episode = json['episode'] is int
        ? json['episode'] as int
        : int.tryParse(json['episode']?.toString() ?? '') ?? defaultEpisode ?? 0;

    String cleanName = rawFileName;
    if (mediaTitle != null && mediaTitle.trim().isNotEmpty) {
      final title = mediaTitle.trim();
      if (season > 0 && episode > 0) {
        cleanName = "$title - S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}.srt";
      } else if (!cleanName.toLowerCase().endsWith('.srt') && !cleanName.toLowerCase().endsWith('.vtt')) {
        cleanName = "$title.srt";
      }
    }
    if (cleanName.isEmpty) {
      cleanName = "Subtitle_${rawLang.toUpperCase()}.srt";
    }

    return OnlineSubtitleItem(
      id: id,
      lang: rawLang,
      languageName: langName,
      fileName: cleanName,
      releaseName: release.isNotEmpty ? release : (rawFileName.isNotEmpty ? rawFileName : "Standard"),
      url: url,
      season: season,
      episode: episode,
      source: 'SubDL',
      author: author.isNotEmpty ? author : null,
    );
  }
}

class OnlineSubtitleService {
  static final OnlineSubtitleService _instance = OnlineSubtitleService._internal();
  factory OnlineSubtitleService() => _instance;
  OnlineSubtitleService._internal();

  static const String _openSubtitlesBase = "https://opensubtitles-v3.strem.io/subtitles";

  /// Normalizes 2-letter or 3-letter ISO language code to human-friendly display name
  static String normalizeLanguageCode(String code) {
    final lower = code.trim().toLowerCase();
    switch (lower) {
      case 'ind':
      case 'id':
      case 'ina':
      case 'indonesian':
        return 'Indonesian';
      case 'eng':
      case 'en':
      case 'english':
        return 'English';
      case 'spa':
      case 'es':
      case 'spanish':
        return 'Spanish';
      case 'pob':
      case 'por':
      case 'pt':
      case 'portuguese':
        return 'Portuguese';
      case 'ara':
      case 'ar':
      case 'arabic':
        return 'Arabic';
      case 'fre':
      case 'fra':
      case 'fr':
      case 'french':
        return 'French';
      case 'ger':
      case 'deu':
      case 'de':
      case 'german':
        return 'German';
      case 'ita':
      case 'it':
      case 'italian':
        return 'Italian';
      case 'jpn':
      case 'ja':
      case 'japanese':
        return 'Japanese';
      case 'kor':
      case 'ko':
      case 'korean':
        return 'Korean';
      case 'zh':
      case 'chi':
      case 'zho':
      case 'chinese':
        return 'Chinese';
      case 'rus':
      case 'ru':
      case 'russian':
        return 'Russian';
      case 'tha':
      case 'th':
      case 'thai':
        return 'Thai';
      case 'vie':
      case 'vi':
      case 'vietnamese':
        return 'Vietnamese';
      case 'ms':
      case 'may':
      case 'msa':
      case 'malay':
        return 'Malay';
      case 'fil':
      case 'tgl':
      case 'tl':
      case 'filipino':
        return 'Filipino';
      case 'hin':
      case 'hi':
      case 'hindi':
        return 'Hindi';
      case 'tur':
      case 'tr':
      case 'turkish':
        return 'Turkish';
      case 'nld':
      case 'nl':
      case 'dutch':
        return 'Dutch';
      default:
        return code.toUpperCase();
    }
  }

  /// Clean query string to extract clean movie/show title (remove quality badges, season tags, etc.)
  static String cleanSearchQuery(String query) {
    var cleaned = query;
    // Remove "S1:E1" or "S01E01" or "• S1 E1" patterns
    cleaned = cleaned.replaceAll(RegExp(r'[•\-]?\s*S\d+\s*[:E]\s*\d+', caseSensitive: false), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\b(season|episode)\s*\d+\b', caseSensitive: false), ' ');
    // Remove quality & source tags
    cleaned = cleaned.replaceAll(RegExp(r'\b(4k|uhd|1080p|720p|480p|bluray|bdrip|web-?dl|hdrip|cam|x264|x265|hevc)\b', caseSensitive: false), ' ');
    // Remove brackets and parentheses
    cleaned = cleaned.replaceAll(RegExp(r'[\[\]\(\)]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();
    return cleaned.isNotEmpty ? cleaned : query;
  }

  /// Resolve a title to an IMDb ID via TMDB Search & External IDs
  Future<String?> resolveImdbId({
    required String title,
    bool isTv = false,
    int? releaseYear,
  }) async {
    final cleanTitle = cleanSearchQuery(title);
    if (cleanTitle.isEmpty) return null;

    try {
      // 1. Search TMDB
      final searchEndpoint = isTv ? "/search/tv" : "/search/movie";
      final params = <String, String>{"query": cleanTitle};
      if (releaseYear != null && releaseYear > 1900) {
        params[isTv ? "first_air_date_year" : "primary_release_year"] = releaseYear.toString();
      }

      final uri = Uri.parse("${TmdbService.baseUrl}$searchEndpoint").replace(
        queryParameters: {
          "api_key": TmdbService.apiKey,
          "include_adult": "false",
          ...params,
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final results = decoded['results'] as List? ?? [];
        if (results.isEmpty) {
          // Fallback to multi search if specific endpoint was empty
          return _fallbackMultiSearch(cleanTitle);
        }

        final top = results.first as Map<String, dynamic>;
        final int tmdbId = top['id'] as int;

        // 2. Fetch external IDs from TMDB
        return await _fetchImdbFromTmdb(tmdbId, isTv: isTv);
      }
    } catch (e) {
      debugPrint("Failed to resolve IMDb ID via TMDB: $e");
    }

    return _fallbackMultiSearch(cleanTitle);
  }

  Future<String?> _fetchImdbFromTmdb(int tmdbId, {required bool isTv}) async {
    try {
      final extUri = Uri.parse("${TmdbService.baseUrl}/${isTv ? 'tv' : 'movie'}/$tmdbId/external_ids").replace(
        queryParameters: {
          "api_key": TmdbService.apiKey,
        },
      );

      final res = await http.get(extUri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final imdbId = decoded['imdb_id']?.toString().trim();
        if (imdbId != null && imdbId.startsWith('tt')) {
          return imdbId;
        }
      }
    } catch (e) {
      debugPrint("Error fetching external_ids: $e");
    }
    return null;
  }

  Future<String?> _fallbackMultiSearch(String query) async {
    try {
      final uri = Uri.parse("${TmdbService.baseUrl}/search/multi").replace(
        queryParameters: {
          "api_key": TmdbService.apiKey,
          "query": query,
          "include_adult": "false",
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final results = decoded['results'] as List? ?? [];
        for (final item in results) {
          if (item is Map) {
            final mediaType = item['media_type']?.toString();
            final tmdbId = item['id'];
            if (tmdbId is int && (mediaType == 'movie' || mediaType == 'tv')) {
              final imdb = await _fetchImdbFromTmdb(tmdbId, isTv: mediaType == 'tv');
              if (imdb != null && imdb.isNotEmpty) return imdb;
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Fallback multi-search error: $e");
    }
    return null;
  }

  static const String _subdlApiBase = "https://api.subdl.com/api/v1/subtitles";
  static int _subdlActiveKeyIndex = 0;
  static final Map<String, DateTime> _subdlExhaustedKeys = {};

  /// Search SubDL subtitles by IMDb ID with multi-key failover support
  Future<List<OnlineSubtitleItem>> searchSubdl({
    required String imdbId,
    required String query,
    int season = 0,
    int episode = 0,
    String? languageFilter,
  }) async {
    final pool = RemoteConfigService.instance.subdlApiKeyPool;
    if (pool.isEmpty) return [];

    // Filter out keys marked exhausted within the last 2 hours (unless all are exhausted)
    final now = DateTime.now();
    final availableKeys = pool.where((key) {
      final exhaustedAt = _subdlExhaustedKeys[key];
      if (exhaustedAt == null) return true;
      if (now.difference(exhaustedAt) > const Duration(hours: 2)) {
        _subdlExhaustedKeys.remove(key);
        return true;
      }
      return false;
    }).toList();

    final candidateKeys = availableKeys.isNotEmpty ? availableKeys : pool;

    // Start with currently active key index if valid, else 0
    final startIndex = candidateKeys.indexOf(pool[_subdlActiveKeyIndex % pool.length]);
    final orderedKeys = <String>[];
    if (startIndex >= 0) {
      for (int i = 0; i < candidateKeys.length; i++) {
        orderedKeys.add(candidateKeys[(startIndex + i) % candidateKeys.length]);
      }
    } else {
      orderedKeys.addAll(candidateKeys);
    }

    final isTv = (season > 0 || episode > 0);
    final baseParams = <String, String>{
      "imdb_id": imdbId,
      "type": isTv ? "tv" : "movie",
    };
    if (isTv && season > 0) {
      baseParams["season_number"] = season.toString();
    }
    if (isTv && episode > 0) {
      baseParams["episode_number"] = episode.toString();
    }
    if (languageFilter != null && languageFilter.isNotEmpty && languageFilter.toLowerCase() != 'all') {
      final code = languageFilter.toLowerCase();
      if (code == 'ind' || code == 'id') {
        baseParams["languages"] = "ID";
      } else if (code == 'eng' || code == 'en') {
        baseParams["languages"] = "EN";
      } else {
        baseParams["languages"] = languageFilter.toUpperCase();
      }
    }

    for (int i = 0; i < orderedKeys.length; i++) {
      final apiKey = orderedKeys[i];
      try {
        final params = Map<String, String>.from(baseParams);
        params["api_key"] = apiKey;

        final uri = Uri.parse(_subdlApiBase).replace(queryParameters: params);
        final res = await http.get(uri).timeout(const Duration(seconds: 10));

        // Detect quota / rate limit exhaustion
        final isQuotaError = res.statusCode == 429 ||
            (res.statusCode == 403 && res.body.toLowerCase().contains('limit')) ||
            (res.statusCode == 200 && res.body.toLowerCase().contains('daily limit'));

        if (isQuotaError) {
          debugPrint("SubDL API Key (ending in ...${apiKey.length > 6 ? apiKey.substring(apiKey.length - 6) : apiKey}) exhausted daily limit. Switching to next key...");
          _subdlExhaustedKeys[apiKey] = DateTime.now();
          final poolIdx = pool.indexOf(apiKey);
          if (poolIdx >= 0 && pool.length > 1) {
            _subdlActiveKeyIndex = (poolIdx + 1) % pool.length;
          }
          continue;
        }

        if (res.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
          final rawList = decoded['subtitles'] as List? ?? [];
          final List<OnlineSubtitleItem> items = [];

          for (final item in rawList) {
            if (item is Map<String, dynamic>) {
              final subItem = OnlineSubtitleItem.fromSubdl(
                item,
                mediaTitle: query,
                defaultSeason: season,
                defaultEpisode: episode,
              );
              if (subItem.url.isNotEmpty) {
                if (languageFilter == null || languageFilter.isEmpty || languageFilter.toLowerCase() == 'all') {
                  items.add(subItem);
                } else if (subItem.lang == languageFilter.toLowerCase() ||
                           subItem.languageName.toLowerCase() == languageFilter.toLowerCase()) {
                  items.add(subItem);
                }
              }
            }
          }

          // Remember this working key as the active key
          final poolIdx = pool.indexOf(apiKey);
          if (poolIdx >= 0) {
            _subdlActiveKeyIndex = poolIdx;
          }

          return items;
        }
      } catch (e) {
        debugPrint("Error trying SubDL key (index $i): $e");
        if (i < orderedKeys.length - 1) continue;
      }
    }

    return [];
  }

  /// Search OpenSubtitles helper
  Future<List<OnlineSubtitleItem>> _searchOpenSubtitles({
    required String imdbId,
    required String query,
    int season = 0,
    int episode = 0,
    String? languageFilter,
  }) async {
    try {
      final isTv = (season > 0 || episode > 0);
      final endpoint = isTv
          ? "$_openSubtitlesBase/series/$imdbId:${season > 0 ? season : 1}:${episode > 0 ? episode : 1}.json"
          : "$_openSubtitlesBase/movie/$imdbId.json";

      final res = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final rawList = decoded['subtitles'] as List? ?? [];
        final List<OnlineSubtitleItem> items = [];

        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final subItem = OnlineSubtitleItem.fromOpenSubtitles(
              item,
              mediaTitle: query,
              defaultSeason: season,
              defaultEpisode: episode,
            );
            if (subItem.url.isNotEmpty) {
              if (languageFilter == null || languageFilter.isEmpty || languageFilter.toLowerCase() == 'all') {
                items.add(subItem);
              } else if (subItem.lang == languageFilter.toLowerCase() ||
                         subItem.languageName.toLowerCase() == languageFilter.toLowerCase()) {
                items.add(subItem);
              }
            }
          }
        }
        return items;
      }
    } catch (e) {
      debugPrint("Error searching OpenSubtitles: $e");
    }
    return [];
  }

  /// Search online subtitles across OpenSubtitles and SubDL concurrently by title or direct IMDb ID
  Future<List<OnlineSubtitleItem>> searchSubtitles({
    required String query,
    int season = 0,
    int episode = 0,
    String? imdbId,
    String? languageFilter, // e.g. 'ind', 'eng', or null for all
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty && (imdbId == null || imdbId.isEmpty)) return [];

    String? targetImdbId = imdbId;

    // Check if query itself is directly an IMDb ID (e.g. "tt1234567")
    if (targetImdbId == null || targetImdbId.isEmpty) {
      if (RegExp(r'^tt\d+$', caseSensitive: false).hasMatch(trimmed)) {
        targetImdbId = trimmed.toLowerCase();
      } else {
        final isTv = season > 0 || episode > 0;
        targetImdbId = await resolveImdbId(title: trimmed, isTv: isTv);
      }
    }

    if (targetImdbId == null || targetImdbId.isEmpty) {
      return [];
    }

    try {
      final results = await Future.wait([
        _searchOpenSubtitles(
          imdbId: targetImdbId,
          query: trimmed,
          season: season,
          episode: episode,
          languageFilter: languageFilter,
        ),
        searchSubdl(
          imdbId: targetImdbId,
          query: trimmed,
          season: season,
          episode: episode,
          languageFilter: languageFilter,
        ),
      ]);

      final List<OnlineSubtitleItem> items = [];
      for (final list in results) {
        items.addAll(list);
      }

      // Sort to prioritize Indonesian first, then English, then others.
      // SubDL gets a slight boost (+5) for Indonesian due to community translation quality.
      items.sort((a, b) {
        int scoreA = 0;
        int scoreB = 0;
        if (a.lang == 'ind' || a.lang == 'id') scoreA += 100;
        if (b.lang == 'ind' || b.lang == 'id') scoreB += 100;
        if (a.lang == 'eng' || a.lang == 'en') scoreA += 50;
        if (b.lang == 'eng' || b.lang == 'en') scoreB += 50;
        if (a.source == 'SubDL') scoreA += 5;
        if (b.source == 'SubDL') scoreB += 5;
        return scoreB.compareTo(scoreA);
      });

      return items;
    } catch (e) {
      debugPrint("Error searching online subtitles: $e");
    }

    return [];
  }

  /// Download subtitle file (.srt or .zip archive from SubDL) content as raw UTF-8 string with key failover
  Future<String?> downloadSubtitleContent(String url, {int season = 0, int episode = 0}) async {
    final pool = RemoteConfigService.instance.subdlApiKeyPool;
    final isSubdlUrl = url.contains('subdl.com');

    // Build URL list: original URL first, then variants with alternate keys from the pool
    final urlsToTry = <String>[url];
    if (isSubdlUrl && pool.length > 1) {
      for (final key in pool) {
        final replaced = url.replaceAll(RegExp(r'api_key=[^&]+'), 'api_key=$key');
        if (replaced != url && !urlsToTry.contains(replaced)) {
          urlsToTry.add(replaced);
        }
      }
    }

    for (int i = 0; i < urlsToTry.length; i++) {
      final currentUrl = urlsToTry[i];
      try {
        final res = await http.get(Uri.parse(currentUrl)).timeout(const Duration(seconds: 20));

        if (res.statusCode == 429 || res.statusCode == 403) {
          debugPrint("SubDL download returned HTTP ${res.statusCode}, trying alternate key in pool...");
          continue;
        }

        if (res.statusCode == 200) {
          final bytes = res.bodyBytes;
          // Check if response is a ZIP file (Magic bytes: 'PK\x03\x04' -> [0x50, 0x4B, 0x03, 0x04])
          final isZip = bytes.length >= 4 &&
              bytes[0] == 0x50 &&
              bytes[1] == 0x4B &&
              bytes[2] == 0x03 &&
              bytes[3] == 0x04;

          if (isZip || currentUrl.toLowerCase().contains('.zip')) {
            return _extractSubtitleFromZip(bytes, episode: episode);
          }

          return utf8.decode(bytes, allowMalformed: true);
        }
      } catch (e) {
        debugPrint("Error downloading subtitle file from $currentUrl: $e");
        if (i < urlsToTry.length - 1) continue;
      }
    }
    return null;
  }

  /// Extract the best matching .srt or .vtt subtitle file from ZIP archive bytes
  String? _extractSubtitleFromZip(Uint8List zipBytes, {int episode = 0}) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      ArchiveFile? bestFile;

      final subtitleFiles = archive.where((file) {
        if (!file.isFile) return false;
        final name = file.name.toLowerCase();
        return name.endsWith('.srt') || name.endsWith('.vtt');
      }).toList();

      if (subtitleFiles.isEmpty) return null;

      if (episode > 0) {
        // Try to match episode e.g. E01, EP01, episode.1, E1
        final epStr = episode.toString();
        final epPadded = episode.toString().padLeft(2, '0');
        final epRegex = RegExp(r'(?:e|ep|episode)[\s\._-]*0?' + epStr + r'\b', caseSensitive: false);

        for (final file in subtitleFiles) {
          final name = file.name.toLowerCase();
          if (epRegex.hasMatch(name) || (name.contains('s') && name.contains('e$epPadded'))) {
            bestFile = file;
            break;
          }
        }
      }

      bestFile ??= subtitleFiles.first;

      final contentBytes = bestFile.content as List<int>;
      return utf8.decode(contentBytes, allowMalformed: true);
    } catch (e) {
      debugPrint("Error extracting subtitle from zip: $e");
      return null;
    }
  }
}

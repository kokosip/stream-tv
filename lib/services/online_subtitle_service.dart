import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  const OnlineSubtitleItem({
    required this.id,
    required this.lang,
    required this.languageName,
    required this.fileName,
    required this.releaseName,
    required this.url,
    this.season = 0,
    this.episode = 0,
  });

  factory OnlineSubtitleItem.fromJson(
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

    // MovieBox-TUI v0.1.22 Clean Subtitles: Title - S01E01.srt
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

  /// Search online subtitles by title or direct IMDb ID
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
      final isTv = (season > 0 || episode > 0);
      final endpoint = isTv
          ? "$_openSubtitlesBase/series/$targetImdbId:${season > 0 ? season : 1}:${episode > 0 ? episode : 1}.json"
          : "$_openSubtitlesBase/movie/$targetImdbId.json";

      final res = await http.get(Uri.parse(endpoint)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final rawList = decoded['subtitles'] as List? ?? [];
        final List<OnlineSubtitleItem> items = [];

        for (final item in rawList) {
          if (item is Map<String, dynamic>) {
            final subItem = OnlineSubtitleItem.fromJson(
              item,
              mediaTitle: trimmed,
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

        // Sort to prioritize Indonesian first, then English, then others
        items.sort((a, b) {
          int scoreA = 0;
          int scoreB = 0;
          if (a.lang == 'ind' || a.lang == 'id') scoreA += 100;
          if (b.lang == 'ind' || b.lang == 'id') scoreB += 100;
          if (a.lang == 'eng' || a.lang == 'en') scoreA += 50;
          if (b.lang == 'eng' || b.lang == 'en') scoreB += 50;
          return scoreB.compareTo(scoreA);
        });

        return items;
      }
    } catch (e) {
      debugPrint("Error searching online subtitles: $e");
    }

    return [];
  }

  /// Download subtitle file (.srt) content as raw UTF-8 string
  Future<String?> downloadSubtitleContent(String url) async {
    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return utf8.decode(res.bodyBytes, allowMalformed: true);
      }
    } catch (e) {
      debugPrint("Error downloading subtitle file: $e");
    }
    return null;
  }
}

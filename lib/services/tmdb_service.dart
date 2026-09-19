import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class StreamingPlatformInfo {
  final String id;
  final String name;
  final int providerId;
  final int? networkId;
  final Color primaryColor;
  final String iconEmoji;
  final String badgeText;

  const StreamingPlatformInfo({
    required this.id,
    required this.name,
    required this.providerId,
    this.networkId,
    required this.primaryColor,
    required this.iconEmoji,
    required this.badgeText,
  });
}

class TmdbService {
  static final TmdbService _instance = TmdbService._internal();
  factory TmdbService() => _instance;
  TmdbService._internal();

  static const String apiKey = "5059b58f63c9ff61df8429d06bd3f017";
  static const String baseUrl = "https://api.themoviedb.org/3";
  static const String imageBaseW500 = "https://image.tmdb.org/t/p/w500";
  static const String imageBaseW1280 = "https://image.tmdb.org/t/p/w1280";
  static const String imageBaseOriginal = "https://image.tmdb.org/t/p/original";

  // In-memory cache with TTL (15 minutes)
  final Map<String, _CacheEntry> _cache = {};
  static const Duration cacheTtl = Duration(minutes: 15);

  dynamic _getFromCache(String key) {
    final entry = _cache[key];
    if (entry != null && DateTime.now().difference(entry.timestamp) < cacheTtl) {
      return entry.data;
    }
    _cache.remove(key);
    return null;
  }

  void _putInCache(String key, dynamic data) {
    _cache[key] = _CacheEntry(data, DateTime.now());
  }

  Future<Map<String, dynamic>> _get(String path, {Map<String, String>? params}) async {
    final queryParams = {
      "api_key": apiKey,
      "include_adult": "false",
      ...?params,
    };

    final uri = Uri.parse("$baseUrl$path").replace(queryParameters: queryParams);
    final cacheKey = uri.toString();

    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        _putInCache(cacheKey, decoded);
        return decoded;
      } else {
        throw Exception("TMDB API Error: HTTP ${res.statusCode}");
      }
    } catch (e) {
      print("TmdbService request error ($path): $e");
      rethrow;
    }
  }

  /// Get Trending Movies of the day
  Future<List<Map<String, dynamic>>> getTrendingMovies({int page = 1}) async {
    try {
      final res = await _get("/trending/movie/day", params: {
        "page": page.toString(),
      });
      final results = (res['results'] as List? ?? []);
      return results.map((item) => normalizeItem(item as Map<String, dynamic>, mediaType: 'movie')).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get Now Playing in Cinemas
  Future<List<Map<String, dynamic>>> getNowPlayingMovies({int page = 1}) async {
    try {
      final res = await _get("/movie/now_playing", params: {
        "page": page.toString(),
      });
      final results = (res['results'] as List? ?? []);
      return results.map((item) => normalizeItem(item as Map<String, dynamic>, mediaType: 'movie')).toList();
    } catch (e) {
      return [];
    }
  }

  /// Get Trending TV Shows of the week
  Future<List<Map<String, dynamic>>> getTrendingTv({int page = 1}) async {
    try {
      final res = await _get("/trending/tv/week", params: {
        "page": page.toString(),
      });
      final results = (res['results'] as List? ?? []);
      return results.map((item) => normalizeItem(item as Map<String, dynamic>, mediaType: 'tv')).toList();
    } catch (e) {
      return [];
    }
  }

  /// Supported OTT / Streaming Platforms
  static const List<StreamingPlatformInfo> supportedPlatforms = [
    StreamingPlatformInfo(
      id: 'netflix',
      name: 'Netflix',
      providerId: 8,
      networkId: 213,
      primaryColor: Color(0xFFE50914),
      iconEmoji: '🍿',
      badgeText: 'NETFLIX',
    ),
    StreamingPlatformInfo(
      id: 'disney',
      name: 'Disney+',
      providerId: 122,
      networkId: 2739,
      primaryColor: Color(0xFF113CCF),
      iconEmoji: '✨',
      badgeText: 'DISNEY+',
    ),
    StreamingPlatformInfo(
      id: 'prime',
      name: 'Prime Video',
      providerId: 119,
      networkId: 1024,
      primaryColor: Color(0xFF00A8E1),
      iconEmoji: '🎬',
      badgeText: 'PRIME',
    ),
    StreamingPlatformInfo(
      id: 'apple',
      name: 'Apple TV+',
      providerId: 350,
      networkId: 2552,
      primaryColor: Color(0xFF555555),
      iconEmoji: '🍏',
      badgeText: 'APPLE TV+',
    ),
    StreamingPlatformInfo(
      id: 'hbo',
      name: 'HBO Max',
      providerId: 1899,
      networkId: 49,
      primaryColor: Color(0xFF702082),
      iconEmoji: '👑',
      badgeText: 'MAX',
    ),
    StreamingPlatformInfo(
      id: 'viu',
      name: 'Viu',
      providerId: 158,
      primaryColor: Color(0xFFFFB800),
      iconEmoji: '🌸',
      badgeText: 'VIU',
    ),
  ];

  /// Discover movies on a specific streaming platform
  Future<List<Map<String, dynamic>>> getMoviesByProvider({
    required int providerId,
    int page = 1,
    String region = "ID",
  }) async {
    try {
      final res = await _get("/discover/movie", params: {
        "with_watch_providers": providerId.toString(),
        "watch_region": region,
        "sort_by": "popularity.desc",
        "page": page.toString(),
      });
      final results = (res['results'] as List? ?? []);
      return results.map((item) => normalizeItem(item as Map<String, dynamic>, mediaType: 'movie')).toList();
    } catch (e) {
      return [];
    }
  }

  /// Discover TV Shows on a specific streaming platform
  Future<List<Map<String, dynamic>>> getTvByProvider({
    required int providerId,
    int? networkId,
    int page = 1,
    String region = "ID",
  }) async {
    try {
      final params = <String, String>{
        "sort_by": "popularity.desc",
        "page": page.toString(),
      };
      if (networkId != null) {
        params["with_networks"] = networkId.toString();
      } else {
        params["with_watch_providers"] = providerId.toString();
        params["watch_region"] = region;
      }
      final res = await _get("/discover/tv", params: params);
      final results = (res['results'] as List? ?? []);
      return results.map((item) => normalizeItem(item as Map<String, dynamic>, mediaType: 'tv')).toList();
    } catch (e) {
      return [];
    }
  }

  /// Discover all (Movies + TV) on a platform
  Future<List<Map<String, dynamic>>> getByPlatform({
    required StreamingPlatformInfo platform,
    String type = 'all', // 'all', 'movie', 'tv'
    int page = 1,
  }) async {
    if (type == 'movie') {
      return getMoviesByProvider(providerId: platform.providerId, page: page);
    } else if (type == 'tv') {
      return getTvByProvider(providerId: platform.providerId, networkId: platform.networkId, page: page);
    } else {
      final moviesFuture = getMoviesByProvider(providerId: platform.providerId, page: page);
      final tvFuture = getTvByProvider(providerId: platform.providerId, networkId: platform.networkId, page: page);
      final results = await Future.wait([moviesFuture, tvFuture]);
      final List<Map<String, dynamic>> combined = [];
      final movies = results[0];
      final tv = results[1];
      final maxLen = movies.length > tv.length ? movies.length : tv.length;
      for (int i = 0; i < maxLen; i++) {
        if (i < movies.length) combined.add(movies[i]);
        if (i < tv.length) combined.add(tv[i]);
      }
      return combined;
    }
  }

  /// Search movies and TV Shows available on a specific streaming platform
  Future<List<Map<String, dynamic>>> searchByPlatform({
    required StreamingPlatformInfo platform,
    required String query,
    String type = 'all', // 'all', 'movie', 'tv'
    int page = 1,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      List<dynamic> rawResults = [];

      if (type == 'movie') {
        final res = await _get("/search/movie", params: {
          "query": cleanQuery,
          "page": page.toString(),
        });
        rawResults = (res['results'] as List? ?? []).map((m) {
          final item = Map<String, dynamic>.from(m as Map);
          item['media_type'] = 'movie';
          return item;
        }).toList();
      } else if (type == 'tv') {
        final res = await _get("/search/tv", params: {
          "query": cleanQuery,
          "page": page.toString(),
        });
        rawResults = (res['results'] as List? ?? []).map((t) {
          final item = Map<String, dynamic>.from(t as Map);
          item['media_type'] = 'tv';
          return item;
        }).toList();
      } else {
        final res = await _get("/search/multi", params: {
          "query": cleanQuery,
          "page": page.toString(),
        });
        rawResults = (res['results'] as List? ?? [])
            .where((r) => r['media_type'] == 'movie' || r['media_type'] == 'tv')
            .toList();
      }

      if (rawResults.isEmpty) return [];

      // Limit top candidates to 16 to keep response snappy
      final candidates = rawResults.take(16).toList();

      // Check watch providers for each candidate in parallel
      final checks = await Future.wait(candidates.map((item) async {
        final mediaType = (item['media_type'] ?? (type == 'tv' ? 'tv' : 'movie')).toString();
        final id = item['id'];
        if (id == null) return null;

        try {
          final p = await _get("/$mediaType/$id/watch/providers");
          final resultsMap = (p['results'] as Map? ?? {});

          bool hasProvider = false;

          // Check if providerId or alternative IDs match across regions
          for (final countryEntry in resultsMap.values) {
            if (countryEntry is Map) {
              final flatrate = (countryEntry['flatrate'] as List? ?? []);
              final buy = (countryEntry['buy'] as List? ?? []);
              final rent = (countryEntry['rent'] as List? ?? []);
              final all = [...flatrate, ...buy, ...rent];

              if (all.any((pr) {
                final pid = pr['provider_id'];
                final pName = (pr['provider_name'] ?? '').toString().toLowerCase();
                final targetName = platform.name.toLowerCase();
                return pid == platform.providerId ||
                    (platform.id == 'disney' && (pid == 337 || pid == 390)) ||
                    (platform.id == 'prime' && (pid == 9 || pid == 10)) ||
                    (platform.id == 'apple' && (pid == 2 || pid == 350)) ||
                    (platform.id == 'hbo' && (pid == 384 || pid == 1899)) ||
                    (platform.id == 'viu' && pid == 158) ||
                    pName.contains(targetName);
              })) {
                hasProvider = true;
                break;
              }
            }
          }

          // Check TV network if applicable
          if (!hasProvider && platform.networkId != null && mediaType == 'tv') {
            final tvDetails = await _get("/tv/$id");
            final networks = (tvDetails['networks'] as List? ?? []);
            if (networks.any((n) => n['id'] == platform.networkId)) {
              hasProvider = true;
            }
          }

          if (hasProvider) {
            return normalizeItem(Map<String, dynamic>.from(item as Map), mediaType: mediaType);
          }
        } catch (_) {}
        return null;
      }));

      return checks.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      print("Search by platform error: $e");
      return [];
    }
  }

  /// Get Detailed info for a movie
  Future<Map<String, dynamic>?> getMovieDetails(int tmdbId) async {
    try {
      final res = await _get("/movie/$tmdbId", params: {
        "append_to_response": "credits,similar,videos",
      });
      return res;
    } catch (e) {
      return null;
    }
  }

  /// Get Detailed info for a TV show
  Future<Map<String, dynamic>?> getTvDetails(int tmdbId) async {
    try {
      final res = await _get("/tv/$tmdbId", params: {
        "append_to_response": "credits,similar,videos",
      });
      return res;
    } catch (e) {
      return null;
    }
  }

  /// Normalize TMDB item to the Stream TV standard format
  Map<String, dynamic> normalizeItem(Map<String, dynamic> item, {String? mediaType}) {
    final rawTmdb = item['rawTmdb'] is Map ? (item['rawTmdb'] as Map) : null;
    final typeVal = item['subjectType'] ?? item['subject_type'] ?? rawTmdb?['subjectType'] ?? rawTmdb?['subject_type'];
    final mediaTypeStr = (mediaType ?? item['media_type'] ?? rawTmdb?['media_type'] ?? '').toString().toLowerCase();

    final isTv = mediaTypeStr == 'tv' ||
        typeVal == 2 ||
        typeVal?.toString() == '2' ||
        item['first_air_date'] != null ||
        rawTmdb?['first_air_date'] != null ||
        (item['name'] != null && item['title'] == null) ||
        (rawTmdb?['name'] != null && rawTmdb?['title'] == null);

    final id = item['id'] ?? item['tmdbId'] ?? rawTmdb?['id'];
    final title = item['title'] ?? item['name'] ?? item['subjectTitle'] ?? item['original_title'] ?? item['original_name'] ?? rawTmdb?['name'] ?? rawTmdb?['title'] ?? "Untitled";
    final posterPath = item['poster_path'] ?? (item['cover'] is Map ? item['cover']['url'] : null) ?? rawTmdb?['poster_path'];
    final backdropPath = item['backdrop_path'] ?? (item['backdrop'] is Map ? item['backdrop']['url'] : null) ?? rawTmdb?['backdrop_path'];
    final voteAvg = item['vote_average'] ?? item['imdbRate'] ?? rawTmdb?['vote_average'];
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? item['releaseDate'] ?? rawTmdb?['first_air_date'] ?? rawTmdb?['release_date'] ?? "";
    final overview = item['overview'] ?? item['description'] ?? rawTmdb?['overview'] ?? "";

    String ratingStr = "";
    if (voteAvg is num && voteAvg > 0) {
      ratingStr = voteAvg.toStringAsFixed(1);
    } else if (voteAvg != null && voteAvg.toString().isNotEmpty) {
      ratingStr = voteAvg.toString();
    }

    String coverUrl = "";
    if (posterPath != null && posterPath.toString().isNotEmpty) {
      final p = posterPath.toString();
      coverUrl = p.startsWith('http') ? p : "$imageBaseW500$p";
    }

    String backdropUrl = "";
    if (backdropPath != null && backdropPath.toString().isNotEmpty) {
      final b = backdropPath.toString();
      backdropUrl = b.startsWith('http') ? b : "$imageBaseW1280$b";
    }

    // Genre extraction
    String genreStr = "";
    if (item['genres'] is List) {
      genreStr = (item['genres'] as List).map((g) => g['name'] ?? '').where((s) => s.isNotEmpty).join(', ');
    } else if (item['genre'] is String) {
      genreStr = item['genre'] as String;
    }

    return {
      "id": id,
      "subjectId": "tmdb_$id",
      "tmdbId": id,
      "title": title,
      "subjectTitle": title,
      "cover": {
        "url": coverUrl,
      },
      "backdrop": {
        "url": backdropUrl,
      },
      "image": {
        "url": backdropUrl.isNotEmpty ? backdropUrl : coverUrl,
      },
      "content": title,
      "imdbRate": ratingStr,
      "imdbRatingValue": ratingStr,
      "voteCount": item['vote_count'] ?? rawTmdb?['vote_count'] ?? 0,
      "releaseDate": releaseDate,
      "genre": genreStr,
      "description": overview,
      "subjectType": isTv ? 2 : 1,
      "provider": "tmdb",
      "rawTmdb": rawTmdb ?? item,
    };
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime timestamp;
  _CacheEntry(this.data, this.timestamp);
}

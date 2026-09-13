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
    final isTv = mediaType == 'tv' || item['media_type'] == 'tv' || item['first_air_date'] != null;
    final id = item['id'];
    final title = item['title'] ?? item['name'] ?? item['original_title'] ?? item['original_name'] ?? "Untitled";
    final posterPath = item['poster_path'];
    final backdropPath = item['backdrop_path'];
    final voteAvg = item['vote_average'];
    final releaseDate = item['release_date'] ?? item['first_air_date'] ?? "";
    final overview = item['overview'] ?? "";

    String ratingStr = "";
    if (voteAvg is num && voteAvg > 0) {
      ratingStr = voteAvg.toStringAsFixed(1);
    }

    String coverUrl = "";
    if (posterPath != null && posterPath.toString().isNotEmpty) {
      coverUrl = "$imageBaseW500$posterPath";
    }

    String backdropUrl = "";
    if (backdropPath != null && backdropPath.toString().isNotEmpty) {
      backdropUrl = "$imageBaseW1280$backdropPath";
    }

    // Genre extraction
    String genreStr = "";
    if (item['genres'] is List) {
      genreStr = (item['genres'] as List).map((g) => g['name'] ?? '').where((s) => s.isNotEmpty).join(', ');
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
      "voteCount": item['vote_count'] ?? 0,
      "releaseDate": releaseDate,
      "genre": genreStr,
      "description": overview,
      "subjectType": isTv ? 2 : 1,
      "provider": "tmdb",
      "rawTmdb": item,
    };
  }
}

class _CacheEntry {
  final dynamic data;
  final DateTime timestamp;
  _CacheEntry(this.data, this.timestamp);
}

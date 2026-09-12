import 'dart:convert';
import 'package:http/http.dart' as http;

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

  /// Get Popular Movies
  Future<List<Map<String, dynamic>>> getPopularMovies({int page = 1}) async {
    try {
      final res = await _get("/movie/popular", params: {
        "page": page.toString(),
      });
      final results = (res['results'] as List? ?? []);
      return results.map((item) => normalizeItem(item as Map<String, dynamic>, mediaType: 'movie')).toList();
    } catch (e) {
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

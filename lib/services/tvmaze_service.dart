import 'dart:convert';
import 'package:http/http.dart' as http;

class TvMazeEpisode {
  final int season;
  final int episode;
  final String name;
  final String overview;
  final String? imageUrl;
  final String? airDate;
  final double? rating;

  const TvMazeEpisode({
    required this.season,
    required this.episode,
    required this.name,
    required this.overview,
    this.imageUrl,
    this.airDate,
    this.rating,
  });

  factory TvMazeEpisode.fromJson(Map<String, dynamic> json) {
    // Strip HTML tags from summary (e.g. <p>...</p>, <b>...</b>, <br />)
    String rawSummary = json['summary']?.toString() ?? '';
    final cleanSummary = rawSummary
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();

    String? imgUrl;
    if (json['image'] is Map) {
      final imgMap = json['image'] as Map<String, dynamic>;
      imgUrl = imgMap['original'] ?? imgMap['medium'];
    }

    double? ratingVal;
    if (json['rating'] is Map && json['rating']['average'] != null) {
      ratingVal = double.tryParse(json['rating']['average'].toString());
    }

    return TvMazeEpisode(
      season: (json['season'] as num?)?.toInt() ?? 1,
      episode: (json['number'] as num?)?.toInt() ?? 1,
      name: json['name']?.toString().trim() ?? '',
      overview: cleanSummary,
      imageUrl: imgUrl,
      airDate: json['airdate']?.toString(),
      rating: ratingVal,
    );
  }
}

class TvMazeService {
  TvMazeService._internal();
  static final TvMazeService instance = TvMazeService._internal();

  final Map<String, Map<String, TvMazeEpisode>> _cache = {};

  /// Normalizes TV series title for higher TVMaze search accuracy
  String _normalizeTitle(String rawTitle) {
    String t = rawTitle;
    // Remove (2023), (2024), etc.
    t = t.replaceAll(RegExp(r'\(\d{4}\)'), '');
    // Remove "Season X" or "S1", "S01"
    t = t.replaceAll(RegExp(r'\bseason\s*\d+\b', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\bs\d{1,2}\b', caseSensitive: false), '');
    // Remove common dub tags like [Dubbed], [Sub], 4K, UHD
    t = t.replaceAll(RegExp(r'\[.*?\]', caseSensitive: false), '');
    t = t.replaceAll(RegExp(r'\b(4k|uhd|1080p|720p|bluray|web-dl)\b', caseSensitive: false), '');
    return t.trim();
  }

  /// Fetches episodes metadata for a TV Show title.
  /// Returns a map keyed by "S{season}E{episode}" (e.g. "S1E1", "S1E2").
  Future<Map<String, TvMazeEpisode>> getEpisodesMap(String title) async {
    if (title.trim().isEmpty) return {};

    final cleanTitle = _normalizeTitle(title);
    final cacheKey = cleanTitle.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      final encodedQuery = Uri.encodeQueryComponent(cleanTitle);
      final url = Uri.parse(
        'https://api.tvmaze.com/singlesearch/shows?q=$encodedQuery&embed=episodes',
      );

      final res = await http.get(url, headers: {
        'Accept': 'application/json',
        'User-Agent': 'stream-tv/1.0',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map<String, dynamic> && data['_embedded'] is Map) {
          final embedded = data['_embedded'] as Map<String, dynamic>;
          final epList = embedded['episodes'] as List<dynamic>? ?? [];

          final Map<String, TvMazeEpisode> resultMap = {};
          for (final ep in epList) {
            if (ep is Map<String, dynamic>) {
              final episodeObj = TvMazeEpisode.fromJson(ep);
              final key = 'S${episodeObj.season}E${episodeObj.episode}';
              resultMap[key] = episodeObj;
            }
          }

          _cache[cacheKey] = resultMap;
          return resultMap;
        }
      }
    } catch (_) {
      // Graceful fallback on network failure or if show not found
    }

    // Try fallback search without any extra stripping if cleanTitle failed
    if (cleanTitle != title.trim()) {
      try {
        final rawEncoded = Uri.encodeQueryComponent(title.trim());
        final rawUrl = Uri.parse(
          'https://api.tvmaze.com/singlesearch/shows?q=$rawEncoded&embed=episodes',
        );
        final res = await http.get(rawUrl, headers: {
          'Accept': 'application/json',
          'User-Agent': 'stream-tv/1.0',
        }).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map<String, dynamic> && data['_embedded'] is Map) {
            final embedded = data['_embedded'] as Map<String, dynamic>;
            final epList = embedded['episodes'] as List<dynamic>? ?? [];

            final Map<String, TvMazeEpisode> resultMap = {};
            for (final ep in epList) {
              if (ep is Map<String, dynamic>) {
                final episodeObj = TvMazeEpisode.fromJson(ep);
                final key = 'S${episodeObj.season}E${episodeObj.episode}';
                resultMap[key] = episodeObj;
              }
            }

            _cache[cacheKey] = resultMap;
            return resultMap;
          }
        }
      } catch (_) {}
    }

    _cache[cacheKey] = {};
    return {};
  }
}

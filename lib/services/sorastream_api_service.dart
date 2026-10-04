import 'package:flutter/foundation.dart';
import 'tmdb_service.dart';

class SorastreamApiService {
  static final SorastreamApiService _instance = SorastreamApiService._internal();
  factory SorastreamApiService() => _instance;
  SorastreamApiService._internal();

  final TmdbService _tmdb = TmdbService();

  static const Map<String, String> _defaultHeaders = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9,id;q=0.8',
  };

  /// Search movies and TV shows
  Future<List<Map<String, dynamic>>> search(String query, {int page = 1}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final results = await _tmdb.search(cleanQuery, page: page);
      final items = <Map<String, dynamic>>[];

      for (final r in results) {
        final mediaType = r['media_type'] ?? (r['title'] != null ? 'movie' : 'tv');
        if (mediaType != 'movie' && mediaType != 'tv') continue;

        final id = r['id'] ?? r['tmdbId'];
        final title = r['title'] ?? r['name'] ?? '';
        final posterPath = r['poster_path'] ?? '';
        final backdropPath = r['backdrop_path'] ?? '';
        final voteAvg = (r['vote_average'] as num?)?.toStringAsFixed(1) ?? (r['rating']?.toString() ?? '');
        final releaseDate = r['releaseDate'] ?? r['release_date'] ?? r['first_air_date'] ?? '';

        final cover = (r['cover'] != null && r['cover'].toString().isNotEmpty)
            ? r['cover'].toString()
            : (posterPath.isNotEmpty
                ? '${TmdbService.imageBaseW500}$posterPath'
                : (backdropPath.isNotEmpty ? '${TmdbService.imageBaseW500}$backdropPath' : ''));

        items.add({
          'subjectId': 'sorastream_${mediaType}_$id',
          'tmdbId': id,
          'subjectTitle': title,
          'title': title,
          'cover': cover,
          'coverUrl': cover,
          'poster_path': posterPath,
          'backdrop_path': backdropPath,
          'rating': voteAvg,
          'releaseDate': releaseDate,
          'subjectType': mediaType == 'movie' ? 1 : 2,
          'media_type': mediaType,
          'provider': 'sorastream',
        });
      }

      return items;
    } catch (e) {
      debugPrint('SorastreamApiService.search error: $e');
      return [];
    }
  }

  /// Get Homepage items (Trending Movies & TV)
  Future<Map<String, dynamic>> getHomepage({int page = 1}) async {
    try {
      final moviesFuture = _tmdb.getTrendingMovies(page: page);
      final tvFuture = _tmdb.getTrendingTv(page: page);
      final results = await Future.wait([moviesFuture, tvFuture]);
      final items = <Map<String, dynamic>>[];

      final movies = results[0];
      final tv = results[1];
      final maxLen = movies.length > tv.length ? movies.length : tv.length;
      for (int i = 0; i < maxLen; i++) {
        if (i < movies.length) {
          final m = movies[i];
          final id = m['id'] ?? m['tmdbId'];
          items.add({
            ...m,
            'subjectId': 'sorastream_movie_$id',
            'provider': 'sorastream',
          });
        }
        if (i < tv.length) {
          final t = tv[i];
          final id = t['id'] ?? t['tmdbId'];
          items.add({
            ...t,
            'subjectId': 'sorastream_tv_$id',
            'provider': 'sorastream',
          });
        }
      }

      return {
        'code': 0,
        'list': items,
        'items': items,
        'data': {'list': items},
      };
    } catch (e) {
      debugPrint('SorastreamApiService.getHomepage error: $e');
      return {'code': 0, 'list': [], 'items': []};
    }
  }

  /// Get Details of Movie or TV Show
  Future<Map<String, dynamic>> getDetails({required String subjectId}) async {
    try {
      var s = subjectId.replaceFirst('sorastream_', '');
      String mediaType = 'movie';
      int tmdbId = 0;

      if (s.startsWith('movie_')) {
        mediaType = 'movie';
        tmdbId = int.tryParse(s.substring(6)) ?? 0;
      } else if (s.startsWith('tv_')) {
        mediaType = 'tv';
        tmdbId = int.tryParse(s.substring(3)) ?? 0;
      } else {
        tmdbId = int.tryParse(s) ?? 0;
      }

      if (tmdbId == 0) {
        return {'subjectId': subjectId, 'title': 'Unknown', 'episodes': []};
      }

      final Map<String, dynamic>? data;
      if (mediaType == 'movie') {
        data = await _tmdb.getMovieDetails(tmdbId);
      } else {
        data = await _tmdb.getTvDetails(tmdbId);
      }

      if (data == null) {
        return {'subjectId': subjectId, 'title': 'Unknown', 'episodes': []};
      }

      final title = data['title'] ?? data['name'] ?? '';
      final overview = data['overview'] ?? '';
      final posterPath = data['poster_path'] ?? '';
      final backdropPath = data['backdrop_path'] ?? '';
      final voteAvg = (data['vote_average'] as num?)?.toStringAsFixed(1) ?? '';
      final cover = posterPath.isNotEmpty
          ? '${TmdbService.imageBaseW500}$posterPath'
          : (backdropPath.isNotEmpty ? '${TmdbService.imageBaseW500}$backdropPath' : '');

      final episodes = <Map<String, dynamic>>[];

      if (mediaType == 'tv') {
        final seasons = (data['seasons'] as List?) ?? [];
        final s1 = seasons.firstWhere(
          (s) => s is Map && s['season_number'] == 1,
          orElse: () => seasons.isNotEmpty ? seasons.first : null,
        );
        final epCount = s1 != null && s1 is Map ? (s1['episode_count'] ?? 1) : 1;
        for (var i = 1; i <= epCount; i++) {
          episodes.add({
            'episodeId': 'sorastream_tv_${tmdbId}_1_$i',
            'episodeNumber': i,
            'seasonNumber': 1,
            'title': 'Episode $i',
            'tmdbId': tmdbId,
          });
        }
      } else {
        episodes.add({
          'episodeId': 'sorastream_movie_$tmdbId',
          'episodeNumber': 1,
          'seasonNumber': 0,
          'title': 'Full Movie',
          'tmdbId': tmdbId,
        });
      }

      return {
        'subjectId': subjectId,
        'tmdbId': tmdbId,
        'subjectTitle': title,
        'title': title,
        'description': overview,
        'cover': cover,
        'coverUrl': cover,
        'poster_path': posterPath,
        'backdrop_path': backdropPath,
        'rating': voteAvg,
        'subjectType': mediaType == 'movie' ? 1 : 2,
        'media_type': mediaType,
        'provider': 'sorastream',
        'episodes': episodes,
      };
    } catch (e) {
      debugPrint('SorastreamApiService.getDetails error: $e');
      return {'subjectId': subjectId, 'title': 'Error', 'episodes': []};
    }
  }

  /// Get Season info
  Future<Map<String, dynamic>> getSeasonInfo({required String subjectId}) async {
    var s = subjectId.replaceFirst('sorastream_', '');
    int tmdbId = 0;
    if (s.startsWith('tv_')) {
      tmdbId = int.tryParse(s.substring(3)) ?? 0;
    } else if (s.startsWith('movie_')) {
      tmdbId = int.tryParse(s.substring(6)) ?? 0;
    } else {
      tmdbId = int.tryParse(s) ?? 0;
    }

    if (tmdbId == 0) return {'seasons': []};

    try {
      final data = await _tmdb.getTvDetails(tmdbId);
      if (data == null) return {'seasons': []};
      final seasonsList = (data['seasons'] as List?) ?? [];
      final resultSeasons = <Map<String, dynamic>>[];

      for (final s in seasonsList) {
        if (s is! Map) continue;
        final sNum = s['season_number'] ?? 1;
        if (sNum == 0) continue; // Skip specials
        final epCount = s['episode_count'] ?? 0;
        final eps = <Map<String, dynamic>>[];
        for (var i = 1; i <= epCount; i++) {
          eps.add({
            'episodeId': 'sorastream_tv_${tmdbId}_${sNum}_$i',
            'episodeNumber': i,
            'seasonNumber': sNum,
            'title': 'Episode $i',
            'tmdbId': tmdbId,
          });
        }
        resultSeasons.add({
          'seasonNumber': sNum,
          'season_number': sNum,
          'name': s['name'] ?? 'Season $sNum',
          'episode_count': epCount,
          'episodes': eps,
        });
      }

      return {'seasons': resultSeasons};
    } catch (e) {
      debugPrint('SorastreamApiService.getSeasonInfo error: $e');
      return {'seasons': []};
    }
  }

  /// Get stream resources for movie or episode
  Future<Map<String, dynamic>> getResources({
    required String subjectId,
    int se = 0,
    int ep = 0,
  }) async {
    try {
      var s = subjectId.replaceFirst('sorastream_', '');
      String mediaType = 'movie';
      int tmdbId = 0;

      if (s.startsWith('movie_')) {
        mediaType = 'movie';
        tmdbId = int.tryParse(s.substring(6)) ?? 0;
      } else if (s.startsWith('tv_')) {
        mediaType = 'tv';
        final parts = s.substring(3).split('_');
        tmdbId = int.tryParse(parts[0]) ?? 0;
        if (parts.length >= 3) {
          se = int.tryParse(parts[1]) ?? se;
          ep = int.tryParse(parts[2]) ?? ep;
        }
      } else {
        tmdbId = int.tryParse(s) ?? 0;
      }

      if (tmdbId == 0) return {'streams': []};

      final season = se > 0 ? se : 1;
      final episode = ep > 0 ? ep : 1;

      final streams = <Map<String, dynamic>>[];

      if (mediaType == 'movie') {
        // MultiEmbed
        streams.add({
          'url': 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1',
          'quality': 'MultiEmbed (Server 1)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://multiembed.mov/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // VidSrc.to
        streams.add({
          'url': 'https://vidsrc.to/embed/movie/$tmdbId',
          'quality': 'VidSrc TO (Server 2)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://vidsrc.to/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // VidSrc.xyz
        streams.add({
          'url': 'https://vidsrc.xyz/embed/movie?tmdb=$tmdbId',
          'quality': 'VidSrc XYZ (Server 3)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://vidsrc.xyz/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // AutoEmbed
        streams.add({
          'url': 'https://player.autoembed.cc/embed/movie/$tmdbId',
          'quality': 'AutoEmbed (Server 4)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://player.autoembed.cc/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // 2Embed
        streams.add({
          'url': 'https://www.2embed.cc/embed/$tmdbId',
          'quality': '2Embed (Server 5)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://www.2embed.cc/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });
      } else {
        // TV Shows
        // MultiEmbed
        streams.add({
          'url': 'https://multiembed.mov/?video_id=$tmdbId&tmdb=1&s=$season&e=$episode',
          'quality': 'MultiEmbed (Server 1)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://multiembed.mov/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // VidSrc.to
        streams.add({
          'url': 'https://vidsrc.to/embed/tv/$tmdbId/$season/$episode',
          'quality': 'VidSrc TO (Server 2)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://vidsrc.to/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // VidSrc.xyz
        streams.add({
          'url': 'https://vidsrc.xyz/embed/tv?tmdb=$tmdbId&season=$season&episode=$episode',
          'quality': 'VidSrc XYZ (Server 3)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://vidsrc.xyz/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // AutoEmbed
        streams.add({
          'url': 'https://player.autoembed.cc/embed/tv/$tmdbId/$season/$episode',
          'quality': 'AutoEmbed (Server 4)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://player.autoembed.cc/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });

        // 2Embed
        streams.add({
          'url': 'https://www.2embed.cc/embedtv/$tmdbId&s=$season&e=$episode',
          'quality': '2Embed (Server 5)',
          'format': 'embed',
          'headers': {
            'Referer': 'https://www.2embed.cc/',
            'User-Agent': _defaultHeaders['User-Agent']!,
          },
        });
      }

      return {
        'streams': streams,
        'url': streams.isNotEmpty ? streams.first['url'] : '',
        'format': streams.isNotEmpty ? streams.first['format'] : 'embed',
        'headers': streams.isNotEmpty ? streams.first['headers'] : {},
      };
    } catch (e) {
      debugPrint('SorastreamApiService.getResources error: $e');
      return {'streams': []};
    }
  }
}

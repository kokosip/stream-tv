import 'package:flutter/foundation.dart';
import 'safe_http_client.dart';
import 'kisskh_api_service.dart';

class DramacoolEpisode {
  final int episodeNumber;
  final String url;

  DramacoolEpisode({
    required this.episodeNumber,
    required this.url,
  });
}

class DramacoolDramaResult {
  final String title;
  final String url;
  final String? thumbnail;

  DramacoolDramaResult({
    required this.title,
    required this.url,
    this.thumbnail,
  });
}

class DramacoolStreamResult {
  final String streamUrl;
  final String? quality;
  final Map<String, String> headers;
  final List<KissKhSubtitle> subtitles;

  DramacoolStreamResult({
    required this.streamUrl,
    this.quality,
    required this.headers,
    this.subtitles = const [],
  });
}

class DramacoolApiService {
  static const String _baseUrl = 'https://dramacool.com.tr';

  /// Search dramas on DramaCool
  static Future<List<DramacoolDramaResult>> search(String query) async {
    try {
      final uri = Uri.parse('$_baseUrl/?s=${Uri.encodeComponent(query)}');
      final resp = await SafeHttpClient.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$_baseUrl/',
      });

      if (resp.statusCode != 200) return [];

      final itemRegex = RegExp(
        r'<a\s+href="(https://wxx\.dramacool\.com\.tr/drama-detail/[^"]+/)"\s+class="img"\s+title="([^"]+)">\s*<img[^>]*data-original="([^"]+)"',
      );

      final results = <DramacoolDramaResult>[];
      for (final match in itemRegex.allMatches(resp.body)) {
        final url = match.group(1)!;
        final title = match.group(2)!.trim();
        final thumb = match.group(3);
        results.add(DramacoolDramaResult(title: title, url: url, thumbnail: thumb));
      }

      return results;
    } catch (e) {
      debugPrint('[DramaCool] Search error: $e');
      return [];
    }
  }

  /// Get episodes for a drama detail page
  static Future<List<DramacoolEpisode>> getEpisodes(String dramaUrl) async {
    try {
      final resp = await SafeHttpClient.get(Uri.parse(dramaUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$_baseUrl/',
      });

      if (resp.statusCode != 200) return [];

      final epRegex = RegExp(r'<a\s+href="(https://wxx\.dramacool\.com\.tr/[^"]*episode-(\d+)[^"]*/)"');
      final episodes = <DramacoolEpisode>[];

      for (final match in epRegex.allMatches(resp.body)) {
        final url = match.group(1)!;
        final num = int.tryParse(match.group(2)!) ?? 0;
        episodes.add(DramacoolEpisode(episodeNumber: num, url: url));
      }

      episodes.sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      return episodes;
    } catch (e) {
      debugPrint('[DramaCool] Get episodes error: $e');
      return [];
    }
  }

  /// Resolve stream for title & episode number
  static Future<DramacoolStreamResult?> resolveStream({
    required String title,
    required int episodeNumber,
  }) async {
    try {
      final searchResults = await search(title);
      if (searchResults.isEmpty) return null;

      final drama = searchResults.first;
      final episodes = await getEpisodes(drama.url);
      if (episodes.isEmpty) return null;

      final targetEp = episodes.firstWhere(
        (ep) => ep.episodeNumber == episodeNumber,
        orElse: () => episodes.first,
      );

      final epResp = await SafeHttpClient.get(Uri.parse(targetEp.url), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': drama.url,
      });

      if (epResp.statusCode != 200) return null;

      // Extract embed / data-video links
      final dataVideoRegex = RegExp(r'data-video="([^"]+)"');
      final iframeRegex = RegExp(r'<iframe[^>]*src="([^"]+)"', caseSensitive: false);

      final candidates = <String>[];
      for (final m in dataVideoRegex.allMatches(epResp.body)) {
        candidates.add(m.group(1)!);
      }
      for (final m in iframeRegex.allMatches(epResp.body)) {
        candidates.add(m.group(1)!);
      }

      for (final cand in candidates) {
        // If it references kisskh endpoint: e.g. https://2ivdeo.buzz/kisskh/225823
        final kissMatch = RegExp(r'kisskh/(\d+)').firstMatch(cand);
        if (kissMatch != null) {
          final kissEpId = int.parse(kissMatch.group(1)!);
          final kissStream = await KissKhApiService.resolveEpisodeById(
            episodeId: kissEpId,
            title: title,
            episodeNumber: targetEp.episodeNumber,
          );
          if (kissStream != null) {
            return DramacoolStreamResult(
              streamUrl: kissStream.streamUrl,
              quality: kissStream.quality,
              headers: kissStream.headers,
              subtitles: kissStream.subtitles,
            );
          }
        }
      }

      return null;
    } catch (e) {
      debugPrint('[DramaCool] Resolve stream error: $e');
      return null;
    }
  }
}

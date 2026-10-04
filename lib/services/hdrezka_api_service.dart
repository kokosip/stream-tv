import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'safe_http_client.dart';

class HdrezkaSubtitle {
  final String language;
  final String url;

  HdrezkaSubtitle({
    required this.language,
    required this.url,
  });
}

class HdrezkaStreamResult {
  final String streamUrl;
  final String quality;
  final Map<String, String> qualities; // e.g. {'1080p': 'url', '720p': 'url'}
  final List<HdrezkaSubtitle> subtitles;
  final Map<String, String> headers;

  HdrezkaStreamResult({
    required this.streamUrl,
    required this.quality,
    required this.qualities,
    required this.subtitles,
    required this.headers,
  });
}

class HdrezkaSearchResult {
  final String id;
  final String title;
  final String url;
  final bool isSeries;

  HdrezkaSearchResult({
    required this.id,
    required this.title,
    required this.url,
    required this.isSeries,
  });
}

class HdrezkaApiService {
  static const String _mainUrl = 'https://hdrezka.ag';

  static List<String> _getTrash(List<String> arr, int count) {
    List<List<String>> trash = [];
    for (int i = 0; i < count; i++) {
      trash.add(arr);
    }
    return trash.reduce((acc, list) {
      final temp = <String>[];
      for (final ac in acc) {
        for (final li in list) {
          temp.add(ac + li);
        }
      }
      return temp;
    });
  }

  static String decryptStreamUrl(String data) {
    if (data.startsWith('[') || data.contains('https://')) {
      return data;
    }
    try {
      final trashList = ['@', '#', '!', '^', '\$'];
      final trashSet = [..._getTrash(trashList, 2), ..._getTrash(trashList, 3)];
      var trashString = data.replaceAll('#h', '').split('//_//').join('');

      for (final item in trashSet) {
        final temp = base64Encode(utf8.encode(item));
        trashString = trashString.replaceAll(temp, '');
      }

      return utf8.decode(base64Decode(trashString));
    } catch (e) {
      debugPrint('[HDRezka] Decrypt error: $e');
      return data;
    }
  }

  /// Search movies and series on HDRezka
  static Future<List<HdrezkaSearchResult>> search(String query) async {
    try {
      final searchUri = Uri.parse('$_mainUrl/search/?do=search&subaction=search&q=${Uri.encodeComponent(query)}');
      final resp = await SafeHttpClient.get(
        searchUri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Referer': '$_mainUrl/',
        },
      );

      if (resp.statusCode != 200) return [];

      final itemRegex = RegExp(
        r'<div class="b-content__inline_item[^"]*"[^>]*data-id="(\d+)"[^>]*>.*?<div class="b-content__inline_item-link">\s*<a href="([^"]+)">([^<]+)</a>',
        dotAll: true,
      );

      final results = <HdrezkaSearchResult>[];
      for (final match in itemRegex.allMatches(resp.body)) {
        final id = match.group(1)!;
        final url = match.group(2)!;
        final title = match.group(3)!.trim();
        final isSeries = url.contains('/series/');
        results.add(HdrezkaSearchResult(id: id, title: title, url: url, isSeries: isSeries));
      }

      return results;
    } catch (e) {
      debugPrint('[HDRezka] Search error: $e');
      return [];
    }
  }

  /// Resolve stream for a given media title and episode/season
  static Future<HdrezkaStreamResult?> resolveStream({
    required String title,
    int season = 1,
    int episode = 1,
    bool isMovie = false,
  }) async {
    try {
      final searchResults = await search(title);
      if (searchResults.isEmpty) return null;

      final target = searchResults.first;
      final dramaResp = await SafeHttpClient.get(
        Uri.parse(target.url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': '$_mainUrl/',
        },
      );

      if (dramaResp.statusCode != 200) return null;

      // Extract translators (voice/language)
      final transRegex = RegExp(r'<li[^>]*data-translator_id="(\d+)"[^>]*>([^<]+)</li>');
      final translators = transRegex.allMatches(dramaResp.body).map((m) => {
        'id': m.group(1)!,
        'name': m.group(2)!.trim(),
      }).toList();

      final translatorId = translators.isNotEmpty ? translators.first['id'] : '238';

      final now = DateTime.now().millisecondsSinceEpoch;
      final cdnResp = await SafeHttpClient.post(
        Uri.parse('$_mainUrl/ajax/get_cdn_series/?t=$now'),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': target.url,
          'X-Requested-With': 'XMLHttpRequest',
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        },
        body: {
          'id': target.id,
          'translator_id': translatorId ?? '238',
          'season': isMovie ? '1' : '$season',
          'episode': isMovie ? '1' : '$episode',
          'action': isMovie ? 'get_movie' : 'get_stream',
        },
      );

      if (cdnResp.statusCode != 200) return null;
      final json = jsonDecode(cdnResp.body) as Map<String, dynamic>;
      final rawUrl = json['url']?.toString();
      if (rawUrl == null || rawUrl.isEmpty) return null;

      final decrypted = decryptStreamUrl(rawUrl);

      // Parse qualities: [1080p]https://... or https://...,[720p]...
      final qualityMap = <String, String>{};
      final qualityRegex = RegExp(r'\[([^\]]+)\](https?://[^\s,]+)');
      for (final match in qualityRegex.allMatches(decrypted)) {
        final q = match.group(1)!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
        final u = match.group(2)!.trim();
        qualityMap[q] = u;
      }

      if (qualityMap.isEmpty) return null;

      // Select highest preferred quality: 1080p, 720p, 480p, 360p
      String selectedQuality = '720p';
      String selectedUrl = qualityMap.values.first;

      if (qualityMap.containsKey('1080p')) {
        selectedQuality = '1080p';
        selectedUrl = qualityMap['1080p']!;
      } else if (qualityMap.containsKey('720p')) {
        selectedQuality = '720p';
        selectedUrl = qualityMap['720p']!;
      } else if (qualityMap.containsKey('480p')) {
        selectedQuality = '480p';
        selectedUrl = qualityMap['480p']!;
      }

      // Parse Subtitles: [Русский]https://...,[English]https://...
      final subList = <HdrezkaSubtitle>[];
      final rawSubs = json['subtitle']?.toString();
      if (rawSubs != null && rawSubs.isNotEmpty) {
        final subRegex = RegExp(r'\[([^\]]+)\](https?://[^\s,]+)');
        for (final sm in subRegex.allMatches(rawSubs)) {
          final lang = sm.group(1)!.trim();
          final link = sm.group(2)!.trim();
          subList.add(HdrezkaSubtitle(language: lang, url: link));
        }
      }

      return HdrezkaStreamResult(
        streamUrl: selectedUrl,
        quality: selectedQuality,
        qualities: qualityMap,
        subtitles: subList,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': '$_mainUrl/',
        },
      );
    } catch (e) {
      debugPrint('[HDRezka] Resolve stream error: $e');
      return null;
    }
  }
}

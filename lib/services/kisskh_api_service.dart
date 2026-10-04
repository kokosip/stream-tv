import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import 'safe_http_client.dart';

class KissKhSubtitle {
  final String label;
  final String url;
  final String? language;

  KissKhSubtitle({
    required this.label,
    required this.url,
    this.language,
  });
}

class KissKhStreamResult {
  final String streamUrl;
  final String? quality;
  final Map<String, String> headers;
  final List<KissKhSubtitle> subtitles;

  KissKhStreamResult({
    required this.streamUrl,
    this.quality,
    required this.headers,
    this.subtitles = const [],
  });
}

class KissKhDramaResult {
  final int id;
  final String title;
  final String? thumbnail;
  final int? totalEpisodes;

  KissKhDramaResult({
    required this.id,
    required this.title,
    this.thumbnail,
    this.totalEpisodes,
  });
}

class KissKhEpisode {
  final int id;
  final int number;
  final int? sub;

  KissKhEpisode({
    required this.id,
    required this.number,
    this.sub,
  });
}

class KissKhApiService {
  static const String _baseUrl = 'https://kisskh.co';
  static const String _videoKeyMacro =
      'https://script.google.com/macros/s/AKfycbzn8B31PuDxzaMa9_CQ0VGEDasFqfzI5bXvjaIZH4DM8DNq9q6xj1ALvZNz_JT3jF0suA/exec';
  static const String _subKeyMacro =
      'https://script.google.com/macros/s/AKfycbyq6hTj0ZhlinYC6xbggtgo166tp6XaDKBCGtnYk8uOfYBUFwwxBui0sGXiu_zIFmA/exec';

  static const String _videoGuid = '62f176f3bb1b5b8e70e39932ad34a0c7';
  static const String _subGuid = 'VgV52sWhwvBSf8BsM3BRY9weWiiCbtGp';

  static final Uint8List _key = Uint8List.fromList([
    0x4F, 0x6B, 0xDA, 0xA3, 0x9E, 0x2F, 0x8C, 0xB0,
    0x7F, 0x5E, 0x72, 0x2D, 0x9E, 0xDE, 0xF3, 0x14,
  ]);

  static final Uint8List _iv = Uint8List.fromList([
    0x01, 0x50, 0x4A, 0xF3, 0x56, 0xE6, 0x19, 0xCF,
    0x2E, 0x42, 0xBB, 0xA6, 0x8C, 0x3F, 0x70, 0xF9,
  ]);

  static int _calculateHash64(String tokenStr) {
    int word = 0;
    for (int i = 0; i < tokenStr.length; i++) {
      int shifted = (word << 5) & 0xFFFFFFFF;
      if (shifted >= 0x80000000) shifted -= 0x100000000;
      word = shifted - word + tokenStr.codeUnitAt(i);
    }
    return word;
  }

  static String _generateLocalToken(int episodeId, String guid) {
    final tokenStr = '$episodeId$guid';
    final hash = _calculateHash64(tokenStr);
    final rawPayload = '|$hash|$episodeId||mg3c3b04ba|2.8.10|$guid|4830201|kisskh|kisskh|kisskh|kisskh|kisskh|kisskh|00|';

    final encKey = enc.Key(_key);
    final encIv = enc.IV(_iv);
    final encrypter = enc.Encrypter(enc.AES(encKey, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encrypt(rawPayload, iv: encIv);

    return encrypted.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  static Future<String> _fetchRemoteToken(int episodeId, {bool isSub = false}) async {
    try {
      final macroUrl = isSub ? _subKeyMacro : _videoKeyMacro;
      final uri = Uri.parse('$macroUrl?id=$episodeId&version=2.8.10');
      final resp = await SafeHttpClient.get(uri);
      if (resp.statusCode == 200) {
        try {
          final json = jsonDecode(resp.body);
          if (json is Map && json.containsKey('key')) {
            return json['key'].toString();
          }
        } catch (_) {
          return resp.body.trim();
        }
      }
    } catch (e) {
      debugPrint('[KissKH] Remote token error: $e');
    }
    return _generateLocalToken(episodeId, isSub ? _subGuid : _videoGuid);
  }

  /// Search dramas on KissKH
  static Future<List<KissKhDramaResult>> search(String query) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/DramaList/Search?q=${Uri.encodeComponent(query)}');
      final resp = await SafeHttpClient.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$_baseUrl/',
      });

      if (resp.statusCode != 200) return [];
      final List<dynamic> data = jsonDecode(resp.body);
      return data.map((item) {
        return KissKhDramaResult(
          id: item['id'] as int,
          title: item['title']?.toString() ?? '',
          thumbnail: item['thumbnail']?.toString(),
          totalEpisodes: item['episodesCount'] as int?,
        );
      }).toList();
    } catch (e) {
      debugPrint('[KissKH] Search error: $e');
      return [];
    }
  }

  /// Get list of episodes for a drama
  static Future<List<KissKhEpisode>> getEpisodes(int dramaId) async {
    try {
      final uri = Uri.parse('$_baseUrl/api/DramaList/Drama/$dramaId?isq=false');
      final resp = await SafeHttpClient.get(uri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': '$_baseUrl/',
      });

      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final episodes = data['episodes'] as List<dynamic>? ?? [];

      final list = episodes.map((ep) {
        return KissKhEpisode(
          id: ep['id'] as int,
          number: (ep['number'] as num).toInt(),
          sub: ep['sub'] as int?,
        );
      }).toList();

      list.sort((a, b) => a.number.compareTo(b.number));
      return list;
    } catch (e) {
      debugPrint('[KissKH] Get episodes error: $e');
      return [];
    }
  }

  /// Resolve direct stream for a specific episode ID
  static Future<KissKhStreamResult?> resolveEpisodeById({
    required int episodeId,
    int? dramaId,
    String? title,
    int? episodeNumber,
  }) async {
    try {
      final videoToken = await _fetchRemoteToken(episodeId, isSub: false);
      final videoUri = Uri.parse('$_baseUrl/api/DramaList/Episode/$episodeId.png?err=false&ts=&time=&kkey=$videoToken');
      
      final cleanTitle = (title ?? 'Drama').replaceAll(RegExp(r'[^a-zA-Z0-9]'), '-');
      final epNum = episodeNumber ?? 1;
      final referer = dramaId != null
          ? '$_baseUrl/Drama/$cleanTitle/Episode-$epNum?id=$dramaId&ep=$episodeId&page=0&pageSize=100'
          : '$_baseUrl/';

      final videoResp = await SafeHttpClient.get(videoUri, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': referer,
      });

      if (videoResp.statusCode != 200) return null;
      final videoData = jsonDecode(videoResp.body) as Map<String, dynamic>;
      final videoUrl = videoData['Video']?.toString() ?? videoData['ThirdParty']?.toString();
      if (videoUrl == null || videoUrl.isEmpty) return null;

      // Fetch Subtitles
      final subList = <KissKhSubtitle>[];
      try {
        final subToken = await _fetchRemoteToken(episodeId, isSub: true);
        final subUri = Uri.parse('$_baseUrl/api/Sub/$episodeId?kkey=$subToken');
        final subResp = await SafeHttpClient.get(subUri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': referer,
        });
        if (subResp.statusCode == 200) {
          final List<dynamic> subsJson = jsonDecode(subResp.body);
          for (final s in subsJson) {
            final src = s['src']?.toString();
            final label = s['label']?.toString() ?? 'Subtitle';
            final land = s['land']?.toString();
            if (src != null && src.isNotEmpty) {
              subList.add(KissKhSubtitle(label: label, url: src, language: land));
            }
          }
        }
      } catch (e) {
        debugPrint('[KissKH] Subtitle error: $e');
      }

      return KissKhStreamResult(
        streamUrl: videoUrl,
        quality: 'HLS Auto',
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': '$_baseUrl/',
          'Origin': _baseUrl,
        },
        subtitles: subList,
      );
    } catch (e) {
      debugPrint('[KissKH] Resolve episode error: $e');
      return null;
    }
  }

  /// Resolve stream and subtitles for a specific drama title & episode number
  static Future<KissKhStreamResult?> resolveStream({
    String? title,
    int? dramaId,
    required int episodeNumber,
  }) async {
    try {
      int? targetDramaId = dramaId;
      String targetTitle = title ?? '';

      if (targetDramaId == null) {
        if (title == null || title.isEmpty) return null;
        final searchResults = await search(title);
        if (searchResults.isEmpty) return null;
        final drama = searchResults.first;
        targetDramaId = drama.id;
        targetTitle = drama.title;
      }

      final episodes = await getEpisodes(targetDramaId);
      if (episodes.isEmpty) return null;

      final targetEpisode = episodes.firstWhere(
        (ep) => ep.number == episodeNumber,
        orElse: () => episodes.first,
      );

      return await resolveEpisodeById(
        episodeId: targetEpisode.id,
        dramaId: targetDramaId,
        title: targetTitle,
        episodeNumber: targetEpisode.number,
      );
    } catch (e) {
      debugPrint('[KissKH] Resolve stream error: $e');
      return null;
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'moviebox_api_service.dart';
import 'remote_config_service.dart';
import 'app_language_service.dart';

enum DownloadStatus {
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class DownloadItem {
  final String id;
  final String title;
  final String coverUrl;
  String streamUrl;
  String filePath;
  final String quality;
  final String provider;
  final int season;
  final int episode;
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String? errorMessage;
  final DateTime createdAt;
  Map<String, String>? headers;

  DownloadItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.streamUrl,
    required this.filePath,
    this.quality = "1080p",
    this.provider = "moviebox",
    this.season = 0,
    this.episode = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.downloading,
    this.errorMessage,
    DateTime? createdAt,
    this.headers,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isTvShow => season > 0 || episode > 0;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coverUrl': coverUrl,
    'streamUrl': streamUrl,
    'filePath': filePath,
    'quality': quality,
    'provider': provider,
    'season': season,
    'episode': episode,
    'totalBytes': totalBytes,
    'downloadedBytes': downloadedBytes,
    'status': status.name,
    'errorMessage': errorMessage,
    'createdAt': createdAt.toIso8601String(),
    if (headers != null) 'headers': headers,
  };

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      id: json['id'] ?? '',
      title: json['title'] ?? 'Untitled',
      coverUrl: json['coverUrl'] ?? '',
      streamUrl: json['streamUrl'] ?? '',
      filePath: json['filePath'] ?? '',
      quality: json['quality'] ?? '1080p',
      provider: json['provider'] ?? 'moviebox',
      season: json['season'] ?? 0,
      episode: json['episode'] ?? 0,
      totalBytes: json['totalBytes'] ?? 0,
      downloadedBytes: json['downloadedBytes'] ?? 0,
      status: DownloadStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadStatus.failed,
      ),
      errorMessage: json['errorMessage'],
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt']) ?? DateTime.now()
      : DateTime.now(),
      headers: json['headers'] != null ? Map<String, String>.from(json['headers']) : null,
    );
  }
}

class DownloadService {
  static final DownloadService instance = DownloadService._internal();
  DownloadService._internal();

  static const String _prefKey = 'stream_tv_saved_downloads_v1';

  final ValueNotifier<List<DownloadItem>> downloadsNotifier = ValueNotifier<List<DownloadItem>>([]);

  final Map<String, StreamSubscription<List<int>>> _activeSubscriptions = {};
  final Map<String, IOSink> _activeSinks = {};
  final Map<String, http.Client> _activeClients = {};
  final Map<String, int> _lastSpeedBytes = {};
  final Map<String, DateTime> _lastSpeedTime = {};
  final Map<String, double> _downloadSpeeds = {}; // bytes per sec

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await _loadFromPrefs();
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return "0 MB";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double dBytes = bytes.toDouble();
    while (dBytes >= 1024 && i < suffixes.length - 1) {
      dBytes /= 1024;
      i++;
    }
    return "${dBytes.toStringAsFixed(i >= 2 ? 1 : 0)} ${suffixes[i]}";
  }

  static String formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return "0 KB/s";
    return "${formatBytes(bytesPerSec.toInt())}/s";
  }

  double getDownloadSpeed(String id) {
    return _downloadSpeeds[id] ?? 0.0;
  }

  Future<Directory> _getDownloadDir() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory("${docsDir.path}/downloads");
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  String _sanitizeFileName(String name) {
    return name.replaceAll(RegExp(r'[^\w\.-]'), '_');
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(raw);
        final items = <DownloadItem>[];

        for (final entry in decoded) {
          try {
            final item = DownloadItem.fromJson(Map<String, dynamic>.from(entry));
            // Check if downloading when app was closed
            if (item.status == DownloadStatus.downloading) {
              item.status = DownloadStatus.paused;
            }
            // Verify file exists if marked completed
            if (item.status == DownloadStatus.completed) {
              final file = File(item.filePath);
              if (!file.existsSync()) {
                continue; // Skip or delete item if file physically missing
              }
            }
            items.add(item);
          } catch (e) {
            print("Error parsing saved download item: $e");
          }
        }
        downloadsNotifier.value = items;
      }
    } catch (e) {
      print("Error loading downloads from prefs: $e");
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        downloadsNotifier.value.map((e) => e.toJson()).toList(),
      );
      await prefs.setString(_prefKey, encoded);
    } catch (e) {
      print("Error saving downloads to prefs: $e");
    }
  }

  DownloadItem? getItem(String id) {
    try {
      return downloadsNotifier.value.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  bool isDownloaded(String id) {
    final item = getItem(id);
    if (item == null) return false;
    if (item.status != DownloadStatus.completed) return false;
    return File(item.filePath).existsSync();
  }

  bool isDownloading(String id) {
    final item = getItem(id);
    return item?.status == DownloadStatus.downloading;
  }

  Future<void> startDownload({
    required String id,
    required String title,
    required String coverUrl,
    required String streamUrl,
    String quality = "1080p",
    String provider = "moviebox",
    int season = 0,
    int episode = 0,
    Map<String, String>? headers,
  }) async {
    await init();

    // Check if item already exists
    var item = getItem(id);
    if (item != null) {
      final file = File(item.filePath);
      if (item.status == DownloadStatus.completed && file.existsSync()) {
        return;
      }
      if (item.status == DownloadStatus.downloading) {
        return;
      }
      // Re-download or resume
      item.status = DownloadStatus.downloading;
      item.errorMessage = null;
      item.streamUrl = streamUrl;
      if (headers != null) item.headers = headers;
    } else {
      final dir = await _getDownloadDir();
      final cleanTitle = _sanitizeFileName("${id}_$quality");
      final isDash = streamUrl.toLowerCase().contains('.mpd') || streamUrl.toLowerCase().contains('/dash/');
      final filePath = isDash ? "${dir.path}/$cleanTitle/index.mpd" : "${dir.path}/$cleanTitle.mp4";

      item = DownloadItem(
        id: id,
        title: title,
        coverUrl: coverUrl,
        streamUrl: streamUrl,
        filePath: filePath,
        quality: quality,
        provider: provider,
        season: season,
        episode: episode,
        totalBytes: 0,
        downloadedBytes: 0,
        status: DownloadStatus.downloading,
        headers: headers,
      );

      final current = List<DownloadItem>.from(downloadsNotifier.value);
      current.insert(0, item);
      downloadsNotifier.value = current;
    }

    _saveToPrefs();
    _executeDownload(item);
  }

  Map<String, String> _buildRequestHeaders(DownloadItem item) {
    final headers = <String, String>{};
    if (item.headers != null && item.headers!.isNotEmpty) {
      headers.addAll(item.headers!);
    }

    if (item.provider.toLowerCase() == '4khdhub') {
      headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      final streamLower = item.streamUrl.toLowerCase();
      if (!streamLower.contains('googleusercontent') &&
          !streamLower.contains('storage.googleapis') &&
          !streamLower.contains('pixeldrain') &&
          !streamLower.contains('cloudflarestorage') &&
          !streamLower.contains('snvhost') &&
          !streamLower.contains('r2.')) {
        headers['Referer'] = 'https://4khdhub.one/';
      }
    } else if (item.provider.toLowerCase() == 'dramachi') {
      headers['User-Agent'] =
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    } else {
      headers['User-Agent'] ??= 'ExoPlayer/2.18.1 (Linux; Android 11)';
      headers['Referer'] ??= RemoteConfigService.instance.movieboxStreamReferer;
    }
    return headers;
  }

  Future<bool> _refreshMovieBoxLink(DownloadItem item) async {
    try {
      final sId = item.id.contains('_') ? item.id.split('_').first : item.id;
      final resNum = int.tryParse(item.quality.replaceAll(RegExp(r'[^\d]'), '')) ?? 720;
      final freshData = await MovieBoxApiService().getResources(
        subjectId: sId,
        se: item.season,
        ep: item.episode,
        resolution: resNum,
      );
      final list = freshData['list'] as List<dynamic>? ?? [];
      for (final r in list) {
        final link = r['resourceLink'] ?? r['resource_link'];
        if (link != null && link.toString().isNotEmpty) {
          item.streamUrl = link.toString();
          if (r['headers'] is Map) {
            item.headers = Map<String, String>.from(r['headers']);
          } else {
            final sc = (r['signCookie'] ?? '').toString();
            if (sc.isNotEmpty) {
              item.headers = {
                'User-Agent': 'ExoPlayer/2.18.1 (Linux; Android 11)',
                'Referer': RemoteConfigService.instance.movieboxStreamReferer,
                'Cookie': sc.trim(),
              };
            }
          }
          _updateItemInList(item);
          await _saveToPrefs();
          return true;
        }
      }
    } catch (e) {
      print("Error refreshing MovieBox download link: $e");
    }
    return false;
  }

  Future<void> _executeDownload(DownloadItem item) async {
    final client = http.Client();
    _activeClients[item.id] = client;

    try {
      final isDash = item.streamUrl.toLowerCase().contains('.mpd') || item.streamUrl.toLowerCase().contains('/dash/');
      if (isDash) {
        await _executeDashDownload(item, client);
        return;
      }

      final file = File(item.filePath);
      int startByte = 0;
      if (item.downloadedBytes > 0 && await file.exists()) {
        startByte = await file.length();
        item.downloadedBytes = startByte;
      } else {
        item.downloadedBytes = 0;
      }

      var reqHeaders = _buildRequestHeaders(item);
      var request = http.Request('GET', Uri.parse(item.streamUrl));
      request.headers.addAll(reqHeaders);

      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
      }

      var response = await client.send(request);

      // If CDN link expired or rejected (403, 410, 428), attempt auto-refresh from MovieBox API
      if ((response.statusCode == 403 || response.statusCode == 410 || response.statusCode == 428) &&
          item.provider.toLowerCase() == 'moviebox') {
        final refreshed = await _refreshMovieBoxLink(item);
        if (refreshed) {
          reqHeaders = _buildRequestHeaders(item);
          request = http.Request('GET', Uri.parse(item.streamUrl));
          request.headers.addAll(reqHeaders);
          if (startByte > 0) {
            request.headers['Range'] = 'bytes=$startByte-';
          }
          response = await client.send(request);
        }
      }

      if (response.statusCode != 200 && response.statusCode != 206) {
        throw Exception("Server returned HTTP ${response.statusCode}");
      }

      // Calculate totalBytes accurately from Content-Range or Content-Length
      int totalBytes = item.totalBytes;
      if (response.headers.containsKey('content-range')) {
        final cr = response.headers['content-range']!;
        final parts = cr.split('/');
        if (parts.length > 1) {
          totalBytes = int.tryParse(parts.last) ?? totalBytes;
        }
      } else if (response.contentLength != null && response.contentLength! > 0) {
        if (response.statusCode == 206) {
          totalBytes = startByte + response.contentLength!;
        } else {
          totalBytes = response.contentLength!;
        }
      }

      final isPartial = response.statusCode == 206 && startByte > 0;
      if (!isPartial) {
        item.downloadedBytes = 0;
      }

      item.totalBytes = totalBytes > 0 ? totalBytes : item.totalBytes;
      item.status = DownloadStatus.downloading;
      item.errorMessage = null;
      _updateItemInList(item);

      final sink = file.openWrite(mode: isPartial ? FileMode.append : FileMode.write);
      _activeSinks[item.id] = sink;

      var lastNotifyTime = DateTime.now();
      _lastSpeedTime[item.id] = DateTime.now();
      _lastSpeedBytes[item.id] = item.downloadedBytes;

      final subscription = response.stream.listen(
        (chunk) {
          sink.add(chunk);
          item.downloadedBytes += chunk.length;

          final now = DateTime.now();
          final speedDiff = now.difference(_lastSpeedTime[item.id] ?? now).inMilliseconds;
          if (speedDiff >= 1000) {
            final bytesDiff = item.downloadedBytes - (_lastSpeedBytes[item.id] ?? 0);
            _downloadSpeeds[item.id] = (bytesDiff / (speedDiff / 1000.0));
            _lastSpeedTime[item.id] = now;
            _lastSpeedBytes[item.id] = item.downloadedBytes;
          }

          if (now.difference(lastNotifyTime).inMilliseconds >= 400) {
            lastNotifyTime = now;
            downloadsNotifier.value = List<DownloadItem>.from(downloadsNotifier.value);
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          _cleanupHandles(item.id);

          item.status = DownloadStatus.completed;
          _downloadSpeeds.remove(item.id);
          _updateItemInList(item);
          await _saveToPrefs();
        },
        onError: (err) async {
          await sink.flush();
          await sink.close();
          _cleanupHandles(item.id);

          item.status = DownloadStatus.failed;
          item.errorMessage = _sanitizeDownloadError(err);
          _downloadSpeeds.remove(item.id);
          _updateItemInList(item);
          await _saveToPrefs();
        },
        cancelOnError: true,
      );

      _activeSubscriptions[item.id] = subscription;
    } catch (e) {
      _cleanupHandles(item.id);
      item.status = DownloadStatus.failed;
      item.errorMessage = _sanitizeDownloadError(e);
      _downloadSpeeds.remove(item.id);
      _updateItemInList(item);
      await _saveToPrefs();
    }
  }

  Future<void> _executeDashDownload(
    DownloadItem item,
    http.Client client,
  ) async {
    try {
      final cleanTitle = _sanitizeFileName("${item.id}_${item.quality}");
      final docsDir = await getApplicationDocumentsDirectory();
      final folder = Directory("${docsDir.path}/downloads/$cleanTitle");
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final manifestFile = File("${folder.path}/index.mpd");
    item.filePath = manifestFile.path;

    var reqHeaders = _buildRequestHeaders(item);
    var mpdRes = await client.get(Uri.parse(item.streamUrl), headers: reqHeaders);

    // Auto-refresh if 403, 410, 428
    if ((mpdRes.statusCode == 403 || mpdRes.statusCode == 410 || mpdRes.statusCode == 428) &&
        item.provider.toLowerCase() == 'moviebox') {
      final refreshed = await _refreshMovieBoxLink(item);
      if (refreshed) {
        reqHeaders = _buildRequestHeaders(item);
        mpdRes = await client.get(Uri.parse(item.streamUrl), headers: reqHeaders);
      }
    }

    if (mpdRes.statusCode != 200) {
      throw Exception("Server returned HTTP ${mpdRes.statusCode} while fetching manifest");
    }

    final mpdXml = mpdRes.body;
    await manifestFile.writeAsString(mpdXml);

    final baseUrl = item.streamUrl.substring(0, item.streamUrl.lastIndexOf('/') + 1);

    // Parse duration
    final durMatch = RegExp(r'mediaPresentationDuration="PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d\.]+)S)?"').firstMatch(mpdXml);
    double totalSeconds = 0;
    if (durMatch != null) {
      final h = double.tryParse(durMatch.group(1) ?? '0') ?? 0;
      final m = double.tryParse(durMatch.group(2) ?? '0') ?? 0;
      final s = double.tryParse(durMatch.group(3) ?? '0') ?? 0;
      totalSeconds = (h * 3600) + (m * 60) + s;
    }

    final segDurMatch = RegExp(r'<SegmentTemplate[^>]*timescale="(\d+)"[^>]*duration="(\d+)"').firstMatch(mpdXml);
    double segSec = 5.0;
    if (segDurMatch != null) {
      final ts = double.tryParse(segDurMatch.group(1) ?? '1') ?? 1;
      final dur = double.tryParse(segDurMatch.group(2) ?? '5') ?? 5;
      segSec = dur / ts;
    }
    final totalChunks = totalSeconds > 0 ? (totalSeconds / segSec).ceil() : 0;

    // Parse Representation IDs
    final targetRes = int.tryParse(item.quality.replaceAll(RegExp(r'[^\d]'), '')) ?? 1080;
    final videoRepMatches = RegExp(r'<Representation[^>]*id="([^"]+)"[^>]*mimeType="video[^"]*"[^>]*height="(\d+)"').allMatches(mpdXml).toList();
    if (videoRepMatches.isEmpty) {
      videoRepMatches.addAll(RegExp(r'<Representation[^>]*height="(\d+)"[^>]*id="([^"]+)"').allMatches(mpdXml));
    }

    String videoRepId = "0";
    if (videoRepMatches.isNotEmpty) {
      var bestDiff = 99999;
      for (final m in videoRepMatches) {
        final id = m.group(1) ?? "0";
        final h = int.tryParse(m.group(2) ?? "1080") ?? 1080;
        final diff = (h - targetRes).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          videoRepId = id;
        }
      }
    }

    // Audio representation
    final audioRepMatch = RegExp(r'<Representation[^>]*id="([^"]+)"[^>]*mimeType="audio').firstMatch(mpdXml) ??
        RegExp(r'<Representation[^>]*mimeType="audio[^"]*"[^>]*id="([^"]+)"').firstMatch(mpdXml);
    final audioRepId = audioRepMatch?.group(1) ?? "3";

    // Download init segments
    final videoInitFile = File("${folder.path}/init-stream$videoRepId.m4s");
    if (!await videoInitFile.exists() || await videoInitFile.length() == 0) {
      final vInitRes = await client.get(Uri.parse('${baseUrl}init-stream$videoRepId.m4s'), headers: reqHeaders);
      if (vInitRes.statusCode == 200) {
        await videoInitFile.writeAsBytes(vInitRes.bodyBytes);
      }
    }

    final audioInitFile = File("${folder.path}/init-stream$audioRepId.m4s");
    if (!await audioInitFile.exists() || await audioInitFile.length() == 0) {
      final aInitRes = await client.get(Uri.parse('${baseUrl}init-stream$audioRepId.m4s'), headers: reqHeaders);
      if (aInitRes.statusCode == 200) {
        await audioInitFile.writeAsBytes(aInitRes.bodyBytes);
      }
    }

    // Check existing downloaded chunks for resume support
    int completedChunks = 0;
    int currentBytes = (await videoInitFile.exists() ? await videoInitFile.length() : 0) +
        (await audioInitFile.exists() ? await audioInitFile.length() : 0);

    for (int i = 1; i <= totalChunks; i++) {
      final padIdx = i.toString().padLeft(5, '0');
      final vChunk = File("${folder.path}/chunk-stream$videoRepId-$padIdx.m4s");
      final aChunk = File("${folder.path}/chunk-stream$audioRepId-$padIdx.m4s");
      if (await vChunk.exists() && await aChunk.exists()) {
        final vLen = await vChunk.length();
        final aLen = await aChunk.length();
        if (vLen > 0 && aLen > 0) {
          completedChunks++;
          currentBytes += vLen + aLen;
        }
      }
    }

    item.downloadedBytes = currentBytes;
    if (item.totalBytes <= 0 && totalChunks > 0 && completedChunks > 0) {
      item.totalBytes = ((currentBytes / completedChunks) * totalChunks).toInt();
    }
    item.status = DownloadStatus.downloading;
    item.errorMessage = null;
    _updateItemInList(item);

    var lastNotifyTime = DateTime.now();
    _lastSpeedTime[item.id] = DateTime.now();
    _lastSpeedBytes[item.id] = item.downloadedBytes;

    for (int i = 1; i <= totalChunks; i++) {
      if (item.status != DownloadStatus.downloading) {
        break;
      }
      final padIdx = i.toString().padLeft(5, '0');
      final vFile = File("${folder.path}/chunk-stream$videoRepId-$padIdx.m4s");
      final aFile = File("${folder.path}/chunk-stream$audioRepId-$padIdx.m4s");

      if (await vFile.exists() && await aFile.exists()) {
        final vLen = await vFile.length();
        final aLen = await aFile.length();
        if (vLen > 0 && aLen > 0) {
          continue;
        }
      }

      // Download video chunk
      final vChunkUrl = '${baseUrl}chunk-stream$videoRepId-$padIdx.m4s';
      var vRes = await client.get(Uri.parse(vChunkUrl), headers: reqHeaders);
      if ((vRes.statusCode == 403 || vRes.statusCode == 410) && item.provider.toLowerCase() == 'moviebox') {
        final refreshed = await _refreshMovieBoxLink(item);
        if (refreshed) {
          reqHeaders = _buildRequestHeaders(item);
          vRes = await client.get(Uri.parse(vChunkUrl), headers: reqHeaders);
        }
      }
      if (vRes.statusCode != 200) {
        throw Exception("Server returned HTTP ${vRes.statusCode} for chunk $i");
      }
      await vFile.writeAsBytes(vRes.bodyBytes);
      item.downloadedBytes += vRes.bodyBytes.length;

      // Download audio chunk
      final aChunkUrl = '${baseUrl}chunk-stream$audioRepId-$padIdx.m4s';
      var aRes = await client.get(Uri.parse(aChunkUrl), headers: reqHeaders);
      if (aRes.statusCode == 200) {
        await aFile.writeAsBytes(aRes.bodyBytes);
        item.downloadedBytes += aRes.bodyBytes.length;
      }

      completedChunks++;
      if (item.totalBytes <= 0 && totalChunks > 0) {
        item.totalBytes = ((item.downloadedBytes / completedChunks) * totalChunks).toInt();
      }

      final now = DateTime.now();
      final speedDiff = now.difference(_lastSpeedTime[item.id] ?? now).inMilliseconds;
      if (speedDiff >= 1000) {
        final bytesDiff = item.downloadedBytes - (_lastSpeedBytes[item.id] ?? 0);
        _downloadSpeeds[item.id] = (bytesDiff / (speedDiff / 1000.0));
        _lastSpeedTime[item.id] = now;
        _lastSpeedBytes[item.id] = item.downloadedBytes;
      }

      if (now.difference(lastNotifyTime).inMilliseconds >= 400) {
        lastNotifyTime = now;
        downloadsNotifier.value = List<DownloadItem>.from(downloadsNotifier.value);
      }
    }

    if (item.status == DownloadStatus.downloading) {
      item.status = DownloadStatus.completed;
      _downloadSpeeds.remove(item.id);
      _cleanupHandles(item.id);
      _updateItemInList(item);
      await _saveToPrefs();
    }
  } catch (e) {
    _cleanupHandles(item.id);
    item.status = DownloadStatus.failed;
    item.errorMessage = _sanitizeDownloadError(e);
    _downloadSpeeds.remove(item.id);
    _updateItemInList(item);
    await _saveToPrefs();
  }
}

  String _sanitizeDownloadError(dynamic error) {
    final errStr = error.toString().toLowerCase();

    // MovieBox TUI v0.1.24 Sanitized Download Failure Notices (DownloadError::user_message())
    if (errStr.contains('403') || errStr.contains('401') || errStr.contains('forbidden')) {
      return AppLanguageService.tr(
        en: "Server access denied (HTTP 403). Link expired or forbidden.",
        id: "Izin server ditolak (HTTP 403). Link kedaluwarsa atau akses ditolak.",
      );
    }
    if (errStr.contains('404') || errStr.contains('410') || errStr.contains('not found')) {
      return AppLanguageService.tr(
        en: "File is no longer available on source server (HTTP 404).",
        id: "File sudah tidak tersedia di server sumber (HTTP 404).",
      );
    }
    if (errStr.contains('429')) {
      return AppLanguageService.tr(
        en: "Server download rate limit exceeded. Please try again later.",
        id: "Batas unduhan server terlampaui (Rate limit). Coba lagi beberapa saat lagi.",
      );
    }
    if (errStr.contains('500') || errStr.contains('502') || errStr.contains('503') || errStr.contains('504')) {
      return AppLanguageService.tr(
        en: "Download server encountered an issue. Please try again later.",
        id: "Server unduhan sedang mengalami gangguan. Coba lagi nanti.",
      );
    }
    if (errStr.contains('timeout') || errStr.contains('timed out')) {
      return AppLanguageService.tr(
        en: "Connection to download server timed out.",
        id: "Koneksi ke server unduhan waktu habis (Timed out).",
      );
    }
    if (errStr.contains('socketexception') ||
        errStr.contains('connection closed') ||
        errStr.contains('connection reset') ||
        errStr.contains('network is unreachable') ||
        errStr.contains('handshake failed')) {
      return AppLanguageService.tr(
        en: "Internet connection lost during download.",
        id: "Koneksi internet terputus saat mengunduh.",
      );
    }
    if (errStr.contains('os error') || errStr.contains('no space') || errStr.contains('filesystemexception')) {
      return AppLanguageService.tr(
        en: "Failed to save file. Check your device storage space.",
        id: "Gagal menyimpan file. Periksa sisa ruang penyimpanan perangkat.",
      );
    }
    return AppLanguageService.tr(
      en: "Download failed: ${error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}",
      id: "Unduhan gagal: ${error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}",
    );
  }

  void _updateItemInList(DownloadItem item) {
    final list = List<DownloadItem>.from(downloadsNotifier.value);
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx != -1) {
      list[idx] = item;
      downloadsNotifier.value = list;
    }
  }

  void _cleanupHandles(String id) {
    _activeSubscriptions.remove(id);
    _activeSinks.remove(id);
    _activeClients[id]?.close();
    _activeClients.remove(id);
    _lastSpeedBytes.remove(id);
    _lastSpeedTime.remove(id);
  }

  Future<void> cancelDownload(String id) async {
    final sub = _activeSubscriptions[id];
    await sub?.cancel();
    final sink = _activeSinks[id];
    await sink?.close();
    _cleanupHandles(id);
    _downloadSpeeds.remove(id);

    final item = getItem(id);
    if (item != null) {
      item.status = DownloadStatus.cancelled;
      final file = File(item.filePath);
      if (item.filePath.endsWith('.mpd') && file.parent.existsSync()) {
        try {
          await file.parent.delete(recursive: true);
        } catch (_) {}
      } else if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      final list = List<DownloadItem>.from(downloadsNotifier.value);
      list.removeWhere((e) => e.id == id);
      downloadsNotifier.value = list;
      await _saveToPrefs();
    }
  }

  Future<void> pauseDownload(String id) async {
    final sub = _activeSubscriptions[id];
    await sub?.cancel();
    final sink = _activeSinks[id];
    await sink?.close();
    _cleanupHandles(id);
    _downloadSpeeds.remove(id);

    final item = getItem(id);
    if (item != null) {
      item.status = DownloadStatus.paused;
      _updateItemInList(item);
      await _saveToPrefs();
    }
  }

  Future<void> resumeDownload(String id) async {
    final item = getItem(id);
    if (item == null) return;
    item.status = DownloadStatus.downloading;
    item.errorMessage = null;
    _updateItemInList(item);
    _executeDownload(item);
  }

  Future<void> deleteDownload(String id) async {
    await cancelDownload(id);
    final item = getItem(id);
    if (item != null) {
      final file = File(item.filePath);
      if (item.filePath.endsWith('.mpd') && file.parent.existsSync()) {
        try {
          await file.parent.delete(recursive: true);
        } catch (_) {}
      } else if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      final list = List<DownloadItem>.from(downloadsNotifier.value);
      list.removeWhere((e) => e.id == id);
      downloadsNotifier.value = list;
      await _saveToPrefs();
    }
  }
}

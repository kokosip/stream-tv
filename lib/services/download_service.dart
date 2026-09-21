import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'moviebox_api_service.dart';

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
  final String filePath;
  final String quality;
  final String provider;
  final int season;
  final int episode;
  int totalBytes;
  int downloadedBytes;
  DownloadStatus status;
  String? errorMessage;
  final DateTime createdAt;


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
  }) async {
    await init();

    // Check if item already exists
    var item = getItem(id);
    if (item != null) {
      if (item.status == DownloadStatus.completed && File(item.filePath).existsSync()) {
        return;
      }
      if (item.status == DownloadStatus.downloading) {
        return;
      }
      // Re-download or resume
      item.status = DownloadStatus.downloading;
      item.errorMessage = null;
    } else {
      final dir = await _getDownloadDir();
      final cleanTitle = _sanitizeFileName("${id}_$quality");
      final filePath = "${dir.path}/$cleanTitle.mp4";

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
      );

      final current = List<DownloadItem>.from(downloadsNotifier.value);
      current.insert(0, item);
      downloadsNotifier.value = current;
    }

    _saveToPrefs();
    _executeDownload(item);
  }

  Future<void> _executeDownload(DownloadItem item) async {
    final client = http.Client();
    _activeClients[item.id] = client;

    try {
      final file = File(item.filePath);
      int startByte = 0;
      if (item.downloadedBytes > 0 && await file.exists()) {
        startByte = await file.length();
        item.downloadedBytes = startByte;
      } else {
        item.downloadedBytes = 0;
      }

      var request = http.Request('GET', Uri.parse(item.streamUrl));
      if (item.provider.toLowerCase() == '4khdhub') {
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
        request.headers['Referer'] = 'https://4khdhub.one/';
      } else if (item.provider.toLowerCase() == 'dramachi') {
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
      } else {
        // Use media player User-Agent (ExoPlayer) which MovieBox CDN accepts (browser UAs return 428 Forbidden)
        request.headers['User-Agent'] = 'ExoPlayer/2.18.1 (Linux; Android 11)';
      }

      if (startByte > 0) {
        request.headers['Range'] = 'bytes=$startByte-';
      }

      var response = await client.send(request);

      // If CDN link expired or rejected (403, 410, 428), attempt auto-refresh from MovieBox API
      if ((response.statusCode == 403 || response.statusCode == 410 || response.statusCode == 428) &&
          item.provider.toLowerCase() == 'moviebox') {
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
          String? freshUrl;
          for (final r in list) {
            final link = r['resourceLink'] ?? r['resource_link'];
            if (link != null && link.toString().isNotEmpty) {
              freshUrl = link.toString();
              break;
            }
          }

          if (freshUrl != null && freshUrl.isNotEmpty) {
            item.streamUrl = freshUrl;
            _updateItemInList(item);
            await _saveToPrefs();

            request = http.Request('GET', Uri.parse(item.streamUrl));
            request.headers['User-Agent'] = 'ExoPlayer/2.18.1 (Linux; Android 11)';
            if (startByte > 0) {
              request.headers['Range'] = 'bytes=$startByte-';
            }
            response = await client.send(request);
          }
        } catch (_) {}
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
          // Calculate speed every 1 second
          final speedDiff = now.difference(_lastSpeedTime[item.id] ?? now).inMilliseconds;
          if (speedDiff >= 1000) {
            final bytesDiff = item.downloadedBytes - (_lastSpeedBytes[item.id] ?? 0);
            _downloadSpeeds[item.id] = (bytesDiff / (speedDiff / 1000.0));
            _lastSpeedTime[item.id] = now;
            _lastSpeedBytes[item.id] = item.downloadedBytes;
          }

          // Throttle ValueNotifier updates to every 400ms for smooth UI without lagging
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
          item.errorMessage = err.toString();
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
      item.errorMessage = e.toString();
      _downloadSpeeds.remove(item.id);
      _updateItemInList(item);
      await _saveToPrefs();
    }
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
      // Delete temporary partial file
      final file = File(item.filePath);
      if (await file.exists()) {
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
      if (await file.exists()) {
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

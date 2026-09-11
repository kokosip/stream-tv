import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

class AppReleaseInfo {
  final String version;
  final String tagName;
  final String title;
  final String changelog;
  final String publishedAt;
  final String apkDownloadUrl;
  final int apkSizeBytes;

  AppReleaseInfo({
    required this.version,
    required this.tagName,
    required this.title,
    required this.changelog,
    required this.publishedAt,
    required this.apkDownloadUrl,
    required this.apkSizeBytes,
  });
}

class UpdateService {
  UpdateService._internal();
  static final UpdateService instance = UpdateService._internal();

  static const String _githubRepo = "kokosip/stream-tv";
  static const String _releasesApiUrl = "https://api.github.com/repos/$_githubRepo/releases/latest";

  /// Compares two semver strings (e.g. '1.2.5' vs '1.2.4').
  /// Returns true if [remoteVersion] is strictly newer than [currentVersion].
  static bool isNewerVersion(String remoteVersion, String currentVersion) {
    try {
      final cleanRemote = remoteVersion.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanCurrent = currentVersion.replaceAll(RegExp(r'[^0-9.]'), '');

      final rParts = cleanRemote.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final cParts = cleanCurrent.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      final maxLen = rParts.length > cParts.length ? rParts.length : cParts.length;
      while (rParts.length < maxLen) {
        rParts.add(0);
      }
      while (cParts.length < maxLen) {
        cParts.add(0);
      }

      for (int i = 0; i < maxLen; i++) {
        if (rParts[i] > cParts[i]) return true;
        if (rParts[i] < cParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Checks GitHub API for newer releases. Returns [AppReleaseInfo] if an update is found.
  Future<AppReleaseInfo?> checkForUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(_releasesApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'MovieBox-StreamTV-App',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final Map<String, dynamic> data = jsonDecode(response.body);
      final String tagName = data['tag_name'] ?? '';
      final String releaseTitle = data['name'] ?? tagName;
      final String body = data['body'] ?? '';
      final String publishedAt = data['published_at'] ?? '';
      final List<dynamic> assets = data['assets'] ?? [];

      final remoteVersion = tagName.replaceAll(RegExp(r'^[vV]'), '');

      if (!isNewerVersion(remoteVersion, currentVersion)) {
        return null; // Already up to date
      }

      // Locate APK asset in release
      String apkUrl = '';
      int apkSize = 0;

      for (final asset in assets) {
        final name = (asset['name'] ?? '').toString().toLowerCase();
        if (name.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] ?? '';
          apkSize = asset['size'] ?? 0;
          break;
        }
      }

      // Fallback to first asset if no .apk suffix matched
      if (apkUrl.isEmpty && assets.isNotEmpty) {
        apkUrl = assets.first['browser_download_url'] ?? '';
        apkSize = assets.first['size'] ?? 0;
      }

      if (apkUrl.isEmpty) {
        return null;
      }

      return AppReleaseInfo(
        version: remoteVersion,
        tagName: tagName,
        title: releaseTitle,
        changelog: body,
        publishedAt: publishedAt,
        apkDownloadUrl: apkUrl,
        apkSizeBytes: apkSize,
      );
    } catch (e) {
      return null;
    }
  }

  /// Downloads the release APK and automatically launches the Android package installer.
  Future<void> downloadAndInstall({
    required AppReleaseInfo release,
    required void Function(int receivedBytes, int totalBytes) onProgress,
    required void Function(String error) onError,
    required void Function() onCompleted,
  }) async {
    http.Client? client;
    IOSink? sink;
    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(release.apkDownloadUrl));
      request.headers['User-Agent'] = 'MovieBox-StreamTV-App';

      final response = await client.send(request);

      if (response.statusCode != 200) {
        onError("Gagal mengunduh file update (HTTP ${response.statusCode})");
        return;
      }

      final totalBytes = response.contentLength ?? release.apkSizeBytes;
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/MovieBox_${release.version}.apk';
      final file = File(filePath);

      if (await file.exists()) {
        await file.delete();
      }

      sink = file.openWrite();
      int receivedBytes = 0;

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress(receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null;

      onCompleted();

      // Trigger Android native package installer
      final result = await OpenFilex.open(
        filePath,
        type: "application/vnd.android.package-archive",
      );

      if (result.type != ResultType.done) {
        onError("Pemasangan APK: ${result.message}");
      }
    } catch (e) {
      onError("Terjadi kesalahan saat mengunduh: $e");
    } finally {
      client?.close();
      await sink?.close();
    }
  }
}

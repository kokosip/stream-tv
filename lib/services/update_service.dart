import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'app_language_service.dart';

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

  /// Opens an external URL in the system browser or default handler.
  Future<bool> openInBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Downloads the release APK and automatically launches the Android package installer.
  /// Supports HTTP Range resumption and auto-retries for unstable network connections.
  Future<void> downloadAndInstall({
    required AppReleaseInfo release,
    required void Function(int receivedBytes, int totalBytes) onProgress,
    required void Function(String error) onError,
    required void Function() onCompleted,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final apkPath = '${tempDir.path}/MovieBox_${release.version}.apk';
    final partPath = '$apkPath.part';
    final partFile = File(partPath);
    final apkFile = File(apkPath);

    int totalBytes = release.apkSizeBytes;
    int downloadedBytes = 0;

    if (await partFile.exists()) {
      downloadedBytes = await partFile.length();
    }

    const int maxRetries = 5;
    int retryCount = 0;
    bool completed = false;

    while (!completed && retryCount < maxRetries) {
      http.Client? client;
      IOSink? sink;
      try {
        client = http.Client();
        final request = http.Request('GET', Uri.parse(release.apkDownloadUrl));
        request.headers['User-Agent'] = 'MovieBox-StreamTV-App';

        if (downloadedBytes > 0) {
          request.headers['Range'] = 'bytes=$downloadedBytes-';
        }

        final response = await client.send(request);

        // Check status code: 200 (full), 206 (partial content)
        if (response.statusCode != 200 && response.statusCode != 206) {
          if (response.statusCode == 416) {
            // Requested range not satisfiable - file may be fully downloaded or invalid
            if (await partFile.exists()) {
              await partFile.delete();
            }
            downloadedBytes = 0;
            retryCount++;
            continue;
          }
          onError(
            AppLanguageService.tr(
              en: "Failed to download update file (HTTP ${response.statusCode})",
              id: "Gagal mengunduh file update (HTTP ${response.statusCode})",
            ),
          );
          return;
        }

        final isPartial = response.statusCode == 206;
        if (!isPartial && downloadedBytes > 0) {
          // Server did not accept Range request, reset download from beginning
          downloadedBytes = 0;
          if (await partFile.exists()) {
            await partFile.delete();
          }
        }

        // Determine totalBytes accurately from headers
        if (response.headers.containsKey('content-range')) {
          final match = RegExp(r'/(\d+)').firstMatch(response.headers['content-range'] ?? '');
          if (match != null) {
            totalBytes = int.tryParse(match.group(1)!) ?? totalBytes;
          }
        } else if (response.contentLength != null && response.contentLength! > 0) {
          totalBytes = isPartial ? (downloadedBytes + response.contentLength!) : response.contentLength!;
        }

        sink = partFile.openWrite(mode: isPartial ? FileMode.append : FileMode.write);

        await for (final chunk in response.stream) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          onProgress(downloadedBytes, totalBytes);
        }

        await sink.flush();
        await sink.close();
        sink = null;

        // Verify if we actually reached the total expected size
        if (totalBytes > 0 && downloadedBytes < totalBytes) {
          throw Exception(
            AppLanguageService.tr(
              en: "Connection dropped before download completed ($downloadedBytes / $totalBytes bytes)",
              id: "Koneksi terputus sebelum unduhan selesai ($downloadedBytes / $totalBytes bytes)",
            ),
          );
        }

        completed = true;
      } catch (e) {
        retryCount++;
        if (await partFile.exists()) {
          downloadedBytes = await partFile.length();
        }
        if (retryCount >= maxRetries) {
          onError(
            AppLanguageService.tr(
              en: "An error occurred while downloading: $e",
              id: "Terjadi kesalahan saat mengunduh: $e",
            ),
          );
          return;
        }
        // Exponential backoff before retry (2s, 4s, 6s...)
        await Future.delayed(Duration(seconds: retryCount * 2));
      } finally {
        try {
          await sink?.close();
        } catch (_) {}
        client?.close();
      }
    }

    if (!completed) return;

    try {
      if (await apkFile.exists()) {
        await apkFile.delete();
      }
      await partFile.rename(apkPath);

      onCompleted();

      // Trigger Android native package installer
      final result = await OpenFilex.open(
        apkPath,
        type: "application/vnd.android.package-archive",
      );

      if (result.type != ResultType.done) {
        onError(
          AppLanguageService.tr(
            en: "APK Installation: ${result.message}",
            id: "Pemasangan APK: ${result.message}",
          ),
        );
      }
    } catch (e) {
      onError(
        AppLanguageService.tr(
          en: "Failed to open installation file: $e",
          id: "Gagal membuka file instalasi: $e",
        ),
      );
    }
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/download_service.dart';
import '../services/app_language_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatefulWidget {
  final bool isTv;

  const DownloadsScreen({
    super.key,
    this.isTv = false,
  });

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadService _downloadService = DownloadService.instance;

  @override
  void initState() {
    super.initState();
    _downloadService.init();
  }

  void _playOffline(DownloadItem item) {
    if (!File(item.filePath).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguageService.tr(
              en: "File not found. It may have been deleted.",
              id: "File tidak ditemukan. Mungkin sudah terhapus dari penyimpanan.",
            ),
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          streamUrl: item.filePath,
          title: item.title,
          subjectId: item.id,
          provider: item.provider,
          season: item.season,
          episode: item.episode,
          coverUrl: item.coverUrl,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(DownloadItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text(
              AppLanguageService.tr(en: "Delete Download?", id: "Hapus Unduhan?"),
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          AppLanguageService.tr(
            en: "Are you sure you want to delete \"${item.title}\"? The file will be removed from your device storage.",
            id: "Apakah Anda yakin ingin menghapus \"${item.title}\"? File video akan dihapus dari penyimpanan perangkat Anda.",
          ),
          style: GoogleFonts.outfit(color: Colors.grey.shade300, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              AppLanguageService.tr(en: "Cancel", id: "Batal"),
              style: GoogleFonts.outfit(color: Colors.grey.shade400),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.shade700,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppLanguageService.tr(en: "Delete", id: "Hapus"),
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _downloadService.deleteDownload(item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.tr(
                en: "\"${item.title}\" deleted from storage",
                id: "\"${item.title}\" berhasil dihapus dari memori",
              ),
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: const Color(0xFF222222),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<DownloadItem>>(
      valueListenable: _downloadService.downloadsNotifier,
      builder: (context, items, _) {
        final activeDownloads = items.where((i) => i.status == DownloadStatus.downloading || i.status == DownloadStatus.paused).toList();
        final completedDownloads = items.where((i) => i.status == DownloadStatus.completed).toList();
        final failedDownloads = items.where((i) => i.status == DownloadStatus.failed).toList();

        // Calculate total storage used by completed downloads
        int totalStorageBytes = 0;
        for (final item in completedDownloads) {
          totalStorageBytes += item.totalBytes > 0 ? item.totalBytes : item.downloadedBytes;
        }

        if (items.isEmpty) {
          return _buildEmptyState();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Storage Bar Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF242424)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sd_storage_rounded, color: Colors.cyanAccent, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguageService.tr(en: "Stream TV Offline Storage", id: "Penyimpanan Offline Stream TV"),
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          AppLanguageService.tr(
                            en: "${completedDownloads.length} downloaded titles • ${DownloadService.formatBytes(totalStorageBytes)} used",
                            id: "${completedDownloads.length} judul tersimpan • ${DownloadService.formatBytes(totalStorageBytes)} terpakai",
                          ),
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (activeDownloads.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SpinKitRing(color: Colors.redAccent, size: 12),
                          const SizedBox(width: 6),
                          Text(
                            AppLanguageService.tr(
                              en: "${activeDownloads.length} downloading",
                              id: "${activeDownloads.length} mengunduh",
                            ),
                            style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Download List
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                children: [
                  // Active downloads section
                  if (activeDownloads.isNotEmpty) ...[
                    _buildSectionHeader(
                      AppLanguageService.tr(en: "Downloading Now", id: "Sedang Mengunduh"),
                      activeDownloads.length,
                    ),
                    const SizedBox(height: 10),
                    ...activeDownloads.map((item) => _buildActiveDownloadTile(item)),
                    const SizedBox(height: 20),
                  ],

                  // Completed downloads section
                  if (completedDownloads.isNotEmpty) ...[
                    _buildSectionHeader(
                      AppLanguageService.tr(en: "Downloaded & Ready to Watch", id: "Siap Ditonton Offline"),
                      completedDownloads.length,
                    ),
                    const SizedBox(height: 10),
                    ...completedDownloads.map((item) => _buildCompletedDownloadTile(item)),
                    const SizedBox(height: 20),
                  ],

                  // Failed downloads section
                  if (failedDownloads.isNotEmpty) ...[
                    _buildSectionHeader(
                      AppLanguageService.tr(en: "Failed Downloads", id: "Unduhan Gagal"),
                      failedDownloads.length,
                    ),
                    const SizedBox(height: 10),
                    ...failedDownloads.map((item) => _buildFailedDownloadTile(item)),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF262626),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: GoogleFonts.outfit(
              color: Colors.grey.shade300,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveDownloadTile(DownloadItem item) {
    final speed = _downloadService.getDownloadSpeed(item.id);
    final isPaused = item.status == DownloadStatus.paused;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Row(
          children: [
            // Poster
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: item.coverUrl,
                width: 60,
                height: 90,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  width: 60,
                  height: 90,
                  color: const Color(0xFF262626),
                  child: const Icon(Icons.movie_rounded, color: Colors.grey, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Details & Progress
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.cyan.shade900.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.quality,
                          style: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (item.isTvShow) ...[
                        const SizedBox(width: 8),
                        Text(
                          "S${item.season}:E${item.episode}",
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Text(
                        isPaused ? "Dijeda" : DownloadService.formatSpeed(speed),
                        style: GoogleFonts.outfit(
                          color: isPaused ? Colors.amberAccent : Colors.greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: item.progress > 0 ? item.progress : null,
                      minHeight: 5,
                      backgroundColor: const Color(0xFF282828),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isPaused ? Colors.amberAccent : Colors.redAccent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Byte counter
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${DownloadService.formatBytes(item.downloadedBytes)} / ${item.totalBytes > 0 ? DownloadService.formatBytes(item.totalBytes) : '...'}",
                        style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                      ),
                      Text(
                        "${(item.progress * 100).toStringAsFixed(1)}%",
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Actions: Pause/Resume & Cancel
            Column(
              children: [
                TvFocusableCard(
                  onTap: () {
                    if (isPaused) {
                      _downloadService.resumeDownload(item.id);
                    } else {
                      _downloadService.pauseDownload(item.id);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TvFocusableCard(
                  onTap: () => _downloadService.cancelDownload(item.id),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.redAccent,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompletedDownloadTile(DownloadItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: TvFocusableCard(
        onTap: () => _playOffline(item),
        borderRadius: BorderRadius.circular(14),
        scaleFactor: 1.02,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF262626)),
          ),
          child: Row(
            children: [
              // Poster
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: item.coverUrl,
                  width: 60,
                  height: 90,
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => Container(
                    width: 60,
                    height: 90,
                    color: const Color(0xFF262626),
                    child: const Icon(Icons.movie_rounded, color: Colors.grey, size: 24),
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade900.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.4), width: 0.8),
                          ),
                          child: Text(
                            item.quality,
                            style: GoogleFonts.outfit(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (item.isTvShow) ...[
                          const SizedBox(width: 8),
                          Text(
                            "S${item.season}:E${item.episode}",
                            style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const SizedBox(width: 10),
                        const Icon(Icons.sd_storage_outlined, size: 12, color: Colors.grey),
                        const SizedBox(width: 3),
                        Text(
                          DownloadService.formatBytes(item.totalBytes > 0 ? item.totalBytes : item.downloadedBytes),
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.offline_pin_rounded, color: Colors.greenAccent, size: 14),
                        const SizedBox(width: 5),
                        Text(
                          AppLanguageService.tr(en: "Ready for Offline Playback", id: "Tersimpan untuk Ditonton Offline"),
                          style: GoogleFonts.outfit(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Play & Delete Buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFE50914), Color(0xFFB81D24)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 4),
                        Text(
                          AppLanguageService.tr(en: "Play", id: "Putar"),
                          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TvFocusableCard(
                    onTap: () => _confirmDelete(item),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF222222),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFailedDownloadTile(DownloadItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: item.coverUrl,
                width: 50,
                height: 75,
                fit: BoxFit.cover,
                errorWidget: (context, url, error) => Container(
                  width: 50,
                  height: 75,
                  color: const Color(0xFF262626),
                  child: const Icon(Icons.error_outline_rounded, color: Colors.redAccent),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.errorMessage != null
                        ? (item.errorMessage!.contains('428')
                            ? "Akses CDN diperbarui. Tekan Coba Lagi."
                            : (item.errorMessage!.contains('403') || item.errorMessage!.contains('410')
                                ? "Tautan kedaluwarsa. Tekan Coba Lagi untuk memperbarui."
                                : item.errorMessage!))
                        : "Gagal mengunduh file.",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            TvFocusableCard(
              onTap: () => _downloadService.resumeDownload(item.id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.refresh_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      AppLanguageService.tr(en: "Retry", id: "Coba Lagi"),
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            TvFocusableCard(
              onTap: () => _downloadService.deleteDownload(item.id),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.grey, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF262626), width: 1.5),
              ),
              child: const Icon(
                Icons.download_for_offline_outlined,
                size: 64,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLanguageService.tr(
                en: "No Downloaded Movies Yet",
                id: "Belum Ada Film yang Diunduh",
              ),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppLanguageService.tr(
                en: "Download your favorite movies and TV episodes to watch them offline anytime without internet connection.",
                id: "Unduh film dan episode serial favorit Anda untuk ditonton secara offline kapan saja tanpa kuota atau internet.",
              ),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: Colors.grey.shade400,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

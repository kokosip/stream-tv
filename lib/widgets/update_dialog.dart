import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/update_service.dart';
import '../services/app_language_service.dart';
import '../widgets/tv_focusable_card.dart';

class UpdateDialog extends StatefulWidget {
  final AppReleaseInfo release;

  const UpdateDialog({super.key, required this.release});

  static Future<void> show(BuildContext context, AppReleaseInfo release) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => UpdateDialog(release: release),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;
  bool _isCompleted = false;

  final FocusNode _updateFocusNode = FocusNode();
  final FocusNode _cancelFocusNode = FocusNode();
  final FocusNode _browserFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _updateFocusNode.dispose();
    _cancelFocusNode.dispose();
    _browserFocusNode.dispose();
    super.dispose();
  }

  void _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _receivedBytes = 0;
      _totalBytes = widget.release.apkSizeBytes;
    });

    await UpdateService.instance.downloadAndInstall(
      release: widget.release,
      onProgress: (received, total) {
        if (mounted) {
          setState(() {
            _receivedBytes = received;
            _totalBytes = total > 0 ? total : widget.release.apkSizeBytes;
            if (_totalBytes > 0) {
              _progress = (_receivedBytes / _totalBytes).clamp(0.0, 1.0);
            }
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _errorMessage = error;
          });
        }
      },
      onCompleted: () {
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _isCompleted = true;
          });
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.currentLanguage,
      builder: (context, currentLang, _) {
        final size = MediaQuery.of(context).size;
        final isTv = size.width > 800 && size.height > 500;
        final mbReceived = (_receivedBytes / (1024 * 1024)).toStringAsFixed(1);
        final mbTotal = (_totalBytes / (1024 * 1024)).toStringAsFixed(1);

        return PopScope(
          canPop: !_isDownloading,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Container(
                width: isTv ? 520 : 400,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2C2C2C), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.8),
                      blurRadius: 32,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: Icon + Title + Version Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(
                            Icons.system_update_rounded,
                            color: Colors.redAccent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguageService.tr(
                                  en: "Update Available!",
                                  id: "Pembaruan Tersedia!",
                                ),
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade900.withValues(alpha: 0.8),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "v${widget.release.version}",
                                      style: GoogleFonts.outfit(
                                        color: Colors.greenAccent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  if (widget.release.apkSizeBytes > 0) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      "• ${(widget.release.apkSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB",
                                      style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFF262626), height: 1),
                    const SizedBox(height: 14),

                    // Content state: Changelog or Download Progress
                    if (_isDownloading) ...[
                      Text(
                        AppLanguageService.tr(
                          en: "Downloading update...",
                          id: "Mengunduh pembaruan...",
                        ),
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _totalBytes > 0 ? _progress : null,
                          minHeight: 10,
                          backgroundColor: const Color(0xFF262626),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "${(_progress * 100).toStringAsFixed(0)}%",
                            style: GoogleFonts.outfit(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            _totalBytes > 0 ? "$mbReceived MB / $mbTotal MB" : "$mbReceived MB",
                            style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLanguageService.tr(
                          en: "When completed, confirm installation on the Android system screen.",
                          id: "Setelah selesai, konfirmasi pemasangan di layar sistem Android.",
                        ),
                        style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 11),
                      ),
                    ] else if (_isCompleted) ...[
                      Center(
                        child: Column(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 42),
                            const SizedBox(height: 10),
                            Text(
                              AppLanguageService.tr(
                                en: "Installation Started",
                                id: "Pemasangan Dimulai",
                              ),
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppLanguageService.tr(
                                en: "Please tap 'Install / Update' on the Android prompt that appears.",
                                id: "Silakan klik 'Install / Update' pada prompt Android yang muncul.",
                              ),
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      // Release Notes
                      Text(
                        AppLanguageService.tr(
                          en: "Release Notes:",
                          id: "Catatan Rilis:",
                        ),
                        style: GoogleFonts.outfit(
                          color: Colors.grey.shade300,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 160),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1B1B),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF282828)),
                        ),
                        child: SingleChildScrollView(
                          child: Text(
                            widget.release.changelog.isNotEmpty
                                ? widget.release.changelog
                                : AppLanguageService.tr(
                                    en: "Performance improvements, UI updates, and stability fixes.",
                                    id: "Perbaikan performa, pembaruan antarmuka, dan peningkatan stabilitas.",
                                  ),
                            style: GoogleFonts.outfit(
                              color: Colors.grey.shade300,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Action Buttons
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          if (!_isDownloading && !_isCompleted) ...[
                            TvFocusableCard(
                              focusNode: _cancelFocusNode,
                              onTap: () => Navigator.pop(context),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF222222),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFF333333)),
                                ),
                                child: Text(
                                  AppLanguageService.tr(
                                    en: "Later",
                                    id: "Nanti",
                                  ),
                                  style: GoogleFonts.outfit(
                                    color: Colors.grey.shade300,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            if (_errorMessage != null)
                              TvFocusableCard(
                                focusNode: _browserFocusNode,
                                onTap: () => UpdateService.instance.openInBrowser(widget.release.apkDownloadUrl),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1E293B),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF3B82F6)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.open_in_browser_rounded, color: Colors.blueAccent, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        AppLanguageService.tr(
                                          en: "Download in Browser",
                                          id: "Unduh di Browser",
                                        ),
                                        style: GoogleFonts.outfit(
                                          color: Colors.blueAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            TvFocusableCard(
                              focusNode: _updateFocusNode,
                              onTap: _startDownload,
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.shade700,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.redAccent.withValues(alpha: 0.3),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _errorMessage != null ? Icons.refresh_rounded : Icons.download_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      _errorMessage != null
                                          ? AppLanguageService.tr(en: "Retry", id: "Coba Lagi")
                                          : AppLanguageService.tr(en: "Update Now", id: "Update Sekarang"),
                                      style: GoogleFonts.outfit(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ] else if (_isCompleted) ...[
                            TvFocusableCard(
                              focusNode: _updateFocusNode,
                              onTap: () => Navigator.pop(context),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF262626),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  AppLanguageService.tr(
                                    en: "Close",
                                    id: "Tutup",
                                  ),
                                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

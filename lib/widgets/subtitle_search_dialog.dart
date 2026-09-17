import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/app_language_service.dart';
import '../services/online_subtitle_service.dart';
import 'tv_focusable_card.dart';

class SubtitleDownloadResult {
  final OnlineSubtitleItem item;
  final String srtContent;

  const SubtitleDownloadResult({
    required this.item,
    required this.srtContent,
  });
}

class SubtitleSearchDialog extends StatefulWidget {
  final String initialTitle;
  final int season;
  final int episode;

  const SubtitleSearchDialog({
    super.key,
    required this.initialTitle,
    this.season = 0,
    this.episode = 0,
  });

  static Future<SubtitleDownloadResult?> show(
    BuildContext context, {
    required String initialTitle,
    int season = 0,
    int episode = 0,
  }) {
    return showDialog<SubtitleDownloadResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => SubtitleSearchDialog(
        initialTitle: initialTitle,
        season: season,
        episode: episode,
      ),
    );
  }

  @override
  State<SubtitleSearchDialog> createState() => _SubtitleSearchDialogState();
}

class _SubtitleSearchDialogState extends State<SubtitleSearchDialog> {
  final OnlineSubtitleService _subtitleService = OnlineSubtitleService();
  late final TextEditingController _searchController;
  final FocusNode _searchFocusNode = FocusNode();

  bool _isLoading = false;
  String? _downloadingId;
  String? _errorMessage;
  List<OnlineSubtitleItem> _allResults = [];
  String _selectedLangFilter = 'ind'; // 'ind', 'eng', 'all'

  @override
  void initState() {
    super.initState();
    final clean = OnlineSubtitleService.cleanSearchQuery(widget.initialTitle);
    _searchController = TextEditingController(text: clean);
    _performSearch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await _subtitleService.searchSubtitles(
        query: query,
        season: widget.season,
        episode: widget.episode,
      );

      if (mounted) {
        setState(() {
          _allResults = results;
          _isLoading = false;
          if (results.isEmpty) {
            _errorMessage = AppLanguageService.tr(
              en: "No subtitles found. Try adjusting the search title.",
              id: "Subtitle tidak ditemukan. Coba ubah kata kunci judul.",
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = AppLanguageService.tr(
            en: "Error searching subtitles. Check internet connection.",
            id: "Gagal mencari subtitle. Periksa koneksi internet.",
          );
        });
      }
    }
  }

  List<OnlineSubtitleItem> get _filteredResults {
    if (_selectedLangFilter == 'all') return _allResults;
    return _allResults.where((item) {
      if (_selectedLangFilter == 'ind') {
        return item.lang == 'ind' || item.lang == 'id' || item.languageName.toLowerCase() == 'indonesian';
      }
      if (_selectedLangFilter == 'eng') {
        return item.lang == 'eng' || item.lang == 'en' || item.languageName.toLowerCase() == 'english';
      }
      return true;
    }).toList();
  }

  Future<void> _selectAndDownload(OnlineSubtitleItem item) async {
    setState(() {
      _downloadingId = item.id;
    });

    try {
      final srt = await _subtitleService.downloadSubtitleContent(item.url);
      if (!mounted) return;

      if (srt != null && srt.isNotEmpty) {
        Navigator.pop(
          context,
          SubtitleDownloadResult(item: item, srtContent: srt),
        );
      } else {
        setState(() {
          _downloadingId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.tr(
                en: "Failed to download subtitle file.",
                id: "Gagal mengunduh file subtitle.",
              ),
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Error: $e",
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isLandscape = size.width > size.height;
    final dialogWidth = isLandscape ? (size.width * 0.60).clamp(480.0, 750.0) : (size.width * 0.92);
    final dialogHeight = isLandscape ? (size.height * 0.85).clamp(420.0, 600.0) : (size.height * 0.75);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF181818).withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              children: [
                // 1. Dialog Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.subtitles_rounded, color: Colors.redAccent, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppLanguageService.tr(
                            en: "Search Online Subtitles",
                            id: "Cari Subtitle Online",
                          ),
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (widget.season > 0 || widget.episode > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            "S${widget.season}:E${widget.episode}",
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                        splashRadius: 20,
                      ),
                    ],
                  ),
                ),

                // 2. Search Input & Filter Chips
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    children: [
                      // Search bar
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF252525),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _performSearch(),
                          decoration: InputDecoration(
                            hintText: AppLanguageService.tr(
                              en: "Enter movie or series title...",
                              id: "Masukkan judul film atau serial...",
                            ),
                            hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            suffixIcon: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_searchController.text.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() {});
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.search, color: Colors.redAccent, size: 22),
                                  onPressed: _performSearch,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Language Filter Bar
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              label: "🇮🇩 Indonesia",
                              filterValue: "ind",
                              count: _allResults.where((s) => s.lang == 'ind' || s.lang == 'id').length,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: "🇬🇧 English",
                              filterValue: "eng",
                              count: _allResults.where((s) => s.lang == 'eng' || s.lang == 'en').length,
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: AppLanguageService.tr(en: "All Languages", id: "Semua Bahasa"),
                              filterValue: "all",
                              count: _allResults.length,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(color: Colors.white10, height: 1),

                // 3. Subtitle Results List
                Expanded(
                  child: _buildBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required String filterValue,
    required int count,
  }) {
    final isSelected = _selectedLangFilter == filterValue;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedLangFilter = filterValue;
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.redAccent : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "$count",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpinKitRing(color: Colors.redAccent, size: 42.0),
            const SizedBox(height: 16),
            Text(
              AppLanguageService.tr(
                en: "Searching subtitles database...",
                id: "Mencari di database subtitle...",
              ),
              style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null && _allResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.subtitles_off_rounded, color: Colors.white30, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredResults;
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          AppLanguageService.tr(
            en: "No subtitles match the selected language filter.",
            id: "Tidak ada subtitle yang sesuai dengan filter bahasa.",
          ),
          style: GoogleFonts.outfit(color: Colors.white54, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final isDownloading = _downloadingId == item.id;
        final isId = item.lang == 'ind' || item.lang == 'id';

        return TvFocusableCard(
          borderRadius: BorderRadius.circular(12),
          onTap: isDownloading ? () {} : () => _selectAndDownload(item),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isId ? Colors.redAccent.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                // Language badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isId ? Colors.redAccent.withValues(alpha: 0.2) : Colors.blueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isId ? Colors.redAccent : Colors.blueAccent.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    item.languageName.toUpperCase(),
                    style: GoogleFonts.outfit(
                      color: isId ? Colors.redAccent : Colors.lightBlueAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // File and Release details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (item.releaseName.isNotEmpty && item.releaseName != item.fileName) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.releaseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Download icon / progress
                if (isDownloading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.redAccent,
                      strokeWidth: 2.5,
                    ),
                  )
                else
                  const Icon(
                    Icons.download_rounded,
                    color: Colors.white70,
                    size: 20,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

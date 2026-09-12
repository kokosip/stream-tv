import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/moviebox_api_service.dart';
import '../services/fourkhdhub_service.dart';
import '../services/app_language_service.dart';
import '../services/search_history_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final MovieBoxApiService _api = MovieBoxApiService();
  final FourKHdHubService _fourkApi = FourKHdHubService();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  String _selectedProvider = 'all'; // 'all', 'moviebox', '4khdhub'
  List<dynamic> _results = [];
  List<String> _searchHistory = [];
  bool _isLoading = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    final list = await SearchHistoryService.getSearchHistory();
    if (mounted) {
      setState(() {
        _searchHistory = list;
      });
    }
  }

  Future<void> _deleteSearchHistoryItem(String query) async {
    await SearchHistoryService.removeSearchQuery(query);
    await _loadSearchHistory();
  }

  Future<void> _showDeleteSearchItemDialog(String query) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
            const SizedBox(width: 10),
            Text(
              AppLanguageService.tr(en: "Delete Search?", id: "Hapus Pencarian?"),
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          AppLanguageService.tr(
            en: "Remove \"$query\" from search history?",
            id: "Hapus \"$query\" dari riwayat pencarian?",
          ),
          style: GoogleFonts.outfit(color: Colors.grey.shade300, fontSize: 13),
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
      await _deleteSearchHistoryItem(query);
    }
  }

  Future<void> _showClearAllSearchHistoryDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Text(
              AppLanguageService.tr(en: "Clear Search History?", id: "Hapus Riwayat Pencarian?"),
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
        content: Text(
          AppLanguageService.tr(
            en: "Are you sure you want to delete all search history?",
            id: "Apakah Anda yakin ingin menghapus semua riwayat pencarian?",
          ),
          style: GoogleFonts.outfit(color: Colors.grey.shade300, fontSize: 13),
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
              AppLanguageService.tr(en: "Clear All", id: "Hapus Semua"),
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await SearchHistoryService.clearAllSearchHistory();
      await _loadSearchHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.tr(en: "Search history cleared", id: "Riwayat pencarian telah dibersihkan"),
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: const Color(0xFF222222),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    SearchHistoryService.addSearchQuery(query);
    _loadSearchHistory();

    setState(() {
      _isLoading = true;
      _errorMessage = "";
      _results = [];
    });

    try {
      List<dynamic> combined = [];

      if (_selectedProvider == 'moviebox') {
        final res = await _api.search(query: query);
        final list = (res['items'] as List<dynamic>?) ?? [];
        for (final item in list) {
          if (item is Map) {
            item['provider'] = 'moviebox';
            combined.add(item);
          }
        }
      } else if (_selectedProvider == '4khdhub') {
        final res = await _fourkApi.search(query);
        combined.addAll(res);
      } else {
        // Search both in parallel
        final results = await Future.wait([
          _api.search(query: query).catchError((e) => <String, dynamic>{'items': []}),
          _fourkApi.search(query).catchError((e) => <Map<String, dynamic>>[]),
        ]);

        final mbList = (results[0] is Map ? (results[0] as Map)['items'] as List<dynamic>? : null) ?? [];
        for (final item in mbList) {
          if (item is Map) {
            item['provider'] = 'moviebox';
          }
        }

        final fourkList = results[1] is List ? results[1] as List<dynamic> : [];

        // Interleave results (4KHDHub + MovieBox) to provide a rich mix
        final maxLen = mbList.length > fourkList.length ? mbList.length : fourkList.length;
        for (int i = 0; i < maxLen; i++) {
          if (i < fourkList.length) combined.add(fourkList[i]);
          if (i < mbList.length) combined.add(mbList[i]);
        }
      }

      setState(() {
        _results = combined;
        if (_results.isEmpty) {
          _errorMessage = AppLanguageService.tr(
            en: "No results found for '$query'",
            id: "Tidak ada hasil untuk '$query'",
          );
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = AppLanguageService.tr(
          en: "Error searching. Please try again.",
          id: "Gagal mencari. Silakan coba lagi.",
        );
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildSearchHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Icon(Icons.history_rounded, color: Colors.redAccent, size: 18),
            const SizedBox(width: 8),
            Text(
              AppLanguageService.tr(en: "Recent Searches", id: "Riwayat Pencarian"),
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TvFocusableCard(
              onTap: _showClearAllSearchHistoryDialog,
              borderRadius: BorderRadius.circular(6),
              scaleFactor: 1.05,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline_rounded, color: Colors.grey.shade400, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      AppLanguageService.tr(en: "Clear All", id: "Hapus Semua"),
                      style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _searchHistory.map((query) => _buildSearchHistoryChip(query)).toList(),
        ),
      ],
    );
  }

  Widget _buildSearchHistoryChip(String query) {
    return TvFocusableCard(
      onTap: () {
        _searchController.text = query;
        _performSearch();
      },
      onLongPress: () => _showDeleteSearchItemDialog(query),
      borderRadius: BorderRadius.circular(20),
      scaleFactor: 1.05,
      child: Container(
        padding: const EdgeInsets.only(left: 12, top: 6, bottom: 6, right: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history, size: 14, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              query,
              style: GoogleFonts.outfit(color: Colors.grey.shade300, fontSize: 13),
            ),
            const SizedBox(width: 6),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _deleteSearchHistoryItem(query),
              child: Padding(
                padding: const EdgeInsets.all(2.0),
                child: Icon(Icons.close_rounded, size: 15, color: Colors.grey.shade400),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderChip(String providerKey, String label, bool isTv) {
    final isSelected = _selectedProvider == providerKey;
    final is4k = providerKey == '4khdhub';

    return TvFocusableCard(
      onTap: () {
        setState(() {
          _selectedProvider = providerKey;
        });
        if (_searchController.text.trim().isNotEmpty) {
          _performSearch();
        }
      },
      borderRadius: BorderRadius.circular(8),
      scaleFactor: 1.04,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTv ? 16 : 12,
          vertical: isTv ? 8 : 6,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? (is4k ? Colors.cyan.shade900 : Colors.redAccent.shade700)
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (is4k ? Colors.cyanAccent : Colors.redAccent)
                : const Color(0xFF333333),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (is4k) ...[
              Icon(
                Icons.hd_outlined,
                color: isSelected ? Colors.white : Colors.cyanAccent,
                size: isTv ? 16 : 14,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? Colors.white : Colors.grey.shade400,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: isTv ? 14 : 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 800; // TV has wider screen width

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          AppLanguageService.tr(en: 'Search Movies & TV Shows', id: 'Cari Film & Serial TV'),
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
        child: Column(
          children: [
            // Search Input Row
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _inputFocusNode,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                      decoration: InputDecoration(
                        hintText: AppLanguageService.tr(en: "Search here...", id: "Cari di sini..."),
                        hintStyle: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                                onPressed: () {
                                  setState(() {
                                    _searchController.clear();
                                    _results = [];
                                    _errorMessage = "";
                                  });
                                  _loadSearchHistory();
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (_) {
                        setState(() {});
                      },
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Search Button (Focusable)
                TvFocusableCard(
                  onTap: _performSearch,
                  borderRadius: BorderRadius.circular(10),
                  scaleFactor: 1.04,
                  child: Container(
                    color: Colors.redAccent.shade700,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Text(
                      AppLanguageService.tr(en: 'Search', id: 'Cari'),
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Provider Selector Chips
            Row(
              children: [
                _buildProviderChip('all', AppLanguageService.tr(en: "All Providers", id: "Semua"), isTv),
                const SizedBox(width: 10),
                _buildProviderChip('moviebox', "MovieBox", isTv),
                const SizedBox(width: 10),
                _buildProviderChip('4khdhub', "4KHDHub (4K UHD)", isTv),
              ],
            ),
            const SizedBox(height: 16),

            // Results or States
            Expanded(
              child: ClipRect(
                child: _isLoading
                    ? const Center(
                        child: SpinKitRing(
                          color: Colors.redAccent,
                          size: 50.0,
                        ),
                      )
                    : _errorMessage.isNotEmpty
                        ? Center(
                            child: Text(
                              _errorMessage,
                              style: GoogleFonts.outfit(
                                color: Colors.grey,
                                fontSize: 18,
                              ),
                            ),
                          )
                        : _results.isEmpty
                            ? Align(
                                alignment: Alignment.topLeft,
                                child: _searchHistory.isNotEmpty
                                    ? _buildSearchHistorySection()
                                    : Center(
                                        child: Text(
                                          AppLanguageService.tr(
                                            en: "Type keywords above to search movies or TV shows",
                                            id: "Ketik kata kunci di atas untuk mencari film atau serial TV",
                                          ),
                                          style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 15),
                                        ),
                                      ),
                              )
                            : GridView.builder(
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: isTv ? 6 : 3,
                              childAspectRatio: 0.7,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final item = _results[index];
                              final title = item['title'] ?? item['subjectTitle'] ?? "Untitled";
                              final coverUrl = item['cover']?['url'] ?? item['coverUrl'] ?? "";
                              final subjectId = item['subjectId'] ?? item['id']?.toString() ?? "";
                              final provider = item['provider']?.toString() ?? 'moviebox';
                              final is4k = provider == '4khdhub';

                              return TvFocusableCard(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => DetailScreen(
                                        subjectId: subjectId,
                                        provider: provider,
                                      ),
                                    ),
                                  );
                                },
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: coverUrl,
                                      memCacheWidth: 320,
                                      memCacheHeight: 480,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: const Color(0xFF1E1E1E),
                                        child: const Center(
                                          child: SpinKitRing(
                                            color: Colors.redAccent,
                                            size: 30.0,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: const Color(0xFF1E1E1E),
                                        child: const Icon(Icons.movie, size: 40, color: Colors.grey),
                                      ),
                                    ),

                                    // Provider Badge (Top-Left)
                                    Positioned(
                                      top: 8,
                                      left: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: is4k
                                              ? const Color(0xDD004D40)
                                              : Colors.redAccent.shade700.withOpacity(0.9),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(
                                            color: is4k ? Colors.cyanAccent : Colors.redAccent,
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Text(
                                          is4k ? "4KHDHub" : "MovieBox",
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Gradient Overlay & Title (Bottom)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Colors.transparent,
                                              Colors.black.withOpacity(0.9),
                                            ],
                                          ),
                                        ),
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/moviebox_api_service.dart';
import '../services/fourkhdhub_service.dart';
import '../services/tmdb_service.dart';
import '../services/app_language_service.dart';
import '../services/app_content_filter_service.dart';
import '../services/search_history_service.dart';
import '../services/analytics_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'detail_screen.dart';
import 'cast_screen.dart';

class SearchScreen extends StatefulWidget {
  final String? initialQuery;

  const SearchScreen({super.key, this.initialQuery});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final MovieBoxApiService _api = MovieBoxApiService();
  final FourKHdHubService _fourkApi = FourKHdHubService();
  final TmdbService _tmdbApi = TmdbService();

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  String _selectedProvider = 'all'; // 'all', 'moviebox', '4khdhub'
  List<dynamic> _results = [];
  List<Map<String, dynamic>> _matchedPeople = [];
  Map<String, dynamic>? _activeMatchedPerson;
  int _matchedPersonCreditsCount = 0;
  List<String> _searchHistory = [];
  bool _isLoading = false;
  String _errorMessage = "";

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _searchController.text = widget.initialQuery!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _performSearch();
      });
    }
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
            Expanded(
              child: Text(
                AppLanguageService.tr(en: "Delete Search?", id: "Hapus Pencarian?"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
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
            Expanded(
              child: Text(
                AppLanguageService.tr(en: "Clear Search History?", id: "Hapus Riwayat Pencarian?"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
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

    AnalyticsService.logSearch(query);

    SearchHistoryService.addSearchQuery(query);
    _loadSearchHistory();

    setState(() {
      _isLoading = true;
      _errorMessage = "";
      _results = [];
      _matchedPeople = [];
      _activeMatchedPerson = null;
      _matchedPersonCreditsCount = 0;
    });

    try {
      final cleanQuery = query.toLowerCase();
      final peopleFuture = _tmdbApi.searchPeople(query).catchError((_) => <Map<String, dynamic>>[]);

      List<dynamic> combined = [];

      if (_selectedProvider == 'moviebox') {
        final results = await Future.wait([
          _api.search(query: query).catchError((_) => <String, dynamic>{'items': []}),
          peopleFuture,
        ]);
        final res = results[0] as Map<String, dynamic>;
        final list = (res['items'] as List<dynamic>?) ?? (res['list'] as List<dynamic>?) ?? [];
        for (final item in list) {
          if (item is Map) {
            item['provider'] = 'moviebox';
            combined.add(item);
          }
        }
      } else if (_selectedProvider == '4khdhub') {
        final results = await Future.wait([
          _fourkApi.search(query).catchError((_) => <Map<String, dynamic>>[]),
          peopleFuture,
        ]);
        combined.addAll(results[0] as List<dynamic>);
      } else if (_selectedProvider == 'tmdb') {
        final results = await Future.wait([
          _tmdbApi.search(query).catchError((_) => <Map<String, dynamic>>[]),
          peopleFuture,
        ]);
        combined.addAll(results[0] as List<dynamic>);
      } else {
        // Search all in parallel: TMDB, 4KHDHub, MovieBox, and People
        final results = await Future.wait([
          _tmdbApi.search(query).catchError((e) => <Map<String, dynamic>>[]),
          _fourkApi.search(query).catchError((e) => <Map<String, dynamic>>[]),
          _api.search(query: query).catchError((e) => <String, dynamic>{'items': [], 'list': []}),
          peopleFuture,
        ]);

        final tmdbList = results[0] as List<dynamic>;
        final fourkList = results[1] as List<dynamic>;
        final mbRes = results[2] is Map ? (results[2] as Map) : null;
        final mbList = ((mbRes?['items'] ?? mbRes?['list']) as List<dynamic>?) ?? [];
        for (final item in mbList) {
          if (item is Map) {
            item['provider'] = 'moviebox';
          }
        }

        // Interleave results (TMDB + 4KHDHub + MovieBox) to provide the richest, most reliable mix
        final maxLen = [tmdbList.length, fourkList.length, mbList.length].reduce((a, b) => a > b ? a : b);
        for (int i = 0; i < maxLen; i++) {
          if (i < tmdbList.length) combined.add(tmdbList[i]);
          if (i < fourkList.length) combined.add(fourkList[i]);
          if (i < mbList.length) combined.add(mbList[i]);
        }
      }

      final people = await peopleFuture;
      final validPeople = people.where((p) {
        final pop = (p['popularity'] is num) ? (p['popularity'] as num).toDouble() : 0.0;
        final nameLower = (p['name'] ?? '').toString().toLowerCase();
        return pop >= 1.0 || nameLower.contains(cleanQuery) || (p['knownFor'] as List).isNotEmpty;
      }).toList();

      List<Map<String, dynamic>> personCredits = [];
      Map<String, dynamic>? topPerson;
      if (validPeople.isNotEmpty) {
        topPerson = validPeople.first;
        try {
          personCredits = await _tmdbApi.getPersonCredits(topPerson['id']);
        } catch (_) {}
      }

      final seenIds = <String>{};
      final List<dynamic> finalResults = [];

      void addUnique(dynamic item) {
        if (item is! Map) return;
        final id = (item['id'] ?? item['subjectId'] ?? item['pathId'] ?? '').toString();
        final title = (item['title'] ?? item['subjectTitle'] ?? item['name'] ?? '').toString().toLowerCase();
        final key = "${item['provider'] ?? 'tmdb'}_$id";
        final titleKey = "${title}_${item['releaseDate'] ?? ''}";
        if (!seenIds.contains(key) && !seenIds.contains(titleKey)) {
          seenIds.add(key);
          seenIds.add(titleKey);
          finalResults.add(item);
        }
      }

      final isActorQuery = topPerson != null &&
          (topPerson['name'].toString().toLowerCase().contains(cleanQuery) ||
              cleanQuery.contains(topPerson['name'].toString().toLowerCase()));

      if (isActorQuery) {
        // Put actor filmography credits prominently first
        for (final c in personCredits) {
          addUnique(c);
        }
        for (final item in combined) {
          addUnique(item);
        }
      } else {
        for (final item in combined) {
          addUnique(item);
        }
        for (final c in personCredits) {
          addUnique(c);
        }
      }

      List<dynamic> processed = finalResults;
      if (AppContentFilterService.filterHindi.value) {
        processed = AppContentFilterService.filterList(processed);
      }

      setState(() {
        _matchedPeople = validPeople;
        _activeMatchedPerson = topPerson;
        _matchedPersonCreditsCount = personCredits.length;
        _results = processed;
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

  Widget _buildActorBanner(bool isTv) {
    if (_activeMatchedPerson == null) return const SizedBox.shrink();

    final person = _activeMatchedPerson!;
    final name = (person['name'] ?? '').toString();
    final profileUrl = (person['profileUrl'] ?? '').toString();
    final department = (person['department'] ?? 'Acting').toString();
    final deptLabel = department == 'Directing'
        ? AppLanguageService.tr(en: "Director", id: "Sutradara")
        : AppLanguageService.tr(en: "Cast / Actor", id: "Pemeran / Aktor");

    final otherPeople = _matchedPeople
        .where((p) => p['id'] != person['id'])
        .take(5)
        .toList();

    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = isTv || screenWidth > 800;

    final viewButton = TvFocusableCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CastScreen(
              personId: person['id'],
              personName: name,
              profileUrl: profileUrl,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      scaleFactor: 1.05,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isWide ? 16 : 12,
          vertical: isWide ? 10 : 8,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFE50914), Color(0xFFB81D24)],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.redAccent.withValues(alpha: 0.3),
              blurRadius: 8,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.movie_filter_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              AppLanguageService.tr(
                en: "View Filmography",
                id: "Lihat Semua Filmografi",
              ),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: isWide ? 13 : 11,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 11),
          ],
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF241515), Color(0xFF141414)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.redAccent.withValues(alpha: 0.08),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(horizontal: isWide ? 20 : 14, vertical: isWide ? 16 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(36),
                child: Container(
                  width: isWide ? 64 : 52,
                  height: isWide ? 64 : 52,
                  color: const Color(0xFF2A2A2A),
                  child: profileUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: profileUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const Center(
                            child: Icon(Icons.person, color: Colors.white30, size: 28),
                          ),
                          errorWidget: (_, _, _) => const Center(
                            child: Icon(Icons.person, color: Colors.white30, size: 28),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.person, color: Colors.white30, size: 28),
                        ),
                ),
              ),
              const SizedBox(width: 16),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.6), width: 0.8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.stars_rounded, color: Colors.amberAccent, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                deptLabel,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_matchedPersonCreditsCount > 0)
                          Text(
                            "•  $_matchedPersonCreditsCount ${AppLanguageService.tr(en: "Titles in Filmography", id: "Judul Filmografi")}",
                            style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: isWide ? 20 : 17,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              if (isWide) ...[
                const SizedBox(width: 14),
                viewButton,
              ],
            ],
          ),

          if (!isWide) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: viewButton,
            ),
          ],

          // If there are other matched people
          if (otherPeople.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    AppLanguageService.tr(en: "Other people:", id: "Pemeran lain:"),
                    style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  for (final p in otherPeople) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: TvFocusableCard(
                        onTap: () async {
                          setState(() {
                            _activeMatchedPerson = p;
                            _isLoading = true;
                          });
                          try {
                            final credits = await _tmdbApi.getPersonCredits(p['id']);
                            if (mounted) {
                              setState(() {
                                _matchedPersonCreditsCount = credits.length;
                                _results = credits;
                                _isLoading = false;
                              });
                            }
                          } catch (_) {
                            if (mounted) setState(() => _isLoading = false);
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF262626),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person, color: Colors.white60, size: 12),
                              const SizedBox(width: 4),
                              Builder(builder: (context) {
                                final pName = (p['name'] ?? '').toString();
                                final pDept = (p['department'] ?? '').toString();
                                final isSameName = pName.trim().toLowerCase() == name.trim().toLowerCase();
                                final String label;
                                if (isSameName && pDept.isNotEmpty) {
                                  final deptText = pDept == 'Directing'
                                      ? AppLanguageService.tr(en: "Director", id: "Sutradara")
                                      : pDept == 'Writing'
                                          ? AppLanguageService.tr(en: "Writer", id: "Penulis")
                                          : AppLanguageService.tr(en: "Cast", id: "Pemeran");
                                  label = "$pName ($deptText)";
                                } else {
                                  label = pName;
                                }
                                return Text(
                                  label,
                                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
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
            Expanded(
              child: Text(
                AppLanguageService.tr(en: "Recent Searches", id: "Riwayat Pencarian"),
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
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
    final isTmdb = providerKey == 'tmdb';

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
              ? (is4k
                  ? Colors.cyan.shade900
                  : (isTmdb ? Colors.amber.shade900 : Colors.redAccent.shade700))
              : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? (is4k
                    ? Colors.cyanAccent
                    : (isTmdb ? Colors.amberAccent : Colors.redAccent))
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
            ] else if (isTmdb) ...[
              Icon(
                Icons.movie_filter_outlined,
                color: isSelected ? Colors.white : Colors.amberAccent,
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
                                    _matchedPeople = [];
                                    _activeMatchedPerson = null;
                                    _matchedPersonCreditsCount = 0;
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
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildProviderChip('all', AppLanguageService.tr(en: "All Providers", id: "Semua"), isTv),
                  const SizedBox(width: 10),
                  _buildProviderChip('tmdb', "TMDB", isTv),
                  const SizedBox(width: 10),
                  _buildProviderChip('4khdhub', "4KHDHub (4K UHD)", isTv),
                  const SizedBox(width: 10),
                  _buildProviderChip('moviebox', "MovieBox", isTv),
                ],
              ),
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
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_activeMatchedPerson != null) _buildActorBanner(isTv),
                                  Expanded(
                                    child: GridView.builder(
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: isTv ? 6 : 3,
                                        childAspectRatio: 0.65,
                                        crossAxisSpacing: 16,
                                        mainAxisSpacing: 16,
                                      ),
                                      itemCount: _results.length,
                                      itemBuilder: (context, index) {
                                        final item = _results[index];
                                        final title = item['title'] ?? item['subjectTitle'] ?? item['name'] ?? "Untitled";
                                        final coverUrl = item['cover']?['url'] ?? item['coverUrl'] ?? "";
                                        final subjectId = (item['subjectId'] ?? item['id'] ?? "").toString();
                                        final provider = (item['provider'] ??
                                            (subjectId.startsWith('tmdb_')
                                                ? 'tmdb'
                                                : (subjectId.startsWith('/') ? '4khdhub' : 'moviebox'))).toString();
                                        final is4k = provider == '4khdhub';
                                        final isTmdb = provider == 'tmdb';

                                        return TvFocusableCard(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (context) => DetailScreen(
                                                  subjectId: subjectId,
                                                  provider: provider,
                                                  tmdbData: item is Map<String, dynamic>
                                                      ? item
                                                      : Map<String, dynamic>.from(item as Map),
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
                                                        : (isTmdb
                                                            ? Colors.amber.shade900.withValues(alpha: 0.9)
                                                            : Colors.redAccent.shade700.withValues(alpha: 0.9)),
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(
                                                      color: is4k
                                                          ? Colors.cyanAccent
                                                          : (isTmdb ? Colors.amberAccent : Colors.redAccent),
                                                      width: 0.8,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    is4k ? "4KHDHub" : (isTmdb ? "TMDB" : "MovieBox"),
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
                                                        Colors.black.withValues(alpha: 0.9),
                                                      ],
                                                    ),
                                                  ),
                                                  padding: const EdgeInsets.all(8.0),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        title,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: GoogleFonts.outfit(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.w600,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                      if ((item['character'] ?? '').toString().isNotEmpty) ...[
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          "as ${item['character']}",
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: GoogleFonts.outfit(
                                                            color: Colors.amberAccent.shade100,
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w500,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


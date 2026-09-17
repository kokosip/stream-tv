import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/tmdb_service.dart';
import '../services/app_language_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'detail_screen.dart';

class ProviderCatalogScreen extends StatefulWidget {
  final StreamingPlatformInfo initialPlatform;

  const ProviderCatalogScreen({
    super.key,
    required this.initialPlatform,
  });

  @override
  State<ProviderCatalogScreen> createState() => _ProviderCatalogScreenState();
}

class _ProviderCatalogScreenState extends State<ProviderCatalogScreen> {
  final TmdbService _tmdb = TmdbService();
  late StreamingPlatformInfo _selectedPlatform;
  String _selectedType = 'all'; // 'all', 'movie', 'tv'

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _currentPage = 1;
  bool _hasMore = true;
  String _errorMessage = "";

  late final ScrollController _scrollController;

  // Search state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";
  bool _isSearching = false;
  List<Map<String, dynamic>> _searchResults = [];
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _selectedPlatform = widget.initialPlatform;
    _scrollController = ScrollController()..addListener(_onScroll);
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    _loadItems(refresh: true);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_searchQuery.isNotEmpty) return; // Disable catalog pagination during active search
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 400 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadItems({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _errorMessage = "";
        _currentPage = 1;
        _hasMore = true;
      });
    }

    try {
      final results = await _tmdb.getByPlatform(
        platform: _selectedPlatform,
        type: _selectedType,
        page: _currentPage,
      );

      if (mounted) {
        setState(() {
          if (refresh) {
            _items = results;
          } else {
            _items.addAll(results);
          }
          _isLoading = false;
          _hasMore = results.isNotEmpty;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = AppLanguageService.tr(
            en: "Failed to load catalog. Please check your network.",
            id: "Gagal memuat katalog platform. Silakan periksa jaringan.",
          );
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _searchQuery.isNotEmpty) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = _currentPage + 1;
      final results = await _tmdb.getByPlatform(
        platform: _selectedPlatform,
        type: _selectedType,
        page: nextPage,
      );

      if (mounted) {
        setState(() {
          _currentPage = nextPage;
          _items.addAll(results);
          _isLoadingMore = false;
          if (results.isEmpty) {
            _hasMore = false;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
        });
      }
    }
  }

  void _onSearchChanged(String val) {
    _debounceTimer?.cancel();
    final trimmed = val.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _searchQuery = "";
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    // Instant local match on loaded items for instant responsiveness
    final localMatches = _items.where((it) {
      final title = (it['title'] ?? it['name'] ?? '').toString().toLowerCase();
      return title.contains(trimmed.toLowerCase());
    }).toList();

    setState(() {
      _searchQuery = trimmed;
      _searchResults = localMatches;
      _isSearching = true;
    });

    // Debounced TMDB deep catalog search for platform
    _debounceTimer = Timer(const Duration(milliseconds: 550), () {
      _performDeepSearch(trimmed);
    });
  }

  Future<void> _performDeepSearch(String query) async {
    if (!mounted || query.isEmpty) return;

    setState(() {
      _isSearching = true;
    });

    try {
      final remoteResults = await _tmdb.searchByPlatform(
        platform: _selectedPlatform,
        query: query,
        type: _selectedType,
      );

      if (mounted && _searchQuery == query) {
        // Deduplicate between local results and remote TMDB results by subjectId / id
        final seenIds = <String>{};
        final combined = <Map<String, dynamic>>[];

        for (final item in remoteResults) {
          final id = (item['subjectId'] ?? item['id'] ?? '').toString();
          if (id.isNotEmpty && !seenIds.contains(id)) {
            seenIds.add(id);
            combined.add(item);
          }
        }

        for (final item in _searchResults) {
          final id = (item['subjectId'] ?? item['id'] ?? '').toString();
          if (id.isNotEmpty && !seenIds.contains(id)) {
            seenIds.add(id);
            combined.add(item);
          }
        }

        setState(() {
          _searchResults = combined;
          _isSearching = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    _debounceTimer?.cancel();
    setState(() {
      _searchQuery = "";
      _isSearching = false;
      _searchResults = [];
    });
  }

  void _selectPlatform(StreamingPlatformInfo platform) {
    if (_selectedPlatform.id == platform.id) return;
    setState(() {
      _selectedPlatform = platform;
    });

    if (_searchQuery.isNotEmpty) {
      _performDeepSearch(_searchQuery);
    } else {
      _loadItems(refresh: true);
    }
  }

  void _selectType(String type) {
    if (_selectedType == type) return;
    setState(() {
      _selectedType = type;
    });

    if (_searchQuery.isNotEmpty) {
      _performDeepSearch(_searchQuery);
    } else {
      _loadItems(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 800 && size.height > 500;
    final crossAxisCount = isTv ? 6 : (size.width > 600 ? 4 : (size.width > 400 ? 3 : 2));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header with back button & title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Row(
                children: [
                  TvFocusableCard(
                    autoFocus: false,
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1C1C1C),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2C2C2C)),
                      ),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _selectedPlatform.name,
                              style: GoogleFonts.outfit(
                                color: _selectedPlatform.primaryColor,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _selectedPlatform.primaryColor.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: _selectedPlatform.primaryColor.withValues(alpha: 0.6),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                _selectedPlatform.badgeText,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          AppLanguageService.tr(
                            en: "Originals, Movies & Popular Series",
                            id: "Koleksi Film & Serial Eksklusif",
                          ),
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Platform Selector Bar
            Container(
              height: 48,
              margin: const EdgeInsets.only(bottom: 6),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: TmdbService.supportedPlatforms.length,
                itemBuilder: (context, index) {
                  final platform = TmdbService.supportedPlatforms[index];
                  final isSelected = platform.id == _selectedPlatform.id;

                  return Padding(
                    padding: const EdgeInsets.only(right: 10.0),
                    child: TvFocusableCard(
                      onTap: () => _selectPlatform(platform),
                      borderRadius: BorderRadius.circular(20),
                      scaleFactor: 1.05,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? platform.primaryColor.withValues(alpha: 0.25)
                              : const Color(0xFF161616),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? platform.primaryColor : const Color(0xFF282828),
                            width: isSelected ? 1.6 : 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(platform.iconEmoji, style: const TextStyle(fontSize: 15)),
                            const SizedBox(width: 6),
                            Text(
                              platform.name,
                              style: GoogleFonts.outfit(
                                color: isSelected ? Colors.white : Colors.grey.shade400,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // 3. Platform Search Bar
            _buildSearchBar(isTv),

            // 4. Filter Type Selector (All / Movies / TV)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
              child: Row(
                children: [
                  _buildTypeChip('all', AppLanguageService.tr(en: "All", id: "Semua")),
                  const SizedBox(width: 8),
                  _buildTypeChip('movie', AppLanguageService.tr(en: "Movies", id: "Film")),
                  const SizedBox(width: 8),
                  _buildTypeChip('tv', AppLanguageService.tr(en: "TV Series", id: "Serial TV")),
                ],
              ),
            ),

            const SizedBox(height: 4),

            // 5. Catalog or Search Grid
            Expanded(
              child: _buildGridContent(crossAxisCount, isTv),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(bool isTv) {
    final themeColor = _selectedPlatform.primaryColor;
    final hasFocus = _searchFocusNode.hasFocus;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFocus
                ? themeColor
                : (_searchQuery.isNotEmpty ? themeColor.withValues(alpha: 0.6) : const Color(0xFF262626)),
            width: hasFocus ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(
              Icons.search_rounded,
              color: _searchQuery.isNotEmpty || hasFocus ? themeColor : Colors.grey.shade500,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                onSubmitted: (val) {
                  _debounceTimer?.cancel();
                  if (val.trim().isNotEmpty) {
                    _performDeepSearch(val.trim());
                  }
                },
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                ),
                cursorColor: themeColor,
                decoration: InputDecoration(
                  hintText: AppLanguageService.tr(
                    en: "Search on ${_selectedPlatform.name}...",
                    id: "Cari di ${_selectedPlatform.name}...",
                  ),
                  hintStyle: GoogleFonts.outfit(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (_isSearching)
              Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                  ),
                ),
              )
            else if (_searchQuery.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                splashRadius: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: _clearSearch,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, String label) {
    final isSelected = _selectedType == type;

    return TvFocusableCard(
      onTap: () => _selectType(type),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white.withValues(alpha: 0.15) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? Colors.white : const Color(0xFF262626),
            width: isSelected ? 1.2 : 0.8,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : Colors.grey.shade400,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildGridContent(int crossAxisCount, bool isTv) {
    // 1. If currently in search mode
    if (_searchQuery.isNotEmpty) {
      if (_isSearching && _searchResults.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpinKitRing(color: _selectedPlatform.primaryColor, size: 40.0),
              const SizedBox(height: 14),
              Text(
                AppLanguageService.tr(
                  en: "Searching on ${_selectedPlatform.name}...",
                  id: "Mencari di ${_selectedPlatform.name}...",
                ),
                style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 13),
              ),
            ],
          ),
        );
      }

      if (_searchResults.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_off_rounded, color: Colors.grey.shade600, size: 52),
                const SizedBox(height: 14),
                Text(
                  AppLanguageService.tr(
                    en: "No results for '$_searchQuery' on ${_selectedPlatform.name}",
                    id: "Tidak ada hasil untuk '$_searchQuery' di ${_selectedPlatform.name}",
                  ),
                  style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  AppLanguageService.tr(
                    en: "Try checking the spelling or switch to another platform.",
                    id: "Coba periksa ejaan atau ganti ke platform lain.",
                  ),
                  style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedPlatform.primaryColor.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    side: BorderSide(color: _selectedPlatform.primaryColor),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.clear_rounded, size: 16),
                  label: Text(
                    AppLanguageService.tr(en: "Clear Search", id: "Hapus Pencarian"),
                    style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Text(
                  AppLanguageService.tr(
                    en: "Found ${_searchResults.length} titles on ${_selectedPlatform.name}",
                    id: "Ditemukan ${_searchResults.length} judul di ${_selectedPlatform.name}",
                  ),
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_isSearching) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation<Color>(_selectedPlatform.primaryColor),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.62,
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) => _buildItemCard(_searchResults[index]),
            ),
          ),
        ],
      );
    }

    // 2. Standard Catalog View
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SpinKitRing(color: _selectedPlatform.primaryColor, size: 44.0),
            const SizedBox(height: 14),
            Text(
              AppLanguageService.tr(
                en: "Loading ${_selectedPlatform.name} catalog...",
                id: "Memuat katalog ${_selectedPlatform.name}...",
              ),
              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.grey.shade600, size: 48),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedPlatform.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _loadItems(refresh: true),
              child: Text(
                AppLanguageService.tr(en: "Retry", id: "Coba Lagi"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: Text(
          AppLanguageService.tr(
            en: "No titles found for this filter.",
            id: "Tidak ada judul untuk kategori ini.",
          ),
          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 14),
        ),
      );
    }

    return RefreshIndicator(
      color: _selectedPlatform.primaryColor,
      backgroundColor: const Color(0xFF141414),
      onRefresh: () => _loadItems(refresh: true),
      child: GridView.builder(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: 0.62,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
        ),
        itemCount: _items.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _items.length) {
            return Center(
              child: SpinKitRing(color: _selectedPlatform.primaryColor, size: 28),
            );
          }
          return _buildItemCard(_items[index]);
        },
      ),
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final title = item['title'] ?? item['name'] ?? "Untitled";
    final coverUrl = item['cover']?['url'] ?? item['backdrop']?['url'] ?? "";
    final rating = item['imdbRate'] ?? "";
    final releaseDate = item['releaseDate'] ?? "";
    final year = releaseDate.toString().isNotEmpty ? releaseDate.toString().split('-')[0] : "";
    final isShow = item['subjectType'] == 2;

    return TvFocusableCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DetailScreen(
              subjectId: item['subjectId'] ?? "",
              provider: 'tmdb',
              tmdbData: item['rawTmdb'] ?? item,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      scaleFactor: 1.05,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF222222)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Poster Image
            CachedNetworkImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
              memCacheWidth: 400,
              errorWidget: (context, url, error) => Container(
                color: const Color(0xFF1C1C1C),
                child: const Center(
                  child: Icon(Icons.movie_outlined, color: Colors.grey, size: 32),
                ),
              ),
            ),

            // Bottom Gradient & Title Overlay
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: themeGradientOverlay(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (year.isNotEmpty)
                          Text(
                            year,
                            style: GoogleFonts.outfit(
                              color: Colors.grey.shade400,
                              fontSize: 10,
                            ),
                          ),
                        if (rating.toString().isNotEmpty)
                          Row(
                            children: [
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                rating.toString(),
                                style: GoogleFonts.outfit(
                                  color: Colors.amber,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Top Type badge (TV vs Movie)
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24, width: 0.5),
                ),
                child: Text(
                  isShow ? "TV" : "MOVIE",
                  style: GoogleFonts.outfit(
                    color: isShow ? Colors.amberAccent : Colors.cyanAccent,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  LinearGradient themeGradientOverlay() {
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Colors.transparent,
        Colors.black.withValues(alpha: 0.8),
        Colors.black.withValues(alpha: 0.95),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/tmdb_service.dart';
import '../services/app_language_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'detail_screen.dart';

class CastScreen extends StatefulWidget {
  final int personId;
  final String personName;
  final String? profileUrl;

  const CastScreen({
    super.key,
    required this.personId,
    required this.personName,
    this.profileUrl,
  });

  @override
  State<CastScreen> createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen> {
  final TmdbService _tmdbApi = TmdbService();

  bool _isLoading = true;
  String _errorMessage = "";

  Map<String, dynamic>? _personDetails;
  List<Map<String, dynamic>> _allCredits = [];

  String _selectedType = 'all'; // 'all', 'movie', 'tv'
  String _sortBy = 'popular'; // 'popular', 'newest', 'rating'
  bool _isBioExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = "";
    });

    try {
      final results = await Future.wait([
        _tmdbApi.getPersonDetails(widget.personId),
        _tmdbApi.getPersonCredits(widget.personId),
      ]);

      if (mounted) {
        setState(() {
          _personDetails = results[0] as Map<String, dynamic>?;
          _allCredits = (results[1] as List<Map<String, dynamic>>?) ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = "Gagal memuat profil pemeran: $e";
          _isLoading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredAndSortedCredits {
    List<Map<String, dynamic>> list = _allCredits;

    // Filter by type
    if (_selectedType == 'movie') {
      list = list.where((c) => c['subjectType'] != 2).toList();
    } else if (_selectedType == 'tv') {
      list = list.where((c) => c['subjectType'] == 2).toList();
    }

    // Sort
    final sorted = List<Map<String, dynamic>>.from(list);
    if (_sortBy == 'newest') {
      sorted.sort((a, b) {
        final dateA = (a['releaseDate'] ?? '').toString();
        final dateB = (b['releaseDate'] ?? '').toString();
        return dateB.compareTo(dateA);
      });
    } else if (_sortBy == 'rating') {
      sorted.sort((a, b) {
        final rA = double.tryParse((a['imdbRate'] ?? '').toString()) ?? 0.0;
        final rB = double.tryParse((b['imdbRate'] ?? '').toString()) ?? 0.0;
        return rB.compareTo(rA);
      });
    } else {
      // Default: popularity
      sorted.sort((a, b) {
        final popA = (a['popularity'] is num) ? (a['popularity'] as num).toDouble() : 0.0;
        final popB = (b['popularity'] is num) ? (b['popularity'] as num).toDouble() : 0.0;
        return popB.compareTo(popA);
      });
    }

    return sorted;
  }

  int get _moviesCount => _allCredits.where((c) => c['subjectType'] != 2).length;
  int get _tvCount => _allCredits.where((c) => c['subjectType'] == 2).length;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0C0C),
      body: _isLoading
          ? const Center(
              child: SpinKitRing(color: Colors.redAccent, size: 50.0),
            )
          : _errorMessage.isNotEmpty
              ? _buildErrorView()
              : _buildMainContent(isTv),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 60),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 20),
            TvFocusableCard(
              onTap: _loadData,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  AppLanguageService.tr(en: "Try Again", id: "Coba Lagi"),
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(bool isTv) {
    final filteredList = _filteredAndSortedCredits;
    final screenWidth = MediaQuery.of(context).size.width;

    int crossAxisCount = 3;
    if (isTv) {
      crossAxisCount = screenWidth > 1200 ? 6 : 5;
    } else if (screenWidth > 600) {
      crossAxisCount = 4;
    }

    final profileImage = _personDetails?['profile_path'] != null
        ? "${TmdbService.imageBaseW500}${_personDetails!['profile_path']}"
        : (widget.profileUrl ?? "");

    final bio = (_personDetails?['biography'] ?? '').toString().trim();

    return CustomScrollView(
      slivers: [
        // Custom App Bar / Header
        SliverToBoxAdapter(
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isTv ? 32 : 16, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button row
                  Row(
                    children: [
                      TvFocusableCard(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.arrow_back, color: Colors.white, size: 22),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        AppLanguageService.tr(en: "Cast Filmography", id: "Filmografi Pemeran"),
                        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Actor Profile Card
                  Container(
                    padding: EdgeInsets.all(isTv ? 24 : 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1B1B1B), Color(0xFF121212)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile Avatar
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: isTv ? 120 : 90,
                            height: isTv ? 160 : 120,
                            color: const Color(0xFF262626),
                            child: profileImage.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: profileImage,
                                    fit: BoxFit.cover,
                                    placeholder: (_, _) => const Center(
                                      child: Icon(Icons.person, color: Colors.white24, size: 40),
                                    ),
                                    errorWidget: (_, _, _) => const Center(
                                      child: Icon(Icons.person, color: Colors.white24, size: 40),
                                    ),
                                  )
                                : const Center(
                                    child: Icon(Icons.person, color: Colors.white24, size: 40),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 20),

                        // Actor Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.personName,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: isTv ? 28 : 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (_personDetails?['known_for_department'] != null)
                                    _buildBadge(
                                      _personDetails!['known_for_department'],
                                      Colors.amberAccent,
                                    ),
                                  _buildBadge(
                                    "${_allCredits.length} ${AppLanguageService.tr(en: "Credits", id: "Karya")}",
                                    Colors.cyanAccent,
                                  ),
                                  if (_personDetails?['place_of_birth'] != null)
                                    _buildBadge(
                                      _personDetails!['place_of_birth'],
                                      Colors.white70,
                                    ),
                                ],
                              ),
                              if (bio.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isBioExpanded = !_isBioExpanded;
                                    });
                                  },
                                  child: Text(
                                    bio,
                                    maxLines: _isBioExpanded ? 10 : (isTv ? 3 : 2),
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                      color: Colors.grey.shade400,
                                      fontSize: isTv ? 13 : 12,
                                      height: 1.4,
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

                  const SizedBox(height: 24),

                  // Filter Tabs & Sort Controls
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // Type Tabs
                        _buildFilterTab('all', "${AppLanguageService.tr(en: "All", id: "Semua")} (${_allCredits.length})"),
                        const SizedBox(width: 8),
                        _buildFilterTab('movie', "${AppLanguageService.tr(en: "Movies", id: "Film")} ($_moviesCount)"),
                        const SizedBox(width: 8),
                        _buildFilterTab('tv', "${AppLanguageService.tr(en: "TV Series", id: "Serial TV")} ($_tvCount)"),
                        const SizedBox(width: 24),
                        Container(width: 1, height: 24, color: Colors.white24),
                        const SizedBox(width: 16),

                        // Sort Tabs
                        _buildSortChip('popular', AppLanguageService.tr(en: "Popular", id: "Terpopuler"), Icons.local_fire_department_rounded),
                        const SizedBox(width: 8),
                        _buildSortChip('newest', AppLanguageService.tr(en: "Latest", id: "Terbaru"), Icons.calendar_today_rounded),
                        const SizedBox(width: 8),
                        _buildSortChip('rating', AppLanguageService.tr(en: "Top Rated", id: "Rating Tertinggi"), Icons.star_rounded),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Filmography Grid
        if (filteredList.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 60.0),
              child: Center(
                child: Text(
                  AppLanguageService.tr(
                    en: "No titles found in this category.",
                    id: "Tidak ada film atau series di kategori ini.",
                  ),
                  style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 15),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: isTv ? 32 : 16,
              vertical: 12,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: 0.60,
                crossAxisSpacing: 14,
                mainAxisSpacing: 18,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _buildCreditCard(filteredList[index], isTv);
                },
                childCount: filteredList.length,
              ),
            ),
          ),

        SliverToBoxAdapter(
          child: SizedBox(height: isTv ? 60 : 40),
        ),
      ],
    );
  }

  Widget _buildFilterTab(String type, String label) {
    final isSelected = _selectedType == type;

    return TvFocusableCard(
      onTap: () {
        setState(() {
          _selectedType = type;
        });
      },
      borderRadius: BorderRadius.circular(20),
      scaleFactor: 1.05,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent : const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.redAccent : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSortChip(String sortKey, String label, IconData icon) {
    final isSelected = _sortBy == sortKey;

    return TvFocusableCard(
      onTap: () {
        setState(() {
          _sortBy = sortKey;
        });
      },
      borderRadius: BorderRadius.circular(16),
      scaleFactor: 1.05,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2A2A2A) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.amberAccent : Colors.white10,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.amberAccent : Colors.grey),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? Colors.white : Colors.grey.shade400,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(color: color, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildCreditCard(Map<String, dynamic> item, bool isTv) {
    final title = item['title'] ?? item['name'] ?? "Untitled";
    final coverUrl = item['cover']?['url'] ?? item['backdrop']?['url'] ?? "";
    final rating = (item['imdbRate'] ?? '').toString();
    final releaseDate = (item['releaseDate'] ?? '').toString();
    final year = releaseDate.isNotEmpty ? releaseDate.split('-')[0] : "";
    final character = (item['character'] ?? '').toString();
    final isShow = item['subjectType'] == 2;

    return TvFocusableCard(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DetailScreen(
              subjectId: item['subjectId'] ?? "tmdb_${item['id']}",
              provider: 'tmdb',
              tmdbData: item,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      scaleFactor: 1.05,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161616),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster Image
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  coverUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => Container(
                            color: const Color(0xFF222222),
                            child: const Center(
                              child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
                            ),
                          ),
                          errorWidget: (_, _, _) => Container(
                            color: const Color(0xFF222222),
                            child: const Center(
                              child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 36),
                            ),
                          ),
                        )
                      : Container(
                          color: const Color(0xFF222222),
                          child: const Center(
                            child: Icon(Icons.movie_outlined, color: Colors.white24, size: 36),
                          ),
                        ),

                  // Rating Badge Top-Right
                  if (rating.isNotEmpty && rating != "0" && rating != "0.0")
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.6), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 12),
                            const SizedBox(width: 2),
                            Text(
                              rating,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Media Type Badge Top-Left
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (isShow ? Colors.deepPurpleAccent : Colors.redAccent).withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isShow ? "TV" : "Movie",
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Card Text Details
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: isTv ? 13 : 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (year.isNotEmpty) ...[
                        Text(
                          year,
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                        ),
                        const SizedBox(width: 6),
                      ],
                      if (character.isNotEmpty)
                        Expanded(
                          child: Text(
                            "as $character",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: Colors.amberAccent.shade100,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

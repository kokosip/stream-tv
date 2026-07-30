import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/moviebox_api_service.dart';
import '../services/favorites_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MovieBoxApiService _api = MovieBoxApiService();
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;

  List<dynamic> _results = [];
  List<dynamic> _rawResults = [];
  bool _nsfwFilter = true;
  bool _isLoading = false;
  String _errorMessage = "";
  bool _hasSearched = false;
  List<Map<String, dynamic>> _favorites = [];

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
              event.logicalKey == LogicalKeyboardKey.arrowRight) {
            node.nextFocus();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
    );
    // Focus search input on start (good for TV remote)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
    });
    _loadFavorites();
  }

  void _loadFavorites() async {
    final list = await FavoritesService.getFavorites();
    if (mounted) {
      setState(() {
        _favorites = list;
      });
    }
  }

  void _applyFilter() {
    if (_nsfwFilter) {
      _results = _rawResults.where((item) {
        final restrictKid = item['restrictKid'];
        final genre = (item['genre'] ?? "").toString().toLowerCase();
        final rating = (item['contentRating'] ?? "").toString().toUpperCase();

        if (restrictKid == 1 || restrictKid == '1' ||
            genre.contains('erotic') ||
            rating == 'R' || rating == 'TV-MA' || rating == 'NC-17') {
          return false;
        }
        return true;
      }).toList();
    } else {
      _results = List.from(_rawResults);
    }
  }

  void _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = "";
      _hasSearched = true;
      _results = [];
      _rawResults = [];
    });

    try {
      final res = await _api.search(query: query);
      setState(() {
        _rawResults = res['items'] ?? [];
        _applyFilter();
        if (_results.isEmpty) {
          _errorMessage = "No results found for '$query'";
        }
      });
    } catch (e) {
      print("MovieBox Search Error: $e");
      setState(() {
        _errorMessage = "Error connecting to MovieBox ($e). Please try again.";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              // Brand Logo
              Text(
                'MOVIEBOX',
                style: GoogleFonts.outfit(
                  fontSize: isTv ? 64 : 42,
                  fontWeight: FontWeight.w900,
                  color: Colors.redAccent.shade700,
                  letterSpacing: 4,
                ),
              ),
              Text(
                'TUI for Android & Android TV',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 32),

              // Search Bar Group (Full Width)
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: "Type to Search Movie or TV Show...",
                    hintStyle: GoogleFonts.outfit(color: Colors.grey.shade600, fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                            onPressed: () {
                              setState(() {
                                _searchController.clear();
                                _hasSearched = false;
                                _results = [];
                                _rawResults = [];
                                _errorMessage = "";
                              });
                              _loadFavorites();
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
                  onSubmitted: (_) => _onSearch(),
                ),
              ),
              const SizedBox(height: 12),

              // Action Buttons Row (Search and NSFW Toggle)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // NSFW switch
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'NSFW Filter',
                        style: GoogleFonts.outfit(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TvFocusableCard(
                        onTap: () {
                          setState(() {
                            _nsfwFilter = !_nsfwFilter;
                            _applyFilter();
                          });
                        },
                        borderRadius: BorderRadius.circular(18),
                        scaleFactor: 1.05,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 65,
                          height: 34,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            color: _nsfwFilter ? Colors.green.shade800 : Colors.red.shade900,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                left: _nsfwFilter ? 8 : null,
                                right: _nsfwFilter ? null : 8,
                                child: Text(
                                  _nsfwFilter ? 'ON' : 'OFF',
                                  style: GoogleFonts.outfit(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              AnimatedAlign(
                                duration: const Duration(milliseconds: 150),
                                alignment: _nsfwFilter ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 3,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Search button
                  TvFocusableCard(
                    onTap: _onSearch,
                    borderRadius: BorderRadius.circular(10),
                    scaleFactor: 1.04,
                    child: Container(
                      color: Colors.redAccent.shade700,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      child: Text(
                        'Search',
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
              const SizedBox(height: 16),

              // Dynamic Body
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
                          : !_hasSearched
                              ? _buildFavoritesSection()
                              : ListView.builder(
                                  itemCount: _results.length,
                                  itemBuilder: (context, index) {
                                  final item = _results[index];
                                  final title = item['title'] ?? item['subjectTitle'] ?? "Untitled";
                                  final coverUrl = item['cover']?['url'] ?? "";
                                  final subjectId = item['subjectId'] ?? item['id']?.toString() ?? "";
                                  final type = item['subjectType'] ?? item['subject_type'];
                                  final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';
                                  final year = item['releaseDate'] != null 
                                      ? item['releaseDate'].toString().split('-')[0] 
                                      : (item['release_date'] != null 
                                          ? item['release_date'].toString().split('-')[0] 
                                          : "-");

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                    child: TvFocusableCard(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => DetailScreen(subjectId: subjectId),
                                          ),
                                        ).then((_) {
                                          _loadFavorites();
                                        });
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      scaleFactor: 1.03,
                                      child: Container(
                                        color: const Color(0xFF121212),
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          children: [
                                            // Movie Poster thumbnail
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: CachedNetworkImage(
                                                imageUrl: coverUrl,
                                                width: 50,
                                                height: 75,
                                                fit: BoxFit.cover,
                                                errorWidget: (context, url, error) => Container(
                                                  color: const Color(0xFF1E1E1E),
                                                  width: 50,
                                                  height: 75,
                                                  child: const Icon(Icons.movie, color: Colors.grey),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            // Metadata text
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    title,
                                                    style: GoogleFonts.outfit(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 18,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: isShow ? Colors.blue.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
                                                          border: Border.all(color: isShow ? Colors.blue : Colors.redAccent, width: 1),
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          isShow ? "TV Series" : "Movie",
                                                          style: GoogleFonts.outfit(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: isShow ? Colors.blue : Colors.redAccent,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Text(
                                                        year,
                                                        style: GoogleFonts.outfit(
                                                          color: Colors.grey.shade500,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFavoritesSection() {
    if (_favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border, size: 48, color: Colors.grey.shade800),
            const SizedBox(height: 16),
            Text(
              "No favorites added yet.",
              style: GoogleFonts.outfit(
                color: Colors.grey.shade600,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Search for a movie or TV show to begin streaming.",
              style: GoogleFonts.outfit(
                color: Colors.grey.shade700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              const Icon(Icons.favorite, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                "My Favorites",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.builder(
            itemCount: _favorites.length,
            itemBuilder: (context, index) {
              final item = _favorites[index];
              final title = item['title'] ?? "Untitled";
              final coverUrl = item['coverUrl'] ?? "";
              final subjectId = item['subjectId'] ?? "";
              final type = item['subjectType'];
              final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';
              final year = item['releaseDate'] != null 
                  ? item['releaseDate'].toString().split('-')[0] 
                  : "-";

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TvFocusableCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(subjectId: subjectId),
                      ),
                    ).then((_) {
                      _loadFavorites();
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  scaleFactor: 1.03,
                  child: Container(
                    color: const Color(0xFF121212),
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: coverUrl,
                            width: 50,
                            height: 75,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF1E1E1E),
                              width: 50,
                              height: 75,
                              child: const Icon(Icons.movie, color: Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isShow ? Colors.blue.withOpacity(0.2) : Colors.redAccent.withOpacity(0.2),
                                      border: Border.all(color: isShow ? Colors.blue : Colors.redAccent, width: 1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isShow ? "TV Series" : "Movie",
                                      style: GoogleFonts.outfit(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: isShow ? Colors.blue : Colors.redAccent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    year,
                                    style: GoogleFonts.outfit(
                                      color: Colors.grey.shade500,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

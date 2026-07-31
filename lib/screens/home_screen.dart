import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/moviebox_api_service.dart';
import '../services/favorites_service.dart';
import '../services/playback_progress_service.dart';
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

  List<dynamic> _searchResults = [];
  List<dynamic> _rawSearchResults = [];
  bool _nsfwFilter = true;
  bool _isLoadingSearch = false;
  bool _isLoadingHome = true;
  String _errorMessage = "";
  bool _hasSearched = false;

  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _recentPlays = [];
  List<dynamic> _homeItems = [];
  List<dynamic> _bannerItems = [];

  // Custom filtering state variables
  String _selectedLanguage = "Semua";
  String _selectedGenre = "Semua";
  String _selectedType = "Semua";
  String _selectedRating = "Semua";
  bool _isFiltering = false;
  bool _isLoadingFilters = false;
  List<dynamic> _filteredResults = [];

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

    _loadAllHomeData();
    _checkPasscodeSetup();
  }

  Future<void> _loadAllHomeData() async {
    setState(() {
      _isLoadingHome = true;
      _errorMessage = "";
    });

    try {
      // 1. Fetch homepage (tabId 0) and Indonesian movies concurrently
      final responses = await Future.wait([
        _api.getHomepage(page: 1, tabId: 0),
        _api.search(query: "Indonesia", subjectType: 1, page: 1, perPage: 20),
      ]);

      final resHome = responses[0];
      final resSearch = responses[1];

      final List<dynamic> rawHomeItems = resHome['items'] ?? [];
      final List<dynamic> searchItems = resSearch['items'] ?? [];

      // 2. Extract banners from Home
      List<dynamic> banners = [];
      final bannerSection = rawHomeItems.firstWhere(
        (item) => item['type'] == 'BANNER',
        orElse: () => null,
      );
      if (bannerSection != null && bannerSection['banner'] != null) {
        banners = bannerSection['banner']['banners'] ?? [];
      }

      // Filter only subjects rows from Home (dynamic category rows)
      final subjectsSections = rawHomeItems.where((item) => item['type'] == 'SUBJECTS_MOVIE').toList();

      // Construct custom "Film Indonesia" category row
      if (searchItems.isNotEmpty) {
        final customIndoSection = {
          "title": "Film Indonesia",
          "subjects": searchItems,
        };
        if (subjectsSections.isNotEmpty) {
          subjectsSections.insert(1, customIndoSection);
        } else {
          subjectsSections.add(customIndoSection);
        }
      }

      setState(() {
        _homeItems = subjectsSections;
        _bannerItems = banners;
      });
    } catch (e) {
      print("MovieBox Home Catalog Error: $e");
      setState(() {
        _errorMessage = "Gagal memuat katalog. Silakan coba lagi.";
      });
    }

    // 3. Load favorites and recent progress
    await _loadFavoritesAndProgress();

    setState(() {
      _isLoadingHome = false;
    });
  }

  Future<void> _loadFavoritesAndProgress() async {
    final favList = await FavoritesService.getFavorites();
    final recList = await PlaybackProgressService.getRecentPlays();
    if (mounted) {
      setState(() {
        _favorites = favList;
        _recentPlays = recList;
      });
    }
  }

  void _applySearchFilter() {
    if (_nsfwFilter) {
      _searchResults = _rawSearchResults.where((item) {
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
      _searchResults = List.from(_rawSearchResults);
    }
  }

  void _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _selectedLanguage = "Semua";
      _selectedGenre = "Semua";
      _selectedType = "Semua";
      _selectedRating = "Semua";
      _isFiltering = false;
      _filteredResults = [];
      _isLoadingSearch = true;
      _errorMessage = "";
      _hasSearched = true;
      _searchResults = [];
      _rawSearchResults = [];
    });

    try {
      final res = await _api.search(query: query);
      setState(() {
        _rawSearchResults = res['items'] ?? [];
        _applySearchFilter();
        if (_searchResults.isEmpty) {
          _errorMessage = "Tidak ada hasil untuk '$query'";
        }
      });
    } catch (e) {
      print("MovieBox Search Error: $e");
      setState(() {
        _errorMessage = "Error menghubungkan ke MovieBox ($e). Silakan coba lagi.";
      });
    } finally {
      setState(() {
        _isLoadingSearch = false;
      });
    }
  }

  Future<void> _applyCustomFilters() async {
    if (_selectedLanguage == "Semua" &&
        _selectedGenre == "Semua" &&
        _selectedType == "Semua" &&
        _selectedRating == "Semua") {
      setState(() {
        _isFiltering = false;
        _filteredResults = [];
      });
      _loadAllHomeData();
      return;
    }

    setState(() {
      _isFiltering = true;
      _isLoadingFilters = true;
      _errorMessage = "";
      _searchController.clear();
      _hasSearched = false;
      _searchResults = [];
      _rawSearchResults = [];
    });

    try {
      List<dynamic> sourceItems = [];

      if (_selectedLanguage != "Semua") {
        final int targetType = _selectedType == "TV Series" ? 2 : (_selectedType == "Movies" ? 1 : 0);
        final results = await Future.wait([
          _api.search(query: _selectedLanguage, subjectType: targetType, page: 1, perPage: 20),
          _api.search(query: _selectedLanguage, subjectType: targetType, page: 2, perPage: 20),
        ]);
        sourceItems = [
          ...(results[0]['items'] ?? []),
          ...(results[1]['items'] ?? []),
        ];
      } else if (_selectedGenre != "Semua") {
        final int targetType = _selectedType == "TV Series" ? 2 : (_selectedType == "Movies" ? 1 : 0);
        final results = await Future.wait([
          _api.search(query: _selectedGenre, subjectType: targetType, page: 1, perPage: 20),
          _api.search(query: _selectedGenre, subjectType: targetType, page: 2, perPage: 20),
        ]);
        sourceItems = [
          ...(results[0]['items'] ?? []),
          ...(results[1]['items'] ?? []),
        ];
      } else if (_selectedRating != "Semua") {
        // Search generic term "the" to get results with rating metadata to filter
        final int targetType = _selectedType == "TV Series" ? 2 : (_selectedType == "Movies" ? 1 : 0);
        final results = await Future.wait([
          _api.search(query: "the", subjectType: targetType, page: 1, perPage: 20),
          _api.search(query: "the", subjectType: targetType, page: 2, perPage: 20),
        ]);
        sourceItems = [
          ...(results[0]['items'] ?? []),
          ...(results[1]['items'] ?? []),
        ];
      } else {
        if (_selectedType == "Movies") {
          final res = await _api.getHomepage(page: 1, tabId: 2);
          final List<dynamic> rawMovieItems = res['items'] ?? [];
          for (final section in rawMovieItems) {
            if (section['type'] == 'SUBJECTS_MOVIE') {
              final List<dynamic> subs = section['subjects'] ?? [];
              sourceItems.addAll(subs);
            }
          }
        } else if (_selectedType == "TV Series") {
          final res = await _api.getHomepage(page: 1, tabId: 5);
          final List<dynamic> rawTvItems = res['items'] ?? [];
          for (final section in rawTvItems) {
            if (section['type'] == 'SUBJECTS_MOVIE') {
              final List<dynamic> subs = section['subjects'] ?? [];
              sourceItems.addAll(subs);
            }
          }
        }
      }

      final Set<String> seenIds = {};
      final List<dynamic> uniqueItems = [];
      for (final item in sourceItems) {
        final id = (item['subjectId'] ?? item['id']?.toString() ?? "");
        if (id.isNotEmpty && !seenIds.contains(id)) {
          seenIds.add(id);
          uniqueItems.add(item);
        }
      }

      final List<dynamic> filtered = uniqueItems.where((item) {
        if (_selectedLanguage != "Semua") {
          final String title = (item['title'] ?? "").toString().toLowerCase();
          final String language = (item['language'] ?? "").toString().toLowerCase();
          final String country = (item['countryName'] ?? "").toString().toLowerCase();
          
          if (_selectedLanguage == "Indonesia") {
            if (!language.contains("indonesia") && 
                !country.contains("indonesia") && 
                !title.contains("[indonesian]")) {
              return false;
            }
          } else if (_selectedLanguage == "English") {
            if (!language.contains("english") && 
                !country.contains("united states") && 
                !country.contains("united kingdom") && 
                !country.contains("canada") && 
                !country.contains("australia")) {
              return false;
            }
          } else if (_selectedLanguage == "Korea") {
            if (!language.contains("korean") && !country.contains("korea")) {
              return false;
            }
          } else if (_selectedLanguage == "Japan") {
            if (!language.contains("japanese") && !country.contains("japan")) {
              return false;
            }
          } else if (_selectedLanguage == "China") {
            if (!language.contains("chinese") && 
                !country.contains("china") && 
                !country.contains("hong kong") && 
                !country.contains("taiwan")) {
              return false;
            }
          }
        }

        if (_selectedGenre != "Semua") {
          final String genre = (item['genre'] ?? "").toString().toLowerCase();
          final String targetGenre = _selectedGenre.toLowerCase();
          if (targetGenre == "romantic") {
            if (!genre.contains("romance") && !genre.contains("romantic")) {
              return false;
            }
          } else if (targetGenre == "anime") {
            if (!genre.contains("animation") && !genre.contains("anime")) {
              return false;
            }
          } else {
            if (!genre.contains(targetGenre)) {
              return false;
            }
          }
        }

        if (_selectedType != "Semua") {
          final type = item['subjectType'] ?? item['subject_type'] ?? 1;
          final int expectedType = _selectedType == "TV Series" ? 2 : 1;
          if (type != expectedType && type.toString() != expectedType.toString()) {
            return false;
          }
        }

        if (_selectedRating != "Semua") {
          final String rating = (item['contentRating'] ?? "").toString().toUpperCase();
          if (rating != _selectedRating.toUpperCase()) {
            return false;
          }
        }

        if (_nsfwFilter) {
          final restrictKid = item['restrictKid'];
          final genre = (item['genre'] ?? "").toString().toLowerCase();
          if (restrictKid == 1 || restrictKid == '1' || genre.contains('erotic')) {
            return false;
          }
        }

        return true;
      }).toList();

      setState(() {
        _filteredResults = filtered;
      });
    } catch (e) {
      print("MovieBox Apply Filters Error: $e");
      setState(() {
        _errorMessage = "Gagal memfilter konten. Silakan coba lagi.";
      });
    } finally {
      setState(() {
        _isLoadingFilters = false;
      });
    }
  }

  Widget _buildFilterRow(bool isTv) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildFilterDropdown(
            label: "Bahasa",
            value: _selectedLanguage,
            items: ["Semua", "English", "Indonesia", "Korea", "Japan", "China"],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedLanguage = val;
                });
                _applyCustomFilters();
              }
            },
          ),
          const SizedBox(width: 12),
          _buildFilterDropdown(
            label: "Genre",
            value: _selectedGenre,
            items: ["Semua", "Romantic", "Horror", "Anime", "Action", "Comedy", "Drama"],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedGenre = val;
                });
                _applyCustomFilters();
              }
            },
          ),
          const SizedBox(width: 12),
          _buildFilterDropdown(
            label: "Tipe",
            value: _selectedType,
            items: ["Semua", "Movies", "TV Series"],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedType = val;
                });
                _applyCustomFilters();
              }
            },
          ),
          const SizedBox(width: 12),
          _buildFilterDropdown(
            label: "Rating",
            value: _selectedRating,
            items: ["Semua", "G", "PG", "PG-13", "R", "NC-17", "TV-G", "TV-PG", "TV-14", "TV-MA"],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedRating = val;
                });
                _applyCustomFilters();
              }
            },
          ),
          if (_isFiltering) ...[
            const SizedBox(width: 12),
            TvFocusableCard(
              onTap: () {
                setState(() {
                  _selectedLanguage = "Semua";
                  _selectedGenre = "Semua";
                  _selectedType = "Semua";
                  _selectedRating = "Semua";
                  _isFiltering = false;
                  _filteredResults = [];
                });
                _loadAllHomeData();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: Colors.redAccent.shade700,
                child: Row(
                  children: [
                    const Icon(Icons.refresh, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      "Reset",
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$label: ",
            style: GoogleFonts.outfit(
              color: Colors.grey.shade500,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(
              canvasColor: const Color(0xFF161616),
            ),
            child: DropdownButton<String>(
              value: value,
              underline: const SizedBox.shrink(),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredResultsSection(bool isTv) {
    if (_isLoadingFilters) {
      return const Center(
        child: SpinKitRing(color: Colors.redAccent, size: 50.0),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Text(
          _errorMessage,
          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 14),
        ),
      );
    }

    if (_filteredResults.isEmpty) {
      return Center(
        child: Text(
          "Tidak ada hasil yang sesuai dengan filter",
          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 14),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTv ? 6 : 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _filteredResults.length,
      itemBuilder: (context, index) {
        final item = _filteredResults[index];
        final title = item['title'] ?? item['subjectTitle'] ?? "Untitled";
        final coverUrl = item['cover']?['url'] ?? "";
        final subjectId = item['subjectId'] ?? item['id']?.toString() ?? "";
        final rating = item['imdbRate'] ?? item['imdbRatingValue'] ?? "";
        final type = item['subjectType'] ?? item['subject_type'] ?? 1;
        final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';

        return TvFocusableCard(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailScreen(subjectId: subjectId),
              ),
            ).then((_) {
              _loadFavoritesAndProgress();
            });
          },
          borderRadius: BorderRadius.circular(10),
          scaleFactor: 1.04,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Center(
                    child: SpinKitRing(color: Colors.redAccent, size: 24),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Icon(Icons.movie, size: 40, color: Colors.grey),
                ),
              ),
              if (rating.toString().isNotEmpty)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "★ $rating",
                      style: GoogleFonts.outfit(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isShow ? Colors.blue.shade900.withOpacity(0.85) : Colors.red.shade900.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isShow ? "TV" : "MOVIE",
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
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
    );
  }

  Future<void> _checkPasscodeSetup() async {
    final prefs = await SharedPreferences.getInstance();
    final passcode = prefs.getString('nsfw_passcode') ?? '';
    if (passcode.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSetPasscodeDialog();
      });
    }
  }

  void _showSetPasscodeDialog() {
    final pinController1 = TextEditingController();
    final pinController2 = TextEditingController();
    final errorState = ValueNotifier<String>("");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: const Color(0xFF161616),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF2C2C2C)),
            ),
            child: Container(
              width: 340,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.security, color: Colors.redAccent.shade700, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    "Set NSFW Passcode",
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Set a 4-digit passcode to lock NSFW content settings.",
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.grey.shade400,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: pinController1,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, letterSpacing: 16),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: "••••",
                      hintStyle: TextStyle(color: Colors.grey.shade700, letterSpacing: 16),
                      counterText: "",
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C2C2C)),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Confirm Passcode",
                    style: GoogleFonts.outfit(
                      color: Colors.grey.shade400,
                      fontSize: 12,
                    ),
                  ),
                  TextField(
                    controller: pinController2,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    maxLength: 4,
                    style: const TextStyle(color: Colors.white, letterSpacing: 16),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: "••••",
                      hintStyle: TextStyle(color: Colors.grey.shade700, letterSpacing: 16),
                      counterText: "",
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C2C2C)),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: errorState,
                    builder: (context, error, child) {
                      if (error.isEmpty) return const SizedBox.shrink();
                      return Text(
                        error,
                        style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 12),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  TvFocusableCard(
                    onTap: () async {
                      final p1 = pinController1.text;
                      final p2 = pinController2.text;
                      if (p1.length < 4) {
                        errorState.value = "Passcode must be 4 digits";
                        return;
                      }
                      if (p1 != p2) {
                        errorState.value = "Passcodes do not match";
                        return;
                      }
                      
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('nsfw_passcode', p1);
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      color: Colors.redAccent.shade700,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      child: Text(
                        "Save Passcode",
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
            ),
          ),
        );
      },
    );
  }

  void _showUnlockDialog() {
    final pinController = TextEditingController();
    final errorState = ValueNotifier<String>("");

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF161616),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2C2C2C)),
          ),
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_open_rounded, color: Colors.redAccent.shade700, size: 48),
                const SizedBox(height: 16),
                Text(
                  "Enter Passcode",
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Enter the 4-digit passcode to disable the NSFW Filter.",
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, letterSpacing: 16),
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: "••••",
                    hintStyle: TextStyle(color: Colors.grey.shade700, letterSpacing: 16),
                    counterText: "",
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Color(0xFF2C2C2C)),
                    ),
                    focusedBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.redAccent),
                    ),
                  ),
                  onSubmitted: (val) => _verifyAndUnlock(val, errorState, context),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<String>(
                  valueListenable: errorState,
                  builder: (context, error, child) {
                    if (error.isEmpty) return const SizedBox.shrink();
                    return Text(
                      error,
                      style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 12),
                    );
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: TvFocusableCard(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: const Color(0xFF262626),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: Text(
                            "Cancel",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TvFocusableCard(
                        onTap: () => _verifyAndUnlock(pinController.text, errorState, context),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: Colors.redAccent.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          child: Text(
                            "Unlock",
                            style: GoogleFonts.outfit(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _verifyAndUnlock(String val, ValueNotifier<String> errorState, BuildContext dialogContext) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString('nsfw_passcode') ?? '';
    if (val == savedPin) {
      setState(() {
        _nsfwFilter = false;
        _applySearchFilter();
        if (_isFiltering) {
          _applyCustomFilters();
        }
      });
      Navigator.pop(dialogContext);
    } else {
      errorState.value = "Incorrect passcode. Please try again.";
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header (Logo & Remote action icons)
              _buildHeader(isTv),
              const SizedBox(height: 16),

              // 2. Search Input bar
              _buildSearchBar(),
              const SizedBox(height: 16),

              // 3. Filter Row
              _buildFilterRow(isTv),
              const SizedBox(height: 16),

              // 4. Dynamic content body
              Expanded(
                child: ClipRect(
                  child: _isFiltering
                      ? _buildFilteredResultsSection(isTv)
                      : (_hasSearched 
                          ? _buildSearchResultsSection(isTv)
                          : _buildHomeSections(isTv)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isTv) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // App Title Logo
        Text(
          'MOVIEBOX',
          style: GoogleFonts.outfit(
            fontSize: isTv ? 32 : 24,
            fontWeight: FontWeight.w900,
            color: Colors.redAccent.shade700,
            letterSpacing: 2,
          ),
        ),
        // NSFW & Settings Actions
        Row(
          children: [
            Text(
              'NSFW Filter',
              style: GoogleFonts.outfit(
                color: Colors.grey.shade400,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            TvFocusableCard(
              onTap: () {
                if (_nsfwFilter) {
                  _showUnlockDialog();
                } else {
                  setState(() {
                    _nsfwFilter = true;
                    _applySearchFilter();
                    if (_isFiltering) {
                      _applyCustomFilters();
                    }
                  });
                }
              },
              borderRadius: BorderRadius.circular(16),
              scaleFactor: 1.05,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 55,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: _nsfwFilter ? Colors.green.shade800 : Colors.red.shade900,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      left: _nsfwFilter ? 6 : null,
                      right: _nsfwFilter ? null : 6,
                      child: Text(
                        _nsfwFilter ? 'ON' : 'OFF',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      alignment: _nsfwFilter ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
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
          hintText: "Cari film atau serial TV di sini...",
          hintStyle: GoogleFonts.outfit(color: Colors.grey.shade600, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 20),
          suffixIcon: _searchController.text.isNotEmpty || _hasSearched
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey, size: 18),
                  onPressed: () {
                    setState(() {
                      _searchController.clear();
                      _hasSearched = false;
                      _searchResults = [];
                      _rawSearchResults = [];
                      _errorMessage = "";
                    });
                    _loadFavoritesAndProgress();
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
    );
  }

  Widget _buildSearchResultsSection(bool isTv) {
    if (_isLoadingSearch) {
      return const Center(
        child: SpinKitRing(color: Colors.redAccent, size: 50.0),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Text(
          _errorMessage,
          style: GoogleFonts.outfit(color: Colors.grey, fontSize: 18),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: isTv ? 6 : 3,
        childAspectRatio: 0.7,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final title = item['title'] ?? item['subjectTitle'] ?? "Untitled";
        final coverUrl = item['cover']?['url'] ?? "";
        final subjectId = item['subjectId'] ?? item['id']?.toString() ?? "";
        final rating = item['imdbRate'] ?? item['imdbRatingValue'] ?? "";

        return TvFocusableCard(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailScreen(subjectId: subjectId),
              ),
            ).then((_) {
              _loadFavoritesAndProgress();
            });
          },
          borderRadius: BorderRadius.circular(10),
          scaleFactor: 1.04,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: coverUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Center(
                    child: SpinKitRing(color: Colors.redAccent, size: 24),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: const Color(0xFF1E1E1E),
                  child: const Icon(Icons.movie, size: 40, color: Colors.grey),
                ),
              ),
              // Rating Badge
              if (rating.toString().isNotEmpty)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "★ $rating",
                      style: GoogleFonts.outfit(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              // Gradient & Title Overlay
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black.withOpacity(0.9)],
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
    );
  }

  Widget _buildHomeSections(bool isTv) {
    if (_isLoadingHome) {
      return const Center(
        child: SpinKitRing(color: Colors.redAccent, size: 50.0),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAllHomeData,
      color: Colors.redAccent,
      backgroundColor: const Color(0xFF161616),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Featured Spotlight Banner (at top)
            _buildSpotlightBanner(isTv),
            const SizedBox(height: 24),

            // 2. Lanjutkan Nonton Section
            if (_recentPlays.isNotEmpty) ...[
              _buildContinueWatchingSection(isTv),
              const SizedBox(height: 24),
            ],

            // 3. Favorites Section
            if (_favorites.isNotEmpty) ...[
              _buildFavoritesSection(isTv),
              const SizedBox(height: 24),
            ],

            // 4. Dynamic Category Rows
            ..._homeItems.map((section) {
              final title = section['title'] ?? "Trending";
              final List<dynamic> subjects = section['subjects'] ?? [];
              return _buildCategoryRow(title, subjects, isTv);
            }),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSpotlightBanner(bool isTv) {
    if (_bannerItems.isEmpty) return const SizedBox.shrink();
    // Use the first banner item
    final banner = _bannerItems.first;
    final String imageUrl = banner['image']?['url'] ?? "";
    final String title = banner['content'] ?? banner['subject']?['title'] ?? "Spotlight";
    final String subjectId = banner['subjectId'] ?? "";
    final rating = banner['subject']?['imdbRate'] ?? banner['subject']?['imdbRatingValue'] ?? "";
    final year = banner['subject']?['releaseDate'] ?? "";

    return Container(
      height: isTv ? 320 : 200,
      width: double.infinity,
      child: TvFocusableCard(
        onTap: () {
          if (subjectId.isNotEmpty && subjectId != "0") {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailScreen(subjectId: subjectId),
              ),
            ).then((_) {
              _loadFavoritesAndProgress();
            });
          }
        },
        borderRadius: BorderRadius.circular(16),
        scaleFactor: 1.02,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Banner Background
            CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => Container(color: const Color(0xFF1E1E1E)),
            ),
            // Gradient Overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withOpacity(0.1),
                    Colors.black.withOpacity(0.85),
                  ],
                ),
              ),
            ),
            // Info text content (Glassmorphic vibe)
            Positioned(
              left: 20,
              bottom: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.cyan.shade900.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      "SPOTLIGHT",
                      style: GoogleFonts.outfit(
                        color: Colors.cyanAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: isTv ? 28 : 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rating.toString().isNotEmpty) ...[
                        const Icon(Icons.star, color: Colors.amber, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          "$rating",
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                      ],
                      if (year.toString().isNotEmpty)
                        Text(
                          year.toString().split('-')[0],
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
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

  Widget _buildContinueWatchingSection(bool isTv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            "Lanjutkan Nonton",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _recentPlays.length,
            itemBuilder: (context, index) {
              final item = _recentPlays[index];
              final title = item['title'] ?? "Untitled";
              final coverUrl = item['coverUrl'] ?? "";
              final subjectId = item['subjectId'] ?? "";
              final season = item['season'] ?? 0;
              final episode = item['episode'] ?? 0;
              final pos = item['positionMs'] ?? 0;
              final dur = item['durationMs'] ?? 1;

              final progress = (pos / dur).clamp(0.0, 1.0);
              final isShow = season > 0 || episode > 0;
              final String subtitle = isShow 
                  ? "S$season:E$episode" 
                  : (progress == 0 ? "Tonton Ulang" : "Lanjutkan");

              return Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: TvFocusableCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(subjectId: subjectId),
                      ),
                    ).then((_) {
                      _loadFavoritesAndProgress();
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  scaleFactor: 1.04,
                  child: Container(
                    width: 220,
                    color: const Color(0xFF161616),
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        // Left Poster
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CachedNetworkImage(
                            imageUrl: coverUrl,
                            width: 50,
                            height: 84,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF262626),
                              width: 50,
                              height: 84,
                              child: const Icon(Icons.movie, size: 20, color: Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Right Column Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: GoogleFonts.outfit(
                                  color: Colors.cyan.shade400,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Progress Bar
                              if (progress > 0)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 3,
                                    backgroundColor: const Color(0xFF262626),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                                  ),
                                ),
                            ],
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
      ],
    );
  }

  Widget _buildFavoritesSection(bool isTv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: [
              const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
              const SizedBox(width: 6),
              Text(
                "Favorit Saya",
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: _favorites.length,
            itemBuilder: (context, index) {
              final item = _favorites[index];
              final title = item['title'] ?? "Untitled";
              final coverUrl = item['coverUrl'] ?? "";
              final subjectId = item['subjectId'] ?? "";
              final type = item['subjectType'];
              final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';

              return Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: TvFocusableCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(subjectId: subjectId),
                      ),
                    ).then((_) {
                      _loadFavoritesAndProgress();
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  scaleFactor: 1.04,
                  child: Container(
                    width: 120,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => Container(color: const Color(0xFF1E1E1E)),
                        ),
                        // Type Overlay Badge
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isShow ? Colors.blue.shade900.withOpacity(0.8) : Colors.red.shade900.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isShow ? "TV" : "MOVIE",
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        // Title Fade overlay
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                              ),
                            ),
                            padding: const EdgeInsets.all(6.0),
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
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
      ],
    );
  }

  Widget _buildCategoryRow(String title, List<dynamic> subjects, bool isTv) {
    if (subjects.isEmpty) return const SizedBox.shrink();

    // Normal client filtering for NSFW if toggled
    List<dynamic> filteredSubjects = subjects;
    if (_nsfwFilter) {
      filteredSubjects = subjects.where((item) {
        final restrictKid = item['restrictKid'];
        final genre = (item['genre'] ?? "").toString().toLowerCase();
        if (restrictKid == 1 || restrictKid == '1' || genre.contains('erotic')) {
          return false;
        }
        return true;
      }).toList();
    }

    if (filteredSubjects.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Text(
            title,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: filteredSubjects.length,
            itemBuilder: (context, index) {
              final subject = filteredSubjects[index];
              final sTitle = subject['title'] ?? subject['subjectTitle'] ?? "Untitled";
              final coverUrl = subject['cover']?['url'] ?? "";
              final subjectId = subject['subjectId'] ?? subject['id']?.toString() ?? "";
              final rating = subject['imdbRate'] ?? subject['imdbRatingValue'] ?? "";
              final type = subject['subjectType'] ?? subject['subject_type'] ?? 1;
              final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';

              return Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: TvFocusableCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(subjectId: subjectId),
                      ),
                    ).then((_) {
                      _loadFavoritesAndProgress();
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  scaleFactor: 1.04,
                  child: Container(
                    width: 120,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Card Poster image
                        CachedNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: const Color(0xFF1E1E1E),
                            child: const Center(
                              child: SpinKitRing(color: Colors.redAccent, size: 24),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: const Color(0xFF1E1E1E),
                            child: const Icon(Icons.movie, size: 30, color: Colors.grey),
                          ),
                        ),
                        // Rating Badge (Top Left)
                        if (rating.toString().isNotEmpty)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                "★ $rating",
                                style: GoogleFonts.outfit(color: Colors.amber, fontSize: 8, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        // Type Badge (Top Right)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: isShow ? Colors.blue.shade900.withOpacity(0.85) : Colors.red.shade900.withOpacity(0.85),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isShow ? "TV" : "MOVIE",
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 7, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        // Title bottom overlay
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Colors.transparent, Colors.black.withOpacity(0.85)],
                              ),
                            ),
                            padding: const EdgeInsets.all(6.0),
                            child: Text(
                              sTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
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
      ],
    );
  }
}


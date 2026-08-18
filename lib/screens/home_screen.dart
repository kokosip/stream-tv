import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/moviebox_api_service.dart';
import '../services/favorites_service.dart';
import '../services/playback_progress_service.dart';
import '../services/app_language_service.dart';
import '../widgets/tv_focusable_card.dart';
import '../widgets/tv_pin_pad_dialog.dart';
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
  late final FocusNode _nsfwFocusNode;
  late final FocusNode _langFocusNode;

  // Bottom Navigation Bar state and focus nodes
  int _currentTabIndex = 0;
  late final FocusNode _navHomeFocusNode;
  late final FocusNode _navSearchFocusNode;
  late final FocusNode _navFavFocusNode;
  late final FocusNode _navHistoryFocusNode;
  late final FocusNode _navSettingsFocusNode;

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
    _nsfwFocusNode = FocusNode();
    _langFocusNode = FocusNode();

    _navHomeFocusNode = FocusNode();
    _navSearchFocusNode = FocusNode();
    _navFavFocusNode = FocusNode();
    _navHistoryFocusNode = FocusNode();
    _navSettingsFocusNode = FocusNode();

    _searchFocusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _langFocusNode.requestFocus();
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
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
      // 1. Fetch homepage (tabId 0) and Indonesian movies concurrently with fallbacks
      final responses = await Future.wait([
        _api.getHomepage(page: 1, tabId: 0).catchError((e) {
          print("Homepage fetch error: $e");
          return <String, dynamic>{};
        }),
        _api.search(query: "Indonesia", subjectType: 1, page: 1, perPage: 20).catchError((e) {
          print("Indonesian search error: $e");
          return <String, dynamic>{};
        }),
      ]);

      final resHome = responses[0];
      final resSearch = responses[1];

      final List<dynamic> rawHomeItems = resHome['items'] ?? [];
      final List<dynamic> searchItems = resSearch['items'] ?? [];

      if (rawHomeItems.isEmpty && searchItems.isEmpty) {
        setState(() {
          _errorMessage = "Gagal memuat katalog. Periksa koneksi internet Anda.";
        });
      } else {
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
      }
    } catch (e) {
      print("MovieBox Home Catalog Error: $e");
      setState(() {
        _errorMessage = "Gagal memuat katalog. Silakan periksa jaringan.";
      });
    } finally {
      // 3. Load favorites and recent progress
      await _loadFavoritesAndProgress();

      if (mounted) {
        setState(() {
          _isLoadingHome = false;
        });
      }
    }
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
                !language.contains("en") && 
                !language.contains("eng") && 
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
            label: AppLanguageService.tr(en: "Language", id: "Bahasa"),
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
            label: AppLanguageService.tr(en: "Genre", id: "Genre"),
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
            label: AppLanguageService.tr(en: "Type", id: "Tipe"),
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
            label: AppLanguageService.tr(en: "Rating", id: "Rating"),
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
                      AppLanguageService.tr(en: "Reset", id: "Reset"),
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
                String labelText = item;
                if (item == "Semua") {
                  labelText = AppLanguageService.tr(en: "All", id: "Semua");
                } else if (item == "Indonesia") {
                  labelText = AppLanguageService.tr(en: "Indonesian", id: "Indonesia");
                } else if (item == "Korea") {
                  labelText = AppLanguageService.tr(en: "Korean", id: "Korea");
                } else if (item == "Japan") {
                  labelText = AppLanguageService.tr(en: "Japanese", id: "Japan");
                } else if (item == "China") {
                  labelText = AppLanguageService.tr(en: "Chinese", id: "China");
                } else if (item == "Movies") {
                  labelText = AppLanguageService.tr(en: "Movies", id: "Film");
                } else if (item == "TV Series") {
                  labelText = AppLanguageService.tr(en: "TV Series", id: "Serial TV");
                }
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(labelText),
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
                memCacheWidth: 320,
                memCacheHeight: 480,
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

  void _showSetPasscodeDialog() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const SetPasscodeDialog(),
    );
  }

  void _showUnlockDialog() async {
    final unlocked = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const UnlockPasscodeDialog(),
    );

    if (unlocked == true && mounted) {
      setState(() {
        _nsfwFilter = false;
        _applySearchFilter();
        if (_isFiltering) {
          _applyCustomFilters();
        }
      });
    }
  }

  void _showLanguageSettingsDialog() async {
    final currentLang = AppLanguageService.currentLanguage.value;
    final selected = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: const Color(0xFF1A1A1A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 380,
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.language, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      AppLanguageService.tr(
                        en: "App Language Settings",
                        id: "Pengaturan Bahasa Aplikasi",
                      ),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  AppLanguageService.tr(
                    en: "Select preferred language for app interface & default audio/subtitles",
                    id: "Pilih bahasa tampilan aplikasi & preferensi audio/subtitle",
                  ),
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 20),
                _buildLanguageOptionItem(
                  code: 'en',
                  title: 'English',
                  flag: '🇬🇧',
                  isSelected: currentLang == 'en',
                ),
                const SizedBox(height: 10),
                _buildLanguageOptionItem(
                  code: 'id',
                  title: 'Bahasa Indonesia',
                  flag: '🇮🇩',
                  isSelected: currentLang == 'id',
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TvFocusableCard(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade800,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        AppLanguageService.tr(en: "Close", id: "Tutup"),
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null && selected != currentLang) {
      await AppLanguageService.setLanguage(selected);
      setState(() {});
    }
  }

  Widget _buildLanguageOptionItem({
    required String code,
    required String title,
    required String flag,
    required bool isSelected,
  }) {
    return TvFocusableCard(
      onTap: () => Navigator.of(context).pop(code),
      borderRadius: BorderRadius.circular(10),
      scaleFactor: 1.02,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent.withValues(alpha: 0.2) : const Color(0xFF242424),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.redAccent : const Color(0xFF333333),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  color: isSelected ? Colors.white : Colors.grey.shade300,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.redAccent, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _nsfwFocusNode.dispose();
    _langFocusNode.dispose();
    _navHomeFocusNode.dispose();
    _navSearchFocusNode.dispose();
    _navFavFocusNode.dispose();
    _navHistoryFocusNode.dispose();
    _navSettingsFocusNode.dispose();
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
              const SizedBox(height: 12),

              // 2. Active tab content body
              Expanded(
                child: ClipRect(
                  child: _buildActiveTabBody(isTv),
                ),
              ),

              // 3. Premium TV & Mobile Bottom Navigation Bar
              _buildBottomNavBar(isTv),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveTabBody(bool isTv) {
    switch (_currentTabIndex) {
      case 1:
        return _buildSearchTabView(isTv);
      case 2:
        return _buildFavoritesTabView(isTv);
      case 3:
        return _buildHistoryTabView(isTv);
      case 4:
        return _buildSettingsTabView(isTv);
      case 0:
      default:
        return _buildHomeTabView(isTv);
    }
  }

  Widget _buildHomeTabView(bool isTv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterRow(isTv),
        const SizedBox(height: 12),
        Expanded(
          child: _isFiltering
              ? _buildFilteredResultsSection(isTv)
              : _buildHomeSections(isTv),
        ),
      ],
    );
  }

  Widget _buildSearchTabView(bool isTv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSearchBar(),
        const SizedBox(height: 12),
        Expanded(
          child: _hasSearched || _searchController.text.isNotEmpty
              ? _buildSearchResultsSection(isTv)
              : _buildSearchRecommendationsSection(isTv),
        ),
      ],
    );
  }

  Widget _buildSearchRecommendationsSection(bool isTv) {
    final List<dynamic> popularItems = [];
    for (final section in _homeItems) {
      final List<dynamic> subjects = section['subjects'] ?? [];
      popularItems.addAll(subjects);
      if (popularItems.length >= 24) break;
    }

    if (popularItems.isEmpty && _bannerItems.isNotEmpty) {
      for (final banner in _bannerItems) {
        if (banner['subject'] != null) {
          popularItems.add(banner['subject']);
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              const Icon(Icons.trending_up_rounded, color: Colors.redAccent, size: 20),
              const SizedBox(width: 8),
              Text(
                AppLanguageService.tr(en: "Popular & Trending Searches", id: "Pencarian Populer & Trending"),
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: popularItems.isEmpty
              ? Center(
                  child: Text(
                    AppLanguageService.tr(
                      en: "Type keywords above to search movies or TV shows",
                      id: "Ketik kata kunci di atas untuk mencari film atau serial TV",
                    ),
                    style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 14),
                  ),
                )
              : GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isTv ? 6 : 3,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: popularItems.length,
                  itemBuilder: (context, index) {
                    final item = popularItems[index];
                    final title = item['title'] ?? item['name'] ?? "Untitled";
                    final coverUrl = item['cover']?['url'] ?? item['coverUrl'] ?? "";
                    final subjectId = item['subjectId'] ?? item['id'] ?? "";
                    final rating = item['imdbRate'] ?? item['imdbRatingValue'] ?? "";

                    return TvFocusableCard(
                      onTap: () {
                        if (subjectId.toString().isNotEmpty) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DetailScreen(subjectId: subjectId.toString()),
                            ),
                          ).then((_) {
                            _loadFavoritesAndProgress();
                          });
                        }
                      },
                      borderRadius: BorderRadius.circular(10),
                      scaleFactor: 1.04,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: coverUrl,
                            memCacheWidth: 260,
                            memCacheHeight: 390,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(color: const Color(0xFF1E1E1E)),
                          ),
                          if (rating.toString().isNotEmpty)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 10),
                                    const SizedBox(width: 2),
                                    Text(
                                      "$rating",
                                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                    ),
                                  ],
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
                              padding: const EdgeInsets.all(6.0),
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
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
      ],
    );
  }

  Widget _buildFavoritesTabView(bool isTv) {
    if (_favorites.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, color: Colors.grey.shade600, size: 56),
            const SizedBox(height: 16),
            Text(
              AppLanguageService.tr(en: "No favorites added yet", id: "Belum ada favorit ditambahkan"),
              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              AppLanguageService.tr(
                en: "Mark movies or TV shows as favorite to see them here",
                id: "Tandai film atau serial TV sebagai favorit untuk melihatnya di sini",
              ),
              style: GoogleFonts.outfit(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            AppLanguageService.tr(en: "My Favorites List", id: "Daftar Favorit Saya"),
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isTv ? 6 : 3,
              childAspectRatio: 0.7,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: _favorites.length,
            itemBuilder: (context, index) {
              final item = _favorites[index];
              final title = item['title'] ?? "Untitled";
              final coverUrl = item['coverUrl'] ?? "";
              final subjectId = item['subjectId'] ?? "";
              final type = item['subjectType'];
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
                      memCacheWidth: 260,
                      memCacheHeight: 390,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(color: const Color(0xFF1E1E1E)),
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
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryTabView(bool isTv) {
    if (_recentPlays.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_rounded, color: Colors.grey.shade600, size: 56),
            const SizedBox(height: 16),
            Text(
              AppLanguageService.tr(en: "No watch history yet", id: "Belum ada riwayat tontonan"),
              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              AppLanguageService.tr(
                en: "Videos you start watching will appear here to resume anytime",
                id: "Video yang Anda tonton akan muncul di sini untuk dilanjutkan kapan saja",
              ),
              style: GoogleFonts.outfit(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Text(
            AppLanguageService.tr(en: "Continue Watching / History", id: "Lanjutkan Nonton & Riwayat"),
            style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: ListView.builder(
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
                  ? "Season $season: Episode $episode" 
                  : (progress == 0 
                      ? AppLanguageService.tr(en: "Re-watch", id: "Tonton Ulang") 
                      : AppLanguageService.tr(en: "Resume playback", id: "Lanjutkan tontonan"));

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
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
                  borderRadius: BorderRadius.circular(12),
                  scaleFactor: 1.02,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF161616),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF262626)),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CachedNetworkImage(
                            imageUrl: coverUrl,
                            memCacheWidth: 160,
                            memCacheHeight: 240,
                            width: 60,
                            height: 85,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF262626),
                              width: 60,
                              height: 85,
                              child: const Icon(Icons.movie, size: 24, color: Colors.grey),
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                subtitle,
                                style: GoogleFonts.outfit(
                                  color: Colors.cyan.shade400,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (progress > 0)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    minHeight: 4,
                                    backgroundColor: const Color(0xFF262626),
                                    valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(Icons.play_circle_fill_rounded, color: Colors.redAccent, size: 36),
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

  Widget _buildSettingsTabView(bool isTv) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16.0),
            child: Text(
              AppLanguageService.tr(en: "Settings & Preferences", id: "Pengaturan & Preferensi"),
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          // Language Card
          TvFocusableCard(
            onTap: () => _showLanguageSettingsDialog(),
            borderRadius: BorderRadius.circular(14),
            scaleFactor: 1.02,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF262626)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguageService.tr(en: "App Language", id: "Bahasa Aplikasi"),
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        ValueListenableBuilder<String>(
                          valueListenable: AppLanguageService.currentLanguage,
                          builder: (context, lang, child) {
                            return Text(
                              lang == 'id' ? 'Bahasa Indonesia (ID)' : 'English (EN)',
                              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 13),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // NSFW Filter Card
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
            borderRadius: BorderRadius.circular(14),
            scaleFactor: 1.02,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF262626)),
              ),
              child: Row(
                children: [
                  Icon(Icons.security_rounded, color: _nsfwFilter ? Colors.green : Colors.redAccent, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "NSFW Content Filter",
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _nsfwFilter 
                              ? AppLanguageService.tr(en: "Filter Enabled (Restricted Content Hidden)", id: "Filter Aktif (Konten Dewasa Disembunyikan)") 
                              : AppLanguageService.tr(en: "Filter Disabled (All Content Visible)", id: "Filter Nonaktif (Semua Konten Ditampilkan)"),
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _nsfwFilter ? Colors.green.shade800 : Colors.red.shade900,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _nsfwFilter ? "ON" : "OFF",
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(bool isTv) {
    final navItems = [
      {
        'index': 0,
        'icon': Icons.home_rounded,
        'label': AppLanguageService.tr(en: 'Home', id: 'Beranda'),
        'focusNode': _navHomeFocusNode,
      },
      {
        'index': 1,
        'icon': Icons.search_rounded,
        'label': AppLanguageService.tr(en: 'Search', id: 'Cari'),
        'focusNode': _navSearchFocusNode,
      },
      {
        'index': 2,
        'icon': Icons.favorite_rounded,
        'label': AppLanguageService.tr(en: 'Favorites', id: 'Favorit'),
        'badge': _favorites.length,
        'focusNode': _navFavFocusNode,
      },
      {
        'index': 3,
        'icon': Icons.history_rounded,
        'label': AppLanguageService.tr(en: 'History', id: 'Riwayat'),
        'badge': _recentPlays.length,
        'focusNode': _navHistoryFocusNode,
      },
      {
        'index': 4,
        'icon': Icons.settings_rounded,
        'label': AppLanguageService.tr(en: 'Settings', id: 'Pengaturan'),
        'focusNode': _navSettingsFocusNode,
      },
    ];

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF262626), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: navItems.map((item) {
          final int index = item['index'] as int;
          final bool isSelected = _currentTabIndex == index;
          final IconData icon = item['icon'] as IconData;
          final String label = item['label'] as String;
          final int badge = item['badge'] as int? ?? 0;
          final FocusNode fNode = item['focusNode'] as FocusNode;

          return TvFocusableCard(
            focusNode: fNode,
            onTap: () {
              setState(() {
                _currentTabIndex = index;
                if (index == 0) {
                  _isFiltering = false;
                  _hasSearched = false;
                  _searchController.clear();
                }
              });

              if (index == 1) {
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    _searchFocusNode.requestFocus();
                  }
                });
              }
            },
            borderRadius: BorderRadius.circular(16),
            scaleFactor: 1.05,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: isTv ? 20 : 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: isSelected ? Colors.redAccent.shade700 : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        icon,
                        color: isSelected ? Colors.white : Colors.grey.shade400,
                        size: isTv ? 22 : 18,
                      ),
                      if (badge > 0 && !isSelected)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(minWidth: 12, minHeight: 12),
                            child: Text(
                              '$badge',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isTv ? 14 : 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeader(bool isTv) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // App Title Logo
        Flexible(
          child: Text(
            'MOVIEBOX',
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: isTv ? 30 : 22,
              fontWeight: FontWeight.w900,
              color: Colors.redAccent.shade700,
              letterSpacing: 1.5,
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Compact App Language Setting Button
            TvFocusableCard(
              focusNode: _langFocusNode,
              onTap: () {
                _showLanguageSettingsDialog();
              },
              borderRadius: BorderRadius.circular(16),
              scaleFactor: 1.04,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.language, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 4),
                    ValueListenableBuilder<String>(
                      valueListenable: AppLanguageService.currentLanguage,
                      builder: (context, lang, child) {
                        return Text(
                          lang.toUpperCase(),
                          style: GoogleFonts.outfit(
                            color: Colors.grey.shade300,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Compact NSFW Filter Action Button
            TvFocusableCard(
              focusNode: _nsfwFocusNode,
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
              scaleFactor: 1.04,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2C2C2C)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'NSFW',
                      style: GoogleFonts.outfit(
                        color: Colors.grey.shade300,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: _nsfwFilter ? Colors.green.shade800 : Colors.red.shade900,
                      ),
                      child: Text(
                        _nsfwFilter ? 'ON' : 'OFF',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
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
          hintText: AppLanguageService.tr(
            en: "Search movies or TV shows here...",
            id: "Cari film atau serial TV di sini...",
          ),
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
                memCacheWidth: 320,
                memCacheHeight: 480,
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

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, color: Colors.grey.shade600, size: 56),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 15),
            ),
            const SizedBox(height: 20),
            TvFocusableCard(
              autoFocus: true,
              onTap: _loadAllHomeData,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                color: Colors.redAccent.shade700,
                child: Text(
                  AppLanguageService.tr(en: "Retry", id: "Coba Lagi"),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
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
              memCacheWidth: 800,
              memCacheHeight: 450,
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
            AppLanguageService.tr(en: "Continue Watching", id: "Lanjutkan Nonton"),
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
                  : (progress == 0 
                      ? AppLanguageService.tr(en: "Re-watch", id: "Tonton Ulang") 
                      : AppLanguageService.tr(en: "Resume", id: "Lanjutkan"));

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
                            memCacheWidth: 150,
                            memCacheHeight: 250,
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
                AppLanguageService.tr(en: "My Favorites", id: "Favorit Saya"),
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
                          memCacheWidth: 260,
                          memCacheHeight: 390,
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
                          memCacheWidth: 260,
                          memCacheHeight: 390,
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


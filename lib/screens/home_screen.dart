import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/moviebox_api_service.dart';
import '../services/fourkhdhub_service.dart';
import '../services/fourkhdhub_api_service.dart';
import '../services/tmdb_service.dart';
import '../services/favorites_service.dart';
import '../services/playback_progress_service.dart';
import '../services/search_history_service.dart';
import '../services/app_language_service.dart';
import '../services/app_content_filter_service.dart';
import '../widgets/tv_focusable_card.dart';
import '../widgets/tv_pin_pad_dialog.dart';
import 'detail_screen.dart';
import 'live_tv_screen.dart';
import 'downloads_screen.dart';
import 'provider_catalog_screen.dart';
import '../services/download_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';
import '../widgets/update_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final MovieBoxApiService _api = MovieBoxApiService();
  final FourKHdHubService _fourkApi = FourKHdHubService();
  final FourKHdHubApiService _fourkHomeApi = FourKHdHubApiService();
  final TmdbService _tmdb = TmdbService();
  String _selectedSearchProvider = "all";
  final TextEditingController _searchController = TextEditingController();
  late final FocusNode _searchFocusNode;
  late final FocusNode _nsfwFocusNode;
  late final FocusNode _langFocusNode;

  // Bottom Navigation Bar state and focus nodes
  int _currentTabIndex = 0;
  late final FocusNode _navHomeFocusNode;
  late final FocusNode _navSearchFocusNode;
  late final FocusNode _navLiveTvFocusNode;
  late final FocusNode _navFavFocusNode;
  late final FocusNode _navHistoryFocusNode;
  late final FocusNode _navDownloadsFocusNode;
  late final FocusNode _navSettingsFocusNode;

  List<dynamic> _searchResults = [];
  List<dynamic> _rawSearchResults = [];
  bool _nsfwFilter = false;
  bool _isLoadingSearch = false;
  bool _isLoadingHome = true;
  String _errorMessage = "";
  bool _hasSearched = false;

  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _recentPlays = [];
  List<String> _searchHistory = [];
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
    _navLiveTvFocusNode = FocusNode();
    _navFavFocusNode = FocusNode();
    _navHistoryFocusNode = FocusNode();
    _navDownloadsFocusNode = FocusNode();
    _navSettingsFocusNode = FocusNode();
    DownloadService.instance.init();

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
    _loadSearchHistory();
    _loadNsfwFilterPreference();
    _checkPasscodeSetup();
    _checkAutoUpdateSilently();
    AppContentFilterService.filterHindi.addListener(_onHindiFilterChanged);
  }

  Future<void> _checkAutoUpdateSilently() async {
    // Wait for initial screen rendering to settle
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;

    try {
      final release = await UpdateService.instance.checkForUpdate();
      if (release != null && mounted) {
        UpdateDialog.show(context, release);
      }
    } catch (_) {}
  }

  Future<void> _checkUpdateManually() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1C),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2C2C2C)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SpinKitRing(color: Colors.redAccent, size: 36),
              const SizedBox(height: 16),
              Text(
                AppLanguageService.tr(
                  en: "Checking for updates on GitHub...",
                  id: "Memeriksa pembaruan di GitHub...",
                ),
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );

    final release = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;
    Navigator.pop(context); // Dismiss loading dialog

    if (release != null) {
      UpdateDialog.show(context, release);
    } else {
      final pkgInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 24),
              const SizedBox(width: 10),
              Text(
                AppLanguageService.tr(en: "Up to Date", id: "Versi Terbaru"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ],
          ),
          content: Text(
            AppLanguageService.tr(
              en: "You are already using the latest version of MovieBox (v${pkgInfo.version}).",
              id: "Anda sudah menggunakan versi terbaru MovieBox (v${pkgInfo.version}).",
            ),
            style: GoogleFonts.outfit(color: Colors.grey.shade300, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                AppLanguageService.tr(en: "OK", id: "OK"),
                style: GoogleFonts.outfit(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _loadNsfwFilterPreference() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _nsfwFilter = prefs.getBool('nsfw_filter_enabled') ?? false;
      });
    }
  }

  Future<void> _toggleNsfwFilter(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('nsfw_filter_enabled', enabled);
    if (mounted) {
      setState(() {
        _nsfwFilter = enabled;
        _applySearchFilter();
        if (_isFiltering) {
          _applyCustomFilters();
        }
      });
    }
  }

  void _onHindiFilterChanged() {
    if (mounted) {
      setState(() {
        _applySearchFilter();
        if (_isFiltering) {
          _applyCustomFilters();
        }
      });
    }
  }

  Future<void> _loadAllHomeData() async {
    setState(() {
      _isLoadingHome = true;
      _errorMessage = "";
    });

    try {
      // 1. Fetch TMDB, 4KHDHub homepage, Indonesian movies, and MovieBox homepage concurrently
      final responses = await Future.wait([
        _tmdb.getNowPlayingMovies().catchError((e) {
          print("TMDB Now Playing error: $e");
          return <Map<String, dynamic>>[];
        }),
        _tmdb.getTrendingMovies().catchError((e) {
          print("TMDB Trending Movies error: $e");
          return <Map<String, dynamic>>[];
        }),
        _tmdb.getTrendingTv().catchError((e) {
          print("TMDB Trending TV error: $e");
          return <Map<String, dynamic>>[];
        }),
        _api.search(query: "Indonesia", subjectType: 1, page: 1, perPage: 20).catchError((e) {
          print("Indonesian search error: $e");
          return <String, dynamic>{};
        }),
        _fourkHomeApi.getHomepage(page: 1).catchError((e) {
          print("4KHDHub homepage error: $e");
          return <String, dynamic>{};
        }),
        _api.getHomepage(page: 1, tabId: 0).catchError((e) {
          print("MovieBox homepage fetch error: $e");
          return <String, dynamic>{};
        }),
        _tmdb.getMoviesByProvider(providerId: 8).catchError((e) {
          return <Map<String, dynamic>>[];
        }),
        _tmdb.getMoviesByProvider(providerId: 122).catchError((e) {
          return <Map<String, dynamic>>[];
        }),
      ]);

      final List<Map<String, dynamic>> nowPlaying = responses[0] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> trendingMovies = responses[1] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> trendingTv = responses[2] as List<Map<String, dynamic>>;
      final Map<String, dynamic> resSearch = responses[3] as Map<String, dynamic>;
      final Map<String, dynamic> res4k = responses[4] as Map<String, dynamic>;
      final Map<String, dynamic> resHome = responses[5] as Map<String, dynamic>;
      final List<Map<String, dynamic>> netflixMovies = responses.length > 6 ? (responses[6] as List<Map<String, dynamic>>) : [];
      final List<Map<String, dynamic>> disneyMovies = responses.length > 7 ? (responses[7] as List<Map<String, dynamic>>) : [];

      final List<dynamic> searchItems = resSearch['items'] ?? [];
      final List<dynamic> fourkSections = res4k['items'] ?? [];
      final List<dynamic> rawHomeItems = resHome['items'] ?? [];

      if (nowPlaying.isEmpty && trendingMovies.isEmpty && rawHomeItems.isEmpty && searchItems.isEmpty) {
        setState(() {
          _errorMessage = "Gagal memuat katalog. Periksa koneksi internet Anda.";
        });
      } else {
        // 2. Setup Spotlight Banners (prefer TMDB Trending with HD backdrops, fallback to MovieBox)
        List<dynamic> banners = [];
        if (trendingMovies.isNotEmpty) {
          banners = trendingMovies.take(5).map((item) {
            final backdrop = item['backdrop']?['url'] ?? item['cover']?['url'] ?? "";
            return {
              "content": item['title'],
              "title": item['title'],
              "subjectId": item['subjectId'],
              "provider": "tmdb",
              "image": {"url": backdrop},
              "subject": {
                "title": item['title'],
                "imdbRate": item['imdbRate'],
                "imdbRatingValue": item['imdbRate'],
                "releaseDate": item['releaseDate'],
                "description": item['description'],
              },
              "rawTmdb": item,
            };
          }).toList();
        } else {
          final bannerSection = rawHomeItems.firstWhere(
            (item) => item['type'] == 'BANNER',
            orElse: () => null,
          );
          if (bannerSection != null && bannerSection['banner'] != null) {
            banners = bannerSection['banner']['banners'] ?? [];
          }
        }
        banners = AppContentFilterService.filterList(banners);

        // 3. Assemble dynamic category rows
        final List<dynamic> assembledSections = [];

        // Row 1: Now Playing in Cinemas (TMDB)
        if (nowPlaying.isNotEmpty) {
          assembledSections.add({
            "titleEn": "🔥 In Theatres (Now Playing)",
            "titleId": "🔥 Sedang Tayang di Bioskop",
            "title": AppLanguageService.tr(en: "🔥 In Theatres (Now Playing)", id: "🔥 Sedang Tayang di Bioskop"),
            "subjects": nowPlaying,
          });
        }

        // Row 2: Trending Movies Today (TMDB)
        if (trendingMovies.isNotEmpty) {
          assembledSections.add({
            "titleEn": "⭐ Trending Movies Today",
            "titleId": "⭐ Film Populer Hari Ini",
            "title": AppLanguageService.tr(en: "⭐ Trending Movies Today", id: "⭐ Film Populer Hari Ini"),
            "subjects": trendingMovies,
          });
        }

        // Row 3: Trending TV Series (TMDB)
        if (trendingTv.isNotEmpty) {
          assembledSections.add({
            "titleEn": "📺 Popular TV Shows",
            "titleId": "📺 Serial TV Populer",
            "title": AppLanguageService.tr(en: "📺 Popular TV Shows", id: "📺 Serial TV Populer"),
            "subjects": trendingTv,
          });
        }

        // Row 4: 4KHDHub Ultra-HD Releases
        for (final sec in fourkSections) {
          if (sec is Map<String, dynamic> && (sec['subjects'] as List? ?? []).isNotEmpty) {
            final secTitle = (sec['title'] ?? '4KHDHub Latest').toString();
            assembledSections.add({
              "title": "💎 $secTitle",
              "subjects": sec['subjects'],
            });
          }
        }

        // Row 5: Netflix Top Picks
        if (netflixMovies.isNotEmpty) {
          assembledSections.add({
            "titleEn": "🍿 Netflix Top Picks",
            "titleId": "🍿 Pilihan Populer Netflix",
            "title": AppLanguageService.tr(en: "🍿 Netflix Top Picks", id: "🍿 Pilihan Populer Netflix"),
            "subjects": netflixMovies,
          });
        }

        // Row 6: Disney+ Highlights
        if (disneyMovies.isNotEmpty) {
          assembledSections.add({
            "titleEn": "✨ Disney+ Highlights",
            "titleId": "✨ Pilihan Populer Disney+",
            "title": AppLanguageService.tr(en: "✨ Disney+ Highlights", id: "✨ Pilihan Populer Disney+"),
            "subjects": disneyMovies,
          });
        }

        // Row 7: Indonesian Movies
        if (searchItems.isNotEmpty) {
          assembledSections.add({
            "titleEn": "🇮🇩 Indonesian Movies",
            "titleId": "🇮🇩 Film Indonesia",
            "title": AppLanguageService.tr(en: "🇮🇩 Indonesian Movies", id: "🇮🇩 Film Indonesia"),
            "subjects": searchItems,
          });
        }

        // Row 8+: Classic MovieBox Category Rows
        final subjectsSections = rawHomeItems.where((item) => item['type'] == 'SUBJECTS_MOVIE').toList();
        assembledSections.addAll(subjectsSections);

        setState(() {
          _homeItems = assembledSections;
          _bannerItems = banners;
        });
      }
    } catch (e) {
      print("Home Catalog Error: $e");
      setState(() {
        _errorMessage = e is RateLimitException
            ? AppLanguageService.tr(
                en: "Server rate limited. Please try again in a few moments.",
                id: "Server membatasi request (Rate Limited). Silakan coba beberapa saat lagi.",
              )
            : e is NetworkConnectionException
                ? AppLanguageService.tr(
                    en: "Network connection failed. Please check your internet connection.",
                    id: "Koneksi jaringan gagal. Periksa koneksi internet Anda.",
                  )
                : AppLanguageService.tr(
                    en: "Failed to load catalog. Please check your network.",
                    id: "Gagal memuat katalog. Silakan periksa jaringan.",
                  );
      });
    } finally {
      // 4. Load favorites and recent progress
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

  Future<void> _loadSearchHistory() async {
    final history = await SearchHistoryService.getSearchHistory();
    if (mounted) {
      setState(() {
        _searchHistory = history;
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

  Future<void> _deleteWatchHistoryItem(String subjectId, String title) async {
    await PlaybackProgressService.removeRecentPlay(subjectId);
    await _loadFavoritesAndProgress();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguageService.tr(
              en: "\"$title\" removed from watch history",
              id: "\"$title\" dihapus dari riwayat tontonan",
            ),
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: const Color(0xFF222222),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmDeleteWatchHistoryItem(Map<String, dynamic> item) async {
    final title = item['title'] ?? "Untitled";
    final subjectId = item['subjectId']?.toString() ?? "";
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppLanguageService.tr(en: "Remove from History?", id: "Hapus dari Riwayat?"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          AppLanguageService.tr(
            en: "Remove \"$title\" from your watch history?",
            id: "Hapus \"$title\" dari riwayat tontonan Anda?",
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
              AppLanguageService.tr(en: "Remove", id: "Hapus"),
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _deleteWatchHistoryItem(subjectId, title);
    }
  }

  Future<void> _showClearAllWatchHistoryDialog() async {
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
                AppLanguageService.tr(en: "Clear Watch History?", id: "Hapus Riwayat Tontonan?"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Text(
          AppLanguageService.tr(
            en: "Are you sure you want to delete all watch history and playback progress?",
            id: "Apakah Anda yakin ingin menghapus seluruh riwayat tontonan dan progres pemutaran?",
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
              AppLanguageService.tr(en: "Delete All", id: "Hapus Semua"),
              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await PlaybackProgressService.clearAllRecentPlays();
      await _loadFavoritesAndProgress();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.tr(en: "Watch history cleared", id: "Riwayat tontonan telah dibersihkan"),
              style: GoogleFonts.outfit(),
            ),
            backgroundColor: const Color(0xFF222222),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _applySearchFilter() {
    List<dynamic> list = _rawSearchResults;
    if (_nsfwFilter) {
      list = list.where((item) {
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
    }
    if (AppContentFilterService.filterHindi.value) {
      list = AppContentFilterService.filterList(list);
    }
    _searchResults = list;
  }

  void _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    SearchHistoryService.addSearchQuery(query);
    _loadSearchHistory();

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
      if (_selectedSearchProvider == '4khdhub') {
        final hubResults = await _fourkApi.search(query);
        final mapped = hubResults.map((item) => {
          ...item,
          'provider': '4khdhub',
          'subjectId': item['pathId'],
          'cover': {'url': item['coverUrl']},
        }).toList();

        setState(() {
          _rawSearchResults = mapped;
          _searchResults = mapped;
          if (_searchResults.isEmpty) {
            _errorMessage = "Tidak ada hasil di 4KHDHub untuk '$query'";
          }
        });
      } else if (_selectedSearchProvider == 'moviebox') {
        final res = await _api.search(query: query);
        final mbItems = ((res['items'] ?? []) as List<dynamic>).map((item) => {
          ...item,
          'provider': 'moviebox',
        }).toList();

        setState(() {
          _rawSearchResults = mbItems;
          _applySearchFilter();
          if (_searchResults.isEmpty) {
            _errorMessage = "Tidak ada hasil di MovieBox untuk '$query'";
          }
        });
      } else {
        // 'all': Search both concurrently
        final results = await Future.wait([
          _api.search(query: query).catchError((e) {
            print("MovieBox search error in All: $e");
            return <String, dynamic>{'items': []};
          }),
          _fourkApi.search(query).catchError((e) {
            print("4KHDHub search error in All: $e");
            return <Map<String, dynamic>>[];
          }),
        ]);

        final mbRaw = (results[0] as Map<String, dynamic>)['items'] ?? [];
        final List<dynamic> mbList = (mbRaw as List<dynamic>).map((item) => {
          ...item,
          'provider': 'moviebox',
        }).toList();

        final hubRaw = results[1] as List<Map<String, dynamic>>;
        final List<dynamic> hubList = hubRaw.map((item) => {
          ...item,
          'provider': '4khdhub',
          'subjectId': item['pathId'],
          'cover': {'url': item['coverUrl']},
        }).toList();

        // Interleave results so user gets a mix of MovieBox and 4KHDHub
        final List<dynamic> combined = [];
        int maxLen = mbList.length > hubList.length ? mbList.length : hubList.length;
        for (int i = 0; i < maxLen; i++) {
          if (i < hubList.length) combined.add(hubList[i]);
          if (i < mbList.length) combined.add(mbList[i]);
        }

        setState(() {
          _rawSearchResults = combined;
          _searchResults = combined;
          if (_searchResults.isEmpty) {
            _errorMessage = "Tidak ada hasil untuk '$query'";
          }
        });
      }
    } catch (e) {
      print("Search Error: $e");
      setState(() {
        _errorMessage = "Error saat mencari ($e). Silakan coba lagi.";
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

        if (AppContentFilterService.filterHindi.value) {
          if (AppContentFilterService.isItemHindiDub(item)) {
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
        final provider = item['provider'] ?? (subjectId.toString().startsWith('/') ? '4khdhub' : 'moviebox');
        final rating = item['imdbRate'] ?? item['imdbRatingValue'] ?? "";
        final type = item['subjectType'] ?? item['subject_type'] ?? 1;
        final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';

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
      _toggleNsfwFilter(false);
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
            constraints: const BoxConstraints(maxWidth: 380),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.language, color: Colors.redAccent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
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
      _loadAllHomeData();
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
    _navLiveTvFocusNode.dispose();
    _navFavFocusNode.dispose();
    _navHistoryFocusNode.dispose();
    _navDownloadsFocusNode.dispose();
    _navSettingsFocusNode.dispose();
    AppContentFilterService.filterHindi.removeListener(_onHindiFilterChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: AppLanguageService.currentLanguage,
      builder: (context, currentLanguageCode, _) {
        final size = MediaQuery.of(context).size;
        final isTv = size.width > 800 && size.height > 500;
        final isShortScreen = size.height < 480;

        return Scaffold(
          backgroundColor: const Color(0xFF0A0A0A),
          body: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.only(
                left: isTv ? 24.0 : (isShortScreen ? 12.0 : 16.0),
                right: isTv ? 24.0 : (isShortScreen ? 12.0 : 16.0),
                top: isShortScreen ? 4.0 : 8.0,
                bottom: 0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Header (Logo & Remote action icons)
                  if (!isShortScreen) ...[
                    _buildHeader(isTv),
                    const SizedBox(height: 8),
                  ],

                  // 2. Active tab content body
                  Expanded(
                    child: ClipRect(
                      child: _buildActiveTabBody(isTv),
                    ),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isTv ? 24.0 : (isShortScreen ? 6.0 : 8.0),
                vertical: isShortScreen ? 2.0 : 4.0,
              ),
              child: _buildBottomNavBar(isTv),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActiveTabBody(bool isTv) {
    switch (_currentTabIndex) {
      case 1:
        return _buildSearchTabView(isTv);
      case 2:
        return const LiveTvScreen();
      case 3:
        return _buildFavoritesTabView(isTv);
      case 4:
        return _buildHistoryTabView(isTv);
      case 5:
        return DownloadsScreen(isTv: isTv);
      case 6:
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
        const SizedBox(height: 10),
        _buildSearchProviderFilterRow(),
        const SizedBox(height: 12),
        Expanded(
          child: _hasSearched || _searchController.text.isNotEmpty
              ? _buildSearchResultsSection(isTv)
              : _buildSearchRecommendationsSection(isTv),
        ),
      ],
    );
  }

  Widget _buildSearchProviderFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildProviderFilterChip(
            id: 'all',
            label: AppLanguageService.tr(en: "All Providers", id: "Semua Provider"),
            icon: Icons.layers_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 8),
          _buildProviderFilterChip(
            id: 'moviebox',
            label: "MovieBox",
            icon: Icons.movie_rounded,
            color: Colors.redAccent,
          ),
          const SizedBox(width: 8),
          _buildProviderFilterChip(
            id: '4khdhub',
            label: "4KHDHub (4K UHD)",
            icon: Icons.hd_rounded,
            color: Colors.cyanAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildProviderFilterChip({
    required String id,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isSelected = _selectedSearchProvider == id;
    return TvFocusableCard(
      onTap: () {
        setState(() {
          _selectedSearchProvider = id;
        });
        if (_searchController.text.trim().isNotEmpty) {
          _onSearch();
        }
      },
      borderRadius: BorderRadius.circular(20),
      scaleFactor: 1.04,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : const Color(0xFF181818),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : const Color(0xFF303030),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? color : Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: isSelected ? Colors.white : Colors.grey.shade400,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2.0, bottom: 8.0),
          child: Row(
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
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _searchHistory.map((query) {
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: _buildSearchHistoryChip(query),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchHistoryChip(String query) {
    return TvFocusableCard(
      onTap: () {
        _searchController.text = query;
        _onSearch();
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
        if (_searchHistory.isNotEmpty) ...[
          _buildSearchHistorySection(),
          const SizedBox(height: 10),
        ],
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
              final provider = item['provider'] ?? (subjectId.toString().startsWith('/') ? '4khdhub' : 'moviebox');
              final type = item['subjectType'];
              final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';

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
                    if (provider == '4khdhub')
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.cyan.shade900.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 0.8),
                          ),
                          child: Text(
                            "4K UHD",
                            style: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
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
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppLanguageService.tr(en: "Continue Watching / History", id: "Lanjutkan Nonton & Riwayat"),
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TvFocusableCard(
                onTap: _showClearAllWatchHistoryDialog,
                borderRadius: BorderRadius.circular(8),
                scaleFactor: 1.05,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        AppLanguageService.tr(en: "Clear All", id: "Hapus Semua"),
                        style: GoogleFonts.outfit(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
              final provider = item['provider'] ?? (subjectId.toString().startsWith('/') ? '4khdhub' : 'moviebox');
              final season = item['season'] ?? 0;
              final episode = item['episode'] ?? 0;
              final pos = item['positionMs'] ?? 0;
              final dur = item['durationMs'] ?? 1;

              final progress = (pos / dur).clamp(0.0, 1.0);
              final isShow = season > 0 || episode > 0;
              final isNextCue = item['isNextCue'] == true;
              final String subtitle = isShow 
                  ? (isNextCue 
                      ? "Season $season: Episode $episode • ${AppLanguageService.tr(en: "Next Episode", id: "Episode Selanjutnya")}"
                      : "Season $season: Episode $episode") 
                  : (progress == 0 
                      ? AppLanguageService.tr(en: "Re-watch", id: "Tonton Ulang") 
                      : AppLanguageService.tr(en: "Resume playback", id: "Lanjutkan tontonan"));

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TvFocusableCard(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => DetailScreen(
                                subjectId: subjectId,
                                provider: provider,
                                initialSeason: isShow ? season : null,
                                initialEpisode: isShow ? episode : null,
                              ),
                            ),
                          ).then((_) {
                            _loadFavoritesAndProgress();
                          });
                        },
                        onLongPress: () => _confirmDeleteWatchHistoryItem(item),
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
                                    Row(
                                      children: [
                                        if (provider == '4khdhub') ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            margin: const EdgeInsets.only(right: 6),
                                            decoration: BoxDecoration(
                                              color: Colors.cyan.shade900.withOpacity(0.85),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 0.8),
                                            ),
                                            child: Text(
                                              "4K UHD",
                                              style: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ],
                                        Expanded(
                                          child: Text(
                                            title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ],
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
                    ),
                    const SizedBox(width: 8),
                    TvFocusableCard(
                      onTap: () => _confirmDeleteWatchHistoryItem(item),
                      borderRadius: BorderRadius.circular(12),
                      scaleFactor: 1.06,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 38),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161616),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF262626)),
                        ),
                        child: const Icon(Icons.delete_outline_rounded, color: Colors.grey, size: 22),
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
                _toggleNsfwFilter(true);
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
          const SizedBox(height: 16),
          // Hide Hindi Dubs Filter Card
          TvFocusableCard(
            onTap: () async {
              final current = AppContentFilterService.filterHindi.value;
              await AppContentFilterService.setFilterHindi(!current);
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
              child: ValueListenableBuilder<bool>(
                valueListenable: AppContentFilterService.filterHindi,
                builder: (context, filterActive, child) {
                  return Row(
                    children: [
                      Icon(
                        Icons.translate_rounded,
                        color: filterActive ? Colors.cyanAccent : Colors.grey,
                        size: 28,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLanguageService.tr(
                                en: "Hide [Hindi] Dubs Filter",
                                id: "Filter Sembunyikan Dub [Hindi]",
                              ),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              filterActive
                                  ? AppLanguageService.tr(
                                      en: "Filter Enabled (Titles with [Hindi] tag are hidden)",
                                      id: "Filter Aktif (Judul bertag [Hindi] disembunyikan)",
                                    )
                                  : AppLanguageService.tr(
                                      en: "Filter Disabled (Showing all content including Hindi dubs)",
                                      id: "Filter Nonaktif (Semua konten termasuk dub Hindi ditampilkan)",
                                    ),
                              style: GoogleFonts.outfit(
                                color: Colors.grey.shade400,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: filterActive ? Colors.green.shade800 : Colors.red.shade900,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          filterActive ? "ON" : "OFF",
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Check for Updates Card
          TvFocusableCard(
            onTap: _checkUpdateManually,
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
                  const Icon(Icons.system_update_rounded, color: Colors.redAccent, size: 28),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLanguageService.tr(en: "Check for Updates", id: "Periksa Pembaruan"),
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            final ver = snapshot.hasData ? "v${snapshot.data!.version}" : "v1.2.4";
                            return Text(
                              AppLanguageService.tr(
                                en: "Current Version: $ver • Tap to check latest release on GitHub",
                                id: "Versi saat ini: $ver • Ketuk untuk cek rilis terbaru di GitHub",
                              ),
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
        ],
      ),
    );
  }

  Widget _buildBottomNavBar(bool isTv) {
    return ValueListenableBuilder<List<DownloadItem>>(
      valueListenable: DownloadService.instance.downloadsNotifier,
      builder: (context, downloadItems, _) {
        final downloadBadge = downloadItems.where((i) => i.status == DownloadStatus.downloading || i.status == DownloadStatus.completed).length;

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
            'icon': Icons.live_tv_rounded,
            'label': AppLanguageService.tr(en: 'Live TV', id: 'Live TV'),
            'focusNode': _navLiveTvFocusNode,
          },
          {
            'index': 3,
            'icon': Icons.favorite_rounded,
            'label': AppLanguageService.tr(en: 'Favorites', id: 'Favorit'),
            'badge': _favorites.length,
            'focusNode': _navFavFocusNode,
          },
          {
            'index': 4,
            'icon': Icons.history_rounded,
            'label': AppLanguageService.tr(en: 'History', id: 'Riwayat'),
            'badge': _recentPlays.length,
            'focusNode': _navHistoryFocusNode,
          },
          {
            'index': 5,
            'icon': Icons.download_rounded,
            'label': AppLanguageService.tr(en: 'Downloads', id: 'Unduhan'),
            'badge': downloadBadge,
            'focusNode': _navDownloadsFocusNode,
          },
          {
            'index': 6,
            'icon': Icons.settings_rounded,
            'label': AppLanguageService.tr(en: 'Settings', id: 'Pengaturan'),
            'focusNode': _navSettingsFocusNode,
          },
        ];

        return LayoutBuilder(
          builder: (context, constraints) {
            final isVeryNarrow = constraints.maxWidth < 360;
            final containerHPad = isTv ? 16.0 : (isVeryNarrow ? 4.0 : 6.0);
            final containerVPad = isTv ? 6.0 : 4.0;
            final innerWidth = (constraints.maxWidth - (containerHPad * 2)).clamp(0.0, double.infinity);

            return Container(
              width: double.infinity,
              margin: EdgeInsets.zero,
              padding: EdgeInsets.symmetric(horizontal: containerHPad, vertical: containerVPad),
              decoration: BoxDecoration(
                color: const Color(0xFF141414),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF262626), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: innerWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: navItems.map((item) {
                      final int index = item['index'] as int;
                      final bool isSelected = _currentTabIndex == index;
                      final IconData icon = item['icon'] as IconData;
                      final String label = item['label'] as String;
                      final int badge = item['badge'] as int? ?? 0;
                      final FocusNode fNode = item['focusNode'] as FocusNode;

                      final double itemHPad = isSelected
                          ? (isTv ? 18.0 : (isVeryNarrow ? 8.0 : 10.0))
                          : (isTv ? 12.0 : (isVeryNarrow ? 5.0 : 6.0));
                      final double itemVPad = isTv ? 8.0 : (isVeryNarrow ? 5.0 : 6.0);
                      final double iconSize = isTv ? 22.0 : (isVeryNarrow ? 18.0 : 19.0);
                      final double fontSize = isTv ? 13.0 : (isVeryNarrow ? 11.0 : 11.5);

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
                            _loadSearchHistory();
                            Future.delayed(const Duration(milliseconds: 100), () {
                              if (mounted) {
                                _searchFocusNode.requestFocus();
                              }
                            });
                          } else if (index == 4 || index == 3 || index == 0) {
                            _loadFavoritesAndProgress();
                          }
                        },
                        borderRadius: BorderRadius.circular(16),
                        scaleFactor: 1.05,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: EdgeInsets.symmetric(
                            horizontal: itemHPad,
                            vertical: itemVPad,
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
                                    size: iconSize,
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
                                SizedBox(width: isTv ? 6.0 : 4.0),
                                Text(
                                  label,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: fontSize,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            );
          },
        );
      },
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
                  _toggleNsfwFilter(true);
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
        final coverUrl = item['cover']?['url'] ?? item['coverUrl'] ?? "";
        final subjectId = item['subjectId'] ?? item['id']?.toString() ?? "";
        final provider = item['provider'] ?? (subjectId.toString().startsWith('/') ? '4khdhub' : 'moviebox');
        final rating = item['imdbRate'] ?? item['imdbRatingValue'] ?? "";

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
              // Provider Badge (Top Right)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: provider == '4khdhub'
                        ? Colors.cyan.shade900.withValues(alpha: 0.85)
                        : Colors.red.shade900.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: provider == '4khdhub'
                          ? Colors.cyanAccent.withValues(alpha: 0.5)
                          : Colors.redAccent.withValues(alpha: 0.3),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    provider == '4khdhub' ? "4KHDHub" : "MovieBox",
                    style: GoogleFonts.outfit(
                      color: provider == '4khdhub' ? Colors.cyanAccent : Colors.white,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
            const SizedBox(height: 20),

            // 2. Streaming Platforms Shortcut Bar
            _buildStreamingPlatformsRow(isTv),
            const SizedBox(height: 24),

            // 3. Lanjutkan Nonton Section
            if (_recentPlays.isNotEmpty) ...[
              _buildContinueWatchingSection(isTv),
              const SizedBox(height: 24),
            ],

            // 4. Favorites Section
            if (_favorites.isNotEmpty) ...[
              _buildFavoritesSection(isTv),
              const SizedBox(height: 24),
            ],

            // 5. Dynamic Category Rows
            ..._homeItems.map((section) {
              final String title;
              if (section is Map && section['titleEn'] != null && section['titleId'] != null) {
                title = AppLanguageService.tr(
                  en: section['titleEn'].toString(),
                  id: section['titleId'].toString(),
                );
              } else {
                title = section['title'] ?? "Trending";
              }
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
            final prov = banner['provider'] ?? 'moviebox';
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DetailScreen(
                  subjectId: subjectId,
                  provider: prov,
                  tmdbData: prov == 'tmdb' ? banner : null,
                ),
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

  Widget _buildStreamingPlatformsRow(bool isTv) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: [
              const Icon(Icons.tv_rounded, color: Colors.cyanAccent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  AppLanguageService.tr(
                    en: "Streaming Platforms",
                    id: "Platform Streaming",
                  ),
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppLanguageService.tr(
                  en: "Explore All →",
                  id: "Jelajahi →",
                ),
                style: GoogleFonts.outfit(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: isTv ? 90 : 76,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            itemCount: TmdbService.supportedPlatforms.length,
            itemBuilder: (context, index) {
              final platform = TmdbService.supportedPlatforms[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: TvFocusableCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProviderCatalogScreen(initialPlatform: platform),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  scaleFactor: 1.06,
                  child: Container(
                    width: isTv ? 160 : 130,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          platform.primaryColor.withValues(alpha: 0.35),
                          const Color(0xFF161616),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: platform.primaryColor.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: platform.primaryColor.withValues(alpha: 0.15),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              platform.iconEmoji,
                              style: TextStyle(fontSize: isTv ? 22 : 18),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: platform.primaryColor.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                platform.badgeText,
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          platform.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: isTv ? 14 : 12,
                            fontWeight: FontWeight.bold,
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
              final provider = item['provider'] ?? (subjectId.toString().startsWith('/') ? '4khdhub' : 'moviebox');
              final season = item['season'] ?? 0;
              final episode = item['episode'] ?? 0;
              final pos = item['positionMs'] ?? 0;
              final dur = item['durationMs'] ?? 1;

              final progress = (pos / dur).clamp(0.0, 1.0);
              final isShow = season > 0 || episode > 0;
              final isNextCue = item['isNextCue'] == true;
              final String subtitle = isShow 
                  ? (isNextCue 
                      ? "S$season:E$episode • ${AppLanguageService.tr(en: "Next", id: "Selanjutnya")}"
                      : "S$season:E$episode") 
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
                        builder: (context) => DetailScreen(
                          subjectId: subjectId,
                          provider: provider,
                          initialSeason: isShow ? season : null,
                          initialEpisode: isShow ? episode : null,
                          tmdbData: provider == 'tmdb' ? (item['tmdbData'] ?? item) : null,
                        ),
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
              final provider = item['provider'] ?? (subjectId.toString().startsWith('/') ? '4khdhub' : 'moviebox');
              final type = item['subjectType'];
              final isShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';

              return Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: TvFocusableCard(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(
                          subjectId: subjectId,
                          provider: provider,
                          tmdbData: provider == 'tmdb' ? (item['tmdbData'] ?? item) : null,
                        ),
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
                        if (provider == '4khdhub')
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.cyan.shade900.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 0.8),
                              ),
                              child: Text(
                                "4K UHD",
                                style: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold),
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

    if (AppContentFilterService.filterHindi.value) {
      filteredSubjects = AppContentFilterService.filterList(filteredSubjects);
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
                    final prov = subject['provider'] ?? 'moviebox';
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => DetailScreen(
                          subjectId: subjectId,
                          provider: prov,
                          tmdbData: prov == 'tmdb' ? subject : null,
                        ),
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


import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/moviebox_api_service.dart';
import '../services/fourkhdhub_service.dart';
import '../services/tmdb_service.dart';
import '../services/favorites_service.dart';
import '../services/app_language_service.dart';
import '../services/playback_progress_service.dart';
import '../services/tvmaze_service.dart';
import '../widgets/tv_focusable_card.dart';
import '../services/download_service.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final String subjectId;
  final String provider;
  final int? initialSeason;
  final int? initialEpisode;
  final Map<String, dynamic>? tmdbData;

  const DetailScreen({
    super.key,
    required this.subjectId,
    this.provider = 'moviebox',
    this.initialSeason,
    this.initialEpisode,
    this.tmdbData,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final MovieBoxApiService _api = MovieBoxApiService();
  final FourKHdHubService _fourkApi = FourKHdHubService();
  final TmdbService _tmdbApi = TmdbService();
  final DownloadService _downloadService = DownloadService.instance;
  
  late String _activeProvider;
  bool get _is4kHub => _activeProvider.toLowerCase() == '4khdhub';
  bool get _isTmdb => widget.provider.toLowerCase() == 'tmdb';

  bool _isResolvingSources = false;
  List<Map<String, dynamic>> _resolvedSources = [];
  bool _noStreamingSourcesFound = false;
  
  Map<String, dynamic>? _details;
  List<dynamic> _dubs = [];
  List<dynamic> _seasons = [];
  List<dynamic> _streams = [];
  
  String _selectedSubjectId = "";
  String _selectedAudioName = "Original";
  int _selectedSeasonNumber = 1;
  int _selectedEpisodeNumber = 1;
  int? _expandedEpisodeNumber;
  int _episodesCount = 0;
  
  bool _isLoadingDetails = true;
  String _errorMessage = "";
  bool _isFavorite = false;
  int _savedProgressMs = 0;
  Map<String, TvMazeEpisode> _tvMazeEpisodes = {};

  bool get _isTvShow {
    final type = _details?['subjectType'] ?? _details?['subject_type'];
    return type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';
  }

  @override
  void initState() {
    super.initState();
    _activeProvider = widget.provider;
    _selectedSubjectId = widget.subjectId;
    _loadDetails();
    _checkFavorite();
    _checkProgress();
  }

  void _checkProgress() async {
    final pos = await PlaybackProgressService.getProgress(
      widget.subjectId,
      _isTvShow ? _selectedSeasonNumber : 0,
      _isTvShow ? _selectedEpisodeNumber : 0,
    );
    if (mounted) {
      setState(() {
        _savedProgressMs = pos;
      });
    }
  }

  String _formatDurationMs(int ms) {
    final d = Duration(milliseconds: ms);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return "${hours}h ${minutes}m";
    }
    return "${minutes}m ${seconds}s";
  }

  void _checkFavorite() async {
    final fav = await FavoritesService.isFavorite(widget.subjectId);
    if (mounted) {
      setState(() {
        _isFavorite = fav;
      });
    }
  }

  void _toggleFavorite() async {
    if (_details == null) return;
    if (_isFavorite) {
      await FavoritesService.removeFavorite(widget.subjectId);
    } else {
      final favData = Map<String, dynamic>.from(_details!);
      favData['provider'] = widget.provider;
      favData['subjectId'] = widget.subjectId;
      if (_isTmdb) {
        favData['tmdbData'] = _details;
      }
      await FavoritesService.addFavorite(favData);
    }
    _checkFavorite();
  }

  String _formatDubLabel(dynamic dub) {
    if (dub is! Map) return "Original Audio";
    final lanName = (dub['lanName'] ?? dub['language'] ?? dub['title'] ?? 'Original').toString().trim();
    final lanCode = (dub['lanCode'] ?? '').toString().trim().toUpperCase();
    final isOriginal = dub['original'] == true || lanName.toLowerCase().contains('original');

    if (isOriginal) {
      if (!lanName.toLowerCase().contains('original')) {
        return lanCode.isNotEmpty ? "$lanName (Original · $lanCode)" : "$lanName (Original)";
      }
      return lanCode.isNotEmpty ? "$lanName ($lanCode)" : lanName;
    }
    
    if (!lanName.toLowerCase().contains('dub')) {
      return lanCode.isNotEmpty ? "$lanName Dub ($lanCode)" : "$lanName Dub";
    }
    return lanCode.isNotEmpty ? "$lanName ($lanCode)" : lanName;
  }

  void _loadDetails() async {
    setState(() {
      _isLoadingDetails = true;
      _errorMessage = "";
      _isResolvingSources = false;
      _noStreamingSourcesFound = false;
    });

    if (_isTmdb) {
      _loadTmdbDetails();
      return;
    }

    if (_is4kHub) {
      try {
        final detailsRes = await _fourkApi.getDetails(widget.subjectId);
        final isTvShow = detailsRes['subjectType'] == 2;
        final rawSeasons = detailsRes['seasons'] as List? ?? [];
        final List<Map<String, dynamic>> seasonsList = rawSeasons
            .map((s) => s is Map ? Map<String, dynamic>.from(s) : <String, dynamic>{})
            .where((m) => m.isNotEmpty)
            .toList();
        int initialEpisodesCount = 0;
        int targetSeason = widget.initialSeason ?? 1;
        int targetEpisode = widget.initialEpisode ?? 1;

        if (widget.initialSeason == null || widget.initialEpisode == null) {
          final recentPlay = await PlaybackProgressService.getRecentPlay(widget.subjectId);
          if (recentPlay != null) {
            final recSeason = recentPlay['season'] as int? ?? 1;
            final recEpisode = recentPlay['episode'] as int? ?? 1;
            if (recSeason > 0) targetSeason = recSeason;
            if (recEpisode > 0) targetEpisode = recEpisode;
          }
        }

        if (isTvShow && seasonsList.isNotEmpty) {
          dynamic matchingSeason;
          for (final s in seasonsList) {
            if (s is Map && (s['se'] ?? 1) == targetSeason) {
              matchingSeason = s;
              break;
            }
          }
          matchingSeason ??= seasonsList.first;
          _selectedSeasonNumber = (matchingSeason is Map ? matchingSeason['se'] : null) ?? 1;
          initialEpisodesCount = (matchingSeason is Map ? (matchingSeason['maxEp'] ?? 1) : 1) as int;
          _selectedEpisodeNumber = targetEpisode.clamp(1, initialEpisodesCount > 0 ? initialEpisodesCount : 1);
        }

        setState(() {
          _details = detailsRes;
          _dubs = [];
          _selectedAudioName = detailsRes['audios'] ?? "Original Audio";
          _selectedSubjectId = widget.subjectId;
          _seasons = seasonsList;
          _episodesCount = initialEpisodesCount;
          _isLoadingDetails = false;
        });

        _loadStreams();
      } catch (e) {
        setState(() {
          _errorMessage = "Gagal memuat detail 4KHDHub: $e";
          _isLoadingDetails = false;
        });
      }
      return;
    }

    try {
      final detailsRes = await _api.getDetails(subjectId: widget.subjectId);
      final type = detailsRes['subjectType'] ?? detailsRes['subject_type'];
      final isTvShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';
      
      // Extract dubs list (support both direct and nested subject['dubs'])
      List<dynamic> rawDubs = detailsRes['dubs'] ?? 
          (detailsRes['subject'] is Map ? detailsRes['subject']['dubs'] : null) ?? [];
      
      List<dynamic> dubsList = [];
      for (final d in rawDubs) {
        if (d is Map) {
          dubsList.add(Map<String, dynamic>.from(d));
        }
      }

      String selectedAudioName = "Original Audio";
      String selectedSubId = widget.subjectId;

      if (dubsList.isEmpty) {
        dubsList = [
          {"lanName": "Original Audio", "subjectId": widget.subjectId, "original": true}
        ];
      } else {
        // Ensure "Original" is in the list
        bool hasOriginal = dubsList.any((d) => 
            d['original'] == true || 
            (d['lanName'] ?? '').toString().toLowerCase().contains('original'));
            
        if (!hasOriginal) {
          dubsList = [
            {"lanName": "Original Audio", "subjectId": widget.subjectId, "original": true},
            ...dubsList
          ];
        }

        // Always prioritize Original Audio track first
        final selectedDub = dubsList.firstWhere(
          (d) => d['original'] == true || (d['lanName'] ?? '').toString().toLowerCase().contains('original'),
          orElse: () => dubsList.first,
        );
        selectedAudioName = _formatDubLabel(selectedDub);
        selectedSubId = selectedDub['subjectId']?.toString() ?? widget.subjectId;
      }

      List<dynamic> seasonsList = [];
      int initialEpisodesCount = 0;

      if (isTvShow) {
        try {
          final seasonsRes = await _api.getSeasonInfo(subjectId: widget.subjectId);
          seasonsList = seasonsRes['seasons'] ?? [];
        } catch (e) {
          print("Failed to load seasons info: $e");
        }

        // Fallback if seasons list is empty but it's a TV show
        if (seasonsList.isEmpty) {
          final totalEp = detailsRes['episode'] ?? detailsRes['maxEp'] ?? 1;
          seasonsList = [
            {"se": 1, "maxEp": totalEp}
          ];
        }

        // Determine target season and episode based on initial parameters or recent progress
        int targetSeason = 1;
        int targetEpisode = 1;

        if (widget.initialSeason != null && widget.initialEpisode != null) {
          targetSeason = widget.initialSeason!;
          targetEpisode = widget.initialEpisode!;
        } else {
          final recentPlay = await PlaybackProgressService.getRecentPlay(widget.subjectId);
          if (recentPlay != null) {
            final recSeason = recentPlay['season'] as int? ?? 1;
            final recEpisode = recentPlay['episode'] as int? ?? 1;
            if (recSeason > 0) targetSeason = recSeason;
            if (recEpisode > 0) targetEpisode = recEpisode;
          }
        }

        final matchingSeason = seasonsList.firstWhere(
          (s) => (s['se'] ?? 1) == targetSeason,
          orElse: () => seasonsList.first,
        );

        _selectedSeasonNumber = matchingSeason['se'] ?? 1;
        initialEpisodesCount = (matchingSeason['maxEp'] ?? 1) as int;
        _selectedEpisodeNumber = targetEpisode.clamp(1, initialEpisodesCount > 0 ? initialEpisodesCount : 1);
      }

      setState(() {
        _details = detailsRes;
        _dubs = dubsList;
        _selectedAudioName = selectedAudioName;
        _selectedSubjectId = selectedSubId;
        _seasons = seasonsList;
        _episodesCount = initialEpisodesCount;
        _isLoadingDetails = false;
      });

      if (_isTvShow) {
        final seriesTitle = (detailsRes['title'] ?? detailsRes['subjectTitle'] ?? detailsRes['name'] ?? '').toString();
        _fetchTvMazeEpisodes(seriesTitle);
      }

      // Load available streams for the initial selection
      _loadStreams();

    } catch (e) {
      setState(() {
        _errorMessage = e is RateLimitException 
            ? "Server membatasi request (Rate Limited). Silakan tekan Coba Lagi."
            : e is NetworkConnectionException 
                ? "Gagal terhubung ke jaringan. Periksa koneksi internet Anda."
                : "Gagal memuat detail: $e";
        _isLoadingDetails = false;
      });
    }
  }

  void _loadTmdbDetails() async {
    try {
      Map<String, dynamic>? initialMap = widget.tmdbData != null
          ? Map<String, dynamic>.from(widget.tmdbData!)
          : null;

      final rawIdStr = widget.subjectId.replaceFirst('tmdb_', '');
      final int tmdbId = int.tryParse(rawIdStr) ?? 0;

      final isTvInitial = initialMap?['subjectType'] == 2 ||
          initialMap?['media_type'] == 'tv' ||
          widget.initialSeason != null;

      if (tmdbId > 0 && (initialMap == null || (initialMap['description'] ?? '').isEmpty)) {
        final tmdbFull = isTvInitial
            ? await _tmdbApi.getTvDetails(tmdbId)
            : await _tmdbApi.getMovieDetails(tmdbId);
        if (tmdbFull != null) {
          initialMap = _tmdbApi.normalizeItem(tmdbFull, mediaType: isTvInitial ? 'tv' : 'movie');
        }
      }

      if (initialMap == null) {
        if (mounted) {
          setState(() {
            _errorMessage = "Gagal memuat detail TMDB";
            _isLoadingDetails = false;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _details = initialMap;
          _isLoadingDetails = false;
        });
      }

      await _resolveStreamingSources();
    } catch (e) {
      print("TMDB Details Error: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Gagal memuat detail TMDB: $e";
          _isLoadingDetails = false;
        });
      }
    }
  }

  Future<void> _resolveStreamingSources() async {
    if (!mounted) return;
    setState(() {
      _isResolvingSources = true;
      _noStreamingSourcesFound = false;
    });

    final title = (_details?['title'] ?? _details?['name'] ?? _details?['subjectTitle'] ?? '').toString().trim();
    if (title.isEmpty) {
      setState(() {
        _isResolvingSources = false;
        _noStreamingSourcesFound = true;
      });
      return;
    }

    final isTv = _isTvShow;

    try {
      final searchResults = await Future.wait([
        _api.search(query: title, subjectType: isTv ? 2 : 1, page: 1, perPage: 5).catchError((_) => <String, dynamic>{}),
        _fourkApi.search(title).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final mbRes = searchResults[0] as Map<String, dynamic>;
      final fkRes = searchResults[1] as List<Map<String, dynamic>>;

      final List<Map<String, dynamic>> foundSources = [];

      // 1. Check MovieBox (Primary Priority)
      final mbItems = (mbRes['items'] as List?) ??
          (mbRes['list'] as List?) ??
          ((mbRes['results'] as List?)?.firstOrNull?['subjects'] as List?) ??
          [];
      if (mbItems.isNotEmpty) {
        final bestMb = mbItems.first;
        final subId = (bestMb['subjectId'] ?? bestMb['id']).toString();
        foundSources.add({
          'provider': 'moviebox',
          'label': 'MovieBox (Multi-Audio)',
          'badge': 'Multi-Audio',
          'subjectId': subId,
          'item': bestMb,
        });
      }

      // 2. Check 4KHDHub (High-Resolution Alternate Option)
      if (fkRes.isNotEmpty) {
        final bestFk = fkRes.first;
        foundSources.add({
          'provider': '4khdhub',
          'label': '4KHDHub (4K / 1080p)',
          'badge': '4K UHD',
          'subjectId': bestFk['subjectId'],
          'item': bestFk,
        });
      }

      if (!mounted) return;

      if (foundSources.isEmpty) {
        setState(() {
          _isResolvingSources = false;
          _noStreamingSourcesFound = true;
        });
        return;
      }

      setState(() {
        _resolvedSources = foundSources;
        _isResolvingSources = false;
        _noStreamingSourcesFound = false;
      });

      // Prioritize MovieBox if available, otherwise 4KHDHub
      final defaultSource = foundSources.firstWhere(
        (s) => s['provider'] == 'moviebox',
        orElse: () => foundSources.first,
      );
      await _activateResolvedSource(defaultSource);
    } catch (e) {
      print("Resolve sources error: $e");
      if (mounted) {
        setState(() {
          _isResolvingSources = false;
          _noStreamingSourcesFound = true;
        });
      }
    }
  }

  Future<void> _activateResolvedSource(Map<String, dynamic> source) async {
    final prov = source['provider'] as String;
    final sId = source['subjectId'] as String;

    setState(() {
      _activeProvider = prov;
      _selectedSubjectId = sId;
      _streams = [];
    });

    if (prov == '4khdhub') {
      await _load4kHubProvider(sId);
    } else {
      await _loadMovieBoxProvider(sId);
    }
  }

  Future<void> _load4kHubProvider(String sId) async {
    try {
      final detailsRes = await _fourkApi.getDetails(sId);
      final isTvShow = detailsRes['subjectType'] == 2;
      List<dynamic> seasonsList = detailsRes['seasons'] ?? [];
      int initialEpisodesCount = 0;
      int targetSeason = widget.initialSeason ?? 1;
      int targetEpisode = widget.initialEpisode ?? 1;

      if (widget.initialSeason == null || widget.initialEpisode == null) {
        final recentPlay = await PlaybackProgressService.getRecentPlay(widget.subjectId);
        if (recentPlay != null) {
          final recSeason = recentPlay['season'] as int? ?? 1;
          final recEpisode = recentPlay['episode'] as int? ?? 1;
          if (recSeason > 0) targetSeason = recSeason;
          if (recEpisode > 0) targetEpisode = recEpisode;
        }
      }

      if (isTvShow && seasonsList.isNotEmpty) {
        dynamic matchingSeason;
        for (final s in seasonsList) {
          if (s is Map && (s['se'] ?? 1) == targetSeason) {
            matchingSeason = s;
            break;
          }
        }
        matchingSeason ??= seasonsList.first;
        _selectedSeasonNumber = (matchingSeason is Map ? matchingSeason['se'] : null) ?? 1;
        initialEpisodesCount = (matchingSeason is Map ? (matchingSeason['maxEp'] ?? 1) : 1) as int;
        _selectedEpisodeNumber = targetEpisode.clamp(1, initialEpisodesCount > 0 ? initialEpisodesCount : 1);
      }

      if (mounted) {
        setState(() {
          _details = {
            ...?_details,
            'rawHtml': detailsRes['rawHtml'],
            'audios': detailsRes['audios'],
          };
          _dubs = [];
          _selectedAudioName = detailsRes['audios'] ?? "Original Audio";
          _seasons = seasonsList;
          _episodesCount = initialEpisodesCount;
        });
      }

      _loadStreams();
    } catch (e) {
      print("Failed loading 4kHub resolved provider: $e");
    }
  }

  Future<void> _loadMovieBoxProvider(String sId) async {
    try {
      final detailsRes = await _api.getDetails(subjectId: sId);
      final type = detailsRes['subjectType'] ?? detailsRes['subject_type'];
      final isTvShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';

      List<dynamic> rawDubs = detailsRes['dubs'] ?? 
          (detailsRes['subject'] is Map ? detailsRes['subject']['dubs'] : null) ?? [];

      List<dynamic> dubsList = [];
      for (final d in rawDubs) {
        if (d is Map) {
          dubsList.add(Map<String, dynamic>.from(d));
        }
      }

      String selectedAudioName = "Original Audio";
      String selectedSubId = sId;

      if (dubsList.isEmpty) {
        dubsList = [
          {"lanName": "Original Audio", "subjectId": sId, "original": true}
        ];
      } else {
        bool hasOriginal = dubsList.any((d) => 
            d['original'] == true || 
            (d['lanName'] ?? '').toString().toLowerCase().contains('original'));
            
        if (!hasOriginal) {
          dubsList = [
            {"lanName": "Original Audio", "subjectId": sId, "original": true},
            ...dubsList
          ];
        }
        final defaultDub = dubsList.firstWhere(
          (d) => d['original'] == true || (d['lanName'] ?? '').toString().toLowerCase().contains('original'),
          orElse: () => dubsList.first,
        );
        selectedAudioName = (defaultDub['lanName'] ?? defaultDub['language'] ?? 'Original Audio').toString();
        selectedSubId = (defaultDub['subjectId'] ?? sId).toString();
      }

      List<dynamic> seasonsList = [];
      int initialEpisodesCount = 0;
      int targetSeason = widget.initialSeason ?? 1;
      int targetEpisode = widget.initialEpisode ?? 1;

      if (isTvShow) {
        try {
          final seasonInfoRes = await _api.getSeasonInfo(subjectId: sId);
          seasonsList = seasonInfoRes['seasons'] ?? [];
          
          if (widget.initialSeason == null || widget.initialEpisode == null) {
            final recentPlay = await PlaybackProgressService.getRecentPlay(widget.subjectId);
            if (recentPlay != null) {
              final recSeason = recentPlay['season'] as int? ?? 1;
              final recEpisode = recentPlay['episode'] as int? ?? 1;
              if (recSeason > 0) targetSeason = recSeason;
              if (recEpisode > 0) targetEpisode = recEpisode;
            }
          }

          if (seasonsList.isNotEmpty) {
            dynamic matchingSeason;
            for (final s in seasonsList) {
              if (s is Map && (s['se'] ?? 1) == targetSeason) {
                matchingSeason = s;
                break;
              }
            }
            matchingSeason ??= seasonsList.first;
            _selectedSeasonNumber = (matchingSeason is Map ? matchingSeason['se'] : null) ?? 1;
            initialEpisodesCount = (matchingSeason is Map ? (matchingSeason['maxEp'] ?? 1) : 1) as int;
            _selectedEpisodeNumber = targetEpisode.clamp(1, initialEpisodesCount > 0 ? initialEpisodesCount : 1);
          }
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _details = {
            ...?_details,
            'dubs': dubsList,
          };
          _dubs = dubsList;
          _selectedAudioName = selectedAudioName;
          _selectedSubjectId = selectedSubId;
          _seasons = seasonsList;
          _episodesCount = initialEpisodesCount;
        });
      }

      _loadStreams();
    } catch (e) {
      print("Failed loading MovieBox resolved provider: $e");
    }
  }

  void _showUnavailableDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.movie_filter_rounded, color: Colors.amberAccent, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLanguageService.tr(en: "Streaming Unavailable", id: "Belum Tersedia di Streaming"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          AppLanguageService.tr(
            en: "This title is currently exclusive to cinema theaters and has not been uploaded to streaming servers yet. Please check back soon!",
            id: "Film ini masih tayang eksklusif di bioskop dan belum tersedia di server streaming (MovieBox / 4KHDHub). Silakan periksa kembali setelah rilis digital tersedia!",
          ),
          style: GoogleFonts.outfit(color: Colors.grey.shade300, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLanguageService.tr(en: "Understood", id: "Mengerti"), style: GoogleFonts.outfit(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  void _fetchTvMazeEpisodes(String title) async {
    if (title.trim().isEmpty) return;
    try {
      final epMap = await TvMazeService.instance.getEpisodesMap(title);
      if (mounted && epMap.isNotEmpty) {
        setState(() {
          _tvMazeEpisodes = epMap;
        });
      }
    } catch (_) {}
  }

  void _loadStreams() async {
    setState(() {
      _streams = [];
    });

    if (_is4kHub) {
      try {
        final targetId = _isTmdb ? _selectedSubjectId : widget.subjectId;
        final releases = await _fourkApi.getReleases(
          targetId,
          rawHtml: _details?['rawHtml'],
          season: _isTvShow ? _selectedSeasonNumber : 0,
          episode: _isTvShow ? _selectedEpisodeNumber : 0,
        );

        setState(() {
          _streams = releases;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Gagal memuat rilis 4KHDHub: $e")),
          );
        }
      }
      return;
    }

    try {
      final isTvShow = _isTvShow;
      final seNum = isTvShow ? _selectedSeasonNumber : 0;
      final epNum = isTvShow ? _selectedEpisodeNumber : 0;

      // Target resolutions to fetch with concurrency control (batch 2 requests at a time to prevent HTTP 429)
      final List<int> targetResolutions = [1080, 720, 480, 360];
      final List<dynamic> combinedList = [];

      for (int i = 0; i < targetResolutions.length; i += 2) {
        final batch = targetResolutions.sublist(
          i, 
          i + 2 > targetResolutions.length ? targetResolutions.length : i + 2,
        );

        final batchResults = await Future.wait(batch.map((res) {
          return _api.getResources(
            subjectId: _selectedSubjectId,
            se: seNum,
            ep: epNum,
            resolution: res,
          ).catchError((e) {
            print("Failed fetching resolution $res: $e");
            return <String, dynamic>{};
          });
        }));

        for (final resData in batchResults) {
          final List<dynamic> fileList = resData['list'] ?? [];
          combinedList.addAll(fileList);
        }
      }

      // Filter by season and episode on the client side if it is a TV show
      List<dynamic> filteredList = combinedList;
      if (isTvShow) {
        filteredList = combinedList.where((item) {
          final itemSe = int.tryParse(item['se']?.toString() ?? '') ?? 0;
          final itemEp = int.tryParse(item['ep']?.toString() ?? '') ?? 0;
          return itemSe == _selectedSeasonNumber && itemEp == _selectedEpisodeNumber;
        }).toList();
      }

      // Deduplicate streams by unique key (resourceId/link + resolution + codec)
      final Map<String, dynamic> uniqueStreams = {};
      for (final item in filteredList) {
        final id = item['resourceId']?.toString() ?? item['resource_id']?.toString() ?? '';
        final res = item['resolution']?.toString() ?? '';
        final codec = item['codecName']?.toString() ?? item['codec_name']?.toString() ?? '';
        final link = item['resourceLink']?.toString() ?? item['resource_link']?.toString() ?? '';
        final key = id.isNotEmpty ? "${id}_${res}_$codec" : "${link}_${res}_$codec";
        uniqueStreams[key] = item;
      }
      final List<dynamic> finalStreams = uniqueStreams.values.toList();

      // Sort streams: Prioritize H.264/AVC, then descending by resolution, then descending by size
      finalStreams.sort((a, b) {
        final codecA = (a['codecName'] ?? a['codec_name'] ?? "").toString().toLowerCase();
        final codecB = (b['codecName'] ?? b['codec_name'] ?? "").toString().toLowerCase();
        
        final isHevcA = codecA.contains('hevc') || codecA.contains('h265') || codecA.contains('h.265');
        final isHevcB = codecB.contains('hevc') || codecB.contains('h265') || codecB.contains('h.265');
        
        // Prioritize non-HEVC (e.g. H264)
        if (isHevcA && !isHevcB) return 1;
        if (!isHevcA && isHevcB) return -1;

        final resComp = (b['resolution'] ?? 0).compareTo(a['resolution'] ?? 0);
        if (resComp != 0) return resComp;
        
        final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
        final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;
        return sizeB.compareTo(sizeA);
      });

      setState(() {
        _streams = finalStreams;
      });
    } catch (e) {
      if (mounted) {
        final msg = e is RateLimitException 
            ? "Batas request server tercapai. Silakan tunggu sebentar."
            : "Gagal memuat stream: $e";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    }
  }

  Future<PlayerSwitchAudioResult?> _handleSwitchAudioInPlayer(dynamic dub) async {
    final subId = dub['subjectId']?.toString() ?? widget.subjectId;
    final dubLabel = _formatDubLabel(dub);

    try {
      final isTvShow = _isTvShow;
      final seNum = isTvShow ? _selectedSeasonNumber : 0;
      final epNum = isTvShow ? _selectedEpisodeNumber : 0;

      final List<int> targetResolutions = [1080, 720, 480, 360];
      final List<dynamic> combinedList = [];

      for (int i = 0; i < targetResolutions.length; i += 2) {
        final batch = targetResolutions.sublist(
          i,
          i + 2 > targetResolutions.length ? targetResolutions.length : i + 2,
        );

        final batchResults = await Future.wait(batch.map((res) {
          return _api.getResources(
            subjectId: subId,
            se: seNum,
            ep: epNum,
            resolution: res,
          ).catchError((e) => <String, dynamic>{});
        }));

        for (final resData in batchResults) {
          final List<dynamic> fileList = resData['list'] ?? [];
          combinedList.addAll(fileList);
        }
      }

      List<dynamic> filteredList = combinedList;
      if (isTvShow) {
        filteredList = combinedList.where((item) {
          final itemSe = int.tryParse(item['se']?.toString() ?? '') ?? 0;
          final itemEp = int.tryParse(item['ep']?.toString() ?? '') ?? 0;
          return itemSe == _selectedSeasonNumber && itemEp == _selectedEpisodeNumber;
        }).toList();
      }

      final Map<String, dynamic> uniqueStreams = {};
      for (final item in filteredList) {
        final id = item['resourceId']?.toString() ?? item['resource_id']?.toString() ?? '';
        final res = item['resolution']?.toString() ?? '';
        final codec = item['codecName']?.toString() ?? item['codec_name']?.toString() ?? '';
        final link = item['resourceLink']?.toString() ?? item['resource_link']?.toString() ?? '';
        final key = id.isNotEmpty ? "${id}_${res}_$codec" : "${link}_${res}_$codec";
        uniqueStreams[key] = item;
      }
      final List<dynamic> finalStreams = uniqueStreams.values.toList();

      finalStreams.sort((a, b) {
        final resA = (a['resolution'] is num) ? (a['resolution'] as num).toInt() : (int.tryParse(a['resolution']?.toString() ?? '0') ?? 0);
        final resB = (b['resolution'] is num) ? (b['resolution'] as num).toInt() : (int.tryParse(b['resolution']?.toString() ?? '0') ?? 0);
        final resComp = resB.compareTo(resA);
        if (resComp != 0) return resComp;

        final codecA = (a['codecName'] ?? a['codec_name'] ?? "").toString().toLowerCase();
        final codecB = (b['codecName'] ?? b['codec_name'] ?? "").toString().toLowerCase();
        final isHevcA = codecA.contains('hevc') || codecA.contains('h265') || codecA.contains('h.265');
        final isHevcB = codecB.contains('hevc') || codecB.contains('h265') || codecB.contains('h.265');
        if (isHevcA && !isHevcB) return -1;
        if (!isHevcA && isHevcB) return 1;

        final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
        final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;
        return sizeB.compareTo(sizeA);
      });

      if (finalStreams.isEmpty) return null;

      final bestStream = finalStreams.first;
      final String streamUrl = bestStream['resourceLink'] ?? bestStream['resource_link'] ?? '';
      final String resourceId = bestStream['resourceId']?.toString() ?? bestStream['resource_id']?.toString() ?? '';
      if (streamUrl.isEmpty) return null;

      final List<String> siblingIds = [widget.subjectId];
      for (final d in _dubs) {
        final sId = d['subjectId']?.toString() ?? '';
        if (sId.isNotEmpty && !siblingIds.contains(sId)) {
          siblingIds.add(sId);
        }
      }

      List<dynamic> captions = [];
      if (resourceId.isNotEmpty) {
        try {
          captions = await _api.getCleanExtCaptions(
            subjectId: subId,
            resourceId: resourceId,
            siblingSubjectIds: siblingIds,
            se: seNum,
            ep: epNum,
          );
        } catch (e) {
          print("Failed loading captions for new audio: $e");
        }
      }

      if (mounted) {
        setState(() {
          _selectedAudioName = dubLabel;
          _selectedSubjectId = subId;
          _streams = finalStreams;
        });
      }

      return PlayerSwitchAudioResult(
        streamUrl: streamUrl,
        audioName: dubLabel,
        captions: captions,
        availableStreams: finalStreams,
        currentStream: bestStream,
      );
    } catch (e) {
      print("Error switching audio in player: $e");
      return null;
    }
  }

  Future<String?> _handleSwitchQualityInPlayer(Map<String, dynamic> stream) async {
    if (_is4kHub) {
      try {
        final resolvedUrl = await _fourkApi.resolveReleaseStream(stream);
        return resolvedUrl;
      } catch (e) {
        print("Error resolving 4KHDHub stream quality: $e");
        return null;
      }
    } else {
      final url = stream['resourceLink'] ?? stream['resource_link'];
      return url?.toString();
    }
  }

  Future<PlayerNextEpisodeData?> _handleSelectEpisodeInPlayer(int season, int episode) async {
    if (_is4kHub) {
      try {
        final targetId = _isTmdb ? _selectedSubjectId : widget.subjectId;
        final releases = await _fourkApi.getReleases(
          targetId,
          rawHtml: _details?['rawHtml'],
          season: season,
          episode: episode,
        );
        if (releases.isEmpty) return null;

        final bestRelease = releases.first;
        final streamUrl = await _fourkApi.resolveReleaseStream(bestRelease);
        if (streamUrl == null || streamUrl.isEmpty) return null;

        int nextNextSeason = season;
        int nextNextEpisode = episode + 1;
        bool hasNextNext = false;
        int maxEpOfSeason = 0;
        for (final s in _seasons) {
          if ((s['se'] ?? 0) == season) {
            maxEpOfSeason = (s['maxEp'] ?? 0) as int;
            break;
          }
        }

        if (nextNextEpisode <= maxEpOfSeason) {
          hasNextNext = true;
        } else {
          final followingSeason = _seasons.any((s) => (s['se'] ?? 0) == season + 1);
          if (followingSeason) {
            nextNextSeason = season + 1;
            nextNextEpisode = 1;
            hasNextNext = true;
          }
        }

        if (mounted) {
          setState(() {
            _selectedSeasonNumber = season;
            _selectedEpisodeNumber = episode;
            _streams = releases;
            if (maxEpOfSeason > 0) _episodesCount = maxEpOfSeason;
          });
        }

        return PlayerNextEpisodeData(
          streamUrl: streamUrl,
          title: _details?['title'] ?? _details?['subjectTitle'] ?? "Play Video",
          season: season,
          episode: episode,
          captions: const [],
          hasNextEpisode: hasNextNext,
          nextEpisodeLabel: hasNextNext ? "S$nextNextSeason:E$nextNextEpisode" : null,
          availableStreams: releases,
          currentStream: bestRelease,
          currentAudioName: _selectedAudioName,
        );
      } catch (e) {
        print("Error selecting episode in 4khdhub player: $e");
        return null;
      }
    }

    try {
      final List<int> targetResolutions = [1080, 720, 480, 360];
      final List<dynamic> combinedList = [];

      for (int i = 0; i < targetResolutions.length; i += 2) {
        final batch = targetResolutions.sublist(
          i,
          i + 2 > targetResolutions.length ? targetResolutions.length : i + 2,
        );

        final batchResults = await Future.wait(batch.map((res) {
          return _api.getResources(
            subjectId: _selectedSubjectId,
            se: season,
            ep: episode,
            resolution: res,
          ).catchError((e) => <String, dynamic>{});
        }));

        for (final resData in batchResults) {
          final List<dynamic> fileList = resData['list'] ?? [];
          combinedList.addAll(fileList);
        }
      }

      final filteredList = combinedList.where((item) {
        final itemSe = int.tryParse(item['se']?.toString() ?? '') ?? 0;
        final itemEp = int.tryParse(item['ep']?.toString() ?? '') ?? 0;
        return itemSe == season && itemEp == episode;
      }).toList();

      if (filteredList.isEmpty) return null;

      filteredList.sort((a, b) {
        final resA = (a['resolution'] is num) ? (a['resolution'] as num).toInt() : (int.tryParse(a['resolution']?.toString() ?? '0') ?? 0);
        final resB = (b['resolution'] is num) ? (b['resolution'] as num).toInt() : (int.tryParse(b['resolution']?.toString() ?? '0') ?? 0);
        final resComp = resB.compareTo(resA);
        if (resComp != 0) return resComp;

        final codecA = (a['codecName'] ?? a['codec_name'] ?? "").toString().toLowerCase();
        final codecB = (b['codecName'] ?? b['codec_name'] ?? "").toString().toLowerCase();
        final isHevcA = codecA.contains('hevc') || codecA.contains('h265') || codecA.contains('h.265');
        final isHevcB = codecB.contains('hevc') || codecB.contains('h265') || codecB.contains('h.265');
        if (isHevcA && !isHevcB) return -1;
        if (!isHevcA && isHevcB) return 1;

        final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
        final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;
        return sizeB.compareTo(sizeA);
      });

      final bestStream = filteredList.first;
      final String nextStreamUrl = bestStream['resourceLink'] ?? bestStream['resource_link'] ?? '';
      final String nextResourceId = bestStream['resourceId']?.toString() ?? bestStream['resource_id']?.toString() ?? '';
      if (nextStreamUrl.isEmpty) return null;

      final List<String> siblingIds = [widget.subjectId];
      for (final d in _dubs) {
        final sId = d['subjectId']?.toString() ?? '';
        if (sId.isNotEmpty && !siblingIds.contains(sId)) {
          siblingIds.add(sId);
        }
      }

      List<dynamic> nextCaptions = [];
      if (nextResourceId.isNotEmpty) {
        try {
          nextCaptions = await _api.getCleanExtCaptions(
            subjectId: _selectedSubjectId,
            resourceId: nextResourceId,
            siblingSubjectIds: siblingIds,
            se: season,
            ep: episode,
          );
        } catch (e) {
          print("Failed loading episode captions: $e");
        }
      }

      int nextNextSeason = season;
      int nextNextEpisode = episode + 1;
      bool hasNextNext = false;
      int maxEpOfSeason = 0;
      for (final s in _seasons) {
        if ((s['se'] ?? 0) == season) {
          maxEpOfSeason = (s['maxEp'] ?? 0) as int;
          break;
        }
      }

      if (nextNextEpisode <= maxEpOfSeason) {
        hasNextNext = true;
      } else {
        final followingSeason = _seasons.any((s) => (s['se'] ?? 0) == season + 1);
        if (followingSeason) {
          nextNextSeason = season + 1;
          nextNextEpisode = 1;
          hasNextNext = true;
        }
      }

      if (mounted) {
        setState(() {
          _selectedSeasonNumber = season;
          _selectedEpisodeNumber = episode;
          _streams = filteredList;
          if (maxEpOfSeason > 0) _episodesCount = maxEpOfSeason;
        });
      }

      return PlayerNextEpisodeData(
        streamUrl: nextStreamUrl,
        title: _details?['title'] ?? _details?['subjectTitle'] ?? "Play Video",
        season: season,
        episode: episode,
        captions: nextCaptions,
        hasNextEpisode: hasNextNext,
        nextEpisodeLabel: hasNextNext ? "S$nextNextSeason:E$nextNextEpisode" : null,
        availableStreams: filteredList,
        currentStream: bestStream,
        currentAudioName: _selectedAudioName,
      );
    } catch (e) {
      print("Error selecting episode in player: $e");
      return null;
    }
  }

  Future<PlayerNextEpisodeData?> _fetchNextEpisodeStream(int nextSeason, int nextEpisode) async {
    return _handleSelectEpisodeInPlayer(nextSeason, nextEpisode);
  }

  void _playEpisode(int seasonNum, int episodeNum) async {
    if (_noStreamingSourcesFound) {
      _showUnavailableDialog();
      return;
    }

    final isTv = _isTvShow;
    final targetSeason = isTv ? seasonNum : 0;
    final targetEpisode = isTv ? episodeNum : 0;

    setState(() {
      _selectedSeasonNumber = seasonNum;
      _selectedEpisodeNumber = episodeNum;
    });
    _checkProgress();

    // If streams are already loaded for this target episode or movie, play directly or show quality dialog
    if (_streams.isNotEmpty) {
      final firstStream = _streams.first;
      final stSe = int.tryParse(firstStream['se']?.toString() ?? '') ?? 0;
      final stEp = int.tryParse(firstStream['ep']?.toString() ?? '') ?? 0;
      if (!isTv || (stSe == seasonNum && stEp == episodeNum)) {
        if (_is4kHub) {
          _show4kQualitySelectionDialog(_streams);
          return;
        }
        _playStream(firstStream);
        return;
      }
    }

    if (_is4kHub) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          content: Row(
            children: [
              const SpinKitRing(color: Colors.cyanAccent, size: 36.0),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  AppLanguageService.tr(
                    en: "Loading 4KHDHub releases...",
                    id: "Memuat daftar rilis 4KHDHub...",
                  ),
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );

      try {
        final targetId = _isTmdb ? _selectedSubjectId : widget.subjectId;
        final releases = await _fourkApi.getReleases(
          targetId,
          rawHtml: _details?['rawHtml'],
          season: targetSeason,
          episode: targetEpisode,
        );
        if (mounted) Navigator.pop(context);

        if (releases.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLanguageService.tr(
                  en: "No releases available for this episode.",
                  id: "Tidak ada rilis tersedia untuk episode ini.",
                )),
              ),
            );
          }
          return;
        }

        if (mounted) {
          setState(() {
            _streams = releases;
          });
          _show4kQualitySelectionDialog(releases);
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Gagal memuat rilis 4KHDHub: $e")),
          );
        }
      }
      return;
    }

    // MovieBox:
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: SpinKitRing(color: Colors.redAccent, size: 48.0),
      ),
    );

    try {
      final List<int> targetResolutions = [1080, 720, 480, 360];
      final List<dynamic> combinedList = [];

      for (int i = 0; i < targetResolutions.length; i += 2) {
        final batch = targetResolutions.sublist(
          i,
          i + 2 > targetResolutions.length ? targetResolutions.length : i + 2,
        );

        final batchResults = await Future.wait(batch.map((res) {
          return _api.getResources(
            subjectId: _selectedSubjectId,
            se: targetSeason,
            ep: targetEpisode,
            resolution: res,
          ).catchError((e) => <String, dynamic>{});
        }));

        for (final resData in batchResults) {
          final List<dynamic> fileList = resData['list'] ?? [];
          combinedList.addAll(fileList);
        }
      }

      List<dynamic> filteredList = combinedList;
      if (isTv) {
        filteredList = combinedList.where((item) {
          final itemSe = int.tryParse(item['se']?.toString() ?? '') ?? 0;
          final itemEp = int.tryParse(item['ep']?.toString() ?? '') ?? 0;
          return itemSe == seasonNum && itemEp == episodeNum;
        }).toList();
      }

      final Map<String, dynamic> uniqueStreams = {};
      for (final item in filteredList) {
        if (item is! Map) continue;
        final res = (item['resolution'] is num)
            ? (item['resolution'] as num).toInt()
            : (int.tryParse(item['resolution']?.toString() ?? '0') ?? 0);
        final format = (item['format'] ?? '').toString().toUpperCase();
        final isDash = format == 'DASH';

        final key = res > 0 ? "res_$res" : (item['resourceLink'] ?? item['url'] ?? item['resourceId'] ?? item.hashCode).toString();
        if (!uniqueStreams.containsKey(key)) {
          uniqueStreams[key] = item;
        } else {
          final existing = uniqueStreams[key]!;
          final existingIsDash = (existing['format'] ?? '').toString().toUpperCase() == 'DASH';
          if (!existingIsDash && isDash) {
            uniqueStreams[key] = item;
          } else {
            final existingSize = int.tryParse(existing['size']?.toString() ?? '0') ?? 0;
            final itemSize = int.tryParse(item['size']?.toString() ?? '0') ?? 0;
            if (itemSize > existingSize) {
              uniqueStreams[key] = item;
            }
          }
        }
      }
      final List<dynamic> finalStreams = uniqueStreams.values.toList();
      finalStreams.sort((a, b) {
        final resA = (a['resolution'] is num) ? (a['resolution'] as num).toInt() : (int.tryParse(a['resolution']?.toString() ?? '0') ?? 0);
        final resB = (b['resolution'] is num) ? (b['resolution'] as num).toInt() : (int.tryParse(b['resolution']?.toString() ?? '0') ?? 0);
        final resComp = resB.compareTo(resA);
        if (resComp != 0) return resComp;

        final codecA = (a['codecName'] ?? a['codec_name'] ?? "").toString().toLowerCase();
        final codecB = (b['codecName'] ?? b['codec_name'] ?? "").toString().toLowerCase();
        final isHevcA = codecA.contains('hevc') || codecA.contains('h265') || codecA.contains('h.265');
        final isHevcB = codecB.contains('hevc') || codecB.contains('h265') || codecB.contains('h.265');
        if (isHevcA && !isHevcB) return -1;
        if (!isHevcA && isHevcB) return 1;

        final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
        final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;
        return sizeB.compareTo(sizeA);
      });

      if (mounted) Navigator.pop(context);

      if (finalStreams.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Tidak ada stream tersedia untuk pilihan ini.")),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _streams = finalStreams;
        });
        _playStream(finalStreams.first);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal memuat stream: $e")),
        );
      }
    }
  }

  void _open4kQualitySelector() async {
    if (_streams.isNotEmpty) {
      _show4kQualitySelectionDialog(_streams);
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        content: Row(
          children: [
            const SpinKitRing(color: Colors.cyanAccent, size: 36.0),
            const SizedBox(width: 20),
            Expanded(
              child: Text(
                AppLanguageService.tr(
                  en: "Loading 4KHDHub releases...",
                  id: "Memuat daftar rilis 4KHDHub...",
                ),
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final targetId = _isTmdb ? _selectedSubjectId : widget.subjectId;
      final releases = await _fourkApi.getReleases(
        targetId,
        rawHtml: _details?['rawHtml'],
        season: _isTvShow ? _selectedSeasonNumber : 0,
        episode: _isTvShow ? _selectedEpisodeNumber : 0,
      );
      if (mounted) Navigator.pop(context);

      if (releases.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLanguageService.tr(
                en: "No releases found for this title.",
                id: "Tidak ada rilis ditemukan untuk judul ini.",
              )),
            ),
          );
        }
        return;
      }

      if (mounted) {
        setState(() {
          _streams = releases;
        });
        _show4kQualitySelectionDialog(releases);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Gagal memuat rilis 4KHDHub: $e")),
        );
      }
    }
  }

  Future<void> _show4kQualitySelectionDialog(List<dynamic> releases) async {
    if (!mounted || releases.isEmpty) return;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;
        final isTv = screenWidth > 800;

        return Dialog(
          backgroundColor: const Color(0xFF141414),
          insetPadding: EdgeInsets.symmetric(
            horizontal: isTv ? screenWidth * 0.22 : 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3), width: 1.2),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560, maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dialog Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.cyan.shade900.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.hd_rounded, color: Colors.cyanAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLanguageService.tr(
                                en: "Select Video Quality & Release",
                                id: "Pilih Kualitas & Rilis Video",
                              ),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              AppLanguageService.tr(
                                en: "Choose resolution according to your internet speed & device",
                                id: "Pilih resolusi & ukuran sesuai kecepatan internet Anda",
                              ),
                              style: GoogleFonts.outfit(
                                color: Colors.grey.shade400,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Color(0xFF282828), height: 1),
                  const SizedBox(height: 12),

                  // Releases List
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const BouncingScrollPhysics(),
                      itemCount: releases.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final rel = releases[index];
                        final quality = rel['quality']?.toString() ?? "HD";
                        final res = rel['resolution'] as int? ?? 1080;
                        final size = rel['size']?.toString() ?? "";
                        final codec = rel['codecName']?.toString() ?? "";
                        final filename = rel['filename']?.toString() ?? "";

                        final bool is4k = res >= 2160;
                        final bool is1080 = res == 1080;

                        final Color badgeColor = is4k
                            ? Colors.cyanAccent
                            : is1080
                                ? Colors.amberAccent
                                : Colors.greenAccent;
                        final Color badgeBg = is4k
                            ? Colors.cyan.shade900.withValues(alpha: 0.3)
                            : is1080
                                ? Colors.amber.shade900.withValues(alpha: 0.3)
                                : Colors.green.shade900.withValues(alpha: 0.3);

                        // Recommended label for reasonable sizes (e.g. 1080p or lightweight 4K)
                        final bool isRecommended = is1080 || (is4k && size.contains("GB") && (double.tryParse(size.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0) < 10);

                        return TvFocusableCard(
                          onTap: () {
                            Navigator.pop(dialogContext);
                            _playStream(rel);
                          },
                          borderRadius: BorderRadius.circular(12),
                          scaleFactor: 1.02,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1C1C1C),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isRecommended
                                    ? Colors.cyanAccent.withValues(alpha: 0.4)
                                    : const Color(0xFF2C2C2C),
                                width: isRecommended ? 1.4 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                // Quality Indicator
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: badgeBg,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                                  ),
                                  child: Text(
                                    is4k ? "4K UHD" : is1080 ? "1080p" : "720p",
                                    style: GoogleFonts.outfit(
                                      color: badgeColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Wrap(
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Text(
                                            quality,
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (isRecommended)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.teal.shade900.withValues(alpha: 0.7),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5), width: 0.8),
                                              ),
                                              child: Text(
                                                AppLanguageService.tr(en: "Recommended", id: "Direkomendasikan"),
                                                style: GoogleFonts.outfit(
                                                  color: Colors.tealAccent,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          if (size.isNotEmpty) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF282828),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.sd_storage_outlined, size: 11, color: Colors.grey),
                                                  const SizedBox(width: 3),
                                                  Text(
                                                    size,
                                                    style: GoogleFonts.outfit(
                                                      color: Colors.grey.shade300,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          if (codec.isNotEmpty) ...[
                                            Text(
                                              codec,
                                              style: GoogleFonts.outfit(
                                                color: Colors.grey.shade400,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      if (filename.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          filename,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            color: Colors.grey.shade600,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.play_circle_fill_rounded, color: Colors.cyanAccent, size: 28),
                              ],
                            ),
                          ),
                        );
                      },
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

  void _playStream(Map<String, dynamic> stream) async {
    if (_is4kHub) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          content: Row(
            children: [
              const SpinKitRing(color: Colors.cyanAccent, size: 36.0),
              const SizedBox(width: 20),
              Expanded(
                child: Text(
                  AppLanguageService.tr(
                    en: "Resolving 4KHDHub CDN mirror...",
                    id: "Menghubungkan ke mirror 4KHDHub...",
                  ),
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );

      String? streamUrl;
      try {
        streamUrl = await _fourkApi.resolveReleaseStream(stream);
      } catch (e) {
        print("Error resolving stream: $e");
      }

      if (mounted) {
        Navigator.pop(context);
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLanguageService.tr(
                en: "Mirror is dead or expired. Please try another quality/release.",
                id: "Mirror tidak aktif / kadaluarsa. Silakan pilih rilis/kualitas lain.",
              )),
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: AppLanguageService.tr(en: "Choose Quality", id: "Pilih Kualitas"),
                textColor: Colors.cyanAccent,
                onPressed: () {
                  if (_streams.isNotEmpty) {
                    _show4kQualitySelectionDialog(_streams);
                  } else {
                    _open4kQualitySelector();
                  }
                },
              ),
            ),
          );

          // Re-open quality selector dialog so user can immediately pick an alternate release
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              if (_streams.isNotEmpty) {
                _show4kQualitySelectionDialog(_streams);
              } else {
                _open4kQualitySelector();
              }
            }
          });
        }
        return;
      }

      int nextSeason = _selectedSeasonNumber;
      int nextEpisode = _selectedEpisodeNumber + 1;
      bool hasNext = false;
      if (_isTvShow) {
        if (nextEpisode <= _episodesCount) {
          hasNext = true;
        } else {
          final nextSeasonIndex = _seasons.indexWhere((s) => (s['se'] ?? 0) == _selectedSeasonNumber + 1);
          if (nextSeasonIndex != -1) {
            nextSeason = _selectedSeasonNumber + 1;
            nextEpisode = 1;
            hasNext = true;
          }
        }
      }

      final resolvedUrl = streamUrl;
      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              streamUrl: resolvedUrl,
              title: _details?['title'] ?? _details?['subjectTitle'] ?? "Play Video",
              subjectId: widget.subjectId,
              provider: widget.provider,
              season: _isTvShow ? _selectedSeasonNumber : 0,
              episode: _isTvShow ? _selectedEpisodeNumber : 0,
              captions: const [],
              coverUrl: _details?['cover']?['url'] ?? _details?['coverUrl'] ?? "",
              subjectType: _details?['subjectType'] ?? _details?['subject_type'] ?? 1,
              maxEpisodesInSeason: _episodesCount,
              hasNextEpisode: hasNext,
              nextEpisodeLabel: hasNext ? "S$nextSeason:E$nextEpisode" : null,
              onFetchNextEpisode: hasNext ? () => _fetchNextEpisodeStream(nextSeason, nextEpisode) : null,
              dubs: _dubs,
              currentAudioName: _selectedAudioName,
              availableStreams: _streams,
              currentStream: stream,
              seasons: _seasons,
              onSwitchAudio: _handleSwitchAudioInPlayer,
              onSwitchQuality: _handleSwitchQualityInPlayer,
              onSelectEpisode: _handleSelectEpisodeInPlayer,
            ),
          ),
        );

        if (mounted) {
          if (result is Map) {
            if (result['season'] != null && result['episode'] != null) {
              final s = result['season'] as int;
              final e = result['episode'] as int;
              if (s > 0 && e > 0 && (s != _selectedSeasonNumber || e != _selectedEpisodeNumber)) {
                setState(() {
                  _selectedSeasonNumber = s;
                  _selectedEpisodeNumber = e;
                });
              }
            }
            if (result['completed'] == true && _isTvShow && hasNext) {
              setState(() {
                _selectedSeasonNumber = nextSeason;
                _selectedEpisodeNumber = nextEpisode;
              });
            }
          }
          _loadStreams();
        }
      }
      return;
    }

    final String streamUrl = stream['resourceLink'] ?? stream['resource_link'] ?? "";
    final String resourceId = stream['resourceId']?.toString() ?? stream['resource_id']?.toString() ?? "";

    if (streamUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream URL is empty.')),
      );
      return;
    }

    // Show loading spinner while fetching subtitles
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: SpinKitRing(color: Colors.redAccent, size: 50.0),
      ),
    );

    // Collect all sibling subject IDs for cross-dub subtitle resolution
    final List<String> siblingIds = [widget.subjectId];
    for (final d in _dubs) {
      final sId = d['subjectId']?.toString() ?? '';
      if (sId.isNotEmpty && !siblingIds.contains(sId)) {
        siblingIds.add(sId);
      }
    }

    List<dynamic> captions = [];
    try {
      if (resourceId.isNotEmpty) {
        captions = await _api.getCleanExtCaptions(
          subjectId: _selectedSubjectId,
          resourceId: resourceId,
          siblingSubjectIds: siblingIds,
          se: _isTvShow ? _selectedSeasonNumber : 0,
          ep: _isTvShow ? _selectedEpisodeNumber : 0,
        );
      }
    } catch (e) {
      print("Failed to load subtitles: $e");
    }

    // Dismiss spinner
    if (mounted) {
      Navigator.pop(context);
    }

    // Compute next episode availability
    int nextSeason = _selectedSeasonNumber;
    int nextEpisode = _selectedEpisodeNumber + 1;
    bool hasNext = false;

    if (_isTvShow) {
      if (nextEpisode <= _episodesCount) {
        hasNext = true;
      } else {
        final nextSeasonIndex = _seasons.indexWhere((s) => (s['se'] ?? 0) == _selectedSeasonNumber + 1);
        if (nextSeasonIndex != -1) {
          nextSeason = _selectedSeasonNumber + 1;
          nextEpisode = 1;
          hasNext = true;
        }
      }
    }

    if (mounted) {
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            streamUrl: streamUrl,
            title: _details?['title'] ?? _details?['subjectTitle'] ?? "Play Video",
            subjectId: _selectedSubjectId,
            provider: widget.provider,
            season: _isTvShow ? _selectedSeasonNumber : 0,
            episode: _isTvShow ? _selectedEpisodeNumber : 0,
            captions: captions,
            coverUrl: _details?['cover']?['url'] ?? _details?['coverUrl'] ?? "",
            subjectType: _details?['subjectType'] ?? _details?['subject_type'] ?? 1,
            maxEpisodesInSeason: _episodesCount,
            hasNextEpisode: hasNext,
            nextEpisodeLabel: hasNext ? "S$nextSeason:E$nextEpisode" : null,
            onFetchNextEpisode: hasNext ? () => _fetchNextEpisodeStream(nextSeason, nextEpisode) : null,
            dubs: _dubs,
            currentAudioName: _selectedAudioName,
            availableStreams: _streams,
            currentStream: stream,
            seasons: _seasons,
            onSwitchAudio: _handleSwitchAudioInPlayer,
            onSwitchQuality: _handleSwitchQualityInPlayer,
            onSelectEpisode: _handleSelectEpisodeInPlayer,
          ),
        ),
      );

      if (mounted) {
        if (result is Map) {
          if (result['season'] != null && result['episode'] != null) {
            final s = result['season'] as int;
            final e = result['episode'] as int;
            if (s > 0 && e > 0 && (s != _selectedSeasonNumber || e != _selectedEpisodeNumber)) {
              setState(() {
                _selectedSeasonNumber = s;
                _selectedEpisodeNumber = e;
              });
            }
          }
          if (result['completed'] == true && _isTvShow && hasNext) {
            setState(() {
              _selectedSeasonNumber = nextSeason;
              _selectedEpisodeNumber = nextEpisode;
            });
          }
        }
        _loadStreams();
      }
    }
  }

  String _getDownloadId({int? season, int? episode}) {
    final sId = _isTmdb ? _selectedSubjectId : widget.subjectId;
    final se = season ?? (_isTvShow ? _selectedSeasonNumber : 0);
    final ep = episode ?? (_isTvShow ? _selectedEpisodeNumber : 0);
    if (se > 0 || ep > 0) {
      return "${sId}_s${se}_e$ep";
    }
    return sId;
  }

  void _handleDownloadAction({int? season, int? episode}) {
    final dId = _getDownloadId(season: season, episode: episode);
    final item = _downloadService.getItem(dId);

    if (item != null && item.status == DownloadStatus.completed) {
      // Offline play
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            streamUrl: item.filePath,
            title: item.title,
            subjectId: widget.subjectId,
            provider: widget.provider,
            season: item.season,
            episode: item.episode,
            coverUrl: item.coverUrl,
          ),
        ),
      );
      return;
    }

    if (item != null && item.status == DownloadStatus.downloading) {
      showDialog(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C1C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.downloading_rounded, color: Colors.cyanAccent, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppLanguageService.tr(en: "Download in Progress", id: "Sedang Mengunduh"),
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${item.title} (${item.quality})",
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: item.progress > 0 ? item.progress : null,
                minHeight: 6,
                backgroundColor: const Color(0xFF333333),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
              ),
              const SizedBox(height: 8),
              Text(
                "${(item.progress * 100).toStringAsFixed(1)}% • ${DownloadService.formatBytes(item.downloadedBytes)} / ${item.totalBytes > 0 ? DownloadService.formatBytes(item.totalBytes) : '...'}",
                style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _downloadService.pauseDownload(item.id);
              },
              child: Text(
                AppLanguageService.tr(en: "Pause", id: "Jeda"),
                style: GoogleFonts.outfit(color: Colors.amberAccent),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                _downloadService.cancelDownload(item.id);
              },
              child: Text(
                AppLanguageService.tr(en: "Cancel Download", id: "Batalkan Unduhan"),
                style: GoogleFonts.outfit(color: Colors.redAccent),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(
                AppLanguageService.tr(en: "Close", id: "Tutup"),
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (item != null && item.status == DownloadStatus.paused) {
      _downloadService.resumeDownload(item.id);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLanguageService.tr(en: "Resuming download...", id: "Melanjutkan unduhan..."),
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: const Color(0xFF222222),
        ),
      );
      return;
    }

    _openDownloadQualityDialog(season: season, episode: episode);
  }

  Future<void> _openDownloadQualityDialog({int? season, int? episode}) async {
    final isTv = _isTvShow;
    final se = season ?? (isTv ? _selectedSeasonNumber : 0);
    final ep = episode ?? (isTv ? _selectedEpisodeNumber : 0);
    final dId = _getDownloadId(season: se, episode: ep);

    final movieTitle = _details?['title'] ?? _details?['subjectTitle'] ?? "Movie";
    final itemTitle = isTv ? "$movieTitle - S${se}E$ep" : movieTitle;
    final coverUrl = _details?['cover']?['url'] ?? _details?['coverUrl'] ?? "";

    if (_is4kHub) {
      List<dynamic> releases = [];
      if (_streams.isNotEmpty && (!isTv || (_selectedSeasonNumber == se && _selectedEpisodeNumber == ep))) {
        releases = _streams;
      } else {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            content: Row(
              children: [
                const SpinKitRing(color: Colors.cyanAccent, size: 36.0),
                const SizedBox(width: 20),
                Expanded(
                  child: Text(
                    AppLanguageService.tr(
                      en: "Fetching download links...",
                      id: "Mengambil daftar link unduhan...",
                    ),
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );

        try {
          final targetId = _isTmdb ? _selectedSubjectId : widget.subjectId;
          releases = await _fourkApi.getReleases(
            targetId,
            rawHtml: _details?['rawHtml'],
            season: se,
            episode: ep,
          );
        } catch (_) {}

        if (mounted) Navigator.pop(context);
      }

      if (releases.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLanguageService.tr(
                  en: "No download links available for this title.",
                  id: "Tidak ada link unduhan tersedia untuk judul ini.",
                ),
              ),
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) {
          return Dialog(
            backgroundColor: const Color(0xFF141414),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.3), width: 1.2),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520, maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.cyan.shade900.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
                          ),
                          child: const Icon(Icons.download_rounded, color: Colors.cyanAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLanguageService.tr(en: "Download Offline Video", id: "Unduh Video Offline"),
                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                itemTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: releases.length,
                        itemBuilder: (ctx, i) {
                          final rel = releases[i];
                          final quality = rel['quality'] ?? "HD";
                          final size = rel['size'] ?? "";
                          final filename = rel['filename'] ?? "";

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: TvFocusableCard(
                              onTap: () async {
                                Navigator.pop(dialogContext);

                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E1E),
                                    content: Row(
                                      children: [
                                        const SpinKitRing(color: Colors.cyanAccent, size: 36.0),
                                        const SizedBox(width: 20),
                                        Expanded(
                                          child: Text(
                                            AppLanguageService.tr(
                                              en: "Connecting to 4KHDHub download mirror...",
                                              id: "Menghubungkan ke mirror download 4KHDHub...",
                                            ),
                                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );

                                String? resolvedUrl;
                                try {
                                  resolvedUrl = await _fourkApi.resolveReleaseStream(rel);
                                } catch (_) {}

                                if (mounted) Navigator.pop(context);

                                if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
                                  await _downloadService.startDownload(
                                    id: dId,
                                    title: itemTitle,
                                    coverUrl: coverUrl,
                                    streamUrl: resolvedUrl,
                                    quality: quality,
                                    provider: '4khdhub',
                                    season: se,
                                    episode: ep,
                                  );

                                  if (mounted) {
                                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLanguageService.tr(
                                            en: "Download started! Track progress in Downloads tab.",
                                            id: "Unduhan dimulai! Pantau progres di tab Unduhan.",
                                          ),
                                          style: GoogleFonts.outfit(),
                                        ),
                                        backgroundColor: const Color(0xFF1E1E1E),
                                        behavior: SnackBarBehavior.floating,
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                } else {
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLanguageService.tr(
                                            en: "Download link expired or unavailable. Try another quality.",
                                            id: "Link unduhan tidak tersedia / kadaluarsa. Coba kualitas lain.",
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              scaleFactor: 1.02,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: const Color(0xFF333333)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.cyan.shade900.withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        quality,
                                        style: GoogleFonts.outfit(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            filename.isNotEmpty ? filename : itemTitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          if (size.isNotEmpty) ...[
                                            const SizedBox(height: 3),
                                            Text(
                                              "Ukuran: $size",
                                              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.download_rounded, color: Colors.cyanAccent, size: 24),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    // MovieBox: Fetch streams for target resolutions
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: SpinKitRing(color: Colors.redAccent, size: 48.0),
      ),
    );

    List<dynamic> targetStreams = [];
    try {
      final List<int> targetResolutions = [1080, 720, 480, 360];
      final List<dynamic> combinedList = [];

      for (int i = 0; i < targetResolutions.length; i += 2) {
        final batch = targetResolutions.sublist(
          i,
          i + 2 > targetResolutions.length ? targetResolutions.length : i + 2,
        );

        final batchResults = await Future.wait(batch.map((res) {
          return _api.getResources(
            subjectId: _selectedSubjectId,
            se: se,
            ep: ep,
            resolution: res,
          ).catchError((e) => <String, dynamic>{});
        }));

        for (final resData in batchResults) {
          final List<dynamic> fileList = resData['list'] ?? [];
          combinedList.addAll(fileList);
        }
      }

      List<dynamic> filteredList = combinedList;
      if (isTv) {
        filteredList = combinedList.where((item) {
          final itemSe = int.tryParse(item['se']?.toString() ?? '') ?? 0;
          final itemEp = int.tryParse(item['ep']?.toString() ?? '') ?? 0;
          return itemSe == se && itemEp == ep;
        }).toList();
      }

      final Map<String, dynamic> uniqueStreams = {};
      for (final item in filteredList) {
        final id = item['resourceId']?.toString() ?? item['resource_id']?.toString() ?? '';
        final res = item['resolution']?.toString() ?? '';
        final codec = item['codecName']?.toString() ?? item['codec_name']?.toString() ?? '';
        final link = item['resourceLink']?.toString() ?? item['resource_link']?.toString() ?? '';
        final key = id.isNotEmpty ? "${id}_${res}_$codec" : "${link}_${res}_$codec";
        uniqueStreams[key] = item;
      }
      targetStreams = uniqueStreams.values.toList();
    } catch (_) {}

    if (mounted) Navigator.pop(context);

    if (targetStreams.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.tr(
                en: "No download streams found for this selection.",
                id: "Tidak ada stream unduhan ditemukan untuk pilihan ini.",
              ),
            ),
          ),
        );
      }
      return;
    }

    final Map<int, dynamic> bestPerRes = {};
    for (final st in targetStreams) {
      final res = int.tryParse(st['resolution']?.toString() ?? '') ?? 0;
      if (res > 0) {
        final existing = bestPerRes[res];
        if (existing == null) {
          bestPerRes[res] = st;
        } else {
          final codecA = (st['codecName'] ?? st['codec_name'] ?? "").toString().toLowerCase();
          final isHevcA = codecA.contains('hevc') || codecA.contains('h265');
          if (!isHevcA) {
            bestPerRes[res] = st;
          }
        }
      }
    }

    final sortedResolutions = bestPerRes.keys.toList()..sort((a, b) => b.compareTo(a));

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3), width: 1.2),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 480, maxWidth: 540),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                        ),
                        child: const Icon(Icons.download_rounded, color: Colors.redAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppLanguageService.tr(en: "Download Movie / Episode", id: "Pilih Resolusi Unduhan"),
                              style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              itemTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: sortedResolutions.map((res) {
                          final streamData = bestPerRes[res];
                          final rawSize = int.tryParse(streamData['size']?.toString() ?? '0') ?? 0;
                          final sizeFormatted = rawSize > 0 ? DownloadService.formatBytes(rawSize) : "";
                          final isRecommended = res == 720;
                          final label = res >= 1080 ? "Full HD" : (res == 720 ? "HD" : "SD");

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10.0),
                            child: TvFocusableCard(
                              onTap: () async {
                                Navigator.pop(dialogCtx);
                                final streamUrl = streamData['resourceLink'] ?? streamData['resource_link'] ?? "";
                                if (streamUrl.isEmpty) return;

                                await _downloadService.startDownload(
                                  id: dId,
                                  title: itemTitle,
                                  coverUrl: coverUrl,
                                  streamUrl: streamUrl,
                                  quality: "${res}p",
                                  provider: 'moviebox',
                                  season: se,
                                  episode: ep,
                                );

                                if (mounted) {
                                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        AppLanguageService.tr(
                                          en: "Download started (${res}p)! Track progress in Downloads tab.",
                                          id: "Unduhan dimulai (${res}p)! Cek progres di tab Unduhan.",
                                        ),
                                        style: GoogleFonts.outfit(),
                                      ),
                                      backgroundColor: const Color(0xFF1E1E1E),
                                      behavior: SnackBarBehavior.floating,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              scaleFactor: 1.02,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E1E1E),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isRecommended ? Colors.tealAccent.withValues(alpha: 0.6) : const Color(0xFF333333),
                                    width: isRecommended ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: res >= 1080
                                            ? Colors.blue.shade900.withValues(alpha: 0.6)
                                            : (res == 720
                                                ? Colors.teal.shade900.withValues(alpha: 0.6)
                                                : Colors.grey.shade800),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        "${res}p",
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Wrap(
                                            crossAxisAlignment: WrapCrossAlignment.center,
                                            spacing: 8,
                                            runSpacing: 4,
                                            children: [
                                              Text(
                                                "${res}p $label",
                                                style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                              ),
                                              if (isRecommended)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Colors.teal.shade900.withValues(alpha: 0.7),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    AppLanguageService.tr(en: "Best for TV", id: "Hemat Memori TV"),
                                                    style: GoogleFonts.outfit(color: Colors.tealAccent, fontSize: 9, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (sizeFormatted.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              "Ukuran file: ~$sizeFormatted",
                                              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.download_rounded, color: Colors.redAccent, size: 24),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
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

  Widget _buildHeroDownloadButton(bool isTv, {bool isMobile = false}) {
    return ValueListenableBuilder<List<DownloadItem>>(
      valueListenable: _downloadService.downloadsNotifier,
      builder: (context, downloadItems, _) {
        final dId = _getDownloadId();
        final item = _downloadService.getItem(dId);

        final isCompleted = item?.status == DownloadStatus.completed;
        final isDownloading = item?.status == DownloadStatus.downloading;

        String btnLabel = AppLanguageService.tr(en: "Download", id: "Unduh");
        IconData btnIcon = Icons.download_rounded;
        Color btnBorderColor = Colors.white24;
        Color btnIconColor = Colors.white;

        if (isCompleted) {
          btnLabel = AppLanguageService.tr(en: "Watch Offline", id: "Putar Offline");
          btnIcon = Icons.offline_pin_rounded;
          btnBorderColor = Colors.tealAccent;
          btnIconColor = Colors.tealAccent;
        } else if (isDownloading) {
          final pct = (item!.progress * 100).toInt();
          btnLabel = "$pct% Unduh";
          btnIcon = Icons.hourglass_top_rounded;
          btnBorderColor = Colors.amberAccent;
          btnIconColor = Colors.amberAccent;
        }

        return TvFocusableCard(
          onTap: () => _handleDownloadAction(),
          borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
          scaleFactor: 1.05,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 24,
              vertical: isMobile ? 14 : 16,
            ),
            decoration: BoxDecoration(
              color: isCompleted ? Colors.teal.shade900.withValues(alpha: 0.6) : const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
              border: Border.all(color: btnBorderColor, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDownloading)
                  SizedBox(
                    width: isMobile ? 18 : 22,
                    height: isMobile ? 18 : 22,
                    child: SpinKitRing(color: Colors.amberAccent, size: isMobile ? 16 : 18),
                  )
                else
                  Icon(btnIcon, color: btnIconColor, size: isMobile ? 20 : 24),
                const SizedBox(width: 8),
                Text(
                  btnLabel,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: isMobile ? 13 : 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodeDownloadButton(int epNum, bool isTv) {
    return ValueListenableBuilder<List<DownloadItem>>(
      valueListenable: _downloadService.downloadsNotifier,
      builder: (context, downloadItems, _) {
        final dId = _getDownloadId(episode: epNum);
        final item = _downloadService.getItem(dId);

        final isCompleted = item?.status == DownloadStatus.completed;
        final isDownloading = item?.status == DownloadStatus.downloading;

        return TvFocusableCard(
          onTap: () => _handleDownloadAction(episode: epNum),
          borderRadius: BorderRadius.circular(8),
          scaleFactor: 1.1,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isCompleted
                  ? Colors.teal.shade900.withValues(alpha: 0.5)
                  : const Color(0xFF222222),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCompleted ? Colors.tealAccent : const Color(0xFF333333),
              ),
            ),
            child: isDownloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: SpinKitRing(color: Colors.amberAccent, size: 16),
                  )
                : Icon(
                    isCompleted ? Icons.check_circle_rounded : Icons.download_rounded,
                    color: isCompleted ? Colors.tealAccent : Colors.white70,
                    size: 18,
                  ),
          ),
        );
      },
    );
  }

  Widget _buildEpisodePlayButton(int epNum, bool isTv, bool isSelected) {
    return TvFocusableCard(
      onTap: () => _playEpisode(_selectedSeasonNumber, epNum),
      borderRadius: BorderRadius.circular(8),
      scaleFactor: 1.1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.redAccent : const Color(0xFF222222),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.redAccent : const Color(0xFF333333),
          ),
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          color: isSelected ? Colors.white : Colors.white70,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color, {required bool isTv}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTv ? 12 : 8,
        vertical: isTv ? 4 : 2,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: isTv ? 14 : 12,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
  Widget _buildHeaderSection({required bool isTv}) {
    final title = _details?['title'] ?? _details?['subjectTitle'] ?? "Untitled";
    final desc = _details?['description'] ?? "No description available.";
    final releaseDate = _details?['releaseDate'] ?? _details?['release_date'] ?? "-";
    final rating = _details?['imdbRatingValue'] ?? _details?['imdbRate'] ?? "-";
    final coverUrl = _details?['cover']?['url'] ?? _details?['coverUrl'] ?? "";

    final isWatched = _savedProgressMs > 5000;
    final resumeText = _formatDurationMs(_savedProgressMs);

    final playBtnText = _noStreamingSourcesFound
        ? AppLanguageService.tr(
            en: "In Theaters · Streaming Unavailable",
            id: "Tayang di Bioskop · Belum Tersedia",
          )
        : (_isTvShow
            ? (isWatched
                ? AppLanguageService.tr(
                    en: "Resume S$_selectedSeasonNumber:E$_selectedEpisodeNumber ($resumeText)",
                    id: "Lanjutkan S$_selectedSeasonNumber:E$_selectedEpisodeNumber ($resumeText)",
                  )
                : AppLanguageService.tr(
                    en: "Play S$_selectedSeasonNumber:E$_selectedEpisodeNumber",
                    id: "Putar S$_selectedSeasonNumber:E$_selectedEpisodeNumber",
                  ))
            : (isWatched
                ? AppLanguageService.tr(
                    en: "Resume Movie ($resumeText)",
                    id: "Lanjutkan Menonton ($resumeText)",
                  )
                : AppLanguageService.tr(
                    en: "Play Movie",
                    id: "Putar Film",
                  )));

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTv ? 32 : 20, vertical: 20),
      child: isTv
          // TV 2-Column Hero Layout
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Poster Card
                if (coverUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: 200,
                      height: 300,
                      color: const Color(0xFF1E1E1E),
                      child: Image.network(
                        coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => const Icon(Icons.movie, size: 60, color: Colors.white24),
                      ),
                    ),
                  ),
                const SizedBox(width: 32),
                // Right: Details & Play Action
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Badges
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (_isTmdb)
                            _buildBadge("TMDB · Trending", Colors.amberAccent, isTv: isTv)
                          else if (_is4kHub)
                            _buildBadge("4KHDHub · 4K UHD", Colors.cyanAccent, isTv: isTv),
                          if (_is4kHub && _details?['imdbRating'] != null && _details!['imdbRating'].isNotEmpty)
                            _buildBadge("★ ${_details!['imdbRating']}", Colors.amber, isTv: isTv)
                          else if (!_is4kHub && rating != "-")
                            _buildBadge("★ IMDb $rating", Colors.amber, isTv: isTv),
                          _buildBadge(_isTvShow ? "TV Series" : "Movie", Colors.redAccent, isTv: isTv),
                          if (_details?['year'] != null)
                            _buildBadge("${_details!['year']}", Colors.grey, isTv: isTv)
                          else
                            _buildBadge(releaseDate.toString().split('-')[0], Colors.grey, isTv: isTv),
                          if (_isTvShow && _seasons.isNotEmpty)
                            _buildBadge("${_seasons.length} Seasons", Colors.white70, isTv: isTv),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Description
                      Text(
                        desc,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: Colors.grey.shade300,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // TMDB Resolving Indicator
                      if (_isTmdb && _isResolvingSources) ...[
                        Row(
                          children: [
                            const SpinKitRing(color: Colors.redAccent, size: 16),
                            const SizedBox(width: 10),
                            Text(
                              AppLanguageService.tr(
                                en: "Searching streaming sources (MovieBox & 4KHDHub)...",
                                id: "Mencari sumber streaming (MovieBox & 4KHDHub)...",
                              ),
                              style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                      ],
                      // TMDB Resolved Sources Chips
                      if (_isTmdb && _resolvedSources.isNotEmpty) ...[
                        Row(
                          children: _resolvedSources.map((source) {
                            final prov = source['provider'] as String;
                            final isSelected = _activeProvider == prov;
                            final label = source['label'] as String;
                            return Padding(
                              padding: const EdgeInsets.only(right: 12.0),
                              child: TvFocusableCard(
                                onTap: () => _activateResolvedSource(source),
                                borderRadius: BorderRadius.circular(16),
                                scaleFactor: 1.05,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? (prov == '4khdhub'
                                            ? Colors.cyanAccent.withValues(alpha: 0.2)
                                            : Colors.redAccent.withValues(alpha: 0.2))
                                        : const Color(0xFF1E1E1E),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? (prov == '4khdhub' ? Colors.cyanAccent : Colors.redAccent)
                                          : Colors.white24,
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        prov == '4khdhub' ? Icons.hd_outlined : Icons.movie_outlined,
                                        color: isSelected
                                            ? (prov == '4khdhub' ? Colors.cyanAccent : Colors.redAccent)
                                            : Colors.white70,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        label,
                                        style: GoogleFonts.outfit(
                                          color: isSelected ? Colors.white : Colors.white70,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // Main Hero Play Button Row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TvFocusableCard(
                              onTap: () {
                                if (_noStreamingSourcesFound) {
                                  _showUnavailableDialog();
                                  return;
                                }
                                _playEpisode(_selectedSeasonNumber, _selectedEpisodeNumber);
                              },
                              borderRadius: BorderRadius.circular(14),
                              scaleFactor: 1.05,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                decoration: BoxDecoration(
                                  gradient: _noStreamingSourcesFound
                                      ? const LinearGradient(
                                          colors: [Color(0xFF333333), Color(0xFF222222)],
                                        )
                                      : const LinearGradient(
                                          colors: [Color(0xFFE50914), Color(0xFFB81D24)],
                                        ),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: _noStreamingSourcesFound
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: Colors.redAccent.withValues(alpha: 0.4),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _noStreamingSourcesFound ? Icons.schedule_rounded : Icons.play_arrow_rounded,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        playBtnText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (_is4kHub) ...[
                              const SizedBox(width: 16),
                              TvFocusableCard(
                                onTap: () => _open4kQualitySelector(),
                                borderRadius: BorderRadius.circular(14),
                                scaleFactor: 1.05,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A1A1A),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 1.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.tune_rounded, color: Colors.cyanAccent, size: 26),
                                      const SizedBox(width: 10),
                                      Text(
                                        AppLanguageService.tr(en: "Select Quality", id: "Pilih Kualitas"),
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 16),
                            _buildHeroDownloadButton(isTv),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          // Mobile Layout
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (coverUrl.isNotEmpty)
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 150,
                        height: 220,
                        child: Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => const Icon(Icons.movie, size: 50, color: Colors.white24),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (_isTmdb)
                      _buildBadge("TMDB · Trending", Colors.amberAccent, isTv: isTv)
                    else if (_is4kHub)
                      _buildBadge("4KHDHub · 4K UHD", Colors.cyanAccent, isTv: isTv),
                    if (_is4kHub && _details?['imdbRating'] != null && _details!['imdbRating'].isNotEmpty)
                      _buildBadge("★ ${_details!['imdbRating']}", Colors.amber, isTv: isTv)
                    else if (!_is4kHub && rating != "-")
                      _buildBadge("★ IMDb $rating", Colors.amber, isTv: isTv),
                    _buildBadge(_isTvShow ? "TV Series" : "Movie", Colors.redAccent, isTv: isTv),
                    if (_details?['year'] != null)
                      _buildBadge("${_details!['year']}", Colors.grey, isTv: isTv)
                    else
                      _buildBadge(releaseDate.toString().split('-')[0], Colors.grey, isTv: isTv),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  desc,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                // TMDB Resolving Indicator (Mobile)
                if (_isTmdb && _isResolvingSources) ...[
                  Row(
                    children: [
                      const SpinKitRing(color: Colors.redAccent, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppLanguageService.tr(
                            en: "Searching sources (MovieBox & 4KHDHub)...",
                            id: "Mencari sumber streaming...",
                          ),
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                // TMDB Resolved Sources Chips (Mobile)
                if (_isTmdb && _resolvedSources.isNotEmpty) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _resolvedSources.map((source) {
                      final prov = source['provider'] as String;
                      final isSelected = _activeProvider == prov;
                      final label = source['label'] as String;
                      return TvFocusableCard(
                        onTap: () => _activateResolvedSource(source),
                        borderRadius: BorderRadius.circular(14),
                        scaleFactor: 1.03,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (prov == '4khdhub'
                                    ? Colors.cyanAccent.withValues(alpha: 0.2)
                                    : Colors.redAccent.withValues(alpha: 0.2))
                                : const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? (prov == '4khdhub' ? Colors.cyanAccent : Colors.redAccent)
                                  : Colors.white24,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                prov == '4khdhub' ? Icons.hd_outlined : Icons.movie_outlined,
                                color: isSelected
                                    ? (prov == '4khdhub' ? Colors.cyanAccent : Colors.redAccent)
                                    : Colors.white70,
                                size: 14,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                label,
                                style: GoogleFonts.outfit(
                                  color: isSelected ? Colors.white : Colors.white70,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                ],
                // Play Button & Quality Button Row
                Row(
                  children: [
                    Expanded(
                      flex: _is4kHub ? 7 : 1,
                      child: TvFocusableCard(
                        onTap: () {
                          if (_noStreamingSourcesFound) {
                            _showUnavailableDialog();
                            return;
                          }
                          _playEpisode(_selectedSeasonNumber, _selectedEpisodeNumber);
                        },
                        borderRadius: BorderRadius.circular(12),
                        scaleFactor: 1.03,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: _noStreamingSourcesFound
                                ? const LinearGradient(
                                    colors: [Color(0xFF333333), Color(0xFF222222)],
                                  )
                                : const LinearGradient(
                                    colors: [Color(0xFFE50914), Color(0xFFB81D24)],
                                  ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _noStreamingSourcesFound ? Icons.schedule_rounded : Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  playBtnText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_is4kHub) ...[
                      const SizedBox(width: 8),
                      TvFocusableCard(
                        onTap: () => _open4kQualitySelector(),
                        borderRadius: BorderRadius.circular(12),
                        scaleFactor: 1.05,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1A1A1A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 1.2),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.tune_rounded, color: Colors.cyanAccent, size: 20),
                              const SizedBox(width: 4),
                              Text(
                                AppLanguageService.tr(en: "Quality", id: "Kualitas"),
                                style: GoogleFonts.outfit(
                                  color: Colors.cyanAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    _buildHeroDownloadButton(isTv, isMobile: true),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildEpisodesSection({required bool isTv}) {
    if (!_isTvShow) return const SizedBox.shrink();

    Map<String, dynamic>? currentSeasonData;
    for (final s in _seasons) {
      if (s is Map && (s['se'] ?? 1) == _selectedSeasonNumber) {
        currentSeasonData = Map<String, dynamic>.from(s);
        break;
      }
    }
    if (currentSeasonData == null) {
      if (_seasons.isNotEmpty && _seasons.first is Map) {
        currentSeasonData = Map<String, dynamic>.from(_seasons.first as Map);
      } else {
        currentSeasonData = {'se': 1, 'maxEp': _episodesCount};
      }
    }

    List<dynamic> epList = [];
    if (currentSeasonData['episodes'] is List && (currentSeasonData['episodes'] as List).isNotEmpty) {
      epList = currentSeasonData['episodes'];
    } else {
      final maxEp = (currentSeasonData['maxEp'] ?? _episodesCount) as int;
      final total = maxEp > 0 ? maxEp : 1;
      epList = List.generate(total, (i) {
        final epNum = i + 1;
        return {
          'ep': epNum,
          'se': _selectedSeasonNumber,
          'title': "Episode $epNum",
          'description': "Season $_selectedSeasonNumber • Episode $epNum",
        };
      });
    }

    final coverUrl = _details?['cover']?['url'] ?? _details?['coverUrl'] ?? "";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Season Tabs (if more than 1 season)
        if (_seasons.length > 1) ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isTv ? 32.0 : 20.0, vertical: 8.0),
            child: SizedBox(
              height: isTv ? 44 : 38,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _seasons.length,
                itemBuilder: (context, index) {
                  final s = _seasons[index];
                  final seNum = s['se'] ?? (index + 1);
                  final isSelected = seNum == _selectedSeasonNumber;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: TvFocusableCard(
                      onTap: () {
                        final maxEp = (s['maxEp'] ?? 1) as int;
                        setState(() {
                          _selectedSeasonNumber = seNum;
                          _episodesCount = maxEp;
                          _selectedEpisodeNumber = 1;
                          _expandedEpisodeNumber = null;
                        });
                        _checkProgress();
                        _loadStreams();
                      },
                      borderRadius: BorderRadius.circular(20),
                      scaleFactor: 1.05,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isTv ? 20 : 16,
                          vertical: isTv ? 10 : 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.redAccent : const Color(0xFF1E1E1E),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? Colors.redAccent : const Color(0xFF333333),
                          ),
                        ),
                        child: Text(
                          "Season $seNum",
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            fontSize: isTv ? 15 : 13,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Section Title
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTv ? 32.0 : 20.0, vertical: 8.0),
          child: Text(
            "Season $_selectedSeasonNumber • ${epList.length} ${AppLanguageService.tr(en: "Episodes", id: "Episode")}",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: isTv ? 22 : 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        // Episodes List
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: isTv ? 32.0 : 20.0, vertical: 8.0),
          itemCount: epList.length,
          itemBuilder: (context, index) {
            final epItem = epList[index];
            final int epNum = (epItem is Map ? (epItem['ep'] ?? (index + 1)) : (index + 1)) as int;
            final isSelected = _selectedEpisodeNumber == epNum;
            final isExpanded = _expandedEpisodeNumber == epNum;

            // Check TVMaze metadata for official title, synopsis, still image, and rating
            final mazeKey = 'S${_selectedSeasonNumber}E$epNum';
            final mazeData = _tvMazeEpisodes[mazeKey];

            String epTitle = (epItem is Map ? (epItem['title'] ?? epItem['name'] ?? "Episode $epNum") : "Episode $epNum").toString();
            if (mazeData != null && mazeData.name.isNotEmpty) {
              epTitle = mazeData.name;
            }

            String epDesc = (epItem is Map ? (epItem['description'] ?? epItem['desc'] ?? epItem['intro'] ?? "") : "").toString();
            if (mazeData != null && mazeData.overview.isNotEmpty) {
              epDesc = mazeData.overview;
            }

            String epThumb = (epItem is Map ? (epItem['thumbnail'] ?? epItem['cover'] ?? epItem['pic'] ?? epItem['still_path'] ?? "") : "").toString();
            if (mazeData != null && mazeData.imageUrl != null && mazeData.imageUrl!.isNotEmpty) {
              epThumb = mazeData.imageUrl!;
            }
            final displayThumb = epThumb.isNotEmpty ? epThumb : coverUrl;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: TvFocusableCard(
                onTap: () {
                  setState(() {
                    if (_expandedEpisodeNumber == epNum) {
                      _expandedEpisodeNumber = null;
                    } else {
                      _expandedEpisodeNumber = epNum;
                      _selectedEpisodeNumber = epNum;
                    }
                  });
                  _checkProgress();
                  _loadStreams();
                },
                borderRadius: BorderRadius.circular(12),
                scaleFactor: 1.02,
                child: Container(
                  decoration: BoxDecoration(
                    color: (isSelected || isExpanded) ? const Color(0xFF28181A) : const Color(0xFF161616),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (isSelected || isExpanded) ? Colors.redAccent.withValues(alpha: 0.8) : const Color(0xFF2C2C2C),
                      width: (isSelected || isExpanded) ? 1.5 : 1,
                    ),
                  ),
                  padding: EdgeInsets.all(isTv ? 14.0 : 10.0),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Main Row: Thumbnail + Info + Actions
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Thumbnail Container (16:9)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: isTv ? 160 : 96,
                                height: isTv ? 90 : 54,
                                color: const Color(0xFF222222),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    if (displayThumb.isNotEmpty)
                                      Image.network(
                                        displayThumb,
                                        fit: BoxFit.cover,
                                        errorBuilder: (ctx, err, stack) => Container(
                                          color: const Color(0xFF222222),
                                          child: const Icon(Icons.movie, color: Colors.white24),
                                        ),
                                      ),
                                    // Dark gradient overlay
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.black.withValues(alpha: 0.5),
                                          ],
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                        ),
                                      ),
                                    ),
                                    // Badge EP number
                                    Positioned(
                                      top: 4,
                                      left: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          "EP $epNum",
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SizedBox(width: isTv ? 16 : 12),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Flexible(
                                        child: Text(
                                          "Episode $epNum",
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.outfit(
                                            color: (isSelected || isExpanded) ? Colors.redAccent : Colors.white,
                                            fontSize: isTv ? 16 : 13.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (mazeData?.rating != null) ...[
                                        const SizedBox(width: 5),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: Colors.amber.withValues(alpha: 0.4), width: 0.5),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(Icons.star_rounded, color: Colors.amber, size: 10),
                                              const SizedBox(width: 2),
                                              Text(
                                                mazeData!.rating!.toStringAsFixed(1),
                                                style: GoogleFonts.outfit(
                                                  color: Colors.amber,
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (epTitle.isNotEmpty && epTitle != "Episode $epNum") ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      epTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: Colors.white70,
                                        fontSize: isTv ? 14 : 11.5,
                                      ),
                                    ),
                                  ],
                                  if (!isExpanded) ...[
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          AppLanguageService.tr(en: "Details", id: "Detail"),
                                          style: GoogleFonts.outfit(
                                            color: Colors.white38,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          color: Colors.white38,
                                          size: 13,
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Actions: Download & Play
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildEpisodeDownloadButton(epNum, isTv),
                                const SizedBox(width: 6),
                                _buildEpisodePlayButton(epNum, isTv, isSelected),
                              ],
                            ),
                          ],
                        ),

                        // Expanded Description & Actions
                        if (isExpanded) ...[
                          const SizedBox(height: 10),
                          Container(
                            height: 1,
                            color: const Color(0xFF2C2C2C),
                          ),
                          const SizedBox(height: 10),
                          if (epTitle.isNotEmpty && epTitle != "Episode $epNum") ...[
                            Text(
                              epTitle,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: isTv ? 16 : 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                          if (mazeData?.airDate != null && mazeData!.airDate!.isNotEmpty) ...[
                            Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 11, color: Colors.grey.shade400),
                                const SizedBox(width: 5),
                                Text(
                                  "${AppLanguageService.tr(en: "Air Date:", id: "Tayang:")} ${mazeData.airDate!}",
                                  style: GoogleFonts.outfit(
                                    color: Colors.grey.shade400,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            epDesc.isNotEmpty
                                ? epDesc
                                : AppLanguageService.tr(
                                    en: "No description available for this episode.",
                                    id: "Tidak ada deskripsi untuk episode ini.",
                                  ),
                            style: GoogleFonts.outfit(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: isTv ? 14 : 12,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TvFocusableCard(
                            onTap: () => _playEpisode(_selectedSeasonNumber, epNum),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.redAccent,
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.redAccent.withValues(alpha: 0.3),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
                                  const SizedBox(width: 6),
                                  Text(
                                    AppLanguageService.tr(
                                      en: "Play Episode $epNum",
                                      id: "Putar Episode $epNum",
                                    ),
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: isTv ? 15 : 13,
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
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildContentLayout(bool isTv) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(isTv: isTv),
          const Divider(color: Color(0xFF222222), height: 1),
          
          if (_isTvShow) ...[
            const SizedBox(height: 12),
            _buildEpisodesSection(isTv: isTv),
          ],
          
          SizedBox(height: isTv ? 60 : 40),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingDetails) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F0F0F),
        body: Center(
          child: SpinKitRing(color: Colors.redAccent, size: 50.0),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F0F),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                const SizedBox(height: 16),
                Text(
                  _errorMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 18),
                ),
                const SizedBox(height: 24),
                TvFocusableCard(
                  onTap: () {
                    _loadDetails();
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      AppLanguageService.tr(en: "Retry", id: "Coba Lagi"),
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final size = MediaQuery.of(context).size;
    final isTv = size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
          // Content Scroll
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 60.0),
                child: _buildContentLayout(isTv),
              ),
            ),
          ),

          // Back button
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: TvFocusableCard(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black.withOpacity(0.6),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                ),
              ),
            ),
          ),

          // Favorite button
          Positioned(
            top: 20,
            right: 20,
            child: SafeArea(
              child: TvFocusableCard(
                onTap: _toggleFavorite,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.black.withOpacity(0.6),
                  child: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.redAccent : Colors.white,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

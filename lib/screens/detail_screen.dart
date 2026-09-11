import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/moviebox_api_service.dart';
import '../services/fourkhdhub_service.dart';
import '../services/favorites_service.dart';
import '../services/app_language_service.dart';
import '../services/playback_progress_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final String subjectId;
  final String provider;
  final int? initialSeason;
  final int? initialEpisode;

  const DetailScreen({
    super.key,
    required this.subjectId,
    this.provider = 'moviebox',
    this.initialSeason,
    this.initialEpisode,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final MovieBoxApiService _api = MovieBoxApiService();
  final FourKHdHubService _fourkApi = FourKHdHubService();
  
  bool get _is4kHub => widget.provider.toLowerCase() == '4khdhub';
  
  Map<String, dynamic>? _details;
  List<dynamic> _dubs = [];
  List<dynamic> _seasons = [];
  List<dynamic> _streams = [];
  
  String _selectedSubjectId = "";
  String _selectedAudioName = "Original";
  int _selectedSeasonNumber = 1;
  int _selectedEpisodeNumber = 1;
  int _episodesCount = 0;
  
  bool _isLoadingDetails = true;
  bool _isLoadingStreams = false;
  String _errorMessage = "";
  bool _isFavorite = false;

  bool get _isTvShow {
    final type = _details?['subjectType'] ?? _details?['subject_type'];
    return type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';
  }

  @override
  void initState() {
    super.initState();
    _selectedSubjectId = widget.subjectId;
    _loadDetails();
    _checkFavorite();
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
    });

    if (_is4kHub) {
      try {
        final detailsRes = await _fourkApi.getDetails(widget.subjectId);
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

        // Auto-select Indonesian audio track if available, else English, else Original
        final selectedDub = dubsList.firstWhere(
          (d) {
            final name = (d['lanName'] ?? d['language'] ?? '').toString().toLowerCase();
            return name.contains('indonesia') || name.contains('indonesian') || name == 'id' || name == 'ina';
          },
          orElse: () => dubsList.firstWhere(
            (d) {
              final name = (d['lanName'] ?? d['language'] ?? '').toString().toLowerCase();
              return name.contains('english') || name == 'en' || name == 'eng';
            },
            orElse: () => dubsList.firstWhere(
              (d) => d['original'] == true || (d['lanName'] ?? '').toString().toLowerCase().contains('original'),
              orElse: () => dubsList.first,
            ),
          ),
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

  void _loadStreams() async {
    setState(() {
      _isLoadingStreams = true;
      _streams = [];
    });

    if (_is4kHub) {
      try {
        final releases = await _fourkApi.getReleases(
          widget.subjectId,
          rawHtml: _details?['rawHtml'],
          season: _isTvShow ? _selectedSeasonNumber : 0,
          episode: _isTvShow ? _selectedEpisodeNumber : 0,
        );

        setState(() {
          _streams = releases;
          _isLoadingStreams = false;
        });
      } catch (e) {
        setState(() {
          _isLoadingStreams = false;
        });
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

      // Deduplicate streams by resourceId
      final Map<String, dynamic> uniqueStreams = {};
      for (final item in filteredList) {
        final id = item['resourceId']?.toString() ?? item['resource_id']?.toString() ?? '';
        if (id.isNotEmpty) {
          uniqueStreams[id] = item;
        } else {
          uniqueStreams[uniqueStreams.length.toString()] = item;
        }
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
        _isLoadingStreams = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingStreams = false;
      });
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

  void _onAudioChanged(dynamic dub) async {
    final subId = dub['subjectId']?.toString() ?? widget.subjectId;
    final name = _formatDubLabel(dub);
    
    setState(() {
      _selectedAudioName = name;
      _selectedSubjectId = subId;
    });

    // If TV Show, sync season and episode info with the selected dub's subjectId
    if (_isTvShow) {
      try {
        final seasonsRes = await _api.getSeasonInfo(subjectId: subId);
        final List<dynamic> newSeasons = seasonsRes['seasons'] ?? [];
        if (newSeasons.isNotEmpty) {
          final matchingSeason = newSeasons.firstWhere(
            (s) => (s['se'] ?? 1) == _selectedSeasonNumber,
            orElse: () => newSeasons[0],
          );
          final maxEp = (matchingSeason['maxEp'] ?? 1) as int;
          setState(() {
            _seasons = newSeasons;
            _selectedSeasonNumber = matchingSeason['se'] ?? 1;
            _episodesCount = maxEp;
            if (_selectedEpisodeNumber > maxEp || _selectedEpisodeNumber < 1) {
              _selectedEpisodeNumber = 1;
            }
          });
        }
      } catch (e) {
        print("Failed refreshing seasons for dub $subId: $e");
      }
    }

    _loadStreams();
  }

  void _onSeasonChanged(int seasonNum, int maxEp) {
    setState(() {
      _selectedSeasonNumber = seasonNum;
      _episodesCount = maxEp;
      _selectedEpisodeNumber = 1; // reset episode to 1
    });
    _loadStreams();
  }

  void _onEpisodeChanged(int epNum) {
    setState(() {
      _selectedEpisodeNumber = epNum;
    });
    _loadStreams();
  }

  Future<PlayerNextEpisodeData?> _fetchNextEpisodeStream(int nextSeason, int nextEpisode) async {
    if (_is4kHub) {
      try {
        final releases = await _fourkApi.getReleases(
          widget.subjectId,
          rawHtml: _details?['rawHtml'],
          season: nextSeason,
          episode: nextEpisode,
        );
        if (releases.isEmpty) return null;

        final bestRelease = releases.first;
        final streamUrl = await _fourkApi.resolveReleaseStream(bestRelease);
        if (streamUrl == null || streamUrl.isEmpty) return null;

        int nextNextSeason = nextSeason;
        int nextNextEpisode = nextEpisode + 1;
        bool hasNextNext = false;
        int maxEpOfSeason = 0;
        for (final s in _seasons) {
          if ((s['se'] ?? 0) == nextSeason) {
            maxEpOfSeason = (s['maxEp'] ?? 0) as int;
            break;
          }
        }

        if (nextNextEpisode <= maxEpOfSeason) {
          hasNextNext = true;
        } else {
          final followingSeason = _seasons.any((s) => (s['se'] ?? 0) == nextSeason + 1);
          if (followingSeason) {
            nextNextSeason = nextSeason + 1;
            nextNextEpisode = 1;
            hasNextNext = true;
          }
        }

        if (mounted) {
          setState(() {
            _selectedSeasonNumber = nextSeason;
            _selectedEpisodeNumber = nextEpisode;
            if (maxEpOfSeason > 0) _episodesCount = maxEpOfSeason;
          });
        }

        return PlayerNextEpisodeData(
          streamUrl: streamUrl,
          title: _details?['title'] ?? _details?['subjectTitle'] ?? "Play Video",
          season: nextSeason,
          episode: nextEpisode,
          captions: const [],
          hasNextEpisode: hasNextNext,
          nextEpisodeLabel: hasNextNext ? "S$nextNextSeason:E$nextNextEpisode" : null,
        );
      } catch (e) {
        print("Error fetching next 4khdhub episode: $e");
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
            se: nextSeason,
            ep: nextEpisode,
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
        return itemSe == nextSeason && itemEp == nextEpisode;
      }).toList();

      if (filteredList.isEmpty) return null;

      filteredList.sort((a, b) {
        final codecA = (a['codecName'] ?? a['codec_name'] ?? "").toString().toLowerCase();
        final codecB = (b['codecName'] ?? b['codec_name'] ?? "").toString().toLowerCase();
        final isHevcA = codecA.contains('hevc') || codecA.contains('h265') || codecA.contains('h.265');
        final isHevcB = codecB.contains('hevc') || codecB.contains('h265') || codecB.contains('h.265');
        if (isHevcA && !isHevcB) return 1;
        if (!isHevcA && isHevcB) return -1;
        final resComp = (b['resolution'] ?? 0).compareTo(a['resolution'] ?? 0);
        if (resComp != 0) return resComp;
        final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
        final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;
        return sizeB.compareTo(sizeA);
      });

      final bestStream = filteredList.first;
      final String nextStreamUrl = bestStream['resourceLink'] ?? bestStream['resource_link'] ?? '';
      final String nextResourceId = bestStream['resourceId'] ?? bestStream['resource_id'] ?? '';
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
            se: nextSeason,
            ep: nextEpisode,
          );
        } catch (e) {
          print("Failed loading next captions: $e");
        }
      }

      int nextNextSeason = nextSeason;
      int nextNextEpisode = nextEpisode + 1;
      bool hasNextNext = false;
      int maxEpOfSeason = 0;
      for (final s in _seasons) {
        if ((s['se'] ?? 0) == nextSeason) {
          maxEpOfSeason = (s['maxEp'] ?? 0) as int;
          break;
        }
      }

      if (nextNextEpisode <= maxEpOfSeason) {
        hasNextNext = true;
      } else {
        final followingSeason = _seasons.any((s) => (s['se'] ?? 0) == nextSeason + 1);
        if (followingSeason) {
          nextNextSeason = nextSeason + 1;
          nextNextEpisode = 1;
          hasNextNext = true;
        }
      }

      if (mounted) {
        setState(() {
          _selectedSeasonNumber = nextSeason;
          _selectedEpisodeNumber = nextEpisode;
          if (maxEpOfSeason > 0) _episodesCount = maxEpOfSeason;
        });
      }

      return PlayerNextEpisodeData(
        streamUrl: nextStreamUrl,
        title: _details?['title'] ?? _details?['subjectTitle'] ?? "Play Video",
        season: nextSeason,
        episode: nextEpisode,
        captions: nextCaptions,
        hasNextEpisode: hasNextNext,
        nextEpisodeLabel: hasNextNext ? "S$nextNextSeason:E$nextNextEpisode" : null,
      );
    } catch (e) {
      print("Error fetching next episode stream: $e");
      return null;
    }
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
            ),
          );
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

      if (mounted) {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PlayerScreen(
              streamUrl: streamUrl,
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
    final String resourceId = stream['resourceId'] ?? stream['resource_id'] ?? "";

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

  String _formatSize(dynamic bytes) {
    if (bytes == null) return "Unknown size";
    if (bytes is String && (bytes.contains('GB') || bytes.contains('MB') || bytes.contains('KB'))) {
      return bytes;
    }
    final int? sizeInt = int.tryParse(bytes.toString());
    if (sizeInt == null || sizeInt <= 0) return bytes.toString();
    final mb = sizeInt / (1024 * 1024);
    return "${mb.toStringAsFixed(0)}MB";
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isTv) ...[
            // Mobile layout wraps to avoid horizontal overflow
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
                if (_is4kHub)
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
          ] else ...[
            // TV Layout shows single row
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                if (_is4kHub) ...[
                  _buildBadge("4KHDHub · 4K UHD", Colors.cyanAccent, isTv: isTv),
                  const SizedBox(width: 8),
                ],
                if (_is4kHub && _details?['imdbRating'] != null && _details!['imdbRating'].isNotEmpty) ...[
                  _buildBadge("★ ${_details!['imdbRating']}", Colors.amber, isTv: isTv),
                  const SizedBox(width: 8),
                ] else if (!_is4kHub && rating != "-") ...[
                  _buildBadge("★ IMDb $rating", Colors.amber, isTv: isTv),
                  const SizedBox(width: 8),
                ],
                _buildBadge(_isTvShow ? "TV Series" : "Movie", Colors.redAccent, isTv: isTv),
                const SizedBox(width: 8),
                if (_details?['year'] != null)
                  _buildBadge("${_details!['year']}", Colors.grey, isTv: isTv)
                else
                  _buildBadge(releaseDate.toString().split('-')[0], Colors.grey, isTv: isTv),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            desc,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.grey.shade400,
              fontSize: isTv ? 16 : 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  void _showOptionsDialog<T>({
    required String title,
    required List<T> items,
    required T selectedValue,
    required String Function(T) itemLabel,
    required ValueChanged<T> onSelected,
  }) {
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
            constraints: const BoxConstraints(maxHeight: 400),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: items.map((item) {
                        final isSelected = item == selectedValue;
                        final label = itemLabel(item);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: TvFocusableCard(
                            onTap: () {
                              Navigator.pop(context);
                              onSelected(item);
                            },
                            borderRadius: BorderRadius.circular(10),
                            scaleFactor: 1.02,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              color: isSelected ? Colors.redAccent.shade700 : const Color(0xFF222222),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    label,
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: Colors.white, size: 18),
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
        );
      },
    );
  }

  Widget _buildSeasonAndEpisodeDropdowns({required bool isTv}) {
    final count = _episodesCount > 0 ? _episodesCount : 1;
    final currentEp = (_selectedEpisodeNumber >= 1 && _selectedEpisodeNumber <= count)
        ? _selectedEpisodeNumber
        : 1;
    final currentSeason = _seasons.any((s) => (s['se'] ?? 1) == _selectedSeasonNumber)
        ? _selectedSeasonNumber
        : (_seasons.isNotEmpty ? (_seasons.first['se'] ?? 1) : 1);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Row(
        children: [
          // Season Dropdown
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Season",
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.bold,
                    fontSize: isTv ? 15 : 13,
                  ),
                ),
                const SizedBox(height: 6),
                TvFocusableCard(
                  onTap: () {
                    _showOptionsDialog<int>(
                      title: "Select Season",
                      items: _seasons.map<int>((s) => (s['se'] ?? 1) as int).toList(),
                      selectedValue: currentSeason,
                      itemLabel: (sNum) => "Season $sNum",
                      onSelected: (newVal) {
                        final s = _seasons.firstWhere(
                          (element) => (element['se'] ?? 1) == newVal,
                          orElse: () => _seasons.first,
                        );
                        final maxEp = s['maxEp'] ?? 0;
                        _onSeasonChanged(newVal, maxEp);
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  scaleFactor: 1.03,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2C2C2C)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Season $currentSeason",
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: isTv ? 16 : 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.redAccent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Episode Dropdown
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Episode",
                  style: GoogleFonts.outfit(
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.bold,
                    fontSize: isTv ? 15 : 13,
                  ),
                ),
                const SizedBox(height: 6),
                TvFocusableCard(
                  onTap: () {
                    _showOptionsDialog<int>(
                      title: "Select Episode",
                      items: List.generate(count, (index) => index + 1),
                      selectedValue: currentEp,
                      itemLabel: (epNum) => "Episode $epNum",
                      onSelected: (newVal) {
                        _onEpisodeChanged(newVal);
                      },
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  scaleFactor: 1.03,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2C2C2C)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Episode $currentEp",
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: isTv ? 16 : 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, color: Colors.redAccent),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioDropdown({required bool isTv}) {
    if (_dubs.length <= 1) {
      return const SizedBox.shrink();
    }

    final currentDub = _dubs.firstWhere(
      (d) => _formatDubLabel(d) == _selectedAudioName || d['subjectId']?.toString() == _selectedSubjectId,
      orElse: () => _dubs.first,
    );
    final currentAudioLabel = _formatDubLabel(currentDub);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.record_voice_over_outlined, color: Colors.grey.shade400, size: isTv ? 18 : 16),
              const SizedBox(width: 8),
              Text(
                AppLanguageService.tr(en: "Audio Dubbing / Language", id: "Bahasa Sulih Suara (Audio)"),
                style: GoogleFonts.outfit(
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.bold,
                  fontSize: isTv ? 15 : 13,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                ),
                child: Text(
                  "${_dubs.length} ${AppLanguageService.tr(en: "Tracks", id: "Pilihan")}",
                  style: GoogleFonts.outfit(
                    color: Colors.redAccent,
                    fontSize: isTv ? 11 : 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TvFocusableCard(
            onTap: () {
              _showOptionsDialog<dynamic>(
                title: AppLanguageService.tr(en: "Select Audio Language", id: "Pilih Bahasa Audio"),
                items: _dubs,
                selectedValue: currentDub,
                itemLabel: (dub) => _formatDubLabel(dub),
                onSelected: (newDub) {
                  _onAudioChanged(newDub);
                },
              );
            },
            borderRadius: BorderRadius.circular(10),
            scaleFactor: 1.03,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        currentAudioLabel,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: isTv ? 16 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (currentDub['original'] == true) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.amber.withOpacity(0.4)),
                          ),
                          child: Text(
                            "ORIGINAL",
                            style: GoogleFonts.outfit(
                              color: Colors.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Icon(Icons.arrow_drop_down, color: Colors.redAccent),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentLayout(bool isTv) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(isTv: isTv),
          const Divider(color: Color(0xFF222222), height: 1),
          
          if (_isTvShow && _seasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSeasonAndEpisodeDropdowns(isTv: isTv),
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF222222), height: 1),
          ],
          
          if (_dubs.length > 1) ...[
            const SizedBox(height: 8),
            _buildAudioDropdown(isTv: isTv),
            const SizedBox(height: 8),
            const Divider(color: Color(0xFF222222), height: 1),
          ],
          
          Padding(
            padding: EdgeInsets.only(
              left: 24.0,
              top: 16.0,
              bottom: 8.0,
            ),
            child: Text(
              AppLanguageService.tr(en: "Available Streams", id: "Kualitas Video Tersedia"),
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: isTv ? 20 : 16,
              ),
            ),
          ),
          
          _isLoadingStreams
              ? SizedBox(
                  height: 150,
                  child: Center(
                    child: SpinKitRing(color: Colors.redAccent, size: isTv ? 48.0 : 36.0),
                  ),
                )
              : _streams.isEmpty
                  ? SizedBox(
                      height: 150,
                      child: Center(
                        child: Text(
                          "No streams found for this selection.",
                          style: GoogleFonts.outfit(color: Colors.grey, fontSize: isTv ? 18 : 14),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.symmetric(
                        horizontal: isTv ? 24 : 16,
                        vertical: 8,
                      ),
                      itemCount: _streams.length,
                      itemBuilder: (context, index) {
                        final stream = _streams[index];
                        final res = _is4kHub
                            ? (stream['quality'] ?? (stream['resolution'] != null ? "${stream['resolution']}p" : "HD"))
                            : (stream['resolution'] != null ? "${stream['resolution']}p" : "Unknown Res");
                        final sizeStr = _formatSize(stream['size']);
                        final codec = stream['codecName'] ?? stream['codec_name'] ?? "";
                        final codecLower = codec.toString().toLowerCase();
                        final isHevc = codecLower.contains('hevc') || codecLower.contains('h265') || codecLower.contains('h.265');
                        final epText = _isTvShow 
                            ? "S${stream['se'] ?? _selectedSeasonNumber}E${stream['ep'] ?? _selectedEpisodeNumber}  •  "
                            : "";

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: TvFocusableCard(
                            onTap: () => _playStream(stream),
                            borderRadius: BorderRadius.circular(8),
                            scaleFactor: 1.02,
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: isTv ? 24 : 20,
                                vertical: isTv ? 20 : 16,
                              ),
                              color: const Color(0xFF1E1E1E),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.play_circle_fill,
                                        color: Colors.redAccent.shade700,
                                        size: isTv ? 28 : 24,
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        "$epText$res",
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: isTv ? 20 : 16,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        sizeStr,
                                        style: GoogleFonts.outfit(
                                          color: Colors.grey.shade400,
                                          fontSize: isTv ? 18 : 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (codec.isNotEmpty)
                                    Text(
                                      isHevc ? "${codec.toString().toUpperCase()} (MAY FAIL)" : codec.toString().toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        color: isHevc ? Colors.amber.shade700 : Colors.grey.shade500,
                                        fontWeight: FontWeight.bold,
                                        fontSize: isTv ? 14 : 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
          
          // Pinned button spacer
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

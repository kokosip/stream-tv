import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/moviebox_api_service.dart';
import '../services/favorites_service.dart';
import '../widgets/tv_focusable_card.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  final String subjectId;

  const DetailScreen({super.key, required this.subjectId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final MovieBoxApiService _api = MovieBoxApiService();
  
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
      await FavoritesService.addFavorite(_details!);
    }
    _checkFavorite();
  }

  void _loadDetails() async {
    setState(() {
      _isLoadingDetails = true;
      _errorMessage = "";
    });

    try {
      final detailsRes = await _api.getDetails(subjectId: widget.subjectId);
      final type = detailsRes['subjectType'] ?? detailsRes['subject_type'];
      final isTvShow = type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';
      
      // Extract dubs list
      List<dynamic> dubsList = detailsRes['dubs'] ?? [];
      
      // If there are no dubs, add "Original" as placeholder
      if (dubsList.isEmpty) {
        dubsList = [
          {"lanName": "Original", "subjectId": widget.subjectId}
        ];
      } else {
        // Ensure "Original" is in the list
        bool hasOriginal = dubsList.any((d) => d['lanName'] == 'Original' || d['original'] == true);
        if (!hasOriginal) {
          dubsList = [
            {"lanName": "Original", "subjectId": widget.subjectId},
            ...dubsList
          ];
        }
      }

      List<dynamic> seasonsList = [];
      int initialEpisodesCount = 0;

      if (isTvShow) {
        try {
          final seasonsRes = await _api.getSeasonInfo(subjectId: widget.subjectId);
          seasonsList = seasonsRes['seasons'] ?? [];
          if (seasonsList.isNotEmpty) {
            _selectedSeasonNumber = seasonsList[0]['se'] ?? 1;
            initialEpisodesCount = seasonsList[0]['maxEp'] ?? 0;
          }
        } catch (e) {
          print("Failed to load seasons info: $e");
        }

        // Fallback if seasons list is empty but it's a TV show
        if (seasonsList.isEmpty) {
          final totalEp = detailsRes['episode'] ?? detailsRes['maxEp'] ?? 1;
          seasonsList = [
            {"se": 1, "maxEp": totalEp}
          ];
          _selectedSeasonNumber = 1;
          initialEpisodesCount = totalEp;
        }
      }

      setState(() {
        _details = detailsRes;
        _dubs = dubsList;
        _seasons = seasonsList;
        _episodesCount = initialEpisodesCount;
        _isLoadingDetails = false;
      });

      // Load available streams for the initial selection
      _loadStreams();

    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load details: $e";
        _isLoadingDetails = false;
      });
    }
  }

  void _loadStreams() async {
    setState(() {
      _isLoadingStreams = true;
      _streams = [];
    });

    try {
      final isTvShow = _isTvShow;
      final seNum = isTvShow ? _selectedSeasonNumber : 0;
      final epNum = isTvShow ? _selectedEpisodeNumber : 0;

      // Target resolutions to fetch concurrently
      final List<int> targetResolutions = [1080, 720, 480, 360];
      
      final List<Future<Map<String, dynamic>>> futures = targetResolutions.map((res) {
        return _api.getResources(
          subjectId: _selectedSubjectId,
          se: seNum,
          ep: epNum,
          resolution: res,
        );
      }).toList();

      final results = await Future.wait(futures);
      final List<dynamic> combinedList = [];
      
      for (final resData in results) {
        final List<dynamic> fileList = resData['list'] ?? [];
        combinedList.addAll(fileList);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load streams: $e')),
        );
      }
    }
  }

  void _onAudioChanged(String name, String subId) {
    setState(() {
      _selectedAudioName = name;
      _selectedSubjectId = subId;
    });
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

  void _playStream(Map<String, dynamic> stream) async {
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

    List<dynamic> captions = [];
    try {
      if (resourceId.isNotEmpty) {
        final subsRes = await _api.getExtCaptions(
          subjectId: _selectedSubjectId,
          resourceId: resourceId,
        );
        captions = subsRes['extCaptions'] ?? subsRes['external_captions'] ?? [];
      }
    } catch (e) {
      print("Failed to load subtitles: $e");
    }

    // Dismiss spinner
    if (mounted) {
      Navigator.pop(context);
    }

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PlayerScreen(
            streamUrl: streamUrl,
            title: _details?['title'] ?? _details?['subjectTitle'] ?? "Play Video",
            subjectId: _selectedSubjectId,
            season: _isTvShow ? _selectedSeasonNumber : 0,
            episode: _isTvShow ? _selectedEpisodeNumber : 0,
            captions: captions,
          ),
        ),
      );
    }
  }

  String _formatSize(dynamic bytes) {
    if (bytes == null) return "Unknown size";
    final int? sizeInt = int.tryParse(bytes.toString());
    if (sizeInt == null || sizeInt <= 0) return "Unknown size";
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
                _buildBadge("★ IMDb $rating", Colors.amber, isTv: isTv),
                _buildBadge(_isTvShow ? "TV Series" : "Movie", Colors.redAccent, isTv: isTv),
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
                _buildBadge("★ IMDb $rating", Colors.amber, isTv: isTv),
                const SizedBox(width: 8),
                _buildBadge(_isTvShow ? "TV Series" : "Movie", Colors.redAccent, isTv: isTv),
                const SizedBox(width: 8),
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
    final currentAudioName = _dubs.any((d) => (d['lanName'] ?? d['language'] ?? 'Unknown') == _selectedAudioName)
        ? _selectedAudioName
        : (_dubs.isNotEmpty ? (_dubs.first['lanName'] ?? _dubs.first['language'] ?? 'Original') : 'Original');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Audio Language",
            style: GoogleFonts.outfit(
              color: Colors.grey.shade400,
              fontWeight: FontWeight.bold,
              fontSize: isTv ? 15 : 13,
            ),
          ),
          const SizedBox(height: 6),
          TvFocusableCard(
            onTap: () {
              _showOptionsDialog<String>(
                title: "Select Audio Language",
                items: _dubs.map<String>((d) => (d['lanName'] ?? d['language'] ?? 'Unknown').toString()).toList(),
                selectedValue: currentAudioName,
                itemLabel: (name) => name,
                onSelected: (newName) {
                  final targetDub = _dubs.firstWhere(
                    (d) => (d['lanName'] ?? d['language'] ?? 'Unknown') == newName,
                    orElse: () => {"lanName": newName, "subjectId": widget.subjectId},
                  );
                  final subId = targetDub['subjectId'] ?? widget.subjectId;
                  _onAudioChanged(newName, subId);
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
                    currentAudioName,
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
          
          const SizedBox(height: 8),
          _buildAudioDropdown(isTv: isTv),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF222222), height: 1),
          
          Padding(
            padding: EdgeInsets.only(
              left: 24.0,
              top: 16.0,
              bottom: 8.0,
            ),
            child: Text(
              "Available Streams",
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
                        final res = stream['resolution'] != null ? "${stream['resolution']}p" : "Unknown Res";
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
        body: Center(
          child: Text(_errorMessage, style: GoogleFonts.outfit(color: Colors.grey, fontSize: 18)),
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

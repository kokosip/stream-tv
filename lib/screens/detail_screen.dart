import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/moviebox_api_service.dart';
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
  
  Map<String, dynamic>? _selectedStream;
  
  bool _isLoadingDetails = true;
  bool _isLoadingStreams = false;
  String _errorMessage = "";

  bool get _isTvShow {
    final type = _details?['subjectType'] ?? _details?['subject_type'];
    return type == 2 || type?.toString() == '2' || type?.toString().toLowerCase() == 'tv';
  }

  @override
  void initState() {
    super.initState();
    _selectedSubjectId = widget.subjectId;
    _loadDetails();
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
      _selectedStream = null;
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

      // Sort streams: descending by resolution, then descending by size
      finalStreams.sort((a, b) {
        final resComp = (b['resolution'] ?? 0).compareTo(a['resolution'] ?? 0);
        if (resComp != 0) return resComp;
        
        final sizeA = int.tryParse(a['size']?.toString() ?? '0') ?? 0;
        final sizeB = int.tryParse(b['size']?.toString() ?? '0') ?? 0;
        return sizeB.compareTo(sizeA);
      });

      setState(() {
        _streams = finalStreams;
        if (_streams.isNotEmpty) {
          _selectedStream = _streams[0];
        }
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

  void _playVideo() async {
    if (_selectedStream == null) return;
    
    final String streamUrl = _selectedStream!['resourceLink'] ?? _selectedStream!['resource_link'] ?? "";
    final String resourceId = _selectedStream!['resourceId'] ?? _selectedStream!['resource_id'] ?? "";

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

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          fontSize: 12,
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
                _buildBadge("★ IMDb $rating", Colors.amber),
                _buildBadge(_isTvShow ? "TV Series" : "Movie", Colors.redAccent),
                _buildBadge(releaseDate.toString().split('-')[0], Colors.grey),
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
                _buildBadge("★ IMDb $rating", Colors.amber),
                const SizedBox(width: 8),
                _buildBadge(_isTvShow ? "TV Series" : "Movie", Colors.redAccent),
                const SizedBox(width: 8),
                _buildBadge(releaseDate.toString().split('-')[0], Colors.grey),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            desc,
            maxLines: isTv ? 3 : 4,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.grey.shade400,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Text(
            "Seasons",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _seasons.length,
            itemBuilder: (context, index) {
              final s = _seasons[index];
              final sNum = s['se'] ?? 1;
              final maxEp = s['maxEp'] ?? 0;
              final isSelected = sNum == _selectedSeasonNumber;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TvFocusableCard(
                  onTap: () => _onSeasonChanged(sNum, maxEp),
                  borderRadius: BorderRadius.circular(24),
                  scaleFactor: 1.05,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: isSelected ? Colors.redAccent.shade700 : const Color(0xFF1E1E1E),
                    alignment: Alignment.center,
                    child: Text(
                      "Season $sNum",
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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

  Widget _buildEpisodeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Text(
            "Episodes",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _episodesCount,
            itemBuilder: (context, index) {
              final epNum = index + 1;
              final isSelected = epNum == _selectedEpisodeNumber;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TvFocusableCard(
                  onTap: () => _onEpisodeChanged(epNum),
                  borderRadius: BorderRadius.circular(24),
                  scaleFactor: 1.05,
                  child: Container(
                    width: 48,
                    height: 48,
                    color: isSelected ? Colors.redAccent.shade700 : const Color(0xFF1E1E1E),
                    alignment: Alignment.center,
                    child: Text(
                      "$epNum",
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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

  Widget _buildAudioSelectorHorizontal() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Text(
            "Audio Language",
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _dubs.length,
            itemBuilder: (context, index) {
              final d = _dubs[index];
              final name = d['lanName'] ?? d['language'] ?? "Unknown";
              final subId = d['subjectId'] ?? widget.subjectId;
              final isSelected = name == _selectedAudioName;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: TvFocusableCard(
                  onTap: () => _onAudioChanged(name, subId),
                  borderRadius: BorderRadius.circular(24),
                  scaleFactor: 1.05,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: isSelected ? Colors.redAccent.shade700 : const Color(0xFF1E1E1E),
                    alignment: Alignment.center,
                    child: Text(
                      name,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
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

  Widget _buildTvLayout() {
    return Column(
      children: [
        _buildHeaderSection(isTv: true),
        const Divider(color: Color(0xFF222222), height: 1),
        
        if (_isTvShow && _seasons.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildSeasonSelector(),
          const SizedBox(height: 12),
          _buildEpisodeSelector(),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF222222), height: 1),
        ],
        
        Expanded(
          child: Row(
            children: [
              // Left Panel: Audio Selection
              Container(
                width: 240,
                decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: Color(0xFF222222))),
                ),
                child: ListView.builder(
                  itemCount: _dubs.length,
                  itemBuilder: (context, index) {
                    final d = _dubs[index];
                    final name = d['lanName'] ?? d['language'] ?? "Unknown";
                    final subId = d['subjectId'] ?? widget.subjectId;
                    final isSelected = name == _selectedAudioName;

                    return Material(
                      color: isSelected ? Colors.redAccent.shade700.withOpacity(0.2) : Colors.transparent,
                      child: InkWell(
                        onTap: () => _onAudioChanged(name, subId),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                          child: Text(
                            name,
                            style: GoogleFonts.outfit(
                              color: isSelected ? Colors.redAccent : Colors.grey,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              // Right Panel: Streams
              Expanded(
                child: Container(
                  color: const Color(0xFF0F0F0F),
                  child: _isLoadingStreams
                      ? const Center(
                          child: SpinKitRing(color: Colors.redAccent, size: 36.0),
                        )
                      : _streams.isEmpty
                          ? Center(
                              child: Text(
                                "No streams found for this selection.",
                                style: GoogleFonts.outfit(color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: _streams.length,
                              itemBuilder: (context, index) {
                                final stream = _streams[index];
                                final res = stream['resolution'] != null ? "${stream['resolution']}p" : "Unknown Res";
                                final sizeStr = _formatSize(stream['size']);
                                final codec = stream['codecName'] ?? stream['codec_name'] ?? "";
                                final isSelected = stream == _selectedStream;
                                final epText = _isTvShow 
                                    ? "S${stream['se'] ?? _selectedSeasonNumber}E${stream['ep'] ?? _selectedEpisodeNumber}  •  "
                                    : "";

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12.0),
                                  child: TvFocusableCard(
                                    onTap: () {
                                      setState(() {
                                        _selectedStream = stream;
                                      });
                                    },
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                      color: isSelected 
                                          ? Colors.redAccent.shade700.withOpacity(0.15) 
                                          : const Color(0xFF1E1E1E),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                "$epText$res",
                                                style: GoogleFonts.outfit(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 18,
                                                ),
                                              ),
                                              const SizedBox(width: 16),
                                              Text(
                                                sizeStr,
                                                style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 16),
                                              ),
                                            ],
                                          ),
                                          if (codec.isNotEmpty)
                                            Text(
                                              codec.toString().toUpperCase(),
                                              style: GoogleFonts.outfit(
                                                color: Colors.grey.shade500,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14,
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
              ),
            ],
          ),
        ),
        
        // Pinned button spacer
        const SizedBox(height: 100),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderSection(isTv: false),
          const Divider(color: Color(0xFF222222), height: 1),
          
          if (_isTvShow && _seasons.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSeasonSelector(),
            const SizedBox(height: 12),
            _buildEpisodeSelector(),
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF222222), height: 1),
          ],
          
          const SizedBox(height: 12),
          _buildAudioSelectorHorizontal(),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF222222), height: 1),
          
          Padding(
            padding: const EdgeInsets.only(left: 24.0, top: 16.0, bottom: 8.0),
            child: Text(
              "Available Streams",
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          
          _isLoadingStreams
              ? const SizedBox(
                  height: 150,
                  child: Center(
                    child: SpinKitRing(color: Colors.redAccent, size: 36.0),
                  ),
                )
              : _streams.isEmpty
                  ? SizedBox(
                      height: 150,
                      child: Center(
                        child: Text(
                          "No streams found for this selection.",
                          style: GoogleFonts.outfit(color: Colors.grey),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: _streams.length,
                      itemBuilder: (context, index) {
                        final stream = _streams[index];
                        final res = stream['resolution'] != null ? "${stream['resolution']}p" : "Unknown Res";
                        final sizeStr = _formatSize(stream['size']);
                        final codec = stream['codecName'] ?? stream['codec_name'] ?? "";
                        final isSelected = stream == _selectedStream;
                        final epText = _isTvShow 
                            ? "S${stream['se'] ?? _selectedSeasonNumber}E${stream['ep'] ?? _selectedEpisodeNumber}  •  "
                            : "";

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: TvFocusableCard(
                            onTap: () {
                              setState(() {
                                _selectedStream = stream;
                              });
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              color: isSelected 
                                  ? Colors.redAccent.shade700.withOpacity(0.15) 
                                  : const Color(0xFF1E1E1E),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        "$epText$res",
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        sizeStr,
                                        style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  if (codec.isNotEmpty)
                                    Text(
                                      codec.toString().toUpperCase(),
                                      style: GoogleFonts.outfit(
                                        color: Colors.grey.shade500,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
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
          const SizedBox(height: 100),
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
                child: isTv ? _buildTvLayout() : _buildMobileLayout(),
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

          // PLAY ACTION BAR
          if (_selectedStream != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16.0),
                color: const Color(0xFF0A0A0A).withOpacity(0.9),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TvFocusableCard(
                      onTap: _playVideo,
                      borderRadius: BorderRadius.circular(8),
                      scaleFactor: 1.05,
                      child: Container(
                        color: Colors.redAccent.shade700,
                        padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'PLAY VIDEO',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
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
    );
  }
}

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
      final isTvShow = detailsRes['subjectType'] == 'tv' || detailsRes['subject_type'] == 'tv';
      
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
          initialEpisodesCount = detailsRes['episode'] ?? detailsRes['maxEp'] ?? 0;
        }
      }

      setState(() {
        _details = detailsRes;
        _dubs = dubsList;
        _seasons = seasonsList;
        _episodesCount = initialEpisodesCount;
        _isLoadingDetails = false;
      });

      // Load available streams for the initial selection (e.g. Original audio, episode 1)
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

    final isTvShow = _details?['subjectType'] == 'tv' || _details?['subject_type'] == 'tv';

    try {
      final res = await _api.getResources(
        subjectId: _selectedSubjectId,
        se: isTvShow ? _selectedSeasonNumber : 0,
        ep: isTvShow ? _selectedEpisodeNumber : 0,
      );

      final List<dynamic> fileList = res['list'] ?? [];
      
      // Sort streams: descending by resolution
      fileList.sort((a, b) => (b['resolution'] ?? 0).compareTo(a['resolution'] ?? 0));

      setState(() {
        _streams = fileList;
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

    final title = _details?['title'] ?? _details?['subjectTitle'] ?? "Untitled";
    final desc = _details?['description'] ?? "No description available.";
    final isTvShow = _details?['subjectType'] == 'tv' || _details?['subject_type'] == 'tv';
    final releaseDate = _details?['releaseDate'] ?? _details?['release_date'] ?? "-";
    final rating = _details?['imdbRatingValue'] ?? _details?['imdbRate'] ?? "-";

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: Stack(
        children: [
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

          // Detail Content Scroll
          Positioned.fill(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(top: 60.0),
                child: Column(
                  children: [
                    // TOP ROW: Title & Synopsis info matching TUI header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                style: GoogleFonts.outfit(
                                  fontSize: isTv ? 32 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 16),
                              _buildBadge("★ IMDb $rating", Colors.amber),
                              const SizedBox(width: 8),
                              _buildBadge(isTvShow ? "TV Series" : "Movie", Colors.redAccent),
                              const SizedBox(width: 8),
                              _buildBadge(releaseDate.toString().split('-')[0], Colors.grey),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            desc,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: Colors.grey.shade400,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Divider(color: Color(0xFF222222), height: 1),

                    // MIDDLE ROW: Episode Selection (Only for TV Shows)
                    if (isTvShow && _seasons.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Row(
                          children: [
                            // Seasons Dropdown / List
                            Text(
                              "Season:",
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<int>(
                              value: _selectedSeasonNumber,
                              dropdownColor: const Color(0xFF1E1E1E),
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                              underline: const SizedBox(),
                              items: _seasons.map<DropdownMenuItem<int>>((s) {
                                final sNum = s['se'] ?? 1;
                                return DropdownMenuItem<int>(
                                  value: sNum,
                                  child: Text("Season $sNum"),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final selectedS = _seasons.firstWhere((s) => s['se'] == val);
                                  _onSeasonChanged(val, selectedS['maxEp'] ?? 0);
                                }
                              },
                            ),
                            const SizedBox(width: 32),
                            // Episode List Label
                            Text(
                              "Episode:",
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 12),
                            DropdownButton<int>(
                              value: _selectedEpisodeNumber,
                              dropdownColor: const Color(0xFF1E1E1E),
                              style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),
                              underline: const SizedBox(),
                              items: List.generate(_episodesCount, (index) => index + 1)
                                  .map<DropdownMenuItem<int>>((epNum) {
                                return DropdownMenuItem<int>(
                                  value: epNum,
                                  child: Text("Episode $epNum"),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  _onEpisodeChanged(val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const Divider(color: Color(0xFF222222), height: 1),
                    ],

                    // BOTTOM ROW: Audio & Streams grid selection (Matches screenshot)
                    Expanded(
                      child: Row(
                        children: [
                          // Left Panel: Audio Selection
                          Container(
                            width: isTv ? 240 : 150,
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

                          // Right Panel: Available Streams / Resolution List
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
                                                            res,
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

                    // PLAY ACTION BAR (Matches TUI "Enter Play" option)
                    if (_selectedStream != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16.0),
                        color: const Color(0xFF0A0A0A),
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
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
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
}

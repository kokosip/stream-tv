import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final List<dynamic> captions;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    this.captions = const [],
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  Timer? _hideTimer;
  
  String? _selectedSubtitleUrl;
  List<dynamic> _availableSubtitles = [];
  List<SubtitleEntry> _subtitleEntries = [];

  void _loadSubtitles(String url) async {
    if (url.isEmpty) return;
    setState(() {
      _subtitleEntries = [];
    });

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final decoded = utf8.decode(response.bodyBytes);
        final entries = parseSrt(decoded);
        setState(() {
          _subtitleEntries = entries;
        });
      }
    } catch (e) {
      print("Failed to load subtitles: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    // Parse captions list
    _availableSubtitles = widget.captions;
    
    // Auto-select English or first subtitle if available
    if (_availableSubtitles.isNotEmpty) {
      final englishSub = _availableSubtitles.firstWhere(
        (sub) => sub['lan'] == 'en' || sub['lan'] == 'eng',
        orElse: () => _availableSubtitles[0],
      );
      _selectedSubtitleUrl = englishSub['url'];
    }

    if (_selectedSubtitleUrl != null) {
      _loadSubtitles(_selectedSubtitleUrl!);
    }

    _initializePlayer();
    _startHideTimer();
  }

  void _initializePlayer() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl));
    
    try {
      await _controller.initialize();
      setState(() {
        _isInitialized = true;
      });
      _controller.play();
      _controller.addListener(_videoListener);
    } catch (e) {
      setState(() {
        _isInitialized = false;
      });
      _showErrorDialog("Failed to initialize video player: $e");
    }
  }

  void _videoListener() {
    // Force rebuild on position update to move progress bar
    if (mounted) setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startHideTimer();
    }
  }

  void _seekRelative(Duration offset) {
    if (!_isInitialized) return;
    final currentPosition = _controller.value.position;
    final targetPosition = currentPosition + offset;
    _controller.seekTo(targetPosition);
    _startHideTimer();
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
    _startHideTimer();
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Playback Error', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(msg, style: GoogleFonts.outfit(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close player
            },
            child: Text('OK', style: GoogleFonts.outfit(color: Colors.redAccent)),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_videoListener);
    _controller.dispose();
    
    // Restore default system UI modes when exiting fullscreen player
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide status bar and force landscape mode inside player
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    String currentSubText = "";
    if (_isInitialized && _subtitleEntries.isNotEmpty) {
      final pos = _controller.value.position;
      final activeEntry = _subtitleEntries.firstWhere(
        (entry) => pos >= entry.start && pos <= entry.end,
        orElse: () => SubtitleEntry(start: Duration.zero, end: Duration.zero, text: ""),
      );
      currentSubText = activeEntry.text;
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            // TV Remote Keycode mappings
            if (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space) {
              _togglePlayPause();
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              _seekRelative(const Duration(seconds: -10)); // Rewind 10s
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              _seekRelative(const Duration(seconds: 10)); // Fast forward 10s
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.escape ||
                event.logicalKey == LogicalKeyboardKey.backspace) {
              Navigator.pop(context);
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Video Player
              if (_isInitialized)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                )
              else
                const Center(
                  child: SpinKitRing(
                    color: Colors.redAccent,
                    size: 60.0,
                  ),
                ),

              // 2. Custom Subtitles Overlay
              if (_selectedSubtitleUrl != null && _isInitialized && currentSubText.isNotEmpty)
                Positioned(
                  bottom: _showControls ? 90 : 30,
                  left: 40,
                  right: 40,
                  child: Center(
                    child: Text(
                      currentSubText,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        color: Colors.yellowAccent,
                        fontWeight: FontWeight.bold,
                        shadows: const [
                          Shadow(
                            offset: Offset(-1.5, -1.5),
                            color: Colors.black,
                          ),
                          Shadow(
                            offset: Offset(1.5, -1.5),
                            color: Colors.black,
                          ),
                          Shadow(
                            offset: Offset(1.5, 1.5),
                            color: Colors.black,
                          ),
                          Shadow(
                            offset: Offset(-1.5, 1.5),
                            color: Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // 3. Player UI Overlays (Title, progress, and controls)
              AnimatedOpacity(
                opacity: _showControls ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Container(
                    color: Colors.black.withOpacity(0.5),
                    child: Stack(
                      children: [
                        // Top Bar: Back & Title
                        Positioned(
                          top: 24,
                          left: 24,
                          right: 24,
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                                onPressed: () => Navigator.pop(context),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                                // Subtitle Selector Button
                                if (_availableSubtitles.isNotEmpty)
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.subtitles, color: Colors.white, size: 28),
                                    color: const Color(0xFF1E1E1E),
                                    onSelected: (url) {
                                      if (url.isEmpty) {
                                        setState(() {
                                          _selectedSubtitleUrl = null;
                                          _subtitleEntries = [];
                                        });
                                      } else {
                                        setState(() {
                                          _selectedSubtitleUrl = url;
                                        });
                                        _loadSubtitles(url);
                                      }
                                    },
                                    itemBuilder: (context) {
                                      return [
                                        PopupMenuItem<String>(
                                          value: "",
                                          child: Text(
                                            "Off",
                                            style: GoogleFonts.outfit(
                                              color: _selectedSubtitleUrl == null ? Colors.redAccent : Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        ..._availableSubtitles.map((sub) {
                                          final label = sub['lanName'] ?? sub['language'] ?? "Unknown";
                                          return PopupMenuItem<String>(
                                            value: sub['url'],
                                            child: Text(
                                              label,
                                              style: GoogleFonts.outfit(
                                                color: _selectedSubtitleUrl == sub['url'] ? Colors.redAccent : Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          );
                                        }),
                                      ];
                                    },
                                  ),
                            ],
                          ),
                        ),

                        // Center Controls: Play/Pause, Rewind, Fast Forward
                        Align(
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.replay_10, color: Colors.white, size: 48),
                                onPressed: () => _seekRelative(const Duration(seconds: -10)),
                              ),
                              const SizedBox(width: 48),
                              IconButton(
                                icon: Icon(
                                  _isInitialized && _controller.value.isPlaying
                                      ? Icons.pause_circle_filled
                                      : Icons.play_circle_filled,
                                  color: Colors.redAccent,
                                  size: 72,
                                ),
                                onPressed: _togglePlayPause,
                              ),
                              const SizedBox(width: 48),
                              IconButton(
                                icon: const Icon(Icons.forward_10, color: Colors.white, size: 48),
                                onPressed: () => _seekRelative(const Duration(seconds: 10)),
                              ),
                            ],
                          ),
                        ),

                        // Bottom Bar: Progress Bar & Timestamps
                        Positioned(
                          bottom: 24,
                          left: 24,
                          right: 24,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Progress slider
                              if (_isInitialized)
                                VideoProgressIndicator(
                                  _controller,
                                  allowScrubbing: true,
                                  colors: VideoProgressColors(
                                    playedColor: Colors.redAccent.shade700,
                                    bufferedColor: Colors.white.withOpacity(0.3),
                                    backgroundColor: Colors.white.withOpacity(0.1),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              // Timestamps
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDuration(_controller.value.position),
                                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                                  ),
                                  Text(
                                    _formatDuration(_controller.value.duration),
                                    style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                                  ),
                                ],
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
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (duration.inHours > 0) {
      return "${duration.inHours}:${twoDigits(minutes)}:${twoDigits(seconds)}";
    }
    return "${twoDigits(minutes)}:${twoDigits(seconds)}";
  }
}

class SubtitleEntry {
  final Duration start;
  final Duration end;
  final String text;
  SubtitleEntry({required this.start, required this.end, required this.text});
}

List<SubtitleEntry> parseSrt(String srtContent) {
  final List<SubtitleEntry> entries = [];
  final blocks = srtContent.replaceAll('\r\n', '\n').split('\n\n');

  for (final block in blocks) {
    final lines = block.trim().split('\n');
    if (lines.length < 2) continue;

    int timeLineIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains(' --> ')) {
        timeLineIndex = i;
        break;
      }
    }
    if (timeLineIndex == -1) continue;

    try {
      final times = lines[timeLineIndex].split(' --> ');
      final start = _parseSrtTime(times[0]);
      final end = _parseSrtTime(times[1]);
      
      final text = lines.sublist(timeLineIndex + 1).join('\n').replaceAll(RegExp(r'<[^>]*>'), '');

      entries.add(SubtitleEntry(start: start, end: end, text: text));
    } catch (_) {
      // Ignore malformed blocks
    }
  }
  return entries;
}

Duration _parseSrtTime(String timeStr) {
  final cleanStr = timeStr.trim().replaceAll(',', '.');
  final parts = cleanStr.split(':');
  
  if (parts.length == 2) {
    // MM:SS.mmm
    final minutes = int.parse(parts[0]);
    final secondsParts = parts[1].split('.');
    final seconds = int.parse(secondsParts[0]);
    final milliseconds = int.parse(secondsParts[1]);
    return Duration(minutes: minutes, seconds: seconds, milliseconds: milliseconds);
  } else if (parts.length == 3) {
    // HH:MM:SS.mmm
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final secondsParts = parts[2].split('.');
    final seconds = int.parse(secondsParts[0]);
    final milliseconds = int.parse(secondsParts[1]);
    return Duration(hours: hours, minutes: minutes, seconds: seconds, milliseconds: milliseconds);
  }
  throw FormatException("Invalid time format: $timeStr");
}

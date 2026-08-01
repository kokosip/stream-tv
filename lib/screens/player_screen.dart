import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import '../widgets/tv_focusable_card.dart';
import '../services/playback_progress_service.dart';

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String subjectId;
  final int season;
  final int episode;
  final List<dynamic> captions;
  final String? coverUrl;
  final int? subjectType;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.subjectId,
    this.season = 0,
    this.episode = 0,
    this.captions = const [],
    this.coverUrl,
    this.subjectType,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;
  late final VideoController _controller;
  final List<StreamSubscription> _subscriptions = [];
  final ValueNotifier<Duration> _positionNotifier = ValueNotifier(Duration.zero);
  
  bool _isInitialized = false;
  bool _showControls = true;
  Timer? _hideTimer;
  
  bool _isDragging = false;
  double _dragValue = 0.0;
  
  // ignore: unused_field
  Timer? _progressSaveTimer;
  String? _resumeMessage;
  
  String? _selectedSubtitleUrl;
  List<dynamic> _availableSubtitles = [];
  List<SubtitleEntry> _subtitleEntries = [];
  static const MethodChannel _pipChannel = MethodChannel('com.koko.moviebox/pip');
  bool _isPipMode = false;
  Color _selectedSubtitleColor = Colors.white;
  BoxFit _selectedFitMode = BoxFit.contain;

  final Map<String, Color> _subtitleColors = {
    'White': Colors.white,
    'Yellow': Colors.yellowAccent,
    'Cyan': Colors.cyanAccent,
    'Green': Colors.greenAccent,
    'Pink': Colors.pinkAccent,
  };

  final Map<String, BoxFit> _fitModes = {
    'Fit (Default)': BoxFit.contain,
    'Zoom (Fill Screen)': BoxFit.cover,
    'Stretch (Full)': BoxFit.fill,
  };

  // FocusNodes for Android TV Remote Navigation
  late FocusNode _backFocusNode;
  late FocusNode _subtitleFocusNode;
  late FocusNode _subtitleColorFocusNode;
  late FocusNode _fitModeFocusNode;
  late FocusNode _pipFocusNode;
  late FocusNode _rewindFocusNode;
  late FocusNode _playPauseFocusNode;
  late FocusNode _forwardFocusNode;
  late FocusNode _sliderFocusNode;
  
  // GlobalKeys to programmatically open PopupMenuButtons
  final GlobalKey<PopupMenuButtonState<String>> _popupMenuKey = GlobalKey();
  final GlobalKey<PopupMenuButtonState<Color>> _colorPopupMenuKey = GlobalKey();
  final GlobalKey<PopupMenuButtonState<BoxFit>> _fitMenuKey = GlobalKey();

  void _enterPipMode() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (e) {
      print("Failed to enter PiP mode: $e");
    }
  }

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
    
    // Initialize MediaKit Player and Controller with 16MB buffer size for TV RAM optimization
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024,
      ),
    );
    _controller = VideoController(_player);

    // Initialize focus nodes
    _backFocusNode = FocusNode();
    _subtitleFocusNode = FocusNode();
    _subtitleColorFocusNode = FocusNode();
    _fitModeFocusNode = FocusNode();
    _pipFocusNode = FocusNode();
    _rewindFocusNode = FocusNode();
    _playPauseFocusNode = FocusNode();
    _forwardFocusNode = FocusNode();
    _sliderFocusNode = FocusNode();

    // Listen for Picture-in-Picture mode changes from native Android
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'pipModeChanged') {
        final isInPip = call.arguments as bool? ?? false;
        if (mounted) {
          setState(() {
            _isPipMode = isInPip;
            if (isInPip) {
              _showControls = false;
            }
          });
        }
      }
    });

    // Notify native Android that video player is active for auto-PiP
    _pipChannel.invokeMethod('setPipEnabled', {'enabled': true});

    // Autofocus play/pause button on screen load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _playPauseFocusNode.requestFocus();
    });

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
    
    // Save progress periodically every 5 seconds
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _saveCurrentProgress();
    });
  }

  void _initializePlayer() async {
    try {
      // Enable hardware decoding and performance tweaks on Android
      if (_player.platform is NativePlayer) {
        final platform = _player.platform as NativePlayer;
        await platform.setProperty('hwdec', 'mediacodec');
        await platform.setProperty('vd-lavc-fast', 'yes');
        await platform.setProperty('vd-lavc-skiploopfilter', 'all');
      }

      // Check for saved progress
      final savedMs = await PlaybackProgressService.getProgress(
        widget.subjectId,
        widget.season,
        widget.episode,
      );
      bool didResume = false;

      // Listen to error stream
      _subscriptions.add(
        _player.stream.error.listen((error) {
          print("MediaKit Playback Error: $error");
          
          // Ignore non-fatal codec/decoder initialization errors as libmpv 
          // will natively fall back to a working decoder and play smoothly.
          final errStr = error.toString().toLowerCase();
          if (errStr.contains("codec") || errStr.contains("decoder")) {
            return;
          }
          
          _showErrorDialog(error.toString());
        }),
      );

      // Listen to completed stream
      _subscriptions.add(
        _player.stream.completed.listen((completed) {
          if (completed) {
            Navigator.pop(context);
          }
        }),
      );

      // Listen to position changes (updates notifier, avoids rebuilding the entire screen)
      _subscriptions.add(
        _player.stream.position.listen((pos) {
          _positionNotifier.value = pos;
          if (mounted) {
            final dur = _player.state.duration;
            if (dur != Duration.zero && !_isInitialized) {
              setState(() {
                _isInitialized = true;
              });
              
              if (savedMs > 0 && !didResume) {
                didResume = true;
                _player.seek(Duration(milliseconds: savedMs));
                _showResumeToast(savedMs);
              }
            }
          }
        }),
      );

      // Listen to duration changes
      _subscriptions.add(
        _player.stream.duration.listen((dur) {
          if (mounted) setState(() {});
        }),
      );

      // Open media and start playback
      await _player.open(Media(widget.streamUrl));
    } catch (e) {
      _showErrorDialog("Failed to initialize video player: $e");
    }
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
    final currentPosition = _player.state.position;
    final targetPosition = currentPosition + offset;
    _player.seek(targetPosition);
    _startHideTimer();
  }

  void _togglePlayPause() {
    if (!_isInitialized) return;
    setState(() {
      if (_player.state.playing) {
        _player.pause();
      } else {
        _player.play();
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

  void _showResumeToast(int ms) {
    final duration = Duration(milliseconds: ms);
    setState(() {
      _resumeMessage = "Resuming from ${_formatDuration(duration)}";
    });
    Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _resumeMessage = null;
        });
      }
    });
  }

  void _saveCurrentProgress() {
    if (!_isInitialized) return;
    final posMs = _player.state.position.inMilliseconds;
    final durMs = _player.state.duration.inMilliseconds;
    if (posMs > 0 && durMs > 0) {
      PlaybackProgressService.saveProgress(
        widget.subjectId,
        widget.season,
        widget.episode,
        posMs,
        durMs,
        title: widget.title,
        coverUrl: widget.coverUrl,
        subjectType: widget.subjectType,
      );
    }
  }

  @override
  void dispose() {
    _pipChannel.invokeMethod('setPipEnabled', {'enabled': false});
    _hideTimer?.cancel();
    for (final s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();
    _positionNotifier.dispose();
    
    // Dispose focus nodes
    _backFocusNode.dispose();
    _subtitleFocusNode.dispose();
    _subtitleColorFocusNode.dispose();
    _fitModeFocusNode.dispose();
    _pipFocusNode.dispose();
    _rewindFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _forwardFocusNode.dispose();
    _sliderFocusNode.dispose();
    
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

    // Subtitle rendering and position tracking are now handled inside ValueListenableBuilders below
    // to prevent heavy UI rebuilds on every position change.

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        autofocus: true,
        onKeyEvent: (FocusNode node, KeyEvent event) {
          if (event is KeyDownEvent) {
            // Show controls on any key press if they are hidden
            if (!_showControls) {
              setState(() {
                _showControls = true;
              });
              _startHideTimer();
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _playPauseFocusNode.requestFocus();
              });
              return KeyEventResult.handled;
            }
            
            // Restart hide timer on any key press
            _startHideTimer();

            // Handle back/escape to exit player
            if (event.logicalKey == LogicalKeyboardKey.escape ||
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
              Center(
                child: Video(
                  controller: _controller,
                  controls: null,
                  fit: _selectedFitMode,
                ),
              ),

              // Loading spinner if not initialized yet
              if (!_isInitialized)
                const Center(
                  child: SpinKitRing(
                    color: Colors.redAccent,
                    size: 60.0,
                  ),
                ),

              // 2. Custom Subtitles Overlay
              if (_selectedSubtitleUrl != null && _isInitialized && !_isPipMode)
                Positioned(
                  bottom: _showControls ? 90 : 30,
                  left: 40,
                  right: 40,
                  child: ValueListenableBuilder<Duration>(
                    valueListenable: _positionNotifier,
                    builder: (context, pos, child) {
                      final currentSubText = _getSubtitleAt(pos);
                      if (currentSubText.isEmpty) return const SizedBox.shrink();
                      return Center(
                        child: Text(
                          currentSubText,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: 18,
                            color: _selectedSubtitleColor,
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
                                offset: Offset(-1.5, 1.5),
                                color: Colors.black,
                              ),
                              Shadow(
                                offset: Offset(1.5, 1.5),
                                color: Colors.black,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 3. Player UI Overlays (Title, progress, and controls)
              if (!_isPipMode)
                AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: FocusScope(
                    canRequestFocus: _showControls,
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
                                TvFocusableCard(
                                  focusNode: _backFocusNode,
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () => Navigator.pop(context),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.arrow_back, color: Colors.white, size: 28),
                                  ),
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
                                if (_availableSubtitles.isNotEmpty) ...[
                                  TvFocusableCard(
                                    focusNode: _subtitleFocusNode,
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () {
                                      _popupMenuKey.currentState?.showButtonMenu();
                                    },
                                    child: IgnorePointer(
                                      child: PopupMenuButton<String>(
                                        key: _popupMenuKey,
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
                                        child: const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Icon(Icons.subtitles, color: Colors.white, size: 28),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Subtitle Color Button
                                  TvFocusableCard(
                                    focusNode: _subtitleColorFocusNode,
                                    borderRadius: BorderRadius.circular(24),
                                    onTap: () {
                                      _colorPopupMenuKey.currentState?.showButtonMenu();
                                    },
                                    child: IgnorePointer(
                                      child: PopupMenuButton<Color>(
                                        key: _colorPopupMenuKey,
                                        color: const Color(0xFF1E1E1E),
                                        onSelected: (color) {
                                          setState(() {
                                            _selectedSubtitleColor = color;
                                          });
                                        },
                                        itemBuilder: (context) {
                                          return _subtitleColors.entries.map((entry) {
                                            final isSelected = _selectedSubtitleColor == entry.value;
                                            return PopupMenuItem<Color>(
                                              value: entry.value,
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 16,
                                                    height: 16,
                                                    decoration: BoxDecoration(
                                                      color: entry.value,
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: Colors.white38),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    entry.key,
                                                    style: GoogleFonts.outfit(
                                                      color: isSelected ? Colors.redAccent : Colors.white,
                                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList();
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Icon(Icons.palette, color: Colors.white, size: 28),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 12),
                                // Aspect Ratio / Screen Zoom Fit Button
                                TvFocusableCard(
                                  focusNode: _fitModeFocusNode,
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: () {
                                    _fitMenuKey.currentState?.showButtonMenu();
                                  },
                                  child: IgnorePointer(
                                    child: PopupMenuButton<BoxFit>(
                                      key: _fitMenuKey,
                                      color: const Color(0xFF1E1E1E),
                                      onSelected: (mode) {
                                        setState(() {
                                          _selectedFitMode = mode;
                                        });
                                      },
                                      itemBuilder: (context) {
                                        return _fitModes.entries.map((entry) {
                                          final isSelected = _selectedFitMode == entry.value;
                                          return PopupMenuItem<BoxFit>(
                                            value: entry.value,
                                            child: Text(
                                              entry.key,
                                              style: GoogleFonts.outfit(
                                                color: isSelected ? Colors.redAccent : Colors.white,
                                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          );
                                        }).toList();
                                      },
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(Icons.aspect_ratio, color: Colors.white, size: 28),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Picture-in-Picture (PiP) Button
                                TvFocusableCard(
                                  focusNode: _pipFocusNode,
                                  borderRadius: BorderRadius.circular(24),
                                  onTap: _enterPipMode,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 28),
                                  ),
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
                                TvFocusableCard(
                                  focusNode: _rewindFocusNode,
                                  borderRadius: BorderRadius.circular(32),
                                  onTap: () => _seekRelative(const Duration(seconds: -10)),
                                  child: const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: Icon(Icons.replay_10, color: Colors.white, size: 48),
                                  ),
                                ),
                                const SizedBox(width: 48),
                                TvFocusableCard(
                                  focusNode: _playPauseFocusNode,
                                  borderRadius: BorderRadius.circular(40),
                                  onTap: _togglePlayPause,
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Icon(
                                      _isInitialized && _player.state.playing
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_filled,
                                      color: Colors.redAccent,
                                      size: 72,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 48),
                                TvFocusableCard(
                                  focusNode: _forwardFocusNode,
                                  borderRadius: BorderRadius.circular(32),
                                  onTap: () => _seekRelative(const Duration(seconds: 10)),
                                  child: const Padding(
                                    padding: EdgeInsets.all(12.0),
                                    child: Icon(Icons.forward_10, color: Colors.white, size: 48),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Bottom Bar: Progress Bar & Timestamps
                          Positioned(
                            bottom: 24,
                            left: 24,
                            right: 24,
                            child: ValueListenableBuilder<Duration>(
                              valueListenable: _positionNotifier,
                              builder: (context, pos, child) {
                                final dur = _player.state.duration;
                                final displayPos = _isDragging
                                    ? Duration(milliseconds: _dragValue.toInt())
                                    : pos;
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Progress slider
                                    if (_isInitialized)
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 4.0,
                                          activeTrackColor: Colors.redAccent.shade700,
                                          inactiveTrackColor: Colors.white.withOpacity(0.1),
                                          thumbColor: Colors.redAccent,
                                          overlayColor: Colors.redAccent.withOpacity(0.2),
                                          thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 6.0,
                                          ),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                                          trackShape: const CustomTrackShape(),
                                        ),
                                        child: Slider(
                                          value: (_isDragging ? _dragValue : pos.inMilliseconds.toDouble())
                                              .clamp(0.0, dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1.0),
                                          min: 0.0,
                                          max: dur.inMilliseconds.toDouble() > 0 ? dur.inMilliseconds.toDouble() : 1.0,
                                          focusNode: _sliderFocusNode,
                                          onChanged: (value) {
                                            setState(() {
                                              _isDragging = true;
                                              _dragValue = value;
                                            });
                                            _startHideTimer();
                                          },
                                          onChangeEnd: (value) {
                                            _player.seek(Duration(milliseconds: value.toInt())).then((_) {
                                              setState(() {
                                                _isDragging = false;
                                              });
                                            });
                                            _startHideTimer();
                                          },
                                        ),
                                      ),
                                    const SizedBox(height: 8),
                                    // Timestamps
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _formatDuration(displayPos),
                                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                                        ),
                                        Text(
                                          _formatDuration(dur),
                                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 14),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              
              // 4. Resume Toast Overlay
              if (_resumeMessage != null)
                Align(
                  alignment: Alignment.topCenter,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 80.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 1),
                        ),
                        child: Text(
                          _resumeMessage!,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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

  String _getSubtitleAt(Duration pos) {
    if (_subtitleEntries.isEmpty) return "";
    
    int low = 0;
    int high = _subtitleEntries.length - 1;
    while (low <= high) {
      int mid = (low + high) >> 1;
      final entry = _subtitleEntries[mid];
      if (pos >= entry.start && pos <= entry.end) {
        return entry.text;
      } else if (pos < entry.start) {
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return "";
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

class CustomTrackShape extends RoundedRectSliderTrackShape {
  const CustomTrackShape();
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 4.0;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
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

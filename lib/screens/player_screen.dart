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
import '../services/app_language_service.dart';

class PlayerNextEpisodeData {
  final String streamUrl;
  final String title;
  final int season;
  final int episode;
  final List<dynamic> captions;
  final bool hasNextEpisode;
  final String? nextEpisodeLabel;

  PlayerNextEpisodeData({
    required this.streamUrl,
    required this.title,
    required this.season,
    required this.episode,
    this.captions = const [],
    this.hasNextEpisode = false,
    this.nextEpisodeLabel,
  });
}

class PlayerScreen extends StatefulWidget {
  final String streamUrl;
  final String title;
  final String subjectId;
  final int season;
  final int episode;
  final List<dynamic> captions;
  final String? coverUrl;
  final int? subjectType;
  final String provider;
  final int maxEpisodesInSeason;
  final bool hasNextEpisode;
  final String? nextEpisodeLabel;
  final Future<PlayerNextEpisodeData?> Function()? onFetchNextEpisode;

  const PlayerScreen({
    super.key,
    required this.streamUrl,
    required this.title,
    required this.subjectId,
    this.provider = 'moviebox',
    this.season = 0,
    this.episode = 0,
    this.captions = const [],
    this.coverUrl,
    this.subjectType,
    this.maxEpisodesInSeason = 0,
    this.hasNextEpisode = false,
    this.nextEpisodeLabel,
    this.onFetchNextEpisode,
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
  
  // Dynamic episode & playback state
  late String _currentTitle;
  late int _currentSeason;
  late int _currentEpisode;
  late bool _hasNextEpisode;
  String? _nextEpisodeLabel;

  // Auto-next episode countdown state
  bool _showNextEpisodeOverlay = false;
  int _nextEpisodeCountdown = 8;
  Timer? _nextEpisodeTimer;
  bool _isSwitchingNextEpisode = false;
  late FocusNode _playNextFocusNode;

  String? _selectedSubtitleUrl;
  List<dynamic> _availableSubtitles = [];
  List<SubtitleEntry> _subtitleEntries = [];
  static const MethodChannel _pipChannel = MethodChannel('com.koko.moviebox/pip');
  bool _isPipMode = false;
  bool _isErrorDialogShowing = false;
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

    _currentTitle = widget.title;
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;
    _hasNextEpisode = widget.hasNextEpisode;
    _nextEpisodeLabel = widget.nextEpisodeLabel;
    _playNextFocusNode = FocusNode();

    // Parse and clean captions list
    _setupSubtitles(widget.captions);

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
        // Auto-reconnect on network drops for HLS / HTTP streams to prevent ffurl_read timeouts
        await platform.setProperty('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5');
        await platform.setProperty('demuxer-max-bytes', '33554432');
        await platform.setProperty('demuxer-max-back-bytes', '16777216');
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
          
          final errStr = error.toString().toLowerCase();
          
          // Ignore transient network, protocol, demuxer, and decoder warnings.
          // Libmpv and FFmpeg automatically retry and reconnect seamlessly under the hood.
          final isTransient = errStr.contains("tcp") ||
              errStr.contains("ffurl") ||
              errStr.contains("http") ||
              errStr.contains("tls") ||
              errStr.contains("timeout") ||
              errStr.contains("timed out") ||
              errStr.contains("reset") ||
              errStr.contains("pipe") ||
              errStr.contains("demuxer") ||
              errStr.contains("lavf") ||
              errStr.contains("hls") ||
              errStr.contains("eof") ||
              errStr.contains("codec") ||
              errStr.contains("decoder") ||
              errStr.contains("mediacodec") ||
              errStr.contains("0xffffff");

          // Never interrupt active or initialized playback with non-fatal / transient errors
          if (isTransient || _player.state.playing || _isInitialized) {
            return;
          }
          
          _showErrorDialog(error.toString());
        }),
      );

      // Listen to completed stream
      _subscriptions.add(
        _player.stream.completed.listen((completed) {
          if (completed) {
            if (_hasNextEpisode && !_isSwitchingNextEpisode) {
              _triggerNextEpisodeCountdown();
            } else {
              if (mounted) {
                Navigator.pop(context, {
                  'completed': true,
                  'season': _currentSeason,
                  'episode': _currentEpisode,
                });
              }
            }
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

            // Check for Smart Next Episode overlay trigger (watched >= 90% or last 25s)
            if (_isInitialized && _hasNextEpisode && !_showNextEpisodeOverlay && !_isSwitchingNextEpisode) {
              final durMs = dur.inMilliseconds;
              final posMs = pos.inMilliseconds;
              if (durMs > 0 && (posMs >= durMs * 0.90 || (durMs - posMs) <= 25000)) {
                _triggerNextEpisodeCountdown();
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
    if (!mounted || _isErrorDialogShowing) return;
    _isErrorDialogShowing = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text('Playback Error', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(msg, style: GoogleFonts.outfit(color: Colors.grey)),
        actions: [
          TextButton(
            onPressed: () {
              _isErrorDialogShowing = false;
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Close player
            },
            child: Text('OK', style: GoogleFonts.outfit(color: Colors.redAccent)),
          )
        ],
      ),
    ).then((_) {
      _isErrorDialogShowing = false;
    });
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
        _currentSeason,
        _currentEpisode,
        posMs,
        durMs,
        title: _currentTitle,
        coverUrl: widget.coverUrl,
        subjectType: widget.subjectType,
        maxEpisodesInSeason: widget.maxEpisodesInSeason > 0 ? widget.maxEpisodesInSeason : null,
        provider: widget.provider,
      );
    }
  }

  @override
  void dispose() {
    _pipChannel.invokeMethod('setPipEnabled', {'enabled': false});
    _hideTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _progressSaveTimer?.cancel();
    _saveCurrentProgress();

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
    _playNextFocusNode.dispose();
    
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
              Navigator.pop(context, {
                'season': _currentSeason,
                'episode': _currentEpisode,
              });
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
                                  onTap: () => Navigator.pop(context, {
                                    'season': _currentSeason,
                                    'episode': _currentEpisode,
                                  }),
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.arrow_back, color: Colors.white, size: 28),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    (_currentSeason > 0 || _currentEpisode > 0)
                                        ? "$_currentTitle • S$_currentSeason E$_currentEpisode"
                                        : _currentTitle,
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
                                              final label = sub['normalizedLan'] ??
                                                            sub['lanName'] ?? 
                                                            sub['language'] ?? 
                                                            sub['lan'] ?? 
                                                            sub['lang'] ?? 
                                                            "Subtitle";
                                              final subUrl = (sub['url'] ?? sub['link'] ?? sub['src'] ?? sub['path'] ?? '').toString();
                                              if (subUrl.isEmpty) return null;

                                              final isSelected = _selectedSubtitleUrl == subUrl;
                                              return PopupMenuItem<String>(
                                                value: subUrl,
                                                child: Text(
                                                  label.toString(),
                                                  style: GoogleFonts.outfit(
                                                    color: isSelected ? Colors.redAccent : Colors.white,
                                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                  ),
                                                ),
                                              );
                                            }).whereType<PopupMenuItem<String>>(),
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

              // 5. Smart Next Episode Floating Overlay
              if (_showNextEpisodeOverlay && _hasNextEpisode)
                _buildNextEpisodeOverlay(),

              // 6. Switching Next Episode Spinner
              if (_isSwitchingNextEpisode)
                _buildSwitchingNextOverlay(),
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

  static String normalizeSubtitleLanguage(dynamic sub) {
    if (sub is! Map) return "Subtitle";
    final raw = (sub['lanName'] ?? 
                 sub['language'] ?? 
                 sub['lan'] ?? 
                 sub['lang'] ?? 
                 sub['name'] ?? 
                 sub['disName'] ?? 
                 sub['title'] ?? 
                 'Unknown').toString().trim();
                 
    final lower = raw.toLowerCase();
    if (lower == 'in' || lower == 'in_id' || lower == 'id' || lower == 'ina' || lower.contains('indonesia')) {
      return "Indonesian";
    }
    if (lower == 'en' || lower == 'eng' || lower.contains('english') || lower.contains('inggris')) {
      return "English";
    }
    if (lower == 'es' || lower == 'spa' || lower.contains('spanish') || lower.contains('spanyol') || lower.contains('espanol')) {
      return "Spanish";
    }
    if (lower == 'fr' || lower == 'fra' || lower == 'fre' || lower.contains('french') || lower.contains('prancis') || lower.contains('francais')) {
      return "French";
    }
    if (lower == 'de' || lower == 'deu' || lower == 'ger' || lower.contains('german') || lower.contains('jerman') || lower.contains('deutsch')) {
      return "German";
    }
    if (lower == 'ja' || lower == 'jpn' || lower.contains('japanese') || lower.contains('jepang')) {
      return "Japanese";
    }
    if (lower == 'ko' || lower == 'kor' || lower.contains('korean') || lower.contains('korea')) {
      return "Korean";
    }
    if (lower == 'zh' || lower == 'chi' || lower == 'zho' || lower.contains('chinese') || lower.contains('mandarin')) {
      return "Chinese";
    }
    if (lower == 'ar' || lower == 'ara' || lower.contains('arabic') || lower.contains('arab')) {
      return "Arabic";
    }
    if (lower == 'hi' || lower == 'hin' || lower.contains('hindi')) {
      return "Hindi";
    }
    if (lower == 'pt' || lower == 'por' || lower.contains('portuguese') || lower.contains('portugis')) {
      return "Portuguese";
    }
    if (lower == 'ru' || lower == 'rus' || lower.contains('russian') || lower.contains('rusia')) {
      return "Russian";
    }
    if (lower == 'th' || lower == 'tha' || lower.contains('thai')) {
      return "Thai";
    }
    if (lower == 'vi' || lower == 'vie' || lower.contains('vietnamese') || lower.contains('vietnam')) {
      return "Vietnamese";
    }
    if (lower == 'ms' || lower == 'msa' || lower == 'may' || lower.contains('malay') || lower.contains('melayu')) {
      return "Malay";
    }
    if (lower == 'tl' || lower == 'tgl' || lower == 'fil' || lower.contains('filipino') || lower.contains('tagalog')) {
      return "Filipino";
    }
    return raw.isNotEmpty ? raw : "Subtitle";
  }

  void _setupSubtitles(List<dynamic> rawCaptions) {
    final List<dynamic> cleanSubs = [];
    final Set<String> seenUrls = {};

    for (final sub in rawCaptions) {
      if (sub is! Map) continue;
      final url = (sub['url'] ?? sub['link'] ?? sub['src'] ?? sub['path'] ?? '').toString().trim();
      if (url.isEmpty || url.contains('aa348f2541d13ffe')) continue;

      final rawSize = sub['size'];
      int size = 0;
      if (rawSize is num) {
        size = rawSize.toInt();
      } else if (rawSize != null) {
        size = int.tryParse(rawSize.toString()) ?? 0;
      }
      // Filter dummy/empty 34-50 byte caption placeholder files
      if (size > 0 && size <= 50) continue;

      final normalizedLang = normalizeSubtitleLanguage(sub);
      if (normalizedLang == 'Indonesian' && size > 0 && size <= 100) continue;

      if (seenUrls.add(url)) {
        final entry = Map<String, dynamic>.from(sub);
        entry['normalizedLan'] = normalizedLang;
        cleanSubs.add(entry);
      }
    }

    _availableSubtitles = cleanSubs;

    if (_availableSubtitles.isNotEmpty) {
      // Prioritize Indonesian if app language is 'id', else English, else first
      final isIdLang = AppLanguageService.currentLanguage.value == 'id';
      final preferred = _availableSubtitles.firstWhere(
        (sub) => sub['normalizedLan'] == (isIdLang ? 'Indonesian' : 'English'),
        orElse: () => _availableSubtitles.firstWhere(
          (sub) => sub['normalizedLan'] == (isIdLang ? 'English' : 'Indonesian'),
          orElse: () => _availableSubtitles[0],
        ),
      );
      _selectedSubtitleUrl = preferred['url'] ?? preferred['link'];
    } else {
      _selectedSubtitleUrl = null;
    }

    if (_selectedSubtitleUrl != null) {
      _loadSubtitles(_selectedSubtitleUrl!);
    }
  }

  void _triggerNextEpisodeCountdown() {
    if (_showNextEpisodeOverlay || _isSwitchingNextEpisode || !_hasNextEpisode) return;
    setState(() {
      _showNextEpisodeOverlay = true;
      _nextEpisodeCountdown = 8;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _playNextFocusNode.requestFocus();
      }
    });

    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_nextEpisodeCountdown <= 1) {
        timer.cancel();
        _playNextEpisode();
      } else {
        setState(() {
          _nextEpisodeCountdown--;
        });
      }
    });
  }

  void _playNextEpisode() async {
    _nextEpisodeTimer?.cancel();
    if (_isSwitchingNextEpisode) return;

    setState(() {
      _isSwitchingNextEpisode = true;
      _showNextEpisodeOverlay = false;
    });

    // Save current episode progress as completed
    _saveCurrentProgress();

    if (widget.onFetchNextEpisode != null) {
      try {
        final nextData = await widget.onFetchNextEpisode!();
        if (nextData != null && mounted) {
          setState(() {
            _currentTitle = nextData.title;
            _currentSeason = nextData.season;
            _currentEpisode = nextData.episode;
            _hasNextEpisode = nextData.hasNextEpisode;
            _nextEpisodeLabel = nextData.nextEpisodeLabel;
            _isSwitchingNextEpisode = false;
            _isInitialized = false;
          });

          _setupSubtitles(nextData.captions);
          await _player.open(Media(nextData.streamUrl));
          _startHideTimer();
          return;
        }
      } catch (e) {
        print("Failed switching to next episode: $e");
      }
    }

    // If no seamless handler or fetch failed, exit back to DetailScreen with next cue
    if (mounted) {
      Navigator.pop(context, {
        'completed': true,
        'playNext': true,
        'season': _currentSeason,
        'episode': _currentEpisode,
      });
    }
  }

  Widget _buildNextEpisodeOverlay() {
    final label = _nextEpisodeLabel ?? "Next Episode";

    return Positioned(
      bottom: 90,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF141414).withOpacity(0.95),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.redAccent.withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 16,
                spreadRadius: 4,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.skip_next, color: Colors.redAccent, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      "${_nextEpisodeCountdown}s",
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                AppLanguageService.tr(
                  en: "Next episode will play automatically",
                  id: "Episode selanjutnya akan otomatis diputar",
                ),
                style: GoogleFonts.outfit(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TvFocusableCard(
                      focusNode: _playNextFocusNode,
                      onTap: _playNextEpisode,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                            const SizedBox(width: 4),
                            Text(
                              AppLanguageService.tr(en: "Play Now", id: "Putar Sekarang"),
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  TvFocusableCard(
                    onTap: () {
                      _nextEpisodeTimer?.cancel();
                      setState(() {
                        _showNextEpisodeOverlay = false;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF262626),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF383838)),
                      ),
                      child: Text(
                        AppLanguageService.tr(en: "Cancel", id: "Batal"),
                        style: GoogleFonts.outfit(
                          color: Colors.grey.shade300,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchingNextOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.75),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SpinKitRing(color: Colors.redAccent, size: 48.0),
            const SizedBox(height: 16),
            Text(
              AppLanguageService.tr(
                en: "Loading next episode...",
                id: "Memuat episode berikutnya...",
              ),
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 16),
            ),
          ],
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

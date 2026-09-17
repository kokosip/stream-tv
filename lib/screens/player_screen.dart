import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import '../widgets/tv_focusable_card.dart';
import '../widgets/subtitle_search_dialog.dart';
import '../services/playback_progress_service.dart';
import '../services/app_language_service.dart';
import '../services/analytics_service.dart';

class PlayerSwitchAudioResult {
  final String streamUrl;
  final String audioName;
  final List<dynamic> captions;
  final List<dynamic> availableStreams;
  final Map<String, dynamic>? currentStream;

  PlayerSwitchAudioResult({
    required this.streamUrl,
    required this.audioName,
    this.captions = const [],
    this.availableStreams = const [],
    this.currentStream,
  });
}

class PlayerNextEpisodeData {
  final String streamUrl;
  final String title;
  final int season;
  final int episode;
  final List<dynamic> captions;
  final bool hasNextEpisode;
  final String? nextEpisodeLabel;
  final List<dynamic> availableStreams;
  final Map<String, dynamic>? currentStream;
  final String? currentAudioName;

  PlayerNextEpisodeData({
    required this.streamUrl,
    required this.title,
    required this.season,
    required this.episode,
    this.captions = const [],
    this.hasNextEpisode = false,
    this.nextEpisodeLabel,
    this.availableStreams = const [],
    this.currentStream,
    this.currentAudioName,
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
  final List<dynamic> dubs;
  final String? currentAudioName;
  final List<dynamic> availableStreams;
  final Map<String, dynamic>? currentStream;
  final List<dynamic> seasons;
  final Future<PlayerSwitchAudioResult?> Function(dynamic dub)? onSwitchAudio;
  final Future<String?> Function(Map<String, dynamic> stream)? onSwitchQuality;
  final Future<PlayerNextEpisodeData?> Function(int season, int episode)? onSelectEpisode;
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
    this.dubs = const [],
    this.currentAudioName,
    this.availableStreams = const [],
    this.currentStream,
    this.seasons = const [],
    this.onSwitchAudio,
    this.onSwitchQuality,
    this.onSelectEpisode,
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
  bool _nextEpisodeDismissed = false;
  late FocusNode _playNextFocusNode;
  late FocusNode _cancelNextFocusNode;

  // In-player audio, quality, and episode state
  late List<dynamic> _dubs;
  String? _currentAudioName;
  late List<dynamic> _availableStreams;
  Map<String, dynamic>? _currentStream;
  late List<dynamic> _seasons;

  bool _isSwitchingAudio = false;
  bool _isSwitchingQuality = false;

  late FocusNode _audioFocusNode;
  late FocusNode _qualityFocusNode;
  late FocusNode _episodesFocusNode;

  final GlobalKey<PopupMenuButtonState<dynamic>> _audioPopupMenuKey = GlobalKey<PopupMenuButtonState<dynamic>>();
  final GlobalKey<PopupMenuButtonState<Map<String, dynamic>>> _qualityPopupMenuKey = GlobalKey<PopupMenuButtonState<Map<String, dynamic>>>();

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

  // Screen Orientation state (defaults to Landscape, can be toggled to Portrait during playback)
  bool _isPortrait = false;
  late FocusNode _orientationFocusNode;

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

  Map<String, String>? _extractStreamHeaders(Map<String, dynamic>? stream) {
    if (stream == null) return null;
    if (stream['headers'] is Map) {
      final rawMap = stream['headers'] as Map;
      return rawMap.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    final signCookie = stream['signCookie']?.toString();
    if (signCookie != null && signCookie.isNotEmpty) {
      return {
        'User-Agent': 'com.community.oneroom/50020118 (Linux; U; Android 12; en_US; Redmi 2201117TG; Build/S1B.220414.015; Cronet/135.0.7012.3)',
        'Referer': 'https://sportslive.wine',
        'Cookie': signCookie.trim(),
      };
    }
    return null;
  }

  void _enterPipMode() async {
    try {
      await _pipChannel.invokeMethod('enterPip');
    } catch (e) {
      print("Failed to enter PiP mode: $e");
    }
  }

  void _toggleOrientation() {
    setState(() {
      _isPortrait = !_isPortrait;
    });
    if (_isPortrait) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    _startHideTimer();
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

  Future<void> _openOnlineSubtitleSearch() async {
    _hideTimer?.cancel();
    final result = await SubtitleSearchDialog.show(
      context,
      initialTitle: _currentTitle,
      season: _currentSeason,
      episode: _currentEpisode,
    );

    if (result != null && mounted) {
      final entries = parseSrt(result.srtContent);
      if (entries.isNotEmpty) {
        final customSubEntry = {
          'url': result.item.url,
          'normalizedLan': "${result.item.languageName} (Online)",
          'lanName': result.item.languageName,
          'isOnline': true,
        };

        setState(() {
          _subtitleEntries = entries;
          _selectedSubtitleUrl = result.item.url;
          if (!_availableSubtitles.any((s) => s['url'] == result.item.url)) {
            _availableSubtitles.insert(0, customSubEntry);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLanguageService.tr(
                en: "Applied subtitle: ${result.item.languageName} (${result.item.releaseName})",
                id: "Subtitle diterapkan: ${result.item.languageName} (${result.item.releaseName})",
              ),
              style: GoogleFonts.outfit(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF1E1E1E),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    _startHideTimer();
  }

  @override
  void initState() {
    super.initState();
    
    // Force default landscape mode and immersive sticky mode upon entering player
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // Initialize MediaKit Player and Controller with 32MB buffer size for TV streaming stability
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024,
      ),
    );
    _controller = VideoController(_player);

    // Initialize focus nodes
    _backFocusNode = FocusNode();
    _subtitleFocusNode = FocusNode();
    _subtitleColorFocusNode = FocusNode();
    _fitModeFocusNode = FocusNode();
    _orientationFocusNode = FocusNode();
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

    // Track playback event in Analytics
    final String contentType = (widget.subjectType == 2 || widget.episode > 0) ? 'series' : 'movie';
    AnalyticsService.logPlayContent(
      title: widget.title,
      contentType: contentType,
      episode: widget.episode > 0 ? 'S${widget.season}E${widget.episode}' : null,
    );

    _currentTitle = widget.title;
    _currentSeason = widget.season;
    _currentEpisode = widget.episode;
    _hasNextEpisode = widget.hasNextEpisode;
    _nextEpisodeLabel = widget.nextEpisodeLabel;
    _playNextFocusNode = FocusNode();
    _cancelNextFocusNode = FocusNode();

    _dubs = List.from(widget.dubs);
    _currentAudioName = widget.currentAudioName;
    _availableStreams = List.from(widget.availableStreams);
    _currentStream = widget.currentStream;
    _seasons = List.from(widget.seasons);

    _audioFocusNode = FocusNode();
    _qualityFocusNode = FocusNode();
    _episodesFocusNode = FocusNode();

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
      // Enable hardware decoding and performance tweaks on Android TV
      if (_player.platform is NativePlayer) {
        final platform = _player.platform as NativePlayer;
        // 'auto-safe' tries safe mediacodec/mediacodec-copy methods compatible with TV texture rendering
        await platform.setProperty('hwdec', 'auto-safe');
        await platform.setProperty('hwdec-codecs', 'all');
        // Drop late frames at VO level instead of accumulating lag or stutter
        await platform.setProperty('framedrop', 'vo');
        // Fast decode and skip loop filter for non-reference frames to preserve CPU/GPU
        await platform.setProperty('vd-lavc-fast', 'yes');
        await platform.setProperty('vd-lavc-skiploopfilter', 'all');
        // Utilize 4 threads if software decoding fallback occurs on quad-core TV chipsets
        await platform.setProperty('vd-lavc-threads', '4');
        // Forcibly allow seeking on HTTP streams and enable fast keyframe seeking
        await platform.setProperty('force-seekable', 'yes');
        await platform.setProperty('hr-seek', 'yes');
        await platform.setProperty('hr-seek-framedrop', 'yes');
        // Auto-reconnect on network drops for HLS / HTTP streams to prevent ffurl_read timeouts, enable seeking
        await platform.setProperty('demuxer-lavf-o', 'reconnect=1,reconnect_streamed=1,reconnect_delay_max=5,seekable=1');
        // Demuxer cache optimizations: 64MB buffer and 30s readahead to absorb Wi-Fi jitter on TV
        await platform.setProperty('demuxer-max-bytes', '67108864');
        await platform.setProperty('demuxer-max-back-bytes', '16777216');
        await platform.setProperty('demuxer-readahead-secs', '30');
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
            if (_hasNextEpisode && !_isSwitchingNextEpisode && !_nextEpisodeDismissed) {
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

            final durMs = dur.inMilliseconds;
            final posMs = pos.inMilliseconds;

            // Reset dismissed state if user rewinds back before the end credits zone
            if (durMs > 0 && posMs < durMs * 0.85) {
              _nextEpisodeDismissed = false;
            }

            // Check for Smart Next Episode overlay trigger (watched >= 90% or last 25s)
            if (_isInitialized && _hasNextEpisode && !_showNextEpisodeOverlay && !_isSwitchingNextEpisode && !_nextEpisodeDismissed) {
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
      final headers = _extractStreamHeaders(_currentStream ?? widget.currentStream);
      await _player.open(Media(widget.streamUrl, httpHeaders: headers));
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
    _orientationFocusNode.dispose();
    _pipFocusNode.dispose();
    _rewindFocusNode.dispose();
    _playPauseFocusNode.dispose();
    _forwardFocusNode.dispose();
    _sliderFocusNode.dispose();
    _playNextFocusNode.dispose();
    _cancelNextFocusNode.dispose();
    _audioFocusNode.dispose();
    _qualityFocusNode.dispose();
    _episodesFocusNode.dispose();
    
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

  List<Widget> _buildTopBarActionButtons({required bool isPortrait}) {
    final List<Widget> buttons = [];
    final double iconSize = isPortrait ? 22 : 28;
    final EdgeInsets btnPadding = EdgeInsets.all(isPortrait ? 6.0 : 8.0);
    final double spacing = isPortrait ? 6 : 12;

    // Episodes Drawer Button (TV Series)
    if (_seasons.isNotEmpty || _currentSeason > 0) {
      buttons.add(
        TvFocusableCard(
          focusNode: _episodesFocusNode,
          borderRadius: BorderRadius.circular(24),
          onTap: _showEpisodeModal,
          child: Padding(
            padding: btnPadding,
            child: Icon(Icons.video_library, color: Colors.white, size: iconSize),
          ),
        ),
      );
      buttons.add(SizedBox(width: spacing));
    }

    // Audio Dub Selector Button
    if (_dubs.isNotEmpty && widget.onSwitchAudio != null) {
      buttons.add(
        TvFocusableCard(
          focusNode: _audioFocusNode,
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            _audioPopupMenuKey.currentState?.showButtonMenu();
          },
          child: IgnorePointer(
            child: PopupMenuButton<dynamic>(
              key: _audioPopupMenuKey,
              color: const Color(0xFF1E1E1E),
              onSelected: (dub) => _switchAudio(dub),
              itemBuilder: (context) {
                return _dubs.map((dub) {
                  final label = _formatDubLabel(dub);
                  final isSelected = label == _currentAudioName;
                  return PopupMenuItem<dynamic>(
                    value: dub,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.outfit(
                            color: isSelected ? Colors.redAccent : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check, color: Colors.redAccent, size: 18),
                      ],
                    ),
                  );
                }).toList();
              },
              child: Padding(
                padding: btnPadding,
                child: Icon(Icons.audiotrack, color: Colors.white, size: iconSize),
              ),
            ),
          ),
        ),
      );
      buttons.add(SizedBox(width: spacing));
    }

    // Video Quality Selector Button
    if (_availableStreams.isNotEmpty) {
      buttons.add(
        TvFocusableCard(
          focusNode: _qualityFocusNode,
          borderRadius: BorderRadius.circular(24),
          onTap: () {
            _qualityPopupMenuKey.currentState?.showButtonMenu();
          },
          child: IgnorePointer(
            child: PopupMenuButton<Map<String, dynamic>>(
              key: _qualityPopupMenuKey,
              color: const Color(0xFF1E1E1E),
              onSelected: (stream) => _switchQuality(stream),
              itemBuilder: (context) {
                return _availableStreams.map((s) {
                  final mapStream = Map<String, dynamic>.from(s is Map ? s : {});
                  final label = _formatStreamQualityLabel(mapStream);
                  final isSelected = _currentStream != null &&
                      ((_currentStream!['resourceId'] != null && _currentStream!['resourceId'] == mapStream['resourceId']) ||
                       (_currentStream!['url'] != null && _currentStream!['url'] == mapStream['url']) ||
                       (_currentStream!['resourceLink'] != null && _currentStream!['resourceLink'] == mapStream['resourceLink']));
                  return PopupMenuItem<Map<String, dynamic>>(
                    value: mapStream,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          label,
                          style: GoogleFonts.outfit(
                            color: isSelected ? Colors.redAccent : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check, color: Colors.redAccent, size: 18),
                      ],
                    ),
                  );
                }).toList();
              },
              child: Padding(
                padding: btnPadding,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.high_quality, color: Colors.white, size: iconSize),
                    if (_currentStream != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        _formatShortQualityLabel(_currentStream),
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: isPortrait ? 10 : 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      buttons.add(SizedBox(width: spacing));
    }

    // Subtitle Selector Button (Always available with in-app online search)
    buttons.add(
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
              if (url == "__search_online__") {
                _openOnlineSubtitleSearch();
              } else if (url.isEmpty) {
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
                  value: "__search_online__",
                  child: Row(
                    children: [
                      const Icon(Icons.search, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        AppLanguageService.tr(
                          en: "Search Online Subtitles...",
                          id: "Cari Subtitle Online...",
                        ),
                        style: GoogleFonts.outfit(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
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
            child: Padding(
              padding: btnPadding,
              child: Icon(
                Icons.subtitles,
                color: _selectedSubtitleUrl != null ? Colors.redAccent : Colors.white,
                size: iconSize,
              ),
            ),
          ),
        ),
      ),
    );
    buttons.add(SizedBox(width: spacing));

    // Subtitle Color Button
    if (_availableSubtitles.isNotEmpty || _subtitleEntries.isNotEmpty) {
      buttons.add(
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
              child: Padding(
                padding: btnPadding,
                child: Icon(Icons.palette, color: Colors.white, size: iconSize),
              ),
            ),
          ),
        ),
      );
      buttons.add(SizedBox(width: spacing));
    }

    // Aspect Ratio / Screen Zoom Fit Button
    buttons.add(
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
            child: Padding(
              padding: btnPadding,
              child: Icon(Icons.aspect_ratio, color: Colors.white, size: iconSize),
            ),
          ),
        ),
      ),
    );
    buttons.add(SizedBox(width: spacing));

    // Screen Orientation Toggle Button (Default Landscape, toggleable to Portrait during playback)
    buttons.add(
      TvFocusableCard(
        focusNode: _orientationFocusNode,
        borderRadius: BorderRadius.circular(24),
        onTap: _toggleOrientation,
        child: Tooltip(
          message: _isPortrait
              ? AppLanguageService.tr(en: "Switch to Landscape", id: "Ubah ke Lanskap")
              : AppLanguageService.tr(en: "Switch to Portrait", id: "Ubah ke Potret"),
          child: Padding(
            padding: btnPadding,
            child: Icon(
              _isPortrait ? Icons.stay_current_landscape : Icons.stay_current_portrait,
              color: _isPortrait ? Colors.redAccent : Colors.white,
              size: iconSize,
            ),
          ),
        ),
      ),
    );
    buttons.add(SizedBox(width: spacing));

    // Picture-in-Picture (PiP) Button
    buttons.add(
      TvFocusableCard(
        focusNode: _pipFocusNode,
        borderRadius: BorderRadius.circular(24),
        onTap: _enterPipMode,
        child: Padding(
          padding: btnPadding,
          child: Icon(Icons.picture_in_picture_alt, color: Colors.white, size: iconSize),
        ),
      ),
    );

    return buttons;
  }

  @override
  Widget build(BuildContext context) {
    // Hide status bar inside player
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait || _isPortrait;
    final topInset = mediaQuery.padding.top;
    final bottomInset = mediaQuery.padding.bottom;

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
                  bottom: _showControls
                      ? (isPortrait ? (bottomInset > 0 ? bottomInset + 80 : 80) : 90)
                      : (isPortrait ? (bottomInset > 0 ? bottomInset + 30 : 30) : 30),
                  left: isPortrait ? 20 : 40,
                  right: isPortrait ? 20 : 40,
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
                            fontSize: isPortrait ? 16 : 18,
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
                          // Top Bar: Back, Title & Action Controls
                          if (isPortrait)
                            Positioned(
                              top: topInset > 0 ? topInset + 6 : 16,
                              left: 16,
                              right: 16,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      TvFocusableCard(
                                        focusNode: _backFocusNode,
                                        borderRadius: BorderRadius.circular(24),
                                        onTap: () => Navigator.pop(context, {
                                          'season': _currentSeason,
                                          'episode': _currentEpisode,
                                        }),
                                        child: const Padding(
                                          padding: EdgeInsets.all(6.0),
                                          child: Icon(Icons.arrow_back, color: Colors.white, size: 24),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          (_currentSeason > 0 || _currentEpisode > 0)
                                              ? "$_currentTitle • S$_currentSeason E$_currentEpisode"
                                              : _currentTitle,
                                          style: GoogleFonts.outfit(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: _buildTopBarActionButtons(isPortrait: true),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
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
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Flexible(
                                    child: SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: _buildTopBarActionButtons(isPortrait: false),
                                      ),
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
                                  child: Padding(
                                    padding: EdgeInsets.all(isPortrait ? 8.0 : 12.0),
                                    child: Icon(Icons.replay_10, color: Colors.white, size: isPortrait ? 40 : 48),
                                  ),
                                ),
                                SizedBox(width: isPortrait ? 28 : 48),
                                TvFocusableCard(
                                  focusNode: _playPauseFocusNode,
                                  borderRadius: BorderRadius.circular(40),
                                  onTap: _togglePlayPause,
                                  child: Padding(
                                    padding: EdgeInsets.all(isPortrait ? 8.0 : 12.0),
                                    child: Icon(
                                      _isInitialized && _player.state.playing
                                          ? Icons.pause_circle_filled
                                          : Icons.play_circle_filled,
                                      color: Colors.redAccent,
                                      size: isPortrait ? 60 : 72,
                                    ),
                                  ),
                                ),
                                SizedBox(width: isPortrait ? 28 : 48),
                                TvFocusableCard(
                                  focusNode: _forwardFocusNode,
                                  borderRadius: BorderRadius.circular(32),
                                  onTap: () => _seekRelative(const Duration(seconds: 10)),
                                  child: Padding(
                                    padding: EdgeInsets.all(isPortrait ? 8.0 : 12.0),
                                    child: Icon(Icons.forward_10, color: Colors.white, size: isPortrait ? 40 : 48),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Bottom Bar: Progress Bar & Timestamps
                          Positioned(
                            bottom: isPortrait ? (bottomInset > 0 ? bottomInset + 12 : 16) : 24,
                            left: isPortrait ? 16 : 24,
                            right: isPortrait ? 16 : 24,
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

              // 7. Switching Audio / Quality Loading Overlay
              if (_isSwitchingAudio || _isSwitchingQuality)
                Container(
                  color: Colors.black.withValues(alpha: 0.7),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SpinKitRing(color: Colors.redAccent, size: 48.0),
                        const SizedBox(height: 16),
                        Text(
                          _isSwitchingAudio 
                              ? AppLanguageService.tr(en: "Switching audio...", id: "Mengganti audio...")
                              : AppLanguageService.tr(en: "Switching quality...", id: "Mengganti kualitas..."),
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
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

  String _formatStreamQualityLabel(dynamic stream) {
    if (stream is! Map) return "HD";
    if (stream['resolution'] != null && stream['resolution'] != 0) {
      final res = stream['resolution'];
      if (res >= 2160) return "4K UHD (2160p)";
      if (res >= 1080) return "FHD (1080p)";
      if (res >= 720) return "HD (720p)";
      return "${res}p";
    }
    final title = (stream['qualityTitle'] ?? stream['title'] ?? stream['quality'] ?? '').toString();
    if (title.isNotEmpty) return title;
    return "HD";
  }

  String _formatShortQualityLabel(dynamic stream) {
    if (stream is! Map) return "HD";
    if (stream['resolution'] != null && stream['resolution'] != 0) {
      final res = stream['resolution'];
      if (res >= 2160) return "4K";
      if (res >= 1080) return "1080p";
      if (res >= 720) return "720p";
      return "${res}p";
    }
    final title = (stream['qualityTitle'] ?? stream['title'] ?? '').toString().toLowerCase();
    if (title.contains('2160') || title.contains('4k')) return "4K";
    if (title.contains('1080')) return "1080p";
    if (title.contains('720')) return "720p";
    return "HD";
  }

  void _switchAudio(dynamic dub) async {
    if (widget.onSwitchAudio == null) return;
    final currentPos = _player.state.position;

    setState(() {
      _isSwitchingAudio = true;
    });

    try {
      final res = await widget.onSwitchAudio!(dub);
      if (res != null && mounted) {
        setState(() {
          _currentAudioName = res.audioName;
          if (res.availableStreams.isNotEmpty) {
            _availableStreams = res.availableStreams;
          }
          if (res.currentStream != null) {
            _currentStream = res.currentStream;
          }
        });
        _setupSubtitles(res.captions);
        final headers = _extractStreamHeaders(res.currentStream ?? _currentStream);
        await _player.open(Media(res.streamUrl, httpHeaders: headers));
        await _player.seek(currentPos);
      }
    } catch (e) {
      print("Error switching audio: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingAudio = false;
        });
      }
    }
  }

  void _switchQuality(Map<String, dynamic> stream) async {
    final currentPos = _player.state.position;

    setState(() {
      _isSwitchingQuality = true;
    });

    try {
      String? newUrl;
      if (widget.onSwitchQuality != null) {
        newUrl = await widget.onSwitchQuality!(stream);
      } else {
        newUrl = (stream['url'] ?? stream['link'] ?? stream['src'] ?? '').toString();
      }

      if (newUrl != null && newUrl.isNotEmpty && mounted) {
        setState(() {
          _currentStream = stream;
        });
        final headers = _extractStreamHeaders(stream);
        await _player.open(Media(newUrl, httpHeaders: headers));
        await _player.seek(currentPos);
      }
    } catch (e) {
      print("Error switching quality: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingQuality = false;
        });
      }
    }
  }

  void _selectEpisode(int season, int episode) async {
    if (widget.onSelectEpisode == null) return;

    _saveCurrentProgress();

    setState(() {
      _isSwitchingNextEpisode = true;
    });

    try {
      final nextData = await widget.onSelectEpisode!(season, episode);
      if (nextData != null && mounted) {
        setState(() {
          _currentTitle = nextData.title;
          _currentSeason = nextData.season;
          _currentEpisode = nextData.episode;
          _hasNextEpisode = nextData.hasNextEpisode;
          _nextEpisodeLabel = nextData.nextEpisodeLabel;
          if (nextData.availableStreams.isNotEmpty) {
            _availableStreams = nextData.availableStreams;
          }
          if (nextData.currentStream != null) {
            _currentStream = nextData.currentStream;
          }
          if (nextData.currentAudioName != null) {
            _currentAudioName = nextData.currentAudioName;
          }
          _isInitialized = false;
          _nextEpisodeDismissed = false;
        });

        _setupSubtitles(nextData.captions);
        final headers = _extractStreamHeaders(nextData.currentStream ?? _currentStream);
        await _player.open(Media(nextData.streamUrl, httpHeaders: headers));
        _startHideTimer();
      }
    } catch (e) {
      print("Error selecting episode: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingNextEpisode = false;
        });
      }
    }
  }

  void _showEpisodeModal() {
    int selectedSeasonTab = _currentSeason > 0 ? _currentSeason : 1;
    Map<String, dynamic>? seasonData;
    for (final s in _seasons) {
      if (s is Map && (s['se'] ?? 1) == selectedSeasonTab) {
        seasonData = Map<String, dynamic>.from(s);
        break;
      }
    }
    if (seasonData == null) {
      if (_seasons.isNotEmpty && _seasons.first is Map) {
        seasonData = Map<String, dynamic>.from(_seasons.first as Map);
      } else {
        seasonData = {'se': 1, 'maxEp': widget.maxEpisodesInSeason};
      }
    }
    int epCount = (seasonData['maxEp'] ?? widget.maxEpisodesInSeason) as int;
    if (epCount <= 0) epCount = 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xF2141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: 380,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLanguageService.tr(en: "Select Episode", id: "Pilih Episode"),
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_seasons.length > 1) ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: _seasons.map((s) {
                          final seNum = s['se'] ?? 1;
                          final isTabSelected = selectedSeasonTab == seNum;
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: TvFocusableCard(
                              onTap: () {
                                setModalState(() {
                                  selectedSeasonTab = seNum;
                                  epCount = (s['maxEp'] ?? 1) as int;
                                  if (epCount <= 0) epCount = 1;
                                });
                              },
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isTabSelected ? Colors.redAccent : const Color(0xFF222222),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  "Season $seNum",
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontWeight: isTabSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 2.2,
                      ),
                      itemCount: epCount,
                      itemBuilder: (context, index) {
                        final epNum = index + 1;
                        final isCurrentEp = _currentSeason == selectedSeasonTab && _currentEpisode == epNum;
                        return TvFocusableCard(
                          onTap: () {
                            Navigator.pop(context);
                            _selectEpisode(selectedSeasonTab, epNum);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isCurrentEp ? Colors.redAccent.withValues(alpha: 0.3) : const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrentEp ? Colors.redAccent : const Color(0xFF2E2E2E),
                                width: isCurrentEp ? 1.5 : 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isCurrentEp) ...[
                                  const Icon(Icons.play_circle_fill, color: Colors.redAccent, size: 14),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  "Ep $epNum",
                                  style: GoogleFonts.outfit(
                                    color: isCurrentEp ? Colors.redAccent : Colors.white,
                                    fontWeight: isCurrentEp ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _triggerNextEpisodeCountdown() {
    if (_showNextEpisodeOverlay || _isSwitchingNextEpisode || !_hasNextEpisode || _nextEpisodeDismissed) return;
    setState(() {
      _showNextEpisodeOverlay = true;
      _nextEpisodeCountdown = 8;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _showNextEpisodeOverlay) {
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
      _nextEpisodeDismissed = false;
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
          final headers = _extractStreamHeaders(nextData.currentStream ?? _currentStream);
          await _player.open(Media(nextData.streamUrl, httpHeaders: headers));
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
      bottom: 76,
      right: 24,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 14,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Next Episode Info & Timer
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            AppLanguageService.tr(en: "NEXT IN", id: "LANJUT DALAM"),
                            style: GoogleFonts.outfit(
                              color: Colors.redAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              "${_nextEpisodeCountdown}s",
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // Netflix style White Play Button
                  TvFocusableCard(
                    focusNode: _playNextFocusNode,
                    onTap: _playNextEpisode,
                    borderRadius: BorderRadius.circular(6),
                    scaleFactor: 1.05,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow, color: Colors.black, size: 16),
                          const SizedBox(width: 3),
                          Text(
                            AppLanguageService.tr(en: "Play", id: "Putar"),
                            style: GoogleFonts.outfit(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Compact Close Button
                  TvFocusableCard(
                    focusNode: _cancelNextFocusNode,
                    onTap: () {
                      _nextEpisodeTimer?.cancel();
                      setState(() {
                        _showNextEpisodeOverlay = false;
                        _nextEpisodeDismissed = true;
                      });
                      _playPauseFocusNode.requestFocus();
                    },
                    borderRadius: BorderRadius.circular(6),
                    scaleFactor: 1.05,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 0.8),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 16),
                    ),
                  ),
                ],
              ),
            ),
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

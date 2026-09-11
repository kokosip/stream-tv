import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../services/iptv_service.dart';
import '../widgets/tv_focusable_card.dart';

class LiveTvPlayerScreen extends StatefulWidget {
  final List<IptvChannel> channels;
  final int initialIndex;

  const LiveTvPlayerScreen({
    super.key,
    required this.channels,
    this.initialIndex = 0,
  });

  @override
  State<LiveTvPlayerScreen> createState() => _LiveTvPlayerScreenState();
}

class _LiveTvPlayerScreenState extends State<LiveTvPlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  late int _currentIndex;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = "";

  // OSD Overlays state
  bool _showControls = true;
  Timer? _controlsTimer;
  bool _showSideDrawer = false;

  final FocusNode _keyboardFocusNode = FocusNode();
  final ScrollController _drawerScrollController = ScrollController();

  IptvChannel get _currentChannel => widget.channels[_currentIndex];

  @override
  void initState() {
    super.initState();
    // Auto-rotate and lock to landscape for immersive TV viewing
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _currentIndex = widget.initialIndex.clamp(0, widget.channels.length - 1);

    _player = Player();
    _videoController = VideoController(_player);

    _player.stream.error.listen((error) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage = error.toString();
        });
      }
    });

    _player.stream.buffering.listen((buffering) {
      if (mounted && !_hasError) {
        setState(() {
          _isLoading = buffering;
        });
      }
    });

    _player.stream.playing.listen((playing) {
      if (mounted && playing && _isLoading) {
        setState(() {
          _isLoading = false;
        });
      }
    });

    _playCurrentChannel();
    _startHideControlsTimer();
  }

  void _playCurrentChannel() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = "";
    });

    try {
      final channel = _currentChannel;
      final headers = channel.httpHeaders ?? {};

      await _player.open(
        Media(
          channel.url,
          httpHeaders: headers.isNotEmpty ? headers : null,
        ),
        play: true,
      );

      _resetControlsTimer();
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _switchChannel(int newIndex) {
    if (widget.channels.isEmpty) return;
    final targetIndex = (newIndex + widget.channels.length) % widget.channels.length;
    if (targetIndex == _currentIndex && !_hasError) return;

    setState(() {
      _currentIndex = targetIndex;
      _showControls = true;
      _showSideDrawer = false;
    });

    _playCurrentChannel();
  }

  void _startHideControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_showSideDrawer) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _resetControlsTimer() {
    setState(() {
      _showControls = true;
    });
    _startHideControlsTimer();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (_showSideDrawer) {
      if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
          event.logicalKey == LogicalKeyboardKey.escape ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        setState(() {
          _showSideDrawer = false;
          _keyboardFocusNode.requestFocus();
        });
        _resetControlsTimer();
      }
      return;
    }

    // Remote D-Pad Navigation in Video Player
    if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
        event.logicalKey == LogicalKeyboardKey.pageUp) {
      _switchChannel(_currentIndex - 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
        event.logicalKey == LogicalKeyboardKey.pageDown) {
      _switchChannel(_currentIndex + 1);
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
        event.logicalKey == LogicalKeyboardKey.select ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      setState(() {
        _showSideDrawer = true;
        _showControls = false;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _toggleFavorite();
    } else {
      _resetControlsTimer();
    }
  }

  void _toggleFavorite() async {
    final ch = _currentChannel;
    await IptvService.instance.toggleFavorite(ch);
    setState(() {});
    _resetControlsTimer();
  }

  void _exitPlayer() {
    // Immediately restore portrait orientation for mobile devices
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _player.dispose();
    _keyboardFocusNode.dispose();
    _drawerScrollController.dispose();

    // Restore flexible orientation prioritizing portrait for mobile devices
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTv = size.width > 800 && size.height > 500;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitPlayer();
      },
      child: Scaffold(
      backgroundColor: Colors.black,
      body: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_showSideDrawer) {
              setState(() => _showSideDrawer = false);
            } else {
              _resetControlsTimer();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Video Surface (media_kit libmpv)
              Center(
                child: Video(
                  controller: _videoController,
                  controls: NoVideoControls,
                ),
              ),

              // 2. Loading Spinner Overlay
              if (_isLoading && !_hasError)
                Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SpinKitRing(color: Colors.redAccent, size: 48.0),
                        const SizedBox(height: 16),
                        Text(
                          "Memuat siaran ${_currentChannel.name}...",
                          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),

              // 3. Error Banner
              if (_hasError)
                Container(
                  color: Colors.black.withValues(alpha: 0.75),
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 56),
                        const SizedBox(height: 16),
                        Text(
                          "Siaran sedang tidak dapat diakses",
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage.isNotEmpty
                              ? _errorMessage
                              : "Server siaran mungkin sedang offline atau mengalami kendala jaringan.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 14),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TvFocusableCard(
                              onTap: _playCurrentChannel,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                color: Colors.redAccent,
                                child: Text("Coba Lagi", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 16),
                            TvFocusableCard(
                              onTap: () => _switchChannel(_currentIndex + 1),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                color: const Color(0xFF262626),
                                child: Text("Channel Berikutnya (▶)", style: GoogleFonts.outfit(color: Colors.white)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

              // 4. OSD Channel Info Bar (Bottom Overlay)
              if (_showControls && !_showSideDrawer)
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 24,
                  child: _buildOsdChannelInfo(isTv),
                ),

              // 5. OSD Side Channel List Drawer (Left Overlay)
              if (_showSideDrawer)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: isTv ? 380 : 280,
                  child: _buildSideDrawer(isTv),
                ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _buildOsdChannelInfo(bool isTv) {
    final ch = _currentChannel;
    final isFav = ch.isFavorite;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1),
          ),
          child: Row(
            children: [
              // Back Button
              TvFocusableCard(
                onTap: _exitPlayer,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                ),
              ),
              const SizedBox(width: 14),

              // Channel Logo
              if (ch.logo != null && ch.logo!.isNotEmpty)
                Container(
                  width: 52,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Image.network(
                    ch.logo!,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Icon(Icons.tv, color: Colors.white54, size: 24),
                  ),
                )
              else
                Container(
                  width: 48,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.live_tv, color: Colors.redAccent, size: 24),
                ),
              const SizedBox(width: 14),

              // Channel Name & Category
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        // Red LIVE badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            "LIVE",
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          ch.groupTitle,
                          style: GoogleFonts.outfit(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "• Channel ${_currentIndex + 1}/${widget.channels.length}",
                          style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: isTv ? 18 : 15, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // Favorite Toggle
              TvFocusableCard(
                onTap: _toggleFavorite,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isFav ? Colors.amber.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isFav ? Colors.amber : Colors.transparent, width: 1),
                  ),
                  child: Row(
                    children: [
                      Icon(isFav ? Icons.star_rounded : Icons.star_outline_rounded, color: isFav ? Colors.amber : Colors.white70, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        isFav ? "Favorit" : "+ Favorit",
                        style: GoogleFonts.outfit(color: isFav ? Colors.amber : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Side Drawer Channel Guide Trigger
              TvFocusableCard(
                onTap: () {
                  setState(() {
                    _showSideDrawer = true;
                    _showControls = false;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF242424),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.format_list_bulleted_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text("Daftar TV", style: GoogleFonts.outfit(color: Colors.white, fontSize: 12)),
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

  Widget _buildSideDrawer(bool isTv) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          color: const Color(0xFF101010).withValues(alpha: 0.92),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drawer Header
              Row(
                children: [
                  const Icon(Icons.live_tv_rounded, color: Colors.redAccent, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    "Daftar Saluran TV",
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () {
                      setState(() {
                        _showSideDrawer = false;
                        _keyboardFocusNode.requestFocus();
                      });
                      _resetControlsTimer();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Gunakan remote Up/Down untuk memilih channel",
                style: GoogleFonts.outfit(color: Colors.grey.shade400, fontSize: 11),
              ),
              const Divider(color: Color(0xFF262626), height: 24),

              // Channels ListView
              Expanded(
                child: ListView.builder(
                  controller: _drawerScrollController,
                  itemCount: widget.channels.length,
                  itemBuilder: (context, index) {
                    final ch = widget.channels[index];
                    final isPlaying = index == _currentIndex;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: TvFocusableCard(
                        onTap: () => _switchChannel(index),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isPlaying ? const Color(0xFF2B1417) : const Color(0xFF181818),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isPlaying ? Colors.redAccent : const Color(0xFF282828),
                              width: isPlaying ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              // Number
                              Text(
                                "${index + 1}",
                                style: GoogleFonts.outfit(
                                  color: isPlaying ? Colors.redAccent : Colors.grey.shade500,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Logo
                              if (ch.logo != null && ch.logo!.isNotEmpty)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    ch.logo!,
                                    width: 32,
                                    height: 24,
                                    fit: BoxFit.contain,
                                    errorBuilder: (c, e, s) => const Icon(Icons.tv, size: 18, color: Colors.white38),
                                  ),
                                )
                              else
                                const Icon(Icons.tv, size: 18, color: Colors.white38),
                              const SizedBox(width: 12),

                              // Name & Group
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      ch.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.outfit(
                                        color: isPlaying ? Colors.redAccent : Colors.white,
                                        fontSize: 13,
                                        fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      ch.groupTitle,
                                      style: GoogleFonts.outfit(color: Colors.grey.shade500, fontSize: 10),
                                    ),
                                  ],
                                ),
                              ),

                              if (ch.isFavorite)
                                const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
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
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../utils/logger.dart';
import 'video_watermark.dart';

class SimpleVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? title;
  final bool autoPlay;
  final String? userName;
  final bool showWatermark;
  final VideoPlayerController? existingController;

  const SimpleVideoPlayer({
    super.key,
    required this.videoUrl,
    this.title,
    this.autoPlay = false,
    this.userName,
    this.showWatermark = true,
    this.existingController,
  });

  @override
  State<SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<SimpleVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  double _volume = 1.0;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingController != null) {
      _useExistingController();
    } else {
      _initializePlayer();
    }
  }

  @override
  void dispose() {
    // Only dispose if we created the controller, not if it was provided
    if (widget.existingController == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  void _useExistingController() {
    _controller = widget.existingController!;
    setState(() {
      _isInitialized = _controller!.value.isInitialized;
    });

    if (widget.autoPlay && !_controller!.value.isPlaying) {
      _controller!.play();
    }

    // Auto-hide controls after 3 seconds
    _showControlsTemporarily();

    Logger.i(
      '✅ SimpleVideoPlayer: Using existing controller for ${widget.videoUrl}',
    );
    Logger.d(
      'DEBUG: Existing controller initialized: ${_controller!.value.isInitialized}',
    );
    Logger.d('DEBUG: Video duration: ${_controller!.value.duration}');
  }

  Future<void> _initializePlayer() async {
    try {
      Logger.i('Initializing video player: ${widget.videoUrl}');

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        if (widget.autoPlay) {
          await _controller!.play();
        }

        // Auto-hide controls after 3 seconds
        _showControlsTemporarily();
      }
    } catch (e) {
      Logger.e('Error initializing video: $e');
    }
  }

  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
    });
  }

  void _toggleMute() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _controller!.setVolume(0.0);
      } else {
        _controller!.setVolume(_volume);
      }
    });
  }

  void _setVolume(double volume) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _volume = volume;
      if (!_isMuted) {
        _controller!.setVolume(volume);
      }
      // If user adjusts volume while muted, unmute
      if (_isMuted && volume > 0) {
        _isMuted = false;
      }
    });
  }

  void _toggleFullscreen() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Pause the current player before fullscreen
    final wasPlaying = _controller!.value.isPlaying;
    if (wasPlaying) {
      _controller!.pause();
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullscreenVideoPlayer(
            sharedController: _controller!,
            title: widget.title,
            wasPlaying: wasPlaying,
            userName: widget.userName,
            showWatermark: widget.showWatermark,
            onExit: (wasPlayingOnExit) {
              // Resume playback if it was playing before
              Future.microtask(() {
                if (mounted &&
                    _controller != null &&
                    _controller!.value.isInitialized &&
                    wasPlayingOnExit) {
                  _controller!.play();
                }
              });
            },
            volume: _volume,
            isMuted: _isMuted,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  Widget _buildControls() {
    if (!_showControls || !_isInitialized) {
      return const SizedBox.shrink();
    }

    final position = _controller!.value.position;
    final duration = _controller!.value.duration;
    final isPlaying = _controller!.value.isPlaying;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withOpacity(0.7)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: const VideoProgressColors(
                playedColor: Colors.red,
                bufferedColor: Colors.grey,
                backgroundColor: Colors.white30,
              ),
            ),
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Play/Pause button
                IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),

                // Time display
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: const TextStyle(color: Colors.white),
                ),

                const Spacer(),

                // Volume control
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _toggleMute,
                      icon: Icon(
                        _isMuted 
                          ? Icons.volume_off 
                          : _volume > 0.5 
                            ? Icons.volume_up 
                            : Icons.volume_down,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: _isMuted ? 0.0 : _volume,
                          min: 0.0,
                          max: 1.0,
                          onChanged: _setVolume,
                          activeColor: Colors.white,
                          inactiveColor: Colors.white30,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 8),

                // Fullscreen button
                IconButton(
                  onPressed: _toggleFullscreen,
                  icon: const Icon(
                    Icons.fullscreen,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return GestureDetector(
      onTap: _showControlsTemporarily,
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video player
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),

            // Watermark overlay
            if (widget.showWatermark && widget.userName != null)
              VideoWatermark(userName: widget.userName!),

            // Controls overlay
            _buildControls(),
          ],
        ),
      ),
    );
  }
}

// Fullscreen video player widget
class _FullscreenVideoPlayer extends StatefulWidget {
  final VideoPlayerController sharedController;
  final String? title;
  final bool wasPlaying;
  final String? userName;
  final bool showWatermark;
  final Function(bool wasPlaying) onExit;
  final double volume;
  final bool isMuted;

  const _FullscreenVideoPlayer({
    required this.sharedController,
    this.title,
    required this.wasPlaying,
    this.userName,
    this.showWatermark = true,
    required this.onExit,
    required this.volume,
    required this.isMuted,
  });

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  late VideoPlayerController _controller;
  bool _showControls = true;
  late double _volume;
  late bool _isMuted;

  @override
  void initState() {
    super.initState();
    _controller = widget.sharedController;
    _volume = widget.volume;
    _isMuted = widget.isMuted;
    _setFullscreenMode();
    _resumePlaybackIfNeeded();
  }

  @override
  void dispose() {
    // Don't dispose the shared controller, just restore system UI
    _exitFullscreenMode();
    super.dispose();
  }

  void _setFullscreenMode() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreenMode() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _resumePlaybackIfNeeded() {
    // Resume playing if it was playing before entering fullscreen
    if (widget.wasPlaying && _controller.value.isInitialized) {
      _controller.play();
    }

    // Show controls temporarily
    _showControlsTemporarily();
  }

  void _showControlsTemporarily() {
    setState(() {
      _showControls = true;
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controller.value.isPlaying) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _togglePlayPause() {
    if (!_controller.value.isInitialized) return;

    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  void _toggleMute() {
    if (!_controller.value.isInitialized) return;

    setState(() {
      _isMuted = !_isMuted;
      if (_isMuted) {
        _controller.setVolume(0.0);
      } else {
        _controller.setVolume(_volume);
      }
    });
  }

  void _setVolume(double volume) {
    if (!_controller.value.isInitialized) return;

    setState(() {
      _volume = volume;
      if (!_isMuted) {
        _controller.setVolume(volume);
      }
      // If user adjusts volume while muted, unmute
      if (_isMuted && volume > 0) {
        _isMuted = false;
      }
    });
  }

  void _exitFullscreen() {
    // Capture state before any navigation changes
    final isPlaying = _controller.value.isPlaying;

    // Navigate back
    Navigator.of(context).pop();

    // Delay the callback to avoid rebuilds during navigation
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onExit(isPlaying);
    });
  }

  void _handleBackPressed() {
    // Called when hardware back button is pressed (after navigation already happened)
    final isPlaying = _controller.value.isPlaying;

    // Delay the callback to avoid rebuilds
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onExit(isPlaying);
    });
  }

  Widget _buildFullscreenControls() {
    if (!_showControls || !_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final position = _controller.value.position;
    final duration = _controller.value.duration;
    final isPlaying = _controller.value.isPlaying;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withOpacity(0.7),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withOpacity(0.7),
          ],
        ),
      ),
      child: Column(
        children: [
          // Top bar with title and exit button
          Padding(
            padding: const EdgeInsets.only(top: 50, left: 16, right: 16),
            child: Row(
              children: [
                if (widget.title != null)
                  Expanded(
                    child: Text(
                      widget.title!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  onPressed: _exitFullscreen,
                  icon: const Icon(
                    Icons.fullscreen_exit,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Bottom controls
          Column(
            children: [
              // Progress bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.red,
                    bufferedColor: Colors.grey,
                    backgroundColor: Colors.white30,
                  ),
                ),
              ),

              // Control buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Play/Pause button
                    IconButton(
                      onPressed: _togglePlayPause,
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Time display
                    Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),

                    const Spacer(),

                    // Volume control
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _toggleMute,
                          icon: Icon(
                            _isMuted 
                              ? Icons.volume_off 
                              : _volume > 0.5 
                                ? Icons.volume_up 
                                : Icons.volume_down,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                              overlayShape: SliderComponentShape.noOverlay,
                            ),
                            child: Slider(
                              value: _isMuted ? 0.0 : _volume,
                              min: 0.0,
                              max: 1.0,
                              onChanged: _setVolume,
                              activeColor: Colors.white,
                              inactiveColor: Colors.white30,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (didPop) {
          _handleBackPressed();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body:
            _controller.value.isInitialized
                ? GestureDetector(
                  onTap: _showControlsTemporarily,
                  onDoubleTap: _exitFullscreen,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Video player
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      ),

                      // Watermark overlay
                      if (widget.showWatermark && widget.userName != null)
                        FullscreenVideoWatermark(userName: widget.userName!),

                      // Controls overlay
                      _buildFullscreenControls(),
                    ],
                  ),
                )
                : const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
      ),
    );
  }
}

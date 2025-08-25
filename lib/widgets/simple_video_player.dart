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

  const SimpleVideoPlayer({
    super.key,
    required this.videoUrl,
    this.title,
    this.autoPlay = false,
    this.userName,
    this.showWatermark = true,
  });

  @override
  State<SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<SimpleVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
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

  void _toggleFullscreen() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Navigate to fullscreen player with current state
    final currentPosition = _controller!.value.position;
    final wasPlaying = _controller!.value.isPlaying;

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return _FullscreenVideoPlayer(
            videoUrl: widget.videoUrl,
            title: widget.title,
            initialPosition: currentPosition,
            wasPlaying: wasPlaying,
            userName: widget.userName,
            showWatermark: widget.showWatermark,
            onExit: (exitPosition, wasPlayingOnExit) {
              // Restore the main player's state after navigation is complete
              Future.microtask(() {
                if (mounted &&
                    _controller != null &&
                    _controller!.value.isInitialized) {
                  try {
                    _controller!.seekTo(exitPosition);
                    if (!wasPlayingOnExit) {
                      _controller!.pause();
                    }
                    Logger.i(
                      'Video player state restored: position=${exitPosition.inSeconds}s, playing=$wasPlayingOnExit',
                    );
                  } catch (e) {
                    Logger.e('Error restoring video state: $e');
                  }
                }
              });
            },
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
  final String videoUrl;
  final String? title;
  final Duration initialPosition;
  final bool wasPlaying;
  final String? userName;
  final bool showWatermark;
  final Function(Duration position, bool wasPlaying) onExit;

  const _FullscreenVideoPlayer({
    required this.videoUrl,
    this.title,
    required this.initialPosition,
    required this.wasPlaying,
    this.userName,
    this.showWatermark = true,
    required this.onExit,
  });

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _setFullscreenMode();
  }

  @override
  void dispose() {
    _controller?.dispose();
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

  Future<void> _initializePlayer() async {
    try {
      Logger.i('Initializing fullscreen video player');

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.videoUrl),
      );

      await _controller!.initialize();

      if (mounted) {
        // Seek to the position from the main player
        await _controller!.seekTo(widget.initialPosition);

        setState(() {
          _isInitialized = true;
        });

        // Continue playing if it was playing before
        if (widget.wasPlaying) {
          await _controller!.play();
        }

        // Show controls temporarily
        _showControlsTemporarily();
      }
    } catch (e) {
      Logger.e('Error initializing fullscreen video: $e');
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

  void _exitFullscreen() {
    // Capture state before any navigation changes
    final currentPosition = _controller?.value.position ?? Duration.zero;
    final isPlaying = _controller?.value.isPlaying ?? false;

    // First, restore system UI and orientations
    _exitFullscreenMode();

    // Navigate back
    Navigator.of(context).pop();

    // Delay the callback to avoid rebuilds during navigation
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onExit(currentPosition, isPlaying);
    });
  }

  void _handleBackPressed() {
    // Called when hardware back button is pressed (after navigation already happened)
    final currentPosition = _controller?.value.position ?? Duration.zero;
    final isPlaying = _controller?.value.isPlaying ?? false;

    // Restore system UI
    _exitFullscreenMode();

    // Delay the callback to avoid rebuilds
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onExit(currentPosition, isPlaying);
    });
  }

  Widget _buildFullscreenControls() {
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
            _isInitialized
                ? GestureDetector(
                  onTap: _showControlsTemporarily,
                  onDoubleTap: _exitFullscreen,
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

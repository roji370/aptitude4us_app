import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/logger.dart';
import 'video_watermark.dart';
import 'custom_video_progress_bar.dart';

class SimpleVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? title;
  final bool autoPlay;
  final String? userName;
  final bool showWatermark;
  final VideoPlayerController? existingController;
  /// Called once when 80% of the video is watched (for one-time-view tracking).
  final VoidCallback? onViewedCallback;
  /// When true, all seeking controls are disabled: progress bar dragging/tapping,
  /// skip ±10s buttons, and double-tap-to-skip. Used for one-time-view videos.
  final bool disableSeeking;

  const SimpleVideoPlayer({
    super.key,
    required this.videoUrl,
    this.title,
    this.autoPlay = false,
    this.userName,
    this.showWatermark = true,
    this.existingController,
    this.onViewedCallback,
    this.disableSeeking = false,
  });

  @override
  State<SimpleVideoPlayer> createState() => _SimpleVideoPlayerState();
}

class _SimpleVideoPlayerState extends State<SimpleVideoPlayer> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  double _volume = 1.0;
  bool _isMuted = false;
  double _playbackSpeed = 1.0;
  Timer? _hideControlsTimer;
  String? _skipFeedback;
  Timer? _skipFeedbackTimer;
  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsAnimation;

  // One-time view tracking
  bool _hasTriggeredViewedCallback = false;

  // Throttle tracking: only rebuild when play state or position (in seconds) changes
  bool? _lastPlayingState;
  int _lastPositionSeconds = -1;

  @override
  void initState() {
    super.initState();
    
    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    _controlsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _controlsAnimation = CurvedAnimation(
      parent: _controlsAnimationController,
      curve: Curves.easeInOut,
    );
    _controlsAnimationController.forward();
    
    if (widget.existingController != null) {
      _useExistingController();
    } else {
      _initializePlayer();
    }
  }

  @override
  void deactivate() {
    // Pause video when navigating away from this screen
    if (_controller != null && _controller!.value.isInitialized && _controller!.value.isPlaying) {
      _controller!.pause();
      Logger.i('🎬 Video paused due to navigation away from player');
    }
    super.deactivate();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Cancel timers
    _hideControlsTimer?.cancel();
    _skipFeedbackTimer?.cancel();
    
    // Pause and cleanup
    if (_controller != null && _controller!.value.isInitialized && _controller!.value.isPlaying) {
      _controller!.pause();
    }
    
    // Remove listener and disable wake lock when disposing
    _controller?.removeListener(_handlePlaybackStateChange);
    _disableWakelock();
    
    // Dispose animation controller
    _controlsAnimationController.dispose();
    
    // Only dispose if we created the controller, not if it was provided
    if (widget.existingController == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Pause video when app goes to background or is paused
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
        Logger.i('🎬 Video paused due to app lifecycle change: $state');
      }
    }
    // Optionally resume when app comes back (uncomment if desired)
    // else if (state == AppLifecycleState.resumed) {
    //   if (!_controller!.value.isPlaying && widget.autoPlay) {
    //     _controller!.play();
    //   }
    // }
  }

  void _useExistingController() {
    _controller = widget.existingController!;
    setState(() {
      _isInitialized = _controller!.value.isInitialized;
    });

    // Add listener to manage wake lock based on playback state
    _controller!.addListener(_handlePlaybackStateChange);

    if (widget.autoPlay && !_controller!.value.isPlaying) {
      _controller!.play();
    }

    // Auto-hide controls after 5 seconds
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

        // Add listener to manage wake lock based on playback state
        _controller!.addListener(_handlePlaybackStateChange);

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
    _hideControlsTimer?.cancel();

    if (!_showControls) {
      _controlsAnimationController.forward();
    }

    setState(() {
      _showControls = true;
    });

    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _controller != null && _controller!.value.isPlaying) {
        _controlsAnimationController.reverse();
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// Pause the auto-hide timer while the user is scrubbing.
  void _pauseControlsTimer() {
    _hideControlsTimer?.cancel();
    // Ensure controls stay visible during scrub.
    if (!_showControls) {
      _controlsAnimationController.forward();
      setState(() {
        _showControls = true;
      });
    }
  }

  /// Resume the auto-hide timer after scrubbing ends.
  void _resumeControlsTimer() {
    _showControlsTemporarily();
  }
  
  void _toggleControls() {
    if (_showControls) {
      _hideControlsTimer?.cancel();
      _controlsAnimationController.reverse();
      setState(() {
        _showControls = false;
      });
    } else {
      _showControlsTemporarily();
    }
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

  static const List<double> _speedOptions = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 0.5, 0.75];

  void _cycleSpeed() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final currentIndex = _speedOptions.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speedOptions.length;
    setState(() {
      _playbackSpeed = _speedOptions[nextIndex];
      _controller!.setPlaybackSpeed(_playbackSpeed);
    });
    _showControlsTemporarily();
  }

  // Wake lock management methods
  void _handlePlaybackStateChange() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    final isPlaying = _controller!.value.isPlaying;
    
    if (isPlaying) {
      _enableWakelock();
    } else {
      _disableWakelock();
    }

    // One-time view tracking: fire once when 80% watched.
    // Clamp the threshold to a minimum of 1 second so that very short videos
    // (≤ 1s) don't fire at position=0 the moment the controller initialises.
    if (!_hasTriggeredViewedCallback && widget.onViewedCallback != null) {
      final duration = _controller!.value.duration;
      final position = _controller!.value.position;
      if (duration.inSeconds > 0) {
        final thresholdSeconds =
            (duration.inSeconds * 0.8).toInt().clamp(1, duration.inSeconds);
        if (position.inSeconds >= thresholdSeconds) {
          _hasTriggeredViewedCallback = true;
          Logger.i('🎬 80% progress reached (${position.inSeconds}s / ${duration.inSeconds}s) – triggering one-time view callback');
          widget.onViewedCallback!();
        }
      }
    }

    // Throttled rebuild: only call setState when the play/pause state changes
    // or when the position advances by ≥1 second. This reduces rebuilds from
    // ~30/sec (every frame tick) to ~1/sec while playing.
    final posSeconds = _controller!.value.position.inSeconds;
    final stateChanged = isPlaying != _lastPlayingState;
    final positionAdvanced = posSeconds != _lastPositionSeconds;
    
    if (stateChanged || positionAdvanced) {
      _lastPlayingState = isPlaying;
      _lastPositionSeconds = posSeconds;
      if (mounted) setState(() {});
    }
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
      Logger.i('🔒 Wake lock enabled - screen will stay on during video playback');
    } catch (e) {
      Logger.e('Failed to enable wake lock: $e');
    }
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
      Logger.i('🔓 Wake lock disabled - normal screen timeout restored');
    } catch (e) {
      Logger.e('Failed to disable wake lock: $e');
    }
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

  void _skipBackward({bool showFeedback = true}) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Haptic feedback
    HapticFeedback.lightImpact();

    final currentPosition = _controller!.value.position;
    final newPosition = currentPosition - const Duration(seconds: 10);
    
    // Don't go before the start
    final targetPosition = newPosition < Duration.zero ? Duration.zero : newPosition;
    
    _controller!.seekTo(targetPosition);
    
    if (showFeedback) {
      _showSkipFeedback('- 10s');
    }
    _showControlsTemporarily();
  }

  void _skipForward({bool showFeedback = true}) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Haptic feedback
    HapticFeedback.lightImpact();

    final currentPosition = _controller!.value.position;
    final duration = _controller!.value.duration;
    final newPosition = currentPosition + const Duration(seconds: 10);
    
    // Don't go past the end
    final targetPosition = newPosition > duration ? duration : newPosition;
    
    _controller!.seekTo(targetPosition);
    
    if (showFeedback) {
      _showSkipFeedback('+ 10s');
    }
    _showControlsTemporarily();
  }
  
  void _showSkipFeedback(String text) {
    _skipFeedbackTimer?.cancel();
    
    setState(() {
      _skipFeedback = text;
    });
    
    _skipFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _skipFeedback = null;
        });
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
            disableSeeking: widget.disableSeeking,
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

  Widget _buildCenterControls() {
    if (!_showControls || !_isInitialized) {
      return const SizedBox.shrink();
    }

    final isPlaying = _controller!.value.isPlaying;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Skip backward (hidden when seeking is disabled)
          if (!widget.disableSeeking)
            IconButton(
              onPressed: _skipBackward,
              icon: const Icon(
                Icons.replay_10,
                color: Colors.white,
                size: 40,
              ),
            ),
          if (!widget.disableSeeking) const SizedBox(width: 24),
          // Play/Pause
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _togglePlayPause,
              iconSize: 56,
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 56,
              ),
            ),
          ),
          if (!widget.disableSeeking) const SizedBox(width: 24),
          // Skip forward (hidden when seeking is disabled)
          if (!widget.disableSeeking)
            IconButton(
              onPressed: _skipForward,
              icon: const Icon(
                Icons.forward_10,
                color: Colors.white,
                size: 40,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeedButton() {
    final label = _playbackSpeed == _playbackSpeed.roundToDouble()
        ? '${_playbackSpeed.toInt()}x'
        : '${_playbackSpeed}x';
    return GestureDetector(
      onTap: _cycleSpeed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white54, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time display and fullscreen button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Time display
                Text(
                  '${_formatDuration(position)} / ${_formatDuration(duration)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                // Fullscreen button
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _toggleFullscreen,
                  icon: const Icon(
                    Icons.fullscreen,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // Progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CustomVideoProgressBar(
              controller: _controller!,
              playedColor: const Color(0xFFFF0000),
              bufferedColor: const Color(0x80FFFFFF),
              backgroundColor: const Color(0x33FFFFFF),
              thumbColor: const Color(0xFFFF0000),
              barHeight: 3.0,
              activeBarHeight: 5.0,
              thumbRadius: 6.0,
              activeThumbRadius: 8.0,
              onDragStart: _pauseControlsTimer,
              onDragEnd: _resumeControlsTimer,
              disableSeeking: widget.disableSeeking,
            ),
          ),

          // Control buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Skip backward button (hidden when seeking is disabled)
                if (!widget.disableSeeking)
                  IconButton(
                    onPressed: _skipBackward,
                    icon: const Icon(
                      Icons.replay_10,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),

                if (!widget.disableSeeking) const SizedBox(width: 8),

                // Play/Pause button
                IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 36,
                  ),
                ),

                if (!widget.disableSeeking) const SizedBox(width: 8),

                // Skip forward button (hidden when seeking is disabled)
                if (!widget.disableSeeking)
                  IconButton(
                    onPressed: _skipForward,
                    icon: const Icon(
                      Icons.forward_10,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),

                const Spacer(),

                // Speed control
                _buildSpeedButton(),

                const SizedBox(width: 8),

                // Volume control (mute button only)
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
      return Container(
        color: Colors.black,
      );
    }


    return Container(
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

          // Double-tap zones for skip
          Row(
            children: [
              // Left zone - skip backward (or just toggle controls when seeking disabled)
              Expanded(
                child: GestureDetector(
                  onTap: _toggleControls,
                  onDoubleTap: widget.disableSeeking ? null : () => _skipBackward(),
                  child: Container(color: Colors.transparent),
                ),
              ),
              // Right zone - skip forward (or just toggle controls when seeking disabled)
              Expanded(
                child: GestureDetector(
                  onTap: _toggleControls,
                  onDoubleTap: widget.disableSeeking ? null : () => _skipForward(),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),

          // Skip feedback overlay
          if (_skipFeedback != null)
            Center(
              child: AnimatedOpacity(
                opacity: _skipFeedback != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _skipFeedback!.startsWith('-') ? Icons.replay_10 : Icons.forward_10,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _skipFeedback!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Watermark overlay
          if (widget.showWatermark && widget.userName != null)
            VideoWatermark(userName: widget.userName!),

          // Bottom controls overlay with fade animation - positioned at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _controlsAnimation,
              child: _buildControls(),
            ),
          ),

          // Center controls overlay with fade animation - on top for tap handling
          FadeTransition(
            opacity: _controlsAnimation,
            child: _buildCenterControls(),
          ),
        ],
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
  /// When true, all seeking controls are disabled in fullscreen mode.
  final bool disableSeeking;

  const _FullscreenVideoPlayer({
    required this.sharedController,
    this.title,
    required this.wasPlaying,
    this.userName,
    this.showWatermark = true,
    required this.onExit,
    required this.volume,
    required this.isMuted,
    this.disableSeeking = false,
  });

  @override
  State<_FullscreenVideoPlayer> createState() => _FullscreenVideoPlayerState();
}

class _FullscreenVideoPlayerState extends State<_FullscreenVideoPlayer> 
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _showControls = true;
  late double _volume;
  late bool _isMuted;
  double _playbackSpeed = 1.0;
  Timer? _hideControlsTimer;
  String? _skipFeedback;
  Timer? _skipFeedbackTimer;
  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsAnimation;

  @override
  void initState() {
    super.initState();
    
    // Add lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    
    _controller = widget.sharedController;
    _volume = widget.volume;
    _isMuted = widget.isMuted;
    
    _controlsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _controlsAnimation = CurvedAnimation(
      parent: _controlsAnimationController,
      curve: Curves.easeInOut,
    );
    _controlsAnimationController.forward();
    
    _setFullscreenMode();
    _resumePlaybackIfNeeded();
    
    // Add listener to manage wake lock in fullscreen mode
    _controller.addListener(_handlePlaybackStateChange);
  }

  @override
  void deactivate() {
    // Pause video when exiting fullscreen
    if (_controller.value.isInitialized && _controller.value.isPlaying) {
      _controller.pause();
      Logger.i('🎬 Fullscreen video paused due to navigation');
    }
    super.deactivate();
  }

  @override
  void dispose() {
    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    
    // Cancel timers
    _hideControlsTimer?.cancel();
    _skipFeedbackTimer?.cancel();
    
    // Pause video before cleanup
    if (_controller.value.isInitialized && _controller.value.isPlaying) {
      _controller.pause();
    }
    
    // Remove listener and disable wake lock
    _controller.removeListener(_handlePlaybackStateChange);
    _disableWakelock();
    
    // Dispose animation controller
    _controlsAnimationController.dispose();
    
    // Don't dispose the shared controller, just restore system UI
    _exitFullscreenMode();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (!_controller.value.isInitialized) return;

    // Pause video when app goes to background or is paused
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_controller.value.isPlaying) {
        _controller.pause();
        Logger.i('🎬 Fullscreen video paused due to app lifecycle change: $state');
      }
    }
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
    _hideControlsTimer?.cancel();

    if (!_showControls) {
      _controlsAnimationController.forward();
    }

    setState(() {
      _showControls = true;
    });

    _hideControlsTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _controller.value.isPlaying) {
        _controlsAnimationController.reverse();
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// Pause the auto-hide timer while scrubbing.
  void _pauseControlsTimer() {
    _hideControlsTimer?.cancel();
    if (!_showControls) {
      _controlsAnimationController.forward();
      setState(() {
        _showControls = true;
      });
    }
  }

  /// Resume the auto-hide timer after scrubbing ends.
  void _resumeControlsTimer() {
    _showControlsTemporarily();
  }
  
  void _toggleControls() {
    if (_showControls) {
      _hideControlsTimer?.cancel();
      _controlsAnimationController.reverse();
      setState(() {
        _showControls = false;
      });
    } else {
      _showControlsTemporarily();
    }
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

  // Throttle tracking for fullscreen playback rebuilds
  bool? _lastPlayingState;
  int _lastPositionSeconds = -1;

  // Wake lock management methods for fullscreen mode
  void _handlePlaybackStateChange() {
    if (!_controller.value.isInitialized) return;
    
    final isPlaying = _controller.value.isPlaying;
    
    if (isPlaying) {
      _enableWakelock();
    } else {
      _disableWakelock();
    }

    // Throttled rebuild: only call setState when the play/pause state changes
    // or when the position advances by ≥1 second.
    final posSeconds = _controller.value.position.inSeconds;
    final stateChanged = isPlaying != _lastPlayingState;
    final positionAdvanced = posSeconds != _lastPositionSeconds;
    
    if (stateChanged || positionAdvanced) {
      _lastPlayingState = isPlaying;
      _lastPositionSeconds = posSeconds;
      if (mounted) setState(() {});
    }
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
      Logger.i('🔒 Wake lock enabled in fullscreen - screen will stay on during video playback');
    } catch (e) {
      Logger.e('Failed to enable wake lock in fullscreen: $e');
    }
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
      Logger.i('🔓 Wake lock disabled in fullscreen - normal screen timeout restored');
    } catch (e) {
      Logger.e('Failed to disable wake lock in fullscreen: $e');
    }
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

  static const List<double> _speedOptions = [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 0.5, 0.75];

  void _cycleSpeed() {
    if (!_controller.value.isInitialized) return;
    final currentIndex = _speedOptions.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speedOptions.length;
    setState(() {
      _playbackSpeed = _speedOptions[nextIndex];
      _controller.setPlaybackSpeed(_playbackSpeed);
    });
    _showControlsTemporarily();
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

  void _skipBackward({bool showFeedback = true}) {
    if (!_controller.value.isInitialized) return;

    // Haptic feedback
    HapticFeedback.lightImpact();

    final currentPosition = _controller.value.position;
    final newPosition = currentPosition - const Duration(seconds: 10);
    
    // Don't go before the start
    final targetPosition = newPosition < Duration.zero ? Duration.zero : newPosition;
    
    _controller.seekTo(targetPosition);
    
    if (showFeedback) {
      _showSkipFeedback('- 10s');
    }
    _showControlsTemporarily();
  }

  void _skipForward({bool showFeedback = true}) {
    if (!_controller.value.isInitialized) return;

    // Haptic feedback
    HapticFeedback.lightImpact();

    final currentPosition = _controller.value.position;
    final duration = _controller.value.duration;
    final newPosition = currentPosition + const Duration(seconds: 10);
    
    // Don't go past the end
    final targetPosition = newPosition > duration ? duration : newPosition;
    
    _controller.seekTo(targetPosition);
    
    if (showFeedback) {
      _showSkipFeedback('+ 10s');
    }
    _showControlsTemporarily();
  }
  
  void _showSkipFeedback(String text) {
    _skipFeedbackTimer?.cancel();
    
    setState(() {
      _skipFeedback = text;
    });
    
    _skipFeedbackTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _skipFeedback = null;
        });
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

  Widget _buildCenterControls() {
    if (!_showControls || !_controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final isPlaying = _controller.value.isPlaying;

    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.disableSeeking)
            IconButton(
              onPressed: _skipBackward,
              icon: const Icon(
                Icons.replay_10,
                color: Colors.white,
                size: 48,
              ),
            ),
          if (!widget.disableSeeking) const SizedBox(width: 32),
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: _togglePlayPause,
              iconSize: 64,
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 64,
              ),
            ),
          ),
          if (!widget.disableSeeking) const SizedBox(width: 32),
          if (!widget.disableSeeking)
            IconButton(
              onPressed: _skipForward,
              icon: const Icon(
                Icons.forward_10,
                color: Colors.white,
                size: 48,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeedButton() {
    final label = _playbackSpeed == _playbackSpeed.roundToDouble()
        ? '${_playbackSpeed.toInt()}x'
        : '${_playbackSpeed}x';
    return GestureDetector(
      onTap: _cycleSpeed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white54, width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
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
                child: CustomVideoProgressBar(
                  controller: _controller,
                  playedColor: const Color(0xFFFF0000),
                  bufferedColor: const Color(0x80FFFFFF),
                  backgroundColor: const Color(0x33FFFFFF),
                  thumbColor: const Color(0xFFFF0000),
                  barHeight: 3.0,
                  activeBarHeight: 5.0,
                  thumbRadius: 6.0,
                  activeThumbRadius: 8.0,
                  onDragStart: _pauseControlsTimer,
                  onDragEnd: _resumeControlsTimer,
                  disableSeeking: widget.disableSeeking,
                ),
              ),

              // Control buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Skip backward button (hidden when seeking is disabled)
                    if (!widget.disableSeeking)
                      IconButton(
                        onPressed: _skipBackward,
                        icon: const Icon(
                          Icons.replay_10,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),

                    // Play/Pause button
                    IconButton(
                      onPressed: _togglePlayPause,
                      icon: Icon(
                        isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),

                    // Skip forward button (hidden when seeking is disabled)
                    if (!widget.disableSeeking)
                      IconButton(
                        onPressed: _skipForward,
                        icon: const Icon(
                          Icons.forward_10,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),

                    const SizedBox(width: 16),

                    // Time display
                    Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),

                    const Spacer(),

                    // Speed control
                    _buildSpeedButton(),

                    const SizedBox(width: 12),

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
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _handleBackPressed();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _controller.value.isInitialized
            ? Stack(
                fit: StackFit.expand,
                children: [
                  // Video player
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),

                  // Double-tap zones for skip
                  Row(
                    children: [
                      // Left zone - skip backward (disabled when seeking is blocked)
                      Expanded(
                        child: GestureDetector(
                          onTap: _toggleControls,
                          onDoubleTap: widget.disableSeeking ? null : () => _skipBackward(),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      // Center zone - exit fullscreen
                      GestureDetector(
                        onDoubleTap: _exitFullscreen,
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.2,
                          color: Colors.transparent,
                        ),
                      ),
                      // Right zone - skip forward (disabled when seeking is blocked)
                      Expanded(
                        child: GestureDetector(
                          onTap: _toggleControls,
                          onDoubleTap: widget.disableSeeking ? null : () => _skipForward(),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ],
                  ),

                  // Skip feedback overlay
                  if (_skipFeedback != null)
                    Center(
                      child: AnimatedOpacity(
                        opacity: _skipFeedback != null ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _skipFeedback!.startsWith('-') ? Icons.replay_10 : Icons.forward_10,
                                color: Colors.white,
                                size: 48,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _skipFeedback!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Watermark overlay
                  if (widget.showWatermark && widget.userName != null)
                    FullscreenVideoWatermark(userName: widget.userName!),

                  // Fullscreen controls - full height for top+bottom gradient
                  FadeTransition(
                    opacity: _controlsAnimation,
                    child: _buildFullscreenControls(),
                  ),

                  // Center controls overlay - rendered on top so they receive taps
                  FadeTransition(
                    opacity: _controlsAnimation,
                    child: _buildCenterControls(),
                  ),
                ],
              )
            : Container(
                color: Colors.black,
              ),
      ),
    );
  }
}

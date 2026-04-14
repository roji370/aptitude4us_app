import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../utils/logger.dart';
import 'video_watermark.dart';
import 'custom_video_progress_bar.dart';

/// A cross-platform video player that uses better_player on Android
/// for better codec/device compatibility, and video_player on iOS.
class PlatformVideoPlayer extends StatelessWidget {
  final String videoUrl;
  final String? title;
  final bool autoPlay;
  final String? userName;
  final bool showWatermark;
  final VideoPlayerController? existingController; // For iOS only

  const PlatformVideoPlayer({
    super.key,
    required this.videoUrl,
    this.title,
    this.autoPlay = false,
    this.userName,
    this.showWatermark = true,
    this.existingController,
  });

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return _AndroidVideoPlayer(
        videoUrl: videoUrl,
        title: title,
        autoPlay: autoPlay,
        userName: userName,
        showWatermark: showWatermark,
      );
    } else {
      // iOS - use existing video_player implementation
      return _iOSVideoPlayer(
        videoUrl: videoUrl,
        title: title,
        autoPlay: autoPlay,
        userName: userName,
        showWatermark: showWatermark,
        existingController: existingController,
      );
    }
  }
}

// ============================================================================
// ANDROID VIDEO PLAYER (using better_player)
// ============================================================================
class _AndroidVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? title;
  final bool autoPlay;
  final String? userName;
  final bool showWatermark;

  const _AndroidVideoPlayer({
    required this.videoUrl,
    this.title,
    this.autoPlay = false,
    this.userName,
    this.showWatermark = true,
  });

  @override
  State<_AndroidVideoPlayer> createState() => _AndroidVideoPlayerState();
}

class _AndroidVideoPlayerState extends State<_AndroidVideoPlayer>
    with WidgetsBindingObserver {
  BetterPlayerController? _controller;
  bool _hasError = false;
  String? _errorMessage;
  bool _isLoading = true;
  int _retryCount = 0;
  static const int _maxRetries = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disableWakelock();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _controller?.pause();
      _disableWakelock();
    }
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });

    try {
      Logger.i('Android: Initializing better_player: ${widget.videoUrl}');

      // Data source with caching and buffering optimized for Android
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.videoUrl,
        cacheConfiguration: const BetterPlayerCacheConfiguration(
          useCache: true,
          maxCacheSize: 100 * 1024 * 1024, // 100MB total cache
          maxCacheFileSize: 50 * 1024 * 1024, // 50MB per file
        ),
        // Optimized buffering for low-end devices
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 10000, // 10s min buffer (lower for faster start)
          maxBufferMs: 30000, // 30s max buffer (lower for less memory)
          bufferForPlaybackMs: 2000, // Start after 2s
          bufferForPlaybackAfterRebufferMs: 4000, // 4s after rebuffer
        ),
      );

      final configuration = BetterPlayerConfiguration(
        autoPlay: widget.autoPlay,
        looping: false,
        aspectRatio: 16 / 9,
        fit: BoxFit.contain,
        handleLifecycle: true,
        autoDetectFullscreenAspectRatio: true,
        autoDetectFullscreenDeviceOrientation: true,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enablePlayPause: true,
          enableMute: true,
          enableFullscreen: true,
          enableProgressBar: true,
          enableProgressText: true,
          enableSkips: true,
          enableQualities: true, // Enable quality picker (for HLS/DASH)
          enableAudioTracks: true,
          skipBackIcon: Icons.replay_10,
          skipForwardIcon: Icons.forward_10,
          forwardSkipTimeInMilliseconds: 10000,
          backwardSkipTimeInMilliseconds: 10000,
          controlBarColor: Colors.black54,
          textColor: Colors.white,
          iconsColor: Colors.white,
          progressBarPlayedColor: const Color(0xFFFF0000), // YouTube red
          progressBarHandleColor: const Color(0xFFFF0000), // YouTube red
          progressBarBufferedColor: const Color(0x80FFFFFF), // Semi-transparent white
          progressBarBackgroundColor: const Color(0x33FFFFFF), // More transparent white
          loadingColor: Colors.white,
          showControlsOnInitialize: true,
          controlsHideTime: const Duration(seconds: 3),
        ),
        errorBuilder: (context, errorMessage) {
          return _buildErrorWidget(errorMessage ?? 'Playback error');
        },
        placeholder: _buildLoadingWidget(),
        deviceOrientationsOnFullScreen: [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: [
          DeviceOrientation.portraitUp,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );

      _controller = BetterPlayerController(configuration);
      _controller!.addEventsListener(_handlePlayerEvent);
      await _controller!.setupDataSource(dataSource);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        Logger.i('Android: Video player initialized successfully');
      }
    } catch (e) {
      Logger.e('Android: Error initializing video: $e');
      _handleInitializationError(e);
    }
  }

  void _handlePlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.exception:
        Logger.e('Android: Video exception: ${event.parameters}');
        _handlePlaybackError(event.parameters?['exception']?.toString());
        break;
      case BetterPlayerEventType.play:
        _enableWakelock();
        break;
      case BetterPlayerEventType.pause:
      case BetterPlayerEventType.finished:
        _disableWakelock();
        break;
      case BetterPlayerEventType.bufferingStart:
        Logger.d('Android: Buffering started');
        break;
      case BetterPlayerEventType.bufferingEnd:
        Logger.d('Android: Buffering ended');
        break;
      case BetterPlayerEventType.initialized:
        Logger.i('Android: Video initialized');
        break;
      default:
        break;
    }
  }

  void _handleInitializationError(dynamic error) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      Logger.i('Android: Retry attempt $_retryCount/$_maxRetries');
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _initializePlayer();
      });
    } else {
      if (mounted) {
        setState(() {
          _hasError = true;
          _isLoading = false;
          _errorMessage = _getErrorMessage(error);
        });
      }
    }
  }

  void _handlePlaybackError(String? error) {
    if (_retryCount < _maxRetries) {
      _retryCount++;
      Logger.i('Android: Playback retry attempt $_retryCount/$_maxRetries');
      _controller?.retryDataSource();
    } else {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = _getErrorMessage(error);
        });
      }
    }
  }

  String _getErrorMessage(dynamic error) {
    final errorStr = error?.toString().toLowerCase() ?? '';
    if (errorStr.contains('timeout')) {
      return 'Video loading timed out.\nPlease check your connection.';
    } else if (errorStr.contains('source') ||
        errorStr.contains('codec') ||
        errorStr.contains('format') ||
        errorStr.contains('unsupported')) {
      return 'Video format not supported on this device.\nPlease try a different video.';
    } else if (errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return 'Network error.\nPlease check your connection.';
    } else if (errorStr.contains('permission') ||
        errorStr.contains('403')) {
      return 'Access denied.\nPlease verify your permissions.';
    }
    return 'Unable to play video.\nPlease try again.';
  }

  void _retryInitialization() {
    _retryCount = 0;
    _controller?.dispose();
    _controller = null;
    _initializePlayer();
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (e) {
      Logger.e('Failed to enable wakelock: $e');
    }
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (e) {
      Logger.e('Failed to disable wakelock: $e');
    }
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text('Loading video...', style: TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _retryInitialization,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF323483),
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorWidget(_errorMessage ?? 'Unable to play video');
    }

    if (_isLoading || _controller == null) {
      return _buildLoadingWidget();
    }

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: BetterPlayer(controller: _controller!)),
          if (widget.showWatermark && widget.userName != null)
            VideoWatermark(userName: widget.userName!),
        ],
      ),
    );
  }
}

// ============================================================================
// iOS VIDEO PLAYER (using video_player - same as SimpleVideoPlayer)
// ============================================================================
class _iOSVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final String? title;
  final bool autoPlay;
  final String? userName;
  final bool showWatermark;
  final VideoPlayerController? existingController;

  const _iOSVideoPlayer({
    required this.videoUrl,
    this.title,
    this.autoPlay = false,
    this.userName,
    this.showWatermark = true,
    this.existingController,
  });

  @override
  State<_iOSVideoPlayer> createState() => _iOSVideoPlayerState();
}

class _iOSVideoPlayerState extends State<_iOSVideoPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _showControls = true;
  double _volume = 1.0;
  bool _isMuted = false;
  Timer? _hideControlsTimer;
  String? _skipFeedback;
  Timer? _skipFeedbackTimer;
  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsAnimation;

  @override
  void initState() {
    super.initState();
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
    if (_controller != null &&
        _controller!.value.isInitialized &&
        _controller!.value.isPlaying) {
      _controller!.pause();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _skipFeedbackTimer?.cancel();

    if (_controller != null &&
        _controller!.value.isInitialized &&
        _controller!.value.isPlaying) {
      _controller!.pause();
    }

    _controller?.removeListener(_handlePlaybackStateChange);
    _disableWakelock();
    _controlsAnimationController.dispose();

    if (widget.existingController == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_controller!.value.isPlaying) {
        _controller!.pause();
      }
    }
  }

  void _useExistingController() {
    _controller = widget.existingController!;
    setState(() {
      _isInitialized = _controller!.value.isInitialized;
    });
    _controller!.addListener(_handlePlaybackStateChange);
    if (widget.autoPlay && !_controller!.value.isPlaying) {
      _controller!.play();
    }
    _showControlsTemporarily();
    Logger.i('iOS: Using existing controller for ${widget.videoUrl}');
  }

  Future<void> _initializePlayer() async {
    try {
      Logger.i('iOS: Initializing video_player: ${widget.videoUrl}');
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _controller!.addListener(_handlePlaybackStateChange);
        if (widget.autoPlay) {
          await _controller!.play();
        }
        _showControlsTemporarily();
      }
    } catch (e) {
      Logger.e('iOS: Error initializing video: $e');
    }
  }

  void _handlePlaybackStateChange() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isPlaying) {
      _enableWakelock();
    } else {
      _disableWakelock();
    }
    // Rebuild so the time display and play/pause icon stay live during playback.
    if (mounted) setState(() {});
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

  void _toggleMute() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : _volume);
    });
  }

  void _skipBackward() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    HapticFeedback.lightImpact();
    final pos = _controller!.value.position - const Duration(seconds: 10);
    _controller!.seekTo(pos < Duration.zero ? Duration.zero : pos);
    _showSkipFeedback('- 10s');
    _showControlsTemporarily();
  }

  void _skipForward() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    HapticFeedback.lightImpact();
    final pos = _controller!.value.position + const Duration(seconds: 10);
    final dur = _controller!.value.duration;
    _controller!.seekTo(pos > dur ? dur : pos);
    _showSkipFeedback('+ 10s');
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

    final wasPlaying = _controller!.value.isPlaying;
    if (wasPlaying) {
      _controller!.pause();
    }

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return _iOSFullscreenVideoPlayer(
            sharedController: _controller!,
            title: widget.title,
            wasPlaying: wasPlaying,
            userName: widget.userName,
            showWatermark: widget.showWatermark,
            onExit: (wasPlayingOnExit) {
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

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
  }

  Widget _buildControls() {
    if (!_showControls || !_isInitialized) return const SizedBox.shrink();
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('${_formatDuration(pos)} / ${_formatDuration(dur)}',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _toggleFullscreen,
                  icon: const Icon(Icons.fullscreen, color: Colors.white, size: 24),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _skipBackward,
                  icon:
                      const Icon(Icons.replay_10, color: Colors.white, size: 32),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _togglePlayPause,
                  icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white, size: 36),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _skipForward,
                  icon: const Icon(Icons.forward_10,
                      color: Colors.white, size: 32),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _toggleMute,
                  icon: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
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

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text('Loading video...', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _toggleControls,
                  onDoubleTap: _skipBackward,
                  child: Container(color: Colors.transparent),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _toggleControls,
                  onDoubleTap: _skipForward,
                  child: Container(color: Colors.transparent),
                ),
              ),
            ],
          ),
          if (_skipFeedback != null)
            Center(
              child: AnimatedOpacity(
                opacity: _skipFeedback != null ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _skipFeedback!.startsWith('-')
                            ? Icons.replay_10
                            : Icons.forward_10,
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
          if (widget.showWatermark && widget.userName != null)
            VideoWatermark(userName: widget.userName!),
          FadeTransition(
            opacity: _controlsAnimation,
            child: _buildControls(),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// iOS FULLSCREEN VIDEO PLAYER
// ============================================================================
class _iOSFullscreenVideoPlayer extends StatefulWidget {
  final VideoPlayerController sharedController;
  final String? title;
  final bool wasPlaying;
  final String? userName;
  final bool showWatermark;
  final Function(bool wasPlaying) onExit;
  final double volume;
  final bool isMuted;

  const _iOSFullscreenVideoPlayer({
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
  State<_iOSFullscreenVideoPlayer> createState() =>
      _iOSFullscreenVideoPlayerState();
}

class _iOSFullscreenVideoPlayerState extends State<_iOSFullscreenVideoPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late VideoPlayerController _controller;
  bool _showControls = true;
  late double _volume;
  late bool _isMuted;
  Timer? _hideControlsTimer;
  String? _skipFeedback;
  Timer? _skipFeedbackTimer;
  late AnimationController _controlsAnimationController;
  late Animation<double> _controlsAnimation;

  @override
  void initState() {
    super.initState();
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
    _controller.addListener(_handlePlaybackStateChange);
  }

  @override
  void deactivate() {
    if (_controller.value.isInitialized && _controller.value.isPlaying) {
      _controller.pause();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideControlsTimer?.cancel();
    _skipFeedbackTimer?.cancel();

    if (_controller.value.isInitialized && _controller.value.isPlaying) {
      _controller.pause();
    }

    _controller.removeListener(_handlePlaybackStateChange);
    _disableWakelock();
    _controlsAnimationController.dispose();
    _exitFullscreenMode();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      if (_controller.value.isPlaying) {
        _controller.pause();
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
    if (widget.wasPlaying && _controller.value.isInitialized) {
      _controller.play();
    }
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

  /// Pause the auto-hide timer while the user is scrubbing.
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

  void _handlePlaybackStateChange() {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      _enableWakelock();
    } else {
      _disableWakelock();
    }
    // Rebuild so the time display and play/pause icon stay live during playback.
    if (mounted) setState(() {});
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  void _toggleMute() {
    if (!_controller.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0.0 : _volume);
    });
  }

  void _setVolume(double volume) {
    if (!_controller.value.isInitialized) return;
    setState(() {
      _volume = volume;
      if (!_isMuted) {
        _controller.setVolume(volume);
      }
      if (_isMuted && volume > 0) {
        _isMuted = false;
      }
    });
  }

  void _skipBackward() {
    if (!_controller.value.isInitialized) return;
    HapticFeedback.lightImpact();
    final pos = _controller.value.position - const Duration(seconds: 10);
    _controller.seekTo(pos < Duration.zero ? Duration.zero : pos);
    _showSkipFeedback('- 10s');
    _showControlsTemporarily();
  }

  void _skipForward() {
    if (!_controller.value.isInitialized) return;
    HapticFeedback.lightImpact();
    final pos = _controller.value.position + const Duration(seconds: 10);
    final dur = _controller.value.duration;
    _controller.seekTo(pos > dur ? dur : pos);
    _showSkipFeedback('+ 10s');
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
    final isPlaying = _controller.value.isPlaying;
    Navigator.of(context).pop();
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onExit(isPlaying);
    });
  }

  void _handleBackPressed() {
    final isPlaying = _controller.value.isPlaying;
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onExit(isPlaying);
    });
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}';
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
                  icon: const Icon(Icons.fullscreen_exit,
                      color: Colors.white, size: 32),
                ),
              ],
            ),
          ),
          const Spacer(),
          Column(
            children: [
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
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _skipBackward,
                      icon: const Icon(Icons.replay_10,
                          color: Colors.white, size: 32),
                    ),
                    IconButton(
                      onPressed: _togglePlayPause,
                      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white, size: 36),
                    ),
                    IconButton(
                      onPressed: _skipForward,
                      icon: const Icon(Icons.forward_10,
                          color: Colors.white, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      '${_formatDuration(position)} / ${_formatDuration(duration)}',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                    const Spacer(),
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
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 8),
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

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
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
                  Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _toggleControls,
                          onDoubleTap: _skipBackward,
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      GestureDetector(
                        onDoubleTap: _exitFullscreen,
                        child: Container(
                          width: MediaQuery.of(context).size.width * 0.2,
                          color: Colors.transparent,
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: _toggleControls,
                          onDoubleTap: _skipForward,
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                    ],
                  ),
                  if (_skipFeedback != null)
                    Center(
                      child: AnimatedOpacity(
                        opacity: _skipFeedback != null ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 16),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _skipFeedback!.startsWith('-')
                                    ? Icons.replay_10
                                    : Icons.forward_10,
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
                  if (widget.showWatermark && widget.userName != null)
                    FullscreenVideoWatermark(userName: widget.userName!),
                  FadeTransition(
                    opacity: _controlsAnimation,
                    child: _buildFullscreenControls(),
                  ),
                ],
              )
            : Container(color: Colors.black),
      ),
    );
  }
}




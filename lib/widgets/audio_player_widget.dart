import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../utils/logger.dart';

/// A widget for playing audio content within the app
class AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  final String title;
  final String userName;

  const AudioPlayerWidget({
    super.key,
    required this.audioUrl,
    required this.title,
    required this.userName,
  });

  @override
  State<AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<AudioPlayerWidget> {
  late final AudioPlayer _player;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  double _playbackSpeed = 1.0;

  static const List<double> _speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      Logger.i('Initializing audio player for: ${widget.title}');
      Logger.d('Audio URL: ${widget.audioUrl}');

      await _player.setUrl(widget.audioUrl);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      Logger.i('Audio player initialized successfully');
    } catch (e) {
      Logger.e('Error initializing audio player: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'Failed to load audio: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '--:--';
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (duration.inHours > 0) {
      final hours = duration.inHours.toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  void _changeSpeed() {
    final currentIndex = _speedOptions.indexOf(_playbackSpeed);
    final nextIndex = (currentIndex + 1) % _speedOptions.length;
    setState(() {
      _playbackSpeed = _speedOptions[nextIndex];
    });
    _player.setSpeed(_playbackSpeed);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading audio...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
                _initAudio();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Album art / audio icon
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: const Color(0xFF9C27B0).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF9C27B0).withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Icon(
                Icons.headphones,
                size: 80,
                color: Color(0xFF9C27B0),
              ),
            ),

            const SizedBox(height: 32),

            // Title
            Text(
              widget.title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 32),

            // Progress bar
            StreamBuilder<Duration?>(
              stream: _player.durationStream,
              builder: (context, totalSnapshot) {
                final total = totalSnapshot.data ?? Duration.zero;
                return StreamBuilder<Duration>(
                  stream: _player.positionStream,
                  builder: (context, posSnapshot) {
                    final position = posSnapshot.data ?? Duration.zero;
                    return Column(
                      children: [
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFF9C27B0),
                            inactiveTrackColor:
                                const Color(0xFF9C27B0).withValues(alpha: 0.2),
                            thumbColor: const Color(0xFF9C27B0),
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 8,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
                            value: position.inMilliseconds
                                .toDouble()
                                .clamp(0, total.inMilliseconds.toDouble().clamp(1, double.infinity)),
                            onChanged: (value) {
                              _player.seek(
                                Duration(milliseconds: value.toInt()),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                              Text(
                                _formatDuration(total),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),

            const SizedBox(height: 16),

            // Playback controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Speed button
                TextButton(
                  onPressed: _changeSpeed,
                  style: TextButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF9C27B0).withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    '${_playbackSpeed}x',
                    style: const TextStyle(
                      color: Color(0xFF9C27B0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // Rewind 10s
                IconButton(
                  onPressed: () {
                    final newPos =
                        _player.position - const Duration(seconds: 10);
                    _player.seek(
                      newPos < Duration.zero ? Duration.zero : newPos,
                    );
                  },
                  icon: const Icon(Icons.replay_10),
                  iconSize: 36,
                  color: Colors.grey[700],
                ),

                const SizedBox(width: 8),

                // Play/Pause button
                StreamBuilder<PlayerState>(
                  stream: _player.playerStateStream,
                  builder: (context, snapshot) {
                    final playerState = snapshot.data;
                    final processingState = playerState?.processingState;
                    final playing = playerState?.playing ?? false;

                    if (processingState == ProcessingState.loading ||
                        processingState == ProcessingState.buffering) {
                      return Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Color(0xFF9C27B0),
                          shape: BoxShape.circle,
                        ),
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        ),
                      );
                    }

                    if (processingState == ProcessingState.completed) {
                      return Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Color(0xFF9C27B0),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          onPressed: () {
                            _player.seek(Duration.zero);
                            _player.play();
                          },
                          icon: const Icon(Icons.replay, color: Colors.white),
                          iconSize: 32,
                        ),
                      );
                    }

                    return Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: Color(0xFF9C27B0),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        onPressed: () {
                          if (playing) {
                            _player.pause();
                          } else {
                            _player.play();
                          }
                        },
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                        ),
                        iconSize: 32,
                      ),
                    );
                  },
                ),

                const SizedBox(width: 8),

                // Forward 30s
                IconButton(
                  onPressed: () {
                    final duration = _player.duration ?? Duration.zero;
                    final newPos =
                        _player.position + const Duration(seconds: 30);
                    _player.seek(newPos > duration ? duration : newPos);
                  },
                  icon: const Icon(Icons.forward_30),
                  iconSize: 36,
                  color: Colors.grey[700],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

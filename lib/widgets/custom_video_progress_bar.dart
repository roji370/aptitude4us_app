import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// A custom video progress bar with a visible draggable knob
class CustomVideoProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
  final Color thumbColor;
  final double barHeight;
  final double activeBarHeight;
  final double thumbRadius;
  final double activeThumbRadius;

  const CustomVideoProgressBar({
    super.key,
    required this.controller,
    this.playedColor = const Color(0xFFFF0000), // YouTube red
    this.bufferedColor = const Color(0x80FFFFFF), // Semi-transparent white
    this.backgroundColor = const Color(0x33FFFFFF), // More transparent white
    this.thumbColor = const Color(0xFFFF0000), // YouTube red
    this.barHeight = 3.0, // Thin when inactive
    this.activeBarHeight = 5.0, // Thicker when active
    this.thumbRadius = 6.0, // Small when inactive
    this.activeThumbRadius = 8.0, // Larger when dragging
  });

  @override
  State<CustomVideoProgressBar> createState() => _CustomVideoProgressBarState();
}

class _CustomVideoProgressBarState extends State<CustomVideoProgressBar>
    with SingleTickerProviderStateMixin {
  bool _isDragging = false;
  bool _isSeeking = false;
  double? _dragValue;
  Timer? _seekDebounceTimer;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerUpdate);
    
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _seekDebounceTimer?.cancel();
    _scaleController.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    // Only update UI if we're not dragging or seeking
    if (!_isDragging && !_isSeeking && mounted) {
      setState(() {});
    }
  }

  Future<void> _seekToRelativePosition(double relativePosition) async {
    final duration = widget.controller.value.duration;
    if (duration.inMilliseconds > 0) {
      setState(() {
        _isSeeking = true;
      });

      final position = duration * relativePosition;
      
      try {
        await widget.controller.seekTo(position);
        
        // Wait a bit for the video player to stabilize after seeking
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        // Handle seek errors gracefully
      } finally {
        if (mounted) {
          setState(() {
            _isSeeking = false;
            _dragValue = null; // Clear drag value only after seek completes
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final duration = value.duration;
    
    // Use drag value if we're dragging OR if we're seeking with a drag value
    // This prevents snap-back when releasing the drag
    final position = (_isDragging || _isSeeking) && _dragValue != null
        ? duration * _dragValue!
        : value.position;

    // Calculate progress percentages
    double playedPercentage = 0.0;
    double bufferedPercentage = 0.0;

    if (duration.inMilliseconds > 0) {
      playedPercentage = position.inMilliseconds / duration.inMilliseconds;
      playedPercentage = playedPercentage.clamp(0.0, 1.0);

      if (value.buffered.isNotEmpty) {
        final bufferedEnd = value.buffered.last.end;
        bufferedPercentage = bufferedEnd.inMilliseconds / duration.inMilliseconds;
        bufferedPercentage = bufferedPercentage.clamp(0.0, 1.0);
      }
    }

    return GestureDetector(
      onHorizontalDragStart: (details) {
        HapticFeedback.lightImpact();
        _scaleController.forward();
        setState(() {
          _isDragging = true;
          _isSeeking = false;
        });
      },
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = box.globalToLocal(details.globalPosition);
          final relativePosition = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
          setState(() {
            _dragValue = relativePosition;
          });
        }
      },
      onHorizontalDragEnd: (details) {
        _scaleController.reverse();
        if (_dragValue != null) {
          HapticFeedback.mediumImpact();
          final seekValue = _dragValue!;
          
          // Set dragging to false but keep dragValue until seek completes
          setState(() {
            _isDragging = false;
            // Don't clear _dragValue here - it will be cleared after seek completes
          });
          
          // Perform seek - dragValue will be cleared in _seekToRelativePosition
          _seekToRelativePosition(seekValue);
        } else {
          setState(() {
            _isDragging = false;
          });
        }
      },
      onTapDown: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          HapticFeedback.lightImpact();
          final localPosition = box.globalToLocal(details.globalPosition);
          final relativePosition = (localPosition.dx / box.size.width).clamp(0.0, 1.0);
          _seekToRelativePosition(relativePosition);
        }
      },
      child: Container(
        height: 40, // Increased touch area
        color: Colors.transparent,
        alignment: Alignment.center,
        child: SizedBox(
          height: widget.activeBarHeight + (widget.activeThumbRadius * 2),
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, child) {
              final animatedBarHeight = widget.barHeight +
                  (widget.activeBarHeight - widget.barHeight) * _scaleAnimation.value;
              final animatedThumbRadius = widget.thumbRadius +
                  (widget.activeThumbRadius - widget.thumbRadius) * _scaleAnimation.value;
              
              return CustomPaint(
                painter: _ProgressBarPainter(
                  playedPercentage: playedPercentage,
                  bufferedPercentage: bufferedPercentage,
                  playedColor: widget.playedColor,
                  bufferedColor: widget.bufferedColor,
                  backgroundColor: widget.backgroundColor,
                  thumbColor: widget.thumbColor,
                  barHeight: animatedBarHeight,
                  thumbRadius: animatedThumbRadius,
                  isDragging: _isDragging,
                ),
                size: Size.infinite,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ProgressBarPainter extends CustomPainter {
  final double playedPercentage;
  final double bufferedPercentage;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
  final Color thumbColor;
  final double barHeight;
  final double thumbRadius;
  final bool isDragging;

  _ProgressBarPainter({
    required this.playedPercentage,
    required this.bufferedPercentage,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
    required this.thumbColor,
    required this.barHeight,
    required this.thumbRadius,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final barTop = centerY - (barHeight / 2);
    final barBottom = centerY + (barHeight / 2);

    // Draw background bar
    final backgroundRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(0, barTop, size.width, barBottom),
      Radius.circular(barHeight / 2),
    );
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;
    canvas.drawRRect(backgroundRect, backgroundPaint);

    // Draw buffered bar
    if (bufferedPercentage > 0) {
      final bufferedWidth = size.width * bufferedPercentage;
      final bufferedRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(0, barTop, bufferedWidth, barBottom),
        Radius.circular(barHeight / 2),
      );
      final bufferedPaint = Paint()
        ..color = bufferedColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(bufferedRect, bufferedPaint);
    }

    // Draw played bar
    if (playedPercentage > 0) {
      final playedWidth = size.width * playedPercentage;
      final playedRect = RRect.fromRectAndRadius(
        Rect.fromLTRB(0, barTop, playedWidth, barBottom),
        Radius.circular(barHeight / 2),
      );
      final playedPaint = Paint()
        ..color = playedColor
        ..style = PaintingStyle.fill;
      canvas.drawRRect(playedRect, playedPaint);
    }

    // Draw thumb (knob)
    final thumbX = size.width * playedPercentage;
    final thumbCenter = Offset(thumbX, centerY);
    
    // Draw shadow for thumb when dragging
    if (isDragging) {
      final shadowPaint = Paint()
        ..color = Colors.black.withOpacity(0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
      canvas.drawCircle(
        thumbCenter.translate(0, 2),
        thumbRadius + 2,
        shadowPaint,
      );
    }

    // Draw outer ring for thumb
    final thumbOuterPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(thumbCenter, thumbRadius + 2, thumbOuterPaint);

    // Draw inner thumb
    final thumbPaint = Paint()
      ..color = thumbColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(thumbCenter, thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(_ProgressBarPainter oldDelegate) {
    return oldDelegate.playedPercentage != playedPercentage ||
        oldDelegate.bufferedPercentage != bufferedPercentage ||
        oldDelegate.isDragging != isDragging;
  }
}

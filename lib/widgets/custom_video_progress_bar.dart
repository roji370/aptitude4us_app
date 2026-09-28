import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// A custom video progress bar with a visible draggable knob.
///
/// Design goals / bug-fixes over the previous implementation:
///  • No snap-back: `_dragValue` is held until the seek fully resolves.
///  • No race condition on dispose: every async code-path guards `mounted`.
///  • No stale repaint: `shouldRepaint` covers every field that changes visually.
///  • No mid-drag controller interference: listener is ignored while dragging
///    OR while an async seek is still in-flight.
///  • Drag-cancel is handled (clears drag state gracefully).
///  • Animation controller `forward`/`reverse` is never called while already
///    at the target value, preventing micro-jank.
///  • RenderBox lookup is cached at drag-start so it never fails mid-update.
///  • Seek is non-debounced at drag-end (fires exactly once, immediately).
///  • onTapDown correctly blocks the listener while seeking.
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
  /// Called when the user starts dragging the thumb.
  /// Use this to pause the controls auto-hide timer in the parent.
  final VoidCallback? onDragStart;
  /// Called when the user finishes dragging the thumb (or cancels).
  /// Use this to restart the controls auto-hide timer in the parent.
  final VoidCallback? onDragEnd;
  /// When true, the progress bar is display-only: dragging and tapping
  /// to seek are disabled. Used for one-time-view videos.
  final bool disableSeeking;

  const CustomVideoProgressBar({
    super.key,
    required this.controller,
    this.playedColor = const Color(0xFFFF0000),
    this.bufferedColor = const Color(0x80FFFFFF),
    this.backgroundColor = const Color(0x33FFFFFF),
    this.thumbColor = const Color(0xFFFF0000),
    this.barHeight = 3.0,
    this.activeBarHeight = 5.0,
    this.thumbRadius = 6.0,
    this.activeThumbRadius = 8.0,
    this.onDragStart,
    this.onDragEnd,
    this.disableSeeking = false,
  });

  @override
  State<CustomVideoProgressBar> createState() => _CustomVideoProgressBarState();
}

class _CustomVideoProgressBarState extends State<CustomVideoProgressBar>
    with SingleTickerProviderStateMixin {
  /// True while the user's finger is on the bar.
  bool _isDragging = false;

  /// True while an async seekTo() is in-flight (finger already released).
  bool _isSeekPending = false;

  /// The relative position [0,1] chosen by the user during drag/tap.
  /// Held until the seek completes so the bar doesn't snap back.
  double? _dragValue;

  /// Cached render box captured at drag-start so mid-update lookups never fail.
  RenderBox? _cachedBox;

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
  void didUpdateWidget(CustomVideoProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerUpdate);
      widget.controller.addListener(_onControllerUpdate);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerUpdate);
    _scaleController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Controller listener
  // ---------------------------------------------------------------------------

  void _onControllerUpdate() {
    // Suppress listener-driven redraws while the user controls the bar.
    if (_isDragging || _isSeekPending) return;
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Seek helper
  // ---------------------------------------------------------------------------

  /// Seek to [relativePosition] (clamped 0–1).  Holds `_isSeekPending = true`
  /// until the future resolves so the bar doesn't snap back.
  Future<void> _seekTo(double relativePosition) async {
    final duration = widget.controller.value.duration;
    if (duration == Duration.zero) return;

    // Mark a seek as in-flight *before* the await so the listener stays quiet.
    if (mounted) {
      setState(() {
        _isSeekPending = true;
        _dragValue = relativePosition; // keep bar at chosen position
      });
    }

    try {
      await widget.controller.seekTo(duration * relativePosition);
    } catch (_) {
      // Seek errors are non-fatal; we simply clear the pending state below.
    }

    if (mounted) {
      setState(() {
        _isSeekPending = false;
        // Only clear _dragValue if no new drag has started while this seek was
        // in-flight. A stale seekTo() resolving mid-drag must NOT snap the bar
        // back to the old target — the current drag position takes priority.
        if (!_isDragging) {
          _dragValue = null;
        }
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Animation helpers
  // ---------------------------------------------------------------------------

  void _animateIn() {
    if (_scaleController.status != AnimationStatus.forward &&
        _scaleController.status != AnimationStatus.completed) {
      _scaleController.forward();
    }
  }

  void _animateOut() {
    if (_scaleController.status != AnimationStatus.reverse &&
        _scaleController.status != AnimationStatus.dismissed) {
      _scaleController.reverse();
    }
  }

  // ---------------------------------------------------------------------------
  // Gesture callbacks
  // ---------------------------------------------------------------------------

  void _onDragStart(DragStartDetails details) {
    // Cache the RenderBox now so mid-update lookups are guaranteed to succeed.
    _cachedBox = context.findRenderObject() as RenderBox?;

    HapticFeedback.lightImpact();
    _animateIn();

    final relPos = _cachedBox != null
        ? (_cachedBox!.globalToLocal(details.globalPosition).dx /
                _cachedBox!.size.width)
            .clamp(0.0, 1.0)
        : null;

    setState(() {
      _isDragging = true;
      // Cancel any in-flight seek immediately so the bar follows the finger.
      _isSeekPending = false;
      if (relPos != null) _dragValue = relPos;
    });

    // Notify parent so it can pause the auto-hide timer.
    widget.onDragStart?.call();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_cachedBox == null) return;
    final relPos =
        (_cachedBox!.globalToLocal(details.globalPosition).dx /
                _cachedBox!.size.width)
            .clamp(0.0, 1.0);

    // Use setState only when the value actually changed to avoid unnecessary
    // repaints on every pointer event.
    if (_dragValue != relPos) {
      setState(() {
        _dragValue = relPos;
      });
    }
  }

  void _onDragEnd(DragEndDetails details) {
    _animateOut();
    _cachedBox = null;

    final seekTarget = _dragValue;
    setState(() {
      _isDragging = false;
      // Keep _dragValue so the bar stays put while the seek is in-flight.
    });

    if (seekTarget != null) {
      HapticFeedback.mediumImpact();
      _seekTo(seekTarget);
    }

    // Notify parent so it can restart the auto-hide timer.
    widget.onDragEnd?.call();
  }

  void _onDragCancel() {
    _animateOut();
    _cachedBox = null;

    setState(() {
      _isDragging = false;
      // On cancel, revert visually to the controller's current position.
      _isSeekPending = false;
      _dragValue = null;
    });

    // Notify parent so it can restart the auto-hide timer.
    widget.onDragEnd?.call();
  }

  void _onTapDown(TapDownDetails details) {
    // A tap that coincides with an active drag (gesture-detector edge case) must
    // not trigger a competing seek — let the drag winner take full control.
    if (_isDragging) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    HapticFeedback.lightImpact();
    final relPos =
        (box.globalToLocal(details.globalPosition).dx / box.size.width)
            .clamp(0.0, 1.0);
    _seekTo(relPos);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final duration = value.duration;

    // During drag/seek use the chosen position to prevent snap-back.
    final effectivePosition = (_isDragging || _isSeekPending) && _dragValue != null
        ? duration * _dragValue!
        : value.position;

    double playedPct = 0.0;
    double bufferedPct = 0.0;

    if (duration.inMilliseconds > 0) {
      playedPct =
          (effectivePosition.inMilliseconds / duration.inMilliseconds)
              .clamp(0.0, 1.0);

      if (value.buffered.isNotEmpty) {
        bufferedPct =
            (value.buffered.last.end.inMilliseconds / duration.inMilliseconds)
                .clamp(0.0, 1.0);
      }
    }

    return GestureDetector(
      // Drag gestures for scrubbing (disabled when seeking is blocked).
      onHorizontalDragStart: widget.disableSeeking ? null : _onDragStart,
      onHorizontalDragUpdate: widget.disableSeeking ? null : _onDragUpdate,
      onHorizontalDragEnd: widget.disableSeeking ? null : _onDragEnd,
      onHorizontalDragCancel: widget.disableSeeking ? null : _onDragCancel,
      // Tap for instant seek (disabled when seeking is blocked).
      onTapDown: widget.disableSeeking ? null : _onTapDown,
      child: Container(
        height: 40, // Generous touch area
        color: Colors.transparent,
        alignment: Alignment.center,
        child: SizedBox(
          height: widget.activeBarHeight + (widget.activeThumbRadius * 2),
          child: AnimatedBuilder(
            animation: _scaleAnimation,
            builder: (context, _) {
              final t = _scaleAnimation.value;
              final barH =
                  widget.barHeight + (widget.activeBarHeight - widget.barHeight) * t;
              final thumbR =
                  widget.thumbRadius +
                  (widget.activeThumbRadius - widget.thumbRadius) * t;

              return CustomPaint(
                painter: _ProgressBarPainter(
                  playedPercentage: playedPct,
                  bufferedPercentage: bufferedPct,
                  playedColor: widget.playedColor,
                  bufferedColor: widget.bufferedColor,
                  backgroundColor: widget.backgroundColor,
                  thumbColor: widget.thumbColor,
                  barHeight: barH,
                  thumbRadius: thumbR,
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

// =============================================================================
// Painter
// =============================================================================

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

  const _ProgressBarPainter({
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
    final barTop = centerY - barHeight / 2;
    final barBottom = centerY + barHeight / 2;
    final radius = Radius.circular(barHeight / 2);

    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTRB(0, barTop, size.width, barBottom), radius),
      Paint()
        ..color = backgroundColor
        ..style = PaintingStyle.fill,
    );

    // Buffered
    if (bufferedPercentage > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(0, barTop, size.width * bufferedPercentage, barBottom),
            radius),
        Paint()
          ..color = bufferedColor
          ..style = PaintingStyle.fill,
      );
    }

    // Played
    if (playedPercentage > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(0, barTop, size.width * playedPercentage, barBottom),
            radius),
        Paint()
          ..color = playedColor
          ..style = PaintingStyle.fill,
      );
    }

    // Thumb
    final thumbX = size.width * playedPercentage;
    final thumbCenter = Offset(thumbX, centerY);

    // Shadow while dragging
    if (isDragging) {
      canvas.drawCircle(
        thumbCenter.translate(0, 2),
        thumbRadius + 2,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }

    // White ring
    canvas.drawCircle(
      thumbCenter,
      thumbRadius + 2,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

    // Coloured inner circle
    canvas.drawCircle(
      thumbCenter,
      thumbRadius,
      Paint()
        ..color = thumbColor
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ProgressBarPainter old) {
    return old.playedPercentage != playedPercentage ||
        old.bufferedPercentage != bufferedPercentage ||
        old.isDragging != isDragging ||
        old.barHeight != barHeight ||
        old.thumbRadius != thumbRadius ||
        old.playedColor != playedColor ||
        old.bufferedColor != bufferedColor ||
        old.backgroundColor != backgroundColor ||
        old.thumbColor != thumbColor;
  }
}

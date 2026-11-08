import 'package:flutter/material.dart';

/// A wrapper that plays a one-shot entrance animation on a child widget.
///
/// Used exclusively for **new** messages (sent or received while the screen is
/// open). Messages from cache, initial load, or pagination should never be
/// wrapped with `animate: true`.
///
/// Animation composition (200 ms, no bounce):
///   SizeTransition (axisAlignment -1)
///     → FadeTransition
///       → ScaleTransition (0.96 → 1.0, aligned to the bubble's tail corner)
///         → child
class NewMessageEntrance extends StatefulWidget {
  final Widget child;
  final bool animate;
  final bool isMe;

  /// Called (without setState) when the entrance animation finishes, so the
  /// parent can remove the id from its `_entering` set. Scrolled-away and
  /// recycled items will therefore never re-animate.
  final VoidCallback? onDone;

  const NewMessageEntrance({
    super.key,
    required this.child,
    required this.animate,
    required this.isMe,
    this.onDone,
  });

  @override
  State<NewMessageEntrance> createState() => _NewMessageEntranceState();
}

class _NewMessageEntranceState extends State<NewMessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _sizeAnimation;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  static const _curve = Cubic(0.2, 0, 0, 1);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    final curved = CurvedAnimation(parent: _controller, curve: _curve);

    _sizeAnimation = curved;

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);

    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(curved);

    // Respect the platform's reduced-motion preference.
    final reduceMotion = WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;

    if (!widget.animate || reduceMotion) {
      _controller.value = 1.0;
      // Fire onDone synchronously so the id is removed immediately.
      widget.onDone?.call();
    } else {
      _controller.forward().then((_) {
        widget.onDone?.call();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: _sizeAnimation,
      // ignore: deprecated_member_use
      axisAlignment: -1.0,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          alignment:
              widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft,
          child: widget.child,
        ),
      ),
    );
  }
}


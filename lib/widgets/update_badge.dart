import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Simple badge showing "NEW" for updates
class UpdateBadge extends StatelessWidget {
  final bool hasUpdate;
  final double? size;

  const UpdateBadge({
    super.key,
    required this.hasUpdate,
    this.size,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasUpdate) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size != null ? size! * 0.5 : 6,
        vertical: size != null ? size! * 0.25 : 3,
      ),
      decoration: BoxDecoration(
        color: Colors.orange,
        borderRadius: BorderRadius.circular(size != null ? size! : 10),
      ),
      child: Text(
        'NEW',
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: size != null ? size! * 0.6 : 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Pulsing dot indicator for updates
class PulsingDot extends StatefulWidget {
  final bool hasUpdate;
  final double size;

  const PulsingDot({
    super.key,
    required this.hasUpdate,
    this.size = 12.0,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasUpdate) return const SizedBox.shrink();

    const color = Colors.orange;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: color.withOpacity(_animation.value),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(_animation.value * 0.5),
                blurRadius: 8 * _animation.value,
                spreadRadius: 2 * _animation.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Update indicator with message
class UpdateIndicator extends StatelessWidget {
  final String message;
  final VoidCallback? onDismiss;

  const UpdateIndicator({
    super.key,
    required this.message,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange[50]!,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.orange[200]!,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: Colors.orange[600]!,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.orange[700]!,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onDismiss != null)
            InkWell(
              onTap: onDismiss,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.orange[700]!,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

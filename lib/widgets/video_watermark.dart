import 'package:flutter/material.dart';

/// Video watermark overlay widget that displays user name across the video
/// Similar to XfiniWatermark but optimized for video content
class VideoWatermark extends StatelessWidget {
  final String userName;
  final double opacity;
  final Color textColor;

  const VideoWatermark({
    super.key,
    required this.userName,
    this.opacity = 0.15,
    this.textColor = const Color(0xFF323483),
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate how many watermarks to show based on screen size
            // Use slightly larger cells for video to avoid cluttering
            final double cellWidth = 200;
            final double cellHeight = 120;
            final int horizontalCount =
                (constraints.maxWidth / cellWidth).ceil();
            final int verticalCount =
                (constraints.maxHeight / cellHeight).ceil();

            return Stack(
              children: [
                for (int y = 0; y < verticalCount; y++)
                  for (int x = 0; x < horizontalCount; x++)
                    Positioned(
                      left: x * cellWidth + (y % 2 == 0 ? 0 : cellWidth / 2),
                      top: y * cellHeight,
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.rotate(
                          angle:
                              -0.15, // Slightly less rotation for better readability on video
                          child: Text(
                            userName,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              shadows: [
                                Shadow(
                                  offset: const Offset(1, 1),
                                  blurRadius: 2,
                                  color: Colors.black.withOpacity(0.3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Fullscreen video watermark with larger text and adjusted positioning
class FullscreenVideoWatermark extends StatelessWidget {
  final String userName;
  final double opacity;
  final Color textColor;

  const FullscreenVideoWatermark({
    super.key,
    required this.userName,
    this.opacity = 0.12,
    this.textColor = const Color(0xFF323483),
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // For fullscreen, use larger cells to avoid overcrowding
            final double cellWidth = 280;
            final double cellHeight = 160;
            final int horizontalCount =
                (constraints.maxWidth / cellWidth).ceil();
            final int verticalCount =
                (constraints.maxHeight / cellHeight).ceil();

            return Stack(
              children: [
                for (int y = 0; y < verticalCount; y++)
                  for (int x = 0; x < horizontalCount; x++)
                    Positioned(
                      left: x * cellWidth + (y % 2 == 0 ? 0 : cellWidth / 3),
                      top: y * cellHeight,
                      child: Opacity(
                        opacity: opacity,
                        child: Transform.rotate(
                          angle: -0.12, // Even less rotation for landscape
                          child: Text(
                            userName,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              shadows: [
                                Shadow(
                                  offset: const Offset(1, 1),
                                  blurRadius: 3,
                                  color: Colors.black.withOpacity(0.4),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

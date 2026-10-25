import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

import '../services/learner_presence_service.dart';

/// Floating, draggable, mirrored front-camera self-preview shown above a
/// playing lecture video.
///
/// This widget is intentionally lightweight so it can be hosted inside a
/// root [OverlayEntry] — that way the preview survives navigation into the
/// fullscreen video route without needing per-route plumbing.
///
/// Visual contract
/// ───────────────
/// * Default position: top-right corner of the parent's bounds.
/// * Rounded corners, soft shadow, "Local Preview Only" badge.
/// * Draggable anywhere inside the parent (bounds-clamped on rotation /
///   fullscreen toggle).
/// * Inline retry / Settings actions when permission is denied or the
///   camera errors out.
class LearnerPresenceOverlay extends StatefulWidget {
  const LearnerPresenceOverlay({
    super.key,
    required this.controller,
    this.size = const Size(96, 128),
    this.margin = 12,
  });

  final LearnerPresenceController controller;
  final Size size;
  final double margin;

  @override
  State<LearnerPresenceOverlay> createState() => _LearnerPresenceOverlayState();
}

class _LearnerPresenceOverlayState extends State<LearnerPresenceOverlay> {
  Offset? _offset; // null = use default top-right anchor.
  Size? _lastParentSize;
  // Only rebuild when the controller state actually changes.
  LearnerPresenceState? _lastState;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final newState = widget.controller.state;
    if (newState != _lastState) {
      _lastState = newState;
      if (mounted) setState(() {});
    }
  }

  Offset _defaultOffset(Size parent) {
    final topInset = MediaQuery.maybeOf(context)?.padding.top ?? 0;
    return Offset(
      parent.width - widget.size.width - widget.margin,
      widget.margin + topInset,
    );
  }

  Offset _clamp(Offset value, Size parent) {
    final maxX =
        (parent.width - widget.size.width).clamp(0.0, double.infinity);
    final maxY =
        (parent.height - widget.size.height).clamp(0.0, double.infinity);
    return Offset(value.dx.clamp(0.0, maxX), value.dy.clamp(0.0, maxY));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.controller.state;
    if (state == LearnerPresenceState.idle ||
        state == LearnerPresenceState.unsupported) {
      // Nothing to show: feature is disabled or unsupported.
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final parent = constraints.biggest;

        // Re-clamp when the parent size changes (rotation, fullscreen toggle).
        if (_lastParentSize != parent) {
          _lastParentSize = parent;
          if (_offset != null) {
            _offset = _clamp(_offset!, parent);
          }
        }
        final pos = _offset ?? _defaultOffset(parent);

        return Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: pos.dx,
              top: pos.dy,
              width: widget.size.width,
              height: widget.size.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  final next = (_offset ?? _defaultOffset(parent)) + d.delta;
                  setState(() => _offset = _clamp(next, parent));
                },
                child: _OverlayCard(controller: widget.controller),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OverlayCard extends StatelessWidget {
  const _OverlayCard({required this.controller});

  final LearnerPresenceController controller;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildBody(context),
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _LocalPreviewBadge(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (controller.state) {
      case LearnerPresenceState.ready:
        final cam = controller.cameraController;
        if (cam == null || !cam.value.isInitialized) {
          return const _StatusBody(label: 'Starting…', spinner: true);
        }
        // Mirror the front camera (selfie convention).
        return RepaintBoundary(
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()..scale(-1.0, 1.0, 1.0),
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: cam.value.previewSize?.height ?? 1,
                height: cam.value.previewSize?.width ?? 1,
                child: CameraPreview(cam),
              ),
            ),
          ),
        );

      case LearnerPresenceState.initializing:
      case LearnerPresenceState.requestingPermission:
        return const _StatusBody(label: 'Starting…', spinner: true);

      case LearnerPresenceState.paused:
        return const _StatusBody(label: 'Paused', icon: Icons.pause_rounded);

      case LearnerPresenceState.permissionDenied:
        return _ActionBody(
          icon: Icons.videocam_off_rounded,
          label: 'Camera blocked',
          primaryLabel: 'Settings',
          onPrimary: controller.openSettings,
          secondaryLabel: 'Retry',
          onSecondary: controller.retry,
        );

      case LearnerPresenceState.error:
        return _ActionBody(
          icon: Icons.error_outline_rounded,
          label: controller.errorMessage ?? 'Camera error',
          primaryLabel: 'Retry',
          onPrimary: controller.retry,
        );

      case LearnerPresenceState.unsupported:
      case LearnerPresenceState.idle:
        return const SizedBox.shrink();
    }
  }
}

class _StatusBody extends StatelessWidget {
  const _StatusBody({required this.label, this.spinner = false, this.icon});
  final String label;
  final bool spinner;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (spinner)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else if (icon != null)
            Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _ActionBody extends StatelessWidget {
  const _ActionBody({
    required this.icon,
    required this.label,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String label;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10.5),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MiniButton(label: primaryLabel, onTap: onPrimary, primary: true),
              if (secondaryLabel != null && onSecondary != null) ...[
                const SizedBox(width: 4),
                _MiniButton(label: secondaryLabel!, onTap: onSecondary!),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: primary ? AppColors.primary : Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 10.5),
        ),
      ),
    );
  }
}

class _LocalPreviewBadge extends StatelessWidget {
  const _LocalPreviewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.lock_outline, size: 10, color: Colors.white),
          SizedBox(width: 4),
          Flexible(
            child: Text(
              'Local Preview Only',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

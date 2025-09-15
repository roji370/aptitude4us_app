import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/logger.dart';

/// A fullscreen image viewer with zoom, pan, and rotation capabilities
class FullscreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String title;
  final String userName;

  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.userName,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer>
    with TickerProviderStateMixin {
  late TransformationController _transformationController;
  late AnimationController _animationController;
  late Animation<Matrix4> _animation;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    
    // Set status bar to transparent for fullscreen experience
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
    );
  }

  @override
  void dispose() {
    _transformationController.dispose();
    _animationController.dispose();
    
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  void _resetZoom() {
    _animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    _animationController.reset();
    _animationController.forward().then((_) {
      _transformationController.value = Matrix4.identity();
    });
  }

  void _onDoubleTap() {
    // Double tap to zoom in/out
    HapticFeedback.mediumImpact();
    
    final Matrix4 currentMatrix = _transformationController.value;
    final double currentScale = currentMatrix.getMaxScaleOnAxis();
    
    late Matrix4 targetMatrix;
    
    if (currentScale > 1.5) {
      // If zoomed in, zoom out
      targetMatrix = Matrix4.identity();
    } else {
      // If zoomed out, zoom in to 2x at the center
      targetMatrix = Matrix4.identity()..scale(2.0);
    }
    
    _animation = Matrix4Tween(
      begin: currentMatrix,
      end: targetMatrix,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    _animationController.reset();
    _animationController.forward().then((_) {
      _transformationController.value = targetMatrix;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main image viewer
          Center(
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                if (_animationController.isAnimating) {
                  _transformationController.value = _animation.value;
                }
                return InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 0.1,
                  maxScale: 5.0,
                  onInteractionEnd: (details) {
                    // Haptic feedback when interaction ends
                    HapticFeedback.selectionClick();
                  },
                  child: GestureDetector(
                    onDoubleTap: _onDoubleTap,
                    child: Image.network(
                      widget.imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Loading image...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        Logger.e('Error loading fullscreen image: $error');
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.white,
                                size: 64,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Failed to load image',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                widget.title,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Top app bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).pop();
                    },
                  ),
                  title: Text(
                    widget.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.zoom_out_map, color: Colors.white),
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _resetZoom();
                      },
                      tooltip: 'Reset zoom',
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.7),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildControlButton(
                        icon: Icons.zoom_in,
                        label: 'Zoom In',
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          final Matrix4 currentMatrix = _transformationController.value;
                          final double currentScale = currentMatrix.getMaxScaleOnAxis();
                          if (currentScale < 5.0) {
                            _transformationController.value = Matrix4.identity()
                              ..scale(currentScale * 1.5);
                          }
                        },
                      ),
                      _buildControlButton(
                        icon: Icons.zoom_out,
                        label: 'Zoom Out',
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          final Matrix4 currentMatrix = _transformationController.value;
                          final double currentScale = currentMatrix.getMaxScaleOnAxis();
                          if (currentScale > 0.1) {
                            _transformationController.value = Matrix4.identity()
                              ..scale(currentScale / 1.5);
                          }
                        },
                      ),
                      _buildControlButton(
                        icon: Icons.center_focus_strong,
                        label: 'Reset',
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _resetZoom();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Watermark (subtle in fullscreen)
          Positioned(
            bottom: 80,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                widget.userName,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w300,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            onPressed: onPressed,
            tooltip: label,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:photo_view/photo_view.dart';
import 'package:video_player/video_player.dart';
import 'package:open_file/open_file.dart';
import '../services/attachment_service.dart';
import '../utils/responsive_helper.dart';

class AttachmentPreview extends StatefulWidget {
  final AttachmentData attachment;
  final bool isCompact;
  final VoidCallback? onTap;
  final VoidCallback? onDownload;

  const AttachmentPreview({
    super.key,
    required this.attachment,
    this.isCompact = false,
    this.onTap,
    this.onDownload,
  });

  @override
  State<AttachmentPreview> createState() => _AttachmentPreviewState();
}

class _AttachmentPreviewState extends State<AttachmentPreview> {
  VideoPlayerController? _videoController;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.type == AttachmentType.video && !widget.isCompact) {
      _initializeVideoPlayer();
    }
  }

  void _initializeVideoPlayer() async {
    try {
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(widget.attachment.fileUrl),
      );
      await _videoController!.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error initializing video player: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.attachment.type) {
      case AttachmentType.image:
        return _buildImagePreview(context);
      case AttachmentType.video:
        return _buildVideoPreview(context);
      case AttachmentType.document:
        return _buildDocumentPreview(context);
      case AttachmentType.unknown:
        return _buildUnknownPreview(context);
    }
  }

  Widget _buildImagePreview(BuildContext context) {
    final theme = Theme.of(context);
    final size = widget.isCompact ? 120.0 : 200.0;

    return GestureDetector(
      onTap: widget.onTap ?? () => _showFullScreenImage(context),
      child: ClipRounded(
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 12.0,
            regular: 14.0,
            pro: 16.0,
            large: 18.0,
            extraLarge: 20.0,
          ),
        ),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 12.0,
                regular: 14.0,
                pro: 16.0,
                large: 18.0,
                extraLarge: 20.0,
              ),
            ),
          ),
          child: Stack(
            children: [
              CachedNetworkImage(
                imageUrl: widget.attachment.fileUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholder:
                    (context, url) => Container(
                      width: size,
                      height: size,
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                errorWidget:
                    (context, url, error) => Container(
                      width: size,
                      height: size,
                      color: theme.colorScheme.errorContainer,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onErrorContainer,
                        size: size * 0.3,
                      ),
                    ),
              ),
              if (widget.isCompact)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.image_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreview(BuildContext context) {
    final theme = Theme.of(context);
    final size = widget.isCompact ? 120.0 : 200.0;

    return GestureDetector(
      onTap: widget.onTap ?? () => _playVideo(context),
      child: ClipRounded(
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 12.0,
            regular: 14.0,
            pro: 16.0,
            large: 18.0,
            extraLarge: 20.0,
          ),
        ),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 12.0,
                regular: 14.0,
                pro: 16.0,
                large: 18.0,
                extraLarge: 20.0,
              ),
            ),
          ),
          child: Stack(
            children: [
              // Video thumbnail or player
              if (widget.attachment.thumbnailUrl != null)
                CachedNetworkImage(
                  imageUrl: widget.attachment.thumbnailUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  placeholder:
                      (context, url) => Container(
                        width: size,
                        height: size,
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                  errorWidget:
                      (context, url, error) =>
                          _buildVideoPlaceholder(theme, size),
                )
              else
                _buildVideoPlaceholder(theme, size),

              // Play button overlay
              Center(
                child: Container(
                  width: size * 0.25,
                  height: size * 0.25,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: size * 0.15,
                  ),
                ),
              ),

              // Video icon badge
              if (widget.isCompact)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.videocam_outlined,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlaceholder(ThemeData theme, double size) {
    return Container(
      width: size,
      height: size,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.video_library_outlined,
        color: theme.colorScheme.onSurfaceVariant,
        size: size * 0.3,
      ),
    );
  }

  Widget _buildDocumentPreview(BuildContext context) {
    final theme = Theme.of(context);
    final AttachmentService attachmentService = AttachmentService();

    IconData docIcon = Icons.description_outlined;
    String extension = widget.attachment.fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        docIcon = Icons.picture_as_pdf_outlined;
        break;
      case 'doc':
      case 'docx':
        docIcon = Icons.description_outlined;
        break;
      case 'xls':
      case 'xlsx':
        docIcon = Icons.table_chart_outlined;
        break;
      case 'ppt':
      case 'pptx':
        docIcon = Icons.slideshow_outlined;
        break;
      case 'txt':
        docIcon = Icons.text_snippet_outlined;
        break;
    }

    return GestureDetector(
      onTap: widget.onTap ?? () => _handleFileDownload(context),
      child: Container(
        width: widget.isCompact ? 120.0 : 200.0,
        padding: EdgeInsets.all(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 12.0,
            regular: 14.0,
            pro: 16.0,
            large: 18.0,
            extraLarge: 20.0,
          ),
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(
            ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 12.0,
              regular: 14.0,
              pro: 16.0,
              large: 18.0,
              extraLarge: 20.0,
            ),
          ),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              docIcon,
              size: widget.isCompact ? 32.0 : 48.0,
              color: theme.colorScheme.primary,
            ),
            SizedBox(height: 8),
            Text(
              widget.attachment.fileName,
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(
                  context,
                  widget.isCompact ? 11.0 : 13.0,
                ),
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              attachmentService.formatFileSize(widget.attachment.fileSize),
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(
                  context,
                  widget.isCompact ? 9.0 : 11.0,
                ),
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_isDownloading) ...[
              SizedBox(height: 8),
              LinearProgressIndicator(
                value: _downloadProgress,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUnknownPreview(BuildContext context) {
    final theme = Theme.of(context);
    final AttachmentService attachmentService = AttachmentService();

    return GestureDetector(
      onTap: widget.onTap ?? () => _handleFileDownload(context),
      child: Container(
        width: widget.isCompact ? 120.0 : 200.0,
        padding: EdgeInsets.all(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 12.0,
            regular: 14.0,
            pro: 16.0,
            large: 18.0,
            extraLarge: 20.0,
          ),
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(
            ResponsiveHelper.getAdaptiveSpacing(
              context,
              compact: 12.0,
              regular: 14.0,
              pro: 16.0,
              large: 18.0,
              extraLarge: 20.0,
            ),
          ),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: widget.isCompact ? 32.0 : 48.0,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: 8),
            Text(
              widget.attachment.fileName,
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(
                  context,
                  widget.isCompact ? 11.0 : 13.0,
                ),
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Text(
              attachmentService.formatFileSize(widget.attachment.fileSize),
              style: TextStyle(
                fontSize: ResponsiveHelper.adaptiveFontSize(
                  context,
                  widget.isCompact ? 9.0 : 11.0,
                ),
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => Scaffold(
              backgroundColor: Colors.black,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(widget.attachment.fileName),
                actions: [
                  IconButton(
                    icon: Icon(Icons.download_outlined),
                    onPressed: () => _handleFileDownload(context),
                  ),
                ],
              ),
              body: Center(
                child: PhotoView(
                  imageProvider: CachedNetworkImageProvider(
                    widget.attachment.fileUrl,
                  ),
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3.0,
                  heroAttributes: PhotoViewHeroAttributes(
                    tag: widget.attachment.id,
                  ),
                ),
              ),
            ),
      ),
    );
  }

  void _playVideo(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => VideoPlayerScreen(attachment: widget.attachment),
      ),
    );
  }

  void _handleFileDownload(BuildContext context) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    try {
      final AttachmentService attachmentService = AttachmentService();
      final String? localPath = await attachmentService.downloadAttachment(
        widget.attachment,
      );

      if (localPath != null && mounted) {
        HapticFeedback.selectionClick();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File downloaded successfully'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () => OpenFile.open(localPath),
            ),
          ),
        );

        if (widget.onDownload != null) {
          widget.onDownload!();
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download file'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error downloading file: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }
}

class ClipRounded extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  const ClipRounded({
    super.key,
    required this.child,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}

class VideoPlayerScreen extends StatefulWidget {
  final AttachmentData attachment;

  const VideoPlayerScreen({super.key, required this.attachment});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeVideoPlayer();
  }

  void _initializeVideoPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.attachment.fileUrl),
      );
      await _controller!.initialize();
      await _controller!.play();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.attachment.fileName),
        actions: [
          IconButton(
            icon: Icon(Icons.download_outlined),
            onPressed: () {
              // Handle download
            },
          ),
        ],
      ),
      body: Center(
        child:
            _isLoading
                ? CircularProgressIndicator(color: Colors.white)
                : _hasError
                ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, color: Colors.white, size: 64),
                    SizedBox(height: 16),
                    Text(
                      'Error loading video',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                )
                : _controller != null
                ? AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: VideoPlayer(_controller!),
                )
                : Container(),
      ),
      floatingActionButton:
          _controller != null && !_isLoading && !_hasError
              ? FloatingActionButton(
                onPressed: () {
                  setState(() {
                    _controller!.value.isPlaying
                        ? _controller!.pause()
                        : _controller!.play();
                  });
                },
                child: Icon(
                  _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              )
              : null,
    );
  }
}

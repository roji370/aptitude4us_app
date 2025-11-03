import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/attachment_service.dart';
import '../utils/responsive_helper.dart';

class AttachmentPicker extends StatefulWidget {
  final Function(AttachmentData) onAttachmentSelected;
  final Function(String) onError;

  const AttachmentPicker({
    super.key,
    required this.onAttachmentSelected,
    required this.onError,
  });

  @override
  State<AttachmentPicker> createState() => _AttachmentPickerState();
}

class _AttachmentPickerState extends State<AttachmentPicker>
    with TickerProviderStateMixin {
  final AttachmentService _attachmentService = AttachmentService();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadingFileName = '';

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.elasticOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Container(
        padding: EdgeInsets.all(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 16.0,
            regular: 20.0,
            pro: 24.0,
            large: 28.0,
            extraLarge: 32.0,
          ),
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(
              ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 20.0,
                regular: 24.0,
                pro: 28.0,
                large: 32.0,
                extraLarge: 36.0,
              ),
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.15),
              blurRadius: ResponsiveHelper.getAdaptiveElevation(context) * 2,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              if (_isUploading) ...[
                _buildUploadProgress(context, theme),
                SizedBox(height: 20),
              ],

              // Title
              Text(
                'Send Attachment',
                style: TextStyle(
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 20.0),
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),

              SizedBox(height: 24),

              // Attachment options grid
              ScaleTransition(
                scale: _scaleAnimation,
                child: GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildAttachmentOption(
                      context,
                      theme,
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      color: Colors.green,
                      onTap: () => _handleGallery(context),
                    ),
                    _buildAttachmentOption(
                      context,
                      theme,
                      icon: Icons.description_outlined,
                      label: 'Document',
                      color: Colors.blue,
                      onTap: () => _handleDocument(context),
                    ),
                    _buildAttachmentOption(
                      context,
                      theme,
                      icon: Icons.folder_outlined,
                      label: 'File',
                      color: Colors.teal,
                      onTap: () => _handleAnyFile(context),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 16),

              // Cancel button
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _isUploading ? null : () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.getAdaptiveSpacing(
                        context,
                        compact: 12.0,
                        regular: 14.0,
                        pro: 16.0,
                        large: 18.0,
                        extraLarge: 20.0,
                      ),
                    ),
                  ),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: ResponsiveHelper.adaptiveFontSize(
                        context,
                        16.0,
                      ),
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadProgress(BuildContext context, ThemeData theme) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                value: _uploadProgress,
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Uploading $_uploadingFileName...',
                style: TextStyle(
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: 8),
        LinearProgressIndicator(
          value: _uploadProgress,
          color: theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ],
    );
  }

  Widget _buildAttachmentOption(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isUploading ? null : onTap,
        borderRadius: BorderRadius.circular(
          ResponsiveHelper.getAdaptiveSpacing(
            context,
            compact: 16.0,
            regular: 18.0,
            pro: 20.0,
            large: 22.0,
            extraLarge: 24.0,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh.withValues(
              alpha: 0.5,
            ),
            borderRadius: BorderRadius.circular(
              ResponsiveHelper.getAdaptiveSpacing(
                context,
                compact: 16.0,
                regular: 18.0,
                pro: 20.0,
                large: 22.0,
                extraLarge: 24.0,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: ResponsiveHelper.adaptiveFontSize(context, 48.0),
                height: ResponsiveHelper.adaptiveFontSize(context, 48.0),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: ResponsiveHelper.adaptiveFontSize(context, 24.0),
                  color: color,
                ),
              ),
              SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleGallery(BuildContext context) async {
    try {
      // Show options for image or video from gallery
      final result = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder:
            (context) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Text(
                      'Select from Gallery',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 16),
                    ListTile(
                      leading: Icon(Icons.photo_outlined, color: Colors.blue),
                      title: Text('Photo'),
                      onTap: () => Navigator.pop(context, 'image'),
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.video_library_outlined,
                        color: Colors.red,
                      ),
                      title: Text('Video'),
                      onTap: () => Navigator.pop(context, 'video'),
                    ),
                  ],
                ),
              ),
            ),
      );

      if (result == 'image') {
        await _handleImagePicker();
      } else if (result == 'video') {
        await _handleVideoPicker();
      }
    } catch (e) {
      widget.onError('Error accessing gallery: $e');
    }
  }

  Future<void> _handleImagePicker() async {
    try {
      final XFile? image = await _attachmentService.pickImageFromGallery();
      if (image != null) {
        await _uploadFile(image.path, image.name);
      }
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('photo_access_denied') ||
          errorMessage.contains('permission denied') ||
          errorMessage.contains('not authorized') ||
          errorMessage.contains('access denied')) {
        widget.onError(
          'Photo access required. Please allow photo access in Settings.',
        );
        await _showPermissionDialog();
      } else {
        widget.onError('Error picking image: $e');
      }
    }
  }

  Future<void> _handleVideoPicker() async {
    try {
      final XFile? video = await _attachmentService.pickVideoFromGallery();
      if (video != null) {
        await _uploadFile(video.path, video.name);
      }
    } catch (e) {
      final errorMessage = e.toString().toLowerCase();
      if (errorMessage.contains('photo_access_denied') ||
          errorMessage.contains('permission denied') ||
          errorMessage.contains('not authorized') ||
          errorMessage.contains('access denied')) {
        widget.onError(
          'Photo access required. Please allow photo access in Settings.',
        );
        await _showPermissionDialog();
      } else {
        widget.onError('Error picking video: $e');
      }
    }
  }

  Future<void> _showPermissionDialog() async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Permission Required'),
          content: Text(
            'To select photos and videos, please:\n\n'
            '1. Go to Settings\n'
            '2. Find "Xfini Academy"\n'
            '3. Tap "Photos"\n'
            '4. Select "All Photos" or "Selected Photos"',
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: Text('Open Settings'),
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleDocument(BuildContext context) async {
    try {
      final PlatformFile? file = await _attachmentService.pickDocument();
      if (file != null && file.path != null) {
        await _uploadFile(file.path!, file.name);
      }
    } catch (e) {
      widget.onError('Error picking document: $e');
    }
  }

  Future<void> _handleAnyFile(BuildContext context) async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        final PlatformFile file = result.files.first;
        if (file.path != null) {
          await _uploadFile(file.path!, file.name);
        }
      }
    } catch (e) {
      widget.onError('Error picking file: $e');
    }
  }

  Future<void> _uploadFile(String filePath, String fileName) async {
    if (!mounted) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _uploadingFileName = fileName;
    });

    try {
      HapticFeedback.lightImpact();

      // Debug: Check if file exists and log file info
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Selected file no longer exists');
      }

      final fileSize = await file.length();
      print('📁 Starting upload: $fileName (${fileSize} bytes)');

      final AttachmentData? attachment = await _attachmentService
          .uploadAttachment(
            filePath: filePath,
            fileName: fileName,
            chatType: 'general',
            onProgress: (progress) {
              if (mounted) {
                setState(() {
                  _uploadProgress = progress;
                });
              }
              print(
                '📊 Upload progress: ${(progress * 100).toStringAsFixed(1)}%',
              );
            },
          );

      if (attachment != null && mounted) {
        print('✅ Upload successful: ${attachment.fileName}');
        HapticFeedback.selectionClick();
        widget.onAttachmentSelected(attachment);
        Navigator.pop(context);
      } else if (mounted) {
        print('❌ Upload failed: attachment is null');
        widget.onError('Failed to upload file - please try again');
      }
    } catch (e) {
      print('❌ Upload error: $e');
      if (mounted) {
        String errorMessage = 'Upload failed';

        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('not authenticated') ||
            errorStr.contains('permission')) {
          errorMessage =
              'Authentication error - please try logging out and back in';
        } else if (errorStr.contains('network') ||
            errorStr.contains('internet')) {
          errorMessage = 'Network error - check your internet connection';
        } else if (errorStr.contains('size') || errorStr.contains('large')) {
          errorMessage = 'File too large - please select a smaller file';
        } else if (errorStr.contains('storage')) {
          errorMessage = 'Storage error - please contact support';
        } else {
          errorMessage = 'Upload failed - please try again';
        }

        widget.onError(errorMessage);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
          _uploadingFileName = '';
        });
      }
    }
  }
}

// Helper function to show attachment picker
void showAttachmentPicker(
  BuildContext context, {
  required Function(AttachmentData) onAttachmentSelected,
  required Function(String) onError,
}) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder:
        (context) => AttachmentPicker(
          onAttachmentSelected: onAttachmentSelected,
          onError: onError,
        ),
  );
}

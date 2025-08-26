import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import '../utils/logger.dart';

enum AttachmentType { image, video, document, unknown }

class AttachmentData {
  final String id;
  final String fileName;
  final String fileUrl;
  final String? thumbnailUrl;
  final AttachmentType type;
  final int fileSize;
  final String mimeType;
  final Map<String, dynamic>? metadata;

  AttachmentData({
    required this.id,
    required this.fileName,
    required this.fileUrl,
    this.thumbnailUrl,
    required this.type,
    required this.fileSize,
    required this.mimeType,
    this.metadata,
  });

  factory AttachmentData.fromMap(Map<String, dynamic> map) {
    return AttachmentData(
      id: map['id'] ?? '',
      fileName: map['fileName'] ?? '',
      fileUrl: map['fileUrl'] ?? '',
      thumbnailUrl: map['thumbnailUrl'],
      type: AttachmentType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AttachmentType.unknown,
      ),
      fileSize: map['fileSize'] ?? 0,
      mimeType: map['mimeType'] ?? '',
      metadata: map['metadata'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'fileName': fileName,
      'fileUrl': fileUrl,
      'thumbnailUrl': thumbnailUrl,
      'type': type.name,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'metadata': metadata,
    };
  }
}

class AttachmentService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final ImagePicker _imagePicker = ImagePicker();

  // Maximum file sizes (in bytes)
  static const int maxImageSize = 10 * 1024 * 1024; // 10MB
  static const int maxVideoSize = 100 * 1024 * 1024; // 100MB
  static const int maxDocumentSize = 25 * 1024 * 1024; // 25MB

  // Image compression settings
  static const int imageQuality = 85;
  static const int maxImageWidth = 1920;
  static const int maxImageHeight = 1080;

  /// Pick image from gallery
  Future<XFile?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: maxImageWidth.toDouble(),
        maxHeight: maxImageHeight.toDouble(),
        imageQuality: imageQuality,
      );
      return image;
    } catch (e) {
      Logger.e('Error picking image from gallery: $e');
      return null;
    }
  }

  /// Pick video from gallery
  Future<XFile?> pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10), // 10 minute limit
      );
      return video;
    } catch (e) {
      Logger.e('Error picking video from gallery: $e');
      return null;
    }
  }

  /// Pick document file
  Future<PlatformFile?> pickDocument() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'rtf',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
        ],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        return result.files.first;
      }
      return null;
    } catch (e) {
      Logger.e('Error picking document: $e');
      return null;
    }
  }

  /// Determine attachment type from file
  AttachmentType getAttachmentType(String fileName, String? mimeType) {
    final String extension = fileName.split('.').last.toLowerCase();
    final String mime = mimeType ?? lookupMimeType(fileName) ?? '';

    if (mime.startsWith('image/')) {
      return AttachmentType.image;
    } else if (mime.startsWith('video/')) {
      return AttachmentType.video;
    } else if (mime.startsWith('application/') || mime.startsWith('text/')) {
      return AttachmentType.document;
    }

    // Fallback to extension-based detection
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
        return AttachmentType.image;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'flv':
      case 'webm':
        return AttachmentType.video;

      case 'pdf':
      case 'doc':
      case 'docx':
      case 'txt':
      case 'rtf':
      case 'xls':
      case 'xlsx':
      case 'ppt':
      case 'pptx':
        return AttachmentType.document;
      default:
        return AttachmentType.unknown;
    }
  }

  /// Validate file size based on type
  bool validateFileSize(int fileSize, AttachmentType type) {
    switch (type) {
      case AttachmentType.image:
        return fileSize <= maxImageSize;
      case AttachmentType.video:
        return fileSize <= maxVideoSize;
      case AttachmentType.document:
        return fileSize <= maxDocumentSize;
      case AttachmentType.unknown:
        return fileSize <= maxDocumentSize;
    }
  }

  /// Compress image file
  Future<Uint8List?> compressImage(String filePath) async {
    try {
      final File file = File(filePath);
      if (!await file.exists()) return null;

      final Uint8List? compressedBytes =
          await FlutterImageCompress.compressWithFile(
            filePath,
            quality: imageQuality,
            minWidth: 300,
            minHeight: 300,
            format: CompressFormat.jpeg,
          );

      return compressedBytes;
    } catch (e) {
      Logger.e('Error compressing image: $e');
      return null;
    }
  }

  /// Generate video thumbnail
  Future<Uint8List?> generateVideoThumbnail(String videoPath) async {
    try {
      final Uint8List? thumbnail = await VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 300,
        quality: 75,
      );
      return thumbnail;
    } catch (e) {
      Logger.e('Error generating video thumbnail: $e');
      return null;
    }
  }

  /// Upload attachment to Firebase Storage
  Future<AttachmentData?> uploadAttachment({
    required String filePath,
    required String fileName,
    String? chatType = 'general',
    Function(double)? onProgress,
  }) async {
    try {
      print('🔐 Checking authentication...');
      final User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }
      print('✅ User authenticated: ${currentUser.uid}');

      print('📂 Checking file: $filePath');
      final File file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      final int fileSize = await file.length();
      final String mimeType =
          lookupMimeType(fileName) ?? 'application/octet-stream';
      final AttachmentType type = getAttachmentType(fileName, mimeType);
      print(
        '📊 File info: $fileName, Size: ${formatFileSize(fileSize)}, Type: ${type.name}, MIME: $mimeType',
      );

      // Validate file size
      if (!validateFileSize(fileSize, type)) {
        throw Exception('File size exceeds limit for ${type.name} files');
      }

      // Generate unique file ID
      final String fileId = DateTime.now().millisecondsSinceEpoch.toString();
      final String fileExtension = fileName.split('.').last;
      final String storagePath =
          'attachments/$chatType/${currentUser.uid}/$fileId.$fileExtension';
      print('🗂️ Storage path: $storagePath');

      // Upload main file
      print('☁️ Starting upload to Firebase Storage...');
      final Reference storageRef = _storage.ref().child(storagePath);
      final UploadTask uploadTask = storageRef.putFile(file);

      // Monitor upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final double progress = snapshot.bytesTransferred / snapshot.totalBytes;
        print(
          '📈 Upload progress: ${(progress * 100).toStringAsFixed(1)}% (${snapshot.bytesTransferred}/${snapshot.totalBytes} bytes)',
        );
        onProgress?.call(progress);
      });

      final TaskSnapshot snapshot = await uploadTask;
      print('✅ Upload completed, getting download URL...');
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      print('🔗 Download URL obtained: ${downloadUrl.substring(0, 50)}...');

      // Generate thumbnail for video files
      String? thumbnailUrl;
      if (type == AttachmentType.video) {
        print('🎬 Generating video thumbnail...');
        final Uint8List? thumbnailData = await generateVideoThumbnail(filePath);
        if (thumbnailData != null) {
          final String thumbnailPath =
              'attachments/$chatType/${currentUser.uid}/${fileId}_thumb.jpg';
          final Reference thumbnailRef = _storage.ref().child(thumbnailPath);
          await thumbnailRef.putData(thumbnailData);
          thumbnailUrl = await thumbnailRef.getDownloadURL();
          print('🖼️ Thumbnail uploaded: $thumbnailUrl');
        }
      }

      // Create metadata
      final Map<String, dynamic> metadata = {
        'uploadedAt': DateTime.now().toIso8601String(),
        'uploadedBy': currentUser.uid,
        'originalName': fileName,
      };

      final attachmentData = AttachmentData(
        id: fileId,
        fileName: fileName,
        fileUrl: downloadUrl,
        thumbnailUrl: thumbnailUrl,
        type: type,
        fileSize: fileSize,
        mimeType: mimeType,
        metadata: metadata,
      );

      print(
        '🎉 AttachmentData created successfully: ${attachmentData.fileName}',
      );
      return attachmentData;
    } catch (e) {
      print('💥 Upload error in AttachmentService: $e');
      Logger.e('Error uploading attachment: $e');
      return null;
    }
  }

  /// Download attachment to local storage
  Future<String?> downloadAttachment(AttachmentData attachment) async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String localPath =
          '${appDir.path}/downloads/${attachment.fileName}';
      final File localFile = File(localPath);

      // Create directory if it doesn't exist
      await localFile.parent.create(recursive: true);

      // Download file
      final Reference ref = _storage.refFromURL(attachment.fileUrl);
      await ref.writeToFile(localFile);

      return localPath;
    } catch (e) {
      Logger.e('Error downloading attachment: $e');
      return null;
    }
  }

  /// Get attachment file size in human readable format
  String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Delete attachment from Firebase Storage
  Future<bool> deleteAttachment(String fileUrl) async {
    try {
      final Reference ref = _storage.refFromURL(fileUrl);
      await ref.delete();
      return true;
    } catch (e) {
      Logger.e('Error deleting attachment: $e');
      return false;
    }
  }

  /// Check if file exists in Firebase Storage
  Future<bool> fileExists(String fileUrl) async {
    try {
      final Reference ref = _storage.refFromURL(fileUrl);
      await ref.getDownloadURL();
      return true;
    } catch (e) {
      return false;
    }
  }
}

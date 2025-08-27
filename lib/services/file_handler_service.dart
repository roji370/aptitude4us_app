import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/logger.dart';

/// Enhanced file handling service with cross-platform support
class FileHandlerService {
  /// Opens a file with multiple fallback methods for better compatibility
  static Future<bool> openFile(
    String filePath, {
    String? mimeType,
    String? fileName,
    String? fallbackUrl,
  }) async {
    Logger.i('🔄 Attempting to open file: $filePath');

    // Method 1: Try opening with default app using open_file package
    try {
      final result = await OpenFile.open(filePath, type: mimeType);
      Logger.d('OpenFile result: ${result.message}');

      if (result.type == ResultType.done) {
        Logger.i('✅ File opened successfully with default app');
        return true;
      }

      // Check for specific error types
      if (result.type == ResultType.noAppToOpen) {
        Logger.w('⚠️ No app available to open this file type');
      } else if (result.type == ResultType.fileNotFound) {
        Logger.w('⚠️ File not found: $filePath');
      } else {
        Logger.w('⚠️ OpenFile failed with type: ${result.type}');
      }
    } catch (e) {
      Logger.w('⚠️ OpenFile failed: $e');
    }

    // Method 2: Try using url_launcher for files
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
          if (launched) {
            Logger.i('✅ File opened with url_launcher');
            return true;
          }
        }
      }
    } catch (e) {
      Logger.w('⚠️ URL launcher failed: $e');
    }

    // Method 3: For Android, try sharing the file (opens chooser)
    if (Platform.isAndroid && fileName != null) {
      try {
        final success = await _shareFileOnAndroid(filePath, fileName, mimeType);
        if (success) {
          Logger.i('✅ File shared/opened via Android intent');
          return true;
        }
      } catch (e) {
        Logger.w('⚠️ Android file sharing failed: $e');
      }
    }

    // Method 4: Open external URL as last resort
    if (fallbackUrl != null) {
      try {
        final url = Uri.parse(fallbackUrl);
        if (await canLaunchUrl(url)) {
          final launched = await launchUrl(
            url,
            mode: LaunchMode.externalApplication,
          );
          if (launched) {
            Logger.i('✅ Fallback URL opened');
            return true;
          }
        }
      } catch (e) {
        Logger.w('⚠️ Fallback URL launch failed: $e');
      }
    }

    Logger.w('❌ All file opening methods failed');
    return false;
  }

  /// Copy file to external storage for better accessibility on Android
  static Future<String?> copyToExternalStorage(
    String filePath,
    String fileName,
  ) async {
    if (!Platform.isAndroid) return filePath;

    try {
      // Request storage permission first
      final permission = await Permission.storage.status;
      if (permission != PermissionStatus.granted) {
        final result = await Permission.storage.request();
        if (result != PermissionStatus.granted) {
          Logger.w('⚠️ Storage permission not granted');
          return null;
        }
      }

      final file = File(filePath);
      if (!await file.exists()) {
        Logger.w('⚠️ Source file does not exist: $filePath');
        return null;
      }

      // Get external storage directory
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        Logger.w('⚠️ External storage directory not available');
        return null;
      }

      // Create Briffini Academy folder in Downloads
      final downloadDir = Directory(
        '${externalDir.path}/Download/BriffiniAcademy',
      );
      await downloadDir.create(recursive: true);

      final newPath = '${downloadDir.path}/$fileName';
      await file.copy(newPath);

      Logger.i('📁 File copied to external storage: $newPath');
      return newPath;
    } catch (e) {
      Logger.e('❌ Error copying to external storage: $e');
      return null;
    }
  }

  /// Check if we have necessary permissions for file operations
  static Future<bool> checkFilePermissions() async {
    if (Platform.isAndroid) {
      // Check storage permissions
      final storageStatus = await Permission.storage.status;
      if (storageStatus != PermissionStatus.granted) {
        final result = await Permission.storage.request();
        return result == PermissionStatus.granted;
      }
      return true;
    } else if (Platform.isIOS) {
      // iOS handles permissions automatically through the system
      return true;
    }
    return false;
  }

  /// Request file operation permissions
  static Future<bool> requestFilePermissions() async {
    if (Platform.isAndroid) {
      final results =
          await [
            Permission.storage,
            Permission.manageExternalStorage,
          ].request();

      return results[Permission.storage] == PermissionStatus.granted ||
          results[Permission.manageExternalStorage] == PermissionStatus.granted;
    }
    return true;
  }

  /// Get appropriate download directory based on platform
  static Future<Directory?> getDownloadDirectory() async {
    try {
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final downloadDir = Directory(
            '${externalDir.path}/Download/BriffiniAcademy',
          );
          await downloadDir.create(recursive: true);
          return downloadDir;
        }
      }

      // Fallback to app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final downloadDir = Directory('${appDir.path}/downloads');
      await downloadDir.create(recursive: true);
      return downloadDir;
    } catch (e) {
      Logger.e('❌ Error getting download directory: $e');
      return null;
    }
  }

  /// Share file on Android using intents
  static Future<bool> _shareFileOnAndroid(
    String filePath,
    String fileName,
    String? mimeType,
  ) async {
    try {
      // This would require platform channel implementation or a sharing plugin
      // For now, we'll return false to indicate this method isn't available
      Logger.i('📤 Android file sharing would be implemented here');
      return false;
    } catch (e) {
      Logger.e('❌ Error sharing file on Android: $e');
      return false;
    }
  }

  /// Get MIME type from file extension
  static String? getMimeTypeFromExtension(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      case 'rtf':
        return 'text/rtf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return null;
    }
  }

  /// Show user-friendly error message based on file opening result
  static String getErrorMessage(ResultType resultType) {
    switch (resultType) {
      case ResultType.noAppToOpen:
        return 'No app installed to open this file type. Please install a compatible app.';
      case ResultType.fileNotFound:
        return 'File not found. It may have been moved or deleted.';
      case ResultType.permissionDenied:
        return 'Permission denied. Please check app permissions.';
      case ResultType.error:
        return 'An error occurred while trying to open the file.';
      default:
        return 'Unable to open file. Please try again or contact support.';
    }
  }
}

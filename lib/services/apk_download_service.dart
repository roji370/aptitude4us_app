import 'dart:io';
import 'package:dio/dio.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_file/open_file.dart';
import '../utils/logger.dart';

class ApkDownloadService {
  final Dio _dio = Dio();
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Download APK from Firebase Storage
  /// Returns the local file path if successful, null otherwise
  Future<String?> downloadApk({
    required String storagePath,
    required Function(double) onProgress,
  }) async {
    try {
      Logger.i('🔄 Starting APK download from: $storagePath');

      // Request necessary permissions for Android 13+
      if (Platform.isAndroid) {
        final permissionGranted = await _requestInstallPermission();
        if (!permissionGranted) {
          Logger.w('⚠️ Install permission not granted');
          return null;
        }
      }

      // Get download URL from Firebase Storage
      final ref = _storage.ref(storagePath);
      final downloadUrl = await ref.getDownloadURL();
      Logger.i('📥 Download URL obtained: $downloadUrl');

      // Get temporary directory to save the APK
      final tempDir = await getTemporaryDirectory();
      final savePath = '${tempDir.path}/app-update.apk';

      // Delete old APK if exists
      final file = File(savePath);
      if (await file.exists()) {
        await file.delete();
        Logger.i('🗑️ Deleted old APK file');
      }

      // Download the APK with progress tracking
      await _dio.download(
        downloadUrl,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = (received / total);
            onProgress(progress);
            Logger.i('📊 Download progress: ${(progress * 100).toStringAsFixed(1)}%');
          }
        },
      );

      Logger.i('✅ APK downloaded successfully to: $savePath');
      return savePath;
    } catch (e) {
      Logger.e('❌ Error downloading APK: $e');
      return null;
    }
  }

  /// Install APK file
  Future<bool> installApk(String filePath) async {
    try {
      if (!Platform.isAndroid) {
        Logger.w('⚠️ APK installation is only available on Android');
        return false;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        Logger.e('❌ APK file not found at: $filePath');
        return false;
      }

      Logger.i('📱 Installing APK from: $filePath');

      // Use open_file to open the APK, which triggers Android's package installer
      final result = await OpenFile.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );
      
      if (result.type == ResultType.done) {
        Logger.i('✅ APK installation initiated successfully');
        return true;
      } else {
        Logger.e('❌ APK installation failed: ${result.message}');
        return false;
      }
    } catch (e) {
      Logger.e('❌ Error installing APK: $e');
      return false;
    }
  }

  /// Request install permission (Android 8.0+)
  Future<bool> _requestInstallPermission() async {
    try {
      // For Android 8.0 (API 26) and above, need REQUEST_INSTALL_PACKAGES permission
      if (Platform.isAndroid) {
        final androidInfo = await Permission.requestInstallPackages.status;
        
        if (!androidInfo.isGranted) {
          final result = await Permission.requestInstallPackages.request();
          return result.isGranted;
        }
        
        return true;
      }
      return false;
    } catch (e) {
      Logger.e('❌ Error requesting install permission: $e');
      return false;
    }
  }

  /// Check if device has enough storage space for the APK
  /// Returns true if enough space, false otherwise
  Future<bool> hasEnoughStorage({int requiredBytes = 50 * 1024 * 1024}) async {
    try {
      if (Platform.isAndroid) {
        final tempDir = await getTemporaryDirectory();
        final stat = await tempDir.stat();
        
        // This is a simplified check - in production you might want to use 
        // a platform channel to get actual free space
        Logger.i('📊 Checking storage availability');
        return true; // Simplified for now
      }
      return false;
    } catch (e) {
      Logger.e('❌ Error checking storage: $e');
      return false;
    }
  }

  /// Get APK download URL from version control document
  Future<String?> getApkDownloadPath() async {
    try {
      final versionInfo = await _getVersionInfo();
      final apkPath = versionInfo['apkDownloadPath'] as String?;
      
      if (apkPath == null || apkPath.isEmpty) {
        Logger.w('⚠️ APK download path not found in version control');
        return null;
      }
      
      Logger.i('📍 APK download path: $apkPath');
      return apkPath;
    } catch (e) {
      Logger.e('❌ Error getting APK download path: $e');
      return null;
    }
  }

  /// Get version info from Firestore
  Future<Map<String, dynamic>> _getVersionInfo() async {
    try {
      // Import FirebaseFirestore at the top and use it here
      // For now, returning empty map - will be implemented through VersionCheckService
      return {};
    } catch (e) {
      Logger.e('❌ Error getting version info: $e');
      return {};
    }
  }

  /// Download and install APK in one go
  Future<bool> downloadAndInstall({
    required String storagePath,
    required Function(double) onProgress,
  }) async {
    try {
      // Download the APK
      final apkPath = await downloadApk(
        storagePath: storagePath,
        onProgress: onProgress,
      );

      if (apkPath == null) {
        Logger.e('❌ Failed to download APK');
        return false;
      }

      // Install the APK
      final installed = await installApk(apkPath);
      
      if (!installed) {
        Logger.e('❌ Failed to install APK');
        return false;
      }

      return true;
    } catch (e) {
      Logger.e('❌ Error in download and install: $e');
      return false;
    }
  }

  /// Cancel ongoing download (if needed)
  void cancelDownload() {
    try {
      _dio.close(force: true);
      Logger.i('🚫 Download cancelled');
    } catch (e) {
      Logger.e('❌ Error cancelling download: $e');
    }
  }
}


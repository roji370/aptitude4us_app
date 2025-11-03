import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/logger.dart';

class VersionCheckService {
  final FirebaseFirestore? _firestore;

  VersionCheckService({FirebaseFirestore? firestore})
      : _firestore = firestore;

  /// Check if the current app version is allowed to run
  /// Returns true if update is required, false if app can continue
  Future<bool> isUpdateRequired() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      Logger.i('Current app version: $currentVersion');

      // Get minimum required version from Firestore
      final firestore = _firestore ?? FirebaseFirestore.instance;
      final docSnapshot = await firestore
          .collection('appConfig')
          .doc('versionControl')
          .get();

      if (!docSnapshot.exists) {
        Logger.w('Version control document not found in Firestore');
        // If document doesn't exist, allow app to continue
        return false;
      }

      final data = docSnapshot.data();
      if (data == null) {
        Logger.w('Version control data is null');
        return false;
      }

      final minimumVersion = data['minimumVersion'] as String?;
      final forceUpdate = data['forceUpdate'] as bool? ?? false;

      if (minimumVersion == null) {
        Logger.w('Minimum version not specified in Firestore');
        return false;
      }

      Logger.i('Minimum required version: $minimumVersion');
      Logger.i('Force update enabled: $forceUpdate');

      // If force update is disabled, don't require update
      if (!forceUpdate) {
        return false;
      }

      // Compare versions
      final updateRequired = _isVersionLessThan(currentVersion, minimumVersion);
      
      if (updateRequired) {
        Logger.w('App update required! Current: $currentVersion, Required: $minimumVersion');
      } else {
        Logger.i('App version is up to date');
      }

      return updateRequired;
    } catch (e) {
      Logger.e('Error checking app version: $e');
      // On error, allow app to continue to prevent blocking users
      return false;
    }
  }

  /// Get the latest version info from Firestore
  Future<Map<String, dynamic>> getVersionInfo() async {
    try {
      final firestore = _firestore ?? FirebaseFirestore.instance;
      final docSnapshot = await firestore
          .collection('appConfig')
          .doc('versionControl')
          .get();

      if (!docSnapshot.exists || docSnapshot.data() == null) {
        return {};
      }

      return docSnapshot.data()!;
    } catch (e) {
      Logger.e('Error getting version info: $e');
      return {};
    }
  }

  /// Get current app version
  Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      Logger.e('Error getting current version: $e');
      return '0.0.0';
    }
  }

  /// Compare two version strings
  /// Returns true if version1 is less than version2
  bool _isVersionLessThan(String version1, String version2) {
    try {
      final v1Parts = version1.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final v2Parts = version2.split('.').map((e) => int.tryParse(e) ?? 0).toList();

      // Ensure both lists have at least 3 parts (major.minor.patch)
      while (v1Parts.length < 3) {
        v1Parts.add(0);
      }
      while (v2Parts.length < 3) {
        v2Parts.add(0);
      }

      // Compare major version
      if (v1Parts[0] < v2Parts[0]) return true;
      if (v1Parts[0] > v2Parts[0]) return false;

      // Compare minor version
      if (v1Parts[1] < v2Parts[1]) return true;
      if (v1Parts[1] > v2Parts[1]) return false;

      // Compare patch version
      if (v1Parts[2] < v2Parts[2]) return true;

      return false;
    } catch (e) {
      Logger.e('Error comparing versions: $e');
      return false;
    }
  }
}


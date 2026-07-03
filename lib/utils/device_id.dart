import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'logger.dart';

/// Secure-storage key for the device ID.
/// Stored in iOS Keychain / Android EncryptedSharedPreferences.
const String _secureDeviceIdKey = 'briffini_device_id_secure';

/// Legacy SharedPreferences key — used only during one-time migration.
const String _legacyDeviceIdKey = 'briffini_device_id';

/// Concurrency guard: ensures only one migration / generation runs at a time.
Completer<String>? _pendingGetDeviceId;

/// Secure storage instance with iOS Keychain accessibility set to
/// `first_unlock` so the ID is readable immediately after device reboot
/// (before the user unlocks), which avoids nil-reads during background launches.
const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  ),
);

/// Generate or retrieve a stable device ID using secure storage.
///
/// Storage hierarchy:
/// 1. Secure storage (Keychain / EncryptedSharedPreferences) — primary
/// 2. SharedPreferences (legacy, read-only for migration)
/// 3. Hardware identifier with retry (last resort for new installs)
///
/// The ID format is `mobile-<hardwareId>` for consistency with existing
/// Firestore device registrations.
Future<String> getDeviceId() async {
  // Concurrency guard: if another call is already running, await it.
  if (_pendingGetDeviceId != null && !_pendingGetDeviceId!.isCompleted) {
    return _pendingGetDeviceId!.future;
  }

  _pendingGetDeviceId = Completer<String>();

  try {
    final id = await _resolveDeviceId();
    _pendingGetDeviceId!.complete(id);
    return id;
  } catch (e) {
    final fallbackId = 'mobile-error-${DateTime.now().millisecondsSinceEpoch}';
    Logger.e('Device ID resolution failed completely: $e — using fallback');
    _pendingGetDeviceId!.complete(fallbackId);
    return fallbackId;
  }
}

/// Core resolution logic — tries secure storage, then migration, then hardware.
Future<String> _resolveDeviceId() async {
  // ── Step 1: Check secure storage (primary) ──
  try {
    final secureId = await _secureStorage.read(key: _secureDeviceIdKey);
    if (secureId != null && secureId.isNotEmpty) {
      Logger.d('Device ID loaded from secure storage');
      return secureId;
    }
  } catch (e) {
    Logger.w('Secure storage read failed (will try migration): $e');
  }

  // ── Step 2: Migrate from legacy SharedPreferences ──
  try {
    final prefs = await SharedPreferences.getInstance();
    final legacyId = prefs.getString(_legacyDeviceIdKey);

    if (legacyId != null && legacyId.isNotEmpty) {
      Logger.i('Migrating device ID from SharedPreferences to secure storage');

      // Write to secure storage
      try {
        await _secureStorage.write(key: _secureDeviceIdKey, value: legacyId);
        Logger.i('Device ID migration successful');
      } catch (e) {
        Logger.w('Failed to write migrated ID to secure storage: $e');
        // Still return the legacy ID even if secure write fails
      }

      // Clean up legacy storage (best-effort, don't fail if this errors)
      try {
        await prefs.remove(_legacyDeviceIdKey);
      } catch (_) {}

      return legacyId;
    }
  } catch (e) {
    Logger.w('SharedPreferences migration check failed: $e');
  }

  // ── Step 3: Generate from hardware (new device / fresh install) ──
  final hardwareId = await _getHardwareId();
  final deviceId = 'mobile-$hardwareId';

  // Store in secure storage
  try {
    await _secureStorage.write(key: _secureDeviceIdKey, value: deviceId);
    Logger.i('New device ID stored in secure storage');
  } catch (e) {
    Logger.w('Failed to store new device ID in secure storage: $e');
    // Also try SharedPreferences as a fallback write
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_legacyDeviceIdKey, deviceId);
      Logger.i('Device ID stored in SharedPreferences as fallback');
    } catch (_) {}
  }

  return deviceId;
}

/// Get a hardware-based identifier with retry logic for nil values.
///
/// - iOS: `identifierForVendor` with one retry after 500ms if nil
/// - Android: `ANDROID_ID` (androidInfo.id) with fallback to `fingerprint`
Future<String> _getHardwareId() async {
  final deviceInfo = DeviceInfoPlugin();

  if (Platform.isIOS) {
    return await _getIOSHardwareId(deviceInfo);
  } else if (Platform.isAndroid) {
    return await _getAndroidHardwareId(deviceInfo);
  } else {
    return 'unknown-${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// iOS: identifierForVendor with retry.
///
/// `identifierForVendor` can return nil when:
/// - Device is locked and hasn't been unlocked since reboot
/// - App is in a restricted background state
/// - Very early in the app lifecycle on some iOS versions
///
/// We retry once after 500ms to handle transient nil cases.
Future<String> _getIOSHardwareId(DeviceInfoPlugin deviceInfo) async {
  // First attempt
  try {
    final iosInfo = await deviceInfo.iosInfo;
    if (iosInfo.identifierForVendor != null &&
        iosInfo.identifierForVendor!.isNotEmpty) {
      return iosInfo.identifierForVendor!;
    }
  } catch (e) {
    Logger.w('iOS device info first attempt failed: $e');
  }

  // Wait and retry once
  Logger.w('identifierForVendor was nil, retrying after 500ms...');
  await Future.delayed(const Duration(milliseconds: 500));

  try {
    final iosInfo = await deviceInfo.iosInfo;
    if (iosInfo.identifierForVendor != null &&
        iosInfo.identifierForVendor!.isNotEmpty) {
      Logger.i('identifierForVendor succeeded on retry');
      return iosInfo.identifierForVendor!;
    }
  } catch (e) {
    Logger.e('iOS device info retry failed: $e');
  }

  // Both attempts returned nil — generate a stable fallback.
  // This should be extremely rare.
  Logger.e('identifierForVendor nil after retry — using timestamp fallback');
  return 'ios-fallback-${DateTime.now().millisecondsSinceEpoch}';
}

/// Android: ANDROID_ID with fallback to fingerprint.
///
/// `androidInfo.id` is `Settings.Secure.ANDROID_ID` — unique per device + user
/// combination, persists across reinstalls, changes only on factory reset.
///
/// `androidInfo.fingerprint` is a build fingerprint — same across all devices
/// with the same ROM. Only used as a last-resort fallback.
Future<String> _getAndroidHardwareId(DeviceInfoPlugin deviceInfo) async {
  try {
    final androidInfo = await deviceInfo.androidInfo;

    // Prefer ANDROID_ID (unique per device)
    final androidId = androidInfo.id;
    if (androidId.isNotEmpty) {
      return androidId;
    }

    // Fallback to fingerprint (not unique per device, but stable)
    Logger.w('ANDROID_ID empty, falling back to fingerprint');
    final fingerprint = androidInfo.fingerprint;
    if (fingerprint.isNotEmpty) {
      return fingerprint;
    }

    // Last resort
    Logger.e('Both ANDROID_ID and fingerprint empty');
    return 'android-fallback-${DateTime.now().millisecondsSinceEpoch}';
  } catch (e) {
    Logger.e('Android device info failed: $e');
    return 'android-error-${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// Get human-readable device information string using actual device details.
Future<String> getDeviceInfoString() async {
  const String appVersion = '1.2.2'; // From pubspec.yaml version

  try {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      final brand = androidInfo.brand;
      final model = androidInfo.model;
      final version = androidInfo.version.release;
      return '$brand $model (Android $version, v$appVersion)';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      final model = iosInfo.model;
      final systemVersion = iosInfo.systemVersion;
      return 'Apple $model (iOS $systemVersion, v$appVersion)';
    }

    return '${Platform.operatingSystem} Device (v$appVersion)';
  } catch (e) {
    // Fallback to basic device info if hardware info fails
    Logger.e('Device info string error: $e');
    return '${Platform.operatingSystem} Device (v$appVersion)';
  }
}

/// Clear stored device ID from both secure and legacy storage.
/// Used for testing or admin reset scenarios.
Future<void> clearDeviceId() async {
  try {
    await _secureStorage.delete(key: _secureDeviceIdKey);
  } catch (e) {
    Logger.w('Failed to clear device ID from secure storage: $e');
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyDeviceIdKey);
  } catch (e) {
    Logger.w('Failed to clear device ID from SharedPreferences: $e');
  }
}

/// Check if device has a stored ID (in either storage).
Future<bool> hasStoredDeviceId() async {
  try {
    final secureId = await _secureStorage.read(key: _secureDeviceIdKey);
    if (secureId != null && secureId.isNotEmpty) return true;
  } catch (_) {}

  try {
    final prefs = await SharedPreferences.getInstance();
    final legacyId = prefs.getString(_legacyDeviceIdKey);
    return legacyId != null && legacyId.isNotEmpty;
  } catch (_) {}

  return false;
}

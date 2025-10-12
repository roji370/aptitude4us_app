import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Generate a stable device ID using hardware-based identifiers
/// Uses androidId for Android and identifierForVendor for iOS (Hybrid Approach)
Future<String> getDeviceId() async {
  const String deviceIdKey = 'briffini_device_id';
  
  // Try to get existing device ID from storage first
  final prefs = await SharedPreferences.getInstance();
  String? existingId = prefs.getString(deviceIdKey);
  
  if (existingId != null && existingId.isNotEmpty) {
    return existingId;
  }

  try {
    // Get hardware-based device ID
    final deviceInfo = DeviceInfoPlugin();
    String hardwareId = '';
    
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      // Use fingerprint as a unique device identifier for Android
      hardwareId = androidInfo.fingerprint ?? 
                   androidInfo.board ?? 
                   'android-${DateTime.now().millisecondsSinceEpoch}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      hardwareId = iosInfo.identifierForVendor ?? 'ios-${DateTime.now().millisecondsSinceEpoch}';
    } else {
      // Fallback for other platforms
      hardwareId = 'unknown-${DateTime.now().millisecondsSinceEpoch}';
    }
    
    // Ensure hardwareId is not empty
    if (hardwareId.isEmpty) {
      hardwareId = 'fallback-${DateTime.now().millisecondsSinceEpoch}';
    }
    
    // Create prefixed device ID
    final deviceId = 'mobile-$hardwareId';
    
    // Store for future use
    await prefs.setString(deviceIdKey, deviceId);
    
    return deviceId;
  } catch (e) {
    // If hardware device info fails, generate a fallback ID
    print('Device ID generation error: $e');
    final fallbackId = 'mobile-fallback-${DateTime.now().millisecondsSinceEpoch}';
    
    // Store fallback ID
    await prefs.setString(deviceIdKey, fallbackId);
    
    return fallbackId;
  }
}

/// Get human-readable device information string using actual device details
Future<String> getDeviceInfoString() async {
  const String appVersion = '1.0.4'; // From pubspec.yaml version
  
  try {
    final deviceInfo = DeviceInfoPlugin();
    
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      final brand = androidInfo.brand ?? 'Android';
      final model = androidInfo.model ?? 'Device';
      final version = androidInfo.version.release ?? 'Unknown';
      return '$brand $model (Android $version, v$appVersion)';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      final model = iosInfo.model ?? 'Device';
      final systemVersion = iosInfo.systemVersion ?? 'Unknown';
      return 'Apple $model (iOS $systemVersion, v$appVersion)';
    }
    
    return '${Platform.operatingSystem} Device (v$appVersion)';
  } catch (e) {
    // Fallback to basic device info if hardware info fails
    print('Device info string error: $e');
    return '${Platform.operatingSystem} Device (v$appVersion)';
  }
}

/// Clear stored device ID (for testing or admin reset scenarios)
Future<void> clearDeviceId() async {
  const String deviceIdKey = 'briffini_device_id';
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(deviceIdKey);
}

/// Check if device has a stored ID
Future<bool> hasStoredDeviceId() async {
  const String deviceIdKey = 'briffini_device_id';
  final prefs = await SharedPreferences.getInstance();
  final existingId = prefs.getString(deviceIdKey);
  return existingId != null && existingId.isNotEmpty;
}

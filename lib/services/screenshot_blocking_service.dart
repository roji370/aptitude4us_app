import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';

/// Service for managing screenshot detection and blocking functionality
///
/// This service tracks screenshot attempts and enforces blocking policies:
/// 1. First screenshot attempt: Shows warning
/// 2. Second screenshot attempt: Blocks access to content
///
/// Note: Only active on iOS platform
class ScreenshotBlockingService extends ChangeNotifier {
  static const String _channelName = 'flutter.native/screenProtection';
  static const MethodChannel _channel = MethodChannel(_channelName);
  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'us-central1',
  );

  // Storage key prefixes for persistent state (will be made user-specific)
  static const String _keyPrefixScreenshotCount = 'screenshot_count_';
  static const String _keyPrefixIsAccessBlocked = 'screenshot_access_blocked_';
  static const String _keyPrefixLastWarningTime =
      'screenshot_last_warning_time_';

  // State variables
  bool _isMonitoring = false;
  int _screenshotCount = 0;
  bool _isAccessBlocked = false;
  DateTime? _lastWarningTime;

  // Getters
  bool get isMonitoring => _isMonitoring;
  int get screenshotCount => _screenshotCount;
  bool get isAccessBlocked => _isAccessBlocked;
  bool get hasReceivedWarning => _screenshotCount >= 1;
  DateTime? get lastWarningTime => _lastWarningTime;

  /// Singleton instance
  static final ScreenshotBlockingService _instance =
      ScreenshotBlockingService._internal();
  factory ScreenshotBlockingService() => _instance;
  ScreenshotBlockingService._internal();

  /// Get current user ID for user-specific storage
  String? _getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      Logger.w('📱 No authenticated user for screenshot service');
      return null;
    }
    return user.uid;
  }

  /// Get user-specific storage keys
  Map<String, String>? _getUserSpecificKeys() {
    final userId = _getCurrentUserId();
    if (userId == null) return null;

    return {
      'screenshotCount': '$_keyPrefixScreenshotCount$userId',
      'isAccessBlocked': '$_keyPrefixIsAccessBlocked$userId',
      'lastWarningTime': '$_keyPrefixLastWarningTime$userId',
    };
  }

  /// Initialize the service and load persistent state
  Future<void> initialize() async {
    Logger.i('📱 Initializing ScreenshotBlockingService');
    await _loadState();

    // Only set up monitoring on iOS
    if (ResponsiveHelper.isIOS()) {
      await _setupScreenshotDetection();
    } else {
      Logger.i('📱 Screenshot blocking only available on iOS - skipping setup');
    }
  }

  /// Load persistent state from SharedPreferences
  Future<void> _loadState() async {
    try {
      final keys = _getUserSpecificKeys();
      if (keys == null) {
        Logger.w('📱 Cannot load state: No authenticated user');
        // Reset to default values when no user
        _screenshotCount = 0;
        _isAccessBlocked = false;
        _lastWarningTime = null;
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      _screenshotCount = prefs.getInt(keys['screenshotCount']!) ?? 0;
      _isAccessBlocked = prefs.getBool(keys['isAccessBlocked']!) ?? false;

      final lastWarningTimestamp = prefs.getInt(keys['lastWarningTime']!);
      if (lastWarningTimestamp != null) {
        _lastWarningTime = DateTime.fromMillisecondsSinceEpoch(
          lastWarningTimestamp,
        );
      }

      final userId = _getCurrentUserId();
      Logger.i(
        '📱 Loaded screenshot state for user $userId: count=$_screenshotCount, blocked=$_isAccessBlocked',
      );
    } catch (error) {
      Logger.e('❌ Error loading screenshot blocking state: $error');
    }
  }

  /// Save current state to SharedPreferences
  Future<void> _saveState() async {
    try {
      final keys = _getUserSpecificKeys();
      if (keys == null) {
        Logger.w('📱 Cannot save state: No authenticated user');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(keys['screenshotCount']!, _screenshotCount);
      await prefs.setBool(keys['isAccessBlocked']!, _isAccessBlocked);

      if (_lastWarningTime != null) {
        await prefs.setInt(
          keys['lastWarningTime']!,
          _lastWarningTime!.millisecondsSinceEpoch,
        );
      }

      final userId = _getCurrentUserId();
      Logger.i(
        '📱 Saved screenshot state for user $userId: count=$_screenshotCount, blocked=$_isAccessBlocked',
      );
    } catch (error) {
      Logger.e('❌ Error saving screenshot blocking state: $error');
    }
  }

  /// Set up iOS native screenshot detection
  Future<void> _setupScreenshotDetection() async {
    if (_isMonitoring) return;

    try {
      Logger.i('📱 Setting up iOS screenshot detection');

      // Set up method call handler for screenshot notifications from iOS
      _channel.setMethodCallHandler(_handleMethodCall);

      // Enable screenshot monitoring on iOS side
      await _channel.invokeMethod('enableScreenshotMonitoring');
      _isMonitoring = true;

      Logger.i('📱 Screenshot detection enabled successfully');
    } catch (error) {
      Logger.e('❌ Error setting up screenshot detection: $error');
    }
  }

  /// Handle method calls from iOS native code
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onScreenshotDetected':
        await _handleScreenshotDetected();
        break;
      default:
        Logger.w('📱 Unknown method call from iOS: ${call.method}');
    }
  }

  /// Handle when a screenshot is detected
  Future<void> _handleScreenshotDetected() async {
    Logger.w('📱 Screenshot detected! Recording violation...');

    try {
      // Record violation using Firebase function
      await _recordScreenshotViolation();
    } catch (error) {
      Logger.e('❌ Error recording violation, using local fallback: $error');
      // Fallback to local handling if Firebase fails
      await _handleScreenshotDetectedLocal();
    }
  }

  /// Record screenshot violation using Firebase function
  Future<void> _recordScreenshotViolation() async {
    try {
      final result =
          await _functions.httpsCallable('recordScreenshotViolation').call();

      final data = result.data;
      final violationCount = data['violationCount'] as int;
      final isBlocked = data['isBlocked'] as bool;
      final message = data['message'] as String;

      Logger.i('✅ Violation recorded: $message');
      Logger.i('📊 Total violations: $violationCount');

      // Update local state to match backend
      _screenshotCount = violationCount;
      _isAccessBlocked = isBlocked;
      _lastWarningTime = DateTime.now();

      await _saveState();
      notifyListeners();
    } catch (error) {
      Logger.e('❌ Error calling recordScreenshotViolation: $error');
      rethrow;
    }
  }

  /// Local fallback for screenshot detection
  Future<void> _handleScreenshotDetectedLocal() async {
    _screenshotCount++;
    _lastWarningTime = DateTime.now();

    if (_screenshotCount == 1) {
      Logger.w('📱 First screenshot detected - showing warning');
      await _saveState();
      notifyListeners();
    } else if (_screenshotCount >= 2) {
      Logger.e('📱 Multiple screenshots detected - blocking access');
      _isAccessBlocked = true;
      await _saveState();
      notifyListeners();
    }
  }

  /// Start monitoring screenshots (call when entering protected content)
  Future<void> startMonitoring() async {
    if (!ResponsiveHelper.isIOS()) return;

    if (!_isMonitoring) {
      await _setupScreenshotDetection();
    }

    Logger.i('📱 Started screenshot monitoring');
  }

  /// Stop monitoring screenshots (call when leaving protected content)
  Future<void> stopMonitoring() async {
    if (!ResponsiveHelper.isIOS() || !_isMonitoring) return;

    try {
      await _channel.invokeMethod('disableScreenshotMonitoring');
      _isMonitoring = false;
      Logger.i('📱 Stopped screenshot monitoring');
    } catch (error) {
      Logger.e('❌ Error stopping screenshot monitoring: $error');
    }
  }

  /// Reset the screenshot count and blocking state (for testing or admin reset)
  Future<void> resetState() async {
    Logger.i('📱 Resetting screenshot blocking state');

    _screenshotCount = 0;
    _isAccessBlocked = false;
    _lastWarningTime = null;

    await _saveState();
    notifyListeners();
  }

  /// Check for admin reset from backend (call this periodically)
  Future<void> checkForAdminReset() async {
    if (!ResponsiveHelper.isIOS()) return;

    final userId = _getCurrentUserId();
    if (userId == null) {
      Logger.w('📱 Cannot check for admin reset: No authenticated user');
      return;
    }

    try {
      Logger.d('📱 Checking for admin reset for user $userId...');

      final result =
          await _functions.httpsCallable('checkViolationResetStatus').call();

      final data = result.data;
      final hasBeenReset = data['hasBeenReset'] as bool;
      final currentViolations = data['currentViolations'] as int;
      final isBlocked = data['isBlocked'] as bool;

      if (hasBeenReset) {
        Logger.i('🎉 Screenshot violations reset by admin for user $userId!');

        // Update local state to match backend
        _screenshotCount = currentViolations;
        _isAccessBlocked = isBlocked;
        _lastWarningTime = null;

        await _saveState();
        notifyListeners();

        // Acknowledge the reset
        await _acknowledgeReset();
      } else {
        Logger.d('📱 No admin reset detected for user $userId');
      }
    } catch (error) {
      Logger.e('❌ Error checking for admin reset: $error');
    }
  }

  /// Acknowledge that the reset has been processed
  Future<void> _acknowledgeReset() async {
    try {
      await _functions.httpsCallable('acknowledgeViolationReset').call();
      Logger.i('✅ Reset acknowledged');
    } catch (error) {
      Logger.e('❌ Error acknowledging reset: $error');
    }
  }

  /// Check if content access should be blocked due to screenshot violations
  bool shouldBlockAccess() {
    final blocked = _isAccessBlocked && ResponsiveHelper.isIOS();
    if (blocked) {
      Logger.w('📱 Access blocked due to screenshot violations');
    }
    return blocked;
  }

  /// Check if warning should be shown (first screenshot)
  bool shouldShowWarning() {
    final showWarning =
        _screenshotCount == 1 && !_isAccessBlocked && ResponsiveHelper.isIOS();
    if (showWarning) {
      Logger.w('📱 Should show screenshot warning');
    }
    return showWarning;
  }

  /// Handle user authentication changes (login/logout)
  Future<void> onUserAuthChanged(User? user) async {
    if (user == null) {
      // User logged out - clear local state
      Logger.i('📱 User logged out - clearing screenshot state');
      _screenshotCount = 0;
      _isAccessBlocked = false;
      _lastWarningTime = null;
      notifyListeners();
    } else {
      // User logged in - load their specific state
      Logger.i('📱 User logged in (${user.uid}) - loading screenshot state');
      await _loadState();
      notifyListeners();
    }
  }

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

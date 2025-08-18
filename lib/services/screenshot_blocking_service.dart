import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
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

  // Storage keys for persistent state
  static const String _keyScreenshotCount = 'screenshot_count';
  static const String _keyIsAccessBlocked = 'screenshot_access_blocked';
  static const String _keyLastWarningTime = 'screenshot_last_warning_time';

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
      final prefs = await SharedPreferences.getInstance();
      _screenshotCount = prefs.getInt(_keyScreenshotCount) ?? 0;
      _isAccessBlocked = prefs.getBool(_keyIsAccessBlocked) ?? false;

      final lastWarningTimestamp = prefs.getInt(_keyLastWarningTime);
      if (lastWarningTimestamp != null) {
        _lastWarningTime = DateTime.fromMillisecondsSinceEpoch(
          lastWarningTimestamp,
        );
      }

      Logger.i(
        '📱 Loaded screenshot state: count=$_screenshotCount, blocked=$_isAccessBlocked',
      );
    } catch (error) {
      Logger.e('❌ Error loading screenshot blocking state: $error');
    }
  }

  /// Save current state to SharedPreferences
  Future<void> _saveState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_keyScreenshotCount, _screenshotCount);
      await prefs.setBool(_keyIsAccessBlocked, _isAccessBlocked);

      if (_lastWarningTime != null) {
        await prefs.setInt(
          _keyLastWarningTime,
          _lastWarningTime!.millisecondsSinceEpoch,
        );
      }

      Logger.i(
        '📱 Saved screenshot state: count=$_screenshotCount, blocked=$_isAccessBlocked',
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

    try {
      Logger.d('📱 Checking for admin reset...');

      final result =
          await _functions.httpsCallable('checkViolationResetStatus').call();

      final data = result.data;
      final hasBeenReset = data['hasBeenReset'] as bool;
      final currentViolations = data['currentViolations'] as int;
      final isBlocked = data['isBlocked'] as bool;

      if (hasBeenReset) {
        Logger.i('🎉 Screenshot violations reset by admin!');

        // Update local state to match backend
        _screenshotCount = currentViolations;
        _isAccessBlocked = isBlocked;
        _lastWarningTime = null;

        await _saveState();
        notifyListeners();

        // Acknowledge the reset
        await _acknowledgeReset();
      } else {
        Logger.d('📱 No admin reset detected');
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

  /// Dispose resources
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../providers/session_provider.dart';
import '../services/screenshot_blocking_service.dart';
import '../screens/subscription_expired_screen.dart';
import '../screens/screenshot_warning_screen.dart';
import '../screens/screenshot_blocked_screen.dart';
import './screen_recording_warning_dialog.dart';
import '../utils/logger.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';
import '../services/auth_persistence_service.dart';
import '../screens/login_screen.dart';

/// Widget that protects course content behind subscription validation
///
/// This widget ensures that users can only access course content if they have:
/// 1. A valid, active subscription (via [SessionProvider])
/// 2. The course assigned to their account (via [AuthService.isCourseAssigned])
///
/// If access is denied, shows SubscriptionExpiredScreen instead of content.
///
/// Subscription state is read from [SessionProvider] via `context.select`,
/// so rebuilds only happen when the subscription status actually changes.
/// Course assignment is checked via custom claims (verify-on-denial pattern).
class ProtectedCourseContent extends StatefulWidget {
  final Widget child;
  final String? courseId;
  final String? contentTitle;
  final bool showLoadingSpinner;

  const ProtectedCourseContent({
    Key? key,
    required this.child,
    this.courseId,
    this.contentTitle,
    this.showLoadingSpinner = true,
  }) : super(key: key);

  @override
  State<ProtectedCourseContent> createState() => _ProtectedCourseContentState();
}

class _ProtectedCourseContentState extends State<ProtectedCourseContent> {
  final ScreenshotBlockingService _screenshotService =
      ScreenshotBlockingService();

  // ── Course assignment state (only relevant when courseId is non-null) ──
  bool? _isCourseAssigned; // null = not checked yet
  bool _isCourseCheckLoading = false;
  String? _courseErrorMessage;

  // ── Generation tracking ──
  int _lastCheckedGeneration = -1;

  // ── Screenshot/screen-recording state ──
  bool _isNavigatingToSubscription = false;
  bool _showingScreenshotWarning = false;
  bool _showingScreenRecordingWarning = false;

  // ── Error / auth state ──
  String? _errorMessage;

  // ── Retry cooldown ──
  Timer? _retryCooldownTimer;
  int _retryCooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _initializeScreenshotService();
    // Course assignment check is triggered in build() via generation
    // tracking (context.select on dataGeneration), so no need to call it here.
  }

  @override
  void dispose() {
    _retryCooldownTimer?.cancel();
    _screenshotService.removeListener(_onScreenshotServiceChanged);
    _screenshotService.stopMonitoring();
    super.dispose();
  }


  @override
  void didUpdateWidget(ProtectedCourseContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.courseId != widget.courseId) {
      // courseId changed — reset course-level state
      _isCourseAssigned = null;
      _isCourseCheckLoading = false;
      _courseErrorMessage = null;
      _isNavigatingToSubscription = false;
      _errorMessage = null;
      if (widget.courseId != null) {
        _checkCourseAssignment();
      }
    }
  }

  // ── Course assignment check (verify-on-denial via claims) ──

  Future<void> _checkCourseAssignment() async {
    if (!mounted || widget.courseId == null) return;

    final courseId = widget.courseId!;

    setState(() {
      _isCourseCheckLoading = true;
      _courseErrorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) {
        if (mounted) {
          setState(() {
            _isCourseAssigned = false;
            _isCourseCheckLoading = false;
            _errorMessage = 'Please log in to access content';
          });
        }
        return;
      }

      // Uses the verify-on-denial pattern:
      // Fast path: cached claims say assigned → true (0 reads)
      // Denial path: claims say no → refreshClaimsIfAllowed → re-check
      final assigned = await authService
          .isCourseAssigned(courseId)
          .timeout(const Duration(seconds: 8));

      if (mounted) {
        setState(() {
          _isCourseAssigned = assigned;
          _isCourseCheckLoading = false;
          if (!assigned) {
            _courseErrorMessage = null; // Not an error, just not assigned
          }
        });
      }
    } catch (e) {
      Logger.e('❌ Course assignment check failed: $e');
      if (mounted) {
        setState(() {
          // Fail closed: deny access on error
          _isCourseAssigned = false;
          _isCourseCheckLoading = false;
          _courseErrorMessage =
              'Unable to verify course access. Please try again.';
        });
      }
    }

    // Start cooldown countdown if the check denied access and cooldown is active.
    if (mounted && _isCourseAssigned == false) {
      _startRetryCooldown();
    }
  }

  /// Reads the authoritative cooldown from [AuthService] and starts a
  /// periodic timer that decrements [_retryCooldownSeconds] each second.
  /// The Retry button is disabled while the countdown is active.
  void _startRetryCooldown() {
    _retryCooldownTimer?.cancel();
    final authService = Provider.of<AuthService>(context, listen: false);
    final remaining = authService.claimsRefreshCooldownRemaining;
    if (remaining <= 0) {
      if (_retryCooldownSeconds != 0) {
        setState(() { _retryCooldownSeconds = 0; });
      }
      return;
    }
    _retryCooldownSeconds = remaining;
    setState(() {});
    _retryCooldownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) {
          _retryCooldownTimer?.cancel();
          return;
        }
        setState(() {
          _retryCooldownSeconds--;
          if (_retryCooldownSeconds <= 0) {
            _retryCooldownSeconds = 0;
            _retryCooldownTimer?.cancel();
          }
        });
      },
    );
  }

  /// Navigate to subscription screen and handle result
  Future<void> _navigateToSubscriptionScreen() async {
    if (!mounted || _isNavigatingToSubscription) return;

    setState(() {
      _isNavigatingToSubscription = true;
    });

    try {
      Logger.i('📱 Navigating to subscription expired screen');

      final result = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(
          builder:
              (context) => SubscriptionExpiredScreen(
                contentTitle: widget.contentTitle,
                courseId: widget.courseId,
              ),
        ),
      );

      Logger.i('📱 Returned from subscription screen with result: $result');

      if (mounted) {
        // Force a subscription re-check via SessionProvider
        final session =
            Provider.of<SessionProvider>(context, listen: false);
        await session.checkSubscription(forceRefresh: true);

        // Also re-check course assignment if applicable
        if (widget.courseId != null) {
          await _checkCourseAssignment();
        }
      }
    } catch (error) {
      Logger.e('❌ Error navigating to subscription screen: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isNavigatingToSubscription = false;
        });
      }
    }
  }

  // ── Screenshot service (unchanged from original) ──

  Future<void> _initializeScreenshotService() async {
    if (!ResponsiveHelper.isIOS() && !ResponsiveHelper.isAndroid()) {
      Logger.i('📱 Screenshot blocking not available on this platform');
      return;
    }

    try {
      await _screenshotService.initialize();
      _screenshotService.addListener(_onScreenshotServiceChanged);

      final authService = Provider.of<AuthService>(context, listen: false);
      await _screenshotService.onUserAuthChanged(authService.currentUser);

      await _screenshotService.checkForAdminReset();
      await _screenshotService.startMonitoring();

      Logger.i('📱 Screenshot blocking service initialized successfully');
    } catch (error) {
      Logger.e('❌ Error initializing screenshot service: $error');
    }
  }

  void _onScreenshotServiceChanged() {
    if (!mounted) return;

    Logger.i('📱 Screenshot service state changed');

    if (_screenshotService.shouldShowResetMessage) {
      _showAccessRestoredMessage();
    }

    if (_screenshotService.shouldShowWarning() && !_showingScreenshotWarning) {
      _showScreenshotWarning();
    }

    if (_screenshotService.shouldShowScreenRecordingWarning &&
        !_showingScreenRecordingWarning) {
      Logger.w('📱 Triggering screen recording warning dialog');
      _showScreenRecordingWarning();
    }

    if (_screenshotService.shouldBlockAccess()) {
      _showScreenshotBlocked();
    }
  }

  void _showScreenshotWarning() {
    if (_showingScreenshotWarning) return;

    setState(() {
      _showingScreenshotWarning = true;
    });

    _screenshotService.markWarningShown();

    Logger.w('📱 Showing screenshot warning screen');

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) => ScreenshotWarningScreen(
              onContinue: () {
                Navigator.of(context).pop();
                setState(() {
                  _showingScreenshotWarning = false;
                });
              },
            ),
        transitionDuration: Duration(milliseconds: 150),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );
  }

  void _showScreenshotBlocked() {
    Logger.e('📱 Showing screenshot blocked screen');

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const ScreenshotBlockedScreen(),
        transitionDuration: Duration(
          milliseconds: 100,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );
  }

  void _showScreenRecordingWarning() {
    if (_showingScreenRecordingWarning) return;

    setState(() {
      _showingScreenRecordingWarning = true;
    });

    Logger.w('📱 Showing screen recording warning dialog');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return ScreenRecordingWarningDialog(
          onDismiss: () {
            setState(() {
              _showingScreenRecordingWarning = false;
            });
            _screenshotService.markScreenRecordingWarningShown();
          },
        );
      },
    );
  }

  void _showAccessRestoredMessage() {
    Logger.i('🎉 Showing access restored message');

    _screenshotService.acknowledgeResetMessage();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Your access has been restored by an administrator',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green[600],
        duration: Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    // Screenshot blocking first (iOS only - Android uses FLAG_SECURE)
    if (ResponsiveHelper.isIOS() && _screenshotService.shouldBlockAccess()) {
      Logger.e('📱 Access blocked due to screenshot violations');
      return const ScreenshotBlockedScreen();
    }

    // Auth error (e.g. no user)
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    // Read session state from SessionProvider via context.select.
    // Widget only rebuilds when a selected value actually changes.
    final hasActiveSubscription = context.select<SessionProvider, bool>(
      (s) => s.hasActiveSubscription,
    );
    final hasCheckedOnce = context.select<SessionProvider, bool>(
      (s) => s.hasCheckedOnce,
    );
    // dataGeneration: ensures this widget rebuilds when SessionProvider's
    // generation counter bumps (e.g. stale-resume refresh), even if
    // hasActiveSubscription/hasCheckedOnce didn't change.
    final dataGeneration = context.select<SessionProvider, int>(
      (s) => s.dataGeneration,
    );

    // Still loading initial subscription check
    if (!hasCheckedOnce) {
      return _buildLoadingState();
    }

    // Subscription expired → show expired screen
    if (!hasActiveSubscription) {
      Logger.w(
        '🚫 Content access denied - subscription expired',
      );
      if (!_isNavigatingToSubscription) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigateToSubscriptionScreen();
        });
      }
      return _buildLoadingState();
    }

    // ── Subscription is active. Check course assignment if courseId is set. ──

    if (widget.courseId != null) {
      // Re-verify course assignment when data generation changes.
      // The context.select on dataGeneration above ensures this widget
      // rebuilds even if subscription fields didn't change.
      if (_lastCheckedGeneration != dataGeneration) {
        _lastCheckedGeneration = dataGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkCourseAssignment();
        });
      }

      // Course assignment error
      if (_courseErrorMessage != null) {
        return _buildCourseErrorState();
      }

      // Still checking course assignment
      if (_isCourseCheckLoading || _isCourseAssigned == null) {
        return _buildLoadingState(message: 'Checking course access...');
      }

      // Course not assigned — show "not assigned" screen with retry
      if (_isCourseAssigned == false) {
        return _buildCourseNotAssignedState();
      }
    }

    // ── All checks passed — show content ──
    Logger.i('✅ Content access granted');
    return widget.child;
  }

  Widget _buildLoadingState({String? message}) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                strokeWidth: 3,
              ),
              const SizedBox(height: 24),
              Text(
                message ?? 'Verifying access...',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              if (widget.contentTitle != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.contentTitle!,
                  style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Checking subscription status...',
                  style: TextStyle(fontSize: 14, color: AppColors.primary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final bool isAuthMissing = authService.currentUser == null;

    return Container(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              'Access Error',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (isAuthMissing)
              ElevatedButton(
                onPressed: () async {
                  await AuthPersistenceService.clearAll();
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (context) => const LoginScreen(),
                    ),
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('Go to Login'),
              )
            else
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                  // Trigger a fresh subscription check
                  final session =
                      Provider.of<SessionProvider>(context, listen: false);
                  session.checkSubscription(forceRefresh: true);
                  if (widget.courseId != null) {
                    _checkCourseAssignment();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('Try Again'),
              ),
          ],
        ),
      ),
    );
  }

  /// Course-level error state (network failure during assignment check)
  Widget _buildCourseErrorState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.orange[300]),
            const SizedBox(height: 16),
            Text(
              'Unable to Verify Access',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.orange[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _courseErrorMessage!,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _checkCourseAssignment(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  /// "Course not assigned" state — generic message, Retry button.
  /// No mention of renewal or internal details; just "contact your administrator".
  Widget _buildCourseNotAssignedState() {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'Course Not Available',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This course is not currently assigned to your account. '
                'Please contact your administrator for access.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _retryCooldownSeconds > 0
                    ? null // disabled during cooldown
                    : () => _checkCourseAssignment(),
                icon: Icon(
                  _retryCooldownSeconds > 0 ? Icons.timer : Icons.refresh,
                ),
                label: Text(
                  _retryCooldownSeconds > 0
                      ? 'Retry in ${_retryCooldownSeconds}s'
                      : 'Retry',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey[300],
                  disabledForegroundColor: Colors.grey[600],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Go Back',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience wrapper for protecting entire screens
class ProtectedCourseScreen extends StatelessWidget {
  final Widget child;
  final String? courseId;
  final String? title;

  const ProtectedCourseScreen({
    Key? key,
    required this.child,
    this.courseId,
    this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ProtectedCourseContent(
        courseId: courseId,
        contentTitle: title,
        child: child,
      ),
    );
  }
}

/// Mixin for adding subscription validation to existing widgets
mixin SubscriptionValidationMixin<T extends StatefulWidget> on State<T> {
  /// Quick method to check if current user has course access
  Future<bool> validateCourseAccess(String courseId) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      return await authService.isCourseAssigned(courseId);
    } catch (error) {
      Logger.e('❌ Course access validation failed: $error');
      return false;
    }
  }

  /// Quick method to check if current user has active subscription.
  ///
  /// Note: The catch block returns `false` (fail-closed), which is
  /// intentionally stricter than the optimistic-true default used in
  /// [SessionProvider]. This catches programming errors (e.g. missing
  /// provider in the widget tree) rather than network failures. Callers
  /// who need the optimistic default should read
  /// `SessionProvider.hasActiveSubscription` directly.
  bool validateSubscriptionStatus() {
    try {
      final session = Provider.of<SessionProvider>(context, listen: false);
      return session.hasActiveSubscription;
    } catch (error) {
      Logger.e('❌ Subscription status validation failed: $error');
      return false;
    }
  }
}

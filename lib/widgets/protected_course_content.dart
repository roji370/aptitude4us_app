import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
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
/// 1. A valid, active subscription
/// 2. The course assigned to their account
///
/// If access is denied, shows SubscriptionExpiredScreen instead of content
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

class _ProtectedCourseContentState extends State<ProtectedCourseContent>
    with WidgetsBindingObserver {
  final SubscriptionService _subscriptionService = SubscriptionService();
  final ScreenshotBlockingService _screenshotService =
      ScreenshotBlockingService();
  bool? _hasAccess;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isNavigatingToSubscription = false;
  bool _showingScreenshotWarning = false;
  bool _showingScreenRecordingWarning = false;
  bool _hasInitialCheckCompleted = false; // Track whether initial check is done
  int _backgroundRetryCount = 0; // Tracks consecutive background check failures
  static const int _maxBackgroundRetries = 3; // Show refresh prompt after this many failures
  bool _showRefreshPrompt = false; // Show a non-intrusive banner asking user to refresh
  bool _isManualRefreshing = false; // True while user-triggered refresh is in progress
  Timer? _retryTimer; // Cancellable handle for scheduled background retries

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreenshotService();
    _checkAccess();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
    WidgetsBinding.instance.removeObserver(this);
    _screenshotService.removeListener(_onScreenshotServiceChanged);
    _screenshotService.stopMonitoring();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Re-check access when app becomes active (useful for external subscription changes)
    if (state == AppLifecycleState.resumed) {
      Logger.i(
        '🔄 App resumed - re-checking subscription access with fresh data',
      );

      // Check for admin reset when app resumes (iOS only feature)
      if (ResponsiveHelper.isIOS()) {
        _screenshotService.checkForAdminReset();
      }

      _checkAccess(forceRefresh: true);
    }
  }

  @override
  void didUpdateWidget(ProtectedCourseContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check access if courseId changes. Reset all per-course state so the
    // new course performs a fresh initial check (with loading UI) instead of
    // a background refresh that could leak the previous course's access state.
    if (oldWidget.courseId != widget.courseId) {
      _retryTimer?.cancel();
      _retryTimer = null;
      _hasAccess = null;
      _hasInitialCheckCompleted = false;
      _backgroundRetryCount = 0;
      _showRefreshPrompt = false;
      _isManualRefreshing = false;
      _isNavigatingToSubscription = false;
      _errorMessage = null;
      _checkAccess();
    }
  }

  /// Force refresh access check (can be called when user returns from subscription screen)
  void refreshAccess() {
    Logger.i('🔄 Manually refreshing subscription access with fresh data');
    _checkAccess(forceRefresh: true);
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

      // Check if subscription was activated
      if (result != null && result['subscriptionActivated'] == true) {
        Logger.i('✅ Subscription was activated - refreshing access');

        if (mounted) {
          // Force refresh the access check with fresh server data
          _checkAccess(forceRefresh: true);
        }
      } else {
        Logger.i('❌ No subscription activation - user may have closed screen');

        if (mounted) {
          // Still refresh in case something changed
          _checkAccess(forceRefresh: true);
        }
      }
    } catch (error) {
      Logger.e('❌ Error navigating to subscription screen: $error');

      if (mounted) {
        // Fallback: still try to refresh access
        _checkAccess(forceRefresh: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isNavigatingToSubscription = false;
        });
      }
    }
  }

  Future<void> _checkAccess({bool forceRefresh = false}) async {
    if (!mounted) return;

    // Cancel any previously-scheduled background retry — this call supersedes it.
    _retryTimer?.cancel();
    _retryTimer = null;

    // CRITICAL UX FIX: If we already completed an initial check and the user
    // had access, do the re-check silently in the background without resetting
    // the UI. This prevents the "Verifying access..." flash when navigating
    // back to the home screen or when the app resumes.
    final bool isBackgroundRefresh = _hasInitialCheckCompleted && _hasAccess == true;

    if (!isBackgroundRefresh) {
      // Only show loading UI on the initial check or when access was previously denied
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      Logger.i('🔄 Background subscription re-check (no UI disruption)');
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      // Update screenshot service with current user state (iOS only)
      if (ResponsiveHelper.isIOS()) {
        _screenshotService.onUserAuthChanged(currentUser);
      }

      if (currentUser == null) {
        Logger.w('🔐 No authenticated user for content access check');
        if (mounted) {
          setState(() {
            _hasAccess = false;
            _isLoading = false;
            _hasInitialCheckCompleted = true;
            _errorMessage = 'Please log in to access content';
          });
        }
        return;
      }

      // LOCAL-FIRST VALIDATION: For background refreshes, check the cached
      // endDate against the user's current local time before hitting the server.
      // This makes rechecks instant when the subscription clearly hasn't expired.
      if (isBackgroundRefresh && !forceRefresh) {
        final localValidity = _subscriptionService.isSubscriptionLocallyValid(
          currentUser.uid,
        );

        if (localValidity == true) {
          // Subscription endDate is still in the future — skip the server call
          final endDate = _subscriptionService.getActiveSubscriptionEndDate(
            currentUser.uid,
          );
          Logger.i(
            '⚡ Local validation passed — subscription valid until '
            '${endDate?.toLocal()} — skipping server call',
          );
          _backgroundRetryCount = 0;

          if (mounted && _showRefreshPrompt) {
            setState(() {
              _showRefreshPrompt = false;
              _isManualRefreshing = false;
            });
          }
          return; // No server call needed
        } else if (localValidity == false) {
          // Cached endDate is in the past — subscription likely expired
          Logger.w(
            '⏰ Local validation: subscription endDate has passed — '
            'verifying with server',
          );
          // Fall through to server check with forceRefresh
          forceRefresh = true;
        }
        // localValidity == null: no cache, fall through to normal server check
      }

      // Server-side validation
      late Future<bool> accessCheckFuture;

      if (widget.courseId == null) {
        Logger.i(
          '🔍 Checking general subscription access for user ${currentUser.uid} (forceRefresh: $forceRefresh, background: $isBackgroundRefresh)',
        );
        accessCheckFuture = _subscriptionService.checkUserActiveSubscription(
          currentUser.uid,
          forceRefresh: forceRefresh,
        );
      } else {
        Logger.i(
          '🔐 Checking course access for ${widget.courseId} (forceRefresh: $forceRefresh, background: $isBackgroundRefresh)',
        );
        accessCheckFuture = _subscriptionService.hasAccessToCourse(
          currentUser.uid,
          widget.courseId!,
          forceRefresh: forceRefresh,
        );
      }

      // Apply timeout — throw on timeout so it enters the retry path
      final hasAccess = await accessCheckFuture.timeout(
        const Duration(seconds: 10),
      );

      // Success — reset the retry counter and clear any refresh prompt
      _backgroundRetryCount = 0;

      if (mounted && (_showRefreshPrompt || _isManualRefreshing)) {
        setState(() {
          _showRefreshPrompt = false;
          _isManualRefreshing = false;
        });
      }

      if (mounted) {
        // Only update UI if the result actually changed, or if this is the initial check
        if (!isBackgroundRefresh || hasAccess != _hasAccess) {
          setState(() {
            _hasAccess = hasAccess;
            _isLoading = false;
            _hasInitialCheckCompleted = true;
          });

          // If access was revoked during a background check, log it clearly
          if (isBackgroundRefresh && !hasAccess) {
            Logger.w('⚠️ Subscription access revoked during background check');
          }
        } else {
          // Background check confirmed access is still valid — no UI update needed
          Logger.i('✅ Background subscription check confirmed: access still valid');
        }
      }
    } catch (error) {
      Logger.e('❌ Error checking content access: $error');

      if (isBackgroundRefresh) {
        _backgroundRetryCount++;
        Logger.w(
          '⚠️ Background subscription check failed '
          '(attempt $_backgroundRetryCount/$_maxBackgroundRetries): $error',
        );

        if (_backgroundRetryCount >= _maxBackgroundRetries) {
          // All silent retries exhausted — show a non-intrusive prompt asking
          // the user to manually verify. Content stays visible.
          Logger.w(
            '⚠️ Max background retries reached — prompting user to refresh manually',
          );
          _backgroundRetryCount = 0;

          if (mounted) {
            setState(() {
              _showRefreshPrompt = true;
            });
          }
        } else {
          // Schedule a silent retry with exponential backoff (2s, 4s, 8s)
          final retryDelay = Duration(seconds: 2 * _backgroundRetryCount);
          Logger.i('🔁 Scheduling background retry in ${retryDelay.inSeconds}s');

          _retryTimer?.cancel();
          _retryTimer = Timer(retryDelay, () {
            _retryTimer = null;
            if (mounted) {
              _checkAccess(forceRefresh: true);
            }
          });
        }
      } else {
        // On initial check, show the error
        if (mounted) {
          setState(() {
            _hasAccess = false;
            _isLoading = false;
            _hasInitialCheckCompleted = true;
            _errorMessage = 'Unable to verify access. Please try again.';
          });
        }
      }
    }
  }

  /// Handle the user tapping "Verify Now" on the refresh prompt banner.
  /// If this manual refresh also fails, revoke access.
  Future<void> _handleManualRefresh() async {
    if (!mounted || _isManualRefreshing) return;

    setState(() {
      _isManualRefreshing = true;
    });

    Logger.i('🔄 User-triggered manual subscription refresh');

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) {
        // No user — revoke access
        if (mounted) {
          setState(() {
            _hasAccess = false;
            _isLoading = false;
            _showRefreshPrompt = false;
            _isManualRefreshing = false;
            _errorMessage = 'Please log in to access content';
          });
        }
        return;
      }

      late Future<bool> accessCheckFuture;
      if (widget.courseId == null) {
        accessCheckFuture = _subscriptionService.checkUserActiveSubscription(
          currentUser.uid,
          forceRefresh: true,
        );
      } else {
        accessCheckFuture = _subscriptionService.hasAccessToCourse(
          currentUser.uid,
          widget.courseId!,
          forceRefresh: true,
        );
      }

      final hasAccess = await accessCheckFuture.timeout(
        const Duration(seconds: 15), // Slightly longer timeout for manual retry
      );

      if (mounted) {
        setState(() {
          _hasAccess = hasAccess;
          _isLoading = false;
          _showRefreshPrompt = false;
          _isManualRefreshing = false;
          _backgroundRetryCount = 0;
        });

        if (hasAccess) {
          Logger.i('✅ Manual refresh confirmed: subscription is active');
        } else {
          Logger.w('⚠️ Manual refresh confirmed: subscription is NOT active');
        }
      }
    } catch (error) {
      Logger.e('❌ Manual subscription refresh failed: $error');

      // User-triggered refresh failed — now revoke access for safety
      if (mounted) {
        setState(() {
          _hasAccess = false;
          _isLoading = false;
          _showRefreshPrompt = false;
          _isManualRefreshing = false;
          _errorMessage = 'Unable to verify subscription. Please check your connection and try again.';
        });
      }
    }
  }

  /// Build a non-intrusive banner prompting the user to verify their subscription
  Widget _buildRefreshPromptBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.wifi_off_rounded,
            color: Colors.orange[700],
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Subscription status could not be verified',
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange[900],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _isManualRefreshing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.orange[700]!),
                  ),
                )
              : TextButton(
                  onPressed: _handleManualRefresh,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.orange[800],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: Colors.orange[400]!),
                    ),
                  ),
                  child: const Text(
                    'Verify Now',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
        ],
      ),
    );
  }

  /// Initialize the screenshot blocking service
  Future<void> _initializeScreenshotService() async {
    // Initialize on both iOS and Android
    if (!ResponsiveHelper.isIOS() && !ResponsiveHelper.isAndroid()) {
      Logger.i('📱 Screenshot blocking not available on this platform');
      return;
    }

    try {
      await _screenshotService.initialize();
      _screenshotService.addListener(_onScreenshotServiceChanged);

      // Update screenshot service with current user state
      final authService = Provider.of<AuthService>(context, listen: false);
      await _screenshotService.onUserAuthChanged(authService.currentUser);

      // Check for admin reset before starting monitoring
      await _screenshotService.checkForAdminReset();

      // Start monitoring when content is accessed
      await _screenshotService.startMonitoring();

      Logger.i('📱 Screenshot blocking service initialized successfully');
    } catch (error) {
      Logger.e('❌ Error initializing screenshot service: $error');
    }
  }

  /// Handle screenshot service state changes
  void _onScreenshotServiceChanged() {
    if (!mounted) return;

    Logger.i('📱 Screenshot service state changed');

    // Check if access was restored (admin reset) - only show once
    if (_screenshotService.shouldShowResetMessage) {
      _showAccessRestoredMessage();
    }

    // Check if we should show warning (first screenshot)
    if (_screenshotService.shouldShowWarning() && !_showingScreenshotWarning) {
      _showScreenshotWarning();
    }

    // Check if we should show screen recording warning
    if (_screenshotService.shouldShowScreenRecordingWarning && !_showingScreenRecordingWarning) {
      Logger.w('📱 Triggering screen recording warning dialog');
      _showScreenRecordingWarning();
    }

    // Check if access should be blocked (second screenshot)
    if (_screenshotService.shouldBlockAccess()) {
      _showScreenshotBlocked();
    }
  }

  /// Show screenshot warning screen
  void _showScreenshotWarning() {
    if (_showingScreenshotWarning) return;

    setState(() {
      _showingScreenshotWarning = true;
    });

    // Mark that we're showing the warning to prevent repeated displays
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
        transitionDuration: Duration(milliseconds: 150), // Faster transition
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Quick fade transition instead of default slide
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );
  }

  /// Show screenshot blocked screen
  void _showScreenshotBlocked() {
    Logger.e('📱 Showing screenshot blocked screen');

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const ScreenshotBlockedScreen(),
        transitionDuration: Duration(
          milliseconds: 100,
        ), // Even faster for blocking
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Instant fade transition for immediate blocking
          return FadeTransition(opacity: animation, child: child);
        },
        fullscreenDialog: true,
      ),
    );
  }

  /// Show screen recording warning dialog
  void _showScreenRecordingWarning() {
    if (_showingScreenRecordingWarning) return;

    setState(() {
      _showingScreenRecordingWarning = true;
    });

    Logger.w('📱 Showing screen recording warning dialog');

    showDialog(
      context: context,
      barrierDismissible: false, // Force user to acknowledge
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

  /// Show access restored message when admin resets violations
  void _showAccessRestoredMessage() {
    Logger.i('🎉 Showing access restored message');

    // Acknowledge that we're showing the message
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

  @override
  Widget build(BuildContext context) {
    // Check for screenshot blocking first (iOS only - Android uses FLAG_SECURE)
    if (ResponsiveHelper.isIOS() && _screenshotService.shouldBlockAccess()) {
      Logger.e('📱 Access blocked due to screenshot violations');
      return const ScreenshotBlockedScreen();
    }
    // Show error state
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    // Show content if access granted
    if (_hasAccess == true) {
      Logger.i('✅ Content access granted');

      // If background checks failed, show a non-intrusive refresh banner
      // over the content (content stays fully visible and usable)
      if (_showRefreshPrompt) {
        return Stack(
          children: [
            widget.child,
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: _buildRefreshPromptBanner(),
              ),
            ),
          ],
        );
      }

      return widget.child;
    }

    // Show loading state while checking access (regardless of showLoadingSpinner setting)
    if (_isLoading || _hasAccess == null) {
      return _buildLoadingState();
    }

    // Show subscription expired screen if access definitively denied
    if (_hasAccess == false) {
      Logger.w(
        '🚫 Content access denied - showing subscription expired screen',
      );

      // Navigate to subscription screen and listen for result (only if not already navigating)
      if (!_isNavigatingToSubscription) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigateToSubscriptionScreen();
        });
      }

      // Show loading while navigating
      return _buildLoadingState();
    }

    // Fallback to loading state (should not reach here)
    return _buildLoadingState();
  }

  Widget _buildLoadingState() {
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
                'Verifying access...',
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
              // Add some visual feedback that something is happening
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
                  // Clear any stale persistent data before redirecting
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
                onPressed: _checkAccess,
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
  final SubscriptionService _subscriptionService = SubscriptionService();

  /// Quick method to check if current user has course access
  Future<bool> validateCourseAccess(String courseId) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) return false;

      return await _subscriptionService.hasAccessToCourse(
        currentUser.uid,
        courseId,
      );
    } catch (error) {
      Logger.e('❌ Course access validation failed: $error');
      return false;
    }
  }

  /// Quick method to check if current user has active subscription
  Future<bool> validateSubscriptionStatus() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) return false;

      return await _subscriptionService.checkUserActiveSubscription(
        currentUser.uid,
      );
    } catch (error) {
      Logger.e('❌ Subscription status validation failed: $error');
      return false;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/screenshot_blocking_service.dart';
import '../screens/subscription_expired_screen.dart';
import '../screens/screenshot_warning_screen.dart';
import '../screens/screenshot_blocked_screen.dart';
import '../utils/logger.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeScreenshotService();
    _checkAccess();
  }

  @override
  void dispose() {
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
      _checkAccess(forceRefresh: true);
    }
  }

  @override
  void didUpdateWidget(ProtectedCourseContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check access if courseId changes
    if (oldWidget.courseId != widget.courseId) {
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) {
        Logger.w('🔐 No authenticated user for content access check');
        if (mounted) {
          setState(() {
            _hasAccess = false;
            _isLoading = false;
            _errorMessage = 'Please log in to access content';
          });
        }
        return;
      }

      // Add timeout to prevent hanging
      late Future<bool> accessCheckFuture;

      if (widget.courseId == null) {
        Logger.i(
          '🔍 Checking general subscription access for user ${currentUser.uid} (forceRefresh: $forceRefresh)',
        );
        accessCheckFuture = _subscriptionService.checkUserActiveSubscription(
          currentUser.uid,
          forceRefresh: forceRefresh,
        );
      } else {
        Logger.i(
          '🔐 Checking course access for ${widget.courseId} (forceRefresh: $forceRefresh)',
        );
        accessCheckFuture = _subscriptionService.hasAccessToCourse(
          currentUser.uid,
          widget.courseId!,
          forceRefresh: forceRefresh,
        );
      }

      // Apply timeout to prevent hanging
      final hasAccess = await accessCheckFuture.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          Logger.w(
            '🕒 Subscription check timed out - allowing access for better UX',
          );
          return true; // Allow access on timeout for better user experience
        },
      );

      if (mounted) {
        setState(() {
          _hasAccess = hasAccess;
          _isLoading = false;
        });
      }
    } catch (error) {
      Logger.e('❌ Error checking content access: $error');
      setState(() {
        _hasAccess = false;
        _isLoading = false;
        _errorMessage = 'Unable to verify access. Please try again.';
      });
    }
  }

  /// Initialize the screenshot blocking service
  Future<void> _initializeScreenshotService() async {
    // Only initialize on iOS
    if (!ResponsiveHelper.isIOS()) {
      Logger.i('📱 Screenshot blocking not available on this platform');
      return;
    }

    try {
      await _screenshotService.initialize();
      _screenshotService.addListener(_onScreenshotServiceChanged);

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

    // Check if we should show warning (first screenshot)
    if (_screenshotService.shouldShowWarning() && !_showingScreenshotWarning) {
      _showScreenshotWarning();
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

    Logger.w('📱 Showing screenshot warning screen');

    Navigator.of(context).push(
      MaterialPageRoute(
        builder:
            (context) => ScreenshotWarningScreen(
              onContinue: () {
                Navigator.of(context).pop();
                setState(() {
                  _showingScreenshotWarning = false;
                });
              },
              onGoBack: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Go back to previous screen
              },
            ),
        fullscreenDialog: true,
      ),
    );
  }

  /// Show screenshot blocked screen
  void _showScreenshotBlocked() {
    Logger.e('📱 Showing screenshot blocked screen');

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder:
            (context) => ScreenshotBlockedScreen(
              onGoBack: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check for screenshot blocking first (iOS only)
    if (ResponsiveHelper.isIOS() && _screenshotService.shouldBlockAccess()) {
      Logger.e('📱 Access blocked due to screenshot violations');
      return ScreenshotBlockedScreen(
        onGoBack: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      );
    }
    // Show error state
    if (_errorMessage != null) {
      return _buildErrorState();
    }

    // Show content if access granted
    if (_hasAccess == true) {
      Logger.i('✅ Content access granted');
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

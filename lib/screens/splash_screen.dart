import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../services/firestore_service.dart';
import '../services/subscription_service.dart';
import '../services/version_check_service.dart';
import '../utils/accessibility_helper.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'onboarding_screen.dart';
import 'force_update_screen.dart';
import 'profile_completion_screen.dart';
import '../services/notification_service.dart';
import '../services/first_time_user_service.dart';
import '../utils/exam_overview_navigator.dart';
import '../widgets/exam_overview_dialog.dart';
import '../main.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isNavigating = false;
  bool _hasNavigated = false; // Prevent duplicate navigation
  String _loadingText = "Loading...";

  // Debug flag to disable preloading if needed
  // TEMPORARILY DISABLED to fix app crash issue
  static const bool _enablePreloading = false;

  @override
  void initState() {
    super.initState();

    Logger.i("🔄 SplashScreen: initState called - Starting app initialization");

    // Configure status bar for splash screen
    _configureStatusBar();

    // Initialize fade animation
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut),
    );

    // Start the fade-in animation immediately
    _fadeController.forward();

    // CRITICAL: Defer ALL heavy async work to after first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger.i(
        "🎨 SplashScreen: Post-frame callback - UI rendered, starting async work",
      );
      _startAsyncInitialization();
    });
  }

  void _configureStatusBar() {
    // Configure status bar for splash screen
    if (ResponsiveHelper.isIOS()) {
      AccessibilityHelper.configureSystemUI(
        statusBarColor: const Color(0xFF1A237E),
        statusBarIconBrightness: Brightness.light,
      );
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Color(0xFF1A237E),
          statusBarIconBrightness: Brightness.light,
        ),
      );
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  /// Start all async initialization work AFTER the first frame is rendered
  Future<void> _startAsyncInitialization() async {
    // Ultimate failsafe - force navigation after maximum time
    Timer? timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_isNavigating) {
        Logger.w(
          "🚨 Ultimate failsafe triggered - forcing navigation to login",
        );
        _forceNavigateToLogin();
      }
    });

    try {
      // STEP 1: Initialize Firebase & Core Services
      if (mounted) {
        setState(() {
          _loadingText = "Initializing...";
        });
      }

      Logger.i("🔥 SplashScreen: Starting Firebase initialization");

      // Initialize Firebase with timeout
      bool firebaseReady = false;
      try {
        firebaseReady = await FirebaseInitHelper.ensureInitialized().timeout(
          const Duration(seconds: 8),
        );
      } catch (e) {
        Logger.e("Firebase initialization error in splash: $e");
        firebaseReady = false;
      }

      if (!mounted || _isNavigating) return;

      if (!firebaseReady) {
        Logger.w("Firebase initialization failed - navigating to login screen");
        if (mounted) {
          setState(() {
            _loadingText = "Connection failed. Continuing...";
          });
        }
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          _navigateToLogin();
        }
        return;
      }

      Logger.i("✅ Firebase initialized successfully in SplashScreen");

      // STEP 2: Initialize Notification Service
      if (mounted) {
        setState(() {
          _loadingText = "Setting up notifications...";
        });
      }

      try {
        // Register background message handler
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        Logger.i('📱 Background message handler registered');
        
        // Initialize notification service
        final notificationService = Provider.of<NotificationService>(context, listen: false);
        await notificationService.initialize();
        Logger.i('✅ NotificationService initialized - push notifications ready');
        
        // Store globally for app-wide access
        globalNotificationService = notificationService;
      } catch (e) {
        Logger.e("Notification service initialization error: $e");
        // Continue even if notifications fail
      }

      if (!mounted || _isNavigating) return;

      await Future.delayed(const Duration(milliseconds: 400));

      // STEP 3: Check app version
      if (mounted) {
        setState(() {
          _loadingText = "Checking for updates...";
        });
      }

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted || _isNavigating) return;

      // Check if app update is required
      final versionCheckService = VersionCheckService();
      bool updateRequired = false;
      
      try {
        updateRequired = await versionCheckService.isUpdateRequired().timeout(
          const Duration(seconds: 5),
        );
      } catch (e) {
        Logger.e("Error checking app version: $e");
        // On error, continue to app (don't block user)
        updateRequired = false;
      }

      if (!mounted || _isNavigating) return;

      if (updateRequired) {
        // Navigate to force update screen
        Logger.w("App update required - navigating to force update screen");
        _navigateToForceUpdate();
        return;
      }

      // Version is OK - check authentication
      if (mounted) {
        setState(() {
          _loadingText = "Checking authentication...";
        });
      }

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted || _isNavigating) return;

      // Check auth and navigate
      await _checkAuthAndNavigate();
    } finally {
      timeoutTimer.cancel();
    }
  }

  /// Force navigation to login screen for failsafe scenarios
  void _forceNavigateToLogin() {
    if (!mounted || _isNavigating) return;

    setState(() {
      _isNavigating = true;
    });

    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  /// Navigate to force update screen when app version is outdated
  void _navigateToForceUpdate() async {
    if (!mounted || _isNavigating || _hasNavigated) return;

    // Set navigation flag immediately to prevent duplicates
    _hasNavigated = true;

    setState(() {
      _isNavigating = true;
    });

    Logger.i("🔄 Navigating to force update screen...");

    // Get version information
    final versionCheckService = VersionCheckService();
    final currentVersion = await versionCheckService.getCurrentVersion();
    final versionInfo = await versionCheckService.getVersionInfo();
    final requiredVersion = versionInfo['minimumVersion'] as String? ?? 'Unknown';
    final updateMessage = versionInfo['updateMessage'] as String?;
    final apkDownloadPath = versionInfo['apkDownloadPath'] as String?;

    // Fade out before navigation
    await _fadeController.reverse();

    if (!mounted) return;

    // Force a frame to render before navigation
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ForceUpdateScreen(
          currentVersion: currentVersion,
          requiredVersion: requiredVersion,
          updateMessage: updateMessage,
          apkDownloadPath: apkDownloadPath,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _checkAuthAndNavigate() async {
    if (!mounted || _isNavigating) return;

    setState(() {
      _isNavigating = true;
    });

    try {
      // Get auth service - Firebase is now guaranteed to be initialized
      final authService = Provider.of<AuthService>(context, listen: false);

      // Check authentication state
      Logger.i("Checking authentication state...");

      // Check if we have persistent login data first
      bool hasPersistentLogin = await AuthPersistenceService.isLoggedIn();
      Logger.i("Persistent login status: $hasPersistentLogin");

      // Wait for Firebase Auth to confirm the session state
      // Use a timeout to prevent infinite waiting
      User? firebaseUser;
      try {
        Logger.i("Waiting for Firebase Auth state confirmation...");
        firebaseUser = await authService.authStateChanges.first.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            Logger.w("Firebase Auth state timeout - using current state");
            return authService.currentUser;
          },
        );
        Logger.i("Firebase Auth state confirmed: ${firebaseUser?.uid ?? 'null'}");
      } catch (e) {
        Logger.e("Error waiting for auth state: $e");
        firebaseUser = authService.currentUser;
      }

      if (!mounted) return;

      // Handle the authentication state
      if (firebaseUser != null) {
        // User is authenticated via Firebase
        Logger.i("User authenticated via Firebase Auth: ${firebaseUser.uid}");

        // Ensure persistent storage is in sync
        if (!hasPersistentLogin) {
          Logger.i("Syncing persistent storage with Firebase Auth state");
          String? token = await firebaseUser.getIdToken();
          if (token != null) {
            await AuthPersistenceService.saveAuthToken(token);
          }
        }

        // Check if profile is complete
        bool profileComplete = false;
        final userId = firebaseUser.uid;
        try {
          profileComplete = await authService.isProfileComplete();
          Logger.i("Profile completion status: $profileComplete");
        } catch (e) {
          Logger.e("Error checking profile completion: $e");
          // If error, assume profile is incomplete and let user fill it
          profileComplete = false;
        }

        if (!mounted) return;

        // Profile is complete — go straight to the main screen.
        // Exam overview is only for users who have NOT yet completed their profile.
        if (profileComplete) {
          // Setup user-specific notification handling
          if (mounted) {
            final notificationService = Provider.of<NotificationService>(
              context,
              listen: false,
            );
            notificationService.ensureTopicSubscriptions(userId);
            notificationService.refreshToken();
          }

          if (mounted) {
            _navigateToHome();
          }
          return;
        }

        // Profile is NOT complete — check if the exam overview has been watched.
        // The exam overview is a mandatory first-time orientation that users must
        // complete before filling out their profile.
        final firstTimeUserService = FirstTimeUserService();
        final hasWatchedExamOverview = await firstTimeUserService.hasWatchedExamOverview(userId);

        if (!hasWatchedExamOverview) {
          Logger.i("Profile incomplete & exam overview not watched - showing exam overview dialog");

          if (!mounted) return;

          // Show exam overview dialog
          await _showExamOverviewDialog();
          return;
        }

        // Exam overview already watched but profile still incomplete — go to profile completion
        Logger.i("Exam overview already watched - navigating to profile completion");
        _navigateToProfileCompletion();
        return;
      }

      // Firebase says no user, but we have persistent login data
      if (hasPersistentLogin) {
        Logger.w(
          "⚠️ Persistent login exists but Firebase Auth returned null - likely slow network or offline",
        );
        Logger.i("Trusting persistent login and proceeding to app (offline-first approach)");
        
        // DO NOT clear persistent data - Firebase Auth will sync in background
        // This allows the app to work offline or with slow connections
        
        if (!mounted) return;
        
        // Try to get cached user data
        try {
          final userData = await AuthPersistenceService.getUserData();
          if (userData != null) {
            Logger.i("Cached user data available: ${userData.displayName}");
          }
        } catch (e) {
          Logger.e("Error loading cached user data: $e");
        }
        
        if (!mounted) return;
        
        // Navigate to home screen - auth will sync in background
        _navigateToHome();
      } else {
        // No login detected anywhere, go to login screen
        Logger.i("No authentication detected - navigating to login");
        _navigateToLogin();
      }
    } catch (e) {
      Logger.e("Error during auth check: $e");
      if (mounted) {
        // On error, default to login screen
        _navigateToLogin();
      }
    }
  }

  /// Navigate to profile completion screen
  void _navigateToProfileCompletion() async {
    if (!mounted || !_isNavigating || _hasNavigated) return;

    // Set navigation flag immediately to prevent duplicates
    _hasNavigated = true;

    Logger.i("📝 Navigating to profile completion screen...");

    // Fade out before navigation
    await _fadeController.reverse();

    if (!mounted) return;

    // Force a frame to render before navigation
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ProfileCompletionScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _navigateToHome() async {
    if (!mounted || !_isNavigating || _hasNavigated) return;

    // Set navigation flag immediately to prevent duplicates
    _hasNavigated = true;

    Logger.i("🏠 Navigating to home screen...");

    // Try to preload essential data, but don't block navigation if it fails
    if (_enablePreloading) {
      try {
        await _preloadHomeData();
      } catch (e) {
        Logger.e(
          "🚨 Critical: Preload completely failed, proceeding with immediate navigation: $e",
        );
      }
    } else {
      Logger.i("⚠️ Preloading disabled - proceeding with immediate navigation");
    }

    // Fade out before navigation
    await _fadeController.reverse();

    if (!mounted) return;

    Logger.i("🏠 Performing navigation to MainScreen");

    // Force a frame to render before navigation (iOS Simulator fix)
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:
            (context, animation, secondaryAnimation) =>
                const MainScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  /// Show exam overview dialog to first-time users
  Future<void> _showExamOverviewDialog() async {
    if (!mounted) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    await showDialog(
      context: context,
      barrierDismissible: false, // User must click proceed
      builder: (dialogContext) => ExamOverviewDialog(
        onProceed: () async {
          Logger.i('📚 Navigating to Exam Overview from dialog');
          
          // Navigate to exam overview
          final success = await ExamOverviewNavigator.navigateToExamOverview(
            context,
            firestoreService,
          );
          
          if (!success) {
            Logger.e('Failed to navigate to exam overview');
            // If navigation fails, for now we'll just go to home
            // In production, you might want to retry or show an error
            if (mounted) {
              _navigateToHome();
            }
          }
        },
      ),
    );
  }

  void _navigateToLogin() async {
    if (!mounted || !_isNavigating || _hasNavigated) return;

    // Set navigation flag immediately to prevent duplicates
    _hasNavigated = true;

    Logger.i("🔐 Navigating to login/onboarding screen...");

    // Fade out before navigation
    await _fadeController.reverse();

    if (!mounted) return;

    // Check if onboarding has been completed
    final prefs = await SharedPreferences.getInstance();
    final bool onboardingComplete =
        prefs.getBool('onboarding_complete') ?? false;

    if (!mounted) return;

    Widget nextScreen;
    if (onboardingComplete) {
      // If onboarding is done, go to login screen
      Logger.i("🔐 Performing navigation to LoginScreen");
      nextScreen = const LoginScreen();
    } else {
      // If onboarding is not done, go to onboarding screen
      Logger.i("📖 Performing navigation to OnboardingScreen");
      nextScreen = const OnboardingScreen();
    }

    // Force a frame to render before navigation (iOS cold start fix)
    await Future.delayed(const Duration(milliseconds: 100));

    // Additional iOS-specific pre-warming for OnboardingScreen
    if (ResponsiveHelper.isIOS() && nextScreen is OnboardingScreen) {
      // Force system UI update before OnboardingScreen loads
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.white,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Future<void> _preloadHomeData() async {
    if (!mounted) return;

    // Skip preloading if disabled
    if (!_enablePreloading) {
      Logger.i("📋 Preloading disabled - skipping data preload");
      return;
    }

    try {
      // Add timeout protection to prevent app hanging
      await _performPreload().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          Logger.w("⏰ Preload timeout reached - continuing without preload");
          // Don't throw exception - just return
          return;
        },
      );
    } catch (e) {
      Logger.e("❌ Error preloading home data: $e");
      // Always continue navigation - don't let preload block the app
      if (mounted) {
        setState(() {
          _loadingText = "Loading...";
        });
      }
    }
  }

  Future<void> _performPreload() async {
    if (!mounted) return;

    setState(() {
      _loadingText = "Loading your courses...";
    });

    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
    final subscriptionService = Provider.of<SubscriptionService>(
      context,
      listen: false,
    );

    Logger.i("🔄 SplashScreen: Starting preload with timeout protection...");

    // Check if user is logged in before attempting preload
    if (authService.currentUser == null) {
      Logger.w("⚠️ No current user - skipping preload");
      return;
    }

    // Preload assigned course IDs with individual timeout
    try {
      final assignedCourseIds = await authService
          .getAssignedCourseIds()
          .timeout(const Duration(seconds: 3));
      Logger.i("📚 Preloaded assigned course IDs: $assignedCourseIds");

      if (!mounted) return;

      setState(() {
        _loadingText = "Loading user data...";
      });

      // Preload user data with timeout
      final user = await authService.getUserData().timeout(
        const Duration(seconds: 3),
      );
      Logger.i("👤 Preloaded user data: ${user?.displayName} (${user?.email})");

      if (!mounted) return;

      setState(() {
        _loadingText = "Checking subscription...";
      });

      // Preload subscription data with timeout
      final userId = authService.currentUser?.uid;
      if (userId != null) {
        await subscriptionService
            .checkUserActiveSubscription(userId)
            .timeout(const Duration(seconds: 3));
        Logger.i("🔍 Preloaded subscription data");
      }

      if (!mounted) return;

      setState(() {
        _loadingText = "Loading courses...";
      });

      // Preload course data if there are assigned courses
      if (assignedCourseIds.isNotEmpty) {
        await firestoreService
            .getAssignedCourses(assignedCourseIds)
            .timeout(const Duration(seconds: 3));
        Logger.i("📋 Preloaded course data");
      }

      Logger.i("✅ SplashScreen: All home data preloaded successfully");

      if (mounted) {
        setState(() {
          _loadingText = "Ready!";
        });

        // Small delay to show "Ready!" message
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      Logger.w("⚠️ Individual preload operation failed: $e - continuing...");
      // Don't rethrow - let the app continue
    }
  }

  @override
  Widget build(BuildContext context) {
    // CRITICAL: Build method must return UI immediately without any async work
    // All heavy initialization is deferred to post-frame callback in initState

    return Scaffold(
      backgroundColor: const Color(0xFF1A237E), // Deep blue background
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Color(0xFF1A237E),
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1A237E), // Deep blue
              Color(0xFF3F51B5), // Slightly lighter blue
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Logo/Text - matches native splash branding
                  Text(
                    'XFINI',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: ResponsiveHelper.adaptiveFontSize(
                        context,
                        48.0,
                      ),
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 2.0,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 2),
                          blurRadius: 4,
                          color: Colors.black.withValues(alpha: 0.3),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    height: ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 16.0,
                      regular: 20.0,
                      pro: 24.0,
                      large: 28.0,
                      extraLarge: 32.0,
                    ),
                  ),

                  // Subtitle - enhanced for better readability
                  Text(
                    'Academy',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: ResponsiveHelper.adaptiveFontSize(
                        context,
                        18.0,
                      ),
                      fontWeight: FontWeight.w400,
                      color: Colors.white.withValues(alpha: 0.95),
                      letterSpacing: 1.5,
                      shadows: [
                        Shadow(
                          offset: const Offset(0, 1),
                          blurRadius: 2,
                          color: Colors.black.withValues(alpha: 0.2),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    height: ResponsiveHelper.getAdaptiveSpacing(
                      context,
                      compact: 40.0,
                      regular: 50.0,
                      pro: 55.0,
                      large: 60.0,
                      extraLarge: 70.0,
                    ),
                  ),

                  // Loading indicator
                  if (!_isNavigating)
                    Column(
                      children: [
                        SizedBox(
                          width: ResponsiveHelper.adaptiveFontSize(
                            context,
                            32.0,
                          ),
                          height: ResponsiveHelper.adaptiveFontSize(
                            context,
                            32.0,
                          ),
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withValues(alpha: 0.8),
                            ),
                            strokeWidth: 3.0,
                          ),
                        ),

                        SizedBox(
                          height: ResponsiveHelper.getAdaptiveSpacing(
                            context,
                            compact: 16.0,
                            regular: 20.0,
                            pro: 24.0,
                            large: 28.0,
                            extraLarge: 32.0,
                          ),
                        ),

                        // Loading text - enhanced visibility
                        Text(
                          _loadingText,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: ResponsiveHelper.adaptiveFontSize(
                              context,
                              14.0,
                            ),
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.9),
                            letterSpacing: 0.5,
                            shadows: [
                              Shadow(
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                                color: Colors.black.withValues(alpha: 0.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/auth_persistence_service.dart';
import '../services/firestore_service.dart';
import '../services/subscription_service.dart';
import '../providers/session_provider.dart';
import '../services/version_check_service.dart';
import '../utils/accessibility_helper.dart';
import '../utils/app_colors.dart';
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
    // Configure status bar for the new light-surface splash design
    if (ResponsiveHelper.isIOS()) {
      AccessibilityHelper.configureSystemUI(
        statusBarColor: AppColors.surface,
        statusBarIconBrightness: Brightness.dark,
      );
    } else {
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: AppColors.surface,
          statusBarIconBrightness: Brightness.dark,
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
    // CRITICAL: Check _hasNavigated (not _isNavigating) because _isNavigating
    // is set true early inside _checkAuthAndNavigate(), before the Firestore
    // calls that can actually hang. Using _isNavigating would make this
    // failsafe completely ineffective.
    Timer? timeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_hasNavigated) {
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

      if (!mounted || _hasNavigated) return;

      if (!firebaseReady) {
        Logger.w("Firebase initialization failed - navigating to login screen");
        if (mounted) {
          setState(() {
            _loadingText = "Connection failed. Continuing...";
          });
        }
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && !_hasNavigated) {
          // Use _forceNavigateToLogin because _isNavigating is still false
          // at this point — _navigateToLogin() would silently bail out.
          _forceNavigateToLogin();
        }
        return;
      }

      Logger.i("✅ Firebase initialized successfully in SplashScreen");

      // STEP 2: Notification Service (fire-and-forget — not on critical path)
      // Register background handler synchronously, then kick off init in
      // the background. The user reaches login/home without waiting for
      // notification setup. This structurally prevents the entire class of
      // "notification init hangs splash" bugs (e.g. OPPO/ColorOS permission
      // dialogs, cleanupTokens() Firestore stalls).
      try {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
        Logger.i('📱 Background message handler registered');
      } catch (e) {
        Logger.e("Background message handler registration error: $e");
      }

      // CRITICAL: Check mounted before accessing context after the async gap
      // from Firebase init. If widget was disposed (e.g. user killed app
      // during init), Provider.of would throw "deactivated widget ancestor".
      if (!mounted || _hasNavigated) return;

      try {
        final notificationService = Provider.of<NotificationService>(context, listen: false);
        globalNotificationService = notificationService;

        // Fire-and-forget: initialize in background with its own internal
        // timeouts, concurrency guards, and granular status tracking.
        notificationService.initialize().then((_) {
          Logger.i('✅ NotificationService initialized in background');
        }).catchError((e) {
          Logger.e('Notification service background init failed: $e');
        });
      } catch (e) {
        Logger.e("Notification service setup error: $e");
      }

      if (!mounted || _hasNavigated) return;


      // STEP 3: Check app version
      if (mounted) {
        setState(() {
          _loadingText = "Checking for updates...";
        });
      }

      await Future.delayed(const Duration(milliseconds: 400));

      if (!mounted || _hasNavigated) return;

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

      if (!mounted || _hasNavigated) return;

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

      if (!mounted || _hasNavigated) return;

      // Check auth and navigate
      await _checkAuthAndNavigate();
    } finally {
      timeoutTimer.cancel();
    }
  }

  /// Force navigation to login screen for failsafe scenarios.
  /// This is the "nuclear option" — bypasses all checks and navigates
  /// immediately. Only _hasNavigated is checked to prevent double-push.
  void _forceNavigateToLogin() {
    if (!mounted || _hasNavigated) return;

    _hasNavigated = true;
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

    // Get version information — with timeouts since _hasNavigated is
    // already true and no failsafe can save us if these hang.
    String currentVersion = '0.0.0';
    String requiredVersion = 'Unknown';
    String? updateMessage;
    String? apkDownloadPath;

    try {
      final versionCheckService = VersionCheckService();
      currentVersion = await versionCheckService.getCurrentVersion().timeout(
        const Duration(seconds: 3),
      );
      final versionInfo = await versionCheckService.getVersionInfo().timeout(
        const Duration(seconds: 5),
      );
      requiredVersion = versionInfo['minimumVersion'] as String? ?? 'Unknown';
      updateMessage = versionInfo['updateMessage'] as String?;
      apkDownloadPath = versionInfo['apkDownloadPath'] as String?;
    } catch (e) {
      Logger.e("Error fetching version details (non-fatal): $e");
      // Continue with defaults — the update screen will still show
    }

    // Fade out before navigation
    if (mounted) {
      try {
        await _fadeController.reverse();
      } catch (_) {
        // AnimationController may already be disposed
      }
    }

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

    // Inner failsafe: if _checkAuthAndNavigate itself takes too long
    // (e.g. a Firestore .get() hangs), force-navigate to login.
    // The outer 15-second timer may have already fired, but this is
    // belt-and-suspenders — both check _hasNavigated.
    Timer? innerTimeout = Timer(const Duration(seconds: 10), () {
      if (mounted && !_hasNavigated) {
        Logger.w("🚨 Auth-check inner timeout — forcing navigation to login");
        _forceNavigateToLogin();
      }
    });

    try {
      // Get auth service - Firebase is now guaranteed to be initialized
      final authService = Provider.of<AuthService>(context, listen: false);

      // Check authentication state
      Logger.i("Checking authentication state...");

      // Check if we have persistent login data first
      bool hasPersistentLogin = await AuthPersistenceService.isLoggedIn();
      Logger.i("Persistent login status: $hasPersistentLogin");

      // Wait for Firebase Auth to confirm the session state.
      // IMPORTANT: AuthService is provided lazily, so its async _initializeServices()
      // may not have completed by the time we read authStateChanges. Read from
      // FirebaseAuth.instance directly — it's guaranteed initialized at this point
      // (splash STEP 1 awaited FirebaseInitHelper.ensureInitialized()) and bypasses
      // any AuthService availability-flag race.
      User? firebaseUser;
      try {
        Logger.i("Waiting for Firebase Auth state confirmation...");
        firebaseUser = await FirebaseAuth.instance.authStateChanges().first.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            Logger.w("Firebase Auth state timeout - using current state");
            return FirebaseAuth.instance.currentUser;
          },
        );
        Logger.i("Firebase Auth state confirmed: ${firebaseUser?.uid ?? 'null'}");
      } catch (e) {
        Logger.e("Error waiting for auth state: $e");
        firebaseUser = FirebaseAuth.instance.currentUser;
      }

      if (!mounted || _hasNavigated) { innerTimeout.cancel(); return; }

      // Handle the authentication state
      if (firebaseUser != null) {
        // User is authenticated via Firebase
        Logger.i("User authenticated via Firebase Auth: ${firebaseUser.uid}");

        // Ensure persistent storage is in sync (with timeout)
        if (!hasPersistentLogin) {
          Logger.i("Syncing persistent storage with Firebase Auth state");
          try {
            String? token = await firebaseUser.getIdToken().timeout(
              const Duration(seconds: 5),
            );
            if (token != null) {
              await AuthPersistenceService.saveAuthToken(token);
            }
          } catch (e) {
            Logger.e("Error syncing persistent storage (non-fatal): $e");
            // Continue — token sync failure shouldn't block navigation
          }
        }

        if (!mounted || _hasNavigated) { innerTimeout.cancel(); return; }

        // Check if profile is complete (with timeout to prevent hang
        // on devices where Firestore .get() stalls, e.g. OPPO/Realme
        // with aggressive battery management)
        bool profileComplete = false;
        final userId = firebaseUser.uid;
        try {
          profileComplete = await authService.isProfileComplete().timeout(
            const Duration(seconds: 5),
            onTimeout: () {
              Logger.w("isProfileComplete timeout — assuming complete to avoid blocking");
              return true; // Assume complete so user can get into the app
            },
          );
          Logger.i("Profile completion status: $profileComplete");
        } catch (e) {
          Logger.e("Error checking profile completion: $e");
          // If error, assume profile is complete to let user into the app
          // rather than blocking them on an error screen
          profileComplete = true;
        }

        if (!mounted || _hasNavigated) { innerTimeout.cancel(); return; }

        // Profile is complete — go straight to the main screen.
        // Exam overview is only for users who have NOT yet completed their profile.
        if (profileComplete) {
          // Setup user-specific notification handling
          if (mounted) {
            try {
              final notificationService = Provider.of<NotificationService>(
                context,
                listen: false,
              );
              notificationService.ensureTopicSubscriptions(userId);
              notificationService.refreshToken();
            } catch (e) {
              Logger.e("Error setting up notifications (non-fatal): $e");
            }
          }

          // Initialize session provider with the authenticated user
          if (mounted) {
            try {
              Logger.w("🔧 DIAG: About to call sessionProvider.initialize($userId)");
              final sessionProvider = Provider.of<SessionProvider>(
                context,
                listen: false,
              );
              Logger.w("🔧 DIAG: SessionProvider obtained — hasCheckedOnce=${sessionProvider.hasCheckedOnce}, hasActive=${sessionProvider.hasActiveSubscription}");
              await sessionProvider.initialize(userId);
              Logger.w("🔧 DIAG: initialize() COMPLETED — hasCheckedOnce=${sessionProvider.hasCheckedOnce}, hasActive=${sessionProvider.hasActiveSubscription}");
            } catch (e) {
              Logger.e("🔧 DIAG: initialize() THREW: $e");
            }
          } else {
            Logger.w("🔧 DIAG: NOT mounted before initialize — skipped!");
          }

          if (mounted && !_hasNavigated) {
            final sessionProvider = Provider.of<SessionProvider>(
              context,
              listen: false,
            );
            Logger.w("🔧 DIAG: About to navigate home — hasCheckedOnce=${sessionProvider.hasCheckedOnce}, hasActive=${sessionProvider.hasActiveSubscription}, gen=${sessionProvider.dataGeneration}");
            innerTimeout.cancel();
            _navigateToHome();
          } else {
            Logger.w("🔧 DIAG: Skipping _navigateToHome — mounted=$mounted, _hasNavigated=$_hasNavigated");
          }
          return;
        }

        // Profile is NOT complete — check if the exam overview has been watched.
        // The exam overview is a mandatory first-time orientation that users must
        // complete before filling out their profile.
        final firstTimeUserService = FirstTimeUserService();
        bool hasWatchedExamOverview = false;
        try {
          hasWatchedExamOverview = await firstTimeUserService
              .hasWatchedExamOverview(userId)
              .timeout(const Duration(seconds: 3));
        } catch (e) {
          Logger.e("Error checking exam overview status: $e");
          // Default to true on error so user isn't stuck
          hasWatchedExamOverview = true;
        }

        if (!mounted || _hasNavigated) { innerTimeout.cancel(); return; }

        if (!hasWatchedExamOverview) {
          Logger.i("Profile incomplete & exam overview not watched - showing exam overview dialog");

          if (!mounted) { innerTimeout.cancel(); return; }

          // Show exam overview dialog
          innerTimeout.cancel();
          await _showExamOverviewDialog();
          return;
        }

        // Exam overview already watched but profile still incomplete — go to profile completion
        Logger.i("Exam overview already watched - navigating to profile completion");
        innerTimeout.cancel();
        _navigateToProfileCompletion();
        return;
      }

      // Firebase says no user, but we have persistent login data
      if (hasPersistentLogin) {
        Logger.w(
          "⚠️ Persistent login exists but Firebase Auth returned null",
        );
        
        // This typically happens when the user uninstalled the old app while
        // logged in and installed a new APK.  Android auto-backup may restore
        // SharedPreferences (containing the old auth_token) but Firebase Auth
        // does NOT restore its session from backup.  Trusting the stale token
        // would send the user to the home screen where every screen shows
        // "Please log in" with no way to actually log in.
        //
        // Fix: clear the orphaned persistent data and send the user to login.
        Logger.w("Clearing stale persistent login data and redirecting to login");
        await AuthPersistenceService.clearAll();
        
        if (!mounted || _hasNavigated) { innerTimeout.cancel(); return; }
        
        innerTimeout.cancel();
        _navigateToLogin();
      } else {
        // No login detected anywhere, go to login screen
        Logger.i("No authentication detected - navigating to login");
        innerTimeout.cancel();
        _navigateToLogin();
      }
    } catch (e) {
      Logger.e("Error during auth check: $e");
      innerTimeout.cancel();
      if (mounted && !_hasNavigated) {
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
    try {
      await _fadeController.reverse();
    } catch (_) {
      // AnimationController may already be disposed if failsafe fired
    }

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
    try {
      await _fadeController.reverse();
    } catch (_) {
      // AnimationController may already be disposed if failsafe fired
    }

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

    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    await showDialog(
      context: context,
      barrierDismissible: false, // User must click proceed
      builder: (dialogContext) => ExamOverviewDialog(
        onProceed: () async {
          Logger.i('📚 Navigating to Exam Overview from dialog');
          
          // Navigate to exam overview with timeout protection.
          // ExamOverviewNavigator calls firestoreService.getCourses()
          // which is an unbounded Firestore call — if it hangs, user
          // is stuck in a non-dismissible dialog with no escape.
          bool success = false;
          try {
            success = await ExamOverviewNavigator.navigateToExamOverview(
              context,
              firestoreService,
            ).timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                Logger.w('⏰ Exam overview navigation timed out');
                return false;
              },
            );
          } catch (e) {
            Logger.e('Error navigating to exam overview: $e');
            success = false;
          }
          
          if (!success) {
            Logger.e('Failed to navigate to exam overview — going to home');
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
    try {
      await _fadeController.reverse();
    } catch (_) {
      // AnimationController may already be disposed if failsafe fired
    }

    if (!mounted) return;

    // Check if onboarding has been completed (with timeout — SharedPrefs
    // can hang if Android's storage is in a bad state after a force-kill).
    bool onboardingComplete = false;
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(seconds: 3),
      );
      onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
    } catch (e) {
      Logger.e('Error reading onboarding status (non-fatal): $e');
      // Default to true (skip onboarding) to avoid blocking the user
      onboardingComplete = true;
    }

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
      backgroundColor: AppColors.surface,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: AppColors.surface,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.surface,
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── Top: Accreditation status ──────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.secondary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),

                  // ── Center: Brand identity ────────────────────────
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo circle
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainerLowest,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Image.asset(
                          'assets/logo.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.school_rounded,
                            size: 48,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // App title
                      Text(
                        'APTITUDE 4 US',
                        style: GoogleFonts.inter(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: AppColors.primary,
                          height: 32 / 24,
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Subtitle
                      Text(
                        'Nursing Education & Exam Preparation',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: AppColors.onSurfaceVariant,
                          height: 20 / 14,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Progress indicator
                      if (!_isNavigating)
                        Column(
                          children: [
                            SizedBox(
                              width: 180,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  minHeight: 4,
                                  backgroundColor: AppColors.surfaceContainer,
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.secondary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _loadingText,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AppColors.onSurfaceVariant,
                                height: 18 / 12,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),

                  // ── Footer: Version & Copyright ───────────────────
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'v1.2.4',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurfaceVariant,
                              letterSpacing: 0.33,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              '•',
                              style: TextStyle(
                                color: AppColors.outlineVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Text(
                            'Aptitude 4 Us',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.onSurfaceVariant,
                              letterSpacing: 0.33,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '© 2024 Aptitude 4 Us. All rights reserved.',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.outline,
                          height: 18 / 12,
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


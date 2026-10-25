import 'dart:async'; // Add this for StreamSubscription
import 'dart:io' show Platform;

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'; // Add for SystemChrome
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/main_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/profile_completion_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'services/subscription_service.dart';
import 'providers/session_provider.dart';
import 'utils/accessibility_helper.dart';
import 'utils/adaptive_navigation.dart';
import 'utils/app_colors.dart';
import 'utils/app_info.dart';
import 'utils/app_theme.dart';
import 'utils/global_keys.dart';
import 'utils/logger.dart';
import 'utils/text_scale_calculator.dart';

// Global notification service instance for universal push notifications
// Public so it can be accessed from splash screen
NotificationService? globalNotificationService;

// Background message handler - MUST be top-level function
// Public so it can be registered from splash screen
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();

  // Using debugPrint in background handlers because Logger might not be accessible
  debugPrint('🔔 Background notification received: ${message.messageId}');
  debugPrint('📋 Background message data: ${message.data}');


  // Handle regular chat messages in background
  String title = message.notification?.title ?? 'New Message';
  String body = message.notification?.body ?? '';

  // For data-only messages, use data fields
  if (title == 'New Message' && message.data.containsKey('title')) {
    title = message.data['title'] ?? title;
  }
  if (body.isEmpty && message.data.containsKey('body')) {
    body = message.data['body'] ?? '';
  }

  // Determine the correct notification channel based on message type
  String channelKey = 'general_channel'; // default
  String? messageType = message.data['type'];
  if (messageType == 'chat' || messageType == 'direct_chat') {
    channelKey = 'chat_channel';
  } else if (messageType == 'community_chat') {
    channelKey = 'community_channel';
  } else if (messageType == 'past_questions') {
    channelKey = 'past_questions_channel';
  } else if (messageType == 'content_update' || messageType == 'content_item_update' || messageType == 'course_assignment' || messageType == 'consolidated_course_assignment') {
    channelKey = 'general_channel';
  }

  // Create notification with correct channel
  try {
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: channelKey,
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
        payload: Map<String, String>.from(message.data),
        category: NotificationCategory.Message,
        wakeUpScreen: true,
        criticalAlert: false,
      ),
    );
    debugPrint('✅ Background chat notification created');
  } catch (e) {
    debugPrint('❌ Error creating background chat notification: $e');
  }
}

// Firebase initialization state manager
class FirebaseInitState {
  static bool isInitialized = false;
  static bool isInitializing = false;
  static String? initializationError;
  static Completer<bool>? _initCompleter;
}

// Global flag to prevent infinite rebuild loop
class AppRebuildState {
  static bool _hasTriggeredIOSFix = false;
}

class FirebaseInitHelper {
  static Future<bool> ensureInitialized() async {
    if (FirebaseInitState.isInitialized) return true;

    if (FirebaseInitState.isInitializing &&
        FirebaseInitState._initCompleter != null) {
      return await FirebaseInitState._initCompleter!.future;
    }

    FirebaseInitState.isInitializing = true;
    FirebaseInitState._initCompleter = Completer<bool>();
    FirebaseInitState.initializationError = null;

    try {
      Logger.i("🔥 Starting Firebase initialization...");

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Test Firebase Storage connection
      try {
        final storage = FirebaseStorage.instance;
        Logger.i("Firebase Storage initialized: ${storage.bucket}");
      } catch (e) {
        Logger.w("Firebase Storage warning: $e");
      }

      FirebaseInitState.isInitialized = true;
      FirebaseInitState.isInitializing = false;
      Logger.i("✅ Firebase initialization completed");

      FirebaseInitState._initCompleter!.complete(true);
      return true;
    } catch (e) {
      FirebaseInitState.isInitialized = false;
      FirebaseInitState.isInitializing = false;
      FirebaseInitState.initializationError = e.toString();
      Logger.e("❌ Firebase initialization failed: $e");

      FirebaseInitState._initCompleter!.complete(false);
      return false;
    }
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure immediate UI to prevent white screen
  await _configureImmediateUI();

  Logger.i('🚀 Starting Xfini Academy app...');
  
  // Configure system UI properties for iPhone 11+ compatibility
  final Brightness statusBarIconBrightness =
      Platform.isIOS ? Brightness.light : Brightness.light;
  final Brightness navBarIconBrightness =
      Platform.isIOS ? Brightness.dark : Brightness.light;

  AccessibilityHelper.configureSystemUI(
    statusBarColor: Platform.isIOS ? AppColors.primary : Colors.transparent,
    statusBarIconBrightness: statusBarIconBrightness,
    navigationBarColor: Platform.isIOS ? null : Colors.white,
    navigationBarIconBrightness: navBarIconBrightness,
  );

  // Start app immediately - all initialization moved to SplashScreen
  runApp(
    MultiProvider(
      providers: [
        // Create singleton instances to prevent recreation
        Provider<AuthService>(create: (_) => AuthService(), lazy: true),
        Provider<FirestoreService>(
          create: (_) => FirestoreService(),
          lazy: true,
        ),
        Provider<StorageService>(create: (_) => StorageService(), lazy: true),
        Provider<NotificationService>(
          create: (_) => globalNotificationService ?? NotificationService(),
          lazy: true, // Lazy - will initialize in SplashScreen
        ),
        ChangeNotifierProvider<SessionProvider>(
          create: (_) => SessionProvider(),
        ),
      ],
      child: const MyApp(),
    ),
  );

  // Permissions are now handled by NotificationService during initialization
  // This prevents premature permission requests that interfere with proper plugin setup
}

Future<void> _configureImmediateUI() async {
  // Set app to show immediately with branded color to prevent white flash
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF1A237E), // Xfini brand color
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF1A237E),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  // Pre-configure the status bar for splash screen to avoid flicker
  if (Platform.isIOS) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white, // Use white for better transitions
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
    );
  } else {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white, // Use white for better transitions
        statusBarIconBrightness: Brightness.dark,
      ),
    );
  }

  // Set preferred orientations (allow landscape for video playback)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Force immediate UI update for iOS
  if (Platform.isIOS) {
    await Future.delayed(const Duration(milliseconds: 50));
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<User?>? _tokenChangesSubscription;

  /// Monotonic stopwatch for debouncing device validation on resume.
  /// Using Stopwatch instead of DateTime.now() to avoid system clock manipulation.
  final Stopwatch _validationDebounceWatch = Stopwatch();
  static const Duration _validationDebounceInterval = Duration(seconds: 60);

  @override
  void initState() {
    super.initState();

    Logger.i("🚀 MyApp: initState called - Starting main app initialization");

    // Register for lifecycle events
    WidgetsBinding.instance.addObserver(this);

    // We'll initialize the token change listener in the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger.i("🔧 MyApp: Post-frame callback - Setting up app services");
      _setupTokenChangeListener();

      // Token cleanup will be handled by the NotificationService when it's lazily created
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    Logger.i('App lifecycle state changed to: $state');

    // ✅ Notify notification service of lifecycle changes (including badge clearing)
    if (globalNotificationService != null) {
      globalNotificationService!.handleAppLifecycleChange(state);
    }

    // Reset system UI when app is resumed to handle different device behaviors
    if (state == AppLifecycleState.resumed) {
      // Use ResponsiveHelper after first frame to get proper MediaQuery context
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = globalNavigatorKey.currentContext;
        if (context != null) {
          final statusBarIconBrightness =
              Platform.isIOS ? Brightness.light : Brightness.light;

          AccessibilityHelper.configureSystemUI(
            statusBarColor:
                Platform.isIOS ? AppColors.primary : Colors.transparent,
            statusBarIconBrightness: statusBarIconBrightness,
          );

          // Validate device when app resumes (debounced security check)
          _validateDeviceOnResume(context);
        }
      });
    }
  }

  // Debounced device validation on app resume.
  // Skips validation if the last successful validation was < 60 seconds ago
  // to prevent repeated Cloud Function calls during rapid app switching.
  void _validateDeviceOnResume(BuildContext context) async {
    // Debounce: skip if last validation was recent
    if (_validationDebounceWatch.isRunning &&
        _validationDebounceWatch.elapsed < _validationDebounceInterval) {
      Logger.d("🔒 Skipping device validation — debounced (${_validationDebounceWatch.elapsed.inSeconds}s since last)");
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Only validate if user is logged in
      if (authService.isUserLoggedIn) {
        Logger.i("🔒 Validating device on app resume");
        
        bool isValid = await authService.validateCurrentDevice();
        
        // Reset debounce timer after validation completes (success or not)
        _validationDebounceWatch.reset();
        _validationDebounceWatch.start();
        
        if (!isValid) {
          Logger.w("⚠️ Device validation failed on resume — device not authorised");
          // Log but don't show UI or sign out — the Cloud Function
          // rejection is already logged and the admin can investigate.
          // Aggressive logout was previously disabled due to regression.
        } else {
          Logger.i("✅ Device validation successful on resume");
        }
      }
    } catch (e) {
      Logger.e("Error validating device on resume: $e");
      // Continue silently to avoid disrupting user experience
    }
  }

  void _setupTokenChangeListener() {
    if (!FirebaseInitState.isInitialized) return;

    // Token change listener will be set up by AuthService when it's lazily created
    Logger.i(
      "Token change listener setup deferred to lazy AuthService creation",
    );
  }

  @override
  void dispose() {
    // Unregister from lifecycle events
    WidgetsBinding.instance.removeObserver(this);

    // Clean up the subscription
    _tokenChangesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // NOTE: AuthService, FirestoreService, StorageService and NotificationService
    // are already provided as singletons by the outer MultiProvider in `main()`.
    // Only SubscriptionService is added here. Using `update: (_, previous) => previous!`
    // ensures the same instance is preserved across rebuilds (ProxyProvider0 fires
    // `update` on every rebuild, which would otherwise discard the existing instance
    // and break in-flight listeners / static-cache references).
    return MultiProvider(
      providers: [
        ProxyProvider0<SubscriptionService>(
          lazy: true,
          create: (_) => SubscriptionService(),
          update: (_, previous) => previous ?? SubscriptionService(),
        ),
      ],
      child: MaterialApp(
        navigatorKey: globalNavigatorKey,
        title: AppInfo.appName,
        debugShowCheckedModeBanner: false,
        // Add background color to prevent white screen
        color: const Color(0xFF1A237E), // Primary color background
        // Add builder for handling text scaling and other accessibility features
        builder: (context, child) {
          // Force visual update for iOS on first frame to prevent white screen
          WidgetsBinding.instance.addPostFrameCallback((_) {
            WidgetsBinding.instance.ensureVisualUpdate();

            // Additional iOS-specific fix for cold start white screen - ONE TIME ONLY
            if (Platform.isIOS && !AppRebuildState._hasTriggeredIOSFix) {
              AppRebuildState._hasTriggeredIOSFix = true;
              Future.delayed(const Duration(milliseconds: 100), () {
                if (context.mounted) {
                  (context as Element).markNeedsBuild();
                }
              });
            }
          });

          // Apply a maximum text scale factor to prevent layout issues
          return TextScaleCalculator.wrapWithConstrainedTextScale(
            context: context,
            child: child!,
          );
        },
        // Use platform-specific theme
        theme: AppTheme.getAppTheme(context),
        // Force SplashScreen to render immediately
        home: Container(
          color: const Color(0xFF1A237E), // Immediate background
          child: const SplashScreen(),
        ),
        // Add fallback route with smooth transitions
        onUnknownRoute: (settings) {
          // Use the same platform-specific route creation as AdaptiveNavigation
          if (Platform.isIOS) {
            return CupertinoPageRoute(
              builder: (_) => const MainScreen(),
              settings: settings,
            );
          } else {
            return PageRouteBuilder(
              settings: settings,
              pageBuilder: (context, animation, secondaryAnimation) => const MainScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                const begin = Offset(1.0, 0.0);
                const end = Offset.zero;
                const curve = Curves.easeOutQuad;
                var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                return SlideTransition(
                  position: animation.drive(tween),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
            );
          }
        },
        // Define routes for navigation from notifications
        routes: {
          '/chat': (context) => ChatScreen(),
          '/settings': (context) => const SettingsScreen(),
          '/profile-completion': (context) => const ProfileCompletionScreen(),
        },
      ),
    );
  }
}

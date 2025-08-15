import 'dart:async'; // Add this for StreamSubscription
import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Add for SystemChrome
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/assigned_courses_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';
import 'services/subscription_service.dart';
import 'utils/accessibility_helper.dart';
import 'utils/app_colors.dart';
import 'utils/app_info.dart';
import 'utils/app_theme.dart';
import 'utils/global_keys.dart';
import 'utils/logger.dart';
import 'utils/text_scale_calculator.dart';

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

  // Start app - Firebase initialization happens in splash screen
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
          create: (_) => NotificationService(),
          lazy: true,
        ),
      ],
      child: const MyApp(),
    ),
  );

  // Request permissions in background
  _requestPermissions();
}

Future<void> _configureImmediateUI() async {
  // Set app to show immediately with branded color to prevent white flash
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF1A237E), // Briffini brand color
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

Future<void> _requestPermissions() async {
  if (await Permission.storage.status.isDenied) {
    await Permission.storage.request();
  }

  // Add notifications permission request for iOS
  if (Platform.isIOS) {
    if (await Permission.notification.status.isDenied) {
      await Permission.notification.request();
    }
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  StreamSubscription<User?>? _tokenChangesSubscription;

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

    // App lifecycle changes will be handled by individual services when they're accessed

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
        }
      });
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
    return MultiProvider(
      providers: [
        ProxyProvider0<AuthService>(
          lazy: true,
          create: (_) => AuthService(),
          update: (_, __) => AuthService(),
        ),
        ProxyProvider0<FirestoreService>(
          lazy: true,
          create: (_) => FirestoreService(),
          update: (_, __) => FirestoreService(),
        ),
        ProxyProvider0<StorageService>(
          lazy: true,
          create: (_) => StorageService(),
          update: (_, __) => StorageService(),
        ),
        ProxyProvider0<NotificationService>(
          lazy: true,
          create: (_) => NotificationService(),
          update: (_, __) => NotificationService(),
        ),
        ProxyProvider0<SubscriptionService>(
          lazy: true,
          create: (_) => SubscriptionService(),
          update: (_, __) => SubscriptionService(),
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
        // Add fallback route to prevent white screen
        onUnknownRoute:
            (settings) => MaterialPageRoute(
              builder: (_) => const AssignedCoursesScreen(),
            ),
        // Define routes for navigation from notifications
        routes: {
          '/chat': (context) => ChatScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}

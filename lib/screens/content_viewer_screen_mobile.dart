import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../widgets/simple_video_player.dart';
import '../widgets/learner_presence_video_wrapper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/responsive_helper.dart';
import '../utils/accessibility_helper.dart';
import '../widgets/adaptive_container.dart';
import '../utils/logger.dart';
import '../utils/content_state_manager.dart';

import '../models/content_model.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../utils/pdf_loader.dart';
import '../widgets/custom_pdf_viewer.dart';
import '../services/firestore_service.dart';
import '../services/first_time_user_service.dart';
import '../services/screenshot_blocking_service.dart';
import '../utils/exam_overview_navigator.dart';
import '../widgets/custom_bottom_navigation.dart';
import '../widgets/screen_recording_warning_dialog.dart';
import 'main_screen.dart';
import 'profile_completion_screen.dart';
import 'screenshot_warning_screen.dart';
import 'screenshot_blocked_screen.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../widgets/audio_player_widget.dart';
import 'package:url_launcher/url_launcher.dart';

// Watermark overlay widget for PDFs
class XfiniWatermark extends StatelessWidget {
  final String userName;

  const XfiniWatermark({super.key, required this.userName});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Calculate how many watermarks to show based on screen size
            final double cellWidth = 150;
            final double cellHeight = 150;
            final int horizontalCount =
                (constraints.maxWidth / cellWidth).ceil();
            final int verticalCount =
                (constraints.maxHeight / cellHeight).ceil();

            return Stack(
              children: [
                for (int y = 0; y < verticalCount; y++)
                  for (int x = 0; x < horizontalCount; x++)
                    Positioned(
                      left: x * cellWidth,
                      top: y * cellHeight,
                      child: Opacity(
                        opacity: 0.1,
                        child: Transform.rotate(
                          angle: -0.2,
                          child: Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF323483),
                            ),
                          ),
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Full-screen PDF viewer widget
class FullScreenPdfViewer extends StatefulWidget {
  final String filePath;
  final String userName;

  const FullScreenPdfViewer({
    super.key,
    required this.filePath,
    required this.userName,
  });

  @override
  State<FullScreenPdfViewer> createState() => _FullScreenPdfViewerState();
}

class _FullScreenPdfViewerState extends State<FullScreenPdfViewer> {
  bool _isFullScreen = true;

  @override
  void initState() {
    super.initState();
    // Use AccessibilityHelper to configure system UI
    _configureSystemUI();

    // Allow landscape orientations for better PDF viewing
    AccessibilityHelper.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _configureSystemUI() {
    // Enhanced platform-specific UI configuration
    if (Platform.isIOS) {
      AccessibilityHelper.configureSystemUI(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarVisible: !_isFullScreen,
      );
    } else {
      // Android - Better fullscreen experience
      AccessibilityHelper.configureSystemUI(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        navigationBarColor: Colors.black,
        navigationBarIconBrightness: Brightness.light,
        statusBarVisible: !_isFullScreen,
      );

      // In fullscreen mode, also hide navigation bar
      if (_isFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(
          SystemUiMode.manual,
          overlays: SystemUiOverlay.values,
        );
      }
    }
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      _configureSystemUI();
    });
  }

  @override
  void dispose() {
    // Restore system UI when leaving
    AccessibilityHelper.showStatusBar();

    // Restore original orientations
    AccessibilityHelper.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Ensure system UI is fully restored
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isLandscape = ResponsiveHelper.isLandscape(context);
    final bottomInset = mediaQuery.padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar:
          _isFullScreen
              ? PreferredSize(
                preferredSize: const Size.fromHeight(0),
                child: AppBar(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                ),
              )
              : AppBar(
                backgroundColor: Colors.black,
                elevation: 0,
                title: const Text('PDF Document'),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).pop(),
                  // Use a larger touch target for better accessibility
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen),
                    onPressed: _toggleFullScreen,
                    // Use a larger touch target
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                  ),
                ],
              ),
      // Use SafeContainer for proper safe area handling
      body: SafeArea(
        // In landscape mode, we might want to reduce padding to maximize viewing area
        bottom: !isLandscape,
        child: GestureDetector(
          onTap: _toggleFullScreen,
          onDoubleTap: _toggleFullScreen, // Double tap also toggles fullscreen
          // iOS-specific gesture enhancements
          onLongPress: ResponsiveHelper.isIOS() ? _toggleFullScreen : null,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            children: [
              SizedBox.expand(
                child: CustomPDFViewer(
                  filePath: widget.filePath,
                  userName: widget.userName,
                ),
              ),
              // Show floating button based on screen state
              if (!_isFullScreen)
                Positioned(
                  bottom: bottomInset + 20, // Respect device bottom inset
                  right: 20,
                  child: FloatingActionButton(
                    backgroundColor: Colors.black.withAlpha(
                      128,
                    ), // 0.5 opacity = 128 alpha (255 * 0.5)
                    onPressed: _toggleFullScreen,
                    child: const Icon(Icons.fullscreen),
                    heroTag: "pdf_fullscreen_btn", // Unique hero tag
                  ),
                ),
              // Show exit hint in fullscreen mode
              if (_isFullScreen)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 20,
                  left: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(128),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "Tap to exit fullscreen",
                      style: TextStyle(color: Colors.white, fontSize: 12),
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


class ContentViewerScreen extends StatefulWidget {
  final CourseModel course;
  final ModuleModel module;
  final int? initialContentIndex;
  final String? filteredContentType;
  final bool singleContentMode; // New: When true, only show the single selected content
  final bool isExamOverviewMode;

  const ContentViewerScreen({
    super.key,
    required this.course,
    required this.module,
    this.initialContentIndex,
    this.filteredContentType,
    this.singleContentMode = false,
    this.isExamOverviewMode = false,
  });

  @override
  State<ContentViewerScreen> createState() => _ContentViewerScreenState();
}

class _ContentViewerScreenState extends State<ContentViewerScreen> with WidgetsBindingObserver {
  late Future<List<ContentModel>> _contentFuture;
  bool _isLoading = true;
  int _currentContentIndex = 0;
  int _selectedIndex = 0; // For bottom navigation
  String _userName = ""; // Store user name
  int _totalContentCount = 0; // Track total content vs available content

  // Content state manager for persistent content loading (singleton instance)
  final ContentStateManager _contentStateManager = ContentStateManager();

  // PDF state variables (legacy - gradually being replaced by content state manager)
  String? _pdfPath;
  String? _pdfError;
  bool _isScreenProtectionEnabled = false;

  // Screenshot / screen-recording protection
  final ScreenshotBlockingService _screenshotService = ScreenshotBlockingService();
  bool _showingScreenshotWarning = false;
  bool _showingScreenRecordingWarning = false;

  // Exam overview tracking
  bool _hasMarkedExamOverviewAsWatched = false;

  // One-time view: tracks content IDs confirmed/marked in this session
  final Set<String> _viewedContentIds = {};
  // One-time view: content blocked because it was already viewed in a PREVIOUS session (or user cancelled).
  // Controls the locked-UI placeholder display.
  final Set<String> _blockedOneTimeContentIds = {};
  // One-time view: dedup guard — tracks IDs whose Firestore write has already been sent THIS session.
  // Used only to prevent double-writes; does NOT trigger the locked UI.
  final Set<String> _firestoreWrittenContentIds = {};
  // One-time view: in-flight guard — content IDs currently being checked against Firestore.
  // Prevents duplicate concurrent async calls from rapid rebuilds showing stacked dialogs.
  // Also shows a loading placeholder instead of raw content during the check window.
  final Set<String> _pendingCheckContentIds = {};

  @override
  void initState() {
    super.initState();

    Logger.i(
      "🏁 ContentViewerScreen initState for module: ${widget.module.id}",
    );

    // Add app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize content state manager for this module
    _contentStateManager.initForModule(widget.module.id);

    // Platform-specific safe area handling
    _configureForDevice();

    // Debug output for PDF loading
    Logger.d(
      "ContentViewerScreen init: Loading content for module ${widget.module.id} in course ${widget.course.id}",
    );

    // Get the user's name for the watermark
    _getUserName();

    // Clean up old PDF files
    _cleanupOldPdfFiles();

    // Initialize screenshot / screen-recording protection
    _initializeScreenshotService();

    // Load content
    _loadContent();
  }

  void _configureForDevice() {
    // Enhanced iOS-specific system UI configuration
    if (ResponsiveHelper.isIOS()) {
      AccessibilityHelper.configureSystemUI(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarVisible: true,
      );

      // iOS-specific performance optimization
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      AccessibilityHelper.configureSystemUI(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      );
    }

    // Allow both orientations with smooth transitions for content viewing
    AccessibilityHelper.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    Logger.i("🛑 ContentViewerScreen dispose for module: ${widget.module.id}");

    // Remove app lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    // Pause all currently playing videos when leaving the screen
    _contentStateManager.pauseAllVideos();

    // Clean up old content states (older than 30 minutes) but keep current ones
    _contentStateManager.clearOldContentStates();

    _removeScreenshotProtection();

    // Stop screenshot / screen-recording monitoring
    _screenshotService.removeListener(_onScreenshotServiceChanged);
    _screenshotService.stopMonitoring();

    // iOS-optimized orientation reset with smooth transition
    if (ResponsiveHelper.isIOS()) {
      // Smooth transition back to portrait on iOS
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Future.delayed(const Duration(milliseconds: 200), () {
        AccessibilityHelper.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      });
    } else {
      // Immediate reset for Android
      AccessibilityHelper.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }

    super.dispose();
  }

  // Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Pause all videos when app goes to background or becomes inactive
        Logger.i('📱 App paused/inactive - pausing all videos');
        _contentStateManager.pauseAllVideos();
        break;
      case AppLifecycleState.resumed:
        // App resumed - videos will remain paused until user manually plays them
        Logger.i('📱 App resumed - videos remain paused until user interaction');
        break;
      case AppLifecycleState.detached:
        // App is detached - pause videos for cleanup
        Logger.i('📱 App detached - pausing all videos');
        _contentStateManager.pauseAllVideos();
        break;
      case AppLifecycleState.hidden:
        // App is hidden - pause videos
        Logger.i('📱 App hidden - pausing all videos');
        _contentStateManager.pauseAllVideos();
        break;
    }
  }

  // Get the current user's name
  Future<void> _getUserName() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user != null) {
      // Use email as watermark, fall back to "User" if not available
      setState(() {
        _userName = user.email ?? "User";
      });
    }
  }

  // Remove screenshot protection when leaving the screen
  void _removeScreenshotProtection() async {
    // Restore system UI elements based on platform
    if (ResponsiveHelper.isIOS()) {
      AccessibilityHelper.configureSystemUI(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarVisible: true,
      );

      const MethodChannel(
        'flutter.native/screenProtection',
      ).invokeMethod('preventScreenshots', false);
      _isScreenProtectionEnabled = false;
    } else {
      AccessibilityHelper.showStatusBar();
    }
  }

  void _addScreenshotProtection() {
    if (!ResponsiveHelper.isIOS() || _isScreenProtectionEnabled) return;
    const MethodChannel(
      'flutter.native/screenProtection',
    ).invokeMethod('preventScreenshots', true);
    _isScreenProtectionEnabled = true;
  }

  void _maybeUpdateProtectionForContentType(String contentType) {
    if (!ResponsiveHelper.isIOS()) return;
    if (contentType == 'video' || contentType == 'pdf') {
      _addScreenshotProtection();
    } else if (_isScreenProtectionEnabled) {
      _removeScreenshotProtection();
    }
  }

  // ---------------------------------------------------------------------------
  // Screenshot / screen-recording blocking (mirrors ProtectedCourseContent)
  // ---------------------------------------------------------------------------

  /// Initialize the screenshot blocking service for this screen
  Future<void> _initializeScreenshotService() async {
    if (!ResponsiveHelper.isIOS() && !ResponsiveHelper.isAndroid()) {
      Logger.i('📱 Screenshot blocking not available on this platform');
      return;
    }

    try {
      await _screenshotService.initialize();
      _screenshotService.addListener(_onScreenshotServiceChanged);

      // Provide current user context so per-user state is loaded
      final authService = Provider.of<AuthService>(context, listen: false);
      await _screenshotService.onUserAuthChanged(authService.currentUser);

      // Check for any admin reset that happened while the user was away
      if (ResponsiveHelper.isIOS()) {
        await _screenshotService.checkForAdminReset();
      }

      // Begin monitoring
      await _screenshotService.startMonitoring();

      Logger.i('📱 Screenshot blocking service initialized in ContentViewerScreen');
    } catch (error) {
      Logger.e('❌ Error initializing screenshot service in ContentViewerScreen: $error');
    }
  }

  /// React to screenshot / screen-recording service state changes
  void _onScreenshotServiceChanged() {
    if (!mounted) return;

    Logger.i('📱 Screenshot service state changed (ContentViewerScreen)');

    // Access restored by admin
    if (_screenshotService.shouldShowResetMessage) {
      _screenshotService.acknowledgeResetMessage();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
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
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    // First screenshot → warning screen
    if (_screenshotService.shouldShowWarning() && !_showingScreenshotWarning) {
      _showScreenshotWarningScreen();
    }

    // Screen recording detected → warning dialog
    if (_screenshotService.shouldShowScreenRecordingWarning && !_showingScreenRecordingWarning) {
      Logger.w('📱 Triggering screen recording warning dialog (ContentViewerScreen)');
      _showScreenRecordingWarningDialog();
    }

    // Second screenshot → block access
    if (_screenshotService.shouldBlockAccess()) {
      _showScreenshotBlockedScreen();
    }
  }

  /// Navigate to the screenshot-warning screen (first violation)
  void _showScreenshotWarningScreen() {
    if (_showingScreenshotWarning) return;
    setState(() => _showingScreenshotWarning = true);
    _screenshotService.markWarningShown();
    Logger.w('📱 Showing screenshot warning screen (ContentViewerScreen)');

    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            ScreenshotWarningScreen(
              onContinue: () {
                Navigator.of(context).pop();
                setState(() => _showingScreenshotWarning = false);
              },
            ),
        transitionDuration: const Duration(milliseconds: 150),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        fullscreenDialog: true,
      ),
    );
  }

  /// Replace this screen with the screenshot-blocked screen (second violation)
  void _showScreenshotBlockedScreen() {
    Logger.e('📱 Showing screenshot blocked screen (ContentViewerScreen)');
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ScreenshotBlockedScreen(),
        transitionDuration: const Duration(milliseconds: 100),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
        fullscreenDialog: true,
      ),
    );
  }

  /// Show the screen-recording warning dialog
  void _showScreenRecordingWarningDialog() {
    if (_showingScreenRecordingWarning) return;
    setState(() => _showingScreenRecordingWarning = true);
    Logger.w('📱 Showing screen recording warning dialog (ContentViewerScreen)');

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => ScreenRecordingWarningDialog(
        onDismiss: () {
          setState(() => _showingScreenRecordingWarning = false);
          _screenshotService.markScreenRecordingWarningShown();
        },
      ),
    );
  }

  Future<List<ContentModel>> _getFilteredContent() async {
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    // Load all content from Firestore
    var contentList = await firestoreService.getModuleContent(
      widget.course.id,
      widget.module.id,
    );

    Logger.i("Loaded ${contentList.length} content items");
    
    // Filter content by type if specified
    if (widget.filteredContentType != null) {
      contentList = contentList
          .where((content) => content.contentType == widget.filteredContentType)
          .toList();
      Logger.i(
        "Filtered to ${contentList.length} items of type ${widget.filteredContentType}",
      );
    }

    // If in single content mode, return only the selected content item
    if (widget.singleContentMode && widget.initialContentIndex != null) {
      if (widget.initialContentIndex! >= 0 && widget.initialContentIndex! < contentList.length) {
        final singleContent = contentList[widget.initialContentIndex!];
        Logger.i("Single content mode: showing only '${singleContent.title}'");
        return [singleContent];
      }
    }

    // Print detailed info for debugging
    for (int i = 0; i < contentList.length; i++) {
      final content = contentList[i];
      Logger.d("Content item #$i:");
      Logger.d("  - ID: ${content.id}");
      Logger.d("  - Title: ${content.title}");
      Logger.d("  - Type: ${content.contentType}");
      Logger.d("  - URL/Content: ${content.content}");

      // Verify URL format for videos and PDFs
      if ((content.contentType == 'video' || content.contentType == 'pdf') &&
          content.content.isNotEmpty) {
        if (!content.content.startsWith('http')) {
          Logger.w("WARNING: Invalid URL format: ${content.content}");
        } else {
          Logger.d("URL format looks valid");
        }
      }
    }

    return contentList;
  }

  Future<void> _loadContent() async {
    final authService = Provider.of<AuthService>(context, listen: false);

    setState(() {
      _isLoading = true;
    });

    try {
      // First verify the user has access to this course
      Logger.i("Verifying access to course: ${widget.course.id}");
      final hasAccess = await authService.hasAccessToCourse(widget.course.id);

      if (!hasAccess) {
        Logger.w(
          "Access denied: User does not have access to course ${widget.course.id}",
        );
        setState(() {
          _isLoading = false;
        });

        // Show access denied message
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You do not have access to this course content.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      Logger.i("Access granted: User has access to course ${widget.course.id}");

      // Now load and filter the content
      setState(() {
        _contentFuture = _getFilteredContent();
      });

      final contentList = await _contentFuture;
      
      // Store content count for empty state logic
      _totalContentCount = contentList.length;

      // In single content mode, always start at index 0 (the only item)
      // Otherwise, set initial content index if provided and valid
      if (widget.singleContentMode) {
        setState(() {
          _currentContentIndex = 0;
        });
        Logger.i("Single content mode: index set to 0");
      } else if (widget.initialContentIndex != null &&
          widget.initialContentIndex! >= 0 &&
          widget.initialContentIndex! < contentList.length) {
        setState(() {
          _currentContentIndex = widget.initialContentIndex!;
        });
        Logger.i("Set initial content index to ${widget.initialContentIndex}");
      }

      // Skip pre-initialization to prevent multiple simultaneous initializations
      // Video player will be initialized when needed in _buildContentView
    } catch (e) {
      Logger.e("Error loading content: $e");
      // Log stack trace for better error diagnosis
      Logger.e("Stack trace: ${StackTrace.current}");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeVideoController(ContentModel content) async {
    // Check if widget is still mounted
    if (!mounted) return;

    // Check if already loading
    if (_contentStateManager.isContentLoading(content, 'video')) {
      return;
    }

    _contentStateManager.setContentLoading(content, 'video', true);

    try {
      Logger.i("Initializing video controller for: ${content.title}");

      // ── Token refresh ────────────────────────────────────────────────────
      // Firebase Auth ID tokens expire after 1 hour.  The video player makes
      // raw HTTP requests that carry the token; if the token has expired the
      // CDN returns HTTP 412, which surfaces as a play error on iOS/Android.
      // Force a silent refresh here so the token is always fresh before play.
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.forceTokenRefresh();
        Logger.d('Token refreshed before video load');
      } catch (tokenErr) {
        // Non‑fatal — proceed with existing token
        Logger.w('Could not refresh token before video load (non-fatal): $tokenErr');
      }
      // ─────────────────────────────────────────────────────────────────────

      // Determine the video URL to use
      final videoUrl = content.originalUrl ?? content.content;
      Logger.i('Using video URL: $videoUrl');

      // Basic URL validation
      if (!videoUrl.startsWith('http')) {
        throw Exception("Invalid video URL format");
      }

      // Create and initialize the video controller
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
      );

      await controller.initialize();

      // Store the controller in the content state manager
      _contentStateManager.setVideoController(content, controller);

      // Add listener to track video progress for exam overview completion
      if (_isExamOverviewContent()) {
        controller.addListener(() => _trackVideoProgress(controller, content));
      }

      // Rebuild the UI to show the video player
      if (mounted) {
        setState(() {});
      }

      Logger.i(
        "Video controller initialization completed for: ${content.title}",
      );
    } catch (e) {
      Logger.e('Error initializing video controller: $e');

      // Detect HTTP 412 (expired token) and give the user a helpful message
      final errStr = e.toString();
      final isTokenExpiry = errStr.contains('412') ||
          errStr.contains('CoreMediaErrorDomain') ||
          errStr.contains('Precondition Failed');

      if (mounted) {
        final msg = isTokenExpiry
            ? 'Session token expired. Please go back and try again.'
            : 'Could not load video: ${e.toString()}';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );

        // Rebuild to show error state
        setState(() {});
      }
    } finally {
      _contentStateManager.setContentLoading(content, 'video', false);
    }
  }

  // Load PDF using content state manager for persistence
  Future<void> _loadPdfWithStateManager(ContentModel content) async {
    // Check if already loading
    if (_contentStateManager.isContentLoading(content, 'pdf')) {
      return;
    }

    _contentStateManager.setContentLoading(content, 'pdf', true);

    try {
      Logger.i("Loading PDF for: ${content.title}");

      // ── Token refresh ────────────────────────────────────────────────────
      // Force a silent refresh here so the token is always fresh before fetching
      // the storage signed URL. Keeps us from hitting 412 or permission errors.
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.forceTokenRefresh();
        Logger.d('Token refreshed before PDF load');
      } catch (tokenErr) {
        // Non‑fatal — proceed with existing token
        Logger.w('Could not refresh token before PDF load (non-fatal): $tokenErr');
      }
      // ─────────────────────────────────────────────────────────────────────

      // Use the existing PDF loading logic but store result in content state manager
      final pdfPath = await _downloadAndSavePdf(content.content);

      if (pdfPath != null) {
        _contentStateManager.setPdfPath(content, pdfPath);
        Logger.i("PDF loaded and cached for: ${content.title}");

        // Update UI
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      Logger.e('Error loading PDF: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load PDF: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      _contentStateManager.setContentLoading(content, 'pdf', false);
    }
  }

  // Native platforms method to download PDF and save it locally with enhanced security
  Future<String?> _downloadAndSavePdf(String pdfUrl) async {
    try {
      Logger.i("Content Viewer: Loading PDF from URL: $pdfUrl");

      // Validate the URL
      if (pdfUrl.isEmpty ||
          (!pdfUrl.startsWith('http') && !pdfUrl.startsWith('gs://'))) {
        throw Exception("Invalid PDF URL format: $pdfUrl");
      }

      // Get storage service
      final storageService = Provider.of<StorageService>(
        context,
        listen: false,
      );

      // Get auth service to verify access
      final authService = Provider.of<AuthService>(context, listen: false);

      // Print debug info
      Logger.d("User ID: ${authService.currentUser?.uid}");
      Logger.d("Course ID: ${widget.course.id}");
      Logger.d("Module ID: ${widget.module.id}");
      Logger.d("PDF URL: $pdfUrl");

      // Verify course access first
      final hasAccess = await authService.hasAccessToCourse(widget.course.id);
      Logger.d("Access check result: $hasAccess");

      if (!hasAccess) {
        Logger.w("Access denied to course ${widget.course.id}");
        throw Exception(
          "You don't have access to this course content. Please verify your course access.",
        );
      }

      String secureUrl;

      // Check if this is a Firebase Storage URL or direct URL
      if (pdfUrl.contains('firebasestorage') || pdfUrl.startsWith('gs://')) {
        Logger.i("Processing Firebase Storage URL");
        try {
          // Get secure URL with short expiration
          secureUrl = await storageService.getSecurePdfUrl(pdfUrl);
          Logger.i(
            "Secure URL generated: ${secureUrl.substring(0, min(50, secureUrl.length))}...",
          );
        } catch (e) {
          Logger.e("Error getting secure URL: $e");
          Logger.e("Stack trace: ${StackTrace.current}");

          if (e.toString().contains('403') ||
              e.toString().contains('permission')) {
            throw Exception(
              "Access denied: You don't have permission to access this PDF. Please verify your course access.",
            );
          }

          // Try direct download as fallback only if not a permission error
          Logger.w("Attempting direct download as fallback");
          secureUrl = pdfUrl;
        }
      } else {
        // Use the provided URL directly if it's not a Firebase Storage URL
        secureUrl = pdfUrl;
        Logger.d("Using direct URL");
      }

      // Try using the PDFLoader instead of manual download
      Logger.i("Using PDFLoader class to download and save PDF");

      final filePath = await PDFLoader.loadPDF(secureUrl);

      if (filePath == null) {
        throw Exception("Failed to load PDF through PDFLoader");
      }

      Logger.i("PDFLoader succeeded: $filePath");

      // Return the file path for content state manager
      return filePath;
    } catch (e) {
      Logger.e('Error loading PDF: $e');
      Logger.e('Stack trace: ${StackTrace.current}');
      // Don't set state here - let the calling method handle the error
      rethrow;
    }
  }

  // Update the _buildContentView method to handle PDF viewing with watermark
  Widget _buildContentView(ContentModel content) {
    Logger.d(
      "DEBUG: _buildContentView called for ${content.title} (${content.contentType})",
    );
    Logger.d("DEBUG: Content ID: ${content.id}");

    // One-time view gate: show blocked placeholder if already locked
    if (content.isOneTimeView && _blockedOneTimeContentIds.contains(content.id)) {
      return _buildOneTimeViewBlockedPlaceholder(content);
    }

    if (content.isOneTimeView && !_viewedContentIds.contains(content.id)) {
      // Show a loading placeholder while the Firestore check is in-flight.
      // This prevents the raw content from being visible (and triggering the
      // PDF onRender / video 80% callback) before the user has confirmed.
      if (_pendingCheckContentIds.contains(content.id)) {
        return _buildOneTimeViewCheckingPlaceholder();
      }

      // Launch the check — the in-flight guard prevents duplicate calls.
      Future.microtask(() => _checkAndEnforceOneTimeView(content));
      return _buildOneTimeViewCheckingPlaceholder();
    }

    // Ensure iOS screen protection is toggled appropriately by content type
    _maybeUpdateProtectionForContentType(content.contentType);
    switch (content.contentType) {
      case 'video':
        if (content.content.isEmpty) {
          return const Center(
            child: Text(
              'No video URL available.',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Check if video controller already exists in content state manager
        final existingController = _contentStateManager.getVideoController(
          content,
        );

        Logger.d("DEBUG: Checking video controller for ${content.title}");
        Logger.d("DEBUG: Existing controller: ${existingController != null}");
        Logger.d(
          "DEBUG: Is initialized: ${existingController?.value.isInitialized}",
        );

        if (existingController != null &&
            existingController.value.isInitialized) {
          // Use existing controller - no reloading needed!
          Logger.i("✅ Using existing video controller for: ${content.title}");
          return Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            // Wrap the video with the learner-presence overlay so the student
            // sees a small front-camera self-preview while the lecture plays.
            child: LearnerPresenceVideoWrapper(
              contentKey: content.id,
              child: Center(
                child: SimpleVideoPlayer(
                  key: ValueKey("video_${content.id}_persistent"),
                  videoUrl: existingController?.dataSource ?? content.originalUrl ?? content.content,
                  autoPlay: false,
                  userName: _userName,
                  showWatermark: true,
                  existingController: existingController,
                  onViewedCallback: content.isOneTimeView
                      ? () => _markOneTimeContentViewed(content)
                      : null,
                ),
              ),
            ),
          );
        }

        // Initialize new video controller if needed
        if (!_contentStateManager.isContentLoading(content, 'video')) {
          Logger.i("Initializing new video controller for: ${content.title}");
          Future.microtask(() => _initializeVideoController(content));
        }

        // Show loading while initializing
        return const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        );

      case 'pdf':
        if (content.content.isEmpty) {
          return const Center(
            child: Text(
              'No PDF URL available.',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        // Check if PDF already loaded in content state manager
        final existingPdfPath = _contentStateManager.getPdfPath(content);

        if (existingPdfPath != null) {
          Logger.i("Using existing PDF path for: ${content.title}");
        } else {
          // Load PDF if not already loaded and not currently loading
          if (!_contentStateManager.isContentLoading(content, 'pdf')) {
            Future.microtask(() => _loadPdfWithStateManager(content));
          }
        }

        // Show PDF viewer when PDF is loaded
        final pdfPath = existingPdfPath ?? _pdfPath;
        if (pdfPath != null) {
          // Wrap in a Stack to have a floating fullscreen button
          return Stack(
            children: [
              // PDF viewer takes the full space
              Container(
                width: double.infinity,
                height: double.infinity,
                color: Colors.white,
                child: CustomPDFViewer(
                  filePath: pdfPath,
                  userName: _userName,
                  onViewedCallback: content.isOneTimeView
                      ? () => _markOneTimeContentViewed(content)
                      : null,
                ),
              ),

              // Floating fullscreen button
              Positioned(
                bottom: 16,
                right: 16,
                child: FloatingActionButton(
                  backgroundColor: const Color(0xFF323483),
                  mini: true,
                  heroTag: "content_pdf_fullscreen_btn", // Unique hero tag
                  child: const Icon(Icons.fullscreen, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder:
                            (context) => FullScreenPdfViewer(
                              filePath: pdfPath,
                              userName: _userName,
                            ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        // Show error message if there's an error
        if (_pdfError != null) {
          String errorMessage = _pdfError!;
          String actionMessage =
              "Please try again or contact support if the problem persists.";
          IconData errorIcon = Icons.error_outline;

          // Format user-friendly error messages
          if (_pdfError!.contains("403") || _pdfError!.contains("permission")) {
            errorMessage = "You don't have permission to access this file.";
            actionMessage =
                "Please verify that you have access to this module.";
            errorIcon = Icons.lock_outline;
          } else if (_pdfError!.contains("404") ||
              _pdfError!.contains("not found")) {
            errorMessage = "The requested PDF file could not be found.";
            actionMessage = "The file may have been moved or deleted.";
            errorIcon = Icons.find_in_page;
          } else if (_pdfError!.contains("timeout") ||
              _pdfError!.contains("timed out")) {
            errorMessage = "Connection timed out while downloading the PDF.";
            actionMessage =
                "Please check your internet connection and try again.";
            errorIcon = Icons.wifi_off;
          }

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(errorIcon, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                'Error loading PDF',
                style: TextStyle(
                  color: Colors.red[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  actionMessage,
                  style: const TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF323483),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      setState(() {
                        _pdfError = null;
                      });
                      _loadPdfWithStateManager(content);
                    },
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ],
          );
        }

        // Show loading indicator while PDF is being prepared - UPDATED COLORS
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
              const SizedBox(height: 20),
              const Text(
                'Loading PDF...',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Module: ${widget.module.title}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'This may take a moment depending on your connection',
                style: TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

      case 'link':
        return _buildLinkContent(content);

      case 'image':
        return _buildImageContent(content);

      case 'audio':
        return _buildAudioContent(content);
        
      case 'text':
      default:
        return Stack(
          children: [
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  content.content,
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
              ),
            ),
            // Add watermark overlay with the user's name
            XfiniWatermark(userName: _userName),
          ],
        );
    }
  }

  // ---------------------------------------------------------------------------
  // One-Time View helpers
  // ---------------------------------------------------------------------------

  /// Runs the Firestore check and shows the appropriate dialog.
  /// Must be called with Future.microtask to avoid setState-during-build.
  ///
  /// The [_pendingCheckContentIds] in-flight guard ensures only ONE call runs
  /// at a time per content ID, preventing stacked dialogs from rapid rebuilds.
  Future<void> _checkAndEnforceOneTimeView(ContentModel content) async {
    if (!mounted) return;
    // Already resolved for this session — nothing to do.
    if (_viewedContentIds.contains(content.id)) return;
    if (_blockedOneTimeContentIds.contains(content.id)) return;

    // In-flight guard: if a check is already running for this ID, bail out.
    if (_pendingCheckContentIds.contains(content.id)) return;
    setState(() => _pendingCheckContentIds.add(content.id));

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid;
      if (userId == null) {
        // No user — clean up the guard so the spinner doesn't get stuck.
        if (mounted) setState(() => _pendingCheckContentIds.remove(content.id));
        return;
      }

      final firestoreService = Provider.of<FirestoreService>(context, listen: false);

      // Check Firestore
      final alreadyViewed = await firestoreService.checkIfContentViewed(userId, content.id);

      if (!mounted) {
        // Widget unmounted during network call — clean up in-memory state.
        _pendingCheckContentIds.remove(content.id);
        return;
      }

      if (alreadyViewed) {
        // Content was viewed in a previous session — lock it and inform the user.
        setState(() {
          _pendingCheckContentIds.remove(content.id);
          _blockedOneTimeContentIds.add(content.id);
        });
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.lock, color: Color(0xFF323483)),
                SizedBox(width: 8),
                Text('Content Expired'),
              ],
            ),
            content: const Text(
              'You have already viewed this content. One-time view content cannot be accessed again.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK', style: TextStyle(color: Color(0xFF323483))),
              ),
            ],
          ),
        );
        return;
      }

      // Not yet viewed — ask for confirmation before exposing the content.
      if (!mounted) {
        _pendingCheckContentIds.remove(content.id);
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.visibility_off, color: Color(0xFF323483)),
              SizedBox(width: 8),
              Text('One-Time View'),
            ],
          ),
          content: const Text(
            'You can only view this content once. Once you proceed, it will be permanently locked. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF323483),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (!mounted) {
        _pendingCheckContentIds.remove(content.id);
        return;
      }

      if (confirmed == true) {
        // User confirmed — remove from pending and allow content to render.
        setState(() {
          _pendingCheckContentIds.remove(content.id);
          _viewedContentIds.add(content.id);
        });

        // 🔒 Write to Firestore IMMEDIATELY on confirmation (not deferred to 80%
        // video progress). This prevents the dialog from re-appearing if the user
        // goes back before the 80% threshold fires.
        // userId and firestoreService are already captured above — reuse them
        // to avoid calling Provider.of(context) across an async gap.
        if (!_firestoreWrittenContentIds.contains(content.id)) {
          _firestoreWrittenContentIds.add(content.id);
          final writeSucceeded = await firestoreService.markContentAsViewed(userId, content.id);
          if (!writeSucceeded && mounted) {
            // Another device beat us to it — lock immediately.
            Logger.w('🔒 Two-device race at confirmation — locking content: ${content.title}');
            setState(() => _blockedOneTimeContentIds.add(content.id));
          } else {
            Logger.i('🔒 One-time view locked at confirmation: ${content.title}');
          }
        }
      } else {
        // User cancelled — block the content and navigate away.
        setState(() {
          _pendingCheckContentIds.remove(content.id);
          _blockedOneTimeContentIds.add(content.id);
        });
        if (_currentContentIndex > 0) {
          setState(() => _currentContentIndex--);
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      // On any error, remove the pending guard so the user can retry.
      Logger.e('Error in _checkAndEnforceOneTimeView: $e');
      if (mounted) setState(() => _pendingCheckContentIds.remove(content.id));
    }
  }

  /// Secondary (belt-and-suspenders) Firestore write for video (80% progress)
  /// and PDF (first render) content types.
  ///
  /// The PRIMARY write now happens immediately when the user taps "Continue" in
  /// [_checkAndEnforceOneTimeView], so in the happy path this callback is a
  /// no-op (guarded by [_firestoreWrittenContentIds]).
  ///
  /// It only does real work if the confirmation-time write was silently swallowed
  /// by a network error (the service returns true to avoid blocking the user).
  ///
  /// NOTE: Does NOT add to [_blockedOneTimeContentIds] on success — content stays
  /// playable for the rest of this session; blocked on next session when
  /// [checkIfContentViewed] returns true.
  ///
  /// Image / link / audio / text content types do NOT need this callback because
  /// the confirmation-time write is sufficient for instantaneous content.
  void _markOneTimeContentViewed(ContentModel content) async {
    if (!mounted) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.uid;
    if (userId == null) return;

    // Prevent duplicate Firestore writes in this session without blocking the UI.
    if (_firestoreWrittenContentIds.contains(content.id)) return;
    _firestoreWrittenContentIds.add(content.id);

    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final writeSucceeded = await firestoreService.markContentAsViewed(userId, content.id);

    if (!mounted) return;

    if (!writeSucceeded) {
      // Another device already consumed this one-time view.
      // Lock the content on this device immediately.
      Logger.w('🔒 Two-device race detected — locking content: ${content.title}');
      setState(() => _blockedOneTimeContentIds.add(content.id));
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.lock, color: Color(0xFF323483)),
              SizedBox(width: 8),
              Text('Content Expired'),
            ],
          ),
          content: const Text(
            'This content was already viewed on another device. One-time view content cannot be accessed again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK', style: TextStyle(color: Color(0xFF323483))),
            ),
          ],
        ),
      );
    } else {
      Logger.i('🔒 One-time content marked as viewed: ${content.title}');
    }
  }

  /// Shown while the Firestore check is in flight (spinner + brief message).
  Widget _buildOneTimeViewCheckingPlaceholder() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF323483)),
          SizedBox(height: 16),
          Text(
            'Verifying access…',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  /// Placeholder widget shown after the content has been confirmed as already viewed.
  Widget _buildOneTimeViewBlockedPlaceholder(ContentModel content) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF323483).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock,
                size: 52,
                color: Color(0xFF323483),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Content Expired',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF323483),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'You have already viewed this one-time content. It is no longer accessible.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  /// Check if current content is from Exam Overview course

  /// (any module within the course counts)
  bool _isExamOverviewContent() {
    return widget.course.id == ExamOverviewNavigator.examOverviewCourseId;
  }

  /// Track video progress and mark exam overview as watched when 100% complete
  void _trackVideoProgress(VideoPlayerController controller, ContentModel content) async {
    if (!mounted || _hasMarkedExamOverviewAsWatched) return;

    if (!controller.value.isInitialized) return;

    final position = controller.value.position;
    final duration = controller.value.duration;

    if (duration.inSeconds == 0) return;

    // Calculate percentage watched
    final percentageWatched = (position.inSeconds / duration.inSeconds) * 100;

    // If user has watched 100% (video completed), mark exam overview as complete
    if (percentageWatched >= 99.5) { // Using 99.5% to account for rounding
      Logger.i('📚 User has completed Exam Overview video (${percentageWatched.toStringAsFixed(1)}%)');
      
      // Mark as watched
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.uid;
      
      if (userId != null) {
        final firstTimeUserService = FirstTimeUserService();
        await firstTimeUserService.markExamOverviewAsWatched(userId);
        
        setState(() {
          _hasMarkedExamOverviewAsWatched = true;
        });

        // Check profile completion to decide where to navigate next
        final profileComplete = await authService.isProfileComplete();

        // Show success message
        if (mounted) {
          final destination = profileComplete ? 'home screen' : 'profile setup';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Exam Overview completed! Navigating to $destination...',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Stop video playback before navigation
          Future.delayed(const Duration(seconds: 3), () async {
            if (mounted) {
              // Pause video controller to prevent background playback
              try {
                await controller.pause();
                Logger.i('🎬 Video paused before navigation');
              } catch (e) {
                Logger.w('Failed to pause video: $e');
              }

              // Navigate based on profile completion status, clearing all previous routes
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (context) => profileComplete
                        ? const MainScreen()
                        : const ProfileCompletionScreen(),
                  ),
                  (route) => false,
                );
              }
            }
          });
        }

        Logger.i('✅ Exam Overview marked as watched for user: $userId');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: !widget.isExamOverviewMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && widget.isExamOverviewMode) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please watch the Exam Overview before accessing the app',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        // Proper system UI handling
        extendBodyBehindAppBar: false,
        extendBody: false,
        appBar: AppBar(
          backgroundColor: Colors.grey[50],
          elevation: 0,
          leading: widget.isExamOverviewMode
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          widget.module.title,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        child:
            _isLoading
                ? Center(child: const CircularProgressIndicator())
                : FutureBuilder<List<ContentModel>>(
                  future: _contentFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 20),
                            Text(
                              'Loading module content...',
                              style: GoogleFonts.inter(
                                fontSize:
                                    ResponsiveHelper.isTablet(context)
                                        ? 18
                                        : 16,
                                color: const Color(0xFF323483),
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              size: 48,
                              color: Colors.red,
                            ),
                            const SizedBox(height: 16),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24.0,
                              ),
                              child: Text(
                                'Error loading content: ${snapshot.error}',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _loadContent,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try Again'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF323483),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final contentList = snapshot.data ?? [];
                    if (contentList.isEmpty) {
                      return _buildEmptyContentState();
                    }

                    // Ensure current index is valid
                    if (_currentContentIndex >= contentList.length) {
                      _currentContentIndex = contentList.length - 1;
                    }

                    final currentContent = contentList[_currentContentIndex];

                    // Use adaptive container for orientation changes
                    return OrientationLayout(
                      portrait: _buildPortraitLayout(
                        context,
                        screenSize,
                        safeAreaBottom,
                        contentList,
                        currentContent,
                        ResponsiveHelper.isTablet(context),
                      ),
                      landscape: _buildLandscapeLayout(
                        context,
                        screenSize,
                        safeAreaBottom,
                        contentList,
                        currentContent,
                        ResponsiveHelper.isTablet(context),
                      ),
                    );
                  },
                ),
      ),
      bottomNavigationBar: widget.isExamOverviewMode
        ? null
        : CustomBottomNavigation(
            selectedIndex: _selectedIndex,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
              CustomBottomNavigation.handleNavigation(context, index);
            },
          ),
      ),
    );
  }

  // Portrait layout for the content viewer
  Widget _buildPortraitLayout(
    BuildContext context,
    Size screenSize,
    double safeAreaBottom,
    List<ContentModel> contentList,
    ContentModel currentContent,
    bool isTablet,
  ) {
    return Column(
      children: [
        // Content Title - Dynamic sizing
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 80, // Increased height for longer titles
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                currentContent.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  height: 1.2, // Line height for better readability
                ),
                maxLines: 3, // Allow up to 3 lines
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        
        // Content Container - Takes remaining space
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: _getColorForContentType(currentContent.contentType),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _getColorForContentType(currentContent.contentType).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: _buildContentView(currentContent),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Helper widget for modern navigation buttons
  Widget _buildNavigationButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: enabled
              ? const Color(0xFF323483).withOpacity(0.1)
              : Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: enabled ? const Color(0xFF323483) : Colors.grey[400],
          size: 20,
        ),
      ),
    );
  }

  // Helper method to get color for content type - UPDATED PDF COLOR
  Color _getColorForContentType(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return const Color(0xFF1565C0); // Blue
      case 'pdf':
        return const Color(0xFF29ACD6); // Light Blue (changed from purple)
      case 'audio':
        return Colors.white; // White background (like link)
      case 'image':
        return const Color(0xFFE53935); // Red
      case 'link':
        return const Color(0xFF1976D2); // Blue
      case 'text':
        return const Color(0xFF388E3C); // Green
      default:
        return const Color(0xFF323483); // Default brand color
    }
  }

  // Helper method to get icon for content type
  IconData _getIconForContentType(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return Icons.play_circle_outline;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'audio':
        return Icons.headphones;
      case 'image':
        return Icons.image;
      case 'link':
        return Icons.link;
      case 'text':
        return Icons.text_fields;
      default:
        return Icons.description;
    }
  }

  // Helper method to get display name for content type
  String _getDisplayNameForContentType(String type) {
    switch (type.toLowerCase()) {
      case 'video':
        return 'Video';
      case 'pdf':
        return 'PDF';
      case 'audio':
        return 'Audio';
      case 'image':
        return 'Image';
      case 'link':
        return 'Link';
      case 'text':
        return 'Document';
      default:
        return type.toUpperCase();
    }
  }

  // Clean up old PDF files to prevent storage issues
  Future<void> _cleanupOldPdfFiles() async {
    try {
      Directory cacheDir;
      try {
        cacheDir = await getTemporaryDirectory();
        final pdfDir = Directory('${cacheDir.path}/pdf_cache');
        if (!await pdfDir.exists()) {
          return; // No PDF cache directory yet
        }
        cacheDir = pdfDir;
      } catch (e) {
        Logger.e("Could not access temp directory: $e");
        try {
          cacheDir = await getApplicationDocumentsDirectory();
        } catch (e) {
          Logger.e("Could not access app documents directory: $e");
          return;
        }
      }

      // Delete PDF files older than 24 hours
      Logger.i("Cleaning up PDF cache in ${cacheDir.path}");
      final now = DateTime.now();
      final oneDay = Duration(hours: 24);

      try {
        await for (final entity in cacheDir.list()) {
          if (entity is File && entity.path.endsWith('.pdf')) {
            final stat = await entity.stat();
            final fileAge = now.difference(stat.modified);

            if (fileAge > oneDay) {
              try {
                Logger.d("Deleting old PDF file: ${entity.path}");
                await entity.delete();
              } catch (e) {
                Logger.e("Error checking/deleting file ${entity.path}: $e");
              }
            }
          }
        }
      } catch (e) {
        // Ignore errors during cleanup - this is a background task
        // that shouldn't block the main flow
        Logger.e("Error during PDF cache cleanup: $e");
      }
    } catch (e) {
      // Completely ignore any top-level errors
    }
  }

  // Add the missing _buildLandscapeLayout method
  Widget _buildLandscapeLayout(
    BuildContext context,
    Size screenSize,
    double safeAreaBottom,
    List<ContentModel> contentList,
    ContentModel currentContent,
    bool isTablet,
  ) {
    // Landscape-optimized layout with modern design
    return Container(
      width: screenSize.width,
      height: screenSize.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF5F5F5),
            Colors.white,
          ],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: Navigation sidebar - only show if multiple content items
          if (contentList.length > 1)
            Container(
              width: screenSize.width * 0.28,
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header with content type badge
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF323483).withOpacity(0.05),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Content List',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF323483),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF323483).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${contentList.length} items',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF323483),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Content list
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: contentList.length,
                      itemBuilder: (context, i) {
                        final isSelected = i == _currentContentIndex;
                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? _getColorForContentType(contentList[i].contentType).withOpacity(0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? _getColorForContentType(contentList[i].contentType)
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            title: Text(
                              contentList[i].title,
                              style: GoogleFonts.inter(
                                color: isSelected
                                    ? _getColorForContentType(contentList[i].contentType)
                                    : Colors.black87,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _getColorForContentType(contentList[i].contentType).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getIconForContentType(contentList[i].contentType),
                                color: _getColorForContentType(contentList[i].contentType),
                                size: 20,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(
                                    Icons.play_arrow,
                                    color: _getColorForContentType(contentList[i].contentType),
                                  )
                                : null,
                            onTap: () {
                              // Pause current video before switching
                              if (_currentContentIndex < contentList.length) {
                                final currentContent = contentList[_currentContentIndex];
                                if (currentContent.contentType == 'video') {
                                  _contentStateManager.pauseVideo(currentContent);
                                }
                              }
                              
                              setState(() {
                                _currentContentIndex = i;
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Right side: Content viewer with modern card
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _buildContentView(currentContent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build image content widget
  Widget _buildImageContent(ContentModel content) {
    if (content.content.isEmpty) {
      return const Center(
        child: Text(
          'No image URL available.',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    return Stack(
      children: [
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: InteractiveViewer(
            panEnabled: true,
            scaleEnabled: true,
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                content.content,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF323483),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Loading image...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  Logger.e('Error loading image: $error');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load image',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          content.title,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        
        // Fullscreen button
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              icon: const Icon(
                Icons.fullscreen,
                color: Colors.white,
                size: 24,
              ),
              onPressed: () => _openFullscreenImage(content),
              tooltip: 'View fullscreen',
            ),
          ),
        ),
        
        // Add watermark overlay
        XfiniWatermark(userName: _userName),
      ],
    );
  }

  // Build audio content widget
  Widget _buildAudioContent(ContentModel content) {
    if (content.content.isEmpty) {
      return const Center(
        child: Text(
          'No audio URL available.',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF1976D2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        children: [
          AudioPlayerWidget(
            audioUrl: content.content,
            title: content.title,
            userName: _userName,
          ),
          // Add watermark overlay with the user's name
          XfiniWatermark(userName: _userName),
        ],
      ),
    );
  }

  // Helper method to open fullscreen image viewer
  void _openFullscreenImage(ContentModel content) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullscreenImageViewer(
          imageUrl: content.content,
          title: content.title,
          userName: _userName,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // Build link content widget
  Widget _buildLinkContent(ContentModel content) {
    if (content.content.isEmpty) {
      return const Center(
        child: Text(
          'No link URL available.',
          style: TextStyle(color: Colors.red),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: GestureDetector(
          onTap: () => _openLink(content.content),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            // Compact link icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.link,
                size: 40,
                color: Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 16),
            
            // Link title
            Text(
              content.title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            // Compact URL preview
            if (content.content.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Text(
                  content.content,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontFamily: 'monospace',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Primary action button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openLink(content.content),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open Link'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            
            // Subtle hint text
            Text(
              'Tap anywhere to open',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Open link in external browser
  Future<void> _openLink(String url) async {
    try {
      // Validate URL
      final uri = Uri.parse(url);
      if (uri.scheme.isEmpty || (!uri.scheme.startsWith('http'))) {
        throw FormatException('Invalid URL format');
      }
      
      // Open in external browser with error handling
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );
        } else {
          _showErrorDialog('Cannot open link: $url');
        }
      } catch (launchError) {
        _showErrorDialog('Failed to open link: ${launchError.toString()}');
      }
    } catch (e) {
      _showErrorDialog('Invalid link URL: ${e.toString()}');
    }
  }

  // Show error dialog
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyContentState() {
    // For now, we'll assume content is inactive rather than non-existent
    // This can be enhanced with more sophisticated logic if needed
    final bool hasInactiveContent = widget.module.isPublished; // Module is published but no content
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: hasInactiveContent ? Colors.amber[50] : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasInactiveContent ? Icons.schedule : Icons.folder_open,
                size: 60,
                color: hasInactiveContent ? Colors.amber[400] : Colors.grey[400],
              ),
            ),
            SizedBox(height: 24),
            Text(
              hasInactiveContent 
                ? 'Content Currently Inactive'
                : 'No Content Available',
              style: GoogleFonts.inter(
                fontSize: 20,
                color: hasInactiveContent ? Colors.amber[700] : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: hasInactiveContent ? Colors.amber[50] : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasInactiveContent ? Colors.amber[200]! : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    hasInactiveContent
                      ? 'This module has content that is currently not active. The content may be scheduled for future release or is temporarily unavailable.'
                      : 'This module doesn\'t have any content yet. New content will appear here when it becomes available.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      color: hasInactiveContent ? Colors.amber[600] : Colors.grey[600],
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: hasInactiveContent ? Colors.amber[100] : Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 20,
                          color: hasInactiveContent ? Colors.amber[700] : Colors.grey[600],
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Please contact your instructor for more information about when this content will be available.',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: hasInactiveContent ? Colors.amber[700] : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../widgets/simple_video_player.dart';
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
import '../widgets/custom_bottom_navigation.dart';

// Watermark overlay widget for PDFs
class BriffiniWatermark extends StatelessWidget {
  final String userName;

  const BriffiniWatermark({super.key, required this.userName});

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

  const ContentViewerScreen({
    super.key,
    required this.course,
    required this.module,
  });

  @override
  State<ContentViewerScreen> createState() => _ContentViewerScreenState();
}

class _ContentViewerScreenState extends State<ContentViewerScreen> {
  late Future<List<ContentModel>> _contentFuture;
  bool _isLoading = true;
  int _currentContentIndex = 0;
  int _selectedIndex = 0; // For bottom navigation
  String _userName = ""; // Store user name

  // Content state manager for persistent content loading (singleton instance)
  final ContentStateManager _contentStateManager = ContentStateManager();

  // PDF state variables (legacy - gradually being replaced by content state manager)
  String? _pdfPath;
  String? _pdfError;
  bool _isScreenProtectionEnabled = false;

  @override
  void initState() {
    super.initState();

    Logger.i(
      "🏁 ContentViewerScreen initState for module: ${widget.module.id}",
    );

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

    // Clean up old content states (older than 30 minutes) but keep current ones
    _contentStateManager.clearOldContentStates();

    _removeScreenshotProtection();

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

  Future<void> _loadContent() async {
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );
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

      // Now load the content
      setState(() {
        _contentFuture = firestoreService.getModuleContent(
          widget.course.id,
          widget.module.id,
        );
      });

      final contentList = await _contentFuture;
      Logger.i("Loaded ${contentList.length} content items");

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

      // Basic URL validation
      if (!content.content.startsWith('http')) {
        throw Exception("Invalid video URL format");
      }

      // Create and initialize the video controller
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(content.content),
      );

      await controller.initialize();

      // Store the controller in the content state manager
      _contentStateManager.setVideoController(content, controller);

      // Rebuild the UI to show the video player
      if (mounted) {
        setState(() {});
      }

      Logger.i(
        "Video controller initialization completed for: ${content.title}",
      );
    } catch (e) {
      Logger.e('Error initializing video controller: $e');

      if (mounted) {
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load video: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
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
            child: Center(
              child: SimpleVideoPlayer(
                key: ValueKey("video_${content.id}_persistent"),
                videoUrl: content.content,
                title: content.title,
                autoPlay: false,
                userName: _userName,
                showWatermark: true,
                existingController: existingController,
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
        return const Center(child: CircularProgressIndicator());

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
                child: CustomPDFViewer(filePath: pdfPath, userName: _userName),
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

        // Show loading indicator while PDF is being prepared
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF323483)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Loading PDF...',
                style: TextStyle(
                  color: Color(0xFF323483),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Module: ${widget.module.title}',
                style: const TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              const Text(
                'This may take a moment depending on your connection',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );

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
            BriffiniWatermark(userName: _userName),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.white,
      // Proper system UI handling
      extendBodyBehindAppBar: false,
      extendBody: false,
      appBar: AppBar(
        title: Text(
          widget.module.title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF323483),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
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
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.folder_open,
                              size: 48,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No content available for this module.',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      );
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
      bottomNavigationBar: CustomBottomNavigation(
        selectedIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          CustomBottomNavigation.handleNavigation(context, index);
        },
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
    return Container(
      width: screenSize.width,
      height: screenSize.height,
      color: Colors.white, // Page background
      child: Stack(
        children: [
          // Main content area with padding
          Padding(
            padding: EdgeInsets.only(
              top: screenSize.height * 0.01,
              bottom: safeAreaBottom + 30, // Reduced space for bottom nav
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User Profile Card - Module Title
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: screenSize.width * 0.04,
                    vertical: screenSize.height * 0.01,
                  ),
                  child: Container(
                    width: double.infinity,
                    height: screenSize.height * 0.08,
                    decoration: BoxDecoration(
                      color: const Color(0xFF323483),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x1F171A1F),
                          offset: Offset(0, 2),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        widget.module.title,
                        style: GoogleFonts.inter(
                          fontSize: isTablet ? 22 : 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: screenSize.height * 0.005),

                // Content Container - Expanded to take more screen space
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: screenSize.width * 0.04,
                    ),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF323483),
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x1A000000),
                            offset: Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: _buildContentView(currentContent),
                      ),
                    ),
                  ),
                ),

                // Navigation row (prev/next) with index indicator
                Padding(
                  padding: EdgeInsets.only(
                    top: screenSize.height * 0.005,
                    left: screenSize.width * 0.05,
                    right: screenSize.width * 0.05,
                    bottom: screenSize.height * 0.005,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Previous button
                      IconButton(
                        onPressed:
                            _currentContentIndex > 0
                                ? () {
                                  setState(() {
                                    _currentContentIndex--;
                                    // Note: Content state manager handles persistence across navigation
                                  });
                                }
                                : null,
                        icon: Icon(
                          Icons.arrow_back,
                          color:
                              _currentContentIndex > 0
                                  ? const Color(0xFF323483)
                                  : Colors.grey,
                          size: 30,
                        ),
                      ),

                      // Progress indicator
                      Text(
                        '${_currentContentIndex + 1}/${contentList.length}',
                        style: GoogleFonts.inter(
                          fontSize: screenSize.width * 0.04,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF2E2C6A),
                        ),
                      ),

                      // Next button
                      IconButton(
                        onPressed:
                            _currentContentIndex < contentList.length - 1
                                ? () {
                                  setState(() {
                                    _currentContentIndex++;
                                    // Note: Content state manager handles persistence across navigation
                                  });
                                }
                                : null,
                        icon: Icon(
                          Icons.arrow_forward,
                          color:
                              _currentContentIndex < contentList.length - 1
                                  ? const Color(0xFF323483)
                                  : Colors.grey,
                          size: 30,
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
    );
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
    // Landscape-optimized layout
    return Container(
      width: screenSize.width,
      height: screenSize.height,
      color: Colors.white,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side: Module title and navigation controls
          Container(
            width: screenSize.width * 0.25,
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                // Module title
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF323483),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F171A1F),
                        offset: Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Text(
                    widget.module.title,
                    style: GoogleFonts.inter(
                      fontSize: isTablet ? 18 : 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),

                const SizedBox(height: 16),

                // Navigation
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (int i = 0; i < contentList.length; i++)
                          ListTile(
                            title: Text(
                              contentList[i].title,
                              style: TextStyle(
                                color:
                                    i == _currentContentIndex
                                        ? const Color(0xFF323483)
                                        : Colors.black87,
                                fontWeight:
                                    i == _currentContentIndex
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                              ),
                            ),
                            selected: i == _currentContentIndex,
                            onTap: () {
                              setState(() {
                                _currentContentIndex = i;
                                // Note: No longer disposing video controllers or resetting PDF state
                                // Content state manager handles persistence across navigation
                              });
                            },
                            leading: Icon(
                              _getContentTypeIcon(contentList[i].contentType),
                              color:
                                  i == _currentContentIndex
                                      ? const Color(0xFF323483)
                                      : Colors.grey,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Right side: Content viewer
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFF323483), width: 1),
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    offset: Offset(0, 2),
                    blurRadius: 4,
                  ),
                ],
              ),
              margin: const EdgeInsets.all(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: _buildContentView(currentContent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper method to get icon for content type
  IconData _getContentTypeIcon(String contentType) {
    switch (contentType) {
      case 'video':
        return Icons.video_library;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'text':
        return Icons.text_snippet;
      default:
        return Icons.article;
    }
  }
}

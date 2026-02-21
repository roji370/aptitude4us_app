import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/course_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/content_update_service.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../utils/route_transitions.dart';
import '../widgets/protected_course_content.dart';
import '../widgets/update_badge.dart';
import 'module_list_screen.dart';

class AssignedCoursesScreen extends StatefulWidget {
  const AssignedCoursesScreen({super.key});

  @override
  State<AssignedCoursesScreen> createState() => _AssignedCoursesScreenState();
}

class _AssignedCoursesScreenState extends State<AssignedCoursesScreen> {
  late Future<List<CourseModel>> _coursesFuture;
  late Future<UserModel?> _userFuture;
  bool _isLoading = true;
  bool _hasLoadedData = false;
  int _totalAssignedCourses = 0; // Track total vs published courses
  final ContentUpdateService _updateService = ContentUpdateService();
  
  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Logger.i("🚀 AssignedCoursesScreen: initState called");

    // Use post-frame callback to ensure the widget is fully built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger.i("🚀 AssignedCoursesScreen: Post-frame callback triggered");

      // Force first frame render for iOS Simulator
      if (mounted) {
        Logger.i("🚀 AssignedCoursesScreen: Ensuring visual update");
        WidgetsBinding.instance.ensureVisualUpdate();
      }

      if (mounted && !_hasLoadedData) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted || _hasLoadedData) {
      Logger.w(
        "⚠️ AssignedCoursesScreen: Skipping _loadData (mounted: $mounted, hasLoadedData: $_hasLoadedData)",
      );
      return;
    }

    Logger.i(
      "🔄 AssignedCoursesScreen: Starting _loadData (optimized for preloaded data)",
    );

    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    setState(() {
      _isLoading = true;
    });

    try {
      // AuthService now handles session restoration internally
      Logger.i(
        "Checking auth state - User: ${authService.currentUser?.uid ?? 'Not logged in'}",
      );

      // Get assigned course IDs directly from custom claims
      final assignedCourseIds = await authService.getAssignedCourseIds();
      Logger.i("📚 Assigned course IDs: $assignedCourseIds");

      // Also get user data for display purposes
      final user = await authService.getUserData();
      Logger.i("👤 User data loaded: ${user?.displayName} (${user?.email})");

      setState(() {
        _userFuture = Future.value(user);

        if (assignedCourseIds.isNotEmpty) {
          Logger.i("🔄 Fetching courses from Firestore...");
          _coursesFuture = firestoreService.getPublishedAssignedCourses(
            assignedCourseIds,
          );
          
          // Also get total assigned courses count for inactive course detection
          _loadTotalCoursesCount(firestoreService, assignedCourseIds);
        } else {
          Logger.w("⚠️ No courses assigned to this user");
          _coursesFuture = Future.value([]);
          _totalAssignedCourses = 0;
        }
      });
    } catch (e) {
      Logger.e("Error loading data: $e");
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      if (mounted) {
        Logger.i("✅ AssignedCoursesScreen: Data loading completed, showing UI");
        setState(() {
          _isLoading = false;
          _hasLoadedData =
              true; // Mark data as loaded to prevent duplicate calls
        });
      }
    }
  }

  // Course card with responsive design and update indicators
  Widget _buildCourseCard(
    CourseModel course,
    BuildContext context,
    String userId,
  ) {
    final horizontalPadding = ResponsiveHelper.getScreenHorizontalPadding(
      context,
    );
    final cardSpacing = ResponsiveHelper.getAdaptiveSpacing(
      context,
      compact: 12.0,
      regular: 16.0,
      pro: 18.0,
      large: 20.0,
      extraLarge: 24.0,
    );
    final borderRadius = ResponsiveHelper.getAdaptiveBorderRadius(
      context,
      compact: 8.0,
      regular: 10.0,
      pro: 12.0,
      large: 12.0,
      extraLarge: 14.0,
    );

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _updateService.getCourseUpdateInfo(course.id, userId),
        _updateService.getTotalCourseUpdateCount(course.id, userId),
      ]),
      builder: (context, snapshot) {
        final updateInfo = snapshot.data?[0] as Map<String, dynamic>?;
        final totalUpdateCount = (snapshot.data?[1] as int?) ?? 0;
        final hasUpdate = updateInfo != null;
        final message = updateInfo?['message'] as String?;

        return GestureDetector(
          onTap: () {
            // Navigate immediately for instant response
            AppNavigator.navigateTo(
              context: context,
              page: ModuleListScreen(course: course),
            ).then((_) {
              if (mounted) setState(() {});
            });
            
            // Mark course as seen in the background (don't await)
            if (hasUpdate) {
              _updateService.markCourseAsSeen(
                course.id,
                userId,
              ).then((_) {
                // Refresh the UI after marking as seen (if still mounted)
                if (mounted) {
                  setState(() {});
                }
              }).catchError((error) {
                Logger.w("Failed to mark course as seen: $error");
              });
            }
          },
          child: Container(
            width: double.infinity,
            margin: EdgeInsets.only(bottom: cardSpacing),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: borderRadius,
              border: Border.all(
                color: const Color(0xFF656BE9),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: ResponsiveHelper.getAdaptiveElevation(context),
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main course card - using Row instead of Stack for better tap detection
                Container(
                  constraints: ResponsiveHelper.getMinTouchTarget(),
                  padding: EdgeInsets.only(
                    left: horizontalPadding.horizontal,
                    right: hasUpdate ? 8 : horizontalPadding.horizontal,
                    top: 12,
                    bottom: 12,
                  ),
                  child: Row(
                    children: [
                      // Left spacer
                      const SizedBox(width: 8),
                      // Course title (centered, takes most space)
                      Expanded(
                        child: Text(
                          course.title,
                          style: GoogleFonts.inter(
                            fontSize: ResponsiveHelper.adaptiveFontSize(
                              context,
                              16.0,
                            ),
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF323483),
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Update indicators (on the right side)
                      if (hasUpdate) ...[
                        const SizedBox(width: 16),
                        UpdateBadge(
                          hasUpdate: true,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        PulsingDot(
                          hasUpdate: true,
                          size: 10,
                        ),
                      ],
                    ],
                  ),
                ),
                // Update message banner (inside the clickable area)
                if (hasUpdate && message != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.only(
                        bottomLeft: borderRadius.bottomLeft,
                        bottomRight: borderRadius.bottomRight,
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Colors.orange[200]!,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.orange[600],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            message,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // New modern course card design matching the UI mockup - MADE 20% MORE COMPACT WITH UNIFORM HEIGHT
  Widget _buildModernCourseCard(
    CourseModel course,
    BuildContext context,
    String userId,
    int index,
  ) {
    // Alternate between blue and light blue gradients
    final backgroundColor = index % 2 == 0
        ? const Color(0xFF1565C0)
        : const Color(0xFF29ACD6);

    // Dynamic font size calculation based on title length
    double getTitleFontSize(String title) {
      final length = title.length;
      if (length <= 20) return 18.0; // Short titles - normal size
      if (length <= 40) return 16.0; // Medium titles - slightly smaller
      return 14.0; // Long titles - smallest
    }

    // Dynamic card height based on title length
    double getCardHeight(String title) {
      final length = title.length;
      if (length <= 40) return 130.0; // Normal height for short/medium titles
      return 145.0; // Taller for long titles
    }

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        _updateService.getCourseUpdateInfo(course.id, userId),
        _updateService.getTotalCourseUpdateCount(course.id, userId),
        Provider.of<FirestoreService>(context, listen: false).getModules(course.id),
      ]),
      builder: (context, snapshot) {
        final updateInfo = snapshot.data?[0] as Map<String, dynamic>?;
        final hasUpdate = updateInfo != null;
        final modules = snapshot.data?[2] as List?;
        final moduleCount = modules?.length ?? 0;

        return GestureDetector(
          onTap: () {
            AppNavigator.navigateTo(
              context: context,
              page: ModuleListScreen(course: course),
            ).then((_) {
              if (mounted) setState(() {});
            });
            
            if (hasUpdate) {
              _updateService.markCourseAsSeen(
                course.id,
                userId,
              ).then((_) {
                if (mounted) {
                  setState(() {});
                }
              }).catchError((error) {
                Logger.w("Failed to mark course as seen: $error");
              });
            }
          },
          child: Container(
            height: getCardHeight(course.title), // Dynamic height based on title length
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Badge strip — always 26px tall, badge right-aligned when present
                SizedBox(
                  height: 26,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: hasUpdate
                          ? IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5.4, vertical: 2.7),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      size: 5.4,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 2.7),
                                    Text(
                                      'NEW',
                                      style: GoogleFonts.inter(
                                        fontSize: 8.1,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                // Main content - horizontal layout
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 2, 19, 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left side - Text content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Course ${index + 1}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // Title with dynamic font size
                              Flexible(
                                child: Text(
                                  course.title,
                                  style: GoogleFonts.inter(
                                    fontSize: getTitleFontSize(course.title),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$moduleCount Module${moduleCount != 1 ? 's' : ''}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right side - Book icon
                        Icon(
                          Icons.book_outlined,
                          size: 50,
                          color: Colors.white.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadTotalCoursesCount(FirestoreService firestoreService, List<String> assignedCourseIds) async {
    try {
      final allCourses = await firestoreService.getAssignedCourses(assignedCourseIds);
      _totalAssignedCourses = allCourses.length;
      Logger.d("Total assigned courses: $_totalAssignedCourses");
    } catch (e) {
      Logger.w("Could not fetch total courses count: $e");
      _totalAssignedCourses = 0;
    }
  }

  Future<void> _refreshAccountData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      
      // Show loading indicator
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Refreshing account data...'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }

      await authService.forceTokenRefresh();

      if (mounted) {
        // Reload the data after token refresh
        setState(() {
          _hasLoadedData = false;
        });
        await _loadData();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Text('Account data refreshed successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    } catch (e) {
      Logger.e('❌ Error refreshing account data: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text('Error refreshing data: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      }
    }
  }

  Widget _buildEmptyCoursesState(Size screenSize, List<CourseModel> courses) {
    // Determine if courses exist but are inactive vs no courses at all
    final bool hasInactiveCourses = _totalAssignedCourses > courses.length;
    
    if (hasInactiveCourses) {
      // Show inactive courses message
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: ResponsiveHelper.adaptiveFontSize(context, 100.0),
                height: ResponsiveHelper.adaptiveFontSize(context, 100.0),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule,
                  size: ResponsiveHelper.adaptiveFontSize(context, 50.0),
                  color: Colors.orange[400],
                ),
              ),
              SizedBox(
                height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 20.0, regular: 24.0),
              ),
              Text(
                'Courses Temporarily Inactive',
                style: GoogleFonts.inter(
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 20.0),
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(
                height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 12.0, regular: 16.0),
              ),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.getAdaptiveSpacing(context, compact: 16.0, regular: 20.0)),
                margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.getAdaptiveSpacing(context, compact: 20.0, regular: 32.0)),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange[200]!, width: 1),
                ),
                child: Column(
                  children: [
                    Text(
                      'Your assigned courses are currently inactive for updates and improvements. They will be available again soon.',
                      style: GoogleFonts.inter(
                        fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                        color: Colors.orange[600],
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 12.0, regular: 16.0)),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.getAdaptiveSpacing(context, compact: 12.0, regular: 16.0),
                        vertical: ResponsiveHelper.getAdaptiveSpacing(context, compact: 8.0, regular: 12.0),
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 16,
                            color: Colors.orange[700],
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Please check back later or contact your instructor for updates.',
                              style: GoogleFonts.inter(
                                fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
                                color: Colors.orange[700],
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
    
    // Show no courses assigned message (existing code)
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: ResponsiveHelper.adaptiveFontSize(context, 100.0),
            height: ResponsiveHelper.adaptiveFontSize(context, 100.0),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.school_outlined,
              size: ResponsiveHelper.adaptiveFontSize(context, 50.0),
              color: Colors.blue[400],
            ),
          ),
          SizedBox(
            height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 20.0, regular: 24.0),
          ),
          Text(
            'No Courses Assigned',
            style: GoogleFonts.inter(
              fontSize: ResponsiveHelper.adaptiveFontSize(context, 20.0),
              fontWeight: FontWeight.bold,
              color: Colors.blue[700],
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(
            height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 12.0, regular: 16.0),
          ),
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.getAdaptiveSpacing(context, compact: 16.0, regular: 20.0)),
            margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.getAdaptiveSpacing(context, compact: 20.0, regular: 32.0)),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.blue[200]!, width: 1),
            ),
            child: Column(
              children: [
                Text(
                  'You don\'t have any courses assigned to your account yet. Contact your administrator or instructor to get courses assigned to start your learning journey.',
                  style: GoogleFonts.inter(
                    fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                    color: Colors.blue[600],
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 12.0, regular: 16.0)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.getAdaptiveSpacing(context, compact: 12.0, regular: 16.0),
                    vertical: ResponsiveHelper.getAdaptiveSpacing(context, compact: 8.0, regular: 12.0),
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.contact_support_outlined,
                        size: 16,
                        color: Colors.blue[700],
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Need help? Contact your administrator',
                        style: GoogleFonts.inter(
                          fontSize: ResponsiveHelper.adaptiveFontSize(context, 12.0),
                          color: Colors.blue[700],
                          fontWeight: FontWeight.w500,
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

  Widget _buildNoSearchResults() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: ResponsiveHelper.adaptiveFontSize(context, 100.0),
              height: ResponsiveHelper.adaptiveFontSize(context, 100.0),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off,
                size: ResponsiveHelper.adaptiveFontSize(context, 50.0),
                color: Colors.grey[400],
              ),
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 20.0, regular: 24.0),
            ),
            Text(
              'No Courses Found',
              style: GoogleFonts.inter(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 20.0),
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 12.0, regular: 16.0),
            ),
            Text(
              'No courses match "${_searchController.text}"',
              style: GoogleFonts.inter(
                fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                color: Colors.grey[600],
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(
              height: ResponsiveHelper.getAdaptiveSpacing(context, compact: 16.0, regular: 20.0),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                });
              },
              icon: Icon(Icons.clear, color: const Color(0xFF4A90E2)),
              label: Text(
                'Clear Search',
                style: GoogleFonts.inter(
                  fontSize: ResponsiveHelper.adaptiveFontSize(context, 14.0),
                  color: const Color(0xFF4A90E2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: ProtectedCourseContent(
        contentTitle: 'Course Library',
        showLoadingSpinner: false,
        child:
            _isLoading
                ? Container(
                  color: const Color(0xFFF5F5F5),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading courses...'),
                      ],
                    ),
                  ),
                )
                : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    color: AppColors.primary,
                    child: FutureBuilder<UserModel?>(
                      future: _userFuture,
                      builder: (context, userSnapshot) {
                        if (userSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (userSnapshot.hasError) {
                          return Center(
                            child: Text('Error: ${userSnapshot.error}'),
                          );
                        }

                        final user = userSnapshot.data;
                        if (user == null) {
                          return const Center(
                            child: Text('No user data available.'),
                          );
                        }

                        return FutureBuilder<List<CourseModel>>(
                          future: _coursesFuture,
                          builder: (context, courseSnapshot) {
                            if (courseSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            if (courseSnapshot.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 80,
                                      color: Colors.redAccent,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Error loading courses',
                                      style: GoogleFonts.inter(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      courseSnapshot.error.toString(),
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: _loadData,
                                      child: Text('Try Again'),
                                    ),
                                  ],
                                ),
                              );
                            }

                            final courses = courseSnapshot.data ?? [];
                            // Sort courses: pinned first, then alphabetically within each group
                            courses.sort((a, b) {
                              // If one is pinned and the other isn't, pinned comes first
                              if (a.isPinned && !b.isPinned) return -1;
                              if (!a.isPinned && b.isPinned) return 1;
                              // If both have same pinned status, sort alphabetically
                              return a.title.toLowerCase().compareTo(b.title.toLowerCase());
                            });
                            
                            // Filter courses based on search query
                            final filteredCourses = _searchQuery.isEmpty
                                ? courses
                                : courses.where((course) {
                                    return course.title.toLowerCase().contains(_searchQuery);
                                  }).toList();
                            
                            Logger.i(
                              "📋 Course data received: ${courses.length} courses (${filteredCourses.length} after filtering)",
                            );
                            Logger.i(
                              "🎨 AssignedCoursesScreen: Building main UI with ${filteredCourses.length} courses${_searchQuery.isNotEmpty ? ' (filtered)' : ' (sorted alphabetically)'}",
                            );

                            // Get first name from display name
                            final firstName = user.displayName.split(' ').first;
                            
                            // Get current date
                            final now = DateTime.now();
                            final weekday = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][now.weekday - 1];
                            final day = now.day;
                            final month = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'][now.month - 1];

                            return Container(
                              color: const Color(0xFFF5F5F5),
                              child: GestureDetector(
                                onTap: () {
                                  // Dismiss keyboard when tapping outside
                                  FocusScope.of(context).unfocus();
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                  // Header Section
                                  Container(
                                    color: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13), // Reduced from 16 (20% reduction)
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Logo and Profile Row
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            // Logo - UPDATED TO USE CUSTOM IMAGE
                                            Row(
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.circular(8),
                                                    child: Image.asset(
                                                      'assets/images/xfini_logo.png', // Your custom logo path
                                                      width: 40,
                                                      height: 40,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Text(
                                                  'XFINI ACADEMY',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            // Profile Picture
                                            Stack(
                                              children: [
                                                Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.grey[300]!,
                                                      width: 2,
                                                    ),
                                                    image: user.photoUrl != null && user.photoUrl!.isNotEmpty
                                                        ? DecorationImage(
                                                            image: NetworkImage(user.photoUrl!),
                                                            fit: BoxFit.cover,
                                                          )
                                                        : null,
                                                  ),
                                                  child: user.photoUrl == null || user.photoUrl!.isEmpty
                                                      ? Icon(
                                                          Icons.person,
                                                          size: 28,
                                                          color: Colors.grey[400],
                                                        )
                                                      : null,
                                                ),
                                                // Online indicator
                                                Positioned(
                                                  right: 0,
                                                  bottom: 0,
                                                  child: Container(
                                                    width: 14,
                                                    height: 14,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF4CAF50),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(
                                                        color: Colors.white,
                                                        width: 2,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 11), // Reduced from 14 (20% reduction)
                                        // Date and Greeting Row
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.wb_sunny_outlined,
                                              size: 16,
                                              color: Colors.grey[600],
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '$weekday $day $month',
                                              style: GoogleFonts.inter(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6), // Reduced from 7 (20% reduction)
                                        // Greeting and Refresh
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'Hi, $firstName',
                                              style: GoogleFonts.inter(
                                                fontSize: 28,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            Container(
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: const Color(0xFF4A90E2),
                                                  width: 1.5,
                                                ),
                                                borderRadius: BorderRadius.circular(20),
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: _refreshAccountData,
                                                  borderRadius: BorderRadius.circular(20),
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 6,
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(
                                                          Icons.refresh,
                                                          size: 16,
                                                          color: const Color(0xFF4A90E2),
                                                        ),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          'Refresh',
                                                          style: GoogleFonts.inter(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.w600,
                                                            color: const Color(0xFF4A90E2),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 14), // Reduced from 18 (20% reduction)
                                        // Search Bar - WITH BORDER AND FOCUSED STATE
                                        Container(
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: Colors.grey[100],
                                            borderRadius: BorderRadius.circular(24),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(0.03),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: TextField(
                                            controller: _searchController,
                                            onChanged: (value) {
                                              setState(() {
                                                _searchQuery = value.toLowerCase();
                                              });
                                            },
                                            decoration: InputDecoration(
                                              hintText: 'Search courses',
                                              hintStyle: GoogleFonts.inter(
                                                fontSize: 15,
                                                color: Colors.grey[400],
                                              ),
                                              prefixIcon: Icon(
                                                Icons.search,
                                                color: Colors.grey[400],
                                                size: 20,
                                              ),
                                              suffixIcon: _searchQuery.isNotEmpty
                                                  ? IconButton(
                                                      icon: Icon(
                                                        Icons.clear,
                                                        color: Colors.grey[400],
                                                        size: 20,
                                                      ),
                                                      onPressed: () {
                                                        setState(() {
                                                          _searchController.clear();
                                                          _searchQuery = '';
                                                        });
                                                      },
                                                    )
                                                  : null,
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(24),
                                                borderSide: BorderSide(
                                                  color: Colors.grey[300]!,
                                                  width: 1,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(24),
                                                borderSide: BorderSide(
                                                  color: const Color(0xFF4A90E2),
                                                  width: 2,
                                                ),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.circular(24),
                                                borderSide: BorderSide(
                                                  color: Colors.grey[300]!,
                                                  width: 1,
                                                ),
                                              ),
                                              contentPadding: const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 12,
                                              ),
                                              filled: true,
                                              fillColor: Colors.transparent,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  
                                  // Your Courses Section - MADE 20% MORE COMPACT
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16), // Reduced from 20
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 12), // Reduced from 16
                                          Text(
                                            'Your Courses',
                                            style: GoogleFonts.inter(
                                              fontSize: 17, // Reduced from 20
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 10), // Reduced from 12
                                          // Courses List
                                          Expanded(
                                            child: filteredCourses.isEmpty
                                                ? _searchQuery.isNotEmpty
                                                    ? _buildNoSearchResults()
                                                    : _buildEmptyCoursesState(MediaQuery.of(context).size, courses)
                                                : ListView.builder(
                                                    physics: const AlwaysScrollableScrollPhysics(),
                                                    itemCount: filteredCourses.length,
                                                    itemBuilder: (context, index) {
                                                      return _buildModernCourseCard(
                                                        filteredCourses[index],
                                                        context,
                                                        user.uid,
                                                        index,
                                                      );
                                                    },
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
      ),
    );
  }
}
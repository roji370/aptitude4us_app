import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/course_model.dart';
import '../models/user_model.dart';
import '../providers/session_provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/content_update_service.dart';
import '../utils/app_colors.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
import '../utils/route_transitions.dart';
import '../widgets/protected_course_content.dart';

import 'module_list_screen.dart';

class AssignedCoursesScreen extends StatefulWidget {
  const AssignedCoursesScreen({super.key});

  @override
  State<AssignedCoursesScreen> createState() => _AssignedCoursesScreenState();
}

class _AssignedCoursesScreenState extends State<AssignedCoursesScreen> {
  // ── Resolved data fields (no FutureBuilders needed) ──
  UserModel? _user;
  List<CourseModel> _courses = [];
  bool _isLoading = true;
  bool _hasLoadedData = false;
  int _totalAssignedCourses = 0;

  // ── Concurrency / freshness ──
  int _loadToken = 0;
  int _loadedGeneration = -1;

  final ContentUpdateService _updateService = ContentUpdateService();
  final Map<String, int> _moduleCounts = {};

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    Logger.i("🚀 AssignedCoursesScreen: initState called");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_hasLoadedData) {
        _loadedGeneration =
            context.read<SessionProvider>().dataGeneration;
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Silent reload on generation change ──

  /// Called from build() when dataGeneration changes after data has already
  /// been loaded once. Reloads without showing a spinner. On failure,
  /// restores the previous generation so the next bump retries.
  ///
  /// No explicit retry cap: generation bumps only come from
  /// [SessionProvider.refreshAll] (stale-resume ≥15 min) or explicit
  /// pull-to-refresh, so the natural cadence is at most ~1 retry per
  /// resume cycle. If this ever changes (e.g., a push notification bumps
  /// generation), add a cap here.
  Future<void> _silentReload(int generation) async {
    final previousGeneration = _loadedGeneration;
    _loadedGeneration = generation; // set before await to prevent re-entry
    final success = await _loadData(silent: true);
    if (!success && mounted && _loadedGeneration == generation) {
      _loadedGeneration = previousGeneration;
    }
  }

  // ── Data loading ──

  /// Returns true on success, false on failure.
  ///
  /// [silent]: don't show loading spinner (used by _silentReload).
  /// [force]: bypass the _hasLoadedData guard (used by pull-to-refresh).
  Future<bool> _loadData({bool silent = false, bool force = false}) async {
    if (!mounted) return false;
    if (!silent && !force && _hasLoadedData) return true;

    final thisLoadToken = ++_loadToken;

    if (!silent && !force) {
      setState(() { _isLoading = true; });
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService =
        Provider.of<FirestoreService>(context, listen: false);

    try {
      // On pull-to-refresh, refresh claims to pick up new assignments.
      // Uses the shared 60s cooldown so rapid pulls don't spam Firebase.
      if (force) {
        try {
          await authService.refreshClaimsIfAllowed();
        } catch (e) {
          Logger.w('Token refresh on pull-to-refresh failed (non-fatal): $e');
        }
      }

      final assignedCourseIds = await authService.getAssignedCourseIds();
      Logger.i("📚 Assigned course IDs: $assignedCourseIds");

      late UserModel? user;
      late List<CourseModel> courses;
      late int totalCount;

      if (assignedCourseIds.isNotEmpty) {
        // Parallel fetches: user data, published courses, and total count.
        // Count query has catchError — cosmetic only; used to detect
        // inactive courses (totalAssigned > publishedAssigned). The
        // fallback (assignedCourseIds.length from claims) may differ from
        // the Firestore doc count if claims contain stale/orphaned IDs,
        // but this only matters during a transient Firestore failure and
        // only affects whether the "inactive courses" banner shows.
        final results = await Future.wait([
          authService.getUserData(),
          firestoreService.getPublishedAssignedCourses(assignedCourseIds),
          firestoreService
              .getAssignedCourses(assignedCourseIds)
              .then((c) => c.length)
              .catchError((_) => assignedCourseIds.length),
        ]);
        user = results[0] as UserModel?;
        courses = results[1] as List<CourseModel>;
        totalCount = results[2] as int;
      } else {
        Logger.w("⚠️ No courses assigned to this user");
        user = await authService.getUserData();
        courses = [];
        totalCount = 0;
      }

      // Stale-load guard: discard if a newer load was started
      if (!mounted || thisLoadToken != _loadToken) return false;

      setState(() {
        _user = user;
        _courses = courses;
        _totalAssignedCourses = totalCount;
        _isLoading = false;
        _hasLoadedData = true;
      });

      // Kick off badge refresh and module count fetch in the background.
      if (user != null && courses.isNotEmpty) {
        final courseIds = courses.map((c) => c.id).toList();
        // Badge refresh (concurrency-capped, fires ValueNotifier updates)
        unawaited(
          _updateService.refreshAllCourseBadges(courseIds, user.uid),
        );
        // Module counts — one query per course, results cached in _moduleCounts.
        // This replaces the old per-card FutureBuilder that re-fetched on every
        // rebuild. Errors are swallowed (card falls back to 0).
        unawaited(
          Future.wait(
            courses.map((c) => firestoreService.getModules(c.id).then(
              (modules) {
                if (mounted) {
                  setState(() {
                    _moduleCounts[c.id] = modules.length;
                  });
                }
              },
            ).catchError((_) {})),
          ),
        );
      }

      return true;
    } catch (e) {
      Logger.e("Error loading data: $e");
      if (!mounted || thisLoadToken != _loadToken) return false;
      if (!silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
      setState(() { _isLoading = false; _hasLoadedData = true; });
      return false;
    }
  }

  // Modern course card with bottom-up badge from ValueNotifier
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
      if (length <= 20) return 18.0;
      if (length <= 40) return 16.0;
      return 14.0;
    }

    // Dynamic card height based on title length
    double getCardHeight(String title) {
      final length = title.length;
      if (length <= 40) return 130.0;
      return 145.0;
    }

    return ValueListenableBuilder<bool>(
      valueListenable: _updateService.courseBadgeNotifier(course.id),
      builder: (context, hasUpdate, _) {
        return GestureDetector(
          onTap: () {
            AppNavigator.navigateTo(
              context: context,
              page: ModuleListScreen(course: course),
            ).then((_) {
              if (!mounted) return;
              // Zero-read memory derivation: re-compute badge from the
              // last server refresh's unseen set minus items seen this
              // session. No Firestore reads.
              _updateService.refreshCourseBadgeFromMemory(course.id);
            });
          },
          child: Container(
            height: getCardHeight(course.title),
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5.4,
                                  vertical: 2.7,
                                ),
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
                                      'UPDATE',
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
                                '${_moduleCounts[course.id] ?? 0} Module${(_moduleCounts[course.id] ?? 0) != 1 ? 's' : ''}',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
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

  /// Manual refresh button handler. Uses the same _loadData(force: true)
  /// path as pull-to-refresh, which calls refreshClaimsIfAllowed internally.
  Future<void> _refreshAccountData() async {
    await _loadData(force: true);
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
    // Track data generation — triggers silent reload on stale-resume.
    final dataGeneration = context.select<SessionProvider, int>(
      (s) => s.dataGeneration,
    );

    if (_hasLoadedData && dataGeneration != _loadedGeneration) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _hasLoadedData && dataGeneration != _loadedGeneration) {
          _silentReload(dataGeneration);
        }
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: ProtectedCourseContent(
        contentTitle: 'Course Library',
        showLoadingSpinner: false,
        child: _isLoading
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
                  onRefresh: () => _loadData(force: true),
                  color: AppColors.primary,
                  child: _user == null
                      ? const Center(
                          child: Text('No user data available.'),
                        )
                      : _buildCourseList(),
                ),
              ),
      ),
    );
  }

  /// Main course list UI — extracted from the old nested FutureBuilders.
  /// Now reads from resolved fields (_user, _courses) instead of Futures.
  Widget _buildCourseList() {
    final user = _user!;
    final courses = List<CourseModel>.from(_courses);

    // Sort courses: pinned first, then alphabetically within each group
    courses.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });

    // Filter courses based on search query
    final filteredCourses = _searchQuery.isEmpty
        ? courses
        : courses
            .where((course) =>
                course.title.toLowerCase().contains(_searchQuery))
            .toList();

    // Get first name from display name
    final firstName = user.displayName.split(' ').first;

    // Get current date
    final now = DateTime.now();
    final weekday = [
      'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'
    ][now.weekday - 1];
    final day = now.day;
    final month = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'
    ][now.month - 1];

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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Logo and Profile Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo
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
                                'assets/images/xfini_logo.png',
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
                              image: user.photoUrl != null &&
                                      user.photoUrl!.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(user.photoUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: user.photoUrl == null ||
                                    user.photoUrl!.isEmpty
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
                  const SizedBox(height: 11),
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
                  const SizedBox(height: 6),
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
                  const SizedBox(height: 14),
                  // Search Bar
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

            // Your Courses Section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Your Courses',
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Courses List
                    Expanded(
                      child: filteredCourses.isEmpty
                          ? _searchQuery.isNotEmpty
                              ? _buildNoSearchResults()
                              : _buildEmptyCoursesState(
                                  MediaQuery.of(context).size, courses)
                          : ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
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
  }
}
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/content_update_service.dart';
import '../utils/logger.dart';
import '../utils/route_transitions.dart';
import '../widgets/custom_bottom_navigation.dart';
import 'content_types_screen.dart';

class ModuleListScreen extends StatefulWidget {
  final CourseModel course;
  final bool isExamOverviewMode; // True when navigating from first-time login

  const ModuleListScreen({
    super.key, 
    required this.course,
    this.isExamOverviewMode = false,
  });

  @override
  State<ModuleListScreen> createState() => _ModuleListScreenState();
}

class _ModuleListScreenState extends State<ModuleListScreen> {
  Future<List<ModuleModel>> _modulesFuture = Future.value([]);
  bool _isLoading = true;
  int _selectedIndex = 0;
  Map<String, dynamic> _customClaims = {};
  int _totalModulesCount = 0;
  final ContentUpdateService _updateService = ContentUpdateService();
  String? _currentUserId;
  // Incremented after returning from ContentTypesScreen to force re-fetch.
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _loadUserClaimsAndModules();
  }

  Future<void> _loadUserClaimsAndModules() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final firestoreService = Provider.of<FirestoreService>(
      context,
      listen: false,
    );

    setState(() {
      _isLoading = true;
    });

    try {
      // Get current user ID
      _currentUserId = authService.currentUser?.uid;

      // In exam overview mode, new users haven't had their custom claims set up yet.
      // Skip the claims/permission checks and fetch modules directly from Firestore.
      if (widget.isExamOverviewMode) {
        Logger.i('ExamOverviewMode: skipping claims check, fetching modules directly');
        final courseId = widget.course.id;
        setState(() {
          _modulesFuture = firestoreService.getPublishedModules(courseId);
        });
        await _modulesFuture;
        return;
      }

      // Get custom claims to check for module access permissions
      _customClaims = await authService.getCustomClaims();
      Logger.d("Custom claims: $_customClaims");

      // Check if the course is in the user's assigned courses
      final assignedCourseIds = await authService.getAssignedCourseIds();
      final courseId = widget.course.id;

      if (!assignedCourseIds.contains(courseId)) {
        Logger.w("Warning: User does not have this course in their claims");
      }

      // Check if there's specific module permissions in the claims
      Map<String, dynamic>? assignedModules =
          _customClaims['assignedModules'] as Map<String, dynamic>?;
      List<String>? allowedModuleIds;

      if (assignedModules != null && assignedModules.containsKey(courseId)) {
        // Get specific modules allowed for this course
        var moduleData = assignedModules[courseId];
        if (moduleData is List) {
          allowedModuleIds = moduleData.cast<String>();
        } else if (moduleData is Map) {
          allowedModuleIds = moduleData.keys.toList().cast<String>();
        }

        Logger.d("Allowed module IDs from claims: $allowedModuleIds");
      }

      // Fetch published modules
      setState(() {
        _modulesFuture = firestoreService.getPublishedModules(courseId);
      });

      final modules = await _modulesFuture;
      
      // Also check total modules count to distinguish between no modules vs inactive modules
      try {
        final allModules = await firestoreService.getModules(courseId);
        _totalModulesCount = allModules.length;
        Logger.d("Total modules: $_totalModulesCount, Published modules: ${modules.length}");
      } catch (e) {
        Logger.w("Could not fetch total modules count: $e");
        _totalModulesCount = modules.length;
      }

      // If we have specific module permissions, we should filter the modules
      if (allowedModuleIds != null && allowedModuleIds.isNotEmpty) {
        Logger.i("Filtering modules by claims permissions");
        final filteredModules =
            modules
                .where((module) => allowedModuleIds!.contains(module.id))
                .toList();

        // Update the future to return the filtered modules
        setState(() {
          _modulesFuture = Future.value(filteredModules);
        });
      }

      // Mark course-level docs as seen on entry
      if (_currentUserId != null) {
        _updateService
            .markCourseLevelDocsSeen(widget.course.id, _currentUserId!)
            .catchError(
              (e) => Logger.w('Failed to mark course-level docs as seen: $e'),
            );
      }
    } catch (e) {
      Logger.e("Error loading custom claims and modules: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    CustomBottomNavigation.handleNavigation(context, index);
  }

  // Dynamic font size calculation based on title length
  double _getTitleFontSize(String title) {
    final length = title.length;
    if (length <= 20) return 18.0; // Short titles - normal size
    if (length <= 40) return 16.0; // Medium titles - slightly smaller
    return 14.0; // Long titles - smallest
  }

  // Dynamic card height based on title length
  double _getCardHeight(String title) {
    final length = title.length;
    if (length <= 40) return 130.0; // Normal height for short/medium titles
    return 145.0; // Taller for long titles
  }


  Widget _buildEmptyModulesState(Size screenSize) {
    // Determine if modules exist but are inactive vs no modules at all
    final bool hasInactiveModules = _totalModulesCount > 0;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: screenSize.width * 0.25,
              height: screenSize.width * 0.25,
              decoration: BoxDecoration(
                color: hasInactiveModules ? Colors.orange[50] : Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasInactiveModules ? Icons.schedule : Icons.book_outlined,
                size: screenSize.width * 0.12,
                color: hasInactiveModules ? Colors.orange[400] : Colors.grey[400],
              ),
            ),
            SizedBox(height: 24),
            Text(
              hasInactiveModules 
                ? 'Modules Currently Inactive'
                : 'No Modules Available',
              style: GoogleFonts.inter(
                fontSize: screenSize.width * 0.05,
                color: hasInactiveModules ? Colors.orange[700] : Colors.grey[700],
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: hasInactiveModules ? Colors.orange[50] : Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasInactiveModules ? Colors.orange[200]! : Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    hasInactiveModules
                      ? 'This course has modules, but they are currently not active. The modules may be scheduled for future release or are temporarily unavailable.'
                      : 'This course doesn\'t have any modules yet. New modules will appear here when they become available.',
                    style: GoogleFonts.inter(
                      fontSize: screenSize.width * 0.035,
                      color: hasInactiveModules ? Colors.orange[600] : Colors.grey[600],
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (hasInactiveModules) ...[
                    SizedBox(height: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Colors.orange[600],
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Contact your instructor for more information about when these modules will be available.',
                            style: GoogleFonts.inter(
                              fontSize: screenSize.width * 0.032,
                              color: Colors.orange[600],
                              fontStyle: FontStyle.italic,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return PopScope(
      // Allow back navigation when not in exam overview mode
      canPop: !widget.isExamOverviewMode,
      // Show message when navigation is blocked
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
        appBar: AppBar(
          backgroundColor: Colors.grey[50],
          elevation: 0,
          leading: widget.isExamOverviewMode 
            ? null // Hide back button during exam overview
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
          title: Text(
            widget.course.title,
            style: GoogleFonts.inter(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : FutureBuilder<List<ModuleModel>>(
                  future: _modulesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final modules = snapshot.data ?? [];
                    // Sort modules alphabetically by title
                    modules.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

                    return Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Modules Header
                                Text(
                                  'Modules',
                                  style: GoogleFonts.inter(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                
                                // Module Cards
                                if (modules.isEmpty)
                                  _buildEmptyModulesState(screenSize)
                                else
                                  ...modules.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final module = entry.value;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: _buildModernModuleCard(module, index),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
      bottomNavigationBar: widget.isExamOverviewMode 
        ? null // Hide bottom navigation during exam overview
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

  /// Build modern module card. Badge is derived from hasModuleUpdate.
  Widget _buildModernModuleCard(ModuleModel module, int index) {
    // Alternate between blue and light blue backgrounds
    final backgroundColor = index % 2 == 0
        ? const Color(0xFF1565C0)
        : const Color(0xFF29ACD6);

    return FutureBuilder<bool>(
      key: ValueKey('${module.id}_$_refreshKey'),
      future: _currentUserId != null
          ? _updateService.hasModuleUpdate(
              widget.course.id,
              module.id,
              _currentUserId!,
            )
          : Future.value(false),
      builder: (context, snapshot) {
        final hasUpdate = snapshot.data ?? false;

        return GestureDetector(
          onTap: () {
            AppNavigator.navigateTo(
              context: context,
              page: ContentTypesScreen(
                course: widget.course,
                module: module,
                isExamOverviewMode: widget.isExamOverviewMode,
              ),
            ).then((_) {
              if (!mounted) return;
              // Force re-fetch of badge state for all modules.
              _refreshKey++;
              setState(() {});
            });
          },
          child: Container(
            width: double.infinity,
            height: _getCardHeight(module.title),
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
                // Badge strip — always 28px tall, badge right-aligned when present
                SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: hasUpdate
                          ? _buildUpdateBadgePill()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
                // Main content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
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
                                'Module ${index + 1}',
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Flexible(
                                child: Text(
                                  module.title,
                                  style: GoogleFonts.inter(
                                    fontSize: _getTitleFontSize(module.title),
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    height: 1.2,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right side - Grid icon
                        _buildModuleGridIcon(),
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

  /// The standard "UPDATE" badge pill.
  Widget _buildUpdateBadgePill() {
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7.2, vertical: 3.6),
        decoration: BoxDecoration(
          color: Colors.orange,
          borderRadius: BorderRadius.circular(10.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.circle,
              size: 7.2,
              color: Colors.white,
            ),
            const SizedBox(width: 3.6),
            Text(
              'UPDATE',
              style: GoogleFonts.inter(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the grid icon for module cards
  Widget _buildModuleGridIcon() {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Transform.rotate(
                angle: 0.785398, // 45 degrees in radians
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.transparent),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/content_update_service.dart';
import '../utils/app_colors.dart';
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
        backgroundColor: AppColors.surface,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          leading: widget.isExamOverviewMode 
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: AppColors.onSurface),
                onPressed: () => Navigator.of(context).pop(),
              ),
          title: Text(
            widget.course.title,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator(color: AppColors.secondary))
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
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.onSurface,
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

  /// Build modern module card — Stitch design with accent strip.
  Widget _buildModernModuleCard(ModuleModel module, int index) {
    final accentColor = index % 2 == 0
        ? AppColors.primary
        : AppColors.secondary;

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
              _refreshKey++;
              setState(() {});
            });
          },
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Positioned(
                  left: 0, top: 0, bottom: 0,
                  child: Container(width: 6, color: accentColor),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              module.title,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                                letterSpacing: 0.14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Module ${index + 1}',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasUpdate)
                        _buildUpdateBadgePill(),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.outline,
                        size: 20,
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

  /// Teal update badge pill.
  Widget _buildUpdateBadgePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 6, color: AppColors.onSecondaryContainer),
          const SizedBox(width: 4),
          Text(
            'New',
            style: GoogleFonts.inter(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
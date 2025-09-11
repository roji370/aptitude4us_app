import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../models/course_model.dart';
import '../models/module_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../utils/logger.dart';
import '../utils/route_transitions.dart';
import '../widgets/custom_bottom_navigation.dart';
import 'content_viewer_screen_mobile.dart';

class ModuleListScreen extends StatefulWidget {
  final CourseModel course;

  const ModuleListScreen({super.key, required this.course});

  @override
  State<ModuleListScreen> createState() => _ModuleListScreenState();
}

class _ModuleListScreenState extends State<ModuleListScreen> {
  late Future<List<ModuleModel>> _modulesFuture;
  bool _isLoading = true;
  int _selectedIndex = 0; // For bottom navigation
  Map<String, dynamic> _customClaims = {}; // Store user's custom claims

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

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    // Color Scheme:
    // - Background: #FFFFFF (White)
    // - User Profile Card:
    //   - Background: #323483 (Dark Blue)
    //   - Border: #C9C8D8 (Light Grayish-Purple)
    //   - Text: #FFFFFF (White)
    // - Module Container:
    //   - Background: #FFFFFF (White)
    //   - Border: #656BE9 (Bright Blue)
    //   - Text: #2E2C6A (Dark Purple)
    //   - Play Button: #171A1F (Dark Gray)
    // - Bottom Navigation Bar:
    //   - Background: #FFFFFF (White)
    //   - Icons:
    //     - Unselected: #565E6C (Neutral Gray)
    //     - Selected: #778FF0 (Light Blue)

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          widget.course.title,
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
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                child: FutureBuilder<List<ModuleModel>>(
                  future: _modulesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}'));
                    }

                    final modules = snapshot.data ?? [];

                    return Container(
                      width: screenSize.width,
                      height: screenSize.height,
                      color: Colors.white,
                      child: Stack(
                        children: [
                          // Content area with scroll
                          SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Padding(
                              padding: EdgeInsets.only(
                                top: safeAreaTop + 16,
                                bottom:
                                    100 +
                                    safeAreaBottom, // Space for bottom nav
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // User Profile Card
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: screenSize.width * 0.05,
                                    ),
                                    child: Container(
                                      width: double.infinity,
                                      height: screenSize.height * 0.15,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF323483),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFFC9C8D8),
                                          width: 1,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x1F171A1F),
                                            offset: Offset(0, 0),
                                            blurRadius: 2,
                                          ),
                                          BoxShadow(
                                            color: Color(0x12171A1F),
                                            offset: Offset(0, 0),
                                            blurRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Center(
                                        child: Text(
                                          widget.course.title,
                                          style: GoogleFonts.archivo(
                                            fontSize: screenSize.width * 0.06,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),

                                  SizedBox(height: screenSize.height * 0.04),

                                  // Modules List
                                  modules.isEmpty
                                      ? Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.book_outlined,
                                              size: screenSize.width * 0.2,
                                              color: Colors.grey,
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'No modules available for this course.',
                                              style: GoogleFonts.inter(
                                                fontSize:
                                                    screenSize.width * 0.045,
                                                color: Colors.grey[600],
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      )
                                      : Column(
                                        children:
                                            modules.map((module) {
                                              return Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: 16,
                                                  left: screenSize.width * 0.05,
                                                  right:
                                                      screenSize.width * 0.05,
                                                ),
                                                child: Container(
                                                  width: double.infinity,
                                                  height:
                                                      screenSize.height * 0.085,
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          10,
                                                        ),
                                                    border: Border.all(
                                                      color: const Color(
                                                        0xFF656BE9,
                                                      ),
                                                      width: 2,
                                                    ),
                                                    boxShadow: const [
                                                      BoxShadow(
                                                        color: Color(
                                                          0x26171A1F,
                                                        ),
                                                        offset: Offset(0, 8),
                                                        blurRadius: 17,
                                                      ),
                                                      BoxShadow(
                                                        color: Color(
                                                          0x1F171A1F,
                                                        ),
                                                        offset: Offset(0, 0),
                                                        blurRadius: 2,
                                                      ),
                                                    ],
                                                  ),
                                                  child: Material(
                                                    color: Colors.transparent,
                                                    child: InkWell(
                                                      onTap: () {
                                                        // Navigate to content viewer
                                                        AppNavigator.navigateTo(
                                                          context: context,
                                                          page:
                                                              ContentViewerScreen(
                                                                course:
                                                                    widget
                                                                        .course,
                                                                module: module,
                                                              ),
                                                        );
                                                      },
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            10,
                                                          ),
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 24,
                                                            ),
                                                        child: Row(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .spaceBetween,
                                                          children: [
                                                            Expanded(
                                                              child: Text(
                                                                module.title,
                                                                style: GoogleFonts.inter(
                                                                  fontSize:
                                                                      screenSize
                                                                          .width *
                                                                      0.05,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w400,
                                                                  color: const Color(
                                                                    0xFF2E2C6A,
                                                                  ),
                                                                ),
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                              ),
                                                            ),
                                                            const Icon(
                                                              Icons.play_arrow,
                                                              color: Color(
                                                                0xFF171A1F,
                                                              ),
                                                              size: 24,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                      ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
}

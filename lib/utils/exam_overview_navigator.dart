import 'package:flutter/material.dart';
import '../models/course_model.dart';
import '../services/firestore_service.dart';
import '../screens/module_list_screen.dart';
import '../utils/logger.dart';
import '../utils/route_transitions.dart';

/// Utility class for navigating to the Exam Overview module
/// 
/// This class provides methods to navigate users to the Exam Overview course,
/// which is typically shown on first login or when users need to review exam guidelines.
class ExamOverviewNavigator {
  /// Course ID for Exam Overview (unique identifier)
  static const String examOverviewCourseId = 'GEN-0901-Wbpk';
  
  /// Course title for Exam Overview (for display/logging purposes only)
  static const String examOverviewCourseTitle = 'Exam Overview';
  
  /// Module name for Exam Overview (for reference)
  static const String examOverviewModuleName = 'Exam Overview';
  
  /// Navigate directly to the Exam Overview course
  /// 
  /// This method:
  /// 1. Retrieves all available courses from Firestore
  /// 2. Finds the Exam Overview course by matching the title
  /// 3. Navigates to the module list screen for that course
  /// 4. User can then select which module to watch
  /// 
  /// Parameters:
  /// - [context]: BuildContext for navigation
  /// - [firestoreService]: Service instance for Firestore operations
  /// 
  /// Returns:
  /// - true if navigation was successful
  /// - false if navigation failed or context was not mounted
  /// 
  /// Throws:
  /// - Shows error dialog to user if course cannot be found
  static Future<bool> navigateToExamOverview(
    BuildContext context,
    FirestoreService firestoreService,
  ) async {
    try {
      Logger.i('📚 Starting navigation to Exam Overview');
      Logger.i('🔍 Looking for course with ID: "$examOverviewCourseId"');
      
      // Step 1: Get all courses from Firestore
      final courses = await firestoreService.getCourses();
      Logger.i('📋 Total courses retrieved: ${courses.length}');
      
      // Validate that courses were retrieved
      if (courses.isEmpty) {
        throw Exception(
          'No courses available. Please ensure:\n'
          '1. You have an active internet connection\n'
          '2. Courses have been assigned to your account\n'
          '3. You are properly logged in'
        );
      }
      
      // Debug: Log all available course IDs and titles for troubleshooting
      Logger.i('📚 Available courses:');
      for (var course in courses) {
        Logger.i('  - ID: "${course.id}", Title: "${course.title}"');
        
        // Highlight if this is the Exam Overview course
        if (course.id == examOverviewCourseId) {
          Logger.i('    ⭐ This is the Exam Overview course!');
        }
      }
      
      // Step 2: Find the Exam Overview course by ID
      // Using exact ID match for most reliable identification
      final examOverviewCourse = courses.firstWhere(
        (course) => course.id == examOverviewCourseId,
        orElse: () {
          // Course not found - log detailed error information
          Logger.e('❌ Course with ID "$examOverviewCourseId" not found');
          Logger.e('Available IDs: ${courses.map((c) => '"${c.id}"').join(", ")}');
          
          throw Exception(
            'Exam Overview course not found.\n\n'
            'Expected course ID: "$examOverviewCourseId"\n'
            'Available courses: ${courses.length}\n\n'
            'Please ensure:\n'
            '• The course exists in Firestore\n'
            '• The course is published (isPublished: true)\n'
            '• The course is assigned to your account\n'
            '• The course ID matches: "$examOverviewCourseId"'
          );
        },
      );
      
      // Log successful course retrieval
      Logger.i('✅ Found Exam Overview course:');
      Logger.i('   - ID: ${examOverviewCourse.id}');
      Logger.i('   - Title: ${examOverviewCourse.title}');
      Logger.i('   - Description: ${examOverviewCourse.description}');
      
      // Step 3: Validate context before navigation
      if (!context.mounted) {
        Logger.w('⚠️ Context not mounted, cannot navigate');
        return false;
      }
      
      // Step 4: Navigate to the module list screen for this course
      // Use pushReplacement to prevent back navigation to splash screen
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ModuleListScreen(
            course: examOverviewCourse,
            isExamOverviewMode: true, // Lock user into exam overview flow
          ),
        ),
      );
      
      Logger.i('✅ Successfully navigated to Exam Overview course');
      return true;
      
    } catch (e, stackTrace) {
      // Log detailed error information
      Logger.e('❌ Error navigating to Exam Overview: $e');
      Logger.e('Stack trace: $stackTrace');
      
      // Check if context is still valid before showing dialog
      if (!context.mounted) return false;
      
      // Show user-friendly error dialog with detailed information
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Unable to Load Exam Overview'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The Exam Overview course could not be loaded.',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'This could be because:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• The course has not been published yet'),
                      Text('• The course has not been assigned to you'),
                      Text('• There is a network connectivity issue'),
                      Text('• The course title has been changed'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Please contact your administrator for assistance.',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                ExpansionTile(
                  title: const Text(
                    'Technical Details',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        e.toString(),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      
      return false;
    }
  }
  
  /// Check if the Exam Overview course exists and is accessible
  /// 
  /// This method can be used to validate the setup before attempting navigation,
  /// or to conditionally show UI elements based on course availability.
  /// 
  /// Parameters:
  /// - [firestoreService]: Service instance for Firestore operations
  /// 
  /// Returns:
  /// - true if the Exam Overview course exists and is accessible
  /// - false if the course cannot be found or an error occurs
  static Future<bool> examOverviewExists(
    FirestoreService firestoreService,
  ) async {
    try {
      Logger.i('🔍 Checking if Exam Overview course exists...');
      
      final courses = await firestoreService.getCourses();
      
      if (courses.isEmpty) {
        Logger.w('⚠️ No courses available when checking Exam Overview existence');
        return false;
      }
      
      Logger.i('📋 Checking among ${courses.length} courses');
      
      // Find by ID (exact match)
      try {
        final course = courses.firstWhere(
          (course) => course.id == examOverviewCourseId,
        );
        
        Logger.i('✅ Exam Overview exists: "${course.title}" (ID: ${course.id})');
        
        return true;
      } catch (_) {
        Logger.e('❌ Exam Overview not found');
        Logger.e('Available course IDs: ${courses.map((c) => '"${c.id}"').join(", ")}');
        return false;
      }
    } catch (e) {
      Logger.e('❌ Exam Overview validation failed: $e');
      return false;
    }
  }
  
  /// Get the Exam Overview course object if it exists
  /// 
  /// This method is useful when you need the course object itself
  /// for operations other than navigation.
  /// 
  /// Parameters:
  /// - [firestoreService]: Service instance for Firestore operations
  /// 
  /// Returns:
  /// - CourseModel if the course is found
  /// - null if the course cannot be found or an error occurs
  static Future<CourseModel?> getExamOverviewCourse(
    FirestoreService firestoreService,
  ) async {
    try {
      Logger.i('📚 Retrieving Exam Overview course object...');
      
      final courses = await firestoreService.getCourses();
      
      // Find the Exam Overview course by ID
      final examOverviewCourse = courses.firstWhere(
        (course) => course.id == examOverviewCourseId,
        orElse: () => throw Exception('Exam Overview course not found'),
      );
      
      Logger.i('✅ Retrieved Exam Overview course: ${examOverviewCourse.id}');
      return examOverviewCourse;
    } catch (e) {
      Logger.e('❌ Error getting Exam Overview course: $e');
      return null;
    }
  }
  
  /// Validate and navigate to Exam Overview with pre-check
  /// 
  /// This method first checks if the course exists before attempting navigation,
  /// providing a smoother user experience.
  /// 
  /// Parameters:
  /// - [context]: BuildContext for navigation
  /// - [firestoreService]: Service instance for Firestore operations
  /// - [showLoadingDialog]: Whether to show a loading dialog during validation (default: true)
  /// 
  /// Returns:
  /// - true if navigation was successful
  /// - false if course doesn't exist or navigation failed
  static Future<bool> validateAndNavigate(
    BuildContext context,
    FirestoreService firestoreService, {
    bool showLoadingDialog = true,
  }) async {
    // Show loading dialog if requested
    if (showLoadingDialog && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading Exam Overview...'),
                ],
              ),
            ),
          ),
        ),
      );
    }
    
    try {
      // Check if course exists
      final exists = await examOverviewExists(firestoreService);
      
      // Close loading dialog
      if (showLoadingDialog && context.mounted) {
        Navigator.of(context).pop();
      }
      
      if (!exists) {
        if (context.mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Course Not Available'),
              content: const Text(
                'The Exam Overview course is not currently available. '
                'Please contact your administrator.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return false;
      }
      
      // Course exists, proceed with navigation
      return await navigateToExamOverview(context, firestoreService);
      
    } catch (e) {
      // Close loading dialog if still showing
      if (showLoadingDialog && context.mounted) {
        Navigator.of(context).pop();
      }
      
      Logger.e('Error in validateAndNavigate: $e');
      return false;
    }
  }
}
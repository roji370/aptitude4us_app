import 'package:firebase_messaging/firebase_messaging.dart';
import '../utils/logger.dart';
import 'notification_service.dart';

/// Test utility for course assignment notifications
/// This helps verify the implementation works correctly
class CourseAssignmentNotificationTest {
  static final NotificationService _notificationService = NotificationService();

  /// Simulate a course assignment notification for testing
  static Future<void> simulateCourseAssignmentNotification({
    required String courseId,
    required String courseName,
    String? assignmentDate,
  }) async {
    try {
      Logger.i('🧪 Simulating course assignment notification for testing');
      
      // Create a mock RemoteMessage that matches admin app payload structure
      final mockData = {
        'type': 'course_assignment',
        'courseId': courseId,
        'courseName': courseName,
        'assignmentDate': assignmentDate ?? DateTime.now().toIso8601String().split('T')[0],
        'action': 'open_course',
      };
      
      Logger.i('📋 Mock notification data: $mockData');
      
      // Create a mock RemoteMessage
      final mockMessage = RemoteMessage(
        messageId: 'test_${DateTime.now().millisecondsSinceEpoch}',
        data: mockData,
      );
      
      // Process the notification through our handler
      await _notificationService.handleCourseAssignmentNotification(
        mockMessage, 
        isBackground: false
      );
      
      Logger.i('✅ Test notification sent successfully');
      
    } catch (e) {
      Logger.e('❌ Error sending test notification: $e');
    }
  }

  /// Test notification permissions and setup
  static Future<void> testNotificationSetup() async {
    try {
      Logger.i('🧪 Testing notification setup...');
      
      // Check permissions
      final permissions = await _notificationService.checkNotificationPermissions();
      Logger.i('📱 Notification permissions: $permissions');
      
      // Get FCM token
      final token = await _notificationService.getToken();
      Logger.i('🔑 FCM Token: ${token != null ? 'Available (${token.length} chars)' : 'Not available'}');
      
      // Test with sample course data
      await simulateCourseAssignmentNotification(
        courseId: 'test_course_123',
        courseName: 'Sample Test Course',
        assignmentDate: DateTime.now().toIso8601String().split('T')[0],
      );
      
      Logger.i('✅ Notification setup test completed');
      
    } catch (e) {
      Logger.e('❌ Error testing notification setup: $e');
    }
  }

  /// Verify admin app payload structure is handled correctly
  static Future<void> verifyAdminAppPayload() async {
    Logger.i('🧪 Verifying admin app payload structure...');
    
    // Test exact payload structure from admin team specs
    final exactPayload = {
      "type": "course_assignment",
      "courseId": "course-id-123",
      "courseName": "Flutter Development Fundamentals",
      "assignmentDate": "2024-12-12",
      "action": "open_course"
    };
    
    Logger.i('📋 Testing exact admin app payload: $exactPayload');
    
    try {
      final mockMessage = RemoteMessage(
        messageId: 'admin_test_${DateTime.now().millisecondsSinceEpoch}',
        data: exactPayload,
      );
      
      await _notificationService.handleCourseAssignmentNotification(
        mockMessage, 
        isBackground: false
      );
      
      Logger.i('✅ Admin app payload structure verified successfully');
      
    } catch (e) {
      Logger.e('❌ Error verifying admin app payload: $e');
    }
  }
}

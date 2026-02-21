import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Service to manage first-time user state for exam overview requirement
class FirstTimeUserService {
  static const String _keyPrefix = 'has_watched_exam_overview_';
  
  /// Check if a user has watched the exam overview
  /// Returns true if the user has already watched it
  Future<bool> hasWatchedExamOverview(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      final hasWatched = prefs.getBool(key) ?? false;
      
      Logger.i('📚 Exam Overview Status for $userId: ${hasWatched ? "Watched" : "Not watched"}');
      return hasWatched;
    } catch (e) {
      Logger.e('Error checking exam overview status: $e');
      // Default to false (not watched) on error to be safe
      return false;
    }
  }
  
  /// Mark the exam overview as watched for a specific user
  Future<void> markExamOverviewAsWatched(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      await prefs.setBool(key, true);
      
      Logger.i('✅ Exam Overview marked as watched for user: $userId');
    } catch (e) {
      Logger.e('Error marking exam overview as watched: $e');
      rethrow;
    }
  }
  
  /// Reset exam overview status for a user (useful for testing)
  Future<void> resetExamOverviewStatus(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_keyPrefix$userId';
      await prefs.remove(key);
      
      Logger.i('🔄 Exam Overview status reset for user: $userId');
    } catch (e) {
      Logger.e('Error resetting exam overview status: $e');
      rethrow;
    }
  }
  
  /// Clear all exam overview data (for app reset/logout)
  Future<void> clearAllExamOverviewData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      
      // Remove all keys starting with our prefix
      for (final key in keys) {
        if (key.startsWith(_keyPrefix)) {
          await prefs.remove(key);
        }
      }
      
      Logger.i('🗑️ All exam overview data cleared');
    } catch (e) {
      Logger.e('Error clearing exam overview data: $e');
    }
  }
}

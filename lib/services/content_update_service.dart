import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../utils/logger.dart';

/// Service to handle content update notifications
/// Detects and tracks course/module updates from the backend
class ContentUpdateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  /// Check if a course has unseen updates
  Future<bool> hasCourseUpdate(String courseId, String userId) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('notifiedUsers', arrayContains: userId)
          .get();

      // Check if any update hasn't been seen by this user
      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          return true; // Has unseen update
        }
      }

      return false;
    } catch (e) {
      Logger.e('Error checking course updates: $e');
      return false;
    }
  }

  /// Check if a module has unseen updates
  Future<bool> hasModuleUpdate(
    String courseId,
    String moduleId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('moduleId', isEqualTo: moduleId)
          .where('notifiedUsers', arrayContains: userId)
          .get();

      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          return true;
        }
      }

      return false;
    } catch (e) {
      Logger.e('Error checking module updates: $e');
      return false;
    }
  }

  /// Get the highest priority update for a course
  Future<Map<String, dynamic>?> getCourseUpdateInfo(
    String courseId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('notifiedUsers', arrayContains: userId)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();

      // Filter unseen updates and get highest priority
      final unseenUpdates = updates.docs.where((doc) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        return !seenBy.contains(userId);
      }).toList();

      if (unseenUpdates.isEmpty) return null;

      // Find highest priority (critical > important > medium > low)
      final priorityOrder = ['critical', 'important', 'medium', 'low'];
      unseenUpdates.sort((a, b) {
        final aPriority = a.data()['priority'] ?? 'low';
        final bPriority = b.data()['priority'] ?? 'low';
        return priorityOrder.indexOf(aPriority).compareTo(
          priorityOrder.indexOf(bPriority),
        );
      });

      final highestPriority = unseenUpdates.first.data();
      highestPriority['id'] = unseenUpdates.first.id;
      return highestPriority;
    } catch (e) {
      Logger.e('Error getting course update info: $e');
      return null;
    }
  }

  /// Mark course update as seen
  Future<void> markCourseAsSeen(String courseId, String userId) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('notifiedUsers', arrayContains: userId)
          .get();

      final batch = _firestore.batch();
      int markedCount = 0;

      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          // Call cloud function to mark as seen
          try {
            await _functions.httpsCallable('markUpdateAsSeen').call({
              'updateId': doc.id,
            });
            markedCount++;
          } catch (e) {
            Logger.e('Error calling markUpdateAsSeen function: $e');
            // Fallback: Update locally if cloud function fails
            batch.update(doc.reference, {
              'seenBy': FieldValue.arrayUnion([userId]),
            });
          }
        }
      }

      if (markedCount > 0) {
        Logger.i('Marked $markedCount updates as seen for course $courseId');
      }

      // Commit batch if there were local updates
      if (markedCount < updates.docs.length) {
        await batch.commit();
      }
    } catch (e) {
      Logger.e('Error marking course as seen: $e');
    }
  }

  /// Mark module update as seen
  Future<void> markModuleAsSeen(
    String courseId,
    String moduleId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('moduleId', isEqualTo: moduleId)
          .where('notifiedUsers', arrayContains: userId)
          .get();

      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          try {
            await _functions.httpsCallable('markUpdateAsSeen').call({
              'updateId': doc.id,
            });
          } catch (e) {
            Logger.e('Error calling markUpdateAsSeen function: $e');
          }
        }
      }

      Logger.i('Marked module $moduleId as seen');
    } catch (e) {
      Logger.e('Error marking module as seen: $e');
    }
  }

  /// Get all updates for a user (for a potential updates screen)
  Stream<List<Map<String, dynamic>>> getUserUpdates(String userId) {
    return _firestore
        .collection('contentUpdates')
        .where('notifiedUsers', arrayContains: userId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;

        // Check if this user has seen it
        final seenBy = List<String>.from(data['seenBy'] ?? []);
        data['isNew'] = !seenBy.contains(userId);

        return data;
      }).toList();
    });
  }

  /// Get count of unseen updates for a user
  Future<int> getUnseenUpdatesCount(String userId) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('notifiedUsers', arrayContains: userId)
          .get();

      int unseenCount = 0;
      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          unseenCount++;
        }
      }

      return unseenCount;
    } catch (e) {
      Logger.e('Error getting unseen updates count: $e');
      return 0;
    }
  }

  /// Stream of unseen updates count
  Stream<int> watchUnseenUpdatesCount(String userId) {
    return _firestore
        .collection('contentUpdates')
        .where('notifiedUsers', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      int count = 0;
      for (var doc in snapshot.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          count++;
        }
      }
      return count;
    });
  }

  /// Check if content has been added/deleted in a module and get details
  Future<Map<String, dynamic>?> getContentChangeInfo(
    String courseId,
    String moduleId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('moduleId', isEqualTo: moduleId)
          .where('type', isEqualTo: 'content_change')
          .where('notifiedUsers', arrayContains: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (updates.docs.isNotEmpty) {
        final doc = updates.docs.first;
        final data = doc.data();
        final seenBy = List<String>.from(data['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          data['id'] = doc.id;
          return data;
        }
      }
      return null;
    } catch (e) {
      Logger.e('Error checking content changes: $e');
      return null;
    }
  }

  /// Get count of content updates for a module
  Future<int> getContentUpdateCount(
    String courseId,
    String moduleId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('moduleId', isEqualTo: moduleId)
          .where('type', isEqualTo: 'content_change')
          .where('notifiedUsers', arrayContains: userId)
          .get();

      int count = 0;
      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          count++;
        }
      }
      return count;
    } catch (e) {
      Logger.e('Error getting content update count: $e');
      return 0;
    }
  }

  /// Get count of all unseen updates for a course (including content changes)
  Future<int> getTotalCourseUpdateCount(
    String courseId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('notifiedUsers', arrayContains: userId)
          .get();

      int count = 0;
      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          count++;
        }
      }
      return count;
    } catch (e) {
      Logger.e('Error getting total course update count: $e');
      return 0;
    }
  }

  /// Mark content change as seen
  Future<void> markContentAsSeen(
    String courseId,
    String moduleId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('moduleId', isEqualTo: moduleId)
          .where('type', isEqualTo: 'content_change')
          .where('notifiedUsers', arrayContains: userId)
          .get();

      final batch = _firestore.batch();

      for (var doc in updates.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          batch.update(doc.reference, {
            'seenBy': FieldValue.arrayUnion([userId])
          });
        }
      }

      await batch.commit();
      Logger.i('Marked content changes as seen for module $moduleId');
    } catch (e) {
      Logger.e('Error marking content as seen: $e');
    }
  }
}


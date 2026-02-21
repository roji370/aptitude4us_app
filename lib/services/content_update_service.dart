import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Service to handle content update notifications
/// Detects and tracks course/module updates from the backend
class ContentUpdateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ---------------------------------------------------------------------------
  // Optimistic seen-item cache (session-scoped, static so it survives
  // screen disposal / re-creation during navigation).
  // SharedPreferences provides cross-session persistence underneath.
  // ---------------------------------------------------------------------------
  static final _optimisticSeenItems = <String>{};

  /// Immediately mark [contentItemId] as seen in memory.
  /// Call this on item-card tap so the badge clears instantly.
  void markSeenOptimistically(String contentItemId) =>
      _optimisticSeenItems.add(contentItemId);

  /// Returns true if the item was already tapped this session.
  bool isOptimisticallySeen(String contentItemId) =>
      _optimisticSeenItems.contains(contentItemId);

  /// Helper to check if an update document is fully seen by this user.
  ///
  /// For normal docs: checks Firestore `seenBy` array or local `seen_update_` flag.
  /// For `content_change` docs with per-item `itemIds`: considers the doc seen
  /// only when EVERY individual itemId has a `seen_item_<docId>_<itemId>` flag
  /// set locally. This is what makes the full cascade work:
  ///   Content Item seen → Content Type badge clears → Module badge clears → Course badge clears
  Future<bool> _isUpdateSeen(Map<String, dynamic> data, String docId, String userId) async {
    final seenBy = List<String>.from(data['seenBy'] ?? []);
    if (seenBy.contains(userId)) return true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('seen_update_$docId') ?? false) return true;

    // For content_change docs that use per-item itemIds tracking:
    // only consider the doc seen once EVERY itemId has been individually seen.
    final contentChanges = data['contentChanges'];
    if (contentChanges is List && contentChanges.isNotEmpty) {
      final allItemIds = <String>[];
      for (final change in contentChanges) {
        if (change is Map) {
          final itemIds = change['itemIds'];
          if (itemIds is List) {
            allItemIds.addAll(itemIds.whereType<String>());
          }
        }
      }
      if (allItemIds.isNotEmpty) {
        // Has per-item tracking: seen only when ALL items are visited
        return allItemIds.every(
          (itemId) => prefs.getBool('seen_item_${docId}_$itemId') ?? false,
        );
      } else {
        // Legacy format: contentChanges present but no itemIds.
        // We cannot track this per-item, so treat it as invisible (already seen).
        // This prevents legacy docs from driving badges that can never clear correctly.
        return true;
      }
    }

    return false;
  }

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
        if (!(await _isUpdateSeen(doc.data(), doc.id, userId))) {
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
        if (!(await _isUpdateSeen(doc.data(), doc.id, userId))) {
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
      final unseenUpdates = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (var doc in updates.docs) {
        if (!(await _isUpdateSeen(doc.data(), doc.id, userId))) {
          unseenUpdates.add(doc);
        }
      }

      if (unseenUpdates.isEmpty) return null;

      final highest = unseenUpdates.first.data();
      highest['id'] = unseenUpdates.first.id;
      return highest;
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
        final type = doc.data()['type'] as String? ?? '';
        // Skip module, content-type and content-item updates
        if (type.startsWith('module_') || type.startsWith('content_')) continue;

        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          // Immediately mark as seen locally to prevent UI lag
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('seen_update_${doc.id}', true);

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
        final type = doc.data()['type'] as String? ?? '';
        // Skip content-type and content-item updates
        if (type.startsWith('content_')) continue;

        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          // Immediately mark as seen locally to prevent UI lag
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('seen_update_${doc.id}', true);

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
        .asyncMap((snapshot) async {
      final prefs = await SharedPreferences.getInstance();
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;

        // Check if this user has seen it
        final seenBy = List<String>.from(data['seenBy'] ?? []);
        final isSeenLocally = prefs.getBool('seen_update_${doc.id}') ?? false;
        data['isNew'] = !seenBy.contains(userId) && !isSeenLocally;

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
        if (!(await _isUpdateSeen(doc.data(), doc.id, userId))) {
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
        .asyncMap((snapshot) async {
      final prefs = await SharedPreferences.getInstance();
      int count = 0;
      for (var doc in snapshot.docs) {
        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        final isSeenLocally = prefs.getBool('seen_update_${doc.id}') ?? false;
        if (!seenBy.contains(userId) && !isSeenLocally) {
          count++;
        }
      }
      return count;
    });
  }

  /// Maps our internal contentType string to the plural key used in admin's contentType field
  /// e.g. 'video' → 'videos', 'pdf' → 'pdfs', 'text' (notes) → 'notes'
  String _contentTypeToPluralKey(String contentType) {
    switch (contentType.toLowerCase()) {
      case 'video':
        return 'videos';
      case 'pdf':
        return 'pdfs';
      case 'text':
        return 'notes';
      case 'image':
        return 'images';
      case 'ppt':
        return 'ppts';
      case 'link':
        return 'links';
      default:
        return '${contentType}s';
    }
  }

  /// Helper to check if a content type matches the update document
  bool _matchesContentType(Map<String, dynamic> data, String contentType, String pluralKey) {
    if (data['contentType'] != null) {
      final docContentType = data['contentType'] as String;
      if (docContentType == pluralKey || docContentType == contentType) return true;
    }
    if (data['contentChanges'] != null && data['contentChanges'] is List) {
      for (var change in data['contentChanges']) {
        if (change is Map && change['type'] == pluralKey) return true;
      }
    }
    return false;
  }

  // ─────────────────────────────────────────────────────────────
  // Content-Type Level  (e.g. content_videos_added)
  //
  // NOTE: All queries here intentionally use only courseId + moduleId +
  // notifiedUsers (no contentType WHERE clause, no orderBy). Adding extra
  // equality filters or orderBy on top of an arrayContains clause requires
  // a Firestore composite index that may not exist. All extra filtering is
  // done in memory after fetching, matching the pattern used by the working
  // hasModuleUpdate / getContentUpdateCount methods.
  // ─────────────────────────────────────────────────────────────

  /// Fetch all module-level updates from Firestore (base query, no index needed)
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _fetchModuleUpdates(
    String courseId,
    String moduleId,
    String userId,
  ) async {
    final snapshot = await _firestore
        .collection('contentUpdates')
        .where('courseId', isEqualTo: courseId)
        .where('moduleId', isEqualTo: moduleId)
        .where('notifiedUsers', arrayContains: userId)
        .get();
    return snapshot.docs;
  }

  /// Check if a specific content type has unseen updates (added / removed / reordered)
  Future<bool> hasContentTypeUpdate(
    String courseId,
    String moduleId,
    String contentType,
    String userId,
  ) async {
    try {
      final pluralKey = _contentTypeToPluralKey(contentType);
      final docs = await _fetchModuleUpdates(courseId, moduleId, userId);

      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        if (!type.startsWith('content_') || type.startsWith('content_item_')) continue;
        if (!_matchesContentType(data, contentType, pluralKey)) continue;
        if (!(await _isUpdateSeen(data, doc.id, userId))) return true;
      }
      return false;
    } catch (e) {
      Logger.e('Error checking content type updates: $e');
      return false;
    }
  }

  /// Get the highest-priority unseen update for a specific content type
  Future<Map<String, dynamic>?> getContentTypeUpdateInfo(
    String courseId,
    String moduleId,
    String contentType,
    String userId,
  ) async {
    try {
      final pluralKey = _contentTypeToPluralKey(contentType);
      final docs = await _fetchModuleUpdates(courseId, moduleId, userId);

      final unseenUpdates = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        if (!type.startsWith('content_') || type.startsWith('content_item_')) continue;
        if (!_matchesContentType(data, contentType, pluralKey)) continue;
        if (!(await _isUpdateSeen(data, doc.id, userId))) {
          unseenUpdates.add(doc);
        }
      }

      if (unseenUpdates.isEmpty) return null;

      final highest = Map<String, dynamic>.from(unseenUpdates.first.data());
      highest['id'] = unseenUpdates.first.id;
      return highest;
    } catch (e) {
      Logger.e('Error getting content type update info: $e');
      return null;
    }
  }

  /// Mark all unseen updates for a specific content type as seen
  Future<void> markContentTypeAsSeen(
    String courseId,
    String moduleId,
    String contentType,
    String userId,
  ) async {
    try {
      final pluralKey = _contentTypeToPluralKey(contentType);
      final docs = await _fetchModuleUpdates(courseId, moduleId, userId);

      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        if (!type.startsWith('content_') || type.startsWith('content_item_')) continue;
        if (!_matchesContentType(data, contentType, pluralKey)) continue;
        final seenBy = List<String>.from(data['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          // If this doc tracks individual item IDs, do NOT globally mark it as seen here.
          // Each item's badge is cleared individually by markContentItemAsSeen.
          final contentChanges = data['contentChanges'];
          final hasItemIdTracking = contentChanges is List &&
              contentChanges.any((c) => c is Map && c['itemIds'] is List);
          if (hasItemIdTracking) continue;

          // Immediately mark as seen locally to prevent UI lag
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('seen_update_${doc.id}', true);

          try {
            await _functions.httpsCallable('markUpdateAsSeen').call({
              'updateId': doc.id,
            });
          } catch (e) {
            Logger.e('Error calling markUpdateAsSeen: $e');
            await doc.reference.update({
              'seenBy': FieldValue.arrayUnion([userId]),
            });
          }
        }
      }
      Logger.i('Marked $contentType updates as seen for module $moduleId');
    } catch (e) {
      Logger.e('Error marking content type as seen: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Content-Item Level  (e.g. content_item_title_changed)
  //
  // Admin docs are inconsistent: the record structure uses 'contentItemId'
  // but example notifications use 'itemId'. Both field names are checked.
  // ─────────────────────────────────────────────────────────────

  /// Returns true if a Firestore doc belongs to the given content item,
  /// checking both 'contentItemId' and 'itemId' field names.
  bool _docMatchesContentItem(Map<String, dynamic> data, String contentItemId) {
    final id1 = data['contentItemId'] as String?;
    final id2 = data['itemId'] as String?;
    return id1 == contentItemId || id2 == contentItemId;
  }

  /// Check if a specific content item has unseen updates
  Future<bool> hasContentItemUpdate(
    String courseId,
    String moduleId,
    String contentItemId,
    String contentType,
    String userId,
  ) async {
    final info = await getContentItemUpdateInfo(
      courseId, moduleId, contentItemId, contentType, userId,
    );
    return info != null;
  }

  /// Get the highest-priority unseen update for a specific content item
  Future<Map<String, dynamic>?> getContentItemUpdateInfo(
    String courseId,
    String moduleId,
    String contentItemId,
    String contentType,
    String userId,
  ) async {
    try {
      final pluralKey = _contentTypeToPluralKey(contentType);
      final docs = await _fetchModuleUpdates(courseId, moduleId, userId);
      final prefs = await SharedPreferences.getInstance();

      final unseenUpdates = <Map<String, dynamic>>[];

      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        final isGlobalSeen = await _isUpdateSeen(data, doc.id, userId);

        if (type.startsWith('content_item_')) {
          if (_docMatchesContentItem(data, contentItemId) && !isGlobalSeen) {
             final match = Map<String, dynamic>.from(data);
             match['id'] = doc.id;
             unseenUpdates.add(match);
             continue;
          }
        }

        if (type.startsWith('content_') && !type.startsWith('content_item_')) {
          if (_matchesContentType(data, contentType, pluralKey)) {
            final contentChanges = data['contentChanges'];
            if (contentChanges is List) {
              // This doc uses per-item tracking via itemIds.
              // DO NOT use isGlobalSeen here — seenBy on the shared doc is
              // poisoned as soon as any sibling item is viewed. Instead, rely
              // solely on the per-item local SharedPreferences key.
              for (final change in contentChanges) {
                if (change is Map) {
                  final itemIds = change['itemIds'];
                  if (itemIds is List && itemIds.contains(contentItemId)) {
                    final localKey = 'seen_item_${doc.id}_$contentItemId';
                    final isLocallySeen = prefs.getBool(localKey) ?? false;
                    if (!isLocallySeen) {
                      final match = Map<String, dynamic>.from(data);
                      match['id'] = doc.id;
                      unseenUpdates.add(match);
                    }
                    break;
                  }
                }
              }
            }
            // No itemIds list → skip (legacy doc, can't determine per-item)
          }
        }
      }

      if (unseenUpdates.isEmpty) return null;

      final highest = Map<String, dynamic>.from(unseenUpdates.first);
      return highest;
    } catch (e) {
      Logger.e('Error getting content item update info: $e');
      return null;
    }
  }

  /// Mark all unseen updates for a specific content item as seen
  Future<void> markContentItemAsSeen(
    String courseId,
    String moduleId,
    String contentItemId,
    String contentType,
    String userId,
  ) async {
    try {
      final pluralKey = _contentTypeToPluralKey(contentType);
      final docs = await _fetchModuleUpdates(courseId, moduleId, userId);
      final prefs = await SharedPreferences.getInstance();

      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        final isGlobalSeen = await _isUpdateSeen(data, doc.id, userId);

        if (type.startsWith('content_item_') && _docMatchesContentItem(data, contentItemId) && !isGlobalSeen) {
          // Immediately mark as seen locally to prevent UI lag
          await prefs.setBool('seen_update_${doc.id}', true);

          try {
            await _functions.httpsCallable('markUpdateAsSeen').call({
              'updateId': doc.id,
            });
          } catch (e) {
            Logger.e('Error calling markUpdateAsSeen: $e');
            await doc.reference.update({
              'seenBy': FieldValue.arrayUnion([userId]),
            });
          }
        }

        if (type.startsWith('content_') && !type.startsWith('content_item_')) {
          if (_matchesContentType(data, contentType, pluralKey)) {
            // For shared content_change docs, ONLY set the per-item local key.
            // Never call markUpdateAsSeen here — that would add userId to
            // seenBy on the shared doc and clear every sibling's badge.
            final localKey = 'seen_item_${doc.id}_$contentItemId';
            await prefs.setBool(localKey, true);
          }
        }
      }
      Logger.i('Marked content item $contentItemId updates as seen');
    } catch (e) {
      Logger.e('Error marking content item as seen: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Legacy / shared helpers (kept for backward compat)
  // ─────────────────────────────────────────────────────────────

  /// Get count of unseen content-type-level updates for a module
  /// (counts types like content_videos_added but NOT content_item_* updates)
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
          .where('notifiedUsers', arrayContains: userId)
          .get();

      int count = 0;
      for (var doc in updates.docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        // Count only content-type-level updates
        if (!type.startsWith('content_')) continue;
        if (type.startsWith('content_item_')) continue;
        if (!(await _isUpdateSeen(data, doc.id, userId))) count++;
      }
      return count;
    } catch (e) {
      Logger.e('Error getting content update count: $e');
      return 0;
    }
  }

  /// Get count of unseen content-item-level updates for a specific content type
  /// e.g. how many individual video items have unseen changes within a module
  Future<int> getContentItemUpdateCountForType(
    String courseId,
    String moduleId,
    String contentType,
    String userId,
  ) async {
    try {
      final pluralKey = _contentTypeToPluralKey(contentType);
      final docs = await _fetchModuleUpdates(courseId, moduleId, userId);

      int count = 0;
      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        final docContentType = data['contentType'] as String? ?? '';
        if (!type.startsWith('content_item_')) continue;
        if (docContentType != pluralKey && docContentType != contentType) continue;
        if (!(await _isUpdateSeen(data, doc.id, userId))) count++;
      }
      return count;
    } catch (e) {
      Logger.e('Error getting content item update count for type: $e');
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
        if (!(await _isUpdateSeen(doc.data(), doc.id, userId))) {
          count++;
        }
      }
      return count;
    } catch (e) {
      Logger.e('Error getting total course update count: $e');
      return 0;
    }
  }

  /// Mark all content-type-level updates as seen for a module
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
          .where('notifiedUsers', arrayContains: userId)
          .get();

      final batch = _firestore.batch();

      for (var doc in updates.docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        // Only mark content-type-level updates (not item-level)
        if (!type.startsWith('content_')) continue;
        if (type.startsWith('content_item_')) continue;
        final seenBy = List<String>.from(data['seenBy'] ?? []);
        if (!seenBy.contains(userId)) {
          // Immediately mark as seen locally to prevent UI lag
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('seen_update_${doc.id}', true);

          batch.update(doc.reference, {
            'seenBy': FieldValue.arrayUnion([userId]),
          });
        }
      }

      await batch.commit();
      Logger.i('Marked all content type updates as seen for module $moduleId');
    } catch (e) {
      Logger.e('Error marking content as seen: $e');
    }
  }
}


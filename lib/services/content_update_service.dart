import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';

/// Simplified content-update badge service.
///
/// Design: bottom-up cascade with a single "UPDATE" badge.
///
///   Content Item  →  Content Type  →  Module  →  Course
///
/// Content items are the source of truth. A parent card shows an "UPDATE"
/// badge when ANY of its children have unseen items. The badge clears only
/// when ALL badged children have been visited. Cards without badges never
/// block parent clearing.
///
/// Session-scoped optimistic set: when the user taps an item, the badge
/// vanishes instantly. Firestore persistence happens in the background.
class ContentUpdateService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // ---------------------------------------------------------------------------
  // Session-scoped optimistic seen set (static — survives screen disposal).
  // Keyed by content-item IDs only. Parents derive their state from children.
  // ---------------------------------------------------------------------------
  static final _seenItemIds = <String>{};

  /// Mark a content item as seen in memory (instant badge clear).
  void markItemSeen(String itemId) => _seenItemIds.add(itemId);

  /// Check if a content item has been tapped this session.
  bool isItemSeen(String itemId) => _seenItemIds.contains(itemId);

  // ---------------------------------------------------------------------------
  // Firestore queries
  // ---------------------------------------------------------------------------

  /// Fetch all update docs for a module. Public so callers can cache the
  /// result and pass it to [getUnseenItemIds] to avoid duplicate reads.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchModuleUpdateDocs(
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

  // ---------------------------------------------------------------------------
  // Core: get the set of unseen content-item IDs for a module
  // ---------------------------------------------------------------------------

  /// Returns every content-item ID that has an unseen update within
  /// [moduleId]. This is the single source of truth for the badge cascade.
  ///
  /// [validItemIds] — optional set of item IDs that actually exist in the
  /// module. Orphaned IDs (deleted items still referenced in update docs)
  /// are filtered out so they don't cause permanently stuck badges.
  ///
  /// [cachedDocs] — pre-fetched docs from [fetchModuleUpdateDocs] to
  /// avoid redundant Firestore reads.
  Future<Set<String>> getUnseenItemIds(
    String courseId,
    String moduleId,
    String userId, {
    Set<String>? validItemIds,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? cachedDocs,
  }) async {
    try {
      final docs = cachedDocs ??
          await fetchModuleUpdateDocs(courseId, moduleId, userId);
      final prefs = await SharedPreferences.getInstance();
      final unseenIds = <String>{};

      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';

        // ── Per-item tracking docs (content_* with contentChanges[].itemIds) ──
        if (type.startsWith('content_') && !type.startsWith('content_item_')) {
          // If the whole doc is already globally seen, skip all its items.
          final seenBy = List<String>.from(data['seenBy'] ?? []);
          if (seenBy.contains(userId)) continue;
          if (prefs.getBool('seen_update_${doc.id}') ?? false) continue;

          final contentChanges = data['contentChanges'];
          if (contentChanges is List && contentChanges.isNotEmpty) {
            for (final change in contentChanges) {
              if (change is Map) {
                final itemIds = change['itemIds'];
                if (itemIds is List) {
                  for (final itemId in itemIds.whereType<String>()) {
                    // Skip orphaned IDs
                    if (validItemIds != null &&
                        !validItemIds.contains(itemId)) {
                      continue;
                    }
                    // Skip items already seen this session
                    if (_seenItemIds.contains(itemId)) continue;
                    // Skip items marked seen in local prefs
                    final localKey = 'seen_item_${doc.id}_$itemId';
                    if (prefs.getBool(localKey) ?? false) continue;

                    unseenIds.add(itemId);
                  }
                }
                // contentChanges present but no itemIds → legacy format,
                // treat as invisible (already seen) to avoid stuck badges.
              }
            }
          }
          // No contentChanges at all → legacy doc, skip.
          continue;
        }

        // ── Single-item docs (content_item_*) ────────────────────────────────
        if (type.startsWith('content_item_')) {
          final seenBy = List<String>.from(data['seenBy'] ?? []);
          if (seenBy.contains(userId)) continue;
          if (prefs.getBool('seen_update_${doc.id}') ?? false) continue;

          final itemId =
              (data['contentItemId'] ?? data['itemId']) as String?;
          if (itemId == null) continue;
          if (validItemIds != null && !validItemIds.contains(itemId)) {
            continue;
          }
          if (_seenItemIds.contains(itemId)) continue;

          unseenIds.add(itemId);
          continue;
        }

        // ── Module-level docs (module_*) and other non-content docs ──────────
        // These don't carry item IDs — handled separately by
        // [_hasUnseenModuleLevelDocs] and [markModuleLevelDocsSeen].
      }

      return unseenIds;
    } catch (e) {
      Logger.e('Error getting unseen item IDs: $e');
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // Module-level badge check  (for module cards)
  // ---------------------------------------------------------------------------

  /// Returns true if the module has ANY unseen updates — either per-item
  /// content updates or module-level docs.
  ///
  /// Automatically loads valid item IDs from the module document to filter
  /// out orphaned IDs (deleted items still referenced in update docs).
  Future<bool> hasModuleUpdate(
    String courseId,
    String moduleId,
    String userId, {
    Set<String>? validItemIds,
  }) async {
    try {
      final docs = await fetchModuleUpdateDocs(courseId, moduleId, userId);

      // If caller didn't provide valid IDs, load them from the module doc.
      // This prevents orphaned item IDs from causing permanently stuck badges.
      final effectiveValidIds =
          validItemIds ?? await _loadValidItemIds(moduleId);

      // Check for unseen content items
      final unseenItems = await getUnseenItemIds(
        courseId,
        moduleId,
        userId,
        validItemIds: effectiveValidIds,
        cachedDocs: docs,
      );
      if (unseenItems.isNotEmpty) return true;

      // Check for unseen module-level docs (module_* type)
      return _hasUnseenNonContentDocs(docs, userId);
    } catch (e) {
      Logger.e('Error checking module updates: $e');
      return false;
    }
  }

  /// Load all valid content-item IDs from a module document.
  /// Returns null if IDs can't be determined (skip orphan filtering).
  /// Returns a non-empty set when IDs are found (filter orphans).
  Future<Set<String>?> _loadValidItemIds(String moduleId) async {
    try {
      final moduleDoc =
          await _firestore.collection('modules').doc(moduleId).get();
      if (!moduleDoc.exists) return null;

      final data = moduleDoc.data();
      if (data == null || !data.containsKey('content')) return null;

      final content = data['content'] as Map<String, dynamic>;
      final validIds = <String>{};

      // Extract IDs from each content type array (videos, pdfs, notes, etc.)
      for (final entry in content.entries) {
        final items = entry.value;
        if (items is List) {
          int index = 0;
          for (final item in items) {
            if (item is Map) {
              // Prefer explicit 'id' field; fall back to stable generated ID
              final id = item['id'] as String? ??
                  '${moduleId}_${entry.key == 'notes' ? 'text' : entry.key.replaceAll(RegExp(r's$'), '')}_${item['title'] ?? ''}_${item['order'] ?? index}';
              validIds.add(id);
            }
            index++;
          }
        }
      }

      // Return null if no items found (module exists but has empty content)
      return validIds.isNotEmpty ? validIds : null;
    } catch (e) {
      Logger.w('Failed to load valid item IDs for module $moduleId: $e');
      return null; // null = skip filtering (all IDs considered valid)
    }
  }

  /// Returns true if there are unseen docs whose type does NOT start with
  /// `content_`. These are module-level notifications (e.g. module renamed).
  Future<bool> _hasUnseenNonContentDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String userId,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    for (var doc in docs) {
      final data = doc.data();
      final type = data['type'] as String? ?? '';
      if (type.startsWith('content_')) continue; // handled by getUnseenItemIds

      final seenBy = List<String>.from(data['seenBy'] ?? []);
      if (seenBy.contains(userId)) continue;
      if (prefs.getBool('seen_update_${doc.id}') ?? false) continue;

      return true; // found an unseen module-level doc
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Course-level badge check  (for course cards)
  // ---------------------------------------------------------------------------

  /// Returns true if ANY update doc in the course is unseen.
  ///
  /// Uses the exact same per-module logic as [hasModuleUpdate] so that
  /// course and module badge states are always consistent.
  /// Only checks modules that are published (matching what the user sees).
  Future<bool> hasCourseUpdate(String courseId, String userId) async {
    try {
      // Load the set of published module IDs — only these are visible to users.
      // Update docs referencing deleted/unpublished modules are ignored.
      final publishedModulesSnap = await _firestore
          .collection('modules')
          .where('courseId', isEqualTo: courseId)
          .where('isPublished', isEqualTo: true)
          .get();
      final publishedModuleIds =
          publishedModulesSnap.docs.map((d) => d.id).toSet();
      Logger.i('[hasCourseUpdate] course=$courseId, publishedModules=$publishedModuleIds');

      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('notifiedUsers', arrayContains: userId)
          .get();
      Logger.i('[hasCourseUpdate] total update docs: ${updates.docs.length}');

      final prefs = await SharedPreferences.getInstance();

      // Group docs by moduleId.
      final docsByModule =
          <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
      final docsWithoutModule =
          <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      int skippedOrphaned = 0;

      for (var doc in updates.docs) {
        final moduleId = doc.data()['moduleId'] as String?;
        if (moduleId != null) {
          // Skip docs for modules that don't exist or aren't published.
          if (!publishedModuleIds.contains(moduleId)) {
            skippedOrphaned++;
            Logger.i('[hasCourseUpdate] SKIP orphaned doc ${doc.id} (module=$moduleId not published)');
            continue;
          }
          docsByModule.putIfAbsent(moduleId, () => []).add(doc);
        } else {
          docsWithoutModule.add(doc);
        }
      }
      Logger.i('[hasCourseUpdate] docsWithoutModule=${docsWithoutModule.length}, '
          'moduleGroups=${docsByModule.length}, skippedOrphaned=$skippedOrphaned');

      // 1. Check course-level docs (no moduleId).
      for (var doc in docsWithoutModule) {
        final data = doc.data();
        final seenBy = List<String>.from(data['seenBy'] ?? []);
        if (seenBy.contains(userId)) continue;
        if (prefs.getBool('seen_update_${doc.id}') ?? false) continue;
        Logger.i('[hasCourseUpdate] ⚠️ UNSEEN course-level doc: ${doc.id}, type=${data['type']}');
        return true; // unseen course-level doc
      }

      // 2. Check each published module — same logic as hasModuleUpdate.
      for (var entry in docsByModule.entries) {
        final moduleId = entry.key;
        final moduleDocs = entry.value;

        final validIds = await _loadValidItemIds(moduleId);
        Logger.i('[hasCourseUpdate] module=$moduleId, validIds=${validIds?.length ?? "null (no filter)"}, docs=${moduleDocs.length}');

        // Unseen content items?
        final unseenItems = await getUnseenItemIds(
          courseId,
          moduleId,
          userId,
          validItemIds: validIds,
          cachedDocs: moduleDocs,
        );
        if (unseenItems.isNotEmpty) {
          Logger.i('[hasCourseUpdate] ⚠️ UNSEEN items in module $moduleId: $unseenItems');
          return true;
        }

        // Unseen module-level docs?
        if (await _hasUnseenNonContentDocs(moduleDocs, userId)) {
          Logger.i('[hasCourseUpdate] ⚠️ UNSEEN module-level docs in module $moduleId');
          return true;
        }
      }

      Logger.i('[hasCourseUpdate] ✅ Course $courseId fully seen');
      return false;
    } catch (e) {
      Logger.e('Error checking course updates: $e');
      return false;
    }
  }

  /// Check if a single update document is fully seen.
  ///
  /// For per-item tracking docs (contentChanges with itemIds): the doc is
  /// only considered seen when EVERY non-orphaned itemId has been visited.
  /// [validItemIds] filters out orphaned IDs (deleted items) so they don't
  /// cause permanently stuck badges.
  /// Session-scoped [_seenItemIds] are included in the check.
  Future<bool> _isDocSeen(
    Map<String, dynamic> data,
    String docId,
    String userId,
    SharedPreferences prefs, {
    Set<String>? validItemIds,
  }) async {
    final seenBy = List<String>.from(data['seenBy'] ?? []);
    if (seenBy.contains(userId)) return true;
    if (prefs.getBool('seen_update_$docId') ?? false) return true;

    // Per-item tracking: seen only when ALL non-orphaned items are seen.
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
        // Filter orphaned IDs — only check items that still exist.
        final effectiveIds = validItemIds != null
            ? allItemIds.where((id) => validItemIds.contains(id)).toList()
            : allItemIds;

        // All items are orphaned → treat doc as seen (no valid items left).
        if (effectiveIds.isEmpty) return true;

        return effectiveIds.every((itemId) =>
            _seenItemIds.contains(itemId) ||
            (prefs.getBool('seen_item_${docId}_$itemId') ?? false));
      }

      // contentChanges exists but no itemIds → legacy, treat as seen.
      return true;
    }

    // content_item_* docs: check session-scoped seen set via contentItemId/itemId
    final type = data['type'] as String? ?? '';
    if (type.startsWith('content_item_')) {
      final itemId =
          (data['contentItemId'] ?? data['itemId']) as String?;
      if (itemId != null && _seenItemIds.contains(itemId)) {
        return true;
      }
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Persistence: mark a content item as seen in SharedPreferences + Firestore
  // ---------------------------------------------------------------------------

  /// Maps our internal contentType string to the plural key used in admin's
  /// contentType field.
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

  /// Helper to check if a content type matches the update document.
  bool _matchesContentType(
    Map<String, dynamic> data,
    String contentType,
    String pluralKey,
  ) {
    if (data['contentType'] != null) {
      final docContentType = data['contentType'] as String;
      if (docContentType == pluralKey || docContentType == contentType) {
        return true;
      }
    }
    if (data['contentChanges'] != null && data['contentChanges'] is List) {
      for (var change in data['contentChanges']) {
        if (change is Map && change['type'] == pluralKey) return true;
      }
    }
    return false;
  }

  /// Persist a content item as seen. Sets per-item local pref keys and
  /// calls the cloud function for content_item_* docs.
  Future<void> persistItemSeen(
    String courseId,
    String moduleId,
    String contentItemId,
    String contentType,
    String userId,
  ) async {
    try {
      final pluralKey = _contentTypeToPluralKey(contentType);
      final docs = await fetchModuleUpdateDocs(courseId, moduleId, userId);
      final prefs = await SharedPreferences.getInstance();

      for (var doc in docs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';

        // ── content_item_* docs — single item per doc ──
        if (type.startsWith('content_item_')) {
          final id1 = data['contentItemId'] as String?;
          final id2 = data['itemId'] as String?;
          if (id1 == contentItemId || id2 == contentItemId) {
            final seenBy = List<String>.from(data['seenBy'] ?? []);
            if (!seenBy.contains(userId) &&
                !(prefs.getBool('seen_update_${doc.id}') ?? false)) {
              await prefs.setBool('seen_update_${doc.id}', true);
              try {
                await _functions
                    .httpsCallable('markUpdateAsSeen')
                    .call({'updateId': doc.id});
              } catch (e) {
                Logger.e('Error calling markUpdateAsSeen: $e');
              }
            }
          }
        }

        // ── content_* shared docs — per-item key only ──
        if (type.startsWith('content_') && !type.startsWith('content_item_')) {
          if (_matchesContentType(data, contentType, pluralKey)) {
            final localKey = 'seen_item_${doc.id}_$contentItemId';
            await prefs.setBool(localKey, true);
          }
        }
      }

      Logger.i('Persisted item $contentItemId as seen');
    } catch (e) {
      Logger.e('Error persisting item as seen: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Mark non-content docs as seen (called on screen entry)
  // ---------------------------------------------------------------------------

  /// Mark module-level update docs (type NOT starting with `content_`) as
  /// seen. Called when the user enters a module's content-types screen.
  Future<void> markModuleLevelDocsSeen(
    String courseId,
    String moduleId,
    String userId,
  ) async {
    try {
      final docs = await fetchModuleUpdateDocs(courseId, moduleId, userId);
      final prefs = await SharedPreferences.getInstance();

      for (var doc in docs) {
        final type = doc.data()['type'] as String? ?? '';
        if (type.startsWith('content_')) continue; // skip content docs

        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (seenBy.contains(userId)) continue;
        if (prefs.getBool('seen_update_${doc.id}') ?? false) continue;

        await prefs.setBool('seen_update_${doc.id}', true);
        try {
          await _functions
              .httpsCallable('markUpdateAsSeen')
              .call({'updateId': doc.id});
        } catch (e) {
          Logger.e('Error calling markUpdateAsSeen: $e');
        }
      }
    } catch (e) {
      Logger.e('Error marking module-level docs as seen: $e');
    }
  }

  /// Mark course-level update docs (type NOT starting with `module_` or
  /// `content_`) as seen. Called when the user enters a course's module list.
  Future<void> markCourseLevelDocsSeen(
    String courseId,
    String userId,
  ) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('courseId', isEqualTo: courseId)
          .where('notifiedUsers', arrayContains: userId)
          .get();

      final prefs = await SharedPreferences.getInstance();
      for (var doc in updates.docs) {
        final type = doc.data()['type'] as String? ?? '';
        if (type.startsWith('module_') || type.startsWith('content_')) {
          continue;
        }

        final seenBy = List<String>.from(doc.data()['seenBy'] ?? []);
        if (seenBy.contains(userId)) continue;
        if (prefs.getBool('seen_update_${doc.id}') ?? false) continue;

        await prefs.setBool('seen_update_${doc.id}', true);
        try {
          await _functions
              .httpsCallable('markUpdateAsSeen')
              .call({'updateId': doc.id});
        } catch (e) {
          Logger.e('Error calling markUpdateAsSeen: $e');
        }
      }
    } catch (e) {
      Logger.e('Error marking course-level docs as seen: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Streams / counts for other UI surfaces (notification screen, etc.)
  // ---------------------------------------------------------------------------

  /// Get all updates for a user (for a potential updates screen).
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

        final seenBy = List<String>.from(data['seenBy'] ?? []);
        final isSeenLocally =
            prefs.getBool('seen_update_${doc.id}') ?? false;
        data['isNew'] = !seenBy.contains(userId) && !isSeenLocally;

        return data;
      }).toList();
    });
  }

  /// Get count of unseen updates for a user.
  Future<int> getUnseenUpdatesCount(String userId) async {
    try {
      final updates = await _firestore
          .collection('contentUpdates')
          .where('notifiedUsers', arrayContains: userId)
          .get();

      final prefs = await SharedPreferences.getInstance();
      int count = 0;
      for (var doc in updates.docs) {
        if (!await _isDocSeen(doc.data(), doc.id, userId, prefs)) {
          count++;
        }
      }
      return count;
    } catch (e) {
      Logger.e('Error getting unseen updates count: $e');
      return 0;
    }
  }

  /// Stream of unseen updates count.
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
        final isSeenLocally =
            prefs.getBool('seen_update_${doc.id}') ?? false;
        if (!seenBy.contains(userId) && !isSeenLocally) {
          count++;
        }
      }
      return count;
    });
  }
}

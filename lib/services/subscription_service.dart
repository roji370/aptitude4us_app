import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/logger.dart';

/// Service for managing user subscriptions and course access validation
class SubscriptionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Cache for subscription data
  static final Map<String, _CachedSubscriptionData> _subscriptionCache = {};
  static const Duration _cacheTimeout = Duration(minutes: 5);

  /// Get all subscriptions for a specific user.
  ///
  /// When [forceRefresh] is true, attempts a server-only read first.
  /// If the server read fails (common on Android cold start when Firestore's
  /// gRPC channel isn't established yet), falls back to a cache read, then
  /// to the in-memory cache. If all sources fail, rethrows so the caller
  /// (SessionProvider) can handle it without overwriting the optimistic default.
  Future<List<Map<String, dynamic>>> getUserSubscriptions(
    String userId, {
    bool forceRefresh = false,
  }) async {
    // Check in-memory cache first if not forcing refresh
    if (!forceRefresh && _subscriptionCache.containsKey(userId)) {
      final cachedData = _subscriptionCache[userId]!;
      if (DateTime.now().difference(cachedData.timestamp) < _cacheTimeout) {
        Logger.i(
          '📋 Using cached subscriptions for user: $userId (${cachedData.subscriptions.length} subscriptions)',
        );
        return cachedData.subscriptions;
      }
    }

    Logger.i(
      '📋 Fetching subscriptions for user: $userId (forceRefresh: $forceRefresh)',
    );

    QuerySnapshot<Map<String, dynamic>>? querySnapshot;

    if (forceRefresh) {
      // Try server first; fall back to Firestore cache on failure
      // (Android cold start: gRPC channel may not be ready yet)
      try {
        querySnapshot = await _firestore
            .collection('subscriptions')
            .where('userId', isEqualTo: userId)
            .get(const GetOptions(source: Source.server));
      } catch (serverError) {
        Logger.w(
          '⚠️ Server fetch failed, falling back to Firestore cache: $serverError',
        );
        try {
          querySnapshot = await _firestore
              .collection('subscriptions')
              .where('userId', isEqualTo: userId)
              .get(const GetOptions(source: Source.cache));
          Logger.i('📋 Successfully read subscriptions from Firestore cache');
        } catch (cacheError) {
          Logger.e('❌ Firestore cache also failed: $cacheError');
          // Last resort: return in-memory cache if available
          if (_subscriptionCache.containsKey(userId)) {
            Logger.i('📋 Using stale in-memory cache as last resort');
            return _subscriptionCache[userId]!.subscriptions;
          }
          // Nothing available — rethrow so SessionProvider keeps
          // the optimistic default instead of treating this as "no subscription"
          rethrow;
        }
      }
    } else {
      // Default: Firestore decides server vs cache
      try {
        querySnapshot = await _firestore
            .collection('subscriptions')
            .where('userId', isEqualTo: userId)
            .get();
      } catch (error) {
        Logger.e('❌ Error fetching user subscriptions: $error');
        // Return in-memory cache if available, otherwise rethrow
        if (_subscriptionCache.containsKey(userId)) {
          return _subscriptionCache[userId]!.subscriptions;
        }
        rethrow;
      }
    }

    final subscriptions = <Map<String, dynamic>>[];

    for (final doc in querySnapshot.docs) {
      final data = doc.data();
      final endDate = (data['endDate'] as Timestamp?)?.toDate() ?? DateTime.now();
      final examDate = (data['examDate'] as Timestamp?)?.toDate();
      // Prefer the admin-written denormalized effectiveEndDate (which uses
      // end-of-day for examDate). Fall back to local compute for legacy docs
      // that have not been backfilled yet.
      final adminEffective = (data['effectiveEndDate'] as Timestamp?)?.toDate();
      final effectiveEndDate = adminEffective ??
          ((examDate != null && examDate.isBefore(endDate))
              ? DateTime(examDate.year, examDate.month, examDate.day, 23, 59, 59, 999)
              : endDate);
      
      subscriptions.add({
        'id': doc.id,
        ...data,
        'startDate':
            (data['startDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
        'endDate': endDate,
        'examDate': examDate,
        'effectiveEndDate': effectiveEndDate,
      });
    }

    // Cache the result
    _subscriptionCache[userId] = _CachedSubscriptionData(
      subscriptions: subscriptions,
      timestamp: DateTime.now(),
    );

    Logger.i(
      '📋 Found ${subscriptions.length} subscriptions for user $userId',
    );
    return subscriptions;
  }

  /// Check if user has at least one active subscription.
  ///
  /// Propagates exceptions from [getUserSubscriptions] so that callers
  /// (e.g. SessionProvider) can distinguish "no subscription" from
  /// "couldn't reach any data source" and handle them differently.
  Future<bool> checkUserActiveSubscription(
    String userId, {
    bool forceRefresh = false,
  }) async {
    Logger.i(
      '🔍 Checking active subscription for user: $userId (forceRefresh: $forceRefresh)',
    );

    final subscriptions = await getUserSubscriptions(
      userId,
      forceRefresh: forceRefresh,
    );

    // Check if user has at least one active subscription
    final hasActiveSubscription = subscriptions.any((subscription) {
      final status = subscription['status'] as String?;
      // Use effectiveEndDate which already accounts for exam date
      final effectiveEndDate = subscription['effectiveEndDate'] as DateTime?;

      return status == 'active' &&
          effectiveEndDate != null &&
          effectiveEndDate.isAfter(DateTime.now());
    });

    Logger.i(
      '🔍 User $userId has active subscription: $hasActiveSubscription',
    );
    return hasActiveSubscription;
  }

  /// Check if user has access to a specific course (combines assignment + subscription check)
  Future<bool> hasAccessToCourse(
    String userId,
    String courseId, {
    bool forceRefresh = false,
  }) async {
    try {
      Logger.i(
        '🔐 Checking course access for user $userId, course $courseId (forceRefresh: $forceRefresh)',
      );

      // Get user data
      final userDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get(forceRefresh ? const GetOptions(source: Source.server) : null);

      if (!userDoc.exists) {
        Logger.w('⚠️ User document not found: $userId');
        return false;
      }

      final userData = userDoc.data()!;

      // Check if course is assigned
      final assignedCourseIds = List<String>.from(
        userData['assignedCourseIds'] ?? [],
      );
      final isAssignedToCourse = assignedCourseIds.contains(courseId);

      if (!isAssignedToCourse) {
        Logger.w('⚠️ Course $courseId not assigned to user $userId');
        return false;
      }

      // CRITICAL: Check if user has an active subscription
      final hasActiveSubscription = await checkUserActiveSubscription(
        userId,
        forceRefresh: forceRefresh,
      );

      if (!hasActiveSubscription) {
        Logger.w(
          '⚠️ User $userId has no active subscription for course $courseId',
        );
        return false;
      }

      Logger.i('✅ User $userId has access to course $courseId');
      return true;
    } catch (error) {
      Logger.e('❌ Error checking course access: $error');
      return false;
    }
  }

  /// Get current user's subscription status
  Future<Map<String, dynamic>?> getCurrentUserSubscriptionStatus({
    bool forceRefresh = false,
  }) async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        Logger.w('⚠️ No current user for subscription status check');
        return null;
      }

      final subscriptions = await getUserSubscriptions(
        currentUser.uid,
        forceRefresh: forceRefresh,
      );

      if (subscriptions.isEmpty) {
        return {
          'hasSubscription': false,
          'isActive': false,
          'message': 'No subscription found',
        };
      }

      // Find the most recent active subscription
      final activeSubscriptions =
          subscriptions.where((sub) {
            final status = sub['status'] as String?;
            // Use effectiveEndDate which accounts for exam date
            final effectiveEndDate = sub['effectiveEndDate'] as DateTime?;
            return status == 'active' &&
                effectiveEndDate != null &&
                effectiveEndDate.isAfter(DateTime.now());
          }).toList();

      if (activeSubscriptions.isNotEmpty) {
        final latestSub = activeSubscriptions.first;
        final effectiveEndDate = latestSub['effectiveEndDate'] as DateTime;
        return {
          'hasSubscription': true,
          'isActive': true,
          'endDate': latestSub['endDate'],
          'examDate': latestSub['examDate'],
          'effectiveEndDate': effectiveEndDate,
          'daysRemaining':
              effectiveEndDate
                  .difference(DateTime.now())
                  .inDays,
          'subscription': latestSub,
        };
      }

      // Check for expired subscriptions
      final expiredSubs =
          subscriptions.where((sub) {
            final effectiveEndDate = sub['effectiveEndDate'] as DateTime?;
            return effectiveEndDate != null && effectiveEndDate.isBefore(DateTime.now());
          }).toList();

      if (expiredSubs.isNotEmpty) {
        return {
          'hasSubscription': true,
          'isActive': false,
          'message': 'Subscription expired',
          'lastEndDate': expiredSubs.first['endDate'],
        };
      }

      return {
        'hasSubscription': false,
        'isActive': false,
        'message': 'No valid subscription',
      };
    } catch (error) {
      Logger.e('❌ Error getting current user subscription status: $error');
      return null;
    }
  }

  /// Listen to real-time changes in user's subscription status
  Stream<bool> subscriptionStatusStream(String userId) {
    return _firestore.collection('users').doc(userId).snapshots().asyncMap((
      doc,
    ) async {
      if (!doc.exists) return false;

      final userData = doc.data()!;
      final assignedCourseIds = List<String>.from(
        userData['assignedCourseIds'] ?? [],
      );

      // If no courses assigned, subscription likely expired
      if (assignedCourseIds.isEmpty) {
        return false;
      }

      // Double-check with subscription validation
      return await checkUserActiveSubscription(userId);
    });
  }

  /// Check if subscription is expiring soon (within specified days)
  Future<bool> isSubscriptionExpiringSoon(
    String userId, {
    int daysThreshold = 7,
  }) async {
    try {
      final subscriptions = await getUserSubscriptions(userId);

      for (final subscription in subscriptions) {
        final status = subscription['status'] as String?;
        // Use effectiveEndDate which accounts for exam date
        final effectiveEndDate = subscription['effectiveEndDate'] as DateTime?;

        if (status == 'active' && effectiveEndDate != null) {
          final daysUntilExpiry = effectiveEndDate.difference(DateTime.now()).inDays;
          if (daysUntilExpiry <= daysThreshold && daysUntilExpiry > 0) {
            Logger.i('⚠️ Subscription expiring in $daysUntilExpiry days (effective end date)');
            return true;
          }
        }
      }

      return false;
    } catch (error) {
      Logger.e('❌ Error checking subscription expiry: $error');
      return false;
    }
  }

  /// Clear subscription cache for a specific user or all users
  static void clearCache([String? userId]) {
    if (userId != null) {
      _subscriptionCache.remove(userId);
      Logger.i('🧹 Cleared subscription cache for user: $userId');
    } else {
      _subscriptionCache.clear();
      Logger.i('🧹 Cleared all subscription cache');
    }
  }

  /// Fast, offline-capable local check using cached subscription data.
  ///
  /// Compares the cached `endDate` against the user's current local time.
  /// Returns:
  /// - `true`  — subscription endDate is in the future (still valid)
  /// - `false` — subscription endDate is in the past (expired)
  /// - `null`  — no cached data available (need a server call)
  ///
  /// This does NOT hit the server and is safe to call frequently.
  bool? isSubscriptionLocallyValid(String userId) {
    final cachedData = _subscriptionCache[userId];
    if (cachedData == null || cachedData.subscriptions.isEmpty) {
      Logger.i('📌 No cached subscription data for local validation (user: $userId)');
      return null; // Unknown — need a server call
    }

    final now = DateTime.now();

    // Check if any cached subscription is still active based on local time
    final hasLocallyValid = cachedData.subscriptions.any((subscription) {
      final status = subscription['status'] as String?;
      // Use effectiveEndDate which accounts for exam date
      final effectiveEndDate = subscription['effectiveEndDate'] as DateTime?;

      if (status != 'active' || effectiveEndDate == null) return false;

      final isValid = effectiveEndDate.isAfter(now);
      if (isValid) {
        final remaining = effectiveEndDate.difference(now);
        Logger.i(
          '⏰ Subscription locally valid — '
          '${remaining.inDays}d ${remaining.inHours % 24}h remaining '
          '(effective end: ${effectiveEndDate.toLocal()})',
        );
      }
      return isValid;
    });

    Logger.i(
      '📌 Local subscription validation for $userId: '
      '${hasLocallyValid ? "VALID" : "EXPIRED"} (checked at ${now.toLocal()})',
    );
    return hasLocallyValid;
  }

  /// Get the latest active subscription effective end date from cached data.
  /// Uses effectiveEndDate (which accounts for exam date).
  /// Returns null if no cached active subscription exists.
  DateTime? getActiveSubscriptionEndDate(String userId) {
    final cachedData = _subscriptionCache[userId];
    if (cachedData == null) return null;

    DateTime? latestEndDate;

    for (final subscription in cachedData.subscriptions) {
      final status = subscription['status'] as String?;
      // Use effectiveEndDate which accounts for exam date
      final effectiveEndDate = subscription['effectiveEndDate'] as DateTime?;

      if (status == 'active' && effectiveEndDate != null) {
        if (latestEndDate == null || effectiveEndDate.isAfter(latestEndDate)) {
          latestEndDate = effectiveEndDate;
        }
      }
    }

    return latestEndDate;
  }
}

/// Cache data structure for subscription information
class _CachedSubscriptionData {
  final List<Map<String, dynamic>> subscriptions;
  final DateTime timestamp;

  _CachedSubscriptionData({
    required this.subscriptions,
    required this.timestamp,
  });
}

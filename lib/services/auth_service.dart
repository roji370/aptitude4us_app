import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'auth_persistence_service.dart';
import '../services/notification_service.dart'; // Add this import
import 'subscription_service.dart';
import '../utils/logger.dart';
import '../main.dart'; // For FirebaseInitHelper

class AuthService {
  // Flags to indicate operational mode
  bool _isFirebaseAvailable = true;
  bool _isFirestoreAvailable = true;

  // Getter for Firebase availability status
  bool get isFirebaseAvailable => _isFirebaseAvailable;

  // Firebase instances
  FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;

  // Subscription monitoring
  final SubscriptionService _subscriptionService = SubscriptionService();
  StreamSubscription<bool>? _subscriptionStatusSubscription;
  bool? _lastKnownSubscriptionStatus;

  AuthService() {
    _initializeServices();
  }

  Future<void> _initializeServices() async {
    // Import the FirebaseInitState from main.dart at the top of this file
    try {
      // Wait for Firebase to be initialized before accessing services
      await _waitForFirebaseAndInitialize();
    } catch (e) {
      Logger.e("Failed to initialize AuthService: $e");
      _isFirebaseAvailable = false;
      _isFirestoreAvailable = false;
    }
  }

  Future<void> _waitForFirebaseAndInitialize() async {
    // If Firebase is already initialized, proceed immediately
    if (_isFirebaseAvailable && _auth != null) {
      return;
    }

    try {
      // Wait for Firebase initialization to complete
      bool firebaseReady = await FirebaseInitHelper.ensureInitialized();

      if (!firebaseReady) {
        throw Exception("Firebase initialization failed");
      }

      _auth = FirebaseAuth.instance;
      _firestore = FirebaseFirestore.instance;
      _isFirebaseAvailable = true;
      _isFirestoreAvailable = true;

      // Try to restore user session
      await _restoreUserSession();
      Logger.i("AuthService: Firebase services initialized successfully");
    } catch (e) {
      Logger.e("AuthService: Failed to initialize Firebase services: $e");
      _isFirebaseAvailable = false;
      _isFirestoreAvailable = false;

      // Schedule retry after a delay
      Timer(const Duration(seconds: 2), () {
        _waitForFirebaseAndInitialize();
      });
    }
  }

  // Restore user session from persistent storage
  Future<void> _restoreUserSession() async {
    if (!_isFirebaseAvailable || _auth == null) return;

    // Check if we have a stored token
    bool isLoggedIn = await AuthPersistenceService.isLoggedIn();
    Logger.i("Restore session check - User logged in: $isLoggedIn");

    if (isLoggedIn) {
      Logger.i(
        "User was previously logged in, session should be restored by Firebase",
      );
    }
  }

  // Get current user
  User? get currentUser => _isFirebaseAvailable ? _auth?.currentUser : null;

  // Check if user is logged in
  bool get isUserLoggedIn => currentUser != null;

  // Auth state changes stream
  Stream<User?> get authStateChanges =>
      _isFirebaseAvailable && _auth != null
          ? _auth!.authStateChanges()
          : Stream.value(null);

  // ID token changes stream - use this to detect custom claims changes
  Stream<User?> get idTokenChanges =>
      _isFirebaseAvailable && _auth != null
          ? _auth!.idTokenChanges()
          : Stream.value(null);

  // Get custom claims from the ID token
  Future<Map<String, dynamic>> getCustomClaims() async {
    if (!_isFirebaseAvailable || currentUser == null) {
      return {};
    }

    try {
      final idTokenResult = await currentUser!.getIdTokenResult();
      return idTokenResult.claims ?? {};
    } catch (e) {
      Logger.e("Error getting custom claims: $e");
      return {};
    }
  }

  // Get user's role from custom claims
  Future<String> getUserRole() async {
    final claims = await getCustomClaims();
    return claims['role'] as String? ??
        'student'; // Default to student if no role
  }

  // Get user's assigned course IDs from custom claims
  Future<List<String>> getAssignedCourseIds() async {
    final claims = await getCustomClaims();

    // Handle different types of data in the claims
    if (claims['assignedCourseIds'] is List) {
      return List<String>.from(claims['assignedCourseIds'] as List);
    } else if (claims['assignedCourseIds'] is Map) {
      // If stored as a map with keys as course IDs
      return (claims['assignedCourseIds'] as Map).keys.toList().cast<String>();
    }

    return []; // Default to empty list if no assigned courses
  }

  // Sign in with email and password
  Future<UserCredential?> signInWithEmailAndPassword(
    String email,
    String password,
  ) async {
    if (!_isFirebaseAvailable) {
      throw Exception("Firebase Auth is not available");
    }

    try {
      UserCredential? result = await _auth!.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Store authentication data if login successful
      if (result.user != null) {
        String? token = await result.user!.getIdToken();
        await AuthPersistenceService.saveAuthToken(token!);

        // Get custom claims and user data
        final claims = await getCustomClaims();
        final userRole = claims['role'] as String? ?? 'student';

        List<String> assignedCourseIds = [];
        if (claims['assignedCourseIds'] is List) {
          assignedCourseIds = List<String>.from(
            claims['assignedCourseIds'] as List,
          );
        } else if (claims['assignedCourseIds'] is Map) {
          assignedCourseIds =
              (claims['assignedCourseIds'] as Map).keys.toList().cast<String>();
        }

        // Still get the user model for other data, but use claims for role and permissions
        UserModel? userModel = await getUserData();
        if (userModel != null) {
          // Update the user model with claims data if needed
          userModel = UserModel(
            uid: userModel.uid,
            displayName: userModel.displayName,
            email: userModel.email,
            role: userRole, // Use role from claims
            assignedCourseIds:
                assignedCourseIds, // Use assigned courses from claims
            password: userModel.password,
          );

          await AuthPersistenceService.saveUserData(userModel);
        }

        // Log the successful login
        await _logLoginEvent(result.user!.uid);

        // Start subscription monitoring for real-time access control
        startSubscriptionMonitoring();
      }

      return result;
    } catch (e) {
      String errorMsg = e.toString();
      Logger.e("Error during sign in: $e");

      // Check for the specific error message from the screenshot
      if (errorMsg.contains("'List<Object?>") ||
          errorMsg.contains("PigeonUserDetails") ||
          errorMsg.contains("not a subtype")) {
        Logger.w(
          "Firebase Auth plugin version compatibility issue detected: $errorMsg",
        );

        // Store auth token to indicate user is logged in despite error
        await AuthPersistenceService.saveAuthToken("recovery-token");

        // Store basic user data from email
        UserModel recoveryUser = UserModel(
          uid: 'temp-uid',
          displayName: email.split('@')[0],
          email: email,
          role: 'student',
          assignedCourseIds: [],
        );
        await AuthPersistenceService.saveUserData(recoveryUser);

        // Return null instead of throwing an error
        return null;
      }
      rethrow;
    }
  }

  // Log login events to Firestore
  Future<void> _logLoginEvent(String userId) async {
    if (!_isFirestoreAvailable) {
      Logger.w("Firestore not available, cannot log login event");
      return;
    }

    try {
      await _firestore!.collection('login_events').add({
        'userId': userId,
        'timestamp': FieldValue.serverTimestamp(),
        'platform': defaultTargetPlatform.toString(),
      });
      Logger.i("Login event logged successfully");
    } catch (e) {
      Logger.e("Error logging login event: $e");
    }
  }

  // Sign out
  Future<void> signOut() async {
    if (!_isFirebaseAvailable) return;

    try {
      Logger.i("Signing out user...");

      // Clear persistent storage first
      await AuthPersistenceService.clearAll();
      Logger.i("Auth persistence cleared");

      // Get notification service to clean up tokens
      NotificationService notificationService = NotificationService();

      // Sign out from Firebase last
      await _auth!.signOut();
      Logger.i("Firebase sign out completed");

      // Clean up notification tokens AFTER Firebase sign out
      try {
        await notificationService.deleteToken();
        Logger.i("FCM token cleanup completed after logout");
      } catch (error) {
        Logger.w(
          "Non-critical error cleaning up FCM token after logout: $error",
        );
      }

      // Stop subscription monitoring
      stopSubscriptionMonitoring();

      // Clear subscription cache to ensure fresh data for next login
      SubscriptionService.clearCache();

      Logger.i("User successfully signed out");
    } catch (e) {
      Logger.e("Error during sign out: $e");
      rethrow;
    }
  }

  // Get user data from Firestore
  Future<UserModel?> getUserData() async {
    if (!_isFirebaseAvailable || !_isFirestoreAvailable) {
      throw Exception("Firebase or Firestore is not available");
    }

    try {
      User? user = currentUser;
      if (user == null) return null;

      // Get custom claims first
      final claims = await getCustomClaims();
      final userRole = claims['role'] as String? ?? 'student';

      List<String> assignedCourseIds = [];
      if (claims['assignedCourseIds'] is List) {
        assignedCourseIds = List<String>.from(
          claims['assignedCourseIds'] as List,
        );
      } else if (claims['assignedCourseIds'] is Map) {
        assignedCourseIds =
            (claims['assignedCourseIds'] as Map).keys.toList().cast<String>();
      }

      // Get additional user data from Firestore
      DocumentSnapshot userDoc =
          await _firestore!.collection('users').doc(user.uid).get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        return UserModel(
          uid: user.uid,
          displayName: userData['displayName'] ?? '',
          email: userData['email'] ?? '',
          role: userRole, // Use role from claims
          assignedCourseIds:
              assignedCourseIds, // Use assigned courses from claims
          password: userData['password'],
        );
      }

      // User document doesn't exist in Firestore
      Logger.i("User document not found in Firestore for UID: ${user.uid}");

      // Return basic user data from Firebase Auth and claims
      return UserModel(
        uid: user.uid,
        displayName: user.displayName ?? '',
        email: user.email ?? '',
        role: userRole,
        assignedCourseIds: assignedCourseIds,
        password: null,
      );
    } catch (e) {
      Logger.e("Error getting user data: $e");
      rethrow;
    }
  }

  // Force token refresh (to update custom claims)
  Future<void> forceTokenRefresh() async {
    if (!_isFirebaseAvailable) {
      throw Exception("Firebase Auth is not available");
    }

    try {
      await currentUser?.getIdToken(true);
    } catch (e) {
      rethrow;
    }
  }

  // Verify and refresh token to ensure custom claims are up to date
  Future<Map<String, dynamic>> verifyAndRefreshClaims() async {
    if (!_isFirebaseAvailable || currentUser == null) {
      Logger.w("Firebase not available or user not logged in");
      return {};
    }

    try {
      // First get current claims
      final idTokenResult = await currentUser!.getIdTokenResult();
      final currentClaims = idTokenResult.claims ?? {};

      Logger.i("Current custom claims: $currentClaims");

      // Check if assignedCourseIds exists in claims
      if (!currentClaims.containsKey('assignedCourseIds')) {
        Logger.i("No assignedCourseIds in claims, forcing refresh...");

        // Force token refresh
        await forceTokenRefresh();

        // Get updated claims
        final newTokenResult = await currentUser!.getIdTokenResult();
        final newClaims = newTokenResult.claims ?? {};

        Logger.i("Updated custom claims after refresh: $newClaims");
        return newClaims;
      }

      return currentClaims;
    } catch (e) {
      Logger.e("Error verifying claims: $e");
      return {};
    }
  }

  // Change password
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    if (!_isFirebaseAvailable) {
      throw Exception("Firebase Auth is not available");
    }

    User? user = currentUser;
    if (user == null) {
      throw Exception("No user is currently signed in");
    }

    try {
      // Re-authenticate the user first
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Update the password in Firebase Authentication
      await user.updatePassword(newPassword);

      // Also update the password in Firestore (if available)
      if (_isFirestoreAvailable && _firestore != null) {
        await _firestore!.collection('users').doc(user.uid).update({
          'password': newPassword, // Store the password in Firestore
        });
        Logger.i("Password updated in Firestore for user: ${user.uid}");
      }
    } catch (e) {
      if (e is FirebaseAuthException) {
        if (e.code == 'wrong-password') {
          throw Exception("Incorrect current password");
        } else if (e.code == 'weak-password') {
          throw Exception(
            "New password is too weak. Please use a stronger password",
          );
        } else {
          throw Exception("Authentication error: ${e.message}");
        }
      } else {
        throw Exception("An error occurred: $e");
      }
    }
  }

  // Emergency sign out - bypasses token cleanup for cases where normal logout fails
  Future<void> emergencySignOut() async {
    if (!_isFirebaseAvailable) {
      throw Exception("Firebase Auth is not available");
    }

    Logger.i("EMERGENCY LOGOUT: Bypassing token cleanup");

    try {
      // Just clear auth data and sign out
      await AuthPersistenceService.clearAll();
      await _auth!.signOut();

      // Clear subscription cache
      SubscriptionService.clearCache();

      Logger.i("Emergency logout successful");
    } catch (e) {
      Logger.e("Error during emergency sign out: $e");
      // Try one more approach if even this fails
      try {
        _auth!.signOut();
        // Clear subscription cache even in fallback
        SubscriptionService.clearCache();
      } catch (finalError) {
        Logger.e("Final attempt at logout failed: $finalError");
      }
    }
  }

  /// Start monitoring user's subscription status for real-time changes
  void startSubscriptionMonitoring() {
    final currentUser = _auth?.currentUser;
    if (currentUser == null) {
      Logger.w(
        '🔍 Cannot start subscription monitoring: No authenticated user',
      );
      return;
    }

    // Cancel existing subscription if any
    _subscriptionStatusSubscription?.cancel();

    Logger.i('🔍 Starting subscription monitoring for user ${currentUser.uid}');

    _subscriptionStatusSubscription = _subscriptionService
        .subscriptionStatusStream(currentUser.uid)
        .listen(
          (hasActiveSubscription) {
            Logger.i('🔍 Subscription status update: $hasActiveSubscription');

            // Check if status has changed
            if (_lastKnownSubscriptionStatus != null &&
                _lastKnownSubscriptionStatus != hasActiveSubscription) {
              if (!hasActiveSubscription) {
                Logger.w(
                  '⚠️ Subscription expired! User access should be restricted',
                );
                _handleSubscriptionExpired();
              } else {
                Logger.i(
                  '✅ Subscription restored! User access should be granted',
                );
                _handleSubscriptionRestored();
              }
            }

            _lastKnownSubscriptionStatus = hasActiveSubscription;
          },
          onError: (error) {
            Logger.e('❌ Error in subscription monitoring: $error');
          },
        );
  }

  /// Stop monitoring subscription status
  void stopSubscriptionMonitoring() {
    Logger.i('🔍 Stopping subscription monitoring');
    _subscriptionStatusSubscription?.cancel();
    _subscriptionStatusSubscription = null;
    _lastKnownSubscriptionStatus = null;
  }

  /// Handle subscription expiration
  void _handleSubscriptionExpired() {
    Logger.w('🚫 Handling subscription expiration');

    // Notify the app about subscription expiration
    // This could trigger navigation to subscription screen
    // or show appropriate UI feedback

    // For now, we'll just log it - the UI components will handle the restriction
    // when they check subscription status through ProtectedCourseContent
  }

  /// Handle subscription restoration
  void _handleSubscriptionRestored() {
    Logger.i('✅ Handling subscription restoration');

    // Notify the app about subscription restoration
    // This could trigger a refresh of available content
    // or show appropriate UI feedback
  }

  /// Get current subscription status
  Future<bool> hasActiveSubscription() async {
    final currentUser = _auth?.currentUser;
    if (currentUser == null) return false;

    return await _subscriptionService.checkUserActiveSubscription(
      currentUser.uid,
    );
  }

  /// Get detailed subscription status
  Future<Map<String, dynamic>?> getSubscriptionStatus() async {
    return await _subscriptionService.getCurrentUserSubscriptionStatus();
  }

  /// Check if user has access to specific course
  Future<bool> hasAccessToCourse(String courseId) async {
    final currentUser = _auth?.currentUser;
    if (currentUser == null) return false;

    return await _subscriptionService.hasAccessToCourse(
      currentUser.uid,
      courseId,
    );
  }

  /// Dispose method to clean up resources
  void dispose() {
    stopSubscriptionMonitoring();
  }
}

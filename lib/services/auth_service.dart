import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import 'auth_persistence_service.dart';
import '../services/notification_service.dart'; // Add this import
import 'subscription_service.dart';
import '../utils/logger.dart';
import '../utils/device_id.dart';
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
      
      // Wait a bit for Firebase to restore the session
      await Future.delayed(const Duration(milliseconds: 500));
      
      // If Firebase has restored the user, start subscription monitoring
      if (_auth!.currentUser != null) {
        Logger.i("Firebase session restored successfully, starting subscription monitoring");
        startSubscriptionMonitoring();
      } else {
        Logger.w("Firebase session not yet restored, will be handled by auth state listener");
      }
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

  // Sign in with device restriction validation (improved version)
  Future<UserCredential> loginWithDeviceRestriction(
    String email, 
    String password
  ) async {
    if (!_isFirebaseAvailable) {
      throw Exception("Firebase Auth is not available");
    }

    try {
      // Get device information
      final deviceId = await getDeviceId();
      final deviceInfo = await getDeviceInfoString();
      
      Logger.i("Attempting login with device restriction for device: $deviceId");

      // First, sign in with Firebase Auth
      final cred = await _auth!.signInWithEmailAndPassword(
        email: email, 
        password: password
      );
      
      final uid = cred.user!.uid;
      Logger.i("Firebase Auth successful for user: $uid");

      // Validate device using Cloud Functions.
      // IMPORTANT: Cloud Function failures (network, cold-start, quota) must NOT
      // lock the user out.  Only an explicit device-restriction denial blocks login.
      try {
        final callable = FirebaseFunctions.instance
            .httpsCallable('validateUserDevice',
                options: HttpsCallableOptions(
                    timeout: const Duration(seconds: 10)));
        final res = await callable.call({
          'userId': uid, 
          'currentDeviceId': deviceId
        });
        
        final validationResult = Map<String, dynamic>.from(res.data as Map);
        Logger.i("Device validation result: $validationResult");

        // Restriction not enabled — allow login normally
        if (validationResult['restrictionEnabled'] != true) {
          Logger.i("Device restriction not enabled, proceeding with normal login");
          await _completeDeviceRestrictedLogin(cred, email);
          return cred;
        }

        // First login from this device — register it, then allow
        if (validationResult['requiresRegistration'] == true) {
          Logger.i("Device registration required, registering device: $deviceId");
          try {
            await FirebaseFunctions.instance
                .httpsCallable('registerUserDevice')
                .call({
              'userId': uid,
              'deviceId': deviceId,
              'deviceInfo': deviceInfo,
            });
            Logger.i("Device registered successfully");
          } catch (regError) {
            // Registration failure is non-fatal — let the user in anyway
            Logger.w("Device registration failed (non-fatal): $regError");
          }
          await _completeDeviceRestrictedLogin(cred, email);
          return cred;
        }

        // Restriction is enabled and device is explicitly NOT valid — block login
        if (validationResult['isValid'] != true) {
          Logger.w("Device validation rejected — device not authorised");
          await _cleanupFailedAuth();
          throw FirebaseAuthException(
            code: 'device-restricted', 
            message: 'This account is restricted to a specific device. '
                'Please contact support if you believe this is an error.'
          );
        }

        // Device is valid
        Logger.i("Device validation successful, completing login");
        await _completeDeviceRestrictedLogin(cred, email);
        return cred;

      } on FirebaseAuthException {
        // Re-throw deliberate device-restriction rejections unchanged
        rethrow;
      } catch (cloudFunctionError) {
        // Cloud Function is unavailable (network, cold-start, quota etc.).
        // Do NOT sign the user out — just log the error and proceed.
        Logger.w(
          "Device validation unavailable (non-fatal), proceeding with login: "
          "$cloudFunctionError"
        );
        await _completeDeviceRestrictedLogin(cred, email);
        return cred;
      }
      
    } catch (e) {
      Logger.e("Error during device-restricted login: $e");
      
      // Handle specific device restriction error
      if (e is FirebaseAuthException && e.code == 'device-restricted') {
        rethrow;
      }
      
      // Re-throw other authentication errors (wrong password, user-not-found, etc.)
      rethrow;
    }
  }

  // Helper method to clean up failed authentication attempts
  Future<void> _cleanupFailedAuth() async {
    try {
      Logger.i("Cleaning up failed authentication attempt");
      
      // Sign out from Firebase
      if (_auth != null) {
        await _auth!.signOut();
      }
      
      // Clear any stored authentication data
      await AuthPersistenceService.clearAll();
      
      // Clear subscription cache
      SubscriptionService.clearCache();
      
      Logger.i("Authentication cleanup completed");
    } catch (cleanupError) {
      Logger.e("Error during authentication cleanup: $cleanupError");
      // Continue despite cleanup errors
    }
  }

  // Helper method to complete the login process for device-restricted login
  Future<void> _completeDeviceRestrictedLogin(UserCredential result, String email) async {
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

      // Get user model
      UserModel? userModel = await getUserData();
      if (userModel != null) {
        userModel = UserModel(
          uid: userModel.uid,
          displayName: userModel.displayName,
          email: userModel.email,
          role: userRole,
          assignedCourseIds: assignedCourseIds,
          password: userModel.password,
        );

        await AuthPersistenceService.saveUserData(userModel);
      }

      // Log the successful login
      await _logLoginEvent(result.user!.uid);

      // Start subscription monitoring for real-time access control
      startSubscriptionMonitoring();
    }
  }

  // Method to re-validate device on app resume/start
  Future<bool> validateCurrentDevice() async {
    if (!_isFirebaseAvailable) {
      Logger.w("Firebase not available for device validation");
      return true; // Assume valid to avoid blocking users
    }
    
    if (currentUser == null) {
      Logger.w("No current user for device validation - assuming valid");
      return true; // Return true instead of false to avoid false negatives during session restoration
    }

    try {
      final deviceId = await getDeviceId();
      final uid = currentUser!.uid;
      
      Logger.i("Validating current device: $deviceId for user: $uid");

      final callable = FirebaseFunctions.instance.httpsCallable('validateUserDevice');
      final res = await callable.call({
        'userId': uid, 
        'currentDeviceId': deviceId
      });
      
      final validationResult = Map<String, dynamic>.from(res.data as Map);
      
      // If restriction is not enabled, device is valid
      if (validationResult['restrictionEnabled'] != true) {
        return true;
      }
      
      // If restriction is enabled, check if device is valid
      return validationResult['isValid'] == true;
      
    } catch (e) {
      Logger.e("Error validating current device: $e");
      // In case of error, assume device is valid to avoid blocking legitimate users
      return true;
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

        return UserModel.fromJson(userData, user.uid).copyWith(
          role: userRole, // Use role from claims
          assignedCourseIds: assignedCourseIds, // Use assigned courses from claims
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

  /// Update user profile with additional details
  Future<void> updateUserProfile({
    String? photoUrl,
    DateTime? dateOfJoining,
    DateTime? examDate,
    String? mobile,
    String? subscriptionPeriod,
  }) async {
    if (!_isFirebaseAvailable || !_isFirestoreAvailable) {
      throw Exception("Firebase or Firestore is not available");
    }

    try {
      User? user = currentUser;
      if (user == null) {
        throw Exception("No user logged in");
      }

      // Prepare update data
      Map<String, dynamic> updateData = {};
      
      if (photoUrl != null) updateData['photoUrl'] = photoUrl;
      if (dateOfJoining != null) {
        updateData['dateOfJoining'] = Timestamp.fromDate(dateOfJoining);
      }
      if (examDate != null) {
        updateData['examDate'] = Timestamp.fromDate(examDate);
      }
      if (mobile != null) updateData['mobile'] = mobile;
      if (subscriptionPeriod != null) {
        updateData['subscriptionPeriod'] = subscriptionPeriod;
      }
      
      // Mark profile as completed if all required fields are present
      if (photoUrl != null &&
          dateOfJoining != null &&
          examDate != null &&
          mobile != null &&
          subscriptionPeriod != null) {
        updateData['profileCompleted'] = true;
      }

      // Update Firestore
      await _firestore!
          .collection('users')
          .doc(user.uid)
          .set(updateData, SetOptions(merge: true));

      Logger.i("User profile updated successfully for UID: ${user.uid}");

      // Update local persisted data (non-critical - don't fail if this errors)
      try {
        UserModel? userData = await getUserData();
        if (userData != null) {
          await AuthPersistenceService.saveUserData(userData);
          Logger.i("Local user data cache updated successfully");
        }
      } catch (cacheError) {
        // Don't fail the whole operation if cache update fails
        // The data is already saved to Firestore (the source of truth)
        Logger.w("Failed to update local cache (non-critical): $cacheError");
      }
    } catch (e) {
      Logger.e("Error updating user profile: $e");
      rethrow;
    }
  }

  /// Check if user profile is complete
  Future<bool> isProfileComplete() async {
    try {
      final userData = await getUserData();
      if (userData == null) return false;
      
      return userData.isProfileComplete;
    } catch (e) {
      Logger.e("Error checking profile completion: $e");
      return false;
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

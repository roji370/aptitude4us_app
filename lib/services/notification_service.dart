import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:awesome_notifications/awesome_notifications.dart';
import '../utils/logger.dart';
import '../utils/global_keys.dart';
import '../main.dart' show FirebaseInitHelper; // For FirebaseInitHelper

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  // Singleton pattern
  factory NotificationService() => _instance;

  NotificationService._internal();

  FirebaseMessaging? _firebaseMessaging;
  FirebaseAuth? _auth;

  // Use global navigator key from main.dart to avoid early instantiation

  // Track if the service has been initialized
  bool _isInitialized = false;

  /// Initialize Firebase services
  Future<void> _initializeFirebaseServices() async {
    if (_firebaseMessaging != null && _auth != null) return;

    try {
      // Wait for Firebase to be initialized
      await FirebaseInitHelper.ensureInitialized();

      _firebaseMessaging = FirebaseMessaging.instance;
      _auth = FirebaseAuth.instance;
      Logger.i("NotificationService: Firebase services initialized");
    } catch (e) {
      Logger.e(
        "NotificationService: Failed to initialize Firebase services: $e",
      );
      // Services will remain null, methods should handle this gracefully
    }
  }

  /// Initialize the notification service
  Future<void> initialize() async {
    // Prevent multiple initializations
    if (_isInitialized) return;

    // Ensure Firebase services are ready first
    await _initializeFirebaseServices();

    // Initialize Awesome Notifications
    await AwesomeNotifications().initialize(
      null, // no icon for now, it will use the default app icon
      [
        NotificationChannel(
          channelKey: 'chat_channel',
          channelName: 'Chat Notifications',
          channelDescription: 'Notifications for new chat messages',
          defaultColor: Colors.blue,
          ledColor: Colors.blue,
          importance: NotificationImportance.High,
          channelShowBadge: true,
          enableVibration: true,
          enableLights: true,
          soundSource: 'resource://raw/notification_sound',
          playSound: true,
        ),
      ],
    );

    // Request notification permissions
    await AwesomeNotifications().isNotificationAllowed().then((
      isAllowed,
    ) async {
      if (!isAllowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });

    // Request FCM permissions
    if (_firebaseMessaging != null) {
      NotificationSettings settings = await _firebaseMessaging!
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
            criticalAlert: true,
          );

      Logger.i('User notification settings: ${settings.authorizationStatus}');

      // Configure FCM for specific platforms
      if (!kIsWeb) {
        // iOS-specific setup for foreground notifications
        await _firebaseMessaging!.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }
    } else {
      Logger.w('Firebase Messaging not available, skipping FCM setup');
    }

    // Clean up tokens and refresh token for current user if logged in
    String? userId = _auth?.currentUser?.uid;
    if (userId != null) {
      try {
        // Perform comprehensive token cleanup
        await cleanupTokens();
        Logger.i('Token cleanup completed during initialization');
      } catch (e) {
        Logger.e('Error during token cleanup in initialization: $e');

        // If cleanup fails, try force refresh as fallback
        try {
          String? token = await refreshToken();
          Logger.i(
            'FCM Token refreshed during initialization: ${token ?? 'Failed'}',
          );
        } catch (e) {
          Logger.e('Error refreshing token during initialization: $e');
        }
      }
    } else {
      Logger.i('No user logged in during initialization');
    }

    // Also listen for auth state changes to refresh token on login
    if (_auth != null) {
      _auth!.authStateChanges().listen((User? user) {
        if (user != null) {
          // User logged in, run cleanup and refresh token
          cleanupTokens()
              .then((_) {
                Logger.i('Token cleanup completed after login');
              })
              .catchError((e) {
                Logger.e('Error during token cleanup after login: $e');
              });
        }
      });
    }

    // Handle token refresh
    if (_firebaseMessaging != null) {
      _firebaseMessaging!.onTokenRefresh.listen((token) {
        Logger.i('FCM token refreshed automatically: $token');
        _saveTokenToFirestore(token);
      });
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle when app is opened from terminated state
    if (_firebaseMessaging != null) {
      RemoteMessage? initialMessage =
          await _firebaseMessaging!.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    }

    // Handle when app is in background but opened
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Setup Awesome Notifications action handlers
    await AwesomeNotifications().setListeners(
      onActionReceivedMethod: _onNotificationAction,
      onNotificationCreatedMethod: _onNotificationCreated,
      onNotificationDisplayedMethod: _onNotificationDisplayed,
      onDismissActionReceivedMethod: _onDismissActionReceived,
    );

    // Mark as initialized
    _isInitialized = true;
  }

  /// Force refresh the FCM token and save it to Firestore
  Future<String?> refreshToken() async {
    if (_firebaseMessaging == null || _auth == null) {
      Logger.w('Firebase services not available for token refresh');
      return null;
    }

    try {
      // Delete existing token first to force a new one
      try {
        await _firebaseMessaging!.deleteToken();
        Logger.i('Deleted existing FCM token to force refresh');
      } catch (e) {
        Logger.e('Error deleting existing FCM token: $e');
        // Continue anyway to get a fresh token
      }

      // Get a fresh token
      String? token = await _firebaseMessaging!.getToken();
      if (token != null) {
        Logger.i('New FCM Token: $token');

        // Store the token in Firestore
        await _saveTokenToFirestore(token);

        // Ensure we're subscribed to topics
        String? userId = _auth!.currentUser?.uid;
        if (userId != null) {
          ensureTopicSubscriptions(userId);
        }

        return token;
      } else {
        Logger.w('Failed to get FCM token');
        return null;
      }
    } catch (e) {
      Logger.e('Error refreshing FCM token: $e');
      return null;
    }
  }

  /// Ensure user is subscribed to all required topics
  Future<void> ensureTopicSubscriptions(String userId) async {
    if (_firebaseMessaging == null) {
      Logger.w('Firebase Messaging not available for topic subscriptions');
      return;
    }

    try {
      Logger.i('Ensuring topic subscriptions for user $userId');

      // Get the current token
      String? currentToken = await _firebaseMessaging!.getToken();
      if (currentToken == null) {
        Logger.i('No current token available, skipping topic subscriptions');
        return;
      }

      // Deactivate all other tokens for this user
      await _deactivateAllOtherTokens(userId, currentToken);

      // Subscribe to user-specific topic
      await subscribeToTopic('user_$userId');
      Logger.i('Subscribed to topic: user_$userId');

      // Subscribe to chat topic
      await subscribeToTopic('chat');
      Logger.i('Subscribed to topic: chat');

      // Check notification permissions
      NotificationSettings settings =
          await _firebaseMessaging!.getNotificationSettings();
      Logger.i(
        'Current notification permission status: ${settings.authorizationStatus}',
      );

      // If permissions are not authorized, request them
      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        Logger.i(
          'Notification permissions not authorized, requesting permissions',
        );
        await requestNotificationPermissions();
      }
    } catch (e) {
      Logger.e('Error ensuring topic subscriptions: $e');
    }
  }

  /// Save FCM token to Firestore with user information
  Future<void> _saveTokenToFirestore(String token) async {
    String? userId = _auth?.currentUser?.uid;
    if (userId == null) {
      Logger.i('No user logged in, saving anonymous token');
      // If no user is logged in, we can still store the token
      // for anonymous or pre-login notifications
      try {
        await FirebaseFirestore.instance
            .collection('anonymous_tokens')
            .doc(token)
            .set({
              'token': token,
              'lastUpdated': FieldValue.serverTimestamp(),
              'platform': defaultTargetPlatform.toString(),
            });
      } catch (e) {
        Logger.e('Error saving anonymous token: $e');
      }
      return;
    }

    Logger.i('Saving FCM token for user: $userId');

    // 1. Get all tokens for this user
    try {
      final tokensSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('tokens')
              .get();

      Logger.i(
        'Found ${tokensSnapshot.docs.length} existing tokens for user $userId',
      );

      // 2. Delete all tokens except the current one
      int deletedCount = 0;
      for (var doc in tokensSnapshot.docs) {
        if (doc.id != token) {
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .doc(doc.id)
                .delete();
            Logger.i("Deleted old token from users collection: ${doc.id}");
          } catch (e) {
            Logger.e("Error deleting token from users collection: $e");
          }
          try {
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(doc.id)
                .delete();
            Logger.i(
              "Deleted old token from user_tokens collection: ${doc.id}",
            );
          } catch (e) {
            Logger.e("Error deleting token from user_tokens collection: $e");
          }
          deletedCount++;
        }
      }
      Logger.i('Deleted $deletedCount old tokens for user $userId');
    } catch (e) {
      Logger.e('Error getting user tokens for deletion: $e');
    }

    // 3. Clean up orphaned tokens in user_tokens collection
    try {
      final userTokensSnapshot =
          await FirebaseFirestore.instance
              .collection('user_tokens')
              .where('userId', isEqualTo: userId)
              .where('token', isNotEqualTo: token)
              .get();

      int orphanedCount = 0;
      for (var doc in userTokensSnapshot.docs) {
        try {
          await FirebaseFirestore.instance
              .collection('user_tokens')
              .doc(doc.id)
              .delete();
          Logger.i("Deleted orphaned token from user_tokens: ${doc.id}");
          orphanedCount++;
        } catch (e) {
          Logger.e("Error deleting orphaned token: $e");
        }
      }
      Logger.i(
        'Deleted $orphanedCount orphaned tokens from user_tokens collection',
      );
    } catch (e) {
      Logger.e("Error cleaning up orphaned tokens: $e");
    }

    // 4. Save the new token
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .doc(token)
          .set({
            'token': token,
            'lastUpdated': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.toString(),
            'device': defaultTargetPlatform.toString(),
            'userId': userId,
            'email': _auth?.currentUser?.email,
            'isActive': true,
          });
      Logger.i("Saved new token to users collection: $token");
    } catch (e) {
      Logger.e('Error saving token to users collection: $e');
    }

    try {
      await FirebaseFirestore.instance
          .collection('user_tokens')
          .doc(token)
          .set({
            'token': token,
            'userId': userId,
            'lastUpdated': FieldValue.serverTimestamp(),
            'platform': defaultTargetPlatform.toString(),
            'isActive': true,
          });
      Logger.i("Saved new token to user_tokens collection: $token");
    } catch (e) {
      Logger.e('Error saving token to user_tokens collection: $e');
    }

    // 5. Verify token was saved properly by checking if only one token exists
    try {
      final verificationSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('tokens')
              .get();

      Logger.i(
        'VERIFICATION: User now has ${verificationSnapshot.docs.length} tokens',
      );
      if (verificationSnapshot.docs.length > 1) {
        Logger.w('WARNING: Multiple tokens still exist after cleanup!');
      } else {
        Logger.i('SUCCESS: User has exactly one token after cleanup');
      }
    } catch (e) {
      Logger.e('Error verifying token count: $e');
    }

    // Subscribe to topics in the background
    subscribeToTopic('user_$userId').catchError((e) {
      Logger.e('Error subscribing to user topic: $e');
    });

    subscribeToTopic('chat').catchError((e) {
      Logger.e('Error subscribing to chat topic: $e');
    });

    Logger.i('FCM token saved successfully for user: $userId');
  }

  /// Handle notification tap to navigate to appropriate screen
  void _handleNotificationTap(RemoteMessage message) {
    Logger.i('Notification tapped: ${message.data}');

    // Handle navigation based on notification type
    if (message.data['type'] == 'chat') {
      final String? chatId = message.data['chatId'];
      if (chatId != null && globalNavigatorKey.currentState != null) {
        globalNavigatorKey.currentState!.pushNamed('/chat', arguments: chatId);
      }
    } else if (message.data['type'] == 'course') {
      final String? courseId = message.data['courseId'];
      if (courseId != null && globalNavigatorKey.currentState != null) {
        globalNavigatorKey.currentState!.pushNamed(
          '/course',
          arguments: courseId,
        );
      }
    } else if (message.data['type'] == 'announcement') {
      // Navigate to announcements screen
      if (globalNavigatorKey.currentState != null) {
        globalNavigatorKey.currentState!.pushNamed('/announcements');
      }
    }
  }

  /// Subscribe to a topic for targeted notifications
  Future<void> subscribeToTopic(String topic) async {
    if (_firebaseMessaging == null) {
      Logger.w('Firebase Messaging not available for topic subscription');
      return;
    }
    await _firebaseMessaging!.subscribeToTopic(topic);
    Logger.i('Subscribed to topic: $topic');
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (_firebaseMessaging == null) {
      Logger.w('Firebase Messaging not available for topic unsubscription');
      return;
    }
    await _firebaseMessaging!.unsubscribeFromTopic(topic);
    Logger.i('Unsubscribed from topic: $topic');
  }

  /// Get the current FCM token
  Future<String?> getToken() async {
    if (_firebaseMessaging == null) {
      Logger.w('Firebase Messaging not available for token retrieval');
      return null;
    }
    return await _firebaseMessaging!.getToken();
  }

  /// Check notification permissions status and return a detailed report
  Future<Map<String, dynamic>> checkNotificationPermissions() async {
    Map<String, dynamic> report = {};

    if (_firebaseMessaging == null) {
      report['error'] = 'Firebase Messaging not available';
      return report;
    }

    // Check FCM permissions
    NotificationSettings settings =
        await _firebaseMessaging!.getNotificationSettings();
    report['fcmAuthStatus'] = settings.authorizationStatus.toString();
    report['fcmAlertSetting'] = settings.alert.toString();
    report['fcmBadgeSetting'] = settings.badge.toString();
    report['fcmSoundSetting'] = settings.sound.toString();

    // Check if we have a token
    String? token = await getToken();
    report['hasToken'] = token != null;
    if (token != null) {
      report['tokenLength'] = token.length;

      // Check if token exists in Firestore
      String? userId = _auth?.currentUser?.uid;
      if (userId != null) {
        try {
          var doc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('tokens')
                  .doc(token)
                  .get();
          report['tokenInFirestore'] = doc.exists;
        } catch (e) {
          report['tokenInFirestore'] = false;
          report['firestoreError'] = e.toString();
        }
      }
    }

    // Check Awesome Notifications permissions
    bool isAwesomeNotificationsAllowed =
        await AwesomeNotifications().isNotificationAllowed();
    report['awesomeNotificationsAllowed'] = isAwesomeNotificationsAllowed;

    Logger.i('Notification permissions report: $report');
    return report;
  }

  /// Request notification permissions for both FCM and Awesome Notifications
  Future<NotificationSettings> requestNotificationPermissions() async {
    if (_firebaseMessaging == null) {
      // Return a default NotificationSettings if Firebase is not available
      Logger.w('Firebase Messaging not available for permission request');
      // Create a minimal settings object indicating not authorized
      return NotificationSettings(
        authorizationStatus: AuthorizationStatus.notDetermined,
        alert: AppleNotificationSetting.notSupported,
        badge: AppleNotificationSetting.notSupported,
        sound: AppleNotificationSetting.notSupported,
        carPlay: AppleNotificationSetting.notSupported,
        lockScreen: AppleNotificationSetting.notSupported,
        notificationCenter: AppleNotificationSetting.notSupported,
        showPreviews: AppleShowPreviewSetting.notSupported,
        timeSensitive: AppleNotificationSetting.notSupported,
        criticalAlert: AppleNotificationSetting.notSupported,
        announcement: AppleNotificationSetting.notSupported,
        providesAppNotificationSettings: AppleNotificationSetting.notSupported,
      );
    }

    // Request FCM permissions
    NotificationSettings settings = await _firebaseMessaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: true,
    );

    Logger.i('FCM permissions request result: ${settings.authorizationStatus}');

    // Request Awesome Notifications permissions
    await AwesomeNotifications().isNotificationAllowed().then((
      isAllowed,
    ) async {
      if (!isAllowed) {
        await AwesomeNotifications().requestPermissionToSendNotifications();
      }
    });

    return settings;
  }

  /// Delete FCM token when user logs out
  Future<void> deleteToken() async {
    if (_firebaseMessaging == null || _auth == null) {
      Logger.w('Firebase services not available for token deletion');
      return;
    }

    try {
      String? token = await _firebaseMessaging!.getToken();
      if (token == null) {
        Logger.i('No FCM token found to delete');
        return;
      }

      // Get user ID before signing out
      String? userId = _auth!.currentUser?.uid;
      if (userId == null) {
        Logger.i('No user logged in, no tokens to cleanup');
        return;
      }

      Logger.i('Logging out user $userId, cleaning up FCM token $token');

      // STEP 1: Mark the token as inactive first
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('tokens')
            .doc(token)
            .update({
              'isActive': false,
              'loggedOut': true,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
        Logger.i("Token marked as inactive in users collection");
      } catch (e) {
        Logger.e("Error marking token as inactive: $e");
      }

      try {
        await FirebaseFirestore.instance
            .collection('user_tokens')
            .doc(token)
            .update({
              'isActive': false,
              'loggedOut': true,
              'lastUpdated': FieldValue.serverTimestamp(),
            });
        Logger.i("Token marked as inactive in user_tokens collection");
      } catch (e) {
        Logger.e("Error marking token as inactive in user_tokens: $e");
      }

      // STEP 2: Delete the token
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('tokens')
            .doc(token)
            .delete();
        Logger.i("Token deleted from users collection");
      } catch (e) {
        Logger.e("Error deleting user token: $e");
      }

      try {
        await FirebaseFirestore.instance
            .collection('user_tokens')
            .doc(token)
            .delete();
        Logger.i("Token deleted from user_tokens collection");
      } catch (e) {
        Logger.e("Error deleting from user_tokens: $e");
      }

      // STEP 3: Delete ALL other tokens for this user as well (cleanup)
      try {
        final tokensSnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .get();

        Logger.i(
          'Found ${tokensSnapshot.docs.length} total tokens to clean up during logout',
        );

        int deletedCount = 0;
        for (var doc in tokensSnapshot.docs) {
          String tokenId = doc.id;

          // Mark as inactive first
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .doc(tokenId)
                .update({
                  'isActive': false,
                  'loggedOut': true,
                  'lastUpdated': FieldValue.serverTimestamp(),
                });
          } catch (e) {
            Logger.e("Error marking token $tokenId as inactive: $e");
          }

          // Then delete
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .doc(tokenId)
                .delete();
          } catch (e) {
            Logger.e("Error deleting token $tokenId: $e");
          }

          // Also delete from user_tokens collection
          try {
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(tokenId)
                .delete();
          } catch (e) {
            Logger.e('Error deleting token from user_tokens collection: $e');
          }

          deletedCount++;
        }

        Logger.i(
          'Deleted $deletedCount total tokens for user $userId during logout',
        );
      } catch (e) {
        Logger.e('Error deleting all tokens during logout: $e');
      }

      // STEP 4: Check for any orphaned tokens in user_tokens collection
      try {
        final userTokensSnapshot =
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .where('userId', isEqualTo: userId)
                .get();

        Logger.i(
          'Found ${userTokensSnapshot.docs.length} orphaned tokens in user_tokens collection',
        );

        for (var doc in userTokensSnapshot.docs) {
          try {
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(doc.id)
                .delete();
            Logger.i(
              "Deleted orphaned token ${doc.id} from user_tokens collection",
            );
          } catch (e) {
            Logger.e("Error deleting orphaned token: $e");
          }
        }
      } catch (e) {
        Logger.e("Error cleaning up orphaned tokens: $e");
      }

      // STEP 5: Unsubscribe from topics
      try {
        await unsubscribeFromTopic('user_$userId');
        Logger.i("Unsubscribed from user topic: user_$userId");
      } catch (e) {
        Logger.e("Error unsubscribing from user topic: $e");
      }

      try {
        await unsubscribeFromTopic('chat');
        Logger.i("Unsubscribed from chat topic");
      } catch (e) {
        Logger.e("Error unsubscribing from chat topic: $e");
      }

      // STEP 6: Delete the FCM token from Firebase
      try {
        if (_firebaseMessaging != null) {
          await _firebaseMessaging!.deleteToken();
          Logger.i("FCM token deleted from Firebase");
        } else {
          Logger.w("Firebase Messaging not available for token deletion");
        }
      } catch (e) {
        Logger.e("Error deleting FCM token from Firebase: $e");
      }

      // STEP 7: Verify cleanup was successful
      try {
        final verificationSnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .get();

        Logger.i(
          'VERIFICATION: User now has ${verificationSnapshot.docs.length} tokens after logout',
        );
        if (verificationSnapshot.docs.isNotEmpty) {
          Logger.w('WARNING: User still has tokens after cleanup!');
        } else {
          Logger.i('SUCCESS: All tokens deleted for user $userId');
        }
      } catch (e) {
        Logger.e('Error verifying token deletion: $e');
      }

      return;
    } catch (e) {
      Logger.e("Error in deleteToken: $e");
      // Don't rethrow, just log and continue
    }
  }

  /// Delete all tokens for a user except the current one
  Future<void> cleanupAllTokensExceptCurrent(String userId) async {
    try {
      Logger.i(
        'Starting deletion of all tokens for user $userId except current',
      );

      // Get the current token
      String? currentToken = await _firebaseMessaging?.getToken();
      if (currentToken == null) {
        Logger.i('No current token available, skipping deletion');
        return;
      }

      // Delete all other tokens
      await _deactivateAllOtherTokens(userId, currentToken);
    } catch (e) {
      Logger.e('Error during token deletion: $e');
    }
  }

  /// Delete all other tokens for a user except the current one
  Future<void> _deactivateAllOtherTokens(
    String userId,
    String currentToken,
  ) async {
    try {
      Logger.i(
        'Deleting all other tokens for user $userId except $currentToken',
      );

      // Get all tokens for this user
      final tokensSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('tokens')
              .get();

      int totalTokens = tokensSnapshot.docs.length;
      Logger.i('Found $totalTokens total tokens for user $userId');

      int deletedCount = 0;

      // Process all tokens except the current one
      for (var doc in tokensSnapshot.docs) {
        String tokenId = doc.id;
        if (tokenId != currentToken) {
          // Directly delete from user's tokens collection
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .doc(tokenId)
                .delete();
            Logger.i("Token $tokenId deleted from users collection");
          } catch (e) {
            Logger.e("Error deleting token $tokenId from users collection: $e");
          }

          // Also delete from user_tokens collection
          try {
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(tokenId)
                .delete();
            Logger.i("Token $tokenId deleted from user_tokens collection");
          } catch (e) {
            Logger.e("Error deleting token $tokenId from user_tokens: $e");
          }

          deletedCount++;
        }
      }

      Logger.i('Deleted $deletedCount tokens for user $userId');

      // Also check for any orphaned tokens in user_tokens collection
      try {
        final userTokensSnapshot =
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .where('userId', isEqualTo: userId)
                .where('token', isNotEqualTo: currentToken)
                .get();

        for (var doc in userTokensSnapshot.docs) {
          String tokenId = doc.id;
          try {
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(tokenId)
                .delete();
            Logger.i(
              "Deleted orphaned token $tokenId from user_tokens collection",
            );
          } catch (e) {
            Logger.e("Error deleting orphaned token $tokenId: $e");
          }
        }
      } catch (e) {
        Logger.e("Error cleaning up orphaned tokens: $e");
      }
    } catch (e) {
      Logger.e('Error in _deactivateAllOtherTokens: $e');
    }
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    Logger.i('Got a message whilst in the foreground!');
    Logger.i('Message data: ${message.data}');

    // Get current FCM token
    String? currentToken = await _firebaseMessaging?.getToken();

    // Check if this is a self-notification (from the same device)
    if (message.data['senderFcmToken'] == currentToken) {
      Logger.i('Ignoring self-notification from same device');
      return;
    }

    // Handle both notification and data-only messages
    String title = message.notification?.title ?? 'New Message';
    String body = message.notification?.body ?? '';

    // For data-only messages or if notification fields are empty, try to use data fields
    if (title == 'New Message' && message.data.containsKey('title')) {
      title = message.data['title'] ?? title;
    }

    if (body.isEmpty && message.data.containsKey('body')) {
      body = message.data['body'] ?? '';
    }

    // Create a local notification using Awesome Notifications
    await AwesomeNotifications().createNotification(
      content: NotificationContent(
        id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
        channelKey: 'chat_channel',
        title: title,
        body: body,
        notificationLayout: NotificationLayout.Default,
        payload: Map<String, String>.from(message.data),
        category: NotificationCategory.Message,
        wakeUpScreen: true,
        criticalAlert: true,
      ),
    );

    Logger.i('Local notification created with title: $title');
  }

  /// Handle notification action
  @pragma('vm:entry-point')
  static Future<void> _onNotificationAction(
    ReceivedAction receivedAction,
  ) async {
    Logger.i('Notification action received: ${receivedAction.toString()}');
    // Handle the action based on the payload
    if (receivedAction.payload != null &&
        receivedAction.payload!['type'] == 'chat') {
      final String? chatId = receivedAction.payload!['chatId'];
      if (chatId != null && globalNavigatorKey.currentState != null) {
        globalNavigatorKey.currentState!.pushNamed('/chat', arguments: chatId);
      }
    }
  }

  /// Handle notification creation
  @pragma('vm:entry-point')
  static Future<void> _onNotificationCreated(
    ReceivedNotification receivedNotification,
  ) async {
    Logger.i('Notification created: ${receivedNotification.toString()}');
  }

  /// Handle notification display
  @pragma('vm:entry-point')
  static Future<void> _onNotificationDisplayed(
    ReceivedNotification receivedNotification,
  ) async {
    Logger.i('Notification displayed: ${receivedNotification.toString()}');
  }

  /// Handle notification dismissal
  @pragma('vm:entry-point')
  static Future<void> _onDismissActionReceived(
    ReceivedAction receivedAction,
  ) async {
    Logger.i('Notification dismissed: ${receivedAction.toString()}');
  }

  /// Handle app lifecycle changes to ensure tokens are properly managed
  Future<void> handleAppLifecycleChange(AppLifecycleState state) async {
    Logger.i("App lifecycle state changed to: $state");

    // Get current user ID
    String? userId = _auth?.currentUser?.uid;
    if (userId == null) {
      Logger.i(
        "No user logged in, skipping token management for lifecycle change",
      );
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        // App is in the foreground
        Logger.i("App resumed - refreshing FCM token");
        try {
          // Refresh token when app is resumed to ensure we have the latest
          await refreshToken();
        } catch (e) {
          Logger.e("Error refreshing token on resume: $e");
        }
        break;

      case AppLifecycleState.inactive:
        // App is inactive, about to enter another state
        break;

      case AppLifecycleState.paused:
        // App is in the background
        Logger.i("App paused - verifying token status");
        try {
          // Get current token
          String? token = await _firebaseMessaging?.getToken();
          if (token != null) {
            // Update token status to indicate it's still active
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .doc(token)
                .update({
                  'lastSeen': FieldValue.serverTimestamp(),
                  'isActive': true,
                });

            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(token)
                .update({
                  'lastSeen': FieldValue.serverTimestamp(),
                  'isActive': true,
                });
          }
        } catch (e) {
          Logger.e("Error updating token status on pause: $e");
        }
        break;

      case AppLifecycleState.detached:
        // App is terminated
        Logger.i("App detached - marking token as possibly inactive");
        try {
          // Get current token
          String? token = await _firebaseMessaging?.getToken();
          if (token != null) {
            // Update token status to indicate it might be inactive
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .doc(token)
                .update({
                  'lastSeen': FieldValue.serverTimestamp(),
                  'possiblyTerminated': true,
                });

            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(token)
                .update({
                  'lastSeen': FieldValue.serverTimestamp(),
                  'possiblyTerminated': true,
                });
          }
        } catch (e) {
          Logger.e("Error updating token status on detach: $e");
        }
        break;

      case AppLifecycleState.hidden:
        // App is hidden (minimized but still running)
        Logger.i("App hidden - updating token status");
        try {
          // Get current token
          String? token = await _firebaseMessaging?.getToken();
          if (token != null) {
            // Update token status to indicate it's still active but hidden
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .doc(token)
                .update({
                  'lastSeen': FieldValue.serverTimestamp(),
                  'appHidden': true,
                });
          }
        } catch (e) {
          Logger.e("Error updating token status on hidden: $e");
        }
        break;
    }
  }

  /// Perform a full cleanup of orphaned tokens for all users
  /// This should be called periodically to ensure token database stays clean
  Future<void> performFullTokenCleanup() async {
    try {
      Logger.i("Starting full token cleanup");

      // Get current user ID
      String? userId = _auth?.currentUser?.uid;
      if (userId == null) {
        Logger.i("No user logged in, skipping full token cleanup");
        return;
      }

      // Get current token
      String? currentToken = await _firebaseMessaging?.getToken();
      if (currentToken == null) {
        Logger.i("No current token available, skipping cleanup");
        return;
      }

      Logger.i("Current token: $currentToken for user: $userId");

      // STEP 1: Clean up user's own tokens
      try {
        // Get all tokens for this user
        final tokensSnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .get();

        Logger.i("Found ${tokensSnapshot.docs.length} tokens for user $userId");

        // Delete all tokens except the current one
        for (var doc in tokensSnapshot.docs) {
          String tokenId = doc.id;
          if (tokenId != currentToken) {
            try {
              // Directly delete without marking as inactive first
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('tokens')
                  .doc(tokenId)
                  .delete();

              Logger.i("Deleted token $tokenId for user $userId");
            } catch (e) {
              Logger.e("Error deleting token $tokenId: $e");
            }
          }
        }
      } catch (e) {
        Logger.e("Error cleaning up user tokens: $e");
      }

      // STEP 2: Clean up user_tokens collection for this user
      try {
        final userTokensSnapshot =
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .where('userId', isEqualTo: userId)
                .get();

        Logger.i(
          "Found ${userTokensSnapshot.docs.length} tokens in user_tokens for user $userId",
        );

        for (var doc in userTokensSnapshot.docs) {
          String tokenId = doc.id;
          if (tokenId != currentToken) {
            try {
              // Directly delete without marking as inactive first
              await FirebaseFirestore.instance
                  .collection('user_tokens')
                  .doc(tokenId)
                  .delete();

              Logger.i("Deleted token $tokenId from user_tokens collection");
            } catch (e) {
              Logger.e("Error deleting token from user_tokens: $e");
            }
          }
        }
      } catch (e) {
        Logger.e("Error cleaning up user_tokens: $e");
      }

      Logger.i("Token cleanup completed successfully");
    } catch (e) {
      Logger.e("Error in performFullTokenCleanup: $e");
    }
  }

  /// Clean up tokens based on lastUpdated timestamp, keeping only the most recent one
  Future<void> cleanupTokensByLastUpdated() async {
    try {
      Logger.i("Starting token cleanup based on lastUpdated timestamp");

      // Get current user ID
      String? userId = _auth?.currentUser?.uid;
      if (userId == null) {
        Logger.i("No user logged in, skipping token cleanup");
        return;
      }

      // STEP 1: Get all tokens for this user
      final tokensSnapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('tokens')
              .get();

      Logger.i("Found ${tokensSnapshot.docs.length} tokens for user $userId");

      // If there's only 0 or 1 token, no need to clean up
      if (tokensSnapshot.docs.length <= 1) {
        Logger.i(
          "No cleanup needed, found ${tokensSnapshot.docs.length} tokens",
        );
        return;
      }

      // STEP 2: Sort tokens by lastUpdated (newest first)
      List<QueryDocumentSnapshot> sortedDocs = tokensSnapshot.docs.toList();
      sortedDocs.sort((a, b) {
        final mapA = a.data() as Map<String, dynamic>?;
        final mapB = b.data() as Map<String, dynamic>?;

        Timestamp? timeA = mapA?['lastUpdated'] as Timestamp?;
        Timestamp? timeB = mapB?['lastUpdated'] as Timestamp?;

        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1; // Null timestamps are considered older
        if (timeB == null) return -1;
        return timeB.compareTo(timeA); // Sort descending (newest first)
      });

      // STEP 3: Keep only the most recent token
      String mostRecentTokenId = sortedDocs[0].id;
      Logger.i(
        "Most recent token is: $mostRecentTokenId (updated at: ${(sortedDocs[0].data() as Map<String, dynamic>)['lastUpdated']})",
      );

      // STEP 4: Delete all other tokens
      int deletedCount = 0;
      for (int i = 1; i < sortedDocs.length; i++) {
        String tokenId = sortedDocs[i].id;

        // Delete from user's tokens collection
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('tokens')
              .doc(tokenId)
              .delete();

          // Also delete from user_tokens collection
          await FirebaseFirestore.instance
              .collection('user_tokens')
              .doc(tokenId)
              .delete();

          deletedCount++;
          Logger.i("Deleted older token: $tokenId");
        } catch (e) {
          Logger.e("Error deleting token $tokenId: $e");
        }
      }

      Logger.i(
        "Deleted $deletedCount older tokens based on lastUpdated timestamp",
      );

      // STEP 5: Check for orphaned tokens in user_tokens collection
      try {
        final userTokensSnapshot =
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .where('userId', isEqualTo: userId)
                .where('token', isNotEqualTo: mostRecentTokenId)
                .get();

        for (var doc in userTokensSnapshot.docs) {
          try {
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .doc(doc.id)
                .delete();
            Logger.i(
              "Deleted orphaned token ${doc.id} from user_tokens collection",
            );
          } catch (e) {
            Logger.e("Error deleting orphaned token: $e");
          }
        }
      } catch (e) {
        Logger.e("Error cleaning up orphaned tokens: $e");
      }

      Logger.i("Token cleanup by lastUpdated completed successfully");
    } catch (e) {
      Logger.e("Error in cleanupTokensByLastUpdated: $e");
    }
  }

  /// Perform a comprehensive token cleanup operation
  /// This should be called periodically, especially after login
  Future<void> cleanupTokens() async {
    try {
      Logger.i("Starting comprehensive token cleanup");

      // Get current user ID
      String? userId = _auth?.currentUser?.uid;
      if (userId == null) {
        Logger.i("No user logged in, skipping token cleanup");
        return;
      }

      // Get current token
      String? currentToken = await _firebaseMessaging?.getToken();
      if (currentToken == null) {
        Logger.i("No current token available, skipping cleanup");
        return;
      }

      Logger.i("Current token: $currentToken for user: $userId");

      // STEP 1: First, ensure current token is properly saved
      await _saveTokenToFirestore(currentToken);

      // STEP 2: Verify cleanup was successful
      try {
        final tokensSnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .get();

        Logger.i(
          "VERIFICATION: Found ${tokensSnapshot.docs.length} tokens for user $userId",
        );

        if (tokensSnapshot.docs.length > 1) {
          Logger.w(
            "WARNING: Multiple tokens still exist after _saveTokenToFirestore cleanup!",
          );

          // STEP 3: Force cleanup by manually deleting all tokens except current
          int deletedCount = 0;
          for (var doc in tokensSnapshot.docs) {
            if (doc.id != currentToken) {
              try {
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('tokens')
                    .doc(doc.id)
                    .delete();

                await FirebaseFirestore.instance
                    .collection('user_tokens')
                    .doc(doc.id)
                    .delete();

                deletedCount++;
              } catch (e) {
                Logger.e("Error deleting token ${doc.id}: $e");
              }
            }
          }
          Logger.i("Force-deleted $deletedCount additional tokens");
        } else {
          Logger.i("SUCCESS: User has exactly one token after initial cleanup");
        }
      } catch (e) {
        Logger.e("Error verifying token count: $e");
      }

      // STEP 4: Check for orphaned tokens in user_tokens
      try {
        final userTokensSnapshot =
            await FirebaseFirestore.instance
                .collection('user_tokens')
                .where('userId', isEqualTo: userId)
                .get();

        int orphanCount = 0;
        for (var doc in userTokensSnapshot.docs) {
          if (doc.id != currentToken) {
            try {
              await FirebaseFirestore.instance
                  .collection('user_tokens')
                  .doc(doc.id)
                  .delete();
              orphanCount++;
            } catch (e) {
              Logger.e("Error deleting orphaned token: $e");
            }
          }
        }

        if (orphanCount > 0) {
          Logger.i(
            "Deleted $orphanCount orphaned tokens from user_tokens collection",
          );
        } else {
          Logger.i("No orphaned tokens found in user_tokens collection");
        }
      } catch (e) {
        Logger.e("Error cleaning up orphaned tokens: $e");
      }

      // STEP 5: Double-check by getting token count again
      try {
        final finalSnapshot =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('tokens')
                .get();

        Logger.i(
          "FINAL VERIFICATION: User has ${finalSnapshot.docs.length} tokens",
        );
        if (finalSnapshot.docs.length == 1) {
          Logger.i("SUCCESS: Token cleanup completed successfully");
        } else if (finalSnapshot.docs.length > 1) {
          Logger.w(
            "WARNING: User still has multiple tokens after thorough cleanup!",
          );
        } else if (finalSnapshot.docs.isEmpty) {
          Logger.w(
            "WARNING: User has no tokens after cleanup, saving current token again",
          );
          await _saveTokenToFirestore(currentToken);
        }
      } catch (e) {
        Logger.e("Error in final verification: $e");
      }

      // STEP 6: Ensure we're subscribed to topics
      try {
        await subscribeToTopic('user_$userId');
        await subscribeToTopic('chat');
        Logger.i("Verified topic subscriptions");
      } catch (e) {
        Logger.e("Error verifying topic subscriptions: $e");
      }

      Logger.i("Comprehensive token cleanup completed");
    } catch (e) {
      Logger.e("Error in cleanupTokens: $e");
    }
  }
}

// This needs to be a top-level function
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();

  // Using debugPrint in background handlers because Logger might not be accessible
  debugPrint('Handling a background message: ${message.messageId}');
  debugPrint('Background message data: ${message.data}');

  // Get current FCM token
  final FirebaseMessaging messaging = FirebaseMessaging.instance;
  String? currentToken = await messaging.getToken();

  // Check if this is a self-notification (from the same device)
  if (message.data['senderFcmToken'] == currentToken) {
    debugPrint('Ignoring self-notification from same device in background');
    return;
  }

  // Handle both notification and data-only messages
  String title = message.notification?.title ?? 'New Message';
  String body = message.notification?.body ?? '';

  // For data-only messages or if notification fields are empty, try to use data fields
  if (title == 'New Message' && message.data.containsKey('title')) {
    title = message.data['title'] ?? title;
  }

  if (body.isEmpty && message.data.containsKey('body')) {
    body = message.data['body'] ?? '';
  }

  // Create a notification even in background
  await AwesomeNotifications().createNotification(
    content: NotificationContent(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      channelKey: 'chat_channel',
      title: title,
      body: body,
      notificationLayout: NotificationLayout.Default,
      payload: Map<String, String>.from(message.data),
      category: NotificationCategory.Message,
      wakeUpScreen: true,
      criticalAlert: true,
    ),
  );

  debugPrint('Background notification created with title: $title');
}

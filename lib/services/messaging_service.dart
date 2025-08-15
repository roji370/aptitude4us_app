import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/logger.dart';
import '../main.dart' show FirebaseInitHelper;

class MessagingService {
  static final MessagingService _instance = MessagingService._internal();

  // Singleton pattern
  factory MessagingService() => _instance;

  MessagingService._internal();

  FirebaseMessaging? _firebaseMessaging;
  FirebaseAuth? _auth;

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
      Logger.i("MessagingService: Firebase services initialized");
    } catch (e) {
      Logger.e("MessagingService: Failed to initialize Firebase services: $e");
      // Services will remain null, methods should handle this gracefully
    }
  }

  /// Initialize the messaging service for chat functionality only
  Future<void> initialize() async {
    // Prevent multiple initializations
    if (_isInitialized) return;

    // Ensure Firebase services are ready first
    await _initializeFirebaseServices();

    if (_firebaseMessaging != null) {
      // Setup message handlers for chat messages
      _setupMessageHandlers();

      // Get and store FCM token for messaging
      await _refreshToken();

      Logger.i('MessagingService: Initialized successfully');
      _isInitialized = true;
    } else {
      Logger.w('Firebase Messaging not available, skipping setup');
    }
  }

  /// Setup Firebase message handlers for chat
  void _setupMessageHandlers() {
    if (_firebaseMessaging == null) return;

    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification taps when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

    Logger.i('MessagingService: Message handlers setup complete');
  }

  /// Handle foreground messages (app is open)
  void _handleForegroundMessage(RemoteMessage message) {
    Logger.i('Received foreground message: ${message.data}');

    // For chat messages, you might want to show an in-app notification
    // or update the chat UI directly instead of system notifications
    if (message.data['type'] == 'chat') {
      Logger.i('Chat message received in foreground');
      // Handle chat message (e.g., update chat UI, show badge, etc.)
    }
  }

  /// Handle message tap (when user taps notification)
  void _handleMessageTap(RemoteMessage message) {
    Logger.i('Message tapped: ${message.data}');

    // Navigate to appropriate screen based on message type
    if (message.data['type'] == 'chat') {
      // Navigation logic can be handled here or via a callback
      Logger.i('Navigating to chat from message tap');
    }
  }

  /// Get FCM token for this device
  Future<String?> getToken() async {
    if (_firebaseMessaging == null) return null;

    try {
      String? token = await _firebaseMessaging!.getToken();
      if (token != null) {
        Logger.i('FCM Token retrieved: ${token.substring(0, 20)}...');
      }
      return token;
    } catch (e) {
      Logger.e('Error getting FCM token: $e');
      return null;
    }
  }

  /// Refresh and save FCM token
  Future<void> _refreshToken() async {
    if (_firebaseMessaging == null || _auth?.currentUser == null) return;

    try {
      String? token = await getToken();
      if (token != null) {
        await _saveTokenToFirestore(token);
      }

      // Listen for token refresh
      _firebaseMessaging!.onTokenRefresh.listen((newToken) {
        Logger.i('FCM token refreshed');
        _saveTokenToFirestore(newToken);
      });
    } catch (e) {
      Logger.e('Error refreshing FCM token: $e');
    }
  }

  /// Save FCM token to Firestore for messaging
  Future<void> _saveTokenToFirestore(String token) async {
    if (_auth?.currentUser == null) return;

    try {
      String userId = _auth!.currentUser!.uid;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tokens')
          .doc(token)
          .set({
            'token': token,
            'platform': 'flutter', // Simple platform identifier
            'createdAt': FieldValue.serverTimestamp(),
            'lastUsed': FieldValue.serverTimestamp(),
          });

      Logger.i('FCM token saved to Firestore');
    } catch (e) {
      Logger.e('Error saving FCM token: $e');
    }
  }

  /// Subscribe to topic for messaging
  Future<void> subscribeToTopic(String topic) async {
    if (_firebaseMessaging == null) return;

    try {
      await _firebaseMessaging!.subscribeToTopic(topic);
      Logger.i('Subscribed to topic: $topic');
    } catch (e) {
      Logger.e('Error subscribing to topic $topic: $e');
    }
  }

  /// Unsubscribe from topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (_firebaseMessaging == null) return;

    try {
      await _firebaseMessaging!.unsubscribeFromTopic(topic);
      Logger.i('Unsubscribed from topic: $topic');
    } catch (e) {
      Logger.e('Error unsubscribing from topic $topic: $e');
    }
  }

  /// Ensure topic subscriptions for chat
  Future<void> ensureTopicSubscriptions(String userId) async {
    await subscribeToTopic('chat');
    await subscribeToTopic('user_$userId');
  }

  /// Clean up tokens for the current user
  Future<void> cleanupTokens() async {
    if (_auth?.currentUser == null) return;

    try {
      String userId = _auth!.currentUser!.uid;
      String? currentToken = await getToken();

      if (currentToken == null) return;

      // Get all tokens for this user
      QuerySnapshot snapshot =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection('tokens')
              .get();

      // Remove old tokens, keep only the current one
      for (QueryDocumentSnapshot doc in snapshot.docs) {
        if (doc.id != currentToken) {
          await doc.reference.delete();
        }
      }

      Logger.i('Token cleanup completed');
    } catch (e) {
      Logger.e('Error during token cleanup: $e');
    }
  }
}

/// Global function to handle background messages
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  Logger.i('Background message received: ${message.data}');
}

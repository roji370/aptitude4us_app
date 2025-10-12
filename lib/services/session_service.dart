import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/logger.dart';

/// Service to manage single-device sessions for Firebase Authentication
/// Ensures only one active session per user across all devices
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  StreamSubscription<DocumentSnapshot>? _sessionListener;
  String? _currentSessionId;
  String? _deviceId;
  bool _isInitialized = false;

  /// Initialize the session service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      Logger.i('SessionService: Initializing single-device session management');
      
      // Generate or retrieve device ID
      await _initializeDeviceId();
      
      // Load current session ID from local storage
      await _loadCurrentSessionId();
      
      _isInitialized = true;
      Logger.i('SessionService: Initialization completed');
    } catch (e) {
      Logger.e('SessionService: Error during initialization: $e');
      rethrow;
    }
  }

  /// Generate a unique device identifier
  Future<void> _initializeDeviceId() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        _deviceId = '${androidInfo.model}_${androidInfo.id}_${androidInfo.fingerprint}';
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        _deviceId = '${iosInfo.model}_${iosInfo.identifierForVendor}';
      } else {
        // Fallback for other platforms
        _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
      
      Logger.d('SessionService: Device ID generated: ${_deviceId?.substring(0, 10)}...');
    } catch (e) {
      Logger.e('SessionService: Error generating device ID: $e');
      // Fallback to timestamp-based ID
      _deviceId = 'fallback_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Load current session ID from local storage
  Future<void> _loadCurrentSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentSessionId = prefs.getString('session_id');
      Logger.d('SessionService: Loaded session ID: ${_currentSessionId?.substring(0, 10)}...');
    } catch (e) {
      Logger.e('SessionService: Error loading session ID: $e');
    }
  }

  /// Save session ID to local storage
  Future<void> _saveCurrentSessionId(String sessionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_id', sessionId);
      _currentSessionId = sessionId;
      Logger.d('SessionService: Saved session ID: ${sessionId.substring(0, 10)}...');
    } catch (e) {
      Logger.e('SessionService: Error saving session ID: $e');
    }
  }

  /// Generate a new unique session ID
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return '${_deviceId}_${timestamp}_$random';
  }

  /// Create a new session for the current user
  Future<void> createSession(String userId) async {
    if (!_isInitialized) await initialize();
    
    try {
      Logger.i('SessionService: Creating new session for user: $userId');
      
      // Generate new session ID
      final sessionId = _generateSessionId();
      
      // Create session data
      final sessionData = {
        'sessionId': sessionId,
        'userId': userId,
        'deviceId': _deviceId,
        'deviceInfo': await _getDeviceInfo(),
        'createdAt': FieldValue.serverTimestamp(),
        'lastActive': FieldValue.serverTimestamp(),
        'platform': Platform.isIOS ? 'ios' : 'android',
      };
      
      // Store session in Firestore (this will overwrite any existing session)
      await _firestore
          .collection('sessions')
          .doc(userId)
          .set(sessionData);
      
      // Save session ID locally
      await _saveCurrentSessionId(sessionId);
      
      Logger.i('SessionService: Session created successfully');
    } catch (e) {
      Logger.e('SessionService: Error creating session: $e');
      rethrow;
    }
  }

  /// Start listening for session changes
  Future<void> startSessionListener(String userId) async {
    if (!_isInitialized) await initialize();
    
    try {
      Logger.i('SessionService: Starting session listener for user: $userId');
      
      // Cancel any existing listener
      await stopSessionListener();
      
      // Start listening to session document
      _sessionListener = _firestore
          .collection('sessions')
          .doc(userId)
          .snapshots()
          .listen(
            (snapshot) => _handleSessionChange(snapshot, userId),
            onError: (error) {
              Logger.e('SessionService: Session listener error: $error');
            },
          );
      
      Logger.d('SessionService: Session listener started');
    } catch (e) {
      Logger.e('SessionService: Error starting session listener: $e');
    }
  }

  /// Handle session document changes
  void _handleSessionChange(DocumentSnapshot snapshot, String userId) {
    try {
      if (!snapshot.exists) {
        Logger.w('SessionService: Session document does not exist for user: $userId');
        _handleSessionInvalid('Session document not found');
        return;
      }
      
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) {
        Logger.w('SessionService: Session document has no data');
        _handleSessionInvalid('Session document is empty');
        return;
      }
      
      final remoteSessionId = data['sessionId'] as String?;
      final remoteUserId = data['userId'] as String?;
      
      Logger.d('SessionService: Session change detected');
      Logger.d('SessionService: Remote session ID: ${remoteSessionId?.substring(0, 10)}...');
      Logger.d('SessionService: Local session ID: ${_currentSessionId?.substring(0, 10)}...');
      
      // Validate session
      if (remoteUserId != userId) {
        Logger.w('SessionService: User ID mismatch in session document');
        _handleSessionInvalid('User ID mismatch');
        return;
      }
      
      if (remoteSessionId == null || remoteSessionId.isEmpty) {
        Logger.w('SessionService: Invalid session ID in remote document');
        _handleSessionInvalid('Invalid remote session ID');
        return;
      }
      
      // Check if local session matches remote session
      if (_currentSessionId != remoteSessionId) {
        Logger.w('SessionService: Session ID mismatch - user logged in from another device');
        _handleSessionInvalid('Session invalidated by new login');
        return;
      }
      
      // Update last active timestamp
      _updateLastActive(userId);
      
      Logger.d('SessionService: Session validated successfully');
    } catch (e) {
      Logger.e('SessionService: Error handling session change: $e');
    }
  }

  /// Handle invalid session - sign out user
  void _handleSessionInvalid(String reason) {
    Logger.w('SessionService: Session invalid - $reason');
    
    // Sign out user immediately
    _signOutUser();
  }

  /// Sign out the current user
  Future<void> _signOutUser() async {
    try {
      Logger.i('SessionService: Signing out user due to invalid session');
      
      // Stop session listener
      await stopSessionListener();
      
      // Clear local session data
      await _clearLocalSessionData();
      
      // Sign out from Firebase Auth
      await _auth.signOut();
      
      Logger.i('SessionService: User signed out successfully');
    } catch (e) {
      Logger.e('SessionService: Error during sign out: $e');
    }
  }

  /// Update last active timestamp for the session
  Future<void> _updateLastActive(String userId) async {
    try {
      await _firestore
          .collection('sessions')
          .doc(userId)
          .update({'lastActive': FieldValue.serverTimestamp()});
    } catch (e) {
      Logger.e('SessionService: Error updating last active: $e');
    }
  }

  /// Clear local session data
  Future<void> _clearLocalSessionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_id');
      _currentSessionId = null;
      Logger.d('SessionService: Local session data cleared');
    } catch (e) {
      Logger.e('SessionService: Error clearing local session data: $e');
    }
  }

  /// Stop session listener
  Future<void> stopSessionListener() async {
    try {
      await _sessionListener?.cancel();
      _sessionListener = null;
      Logger.d('SessionService: Session listener stopped');
    } catch (e) {
      Logger.e('SessionService: Error stopping session listener: $e');
    }
  }

  /// Clean up session on sign out
  Future<void> cleanupSession(String userId) async {
    try {
      Logger.i('SessionService: Cleaning up session for user: $userId');
      
      // Stop listener
      await stopSessionListener();
      
      // Clear local data
      await _clearLocalSessionData();
      
      // Optionally remove session document from Firestore
      // (keeping it for audit purposes, but you can uncomment to remove)
      /*
      await _firestore
          .collection('sessions')
          .doc(userId)
          .delete();
      */
      
      Logger.i('SessionService: Session cleanup completed');
    } catch (e) {
      Logger.e('SessionService: Error during session cleanup: $e');
    }
  }

  /// Get device information for session tracking
  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        return {
          'platform': 'android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'version': androidInfo.version.release,
          'brand': androidInfo.brand,
        };
      } else if (Platform.isIOS) {
        final IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
        return {
          'platform': 'ios',
          'model': iosInfo.model,
          'name': iosInfo.name,
          'systemVersion': iosInfo.systemVersion,
          'utsname': iosInfo.utsname.machine,
        };
      } else {
        return {
          'platform': 'unknown',
          'info': 'Platform not supported',
        };
      }
    } catch (e) {
      Logger.e('SessionService: Error getting device info: $e');
      return {
        'platform': Platform.isIOS ? 'ios' : 'android',
        'error': 'Failed to get device info',
      };
    }
  }

  /// Get current session ID
  String? get currentSessionId => _currentSessionId;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Dispose the service
  Future<void> dispose() async {
    await stopSessionListener();
    _isInitialized = false;
    Logger.d('SessionService: Service disposed');
  }
}

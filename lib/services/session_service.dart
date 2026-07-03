import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/device_id.dart';
import '../utils/logger.dart';

/// Service to manage single-device sessions for Firebase Authentication
/// Ensures only one active session per user across all devices
class SessionService {
  static final SessionService _instance = SessionService._internal();
  factory SessionService() => _instance;
  SessionService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Secure storage for session ID — survives reinstall on iOS (Keychain),
  /// survives clear-data on Android (EncryptedSharedPreferences).
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock,
    ),
  );

  static const String _sessionIdKey = 'session_id_secure';
  /// Legacy key for one-time migration from SharedPreferences.
  static const String _legacySessionIdKey = 'session_id';
  
  StreamSubscription<DocumentSnapshot>? _sessionListener;
  String? _currentSessionId;
  bool _isInitialized = false;

  /// Debounce guard: ignore session-change events within this window of
  /// the last processed event to absorb Firestore snapshot bursts after
  /// network reconnection.
  DateTime? _lastSessionChangeProcessed;
  static const Duration _sessionChangeDebounce = Duration(seconds: 2);

  /// Initialize the session service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      Logger.i('SessionService: Initializing single-device session management');
      
      // Load current session ID from secure storage (with migration)
      await _loadCurrentSessionId();
      
      _isInitialized = true;
      Logger.i('SessionService: Initialization completed');
    } catch (e) {
      Logger.e('SessionService: Error during initialization: $e');
      rethrow;
    }
  }

  /// Load session ID from secure storage, with one-time migration from
  /// legacy SharedPreferences.
  Future<void> _loadCurrentSessionId() async {
    // Try secure storage first
    try {
      final secureId = await _secureStorage.read(key: _sessionIdKey);
      if (secureId != null && secureId.isNotEmpty) {
        _currentSessionId = secureId;
        Logger.d('SessionService: Loaded session ID from secure storage');
        return;
      }
    } catch (e) {
      Logger.w('SessionService: Secure storage read failed: $e');
    }

    // Migrate from legacy SharedPreferences
    try {
      final prefs = await _getLegacyPrefs();
      if (prefs != null) {
        final legacyId = prefs.getString(_legacySessionIdKey);
        if (legacyId != null && legacyId.isNotEmpty) {
          Logger.i('SessionService: Migrating session ID to secure storage');
          _currentSessionId = legacyId;
          
          try {
            await _secureStorage.write(key: _sessionIdKey, value: legacyId);
            await prefs.remove(_legacySessionIdKey);
            Logger.i('SessionService: Session ID migration successful');
          } catch (e) {
            Logger.w('SessionService: Migration write failed (non-fatal): $e');
          }
          return;
        }
      }
    } catch (e) {
      Logger.w('SessionService: Legacy session read failed: $e');
    }

    Logger.d('SessionService: No existing session ID found');
  }

  /// Helper to get SharedPreferences (only used for migration).
  Future<dynamic> _getLegacyPrefs() async {
    try {
      final module = await _importSharedPrefs();
      return module;
    } catch (_) {
      return null;
    }
  }

  Future<dynamic> _importSharedPrefs() async {
    // Direct import since it's still a dependency
    final prefs = await (await _sharedPrefsInstance());
    return prefs;
  }

  /// Save session ID to secure storage
  Future<void> _saveCurrentSessionId(String sessionId) async {
    _currentSessionId = sessionId;
    
    try {
      await _secureStorage.write(key: _sessionIdKey, value: sessionId);
      Logger.d('SessionService: Saved session ID to secure storage');
    } catch (e) {
      Logger.e('SessionService: Error saving session ID: $e');
    }
  }

  /// Generate a new unique session ID using the unified device ID.
  Future<String> _generateSessionId() async {
    final deviceId = await getDeviceId();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecond;
    return '${deviceId}_${timestamp}_$random';
  }

  /// Create a new session for the current user
  Future<void> createSession(String userId) async {
    if (!_isInitialized) await initialize();
    
    try {
      Logger.i('SessionService: Creating new session for user: $userId');
      
      // Generate new session ID using unified device ID
      final sessionId = await _generateSessionId();
      final deviceId = await getDeviceId();
      
      // Create session data
      final sessionData = {
        'sessionId': sessionId,
        'userId': userId,
        'deviceId': deviceId,
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

  /// Handle session document changes with debounce and tolerance.
  void _handleSessionChange(DocumentSnapshot snapshot, String userId) async {
    // Guard: don't process events before initialization
    if (!_isInitialized) {
      Logger.d('SessionService: Ignoring session change before initialization');
      return;
    }

    // Debounce: ignore events within 2s of the last processed event
    // to absorb Firestore snapshot bursts after network reconnection.
    final now = DateTime.now();
    if (_lastSessionChangeProcessed != null &&
        now.difference(_lastSessionChangeProcessed!) < _sessionChangeDebounce) {
      Logger.d('SessionService: Debouncing session change event');
      return;
    }

    try {
      if (!snapshot.exists) {
        Logger.w('SessionService: Session document does not exist for user: $userId');
        // Don't force sign-out for missing document — could be a Firestore cache issue
        return;
      }
      
      final data = snapshot.data() as Map<String, dynamic>?;
      if (data == null) {
        Logger.w('SessionService: Session document has no data');
        return;
      }
      
      final remoteSessionId = data['sessionId'] as String?;
      final remoteUserId = data['userId'] as String?;
      
      Logger.d('SessionService: Session change detected');
      
      // Validate user ID
      if (remoteUserId != userId) {
        Logger.w('SessionService: User ID mismatch in session document');
        _lastSessionChangeProcessed = now;
        _handleSessionInvalid('User ID mismatch');
        return;
      }
      
      if (remoteSessionId == null || remoteSessionId.isEmpty) {
        Logger.w('SessionService: Invalid session ID in remote document');
        return;
      }
      
      // ── Tolerance: re-read session ID from secure storage before comparing ──
      // This handles the case where _currentSessionId is null because the
      // in-memory value was lost (shouldn't happen with secure storage, but
      // defense in depth).
      if (_currentSessionId == null) {
        Logger.w('SessionService: Local session ID is null, re-reading from storage');
        try {
          final reReadId = await _secureStorage.read(key: _sessionIdKey);
          if (reReadId != null && reReadId.isNotEmpty) {
            _currentSessionId = reReadId;
            Logger.i('SessionService: Recovered session ID from secure storage');
          } else {
            // Still null — don't sign out, this is a storage issue not a multi-device issue
            Logger.w('SessionService: No session ID in storage — skipping validation');
            return;
          }
        } catch (e) {
          Logger.e('SessionService: Failed to re-read session ID: $e');
          // Don't sign out on storage errors
          return;
        }
      }
      
      // Check if local session matches remote session
      if (_currentSessionId != remoteSessionId) {
        Logger.w('SessionService: Session ID mismatch - user logged in from another device');
        _lastSessionChangeProcessed = now;
        _handleSessionInvalid('Session invalidated by new login');
        return;
      }
      
      // Update last active timestamp
      _updateLastActive(userId);
      _lastSessionChangeProcessed = now;
      
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

  /// Clear local session data from both secure and legacy storage
  Future<void> _clearLocalSessionData() async {
    _currentSessionId = null;
    
    try {
      await _secureStorage.delete(key: _sessionIdKey);
    } catch (e) {
      Logger.w('SessionService: Error clearing session from secure storage: $e');
    }
    
    // Also clear legacy storage if it exists
    try {
      final prefs = await _sharedPrefsInstance();
      await prefs.remove(_legacySessionIdKey);
    } catch (_) {}
    
    Logger.d('SessionService: Local session data cleared');
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
      final deviceInfoPlugin = await _getDeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        return {
          'platform': 'android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'version': androidInfo.version.release,
          'brand': androidInfo.brand,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
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

  // Helpers for legacy SharedPreferences migration and device info
  Future<SharedPreferences> _sharedPrefsInstance() async {
    return await SharedPreferences.getInstance();
  }

  Future<DeviceInfoPlugin> _getDeviceInfoPlugin() async {
    return DeviceInfoPlugin();
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

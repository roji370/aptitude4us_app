import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default Firebase configuration options for different platforms
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // Web configuration
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAOvAz4i5DBIvqY4kNGVXOE3iqgq1mbapU',
    appId: '1:963626043371:web:deedca113df0f92f21fbae',
    messagingSenderId: '963626043371',
    projectId: 'apt4us-afb04',
    authDomain: 'apt4us-afb04.firebaseapp.com',
    storageBucket: 'apt4us-afb04.firebasestorage.app',
  );

  // Android configuration
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAGgSfuDEbaIpYerS2D3o3K7UKNZZrwb4g',
    appId: '1:963626043371:android:8c6b2d5cf23b802221fbae',
    messagingSenderId: '963626043371',
    projectId: 'apt4us-afb04',
    storageBucket: 'apt4us-afb04.firebasestorage.app',
  );

  // iOS configuration
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBCQj1-naA5C31B9LueBAy4f9FQpMKCjhI',
    appId: '1:963626043371:ios:645e7c5b6ceee18321fbae',
    messagingSenderId: '963626043371',
    projectId: 'apt4us-afb04',
    storageBucket: 'apt4us-afb04.firebasestorage.app',
    iosBundleId: 'com.aptitude4us.academy',
  );

  // macOS configuration (uses same as iOS)
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBCQj1-naA5C31B9LueBAy4f9FQpMKCjhI',
    appId: '1:963626043371:ios:645e7c5b6ceee18321fbae',
    messagingSenderId: '963626043371',
    projectId: 'apt4us-afb04',
    storageBucket: 'apt4us-afb04.firebasestorage.app',
    iosBundleId: 'com.aptitude4us.academy',
  );

  // Windows configuration (uses web config as fallback)
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAOvAz4i5DBIvqY4kNGVXOE3iqgq1mbapU',
    appId: '1:963626043371:web:deedca113df0f92f21fbae',
    messagingSenderId: '963626043371',
    projectId: 'apt4us-afb04',
    storageBucket: 'apt4us-afb04.firebasestorage.app',
  );

  // Linux configuration (uses web config as fallback)
  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'AIzaSyAOvAz4i5DBIvqY4kNGVXOE3iqgq1mbapU',
    appId: '1:963626043371:web:deedca113df0f92f21fbae',
    messagingSenderId: '963626043371',
    projectId: 'apt4us-afb04',
    storageBucket: 'apt4us-afb04.firebasestorage.app',
  );
}

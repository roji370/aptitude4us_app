import Flutter
import UIKit
import Firebase
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure Firebase as early as possible
    FirebaseApp.configure()

    // Call super first to initialize Flutter engine
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Set up Firebase Messaging delegate for token handling
    Messaging.messaging().delegate = self

    return result
  }



  // Firebase Messaging delegate method: receives registration token
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let token = fcmToken {
      print("FCM registration token: \(token)")
    }
  }

  // Forward APNs device token to Firebase when needed (kept for compatibility)
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    super.application(
      application,
      didRegisterForRemoteNotificationsWithDeviceToken: deviceToken
    )
  }
}
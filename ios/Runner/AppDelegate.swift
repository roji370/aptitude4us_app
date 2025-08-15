import Flutter
import UIKit
import UserNotifications
import Firebase
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, MessagingDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // CRITICAL: Initialize Firebase first
    FirebaseApp.configure()
    
    // Setup notification delegates for foreground notification presentation  
    if #available(iOS 10.0, *) {
      // For iOS 10 and above, we need to set the UNUserNotificationCenter delegate
      UNUserNotificationCenter.current().delegate = self
      
      // Also set the Firebase Messaging delegate
      Messaging.messaging().delegate = self
    }
    
    // Call super FIRST to ensure proper Flutter engine initialization
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    
    // Register plugins AFTER Flutter engine is ready to avoid nil registrar
    GeneratedPluginRegistrant.register(with: self)
    
    return result
  }
  
  // Handle foreground notifications - This will show notifications even when app is in foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    let userInfo = notification.request.content.userInfo
    
    // Check if it's a chat notification
    if let type = userInfo["type"] as? String, type == "chat" {
      // For chat notifications, always show alert, badge, and sound
      if #available(iOS 14.0, *) {
        completionHandler([[.banner, .badge, .sound]])
      } else {
        completionHandler([[.alert, .badge, .sound]])
      }
    } else {
      // For other notifications, let Firebase handle it with default behavior
      super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler)
    }
  }
  
  // Handle notification tap when app is in background or closed
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    
    // If it's a Firebase message, let Firebase handle it
    if userInfo[AnyHashable("gcm.message_id")] != nil {
      Messaging.messaging().appDidReceiveMessage(userInfo)
    }
    
    // Now we can do our custom handling if needed
    if let type = userInfo["type"] as? String {
      // Log the notification type for debugging
      print("Notification type tapped: \(type)")
    }
    
    // Call super to let Flutter/Firebase handle the rest
    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
  
  // Firebase Messaging Delegate
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    if let token = fcmToken {
      // Firebase registration token received
      print("FCM registration token: \(token)")
    }
  }
}

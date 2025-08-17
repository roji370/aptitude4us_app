import Flutter
import UIKit
import UserNotifications
import Firebase
import FirebaseMessaging

// Manages screen capture/recording protection on iOS
final class ScreenProtectionManager {
  static let shared = ScreenProtectionManager()

  private var captureObserver: NSObjectProtocol?
  private var screenshotObserver: NSObjectProtocol?
  private var shieldView: UIView?
  private var isEnabled: Bool = false

  private init() {}

  func enable(on window: UIWindow?) {
    guard !isEnabled, let window = window else { return }
    isEnabled = true

    // Observe screen capture (recording / mirroring)
    captureObserver = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.updateShield(on: window)
    }

    // Optional: react to screenshots by briefly overlaying
    screenshotObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.showTemporaryShield(on: window)
    }

    // Initial application
    updateShield(on: window)
  }

  func disable() {
    guard isEnabled else { return }
    isEnabled = false

    if let captureObserver = captureObserver {
      NotificationCenter.default.removeObserver(captureObserver)
      self.captureObserver = nil
    }
    if let screenshotObserver = screenshotObserver {
      NotificationCenter.default.removeObserver(screenshotObserver)
      self.screenshotObserver = nil
    }
    removeShield()
  }

  private func updateShield(on window: UIWindow) {
    if UIScreen.main.isCaptured {
      addShield(to: window)
    } else {
      removeShield()
    }
  }

  private func addShield(to window: UIWindow) {
    guard shieldView == nil else { return }
    let view = UIView(frame: window.bounds)
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.backgroundColor = .black
    view.isUserInteractionEnabled = false
    window.addSubview(view)
    window.bringSubviewToFront(view)
    shieldView = view
  }

  private func removeShield() {
    shieldView?.removeFromSuperview()
    shieldView = nil
  }

  private func showTemporaryShield(on window: UIWindow) {
    // Briefly overlay to discourage screenshots; auto-remove
    addShield(to: window)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      // Only remove if not currently captured
      if !UIScreen.main.isCaptured {
        self?.removeShield()
      }
    }
  }
}

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

    // Setup method channel for screen protection
    if let flutterViewController = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "flutter.native/screenProtection",
        binaryMessenger: flutterViewController.binaryMessenger
      )

      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else { result(FlutterError(code: "UNAVAILABLE", message: "AppDelegate deallocated", details: nil)); return }
        switch call.method {
        case "preventScreenshots":
          if let enable = call.arguments as? Bool {
            if enable {
              ScreenProtectionManager.shared.enable(on: self.window)
            } else {
              ScreenProtectionManager.shared.disable()
            }
            result(true)
          } else {
            result(FlutterError(code: "BAD_ARGS", message: "Expected Bool for preventScreenshots", details: nil))
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    
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

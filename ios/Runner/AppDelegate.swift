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
  private var secureTextField: UITextField?
  private weak var originalSuperlayer: CALayer?
  private var isEnabled: Bool = false
  
  // For direct view protection (PDF containers)
  private var secureOverlayField: UITextField?
  private var isSecureViewEnabled: Bool = false

  private init() {}

  func enable(on window: UIWindow?) {
    guard !isEnabled, let window = window else { return }
    isEnabled = true

    // Apply secure text field hierarchy so that screenshots/recordings are blanked
    applySecureMask(on: window)

    // Observe screen capture (recording / mirroring)
    captureObserver = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // No UI change required; secure mask covers capture as well
      // Keep hook in case we want to react (e.g., show a banner)
    }

    // Optional: react to screenshots by briefly overlaying
    screenshotObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // With secure mask active, screenshots are already blanked
      // Optionally, we could notify Flutter here in the future
    }
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
    removeSecureMask()
  }

  // Place the app window's layer under a secure text field layer so captures are blank
  private func applySecureMask(on window: UIWindow) {
    guard secureTextField == nil else { return }
    let field = UITextField(frame: window.bounds)
    field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    field.isSecureTextEntry = true
    field.backgroundColor = .clear
    field.isUserInteractionEnabled = false
    window.addSubview(field)

    let windowLayer = window.layer
    originalSuperlayer = windowLayer.superlayer

    // Embed the window's layer inside the secure field layer
    originalSuperlayer?.addSublayer(field.layer)
    field.layer.addSublayer(windowLayer)

    secureTextField = field
  }

  private func removeSecureMask() {
    guard let field = secureTextField else { return }
    if let originalSuperlayer = originalSuperlayer {
      // Move the window's layer back to its original superlayer
      if let windowLayer = field.layer.sublayers?.first(where: { $0 is CALayer && $0 !== field.layer }) {
        originalSuperlayer.addSublayer(windowLayer)
      }
    }
    field.removeFromSuperview()
    secureTextField = nil
    originalSuperlayer = nil
  }
  
  // Direct secure view overlay for PDF content
  func enableSecureView(on window: UIWindow?) {
    guard !isSecureViewEnabled, let window = window else { return }
    isSecureViewEnabled = true
    
    let field = UITextField(frame: window.bounds)
    field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    field.isSecureTextEntry = true
    field.backgroundColor = .clear
    field.isUserInteractionEnabled = false
    field.layer.zPosition = 1000 // High z-index to ensure it's on top
    
    window.addSubview(field)
    window.bringSubviewToFront(field)
    secureOverlayField = field
  }
  
  func disableSecureView() {
    guard isSecureViewEnabled else { return }
    isSecureViewEnabled = false
    secureOverlayField?.removeFromSuperview()
    secureOverlayField = nil
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
        case "secureView":
          if let enable = call.arguments as? Bool {
            if enable {
              ScreenProtectionManager.shared.enableSecureView(on: self.window)
            } else {
              ScreenProtectionManager.shared.disableSecureView()
            }
            result(true)
          } else {
            result(FlutterError(code: "BAD_ARGS", message: "Expected Bool for secureView", details: nil))
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

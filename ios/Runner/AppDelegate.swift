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
  private var screenshotMonitoringObserver: NSObjectProtocol?
  private var shieldView: UIView?
  private var screenshotSecureField: UITextField?
  private var persistentSecureField: UITextField?
  private var isEnabled: Bool = false
  private var isScreenshotMonitoringEnabled: Bool = false
  private var flutterChannel: FlutterMethodChannel?

  private init() {}

  func enable(on window: UIWindow?) {
    guard !isEnabled, let window = window else { return }
    isEnabled = true

    // Add a transparent secure field overlay so screenshots are blacked out while enabled
    addPersistentSecureOverlay(to: window)

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
      // Add a temporary secure text field overlay to mask subsequent rapid screenshots
      self?.showTemporarySecureMask(on: window)
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
    removePersistentSecureOverlay()
  }

  private func updateShield(on window: UIWindow) {
    if UIScreen.main.isCaptured {
      addShield(to: window)
    } else {
      removeShield()
    }
  }

  private func addPersistentSecureOverlay(to window: UIWindow) {
    guard persistentSecureField == nil else { return }
    let field = UITextField(frame: window.bounds)
    field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    field.isSecureTextEntry = true
    field.backgroundColor = .clear
    field.isUserInteractionEnabled = false
    window.addSubview(field)
    window.bringSubviewToFront(field)
    persistentSecureField = field
  }

  private func removePersistentSecureOverlay() {
    persistentSecureField?.removeFromSuperview()
    persistentSecureField = nil
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

  private func showTemporarySecureMask(on window: UIWindow) {
    // Note: Screenshot notification fires after capture; this protects subsequent rapid captures
    guard screenshotSecureField == nil else { return }
    let field = UITextField(frame: window.bounds)
    field.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    field.isSecureTextEntry = true
    field.backgroundColor = .clear
    field.isUserInteractionEnabled = false
    window.addSubview(field)
    window.bringSubviewToFront(field)
    screenshotSecureField = field

    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.screenshotSecureField?.removeFromSuperview()
      self?.screenshotSecureField = nil
    }
  }
  
  // MARK: - Screenshot Monitoring for Blocking
  
  func setFlutterChannel(_ channel: FlutterMethodChannel) {
    self.flutterChannel = channel
  }
  
  func enableScreenshotMonitoring() {
    guard !isScreenshotMonitoringEnabled else { return }
    isScreenshotMonitoringEnabled = true
    
    // Set up screenshot detection observer
    screenshotMonitoringObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.userDidTakeScreenshotNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.notifyFlutterOfScreenshot()
    }
    
    print("📱 Screenshot monitoring enabled")
  }
  
  func disableScreenshotMonitoring() {
    guard isScreenshotMonitoringEnabled else { return }
    isScreenshotMonitoringEnabled = false
    
    if let screenshotMonitoringObserver = screenshotMonitoringObserver {
      NotificationCenter.default.removeObserver(screenshotMonitoringObserver)
      self.screenshotMonitoringObserver = nil
    }
    
    print("📱 Screenshot monitoring disabled")
  }
  
  private func notifyFlutterOfScreenshot() {
    guard let channel = flutterChannel else {
      print("❌ No Flutter channel available to notify of screenshot")
      return
    }
    
    print("📱 Screenshot detected! Notifying Flutter...")
    channel.invokeMethod("onScreenshotDetected", arguments: nil) { result in
      if let error = result as? FlutterError {
        print("❌ Error notifying Flutter of screenshot: \(error.message ?? "Unknown error")")
      } else {
        print("✅ Successfully notified Flutter of screenshot")
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

      // Set the Flutter channel reference in ScreenProtectionManager
      ScreenProtectionManager.shared.setFlutterChannel(channel)
      
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
        case "enableScreenshotMonitoring":
          ScreenProtectionManager.shared.enableScreenshotMonitoring()
          result(true)
        case "disableScreenshotMonitoring":
          ScreenProtectionManager.shared.disableScreenshotMonitoring()
          result(true)
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

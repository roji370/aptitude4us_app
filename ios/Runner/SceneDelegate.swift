import Flutter
import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }

    // Create FlutterViewController using the shared engine from AppDelegate.
    // This ensures Firebase and all other plugins are available since they
    // were registered on this same engine in didFinishLaunchingWithOptions.
    let flutterViewController = FlutterViewController(
      engine: appDelegate.flutterEngine,
      nibName: nil,
      bundle: nil
    )

    window = UIWindow(windowScene: windowScene)
    window?.rootViewController = flutterViewController
    window?.makeKeyAndVisible()

    // Share the window with AppDelegate for screen protection and other native features
    appDelegate.window = window

    // Now that the window and FlutterViewController are ready,
    // set up the method channel for screen protection
    appDelegate.setupMethodChannel()
  }
}

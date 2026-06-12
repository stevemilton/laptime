import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let watchHandler = WatchSessionHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Use the engine bridge's messenger directly: at this point in the
    // scene lifecycle the FlutterViewController may not yet be installed
    // as the window's rootViewController, and a nil lookup here would
    // silently disable the entire watch bridge (WCSession never activates,
    // every Dart call on the channel throws MissingPluginException).
    watchHandler.setup(with: engineBridge.applicationBinaryMessenger)
  }
}

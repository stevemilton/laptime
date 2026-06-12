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

    // Obtain the binary messenger through a plugin registrar — the same
    // mechanism every Flutter plugin uses. At this point in the scene
    // lifecycle the FlutterViewController may not yet be installed as the
    // window's rootViewController, so looking it up there could be nil and
    // would silently disable the entire watch bridge (WCSession never
    // activates, every Dart call on the channel throws
    // MissingPluginException).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WatchSessionHandler") {
      watchHandler.setup(with: registrar.messenger())
    }
  }
}

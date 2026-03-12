import Foundation
import Flutter
import WatchConnectivity

/// iOS-side WatchConnectivity handler.
///
/// Receives session files from the Apple Watch and forwards them to Flutter
/// via a MethodChannel. Also pushes configuration (user ID, circuit start/finish
/// line) from Flutter to the Watch via applicationContext.
class WatchSessionHandler: NSObject {

    private var methodChannel: FlutterMethodChannel?
    private let channelName = "com.laptime.laptime/watch"

    /// Set up the handler with a Flutter binary messenger.
    func setup(with messenger: FlutterBinaryMessenger) {
        methodChannel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)

        // Handle calls FROM Flutter TO native (push config to Watch)
        methodChannel?.setMethodCallHandler { [weak self] call, result in
            self?.handleFlutterCall(call, result: result)
        }

        // Activate WCSession
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Push user/circuit configuration to the Watch.
    func pushConfigToWatch(userId: String, startFinishLine: [String: Double]?) {
        guard WCSession.default.activationState == .activated else { return }

        var context: [String: Any] = ["userId": userId]

        if let sf = startFinishLine {
            context["sfLat1"] = sf["lat1"]
            context["sfLng1"] = sf["lng1"]
            context["sfLat2"] = sf["lat2"]
            context["sfLng2"] = sf["lng2"]
        }

        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            print("[WatchHandler] Failed to push context: \(error)")
        }
    }

    /// Clear stale auth/circuit state on the Watch.
    func clearConfigOnWatch() {
        guard WCSession.default.activationState == .activated else { return }

        do {
            try WCSession.default.updateApplicationContext([
                "signedIn": false
            ])
        } catch {
            print("[WatchHandler] Failed to clear context: \(error)")
        }
    }

    // MARK: - Flutter Call Handler

    private func handleFlutterCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pushConfig":
            guard let args = call.arguments as? [String: Any],
                  let userId = args["userId"] as? String else {
                result(FlutterError(code: "INVALID_ARGS", message: "userId required", details: nil))
                return
            }

            var sfLine: [String: Double]?
            if let lat1 = args["sfLat1"] as? Double,
               let lng1 = args["sfLng1"] as? Double,
               let lat2 = args["sfLat2"] as? Double,
               let lng2 = args["sfLng2"] as? Double {
                sfLine = ["lat1": lat1, "lng1": lng1, "lat2": lat2, "lng2": lng2]
            }

            pushConfigToWatch(userId: userId, startFinishLine: sfLine)
            result(nil)

        case "isWatchPaired":
            result(WCSession.isSupported() && WCSession.default.isPaired)

        case "clearConfig":
            clearConfigOnWatch()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionHandler: WCSessionDelegate {

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[WatchHandler] Activation error: \(error)")
        } else {
            print("[WatchHandler] Activated, paired: \(session.isPaired), watch installed: \(session.isWatchAppInstalled)")
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Required for iOS
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for multiple watch switching
        WCSession.default.activate()
    }

    /// Receive session file from the Watch.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let metadata = file.metadata,
              metadata["type"] as? String == "session" else {
            print("[WatchHandler] Received unknown file, ignoring")
            return
        }

        // Copy file to a persistent location (the received file is temporary)
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let watchDir = docs.appendingPathComponent("watch_sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: watchDir, withIntermediateDirectories: true)

        let destURL = watchDir.appendingPathComponent(file.fileURL.lastPathComponent)
        do {
            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: file.fileURL, to: destURL)

            print("[WatchHandler] Received session file: \(destURL.lastPathComponent)")

            // Notify Flutter
            DispatchQueue.main.async { [weak self] in
                self?.methodChannel?.invokeMethod("sessionFileReceived", arguments: [
                    "filePath": destURL.path
                ])
            }
        } catch {
            print("[WatchHandler] Failed to save received file: \(error)")
        }
    }
}

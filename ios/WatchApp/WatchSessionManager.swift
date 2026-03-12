import Foundation
import WatchConnectivity

/// Manages WatchConnectivity for transferring session data to the iPhone.
///
/// After recording stops, the session JSON file is queued for transfer.
/// Transfers happen automatically when the iPhone is reachable, even in background.
/// Also receives applicationContext from iPhone (e.g., circuit config, start/finish line).
@MainActor
final class WatchSessionManager: NSObject, ObservableObject {

    @Published var isPhoneReachable = false
    @Published var pendingTransfers: Int = 0

    /// Circuit configuration received from iPhone.
    @Published var startFinishLine: (lat1: Double, lng1: Double, lat2: Double, lng2: Double)?

    /// User ID received from iPhone (needed for session creation).
    @Published var userId: String?

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        // Auto-set a test user ID so the app is usable in the simulator
        // (WCSession is not supported in watchOS Simulator)
        userId = "simulator-test-user"
        #endif
    }

    /// Activate the WCSession. Call on app launch.
    func activate() {
        guard WCSession.isSupported() else {
            print("[WatchSession] WCSession not supported on this device")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Transfer a recorded session file to the iPhone.
    func transferSession(fileURL: URL, sessionId: String) {
        guard WCSession.default.activationState == .activated else {
            print("[WatchSession] Cannot transfer — session not activated")
            return
        }

        let metadata: [String: Any] = [
            "type": "session",
            "sessionId": sessionId,
        ]

        WCSession.default.transferFile(fileURL, metadata: metadata)
        pendingTransfers += 1
        print("[WatchSession] Queued session \(sessionId) for transfer")
    }

    /// Check how many transfers are still pending.
    func updatePendingCount() {
        pendingTransfers = WCSession.default.outstandingFileTransfers.count
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
            if let error {
                print("[WatchSession] Activation error: \(error)")
            } else {
                print("[WatchSession] Activated, reachable: \(session.isReachable)")
            }

            // Check for any existing applicationContext
            processApplicationContext(session.applicationContext)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            isPhoneReachable = session.isReachable
        }
    }

    /// Receive configuration from iPhone (circuit, start/finish line, user ID).
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in
            processApplicationContext(applicationContext)
        }
    }

    /// File transfer completed.
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        Task { @MainActor in
            if let error {
                print("[WatchSession] Transfer failed: \(error)")
            } else {
                print("[WatchSession] Transfer complete")
                pendingTransfers = max(0, pendingTransfers - 1)

                // Clean up the local file
                let fileURL = fileTransfer.file.fileURL
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    // MARK: - Helpers

    @MainActor
    private func processApplicationContext(_ context: [String: Any]) {
        if let signedIn = context["signedIn"] as? Bool, signedIn == false {
            userId = nil
            startFinishLine = nil
            return
        }

        // User ID
        if let uid = context["userId"] as? String {
            userId = uid
        }

        // Start/finish line configuration
        if let sfLat1 = context["sfLat1"] as? Double,
           let sfLng1 = context["sfLng1"] as? Double,
           let sfLat2 = context["sfLat2"] as? Double,
           let sfLng2 = context["sfLng2"] as? Double {
            startFinishLine = (lat1: sfLat1, lng1: sfLng1, lat2: sfLat2, lng2: sfLng2)
        }
    }
}

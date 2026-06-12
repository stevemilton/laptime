import SwiftUI

@main
struct TestTrackWatchApp: App {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var sessionManager = WatchSessionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
                .environmentObject(sessionManager)
                .onAppear {
                    sessionManager.activate()
                }
        }
    }
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var recording: RecordingManager
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        if recording.isRecording {
            recordingView
        } else {
            idleView
        }
    }

    // MARK: - Idle State

    private var idleView: some View {
        VStack(spacing: 12) {
            Text("TestTrack")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            // START button
            Button(action: startRecording) {
                ZStack {
                    Circle()
                        .fill(canStart ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 100, height: 100)

                    VStack(spacing: 2) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 28, weight: .bold))
                        Text("START")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canStart)

            Spacer()

            // Status
            if session.userId == nil {
                Text("Open TestTrack on iPhone")
                    .font(.system(size: 11))
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.center)
            }

            if session.pendingTransfers > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 10))
                    Text("\(session.pendingTransfers) pending")
                        .font(.system(size: 10))
                }
                .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Recording State

    private var recordingView: some View {
        VStack(spacing: 8) {
            // Elapsed time
            Text(formatTime(recording.elapsedMs))
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .minimumScaleFactor(0.6)

            // Current lap time
            if recording.lapCount > 0 {
                Text("LAP \(recording.lapCount + 1)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)

                Text(formatTime(recording.currentLapMs))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundColor(.yellow)
            }

            // Last / Best lap
            HStack(spacing: 16) {
                if let last = recording.lastLapMs {
                    VStack(spacing: 2) {
                        Text("LAST")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(formatTime(last))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                }
                if let best = recording.bestLapMs {
                    VStack(spacing: 2) {
                        Text("BEST")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.green)
                        Text(formatTime(best))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(.green)
                    }
                }
            }

            Spacer()

            // STOP + Manual Lap buttons
            HStack(spacing: 12) {
                // Manual lap button
                Button(action: { recording.manualLapSplit() }) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.blue)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                // STOP button
                Button(action: stopRecording) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 64, height: 64)

                        VStack(spacing: 1) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 18))
                            Text("STOP")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private var canStart: Bool {
        session.userId != nil
    }

    private func startRecording() {
        guard let userId = session.userId else { return }

        // Apply start/finish line if configured
        if let sf = session.startFinishLine {
            recording.setStartFinishLine(lat1: sf.lat1, lng1: sf.lng1, lat2: sf.lat2, lng2: sf.lng2)
        }

        recording.startSession(userId: userId)
    }

    private func stopRecording() {
        guard let fileURL = recording.stopSession() else { return }
        session.transferSession(fileURL: fileURL, sessionId: fileURL.lastPathComponent)
    }

    // MARK: - Formatting

    private func formatTime(_ ms: Int) -> String {
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = (ms % 1000) / 100
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

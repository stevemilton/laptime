import Foundation
import CoreLocation
import CoreMotion
import HealthKit

/// Standalone recording engine for Apple Watch.
///
/// Manages GPS, motion sensors, HKWorkoutSession (for background execution),
/// and lap detection. All data is stored in memory during recording and
/// serialized to a JSON file on stop.
@MainActor
final class RecordingManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isRecording = false
    @Published var elapsedMs: Int = 0
    @Published var lapCount: Int = 0
    @Published var currentLapMs: Int = 0
    @Published var lastLapMs: Int?
    @Published var bestLapMs: Int?
    @Published var gpsAccuracy: Double?

    // MARK: - Private State

    private var sessionId: String?
    private var userId: String?
    private var sessionStart: Date?
    private var lapStart: Date?

    // GPS
    private let locationManager = CLLocationManager()
    private var allPoints: [WatchGpsPoint] = []
    private var currentLapPoints: [WatchGpsPoint] = []

    // Sensors
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private var sensorStart: Date?
    private var latestGyroX: Double = 0
    private var latestGyroY: Double = 0
    private var latestGyroZ: Double = 0
    private var latestMagHeading: Double = 0
    private var latestBaroPressure: Double = 0
    private var currentLapSensors = WatchSensorSnapshot.empty

    // Lap detection
    private let lapDetector = LapDetector()
    private var completedLaps: [WatchLap] = []

    // HealthKit workout (keeps app alive in background)
    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?

    // Timer
    private var elapsedTimer: Timer?

    #if targetEnvironment(simulator)
    // Simulated GPS for testing in the Watch Simulator
    private var simulatedGpsTimer: Timer?
    private var simPointIndex: Int = 0
    // Simple oval track (Silverstone-ish lat/lng, ~300m loop)
    private let simTrack: [(lat: Double, lng: Double)] = {
        let center = (lat: 52.0786, lng: -1.0169)
        let count = 40
        let latRadius = 0.0012  // ~130m N/S
        let lngRadius = 0.0018  // ~130m E/W
        return (0..<count).map { i in
            let angle = 2.0 * .pi * Double(i) / Double(count)
            return (
                lat: center.lat + latRadius * sin(angle),
                lng: center.lng + lngRadius * cos(angle)
            )
        }
    }()
    #endif

    // MARK: - Lifecycle

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Public API

    /// Start a new recording session.
    func startSession(userId: String) {
        guard !isRecording else { return }

        self.userId = userId
        sessionId = UUID().uuidString
        sessionStart = Date()
        lapStart = sessionStart
        sensorStart = sessionStart
        lapCount = 0
        lastLapMs = nil
        bestLapMs = nil
        allPoints = []
        currentLapPoints = []
        completedLaps = []
        currentLapSensors = .empty
        lapDetector.reset()

        isRecording = true

        startWorkoutSession()
        startGPS()
        startSensors()
        startElapsedTimer()
    }

    /// Configure start/finish line for automatic lap detection.
    func setStartFinishLine(lat1: Double, lng1: Double, lat2: Double, lng2: Double) {
        lapDetector.setStartFinishLine(lat1: lat1, lng1: lng1, lat2: lat2, lng2: lng2)
    }

    /// Manually trigger a lap split.
    func manualLapSplit() {
        guard isRecording else { return }
        completeLap(at: Date())
    }

    /// Stop recording and return the file URL of the serialized session.
    func stopSession() -> URL? {
        guard isRecording, let sessionId, let sessionStart, let userId else { return nil }

        // Complete final lap if we have points
        if !currentLapPoints.isEmpty {
            completeLap(at: Date())
        }

        let endedAt = Date()

        // Stop everything
        stopGPS()
        stopSensors()
        stopElapsedTimer()
        stopWorkoutSession()

        // Build session data
        let session = WatchSession(
            id: sessionId,
            userId: userId,
            startedAt: ISO8601DateFormatter().string(from: sessionStart),
            endedAt: ISO8601DateFormatter().string(from: endedAt),
            laps: completedLaps,
            fullTrace: allPoints,
            source: "watch"
        )

        // Serialize to file
        let fileURL = saveSessionToFile(session)

        // Reset state
        self.sessionId = nil
        self.userId = nil
        self.sessionStart = nil
        self.lapStart = nil
        isRecording = false
        elapsedMs = 0
        lapCount = 0
        currentLapMs = 0
        lastLapMs = nil
        bestLapMs = nil
        gpsAccuracy = nil

        return fileURL
    }

    // MARK: - HKWorkoutSession (background execution)

    private func startWorkoutSession() {
        #if targetEnvironment(simulator)
        print("[RecordingManager] Skipping HKWorkoutSession in simulator")
        return
        #else
        guard HKHealthStore.isHealthDataAvailable() else {
            print("[RecordingManager] HealthKit not available")
            return
        }

        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .outdoor

        do {
            workoutSession = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            workoutBuilder = workoutSession?.associatedWorkoutBuilder()
            workoutBuilder?.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
            workoutSession?.startActivity(with: Date())
            try workoutBuilder?.beginCollection(withStart: Date()) { success, error in
                if let error {
                    print("[RecordingManager] Workout builder error: \(error)")
                }
            }
        } catch {
            print("[RecordingManager] Failed to start workout session: \(error)")
        }
        #endif
    }

    private func stopWorkoutSession() {
        workoutSession?.end()
        workoutBuilder?.endCollection(withEnd: Date()) { [weak self] success, error in
            self?.workoutBuilder?.finishWorkout { workout, error in
                if let error {
                    print("[RecordingManager] Failed to finish workout: \(error)")
                }
            }
        }
        workoutSession = nil
        workoutBuilder = nil
    }

    // MARK: - GPS

    private func startGPS() {
        #if targetEnvironment(simulator)
        // Simulator: feed fake GPS points around a loop at ~1Hz
        simPointIndex = 0
        simulatedGpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.emitSimulatedGpsPoint()
            }
        }
        #else
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.activityType = .automotiveNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        #endif
    }

    private func stopGPS() {
        #if targetEnvironment(simulator)
        simulatedGpsTimer?.invalidate()
        simulatedGpsTimer = nil
        #else
        locationManager.stopUpdatingLocation()
        #endif
    }

    #if targetEnvironment(simulator)
    private func emitSimulatedGpsPoint() {
        let coord = simTrack[simPointIndex % simTrack.count]
        simPointIndex += 1
        let point = WatchGpsPoint(
            lat: coord.lat,
            lng: coord.lng,
            alt: 150.0,
            acc: 5.0,
            spd: 40.0,  // ~144 km/h
            hdg: Double((simPointIndex * 9) % 360),
            ts: Int64(Date().timeIntervalSince1970 * 1000)
        )
        onGpsPoint(point)
    }
    #endif

    // MARK: - Sensors

    private func startSensors() {
        // Accelerometer at ~50Hz (master timeline)
        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 50.0
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let data else { return }
                let ts = self.sensorElapsedSeconds()

                self.currentLapSensors.timestamps.append(ts)
                self.currentLapSensors.accelX.append(data.acceleration.x)
                self.currentLapSensors.accelY.append(data.acceleration.y)
                self.currentLapSensors.accelZ.append(data.acceleration.z)
                self.currentLapSensors.gyroX.append(self.latestGyroX)
                self.currentLapSensors.gyroY.append(self.latestGyroY)
                self.currentLapSensors.gyroZ.append(self.latestGyroZ)
                self.currentLapSensors.magHeading.append(self.latestMagHeading)
                self.currentLapSensors.baroPressure.append(self.latestBaroPressure)
            }
        }

        // Gyroscope at ~50Hz
        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / 50.0
            motionManager.startGyroUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                self?.latestGyroX = data.rotationRate.x
                self?.latestGyroY = data.rotationRate.y
                self?.latestGyroZ = data.rotationRate.z
            }
        }

        // Magnetometer at ~10Hz (heading)
        if motionManager.isMagnetometerAvailable {
            motionManager.magnetometerUpdateInterval = 1.0 / 10.0
            motionManager.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                let heading = (180.0 * (.pi - atan2(data.magneticField.y, data.magneticField.x)) / .pi)
                self?.latestMagHeading = heading < 0 ? heading + 360 : heading
            }
        }

        // Barometer (~1Hz event-based)
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
                guard let data else { return }
                // CMAltitudeData.pressure is in kPa, convert to hPa (mbar)
                self?.latestBaroPressure = data.pressure.doubleValue * 10.0
            }
        }
    }

    private func stopSensors() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
        motionManager.stopMagnetometerUpdates()
        altimeter.stopRelativeAltitudeUpdates()
    }

    private func sensorElapsedSeconds() -> Double {
        guard let sensorStart else { return 0 }
        return Date().timeIntervalSince(sensorStart)
    }

    // MARK: - Elapsed Timer

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsed()
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateElapsed() {
        guard let sessionStart else { return }
        elapsedMs = Int(Date().timeIntervalSince(sessionStart) * 1000)
        if let lapStart {
            currentLapMs = Int(Date().timeIntervalSince(lapStart) * 1000)
        }
    }

    // MARK: - Lap Detection

    private func onGpsPoint(_ point: WatchGpsPoint) {
        allPoints.append(point)
        currentLapPoints.append(point)

        gpsAccuracy = point.acc

        // Check for automatic crossing
        if let crossing = lapDetector.processPoint(
            lat: point.lat, lng: point.lng,
            accuracy: point.acc,
            timestamp: Date(timeIntervalSince1970: Double(point.ts) / 1000.0)
        ) {
            completeLap(at: crossing.crossingTime)
        }
    }

    private func completeLap(at crossingTime: Date) {
        guard let lapStart else { return }

        lapCount += 1
        let durationMs = Int(crossingTime.timeIntervalSince(lapStart) * 1000)

        if bestLapMs == nil || durationMs < bestLapMs! {
            bestLapMs = durationMs
        }
        lastLapMs = durationMs

        let lap = WatchLap(
            id: UUID().uuidString,
            lapNumber: lapCount,
            durationMs: durationMs,
            isPersonalBest: false,  // determined on import by iPhone
            trace: currentLapPoints,
            sensorData: currentLapSensors
        )
        completedLaps.append(lap)

        // Reset for next lap
        currentLapPoints = []
        currentLapSensors = .empty
        self.lapStart = crossingTime
    }

    // MARK: - File Storage

    private func saveSessionToFile(_ session: WatchSession) -> URL? {
        do {
            let data = try session.toJSONData()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let fileURL = docs.appendingPathComponent("session_\(session.id).json")
            try data.write(to: fileURL)
            print("[RecordingManager] Saved session to \(fileURL.lastPathComponent) (\(data.count) bytes)")
            return fileURL
        } catch {
            print("[RecordingManager] Failed to save session: \(error)")
            return nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension RecordingManager: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                let point = WatchGpsPoint(
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    alt: location.altitude,
                    acc: location.horizontalAccuracy,
                    spd: max(0, location.speed),
                    hdg: location.course >= 0 ? location.course : 0,
                    ts: Int64(location.timestamp.timeIntervalSince1970 * 1000)
                )
                onGpsPoint(point)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[RecordingManager] Location error: \(error)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            // Permission granted — GPS will start on next recording
        }
    }
}

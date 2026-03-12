import Foundation

// MARK: - GPS Point

struct WatchGpsPoint: Codable {
    let lat: Double
    let lng: Double
    let alt: Double
    let acc: Double
    let spd: Double  // m/s
    let hdg: Double  // degrees
    let ts: Int64    // milliseconds since epoch
}

// MARK: - Sensor Snapshot (per lap)

struct WatchSensorSnapshot: Codable {
    var timestamps: [Double]
    var accelX: [Double]
    var accelY: [Double]
    var accelZ: [Double]
    var gyroX: [Double]
    var gyroY: [Double]
    var gyroZ: [Double]
    var magHeading: [Double]
    var baroPressure: [Double]

    static var empty: WatchSensorSnapshot {
        WatchSensorSnapshot(
            timestamps: [], accelX: [], accelY: [], accelZ: [],
            gyroX: [], gyroY: [], gyroZ: [],
            magHeading: [], baroPressure: []
        )
    }
}

// MARK: - Lap

struct WatchLap: Codable {
    let id: String
    let lapNumber: Int
    let durationMs: Int
    let isPersonalBest: Bool
    let trace: [WatchGpsPoint]
    let sensorData: WatchSensorSnapshot
}

// MARK: - Session (top-level, transferred to iPhone)

struct WatchSession: Codable {
    let id: String
    let userId: String
    let startedAt: String  // ISO 8601
    let endedAt: String    // ISO 8601
    let laps: [WatchLap]
    let fullTrace: [WatchGpsPoint]
    let source: String     // "watch"

    /// Serialize to JSON Data for file transfer.
    func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    /// Deserialize from JSON Data.
    static func fromJSONData(_ data: Data) throws -> WatchSession {
        let decoder = JSONDecoder()
        return try decoder.decode(WatchSession.self, from: data)
    }
}

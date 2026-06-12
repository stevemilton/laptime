import Foundation

// MARK: - Line Crossing Result

struct LineCrossing {
    let crossingTime: Date
    let crossingLat: Double
    let crossingLng: Double
}

// MARK: - Lap Detector

/// Pure-geometry lap detection via start/finish line crossing.
///
/// Port of lib/core/services/lap_detection_service.dart.
/// The start/finish line is a short segment perpendicular to the track.
/// When two consecutive GPS points fall on opposite sides, a crossing is detected.
final class LapDetector {

    // Start/finish line endpoints
    private var sfLat1: Double?
    private var sfLng1: Double?
    private var sfLat2: Double?
    private var sfLng2: Double?

    // Previous GPS point
    private var previousLat: Double?
    private var previousLng: Double?
    private var previousTime: Date?

    // Debounce
    private var lastCrossingTime: Date?
    private let minCrossingInterval: TimeInterval = 10.0

    // Anti-bounce: must move away before re-crossing
    private var hasMovedAway = true

    // Constants (matching AppConstants in Dart)
    private let gpsMinAccuracyMeters: Double = 15.0
    private let startFinishToleranceMeters: Double = 15.0

    // MARK: - Public API

    /// Configure the start/finish line.
    func setStartFinishLine(lat1: Double, lng1: Double, lat2: Double, lng2: Double) {
        sfLat1 = lat1
        sfLng1 = lng1
        sfLat2 = lat2
        sfLng2 = lng2
        previousLat = nil
        previousLng = nil
        previousTime = nil
        lastCrossingTime = nil
        hasMovedAway = true
    }

    /// Whether a start/finish line is configured.
    var hasLine: Bool { sfLat1 != nil }

    /// Process a new GPS point. Returns a LineCrossing if the line was crossed.
    func processPoint(lat: Double, lng: Double, accuracy: Double, timestamp: Date) -> LineCrossing? {
        guard let sfLat1, let sfLng1, let sfLat2, let sfLng2 else { return nil }

        // Skip poor accuracy
        if accuracy > gpsMinAccuracyMeters {
            previousLat = lat
            previousLng = lng
            previousTime = timestamp
            return nil
        }

        guard let prevLat = previousLat, let prevLng = previousLng, let prevTime = previousTime else {
            previousLat = lat
            previousLng = lng
            previousTime = timestamp
            return nil
        }

        previousLat = lat
        previousLng = lng
        previousTime = timestamp

        // Anti-bounce: check distance to line
        let distToLine = GeoMath.distanceToLineSegment(
            pointLat: lat, pointLng: lng,
            lineLat1: sfLat1, lineLng1: sfLng1,
            lineLat2: sfLat2, lineLng2: sfLng2
        )

        if distToLine > startFinishToleranceMeters {
            hasMovedAway = true
        }

        if !hasMovedAway { return nil }

        // Check for line crossing
        guard let crossing = GeoMath.lineSegmentIntersection(
            p1Lat: prevLat, p1Lng: prevLng,
            p2Lat: lat, p2Lng: lng,
            p3Lat: sfLat1, p3Lng: sfLng1,
            p4Lat: sfLat2, p4Lng: sfLng2
        ) else {
            return nil
        }

        // Debounce
        if let last = lastCrossingTime, timestamp.timeIntervalSince(last) < minCrossingInterval {
            return nil
        }

        // Valid crossing
        lastCrossingTime = timestamp
        hasMovedAway = false

        // Interpolate crossing time
        let totalDist = GeoMath.distanceMeters(lat1: prevLat, lng1: prevLng, lat2: lat, lng2: lng)
        let crossDist = GeoMath.distanceMeters(lat1: prevLat, lng1: prevLng, lat2: crossing.lat, lng2: crossing.lng)
        let fraction = totalDist > 0 ? crossDist / totalDist : 0.5
        let timeDelta = timestamp.timeIntervalSince(prevTime)
        let crossingTime = prevTime.addingTimeInterval(timeDelta * fraction)

        return LineCrossing(
            crossingTime: crossingTime,
            crossingLat: crossing.lat,
            crossingLng: crossing.lng
        )
    }

    /// Reset for a new session.
    func reset() {
        previousLat = nil
        previousLng = nil
        previousTime = nil
        lastCrossingTime = nil
        hasMovedAway = true
    }
}

// MARK: - GeoMath (pure geometry utilities)

/// Port of lib/core/utils/geo_utils.dart.
enum GeoMath {

    /// Haversine distance between two coordinates in meters.
    static func distanceMeters(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let earthRadius: Double = 6_371_000
        let dLat = toRadians(lat2 - lat1)
        let dLng = toRadians(lng2 - lng1)
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(toRadians(lat1)) * cos(toRadians(lat2)) *
                sin(dLng / 2) * sin(dLng / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }

    /// Line segment intersection. Returns intersection point or nil.
    static func lineSegmentIntersection(
        p1Lat: Double, p1Lng: Double,
        p2Lat: Double, p2Lng: Double,
        p3Lat: Double, p3Lng: Double,
        p4Lat: Double, p4Lng: Double
    ) -> (lat: Double, lng: Double)? {
        let d1x = p2Lng - p1Lng
        let d1y = p2Lat - p1Lat
        let d2x = p4Lng - p3Lng
        let d2y = p4Lat - p3Lat

        let cross = d1x * d2y - d1y * d2x
        if abs(cross) < 1e-12 { return nil }  // parallel

        let t = ((p3Lng - p1Lng) * d2y - (p3Lat - p1Lat) * d2x) / cross
        let u = ((p3Lng - p1Lng) * d1y - (p3Lat - p1Lat) * d1x) / cross

        if t >= 0 && t <= 1 && u >= 0 && u <= 1 {
            return (lat: p1Lat + t * d1y, lng: p1Lng + t * d1x)
        }

        return nil
    }

    /// Distance from a point to a line segment in meters.
    static func distanceToLineSegment(
        pointLat: Double, pointLng: Double,
        lineLat1: Double, lineLng1: Double,
        lineLat2: Double, lineLng2: Double
    ) -> Double {
        let dx = lineLng2 - lineLng1
        let dy = lineLat2 - lineLat1
        let lenSq = dx * dx + dy * dy

        if lenSq == 0 {
            return distanceMeters(lat1: pointLat, lng1: pointLng, lat2: lineLat1, lng2: lineLng1)
        }

        var t = ((pointLng - lineLng1) * dx + (pointLat - lineLat1) * dy) / lenSq
        t = max(0, min(1, t))

        let projLat = lineLat1 + t * dy
        let projLng = lineLng1 + t * dx

        return distanceMeters(lat1: pointLat, lng1: pointLng, lat2: projLat, lng2: projLng)
    }

    private static func toRadians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}

import Foundation

/// What is around you today: the day's own stops still ahead, and the sights and snacks research
/// tied to the day or found within a short walk of it, ordered by how far they are from you.
public struct NearbyItem: Sendable, Identifiable {
    public var id: String { place.id }
    public let place: Place
    /// straight line from you
    public let km: Double
    /// on foot from you, at your pace
    public let minutes: Double
    /// a planned stop of the day (index), or a side trip
    public let planIndex: Int?
    public let along: Along?
}

public enum Nearby {
    public static func around(_ position: Coordinate, day: Day, store: TripStore, done: Set<Int> = [], pace: Double = 1, radiusKm: Double = 1.5, limit: Int = 12) -> [NearbyItem] {
        var seen = Set<String>()
        var out: [NearbyItem] = []
        for (i, stop) in day.stops where !done.contains(i) {
            guard let p = store.place(stop.place), p.kind != .station, seen.insert(p.id).inserted else { continue }
            let km = Geo.km(position, p.coordinate)
            out.append(NearbyItem(place: p, km: km, minutes: PlanEngine.directWalk(position, p.coordinate, pace: pace), planIndex: i, along: nil))
        }
        for a in day.along {
            guard let p = store.place(a.place), seen.insert(p.id).inserted else { continue }
            let km = Geo.km(position, p.coordinate)
            guard km <= radiusKm else { continue }
            out.append(NearbyItem(place: p, km: km, minutes: PlanEngine.directWalk(position, p.coordinate, pace: pace), planIndex: nil, along: a))
        }
        return Array(out.sorted { $0.km < $1.km }.prefix(limit))
    }

    /// How close a planned stop has to be to count as where you are (`plannedStop`).
    public static let plannedStopKm = 0.15

    /// The day's planned place you are standing at: the nearest of its stops within `plannedStopKm`
    /// of you, stations left out (the place a new expense starts on).
    public static func plannedStop(near position: Coordinate, day: Day, store: TripStore) -> String? {
        let near = day.stops.compactMap { store.place($0.stop.place) }
            .filter { $0.kind != .station }
            .map { ($0, Geo.km($0.coordinate, position)) }
            .min { $0.1 < $1.1 }
        return near.flatMap { $0.1 <= plannedStopKm ? $0.0.id : nil }
    }
}

/// Mount Fuji from where you stand: distance, bearing, and how high the summit sits above level.
public enum FujiSight {
    public static let summit = Coordinate(35.36064, 138.72743)
    public static let height = 3776.0
    /// standard atmospheric refraction coefficient, as in scripts/fuji-tools.mjs
    public static let refraction = 0.13

    public struct Sight: Sendable, Hashable {
        public let km: Double
        public let bearing: Double
        /// apparent elevation of the summit, degrees above the horizontal, after curvature and refraction
        public let elevation: Double
        public var compass: String { Geo.compass(bearing) }
    }

    public static func from(_ p: Coordinate, altitude: Double = 0) -> Sight {
        let d = Geo.km(p, summit)
        let dropM = d * d / (2 * Geo.earthRadiusKm) * (1 - refraction) * 1000
        let rise = height - max(0, altitude) - dropM
        let elevation = atan2(rise, d * 1000) * 180 / .pi
        return Sight(km: d, bearing: Geo.bearing(p, summit), elevation: elevation)
    }
}

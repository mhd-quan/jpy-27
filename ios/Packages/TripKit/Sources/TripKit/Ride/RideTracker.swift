import Foundation

/// Where you are on a ride, from a position: the next station, what to look at on which side,
/// whether to get ready to alight, and roughly when you arrive. Feeds the Live Activity.
public struct RideTracker: Sendable {
    public let ride: Ride
    public let track: [Coordinate]
    /// km of track per km the ride's stations count (the research measured the same rails)
    private let scale: Double

    public init(ride: Ride, store: TripStore) {
        self.ride = ride
        track = store.track(of: ride)
        let length = Geo.length(track)
        scale = length > 0 && ride.km > 0 ? ride.km / length : 1
    }

    public struct Status: Sendable, Hashable {
        /// km from where you boarded
        public let km: Double
        public let progress: Double
        /// how far the position lies from the track (a wrong train, or still on the platform)
        public let offTrackKm: Double
        /// last station passed, next station, and the next one the train stops at
        public let previous: Int?
        public let next: Int?
        public let nextStop: Int?
        /// stations still to go, counting only the ones the train stops at
        public let stopsLeft: Int
        /// what is visible now or within the next two km
        public let events: [Int]
        /// the side Fuji shows on now, when it does
        public let fujiSide: Ride.Side?
        public let alightSoon: Bool
        public let arrived: Bool
        /// a transfer coming up at the next stop
        public let transfer: Int?
    }

    public func status(at position: Coordinate) -> Status? {
        guard let proj = Geo.project(position, on: track) else { return nil }
        return status(km: proj.kmAlong * scale, off: proj.offKm)
    }

    public func status(km rawKm: Double, off: Double = 0) -> Status {
        let st = ride.stations
        let total = max(ride.km, st.last?.km ?? 0)
        let km = max(0, min(total, rawKm))
        let next = st.firstIndex { $0.km > km + 0.15 }
        let previous = st.lastIndex { $0.km <= km + 0.15 }
        let nextStop = st.indices.first { st[$0].stop && st[$0].km > km + 0.15 }
        let stopsLeft = st.filter { $0.stop && $0.km > km + 0.15 }.count
        let events = ride.events.indices.filter { i in
            let e = ride.events[i]
            guard st.indices.contains(e.from), st.indices.contains(e.to) else { return false }
            return st[e.from].km - 2 <= km && km <= st[e.to].km + 0.3
        }
        let fuji = events.map { ride.events[$0] }.first { $0.fuji && $0.side != .both }?.side
        let prevIdx = ride.alight?.idx ?? max(0, st.count - 2)
        let alightSoon = st.indices.contains(prevIdx) && km >= st[prevIdx].km - 0.3
        let arrived = km >= total - 0.3
        let transfer = nextStop.flatMap { i in ride.transfers.firstIndex { $0.idx == i } }
        return Status(km: km, progress: total > 0 ? km / total : 0, offTrackKm: off, previous: previous, next: next, nextStop: nextStop, stopsLeft: stopsLeft, events: events, fujiSide: fuji, alightSoon: alightSoon, arrived: arrived, transfer: transfer)
    }

    /// Planned arrival, minutes since midnight: departure plus the stated time.
    public var plannedArrival: Double? {
        guard let dep = TripTime.minutes(ride.at), let dur = TripTime.statedMinutes(ride.min) else { return nil }
        return Double(dep + dur)
    }

    /// Minutes to the end of the ride from km, at the speed the timetable implies, or at a measured speed.
    public func minutesLeft(km: Double, speedKmh: Double? = nil) -> Double? {
        let left = max(0, ride.km - km)
        if let v = speedKmh, v > 15 { return left / v * 60 }
        guard let dur = TripTime.statedMinutes(ride.min), ride.km > 0 else { return nil }
        return left / ride.km * Double(dur)
    }

    /// Minutes until the stop before yours, where the research says to get ready.
    public func minutesToAlightPrompt(km: Double, speedKmh: Double? = nil) -> Double? {
        guard let idx = ride.alight?.idx, ride.stations.indices.contains(idx) else { return minutesLeft(km: km, speedKmh: speedKmh).map { max(0, $0 - 3) } }
        let target = ride.stations[idx].km
        guard let total = minutesLeft(km: km, speedKmh: speedKmh), ride.km - km > 0 else { return nil }
        return max(0, total * (target - km) / (ride.km - km))
    }
}

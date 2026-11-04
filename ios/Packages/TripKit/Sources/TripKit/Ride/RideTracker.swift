import Foundation

/// Where you are on a ride, from a position: the next station, what to look at on which side,
/// whether to get ready to alight, and roughly when you arrive. Feeds the Live Activity.
///
/// A followed ride keeps one tracker and hands it each fix (`record`): its arrival then comes from
/// the train's pace over its last minutes, not from the speed of one fix. A fresh tracker knows only
/// the timetable.
public struct RideTracker: Sendable {
    public let ride: Ride
    public let track: [Coordinate]
    /// km of track per km the ride's stations count (the research measured the same rails)
    private let scale: Double
    /// where the train was and when, over the last `memory` seconds (`record`)
    private var samples: [Sample] = []
    /// an alarm for the ride has rung (`alarm`): only the timetable's is left to ring
    private var rang = false

    private struct Sample: Sendable {
        let km: Double
        let at: Date
    }

    /// km off the track past which a position says nothing about the ride (still on the platform,
    /// a wrong train, or not on it at all): the Live Activity ignores it, and a followed ride does
    /// not carry the day (`Itinerary.project`).
    public static let offTrack = 1.5

    /// Seconds of fixes kept (`record`); the pace counts once they span `paceSpan`.
    static let memory: TimeInterval = 300
    static let paceSpan: TimeInterval = 120
    /// km/h no train of the trip reaches (the Tōkaidō Shinkansen tops out at 285): a fix this far
    /// ahead of the last one is a jump of the GPS.
    static let fastest = 350.0
    /// km/h under which a speed says nothing about the rest of the ride (standing at a station,
    /// crawling into one): the timetable knows better.
    static let crawl = 15.0
    /// A measured arrival stays between `quickest` × the timetable's fast end and `slowest` × its
    /// slow end.
    static let quickest = 0.6
    static let slowest = 1.5

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
        let alightSoon = isDirect ? km >= tail : st.indices.contains(prevIdx) && km >= st[prevIdx].km - 0.3
        let arrived = km >= total - 0.3
        let transfer = nextStop.flatMap { i in ride.transfers.firstIndex { $0.idx == i } }
        return Status(km: km, progress: total > 0 ? km / total : 0, offTrackKm: off, previous: previous, next: next, nextStop: nextStop, stopsLeft: stopsLeft, events: events, fujiSide: fuji, alightSoon: alightSoon, arrived: arrived, transfer: transfer)
    }

    /// km of the ride, by its length or its last station, whichever is further
    private var total: Double { max(ride.km, ride.stations.last?.km ?? 0) }

    /// The station before yours, where the research says to get ready: the one it names, else the
    /// last but one.
    private var prevIdx: Int { ride.alight?.idx ?? max(0, ride.stations.count - 2) }

    /// The stop before yours is where you board (the Ashi cruise, the Toba ferry to Wagu): getting
    /// ready there would be from the moment you board, so the ride gets ready over its last stretch
    /// (`tail`) instead, for `Status.alightSoon` and the alarm alike.
    var isDirect: Bool { prevIdx == 0 && !ride.stations.isEmpty }

    /// Where a direct ride gets ready to alight, km from boarding: its last 15 %, at least its last
    /// 800 m, never more than its second half.
    var tail: Double { max(total / 2, total - max(0.8, 0.15 * total)) }

    /// A fix at `km`, taken at `time` (the fix's own time, not when it is handled). Kept for `memory`
    /// seconds after the latest. A fix not after the latest is a repeat, or one delivered late: left
    /// out. One ahead of the latest faster than `fastest` is a jump of the GPS: left out. One behind
    /// it is noise, or a train standing still (it never runs backward): it counts at the latest km, at
    /// its own time, so a stop is a stop.
    public mutating func record(km: Double, at time: Date) {
        if let last = samples.last {
            let seconds = time.timeIntervalSince(last.at)
            guard seconds > 0, (km - last.km) / seconds * 3600 <= Self.fastest else { return }
            samples.append(Sample(km: max(km, last.km), at: time))
        } else {
            samples.append(Sample(km: km, at: time))
        }
        let since = time.addingTimeInterval(-Self.memory)
        samples.removeAll { $0.at < since }
    }

    /// km/h along the track over the fixes kept, once they span `paceSpan`.
    private var pace: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let seconds = last.at.timeIntervalSince(first.at)
        guard seconds >= Self.paceSpan else { return nil }
        return (last.km - first.km) / seconds * 3600
    }

    /// Planned arrival, minutes since midnight: departure plus the stated time.
    public var plannedArrival: Double? {
        guard let dep = TripTime.minutes(ride.at), let dur = TripTime.statedMinutes(ride.min) else { return nil }
        return Double(dep + dur)
    }

    /// Minutes to the end of the ride from km: at the speed the timetable implies (its fast end,
    /// "35–45" as 35), or at a measured one: the pace over the last two to five minutes of fixes
    /// (`record`), else the speed of the fix (`speedKmh`) until there is such a pace. A speed under
    /// `crawl` says nothing: the timetable then. A measured time never goes below 0.6 × the
    /// timetable's fast end nor above 1.5 × its slow end ("35–45" from the start: 21 to 67.5), so
    /// a train slowing into a station cannot put the arrival hours away. Without a measured speed,
    /// the timetable's time exactly; with no stated time, the measured one as it is.
    public func minutesLeft(km: Double, speedKmh: Double? = nil) -> Double? {
        let left = max(0, ride.km - km)
        let share = ride.km > 0 ? left / ride.km : nil
        let fast = share.flatMap { s in TripTime.statedMinutes(ride.min).map { s * Double($0) } }
        guard let v = pace ?? speedKmh, v > Self.crawl else { return fast }
        let measured = left / v * 60
        guard let fast, let share, let high = TripTime.statedMaxMinutes(ride.min) else { return measured }
        let slow = share * Double(high)
        return min(max(measured, Self.quickest * fast), Self.slowest * slow)
    }

    /// Minutes until the stop before yours, where the research says to get ready; on a direct ride,
    /// until its last stretch (`tail`).
    public func minutesToAlightPrompt(km: Double, speedKmh: Double? = nil) -> Double? {
        let target: Double
        if isDirect {
            target = tail
        } else if let idx = ride.alight?.idx, ride.stations.indices.contains(idx) {
            target = ride.stations[idx].km
        } else {
            return minutesLeft(km: km, speedKmh: speedKmh).map { max(0, $0 - 3) }
        }
        guard let left = minutesLeft(km: km, speedKmh: speedKmh), ride.km - km > 0 else { return nil }
        return max(0, left * (target - km) / (ride.km - km))
    }

    /// When a followed ride's alarm rings, from a fix at `km` taken at `fix`: as the train leaves the
    /// stop before yours (`minutesToAlightPrompt`), never later than the timetable's alarm for the
    /// ride (`latest`, `WakePlanner.alarm(for:)`), which a slow train or a lost GPS cannot push back.
    /// Nil when that leaves too little time for a new alarm (`WakeReconciler.rideLead` after `now`):
    /// the one set stays as it is, and once the timetable's alarm has had its time, nothing more is
    /// asked for, however late the train runs (it has rung, early, once).
    ///
    /// `scheduled` is what is set for the ride now (`AlarmService.time(of:)`). Once that has had its
    /// time (`<= now`), an alarm has rung, and this tracker remembers it: from then on only the
    /// timetable's alarm, while it is still to come, never another GPS time. A fast stretch can put
    /// the GPS's alarm well before the stop (an arrival at 0.6 × the timetable); a train that then
    /// stops at a station would otherwise be rung for again and again. At most two rings: an early
    /// one from the GPS, then the timetable's.
    public mutating func alarm(km: Double, speedKmh: Double? = nil, at fix: Date, notAfter latest: Date?, scheduled: Date?, now: Date) -> Date? {
        if let scheduled, scheduled <= now { rang = true }
        if rang {
            guard let latest, latest > now.addingTimeInterval(WakeReconciler.rideLead) else { return nil }
            return latest
        }
        guard let prompt = minutesToAlightPrompt(km: km, speedKmh: speedKmh) else { return nil }
        let gps = fix.addingTimeInterval(prompt * 60)
        let at = latest.map { min(gps, $0) } ?? gps
        return at > now.addingTimeInterval(WakeReconciler.rideLead) ? at : nil
    }
}

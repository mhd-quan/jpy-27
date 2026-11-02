import Foundation

// MARK: - Geofences

/// A circle iOS watches in the background. Core Location keeps at most 20 per app, so the planner
/// picks the ones that matter next.
public struct Fence: Sendable, Hashable, Identifiable {
    public enum Kind: String, Sendable { case food, snack, station, stay }

    public var id: String { "\(kind.rawValue):\(placeID)" }
    public let placeID: String
    public let kind: Kind
    public let center: Coordinate
    /// metres
    public let radius: Double
    public let day: String
    /// item index on that day, for planned stops and departures
    public let index: Int?

    /// The app rebuilds fences from what it stored when it registered them with `CLMonitor`.
    public init(placeID: String, kind: Kind, center: Coordinate, radius: Double, day: String, index: Int?) {
        self.placeID = placeID
        self.kind = kind
        self.center = center
        self.radius = radius
        self.day = day
        self.index = index
    }
}

public struct FencePlanner: Sendable {
    public let store: TripStore
    public var limit = 20

    /// Metres: the place's `Presence` circle. Apple promises no better than about 100–200 m for a
    /// circle in a city, and a 60–90 m circle between Tokyo's towers either never fires or fires
    /// once you have walked past the door: a little early ("Owariya is round the corner, order the
    /// tempura soba") beats too late.
    public static func radius(_ place: Place) -> Double { Presence.radius(of: place) * 1000 }

    public init(store: TripStore) {
        self.store = store
    }

    /// Today's food stops still ahead, the snacks tied to today, the stations of today's fixed
    /// departures, tonight's hotel, then tomorrow's first meals.
    public func fences(today: Day, cursor: Int, tomorrow: Day?) -> [Fence] {
        var out: [Fence] = []
        var seen = Set<String>()
        func add(_ p: Place, _ kind: Fence.Kind, _ day: Day, _ index: Int?, radius: Double) {
            guard out.count < limit, seen.insert(p.id).inserted else { return }
            out.append(Fence(placeID: p.id, kind: kind, center: p.coordinate, radius: radius, day: day.key, index: index))
        }
        let itinerary = Itinerary(store: store)
        for (i, s) in today.stops where i >= cursor {
            if let p = store.place(s.place), p.kind == .food { add(p, .food, today, i, radius: Self.radius(p)) }
        }
        for a in today.along {
            if let p = store.place(a.place), p.snack != nil || p.menu != nil { add(p, .snack, today, nil, radius: Self.radius(p)) }
        }
        var i = cursor
        while let dep = itinerary.nextDeparture(today, cursor: i) {
            if let p = store.place(dep.move.leg.from) { add(p, .station, today, dep.index, radius: Self.radius(p)) }
            i = dep.index + 1
        }
        if let stay = store.place(today.stay) { add(stay, .stay, today, nil, radius: Self.radius(stay)) }
        if let tomorrow {
            for (i, s) in tomorrow.stops {
                if let p = store.place(s.place), p.kind == .food { add(p, .food, tomorrow, i, radius: Self.radius(p)) }
            }
        }
        return out
    }
}

// MARK: - Journal

/// A stay Core Location noticed (CLVisit), or a stop marked by hand.
public struct VisitRecord: Sendable, Hashable, Codable {
    public let arrival: Date
    public let departure: Date?
    public let coordinate: Coordinate

    public init(arrival: Date, departure: Date?, coordinate: Coordinate) {
        self.arrival = arrival
        self.departure = departure
        self.coordinate = coordinate
    }
}

extension VisitRecord {
    /// iOS reports one stay twice: when you arrive (no departure yet), then when you leave (both
    /// times). Records with the same arrival (within two minutes) and place (within 100 m) are one
    /// stay; the one that knows the departure wins.
    public static func merged(_ visits: [VisitRecord]) -> [VisitRecord] {
        var out: [VisitRecord] = []
        for v in visits.sorted(by: { $0.arrival < $1.arrival }) {
            if let k = out.firstIndex(where: { $0.isSameStay(as: v) }) {
                if out[k].departure == nil, v.departure != nil { out[k] = v }
            } else {
                out.append(v)
            }
        }
        return out
    }

    public func isSameStay(as other: VisitRecord) -> Bool {
        abs(arrival.timeIntervalSince(other.arrival)) <= 120 && Geo.km(coordinate, other.coordinate) <= 0.1
    }
}

/// The evening page: what was visited and when, what was late, what was dropped, what was extra.
public struct Journal: Sendable {
    public enum Status: Sendable, Hashable {
        /// arrived, minutes after the planned time (negative: early)
        case visited(arrival: Date, departure: Date?, late: Int?)
        case skipped
        case ahead
    }

    public struct Entry: Sendable, Identifiable {
        public var id: Int { index }
        public let index: Int
        public let stop: Stop
        public let place: Place
        public let status: Status
    }

    public struct Extra: Sendable, Identifiable {
        public var id: Date { visit.arrival }
        public let visit: VisitRecord
        /// a known place within 200 m, if any
        public let place: Place?
    }

    public let entries: [Entry]
    public let extras: [Extra]

    public var visited: Int { entries.filter { if case .visited = $0.status { true } else { false } }.count }
    public var skipped: Int { entries.filter { $0.status == .skipped }.count }

    public init(store: TripStore, day: Day, visits: [VisitRecord], marked: [Int: Date], now: Date) {
        let midnight = TripTime.midnight(day.date) ?? now
        let dayVisits = VisitRecord.merged(visits).filter { $0.arrival >= midnight.addingTimeInterval(4 * 3600) && $0.arrival < midnight.addingTimeInterval(28 * 3600) }
            .sorted { $0.arrival < $1.arrival }
        var entries: [Entry] = []
        let projected = PlanEngine(store: store).simulate(day)
        // each stay counts for the stop nearest to it, so one stay never fills two neighbours (Maruzen
        // and Tamai are 87 m apart); a place the day comes back to takes its stays in order
        let stops = day.stops.compactMap { i, s -> (index: Int, stop: Stop, place: Place)? in
            guard let p = store.place(s.place), p.kind != .station else { return nil }
            return (i, s, p)
        }
        var visitAt: [Int: Int] = [:]
        for v in dayVisits.indices {
            guard let id = Presence.nearest(dayVisits[v].coordinate, among: stops.map { ($0.place.id, $0.place) }),
                  let i = stops.first(where: { $0.place.id == id && visitAt[$0.index] == nil })?.index else { continue }
            visitAt[i] = v
        }
        let used = Set(visitAt.values)
        for (i, s, p) in stops {
            let arrival: Date?
            var departure: Date?
            if let v = visitAt[i] {
                arrival = min(dayVisits[v].arrival, marked[i] ?? .distantFuture)
                departure = dayVisits[v].departure
            } else {
                arrival = marked[i]
            }
            let status: Status
            if let arrival {
                let late = TripTime.minutes(s.at).map { planned in
                    Int(((TripTime.minutes(of: arrival, on: day.date) ?? 0) - Double(planned)).rounded())
                }
                status = .visited(arrival: arrival, departure: departure, late: late)
            } else {
                let end = projected.first { $0.index == i }.flatMap { TripTime.date(day.date, minutes: $0.end + 30) } ?? now
                status = now > end ? .skipped : .ahead
            }
            entries.append(Entry(index: i, stop: s, place: p, status: status))
        }
        self.entries = entries
        extras = dayVisits.indices.filter { !used.contains($0) }.compactMap { k in
            let v = dayVisits[k]
            if let d = v.departure, d.timeIntervalSince(v.arrival) < 10 * 60 { return nil }
            return Extra(visit: v, place: Presence.nearest(v.coordinate, among: store.trip.places.map { ($0, $0) }))
        }
    }
}

// MARK: - Walking pace

/// How fast these two walk compared with the model behind every walking time (3.9 km/h on the flat,
/// itself 0.78 × Tobler's 5.04 km/h). Learned from the pedometer and from legs actually walked.
public struct PaceModel: Codable, Sendable, Hashable {
    public private(set) var factor: Double
    /// minutes of walking behind the estimate
    public private(set) var minutes: Double

    public init(factor: Double = 1, minutes: Double = 0) {
        self.factor = factor
        self.minutes = minutes
    }

    static let toblerFlatKmh = 5.04
    static let bounds = 0.7 ... 1.35

    /// Active walking speed from the pedometer (pace while moving, not counting stops).
    public mutating func add(activeKmh: Double, over minutes: Double) {
        guard activeKmh > 1.5, activeKmh < 8, minutes >= 3 else { return }
        fold(activeKmh / Self.toblerFlatKmh, weight: minutes)
    }

    /// A walk that took `actual` minutes where the model said `planned`.
    public mutating func add(planned: Double, actual: Double) {
        guard planned >= 5, actual > 0, actual < planned * 3 else { return }
        fold(planned / actual, weight: actual)
    }

    /// Minutes of walking the model itself is worth before anything is measured: without it the
    /// first walk decides everything, and one slow leg (a crowd, a photo stop) would stretch every
    /// walk left in the trip.
    static let prior = 45.0

    private mutating func fold(_ sample: Double, weight: Double) {
        let s = min(Self.bounds.upperBound, max(Self.bounds.lowerBound, sample))
        // the last two hours of walking count most; older walks fade; the model never counts for
        // less than `prior`
        let keep = max(Self.prior, min(minutes, 120))
        factor = (factor * keep + s * weight) / (keep + weight)
        minutes += weight
    }
}

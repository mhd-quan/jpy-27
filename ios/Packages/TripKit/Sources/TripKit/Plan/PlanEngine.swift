import Foundation

/// Runs a clock through a day: walking time from the slope-aware model, transit from each leg's
/// stated lower bound plus a wait when no departure time is given, and a minimum stay at each stop.
/// With default options it is a line-for-line port of scripts/check-plan.mjs (the tests hold it to
/// that script's output); with live options it projects the rest of today from where you are.
public struct PlanEngine: Sendable {
    public let store: TripStore

    public init(store: TripStore) {
        self.store = store
    }

    public struct Options: Sendable {
        /// first item still ahead; earlier ones are done
        public var from: Int
        /// minutes since midnight to start the clock at (nil: the plan's own first time)
        public var clock: Double?
        /// minutes until you are where item `from` happens: done with its walk, at its stop,
        /// or at its boarding point — measured from your position instead of the plan's
        public var toReach: Double?
        /// stops to drop
        public var skips: Set<Int>
        /// walking pace relative to the model (1 = about 3.9 km/h on the flat)
        public var pace: Double
        /// wait for the planned time where nothing holds you to it: a timed stop without a booking,
        /// a timed departure on a line that runs every few minutes (the plan check does; a live
        /// projection does not, and takes the next train with half the interval as the wait)
        public var waitAtSoftStops: Bool

        public init(from: Int = 0, clock: Double? = nil, toReach: Double? = nil, skips: Set<Int> = [], pace: Double = 1, waitAtSoftStops: Bool = true) {
            self.from = from
            self.clock = clock
            self.toReach = toReach
            self.skips = skips
            self.pace = pace
            self.waitAtSoftStops = waitAtSoftStops
        }

        public static func live(from: Int, now: Double, toReach: Double? = nil, skips: Set<Int> = [], pace: Double = 1) -> Options {
            Options(from: from, clock: now, toReach: toReach, skips: skips, pace: pace, waitAtSoftStops: false)
        }
    }

    public struct Slot: Sendable, Hashable {
        public let index: Int
        /// when you are free to begin it: at the stop, or at the boarding point
        public let ready: Double
        /// when it begins: `ready`, or later when there is a time to wait for
        public let begin: Double
        /// when it is done
        public let end: Double
        /// the plan's time for it
        public let planned: Int?
        public let skipped: Bool
        /// a departure or a reservation: it will not wait for you
        public let hard: Bool
        /// the clock was already running when this item came up
        public let started: Bool

        /// minutes between being ready and the planned time; negative means late
        public var spare: Double? { planned.map { Double($0) - ready } }
    }

    // MARK: - The clock

    private struct PendingWalk {
        let pts: [Coordinate]
        let km: Double
        let min: Double
        var done: Double
        let to: String
    }

    /// A departure or a booking that will not wait: a timed ride on a reserved or sparse line, a
    /// timed stop that is booked. A metro or city line with a time in the plan is not one: the
    /// next train is a few minutes behind it.
    public func isHard(_ item: DayItem) -> Bool {
        switch item {
        case .move(let m): m.at != nil && store.mode(of: m.leg) != .walk && store.line(m.leg.line)?.isFrequent != true
        case .stop(let s): s.at != nil && s.place.map(store.reserved.contains) == true
        }
    }

    /// The wait for a ride that runs often, as a live projection counts it: half the interval.
    func frequentWait(_ leg: Leg) -> Double? {
        guard let line = store.line(leg.line), line.isFrequent, let every = line.every else { return nil }
        return Double(every) / 2
    }

    public func simulate(_ day: Day, _ o: Options = Options()) -> [Slot] {
        var slots: [Slot] = []
        var clock: Double? = o.clock
        var pending = resumedWalk(day, o)
        let merged = mergedWalks(day, o)

        for (i, item) in day.items.enumerated() where i >= o.from {
            let hard = isHard(item)
            switch item {
            case .move(let m):
                let leg = m.leg
                let mode = store.mode(of: leg)
                var dur: Double
                if mode == .walk {
                    let pts = store.path(leg.id)
                    let passes = leg.via.contains { v in day.items.contains { $0.stop?.place == v } }
                    if passes, !pts.isEmpty, let w = leg.walk {
                        pending = PendingWalk(pts: pts, km: w.km, min: w.minutes(pace: o.pace), done: 0, to: leg.to)
                        dur = 0
                    } else {
                        dur = leg.walk?.minutes(pace: o.pace) ?? Double(TripTime.statedMinutes(leg.min) ?? 5)
                    }
                    if let m = merged[i] { dur = m }
                } else {
                    dur = Double(TripTime.statedMinutes(leg.min) ?? 10)
                    if !o.waitAtSoftStops, let wait = frequentWait(leg) {
                        // live: whichever train comes next, not the one the plan named
                        dur += wait
                    } else if m.at == nil {
                        dur += Double(store.trip.rules.wait[mode.rawValue] ?? 5)
                    }
                }
                if i == o.from, let reach = o.toReach {
                    if mode == .walk {
                        dur = reach
                        pending = nil
                    } else {
                        clock = (clock ?? 0) + reach
                    }
                }
                let at = TripTime.minutes(m.at).map(Double.init)
                let started = clock != nil
                let ready = clock ?? at ?? 0
                if let at, hard || o.waitAtSoftStops || clock == nil { clock = max(clock ?? 0, at) }
                let begin = clock ?? 0
                clock = begin + dur
                slots.append(Slot(index: i, ready: ready, begin: begin, end: clock!, planned: TripTime.minutes(m.at), skipped: false, hard: hard, started: started))

            case .stop(let s):
                if i == o.from, let reach = o.toReach { clock = (clock ?? 0) + reach }
                if var walk = pending, let id = s.place, let p = store.place(id) {
                    let km = Self.along(walk.pts, p.coordinate)
                    let part = max(0, km - walk.done)
                    clock = (clock ?? 0) + walk.min * part / walk.km
                    walk.done = max(walk.done, km)
                    pending = id == walk.to ? nil : walk
                }
                let skipped = o.skips.contains(i)
                let at = TripTime.minutes(s.at).map(Double.init)
                let started = clock != nil
                let ready = clock ?? at ?? 0
                if let at, !skipped, hard || o.waitAtSoftStops {
                    clock = max(clock ?? at, at)
                }
                let begin = clock ?? ready
                clock = begin + (skipped ? 0 : Double(dwell(s)))
                slots.append(Slot(index: i, ready: ready, begin: begin, end: clock!, planned: TripTime.minutes(s.at), skipped: skipped, hard: hard, started: started))
            }
        }
        return slots
    }

    /// Minimum minutes at a stop (scripts/check-plan.mjs `dwell`).
    public func dwell(_ s: Stop) -> Int {
        let p = store.place(s.place)
        if let p, let d = store.trip.rules.dwell[p.id] { return d }
        let title = s.title
        func has(_ pattern: String) -> Bool { title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }
        if has("trả phòng|Ăn sáng|Buffet") { return 40 }
        if has("Nhận phòng") { return 15 }
        if has("Gửi") { return 10 }
        guard let p else { return 10 }
        switch p.kind {
        case .food:
            let cost = s.cost ?? 0
            return cost >= 5000 ? 60 : cost >= 2000 ? 45 : 20
        case .shop: return 30
        case .station, .stay: return 10
        case .sight: return s.isOptional ? 20 : 30
        }
    }

    /// Distance along a polyline to the point nearest p, sampled the way check-plan.mjs samples it.
    static func along(_ pts: [Coordinate], _ p: Coordinate) -> Double {
        var acc = 0.0
        var bestOff = Double.infinity
        var bestKm = 0.0
        for i in 1 ..< max(1, pts.count) {
            let a = pts[i - 1], b = pts[i]
            let seg = Geo.km(a, b)
            var t = 0.0
            while t <= 1 {
                let q = Coordinate(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
                let off = Geo.km(q, p)
                if off < bestOff {
                    bestOff = off
                    bestKm = acc + seg * t
                }
                t += 0.1
            }
            acc += seg
        }
        return bestKm
    }

    /// Starting mid-walk: a walk that passes stops still ahead keeps counting from the first of them.
    private func resumedWalk(_ day: Day, _ o: Options) -> PendingWalk? {
        guard o.from > 0, o.from < day.items.count, case .stop(let first) = day.items[o.from] else { return nil }
        for j in stride(from: o.from - 1, through: 0, by: -1) {
            guard case .move(let m) = day.items[j] else { continue }
            guard store.mode(of: m.leg) == .walk else { return nil }
            let pts = store.path(m.leg.id)
            let ahead = day.items[o.from...].contains { $0.stop?.place == m.leg.to }
            guard ahead, let w = m.leg.walk, !pts.isEmpty, m.leg.via.contains(where: { v in day.items.contains { $0.stop?.place == v } }) else { return nil }
            let done = store.place(first.place).map { Self.along(pts, $0.coordinate) } ?? 0
            return PendingWalk(pts: pts, km: w.km, min: w.minutes(pace: o.pace), done: done, to: m.leg.to)
        }
        return nil
    }

    /// Dropping a stop between two walks turns them into one walk, straight there.
    private func mergedWalks(_ day: Day, _ o: Options) -> [Int: Double] {
        var out: [Int: Double] = [:]
        // a walk index → the first walk of its merged chain and where that chain started
        var chain: [Int: (first: Int, from: String, minutes: Double)] = [:]
        for k in o.skips.sorted() {
            guard k > 0, k + 1 < day.items.count,
                  case .stop(let s) = day.items[k], let id = s.place,
                  case .move(let before) = day.items[k - 1], store.mode(of: before.leg) == .walk, before.leg.to == id,
                  case .move(let after) = day.items[k + 1], store.mode(of: after.leg) == .walk, after.leg.from == id
            else { continue }
            let head = chain[k - 1] ?? (first: k - 1, from: before.leg.from, minutes: walkMinutes(before.leg, o.pace))
            let total = head.minutes + walkMinutes(after.leg, o.pace)
            guard let a = store.place(head.from), let b = store.place(after.leg.to) else { continue }
            let direct = Self.directWalk(a.coordinate, b.coordinate, pace: o.pace)
            guard direct < total else { continue }
            out[head.first] = direct
            for j in head.first + 1 ... k + 1 where day.items[j].move != nil { out[j] = 0 }
            chain[k + 1] = (first: head.first, from: head.from, minutes: total)
        }
        return out
    }

    private func walkMinutes(_ leg: Leg, _ pace: Double) -> Double {
        leg.walk?.minutes(pace: pace) ?? Double(TripTime.statedMinutes(leg.min) ?? 5)
    }

    /// A walk with no routed geometry: the straight line bent by city blocks, plus a minute to find the way.
    public static func directWalk(_ a: Coordinate, _ b: Coordinate, pace: Double = 1) -> Double {
        Geo.km(a, b) * 1.3 / (3.9 * max(0.5, pace)) * 60 + 1
    }

    // MARK: - The plan check

    public struct Finding: Sendable, Hashable {
        public enum Kind: Sendable { case late, tight }
        public let kind: Kind
        public let index: Int
        /// how many minutes late (positive) or to spare (tight)
        public let minutes: Int
        /// the line check-plan.mjs prints
        public let line: String
    }

    /// Stops and departures planned earlier than they can be reached, and the tight ones.
    public func check(_ day: Day) -> [Finding] {
        var out: [Finding] = []
        for slot in simulate(day) {
            let item = day.items[slot.index]
            guard let at = item.at, let planned = slot.planned, slot.started else { continue }
            let clock = slot.ready
            switch item {
            case .move(let m):
                if Double(planned) < clock - 1 {
                    let name = store.line(m.leg.line)?.name ?? m.leg.line
                    let late = Self.jsRound(clock - Double(planned))
                    out.append(Finding(kind: .late, index: slot.index, minutes: late, line: "  ! \(at) \(name) \(m.leg.from) → \(m.leg.to): free only at \(Self.jsClock(clock)) (\(late) min late)"))
                }
            case .stop(let s):
                if Double(planned) < clock - 2 {
                    let late = Self.jsRound(clock - Double(planned))
                    out.append(Finding(kind: .late, index: slot.index, minutes: late, line: "  ! \(at) \(s.title): earliest arrival \(Self.jsClock(clock)) (\(late) min short)"))
                } else if Double(planned) - clock < 3, s.title.range(of: "^(Gửi|Nhận phòng)", options: .regularExpression) == nil {
                    let spare = Self.jsRound(Double(planned) - clock)
                    out.append(Finding(kind: .tight, index: slot.index, minutes: spare, line: "  ~ \(at) \(s.title): only \(spare) min to spare"))
                }
            }
        }
        return out
    }

    /// JavaScript's Math.round: halves go up, also below zero.
    static func jsRound(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    /// check-plan.mjs `fmt`
    static func jsClock(_ m: Double) -> String {
        let h = Int((m / 60).rounded(.down))
        let r = jsRound(m.truncatingRemainder(dividingBy: 60))
        return "\(h):\(r < 10 ? "0" : "")\(r)"
    }
}

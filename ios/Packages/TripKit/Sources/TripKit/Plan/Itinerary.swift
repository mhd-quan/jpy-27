import Foundation

/// Where the trip stands at an instant.
public enum TripPhase: Sendable {
    /// before the first day: days to go and that day
    case before(days: Int, first: Day)
    case during(Day)
    case after
}

/// A place or a fixed departure worth announcing: "Next: Owariya — set off 12:32".
public struct Waypoint: Sendable, Hashable, Identifiable {
    public enum Kind: Sendable, Hashable { case stop, departure, reservation }

    public var id: Int { index }
    public let index: Int
    public let kind: Kind
    public let title: String
    /// the stop's place, or the station a departure leaves from
    public let placeID: String?
    /// minutes since midnight: when to leave the previous place
    public let setOff: Double
    /// minutes since midnight: when it begins
    public let begin: Double
    public let planned: Int?
}

public struct Itinerary: Sendable {
    public let store: TripStore
    public let engine: PlanEngine

    public init(store: TripStore) {
        self.store = store
        engine = PlanEngine(store: store)
    }

    /// minutes kept in hand before a train or a table
    public static let margin = 3.0

    public func phase(at instant: Date, days: [Day]) -> TripPhase {
        guard let first = days.first, let last = days.last,
              let start = TripTime.midnight(first.date), let end = TripTime.midnight(last.date)
        else { return .after }
        if instant < start {
            let d = TripTime.calendar.dateComponents([.day], from: TripTime.calendar.startOfDay(for: instant), to: start).day ?? 0
            return .before(days: max(1, d), first: first)
        }
        if instant >= end.addingTimeInterval(86400) { return .after }
        let iso = TripTime.isoDate(of: instant)
        return days.first { $0.date == iso }.map(TripPhase.during) ?? .after
    }

    /// The day's stops and fixed departures with the times the plan gives them.
    public func waypoints(_ day: Day) -> [Waypoint] {
        let slots = engine.simulate(day)
        var out: [Waypoint] = []
        var lastLeave: Double? = nil
        var travelSince = 0.0
        for slot in slots {
            let item = day.items[slot.index]
            switch item {
            case .move(let m):
                let mode = store.mode(of: m.leg)
                if slot.hard, mode != .walk {
                    // the latest you can leave and still be on the platform, with a small margin
                    let setOff = Double(slot.planned ?? Int(slot.begin)) - travelSince - Self.margin
                    out.append(Waypoint(index: slot.index, kind: .departure, title: store.line(m.leg.line)?.name ?? m.leg.line, placeID: m.leg.from, setOff: setOff, begin: slot.begin, planned: slot.planned))
                    travelSince = 0
                    lastLeave = slot.end
                } else {
                    travelSince += slot.end - slot.begin
                }
            case .stop(let s):
                defer {
                    lastLeave = slot.end
                    travelSince = 0
                }
                guard let id = s.place, let p = store.place(id), p.kind != .station else { continue }
                let kind: Waypoint.Kind = slot.hard ? .reservation : .stop
                let setOff = slot.hard ? Double(slot.planned ?? Int(slot.begin)) - travelSince - Self.margin : (lastLeave ?? slot.begin - travelSince)
                out.append(Waypoint(index: slot.index, kind: kind, title: s.title, placeID: id, setOff: setOff, begin: slot.begin, planned: slot.planned))
            }
        }
        return out
    }

    /// First item still ahead: right after the last one marked done, otherwise by the plan's clock,
    /// unless where you stand says otherwise. The clock alone puts you at the station at 16:05
    /// while you may still be inside Sensō-ji; standing at a stop, you are at that stop, whether
    /// the clock has moved past it (late) or not reached it yet (early). Only stops up to the next
    /// departure that will not wait count, so being near a later stop never skips a train.
    public func cursor(_ day: Day, done: Set<Int>, now: Double, position: Coordinate? = nil, skips: Set<Int> = []) -> Int {
        let floor = done.max().map { min($0 + 1, day.items.count) } ?? 0
        let slots = engine.simulate(day)
        let clock = done.isEmpty ? (slots.first { $0.end > now }?.index ?? day.items.count) : floor
        guard let position, clock < day.items.count else { return clock }
        let ceiling = (clock ..< day.items.count).first { engine.isHard(day.items[$0]) } ?? (day.items.count - 1)
        guard floor <= ceiling else { return clock }
        let ends = Dictionary(slots.map { ($0.index, $0.end) }, uniquingKeysWith: { a, _ in a })
        var best: (index: Int, ratio: Double)?
        for i in floor ... ceiling where !done.contains(i) && !skips.contains(i) {
            guard case .stop(let s) = day.items[i], let p = store.place(s.place), p.kind != .station else { continue }
            // a stop the plan left more than two hours ago is not where the day stands, even when
            // the evening walk passes it again
            if let end = ends[i], end < now - 120 { continue }
            let radius = Self.atRadius(p)
            let ratio = Geo.km(p.coordinate, position) / radius
            // nearest relative to the place's size; on a tie, the later stop
            if ratio <= 1, best.map({ ratio <= $0.ratio }) ?? true { best = (i, ratio) }
        }
        return best?.index ?? clock
    }

    /// How close counts as being at a place, km: temple grounds and parks are wide, a counter is not.
    public static func atRadius(_ p: Place) -> Double {
        p.kind == .sight ? 0.25 : 0.12
    }

    /// The next waypoint at or after the cursor.
    public func next(_ day: Day, cursor: Int) -> Waypoint? {
        waypoints(day).first { $0.index >= cursor }
    }

    /// The next departure that will not wait (train, bus, boat with a time) from the cursor on.
    public func nextDeparture(_ day: Day, cursor: Int) -> (index: Int, move: Move)? {
        for i in cursor ..< day.items.count {
            if case .move(let m) = day.items[i], engine.isHard(day.items[i]) { return (i, m) }
        }
        return nil
    }

    /// Minutes a leg takes, at a personal walking pace.
    public func minutes(of move: Move, pace: Double = 1) -> Double {
        if store.mode(of: move.leg) == .walk {
            return move.leg.walk?.minutes(pace: pace) ?? Double(TripTime.statedMinutes(move.leg.min) ?? 5)
        }
        return Double(TripTime.statedMinutes(move.leg.min) ?? 10)
    }

    /// Where item `index` happens: a stop's place, or where a move ends.
    public func destination(_ day: Day, _ index: Int) -> Place? {
        guard day.items.indices.contains(index) else { return nil }
        switch day.items[index] {
        case .stop(let s): return store.place(s.place)
        case .move(let m): return store.place(store.mode(of: m.leg) == .walk ? m.leg.to : m.leg.from)
        }
    }

    /// Minutes from a position to where item `index` happens, on foot (PlanEngine.Options.toReach).
    public func toReach(_ day: Day, _ index: Int, from position: Coordinate, pace: Double = 1) -> Double? {
        destination(day, index).map { PlanEngine.directWalk(position, $0.coordinate, pace: pace) }
    }

    /// Live projection of the rest of the day from where you are, and a replan when a fixed time
    /// is at risk.
    public func project(_ day: Day, done: Set<Int>, now: Double, position: Coordinate?, pace: Double = 1, skips: Set<Int> = []) -> (cursor: Int, slots: [PlanEngine.Slot], replan: Replan?) {
        let from = cursor(day, done: done, now: now, position: position, skips: skips)
        guard from < day.items.count else { return (from, [], nil) }
        let reach = position.flatMap { toReach(day, from, from: $0, pace: pace) }
        let o = PlanEngine.Options.live(from: from, now: now, toReach: reach, skips: skips, pace: pace)
        return (from, engine.simulate(day, o), engine.replan(day, o))
    }
}

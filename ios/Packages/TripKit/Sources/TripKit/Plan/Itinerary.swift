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

    /// First item still ahead: right after the last one marked done, otherwise by the plan's clock.
    public func cursor(_ day: Day, done: Set<Int>, now: Double) -> Int {
        if let last = done.max() { return min(last + 1, day.items.count) }
        let slots = engine.simulate(day)
        return slots.first { $0.end > now }?.index ?? day.items.count
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

    /// Live projection of the rest of the day, and a replan when a fixed time is at risk.
    public func project(_ day: Day, done: Set<Int>, now: Double, position: Coordinate?, pace: Double = 1, skips: Set<Int> = []) -> (slots: [PlanEngine.Slot], replan: Replan?) {
        let from = cursor(day, done: done, now: now)
        guard from < day.items.count else { return ([], nil) }
        let reach = position.flatMap { toReach(day, from, from: $0, pace: pace) }
        let o = PlanEngine.Options.live(from: from, now: now, toReach: reach, skips: skips, pace: pace)
        return (engine.simulate(day, o), engine.replan(day, o))
    }
}

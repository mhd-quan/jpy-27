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

    /// The day's stops and fixed departures with the times the plan gives them. Worked out once
    /// per day and kept (`TripStore.waypoints`).
    public func waypoints(_ day: Day) -> [Waypoint] {
        store.waypoints(day) { makeWaypoints(day) }
    }

    private func makeWaypoints(_ day: Day) -> [Waypoint] {
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
    /// departure that will not wait count, so being near a later stop never skips a train — unless
    /// that departure is gone and where you stand says so (`locate`).
    public func cursor(_ day: Day, done: Set<Int>, now: Double, position: Coordinate? = nil, skips: Set<Int> = []) -> Int {
        locate(day, done: done, now: now, position: position, skips: skips).cursor
    }

    /// A ride the day is on: its last leg is item `last`.
    typealias Riding = (last: Int, ride: Ride)

    /// The cursor, and the ride it was put after when you are on that ride.
    ///
    /// A departure that will not wait, whose time has come, is *taken* when you are not inside its
    /// station's circle (there the plan clock holds it: `PlanEngine.Options.position`) and are more
    /// than a kilometre from that station or on its line: stops after it, up to the next departure
    /// not taken, may then hold you. Only that; a hotel eight kilometres away at 7:45 is a missed
    /// Romancecar, not a taken one. It is *ridden* when you are on its line (`RideTracker`, within
    /// a kilometre), more than a kilometre from its station, and more than a kilometre from every
    /// place the day named before it (still in Fujiyoshida after the 16:48 back to Shinjuku, which
    /// runs past the town, is not riding it): with no stop holding you, the day is right after it.
    ///
    /// The plan's clock counts only once one of the day's planned times has come (`planned < now`).
    /// Before that, or all day on a day with no time at all (the way to the airport, whose made-up
    /// times start at midnight and end before 1:30), the day is at its first item until a mark or
    /// where you stand moves it.
    func locate(_ day: Day, done: Set<Int>, now: Double, position: Coordinate?, skips: Set<Int>) -> (cursor: Int, riding: Riding?) {
        let count = day.items.count
        let floor = done.max().map { min($0 + 1, count) } ?? 0
        let slots = engine.simulate(day)
        let timed = slots.contains { $0.planned.map { Double($0) < now } ?? false }
        let clock = !done.isEmpty ? floor : timed ? (slots.first { $0.end > now }?.index ?? count) : 0
        guard let position, clock < count else { return (clock, nil) }
        var ceiling = count - 1
        var ridden: Riding?
        for j in clock ..< count where engine.isHard(day.items[j]) {
            guard case .move(let m) = day.items[j], let at = TripTime.minutes(m.at), Double(at) < now,
                  let station = store.place(m.leg.from), !Presence.isAt(position, station) else {
                ceiling = j
                break
            }
            let away = Geo.km(position, station.coordinate) > 1
            let ride = store.ride(containing: m.leg.id, on: day)
            let onLine = ride.flatMap { RideTracker(ride: $0, store: store).status(at: position) }.map { $0.offTrackKm < 1 } ?? false
            guard away || onLine else {
                ceiling = j
                break
            }
            if away, onLine, let ride, let last = lastLeg(of: ride, in: day), !named(day, before: j, near: position) {
                ridden = (last, ride)
            }
        }
        guard floor <= ceiling else { return (clock, nil) }
        let ends = Dictionary(slots.map { ($0.index, $0.end) }, uniquingKeysWith: { a, _ in a })
        var candidates: [(Int, Place)] = []
        for i in floor ... ceiling where !done.contains(i) && !skips.contains(i) {
            guard case .stop(let s) = day.items[i], let p = store.place(s.place), p.kind != .station else { continue }
            // a stop the plan left more than two hours ago is not where the day stands, even when
            // the evening walk passes it again (a day the clock does not run has no such hours)
            if timed, let end = ends[i], end < now - 120 { continue }
            candidates.append((i, p))
        }
        // the nearest stop you are at; latest first, so a place the day comes back to counts as the return
        if let at = Presence.nearest(position, among: candidates.reversed()) { return (at, nil) }
        if let ridden { return (ridden.last + 1, ridden) }
        return (clock, nil)
    }

    /// A place the day's items before `index` name (a stop, where a move starts or ends) lies within
    /// a kilometre.
    private func named(_ day: Day, before index: Int, near position: Coordinate) -> Bool {
        day.items[..<index].contains { item in
            let ids: [String?] = switch item {
            case .stop(let s): [s.place]
            case .move(let m): [m.leg.from, m.leg.to]
            }
            return ids.contains { store.place($0).map { Geo.km($0.coordinate, position) <= 1 } ?? false }
        }
    }

    /// The item of a ride's last leg, when its legs are one run of the day's items: the ropeway that
    /// stops at Ōwakudani between its two legs has none, so following it never skips the stop.
    private func lastLeg(of ride: Ride, in day: Day) -> Int? {
        let legs = day.items.indices.filter { i in day.items[i].move.map { ride.legs.contains($0.leg.id) } ?? false }
        guard let first = legs.first, let last = legs.last, legs.count == ride.legs.count, last - first + 1 == legs.count else { return nil }
        return last
    }

    /// When a ride ends, minutes since midnight: from where its track has you, at the timetable's
    /// pace and never before its timetable arrival; off its track or with no position, when the plan
    /// has it end, and never before now.
    func arrival(of riding: Riding, in day: Day, now: Double, position: Coordinate?) -> Double {
        let tracker = RideTracker(ride: riding.ride, store: store)
        if let position, let s = tracker.status(at: position), s.offTrackKm < 1, let left = tracker.minutesLeft(km: s.km) {
            return max(now + left, tracker.plannedArrival ?? now)
        }
        return max(now, engine.simulate(day).first { $0.index == riding.last }?.end ?? now)
    }

    /// The stop a stay at `position` belongs to, from item `from` on: the nearest of the day's
    /// stops whose `Presence` circle holds it, done or not, so that a second report of a stay at
    /// a stop already marked never marks its neighbour. A place the day comes back to is its first
    /// visit not yet done.
    public func stop(at position: Coordinate, in day: Day, from: Int = 0, done: Set<Int>) -> Int? {
        let candidates = day.stops
            .filter { $0.index >= from }
            .compactMap { i, s in store.place(s.place).map { (i, $0) } }
            .sorted { (done.contains($0.0) ? 1 : 0, $0.0) < (done.contains($1.0) ? 1 : 0, $1.0) }
        return Presence.nearest(position, among: candidates)
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
    ///
    /// `riding` is the ride being followed. Once its time has come (an untimed one at once), when
    /// its legs are one run of the day's items and nothing is marked past them, the day goes on
    /// right after it — unless a stop after it holds you — with the clock at its arrival
    /// (`arrival(of:)`), not at the walk from the train to the next place. Without it, a ride the
    /// position says you are on does the same (`locate`); with no position, nothing is inferred.
    /// `riding` in the result is the ride the projection started after, if any.
    public func project(_ day: Day, done: Set<Int>, now: Double, position: Coordinate?, pace: Double = 1, skips: Set<Int> = [], riding: Ride? = nil) -> (cursor: Int, slots: [PlanEngine.Slot], replan: Replan?, riding: Ride?) {
        var marks = done
        var followed: Riding?
        if let riding, riding.day == day.key, let last = lastLeg(of: riding, in: day), (done.max() ?? -1) <= last,
           TripTime.minutes(riding.at).map({ Double($0) <= now }) ?? true {
            // its legs count as done: the day is past them
            marks.insert(last)
            followed = (last, riding)
        }
        let located = locate(day, done: marks, now: now, position: position, skips: skips)
        let from = located.cursor
        guard from < day.items.count else { return (from, [], nil, nil) }
        let on = located.riding ?? followed.flatMap { $0.last + 1 == from ? $0 : nil }
        var o: PlanEngine.Options
        if let on {
            o = .live(from: from, now: arrival(of: on, in: day, now: now, position: position), skips: skips, pace: pace, position: position)
        } else {
            let reach = position.flatMap { toReach(day, from, from: $0, pace: pace) }
            o = .live(from: from, now: now, toReach: reach, skips: skips, pace: pace, position: position)
        }
        return (from, engine.simulate(day, o), engine.replan(day, o), on?.ride)
    }
}

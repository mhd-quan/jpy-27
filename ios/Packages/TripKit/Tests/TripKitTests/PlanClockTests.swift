import Foundation
import Testing
@testable import TripKit

/// The plan clock's hand-written readers, held to the regular expressions they replace, and the
/// day memo, reminders and item identities built on them.
@Suite struct PlanClockTests {
    let store = Bundle_.store

    // MARK: The patterns as they were

    static func regexMinutes(_ s: String?) -> Int? {
        guard let s else { return nil }
        if let m = s.firstMatch(of: /(\d+)\s*giờ\s*(\d+)?/), let h = Int(m.1) {
            return h * 60 + (m.2.flatMap { Int($0) } ?? 0)
        }
        if let m = s.firstMatch(of: /\d+/) { return Int(m.0) }
        return nil
    }

    static func regexMaxMinutes(_ s: String?) -> Int? {
        guard let s, let low = regexMinutes(s) else { return nil }
        if s.contains("giờ") { return low }
        if let m = s.firstMatch(of: /^\s*\d+\s*[–-]\s*(\d+)/), let high = Int(m.1) { return max(low, high) }
        return low
    }

    func regexDwell(_ s: Stop) -> Int {
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

    var allDays: [Day] { store.trip.days + store.trip.altDays }

    // MARK: Stated times

    @Test func statedTimesOfThePlanReadAsBefore() {
        let texts = allDays.flatMap { $0.items.compactMap { $0.move?.leg.min } } + (store.trip.rides + store.trip.altRides).compactMap(\.min)
        #expect(texts.count > 100)
        for t in texts {
            #expect(TripTime.statedMinutes(t) == Self.regexMinutes(t), "\(t)")
            #expect(TripTime.statedMaxMinutes(t) == Self.regexMaxMinutes(t), "\(t)")
        }
    }

    @Test func statedTimesReadAsThePatternsWould() {
        let cases = ["1 giờ 40", "20–25, đổi tàu", "60–90 tính cả chờ", "2 giờ", "3–4 giờ, tính cả dừng", "35-45", " 35 – 45",
                     "giờ 5", "khoảng 1giờ5", "1 giờ", "12giờ30", "x 7 y 8 giờ 9", "", "không rõ", "５ giờ", "２０–２５",
                     "1 GIỜ 40", "3\u{0301} giờ", "1 gio\u{031B}\u{0300} 40", "1\u{00A0}giờ\u{00A0}05", "45–", "–45", "10 - 15 phút"]
        for t in cases {
            #expect(TripTime.statedMinutes(t) == Self.regexMinutes(t), "\(t)")
            #expect(TripTime.statedMaxMinutes(t) == Self.regexMaxMinutes(t), "\(t)")
        }
        #expect(TripTime.statedMinutes(nil) == nil)
        #expect(TripTime.statedMinutes("1 giờ 40") == 100)
        #expect(TripTime.statedMaxMinutes("35–45") == 45)
    }

    @Test func statedTimesMatchThePatternsOnRandomText() {
        let pieces = ["1", "2", "0", "9", "45", " ", "  ", "\u{00A0}", "\t", "giờ", "g", "i", "ờ", "gi", "–", "-", ",", "x",
                      "phút", "５", "²", "½", "3\u{0301}", "\u{0301}", "GIỜ", "\r\n", "o\u{031B}\u{0300}", "đổi", "~"]
        var rng = SplitMix(seed: 27)
        for _ in 0 ..< 20000 {
            let n = Int(rng.next() % 9)
            let t = (0 ..< n).map { _ in pieces[Int(rng.next() % UInt64(pieces.count))] }.joined()
            #expect(TripTime.statedMinutes(t) == Self.regexMinutes(t), "\(t.debugDescription)")
            #expect(TripTime.statedMaxMinutes(t) == Self.regexMaxMinutes(t), "\(t.debugDescription)")
        }
    }

    // MARK: Dwell and errands

    @Test func dwellReadsEveryStopAsBefore() {
        let engine = PlanEngine(store: store)
        let stops = allDays.flatMap { $0.stops.map(\.stop) }
        #expect(stops.count > 50)
        for s in stops {
            #expect(engine.dwell(s) == regexDwell(s), "\(s.title)")
            #expect(s.isErrand == (s.title.range(of: "^(Gửi|Nhận phòng)", options: .regularExpression) != nil), "\(s.title)")
        }
        // the table the store made holds the same
        for day in allDays {
            for (i, s) in day.stops { #expect(engine.dwell(day, i, s) == regexDwell(s)) }
        }
    }

    // MARK: The day memo

    @Test func thePlanOfADayIsWorkedOutOnceAndStaysTheSame() {
        let engine = PlanEngine(store: store)
        let itinerary = Itinerary(store: store)
        for day in allDays {
            let a = engine.simulate(day), b = engine.simulate(day, PlanEngine.Options())
            #expect(a == b)
            #expect(a.count == day.items.count)
            #expect(itinerary.waypoints(day) == itinerary.waypoints(day))
        }
        // a live projection is not the plan, and is not kept as it
        let day = store.day("4")!
        let live = engine.simulate(day, .live(from: 0, now: 6 * 60))
        #expect(live.first?.ready == Double(6 * 60))
        #expect(engine.simulate(day).first?.ready != Double(6 * 60))
        // days are kept apart
        #expect(engine.simulate(store.day("2")!) != engine.simulate(store.day("3")!))
    }

    // MARK: Reminders

    @Test func settledItemsHaveNoReminder() throws {
        let day = store.day("4")!
        let planner = ReminderPlanner(store: store)
        let all = planner.reminders(for: day)
        let dep = try #require(all.first { $0.kind == .departure })
        let index = try #require(dep.itemID.flatMap { day.index(of: $0) })
        let left = planner.reminders(for: day) { d, i in d.key == day.key && i == index }
        #expect(!left.contains { $0.id == dep.id })
        #expect(left.count == all.count - 1)
        // the morning and the journal stay
        #expect(left.contains { $0.kind == .morning } && left.contains { $0.kind == .journal })
    }

    @Test func upcomingLooksOnlyAtTheDaysAhead() {
        let planner = ReminderPlanner(store: store)
        let days = store.days()
        for (k, day) in days.enumerated() where k % 3 == 0 {
            let now = TripTime.date(day.date, minutes: 6 * 60)!
            let until = now.addingTimeInterval(2 * 86400)
            let all: [Reminder] = days.flatMap { planner.reminders(for: $0) } + planner.bookings()
            let every = all
                .filter { $0.fire > now && $0.fire < until }.sorted { $0.fire < $1.fire }.prefix(60).map(\.id)
            #expect(planner.upcoming(days: days, now: now).map(\.id) == Array(every))
        }
        // months before: only bookings can be due
        let before = TripTime.date(days[0].date, minutes: 0)!.addingTimeInterval(-90 * 86400)
        #expect(planner.upcoming(days: days, now: before).allSatisfy { $0.kind == .booking })
    }

    // MARK: Item identity (the rest is in ItemIdentityTests)

    /// A record moved aside below 0 while the indexes are put right (`RecordIndexes`), and left there
    /// by a second write that failed or because another record took its index, still finds its item.
    @Test func aRecordSetAsideBelowZeroFindsItsItem() {
        for day in allDays {
            for i in day.items.indices {
                for k in [1, 2, 9] {
                    #expect(day.resolve(-k, identity: day.identity(of: i)) == i, "day \(day.key): item \(i) recorded at -\(k)")
                }
            }
        }
    }
}

/// A small fixed-seed generator, so the random cases are the same on every run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

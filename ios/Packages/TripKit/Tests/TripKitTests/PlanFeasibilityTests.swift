import Foundation
import Testing
@testable import TripKit

/// The plan can be kept: checked on its own, not only against what scripts/check-plan.mjs prints (a
/// broken plan and a fixture made from it agree with each other).
@Suite struct PlanFeasibilityTests {
    let store = Bundle_.store
    var engine: PlanEngine { PlanEngine(store: store) }

    @Test func everyTimedItemCanBeReached() {
        for day in store.trip.days + store.trip.altDays {
            #expect(!engine.check(day).contains { $0.kind == .late }, "Day \(day.key)")
        }
    }

    @Test func noTightFindingIsNegative() {
        for day in store.trip.days + store.trip.altDays {
            for f in engine.check(day) where f.kind == .tight { #expect(f.minutes >= 0, "\(f.line)") }
        }
    }

    @Test func aStopMovedBeforeItCanBeReachedIsLate() throws {
        let store = try TripStore.patched { trip in trip.setStop(day: "2", place: "nezu-shrine", at: "6:00") }
        let late = PlanEngine(store: store).check(store.day("2")!).filter { $0.kind == .late }
        #expect(late.map(\.minutes) == [302])
    }

    @Test func theTailOfAWalkIsCountedBeforeTheNextRide() {
        let day = store.day("10")!
        let keihan = engine.simulate(day).first { day.items[$0.index].move?.at == "8:30" }!
        #expect(keihan.ready >= 8 * 60 + 15)
        // the same value is pinned in scripts/check-plan.test.mjs: the two clocks agree on the tail
        #expect(abs(keihan.ready - 496.858) < 0.001, "ready at \(keihan.ready)")
    }

    @Test func aStopWithinTheGraceIsNotLate() throws {
        // Nezu Jinja at its old 11:00: reached at 11:02, inside the 2-minute grace
        let store = try TripStore.patched { trip in trip.setStop(day: "2", place: "nezu-shrine", at: "11:00") }
        let found = PlanEngine(store: store).check(store.day("2")!)
        #expect(!found.contains { $0.kind == .late })
        #expect(!found.contains { $0.kind == .tight && $0.minutes < 0 })
        let grace = found.filter { $0.kind == .grace }
        #expect(grace.map(\.minutes) == [2])
        #expect(grace.map(\.line) == ["  ≈ 11:00 Nezu Jinja: 2 min late, within the 2-min grace"])
    }

    @Test func anErrandWithinTheGraceStaysQuiet() throws {
        // checking in at ERA Ise (Day 5, 17:20) is reached a minute after its time: an errand, so no line
        let day = try #require(store.day("5"))
        let index = try #require(day.items.firstIndex { $0.stop?.place == "era-ise" })
        let spare = try #require(engine.simulate(day).first { $0.index == index }?.spare)
        #expect(spare < 0 && spare >= -2, "spare \(spare)")
        #expect(!engine.check(day).contains { $0.index == index })
        // beyond the grace it is late like any other stop
        let early = try TripStore.patched { trip in trip.setStop(day: "5", place: "era-ise", at: "17:00") }
        let late = PlanEngine(store: early).check(early.day("5")!).filter { $0.index == index }
        #expect(late.map(\.kind) == [.late])
    }

    @Test func theReplannerGivesARideLessGraceThanABooking() throws {
        // the booked lunch at AWA (Day 10, 12:30) and the Romancecar 7:37 (Day 4), each reached at a
        // set number of minutes after its time: a booking keeps 2 minutes of grace, a train 1
        let day10 = try #require(store.day("10"))
        let day4 = try #require(store.day("4"))
        func miss(_ day: Day, _ index: Int, lateBy: Double) throws -> Int? {
            let at = try #require(day.items[index].at.flatMap(TripTime.minutes))
            let o = PlanEngine.Options.live(from: index, now: Double(at) + lateBy)
            let slot = try #require(engine.simulate(day, o).first { $0.index == index })
            #expect(slot.hard && abs(slot.spare! + lateBy) < 1e-9, "item \(index) of day \(day.key)")
            return engine.firstMiss(day, o)?.slot.index
        }
        #expect(try miss(day10, 11, lateBy: 1.5) == nil)
        #expect(try miss(day10, 11, lateBy: 2.5) == 11)
        #expect(try miss(day4, 2, lateBy: 0.5) == nil)
        #expect(try miss(day4, 2, lateBy: 1.5) == 2)
        // exactly at the grace is still kept
        #expect(try miss(day10, 11, lateBy: 2) == nil)
        #expect(try miss(day4, 2, lateBy: 1) == nil)
    }

    @Test func aDepartureMoreThanAMinuteBehindTheClockIsLate() throws {
        // Day 10's Keihan (planned 8:30) can leave at 8:16.86 at the earliest
        func check(_ at: String) throws -> [PlanEngine.Finding] {
            let store = try TripStore.patched { trip in trip.setMove(day: "10", from: "8:30", at: at) }
            return PlanEngine(store: store).check(store.day("10")!).filter { $0.index == 4 }
        }
        let late = try check("8:15") // 1.86 min behind
        #expect(late.map(\.kind) == [.late])
        #expect(late.map(\.line) == ["  ! 8:15 Keihan st-fushimi-inari → st-tambabashi: free only at 8:17 (2 min late)"])
        #expect(try check("8:16").isEmpty) // 0.86 min behind
    }

    @Test func aLiveProjectionKeepsTheTailOfAWalk() throws {
        // from the last stop on a walk whose end is not a stop (Fushimi Inari's loop back to the
        // station; Okazaki on the way to Higashiyama): the rest of the walk still comes before the ride
        for (key, stop) in [("10", 3), ("8", 16)] {
            let day = try #require(store.day(key))
            let plan = engine.simulate(day)
            let tail = try #require(plan.first { $0.index == stop + 1 }).ready - plan.first { $0.index == stop }!.end
            #expect(tail > 10, "day \(key): tail \(tail)")
            let now = try #require(plan.first { $0.index == stop }).ready
            let live = engine.simulate(day, .live(from: stop, now: now))
            let ride = try #require(live.first { $0.index == stop + 1 })
            let at = try #require(live.first { $0.index == stop })
            #expect(abs(ride.ready - (now + Double(engine.dwell(day, stop, day.items[stop].stop!)) + tail)) < 1e-9, "day \(key)")
            #expect(abs(ride.ready - at.end - tail) < 1e-9, "day \(key)")
        }
    }

    @Test func theClockNeverGoesBackAtTheEndOfAWalk() throws {
        // a walk model shorter than the stretch already walked along its line (km 0.3 against
        // 0.47 km to the shrine): what is left of it is nothing, not a negative time
        let store = try TripStore.patched { trip in
            trip.editItem(day: "10", at: 2) { item in
                var leg = item["leg"] as! [String: Any]
                var walk = leg["walk"] as! [String: Any]
                walk["km"] = 0.3
                leg["walk"] = walk
                item["leg"] = leg
            }
        }
        let slots = PlanEngine(store: store).simulate(store.day("10")!)
        let shrine = try #require(slots.first { $0.index == 3 })
        let keihan = try #require(slots.first { $0.index == 4 })
        #expect(keihan.ready >= shrine.end, "ready \(keihan.ready), shrine done \(shrine.end)")
    }

    @Test func rulesExportedBeforeTheGraceGetTheValuesTheyWereCheckedWith() throws {
        let old = try JSONDecoder().decode(PlanRules.self, from: Data(#"{"dwell":{},"wait":{}}"#.utf8))
        #expect(old.grace == PlanRules.Grace(move: 1, stop: 2))
        #expect(old.tight == 3)
        let new = try JSONDecoder().decode(PlanRules.self, from: Data(#"{"dwell":{},"wait":{},"grace":{"move":4,"stop":5},"tight":6}"#.utf8))
        #expect(new.grace == PlanRules.Grace(move: 4, stop: 5))
        #expect(new.tight == 6)
        // and the shipped plan carries them
        #expect(store.trip.rules.grace == PlanRules.Grace(move: 1, stop: 2))
        #expect(store.trip.rules.tight == 3)
    }
}

extension Dictionary where Key == String, Value == Any {
    /// Edits item `index` of day `day` of a trip.json object.
    mutating func editItem(day: String, at index: Int, _ edit: (inout [String: Any]) -> Void) {
        for list in ["days", "altDays"] {
            guard var days = self[list] as? [[String: Any]],
                  let d = days.firstIndex(where: { $0["key"] as? String == day }),
                  var items = days[d]["items"] as? [[String: Any]], items.indices.contains(index)
            else { continue }
            edit(&items[index])
            days[d]["items"] = items
            self[list] = days
            return
        }
        Issue.record("no item \(index) on day \(day)")
    }

    /// Moves the departure planned at `from` on day `day` to `at`.
    mutating func setMove(day: String, from: String, at: String) {
        for list in ["days", "altDays"] {
            guard let days = self[list] as? [[String: Any]],
                  let d = days.first(where: { $0["key"] as? String == day }),
                  let items = d["items"] as? [[String: Any]],
                  let i = items.firstIndex(where: { $0["type"] as? String == "move" && $0["at"] as? String == from })
            else { continue }
            editItem(day: day, at: i) { $0["at"] = at }
            return
        }
        Issue.record("no departure at \(from) on day \(day)")
    }

    /// Sets the time of the stop at `place` on day `day` of a trip.json object.
    mutating func setStop(day: String, place: String, at: String) {
        for list in ["days", "altDays"] {
            guard var days = self[list] as? [[String: Any]],
                  let d = days.firstIndex(where: { $0["key"] as? String == day }),
                  var items = days[d]["items"] as? [[String: Any]],
                  let i = items.firstIndex(where: { $0["type"] as? String == "stop" && $0["place"] as? String == place })
            else { continue }
            items[i]["at"] = at
            days[d]["items"] = items
            self[list] = days
            return
        }
        Issue.record("no stop at \(place) on day \(day)")
    }
}

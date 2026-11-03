import Foundation
import Testing
@testable import TripKit

/// iOS reports a stay twice, on arrival and on leaving: one stay marks one stop, once, with or
/// without the journal.
@Suite struct StayMemoryTests {
    let store = Bundle_.store
    let t0 = TripTime.date("2027-10-18", "13:00")!
    let here = Coordinate(35.0, 139.0)

    func stay(_ arrival: Date, _ departure: Date? = nil) -> VisitRecord {
        VisitRecord(arrival: arrival, departure: departure, coordinate: here)
    }

    @Test func aStayMarksOnceWhenFirstReported() {
        var memory = StayMemory()
        let first = memory.report(stay(t0), placeID: "tsumugi", now: t0)
        #expect(first.marks)
        #expect(first.stay == StayMemory.Stay(arrival: t0, departure: nil, placeID: "tsumugi"))
        // the departure report: the same stay, completed, marks nothing
        let left = t0 + 3600
        let second = memory.report(stay(t0 + 30, left), placeID: "tsumugi", now: left)
        #expect(!second.marks)
        #expect(second.stay == StayMemory.Stay(arrival: t0, departure: left, placeID: "tsumugi"))
        #expect(memory.stays.count == 1)
    }

    @Test func aStayFirstReportedWithItsDepartureStillMarks() {
        var memory = StayMemory()
        let r = memory.report(stay(t0, t0 + 600), placeID: "tsumugi", now: t0 + 600)
        #expect(r.marks)
        #expect(r.stay.departure == t0 + 600)
    }

    @Test func aStayThatMatchedNothingMarksWhenItsSecondReportDoes() {
        var memory = StayMemory()
        #expect(!memory.report(stay(t0), placeID: nil, now: t0).marks)
        let r = memory.report(stay(t0, t0 + 600), placeID: "tsumugi", now: t0 + 600)
        #expect(r.marks)
        #expect(r.stay.placeID == "tsumugi")
        // and only once
        #expect(!memory.report(stay(t0, t0 + 600), placeID: "tsumugi", now: t0 + 700).marks)
    }

    @Test func theSameStayIsTheSameArrivalWithinTwoMinutes() {
        var memory = StayMemory()
        _ = memory.report(stay(t0), placeID: "a", now: t0)
        #expect(!memory.report(stay(t0 + 120), placeID: "a", now: t0 + 600).marks)
        #expect(!memory.report(stay(t0 - 120), placeID: "a", now: t0 + 600).marks)
        #expect(memory.report(stay(t0 + 121), placeID: "a", now: t0 + 600).marks)
        #expect(memory.stays.count == 2)
    }

    /// Day 1 drops the bags at the hotel and checks in later; day 8 rents the kimono and returns
    /// it, at the same shop. The departure report from the bag drop matches check-in (a stop not
    /// done comes first at the same spot); it must not mark it.
    @Test(arguments: [("1", "s:resol-akihabara:bags", "s:resol-akihabara:checkin"), ("8", "s:wargo-gion:rent", "s:wargo-gion:return")])
    func leavingTheFirstVisitOfARepeatedPlaceDoesNotMarkTheSecond(_ key: String, _ firstID: String, _ secondID: String) throws {
        let itinerary = Itinerary(store: store)
        let day = try #require(store.day(key))
        let first = try #require(day.index(of: firstID)), second = try #require(day.index(of: secondID))
        let place = try #require(day.items[first].stop.flatMap { store.place($0.place) })
        let at = place.coordinate
        var done = Set<Int>()
        var memory = StayMemory()
        func report(_ v: VisitRecord, now: Date) -> Int? {
            guard let i = itinerary.stop(at: at, in: day, from: max(0, first - 2), done: done) else { return nil }
            let r = memory.report(v, placeID: day.items[i].stop?.place, now: now)
            if r.marks { done.insert(i) }
            return r.marks ? i : nil
        }
        let arrival = try #require(TripTime.date(day.date, "11:00"))
        #expect(report(VisitRecord(arrival: arrival, departure: nil, coordinate: at), now: arrival) == first)
        // what the plan alone would mark on the departure report: the second visit
        #expect(itinerary.stop(at: at, in: day, from: max(0, first - 2), done: done) == second)
        let left = arrival + 20 * 60
        #expect(report(VisitRecord(arrival: arrival, departure: left, coordinate: at), now: left) == nil)
        #expect(!done.contains(second))
        // the second visit, a stay of its own hours later, marks it
        let back = arrival + 5 * 3600
        #expect(report(VisitRecord(arrival: back, departure: nil, coordinate: at), now: back) == second)
    }

    @Test func forgottenADayAfterItEnded() {
        var memory = StayMemory()
        _ = memory.report(stay(t0, t0 + 600), placeID: "a", now: t0 + 600)
        let later = t0 + 600 + StayMemory.keep
        _ = memory.report(stay(later), placeID: "b", now: later - 1)
        #expect(memory.stays.count == 2)
        _ = memory.report(stay(later + 3600), placeID: "c", now: later + 1)
        #expect(memory.stays.map(\.placeID) == ["b", "c"])
    }

    @Test func aStayStillOpenIsKeptThreeDays() {
        var memory = StayMemory()
        _ = memory.report(stay(t0), placeID: "hotel", now: t0)
        _ = memory.report(stay(t0 + StayMemory.keepOpen - 3600), placeID: "a", now: t0 + StayMemory.keepOpen - 1)
        #expect(memory.stays.first?.placeID == "hotel")
        // the hotel's departure report two nights later is still the same stay
        #expect(!memory.report(stay(t0, t0 + StayMemory.keepOpen - 60), placeID: "hotel", now: t0 + StayMemory.keepOpen - 60).marks)
        var open = StayMemory()
        _ = open.report(stay(t0), placeID: "hotel", now: t0)
        _ = open.report(stay(t0 + StayMemory.keepOpen - 60), placeID: "a", now: t0 + StayMemory.keepOpen)
        #expect(open.stays.map(\.placeID) == ["a"])
    }

    @Test func theLastDepartureFromAPlaceForTheWalkAfterIt() {
        var memory = StayMemory()
        let a1 = t0, a2 = t0 + 2 * 3600
        _ = memory.report(stay(a1, a1 + 1800), placeID: "tsumugi", now: a1 + 1800)
        _ = memory.report(stay(a2, a2 + 600), placeID: "tsumugi", now: a2 + 600)
        _ = memory.report(stay(a2 + 3600, a2 + 4000), placeID: "kanda", now: a2 + 4000)
        let until = a2 + 1200
        // the latest departure from that place, not after the arrival at the next stop
        #expect(memory.departure(from: "tsumugi", since: until - 3 * 3600, until: until) == a2 + 600)
        #expect(memory.departure(from: "tsumugi", since: until - 3 * 3600, until: a2 + 599) == a1 + 1800)
        // a stay arriving before `since` does not count
        #expect(memory.departure(from: "tsumugi", since: a1 + 1, until: a2 + 599) == nil)
        #expect(memory.departure(from: "manseibashi", since: until - 3 * 3600, until: until) == nil)
    }

    @Test func noCoordinatesAreKept() throws {
        var memory = StayMemory()
        _ = memory.report(stay(t0, t0 + 60), placeID: "a", now: t0 + 60)
        let json = try #require(String(data: JSONEncoder().encode(memory), encoding: .utf8))
        #expect(!json.contains("lat") && !json.contains("lng") && !json.contains("coordinate"))
        #expect(try JSONDecoder().decode(StayMemory.self, from: Data(json.utf8)) == memory)
    }
}

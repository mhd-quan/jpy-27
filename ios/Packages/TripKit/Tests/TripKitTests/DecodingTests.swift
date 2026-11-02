import Foundation
import Testing
@testable import TripKit

@Suite struct DecodingTests {
    @Test func tripAndGuideDecode() throws {
        let store = Bundle_.store
        #expect(store.trip.days.count == 12)
        #expect(store.trip.altDays.map(\.key) == ["kawaguchiko"])
        #expect(store.places.count > 200)
        #expect(store.trip.rides.count > 20)
        let guide = try #require(store.guide)
        #expect(guide.phrases.scenarios.count == 32)
        #expect(guide.budget.total > 600_000)
        #expect(guide.stays.count == 5)
    }

    @Test func bookingTimesParseOnce() throws {
        let guide = try #require(Bundle_.store.guide)
        let timed = guide.bookings.filter { $0.at != nil }
        #expect(!timed.isEmpty)
        for b in timed { #expect(b.date == ISO8601DateFormatter().date(from: b.at!)) }
        #expect(guide.bookings.filter { $0.at == nil }.allSatisfy { $0.date == nil })
        // 10:00 in Japan is 01:00 UTC
        let first = try #require(timed.first?.date)
        #expect(Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: first).hour == 1)
    }

    @Test func scheduleDecodes() throws {
        let slim = try TripStore(tripJSON: Bundle_.data("Shared/schedule.json"))
        #expect(slim.trip.days.count == 12)
        #expect(slim.guide == nil)
        let day2 = try #require(slim.day("2"))
        #expect(day2.items.count == Bundle_.store.day("2")!.items.count)
        #expect(!slim.trip.bookings.isEmpty)
        // the widget's clock agrees with the app's on every day
        for day in slim.trip.days {
            let a = Itinerary(store: slim).waypoints(day).map(\.setOff)
            let b = Itinerary(store: Bundle_.store).waypoints(Bundle_.store.day(day.key)!).map(\.setOff)
            #expect(a == b, "day \(day.key)")
        }
    }

    @Test func everyPlanPlaceResolves() {
        let store = Bundle_.store
        for day in store.trip.days + store.trip.altDays {
            for item in day.items {
                switch item {
                case .stop(let s): if let id = s.place { #expect(store.place(id) != nil, "\(day.key) \(id)") }
                case .move(let m):
                    #expect(store.place(m.leg.from) != nil)
                    #expect(store.place(m.leg.to) != nil)
                    #expect(store.line(m.leg.line) != nil)
                }
            }
        }
    }
}

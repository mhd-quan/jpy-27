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

    @Test func scheduleDecodes() throws {
        let slim = try TripStore(tripJSON: Bundle_.data("Shared/schedule.json"))
        #expect(slim.trip.days.count == 12)
        #expect(slim.guide == nil)
        let day2 = try #require(slim.day("2"))
        #expect(day2.items.count == Bundle_.store.day("2")!.items.count)
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

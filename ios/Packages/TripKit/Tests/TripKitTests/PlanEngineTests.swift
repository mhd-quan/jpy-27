import Foundation
import Testing
@testable import TripKit

@Suite struct PlanEngineTests {
    let store = Bundle_.store
    var engine: PlanEngine { PlanEngine(store: store) }

    /// The Swift clock prints exactly what scripts/check-plan.mjs prints.
    @Test func matchesCheckPlanScript() throws {
        var lines: [String] = []
        var problems = 0
        for day in store.trip.days + store.trip.altDays {
            let found = engine.check(day)
            problems += found.filter { $0.kind == .late }.count
            if !found.isEmpty { lines.append("Day \(day.key) — \(day.title)\n" + found.map(\.line).joined(separator: "\n")) }
        }
        lines.append(problems > 0 ? "\n\(problems) stops or departures planned earlier than they can be reached" : "\nevery timed stop can be reached")
        let expected = try Bundle_.fixture("check-plan.txt")
        #expect(lines.joined(separator: "\n") + "\n" == expected)
    }

    @Test func statedMinutes() {
        #expect(TripTime.statedMinutes("1 giờ 40") == 100)
        #expect(TripTime.statedMinutes("20–25, đổi tàu") == 20)
        #expect(TripTime.statedMinutes("3–4 giờ, tính cả dừng") == 240)
        #expect(TripTime.statedMinutes("118") == 118)
        #expect(TripTime.statedMinutes(nil) == nil)
    }
}

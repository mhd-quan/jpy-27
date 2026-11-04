import Foundation
import Testing
@testable import TripKit

/// A rehearsal's offset is whole minutes, and an offset within a minute of the real clock is no
/// rehearsal: "Chạy thử" with the picker at now changes nothing.
@Suite struct RehearsalClockTests {
    let day = 86_400.0

    @Test func withinAMinuteIsTheRealClock() {
        for raw in [-0.3, 0.3, 59.9, -59.9, 0, -0.0] {
            let o = RehearsalClock.offset(raw)
            #expect(o == 0, "\(raw)")
            #expect(o.sign == .plus, "\(raw) keeps a -0")
            #expect(!RehearsalClock.isRehearsing(raw), "\(raw)")
        }
    }

    @Test func otherwiseTheNearestWholeMinute() {
        #expect(RehearsalClock.offset(60) == 60)
        #expect(RehearsalClock.offset(-60) == -60)
        #expect(RehearsalClock.offset(89) == 60)
        #expect(RehearsalClock.offset(90) == 120)
        #expect(RehearsalClock.offset(-90) == -120)
        #expect(RehearsalClock.offset(3 * day + 17.4) == 3 * day)
        #expect(RehearsalClock.offset(-(330 * day) - 41) == -(330 * day) - 60)
        #expect(RehearsalClock.isRehearsing(60))
        #expect(RehearsalClock.isRehearsing(-3 * day))
    }

    @Test func notANumberIsTheRealClock() {
        for raw in [Double.nan, .infinity, -.infinity] {
            #expect(RehearsalClock.offset(raw) == 0, "\(raw)")
            #expect(!RehearsalClock.isRehearsing(raw), "\(raw)")
        }
    }

    @Test func thePickerAtNowStartsNothing() {
        let now = TripTime.date("2027-10-20", "12:00")!.addingTimeInterval(41)
        #expect(RehearsalClock.start(at: now.addingTimeInterval(-0.3), realNow: now, current: 0) == nil)
        #expect(RehearsalClock.start(at: now.addingTimeInterval(-59), realNow: now, current: 0) == nil)
        #expect(RehearsalClock.start(at: now.addingTimeInterval(59), realNow: now, current: 0) == nil)
    }

    @Test func aPickedTimeStartsWholeMinutes() {
        let real = TripTime.date("2026-11-04", "14:23")!.addingTimeInterval(41)
        let picked = TripTime.date("2027-10-18", "8:25")!
        let o = RehearsalClock.start(at: picked, realNow: real, current: 0)
        #expect(o == RehearsalClock.offset(picked.timeIntervalSince(real)))
        #expect(o.map { $0.truncatingRemainder(dividingBy: 60) } == 0)
        // the trip clock then reads the picked time, within half a minute
        #expect(o.map { abs(real.addingTimeInterval($0).timeIntervalSince(picked)) <= 30 } == true)
    }

    @Test func theStartButtonNeverEndsARehearsalNorRepeatsIt() {
        let real = TripTime.date("2027-10-20", "12:00")!
        let current = -2 * day
        // the picker at real now while rehearsing: not the end of it
        #expect(RehearsalClock.start(at: real, realNow: real, current: current) == nil)
        // the trip clock as it is: the rehearsal already running
        #expect(RehearsalClock.start(at: real.addingTimeInterval(current + 20), realNow: real, current: current) == nil)
        // another time: moves it
        #expect(RehearsalClock.start(at: real.addingTimeInterval(-day), realNow: real, current: current) == -day)
    }
}

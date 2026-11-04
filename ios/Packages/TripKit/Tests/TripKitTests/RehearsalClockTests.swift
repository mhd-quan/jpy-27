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
        // 347 days 18 h 1 min 19 s ahead, to the nearest minute
        #expect(o == 347 * day + 18 * 3600 + 60)
        // the trip clock then reads the picked time, within half a minute
        #expect(o.map { abs(real.addingTimeInterval($0).timeIntervalSince(picked)) <= 30 } == true)
    }

    /// A pick in the trip clock's current minute is "now": a wheel turned back onto it after the page
    /// stayed open a while starts nothing, nor moves a running rehearsal by a minute. The minute before
    /// is a pick.
    @Test func aPickInTheCurrentMinuteIsNow() {
        // not rehearsing: the real clock reads 12:00:50
        let real = TripTime.date("2027-10-20", "12:00")!.addingTimeInterval(50)
        #expect(RehearsalClock.start(at: TripTime.date("2027-10-20", "12:00")!, realNow: real, current: 0) == nil)
        #expect(RehearsalClock.start(at: TripTime.date("2027-10-20", "11:59")!, realNow: real, current: 0) == -120)
        // rehearsing two days back: the trip clock reads 10:00:50 on the 18th
        let current = -2 * day
        let at = TripTime.date("2027-10-20", "10:00")!.addingTimeInterval(50)
        #expect(RehearsalClock.start(at: TripTime.date("2027-10-18", "10:00")!, realNow: at, current: current) == nil)
        #expect(RehearsalClock.start(at: TripTime.date("2027-10-18", "10:00")!.addingTimeInterval(59.9), realNow: at, current: current) == nil)
        #expect(RehearsalClock.start(at: TripTime.date("2027-10-18", "9:59")!.addingTimeInterval(59), realNow: at, current: current) == current - 60)
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

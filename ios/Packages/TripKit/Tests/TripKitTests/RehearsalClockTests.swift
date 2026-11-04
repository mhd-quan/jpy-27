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

/// A ride followed in a rehearsal is the real ride of the same train, under the same id, with the same alarm
/// slot: what its end lets go of depends on the clock it was followed on and the one it ends on (R-153).
@Suite struct RideClockTests {
    let real = RideClock(rehearsal: false)
    let rehearsal = RideClock(rehearsal: true)

    @Test func onlyARealRideEndedOnTheRealClockCancelsTheAlarm() {
        #expect(real.endCancelsAlarm(rehearsingNow: false))
        #expect(!real.endCancelsAlarm(rehearsingNow: true), "a real ride ended as a rehearsal starts keeps its alarm")
        #expect(!rehearsal.endCancelsAlarm(rehearsingNow: true), "a rehearsal ride set none: the slot is the real ride's")
        #expect(!rehearsal.endCancelsAlarm(rehearsingNow: false), "ended by Về giờ thật")
    }

    @Test func aRideStaysEndedOnlyWhenItEndsOnTheClockItWasFollowedOn() {
        #expect(real.endIsKept(rehearsingNow: false, byClockMove: false), "the button, its arrival, left, long past")
        #expect(rehearsal.endIsKept(rehearsingNow: true, byClockMove: false), "the button in a rehearsal: not followed again in it")
        #expect(!real.endIsKept(rehearsingNow: true, byClockMove: false), "not on the clock it was followed on")
        #expect(!rehearsal.endIsKept(rehearsingNow: false, byClockMove: false), "not on the clock it was followed on")
    }

    /// Ended because the trip's clock moved, a ride is never kept, whichever clock it was followed on and the move
    /// went to: a real ride as a rehearsal starts, a rehearsal's on "Về giờ thật", a rehearsal's whose offset moved
    /// (rehearsing before and after: the clock check alone would keep it).
    @Test func aRideEndedByAClockMoveIsNeverKept() {
        for clock in [real, rehearsal] {
            for now in [false, true] {
                #expect(!clock.endIsKept(rehearsingNow: now, byClockMove: true), "\(clock) ended by a move to rehearsing \(now)")
            }
        }
    }
}

/// The rides ended, one set per clock (New-1): a real ride ended by hand stays ended through a rehearsal; a ride
/// ended because the clock changed is not kept; a rehearsal's end lasts as long as that rehearsal.
@Suite struct EndedRidesTests {
    let real = RideClock(rehearsal: false)
    let rehearsal = RideClock(rehearsal: true)
    let id = "d4-romancecar"

    @Test func aRealRideEndedByHandStaysEndedAfterARehearsal() {
        var ends = EndedRides()
        ends.insert(id, clock: real, rehearsingNow: false, byClockMove: false)
        #expect(ends.contains(id, rehearsingNow: false))
        ends.offsetChanged() // a rehearsal starts
        #expect(!ends.contains(id, rehearsingNow: true), "the rehearsal's ride is its own")
        ends.offsetChanged() // Về giờ thật
        #expect(ends.contains(id, rehearsingNow: false))
    }

    @Test func aRealRideEndedByARehearsalStartingIsNotKept() {
        var ends = EndedRides()
        ends.insert(id, clock: real, rehearsingNow: true, byClockMove: true)
        ends.offsetChanged()
        #expect(!ends.contains(id, rehearsingNow: true))
        ends.offsetChanged() // Về giờ thật
        #expect(!ends.contains(id, rehearsingNow: false), "it starts again in its window (3.4a.9)")
    }

    @Test func aRehearsalRideEndedByHandStaysEndedInThatRehearsal() {
        var ends = EndedRides()
        ends.insert(id, clock: rehearsal, rehearsingNow: true, byClockMove: false)
        #expect(ends.contains(id, rehearsingNow: true), "not followed again near its station")
        #expect(!ends.contains(id, rehearsingNow: false), "nothing of the real ride's")
    }

    @Test func aRehearsalRideEndedByVeGioThatIsNotKept() {
        var ends = EndedRides()
        ends.insert(id, clock: rehearsal, rehearsingNow: false, byClockMove: true)
        ends.offsetChanged()
        #expect(!ends.contains(id, rehearsingNow: false))
        #expect(!ends.contains(id, rehearsingNow: true))
    }

    @Test func movingTheRehearsalForgetsItsEndsOnly() {
        var ends = EndedRides()
        // ended by hand, then moved
        ends.insert("d4-kodama", clock: rehearsal, rehearsingNow: true, byClockMove: false)
        ends.insert("d3-shinkansen", clock: real, rehearsingNow: false, byClockMove: false)
        ends.offsetChanged()
        #expect(!ends.contains("d4-kodama", rehearsingNow: true))
        #expect(ends.contains("d3-shinkansen", rehearsingNow: false), "the real ends are not the rehearsal's to clear")
    }

    /// A rehearsal's ride ended by moving its offset (claimed while still rehearsing) is not kept in the moved
    /// rehearsal, whether the rehearsal's ends are forgotten before its end is recorded or after
    /// (`RideLiveService.clockMoved`): the order of the two is no rule.
    @Test func aRideEndedByMovingTheRehearsalIsNotKeptWhateverTheOrder() {
        var after = EndedRides()
        after.insert(id, clock: rehearsal, rehearsingNow: true, byClockMove: true)
        after.offsetChanged()
        #expect(!after.contains(id, rehearsingNow: true))

        var before = EndedRides()
        before.offsetChanged()
        before.insert(id, clock: rehearsal, rehearsingNow: true, byClockMove: true)
        #expect(!before.contains(id, rehearsingNow: true), "the moved rehearsal may follow it again")
    }
}

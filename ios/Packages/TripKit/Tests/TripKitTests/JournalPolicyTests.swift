import Foundation
import Testing
@testable import TripKit

/// The location journal records only during the trip and only when switched on; the background
/// watch runs only near the trip.
@Suite struct JournalPolicyTests {
    let store = Bundle_.store
    var policy: JournalPolicy { JournalPolicy(days: store.trip.days) }

    @Test func windowCoversTheTripDaysInJapanTime() {
        let w = policy.window!
        #expect(w.lowerBound == TripTime.midnight("2027-10-18")! - 6 * 3600)
        #expect(w.upperBound == TripTime.midnight("2027-10-30")! + 6 * 3600)
    }

    @Test func daysInAnyOrderGiveTheSameWindow() {
        #expect(JournalPolicy(days: store.trip.days.reversed()).window == policy.window)
        #expect(JournalPolicy(days: store.trip.days + store.trip.altDays).window == policy.window)
        #expect(JournalPolicy(days: store.trip.days, margin: 0).window
            == TripTime.midnight("2027-10-18")! ..< TripTime.midnight("2027-10-30")!)
    }

    @Test func recordedDuringTheTripWhenSwitchedOn() {
        let t = TripTime.date("2027-10-20", "12:00")!
        #expect(policy.mayRecord(realNow: t, tripNow: t, rehearsing: false, enabled: true))
    }

    @Test func nothingIsRecordedMonthsBefore() { let t = TripTime.midnight("2027-06-01")!; #expect(!policy.mayRecord(realNow: t, tripNow: t, rehearsing: false, enabled: true)) }
    @Test func nothingIsRecordedWhenSwitchedOff() { let t = TripTime.date("2027-10-20", "12:00")!; #expect(!policy.mayRecord(realNow: t, tripNow: t, rehearsing: false, enabled: false)) }

    @Test func recordingWindowIsHalfOpen() {
        let w = policy.window!
        func may(_ t: Date) -> Bool { policy.mayRecord(realNow: t, tripNow: t, rehearsing: false, enabled: true) }
        #expect(may(w.lowerBound))
        #expect(!may(w.lowerBound - 1))
        #expect(may(w.upperBound - 1))
        #expect(!may(w.upperBound))
    }

    @Test func backgroundWatchOnlyNearTheTrip() {
        func watch(_ t: Date, always: Bool = true) -> Bool { policy.wantsBackgroundWatch(at: t, journal: true, alwaysGranted: always) }
        #expect(!watch(TripTime.midnight("2027-10-16")!))
        #expect(watch(TripTime.date("2027-10-17", "12:00")!))
        #expect(!watch(TripTime.midnight("2027-10-31")!))
        #expect(!watch(TripTime.date("2027-10-20", "12:00")!, always: false))
        // the switch does not change it: reminders and fences re-plan on a significant move
        #expect(policy.wantsBackgroundWatch(at: TripTime.date("2027-10-20", "12:00")!, journal: false, alwaysGranted: true))
    }

    @Test func backgroundWatchEdges() {
        let w = policy.window!
        func watch(_ t: Date) -> Bool { policy.wantsBackgroundWatch(at: t, journal: true, alwaysGranted: true) }
        #expect(watch(w.lowerBound - 24 * 3600))
        #expect(!watch(w.lowerBound - 24 * 3600 - 1))
        #expect(watch(w.upperBound - 1))
        #expect(!watch(w.upperBound))
    }

    @Test func visitsWithTheJournalOrOnATripDay() {
        func visits(_ t: Date, journal: Bool, always: Bool = true) -> Bool { policy.wantsVisits(at: t, journal: journal, alwaysGranted: always) }
        let day = TripTime.date("2027-10-20", "12:00")!
        // a trip day: visits mark the stops, journal or not
        #expect(visits(day, journal: false))
        #expect(visits(day, journal: true))
        #expect(!visits(day, journal: true, always: false))
        // near the trip but not on a trip day: only for the journal
        let eve = TripTime.date("2027-10-17", "21:00")!
        #expect(visits(eve, journal: true))
        #expect(!visits(eve, journal: false))
        // the journal's visits start with the window, not with the watch a day before it
        let w = policy.window!
        #expect(policy.wantsBackgroundWatch(at: w.lowerBound - 1, journal: true, alwaysGranted: true))
        #expect(!visits(w.lowerBound - 1, journal: true))
        #expect(visits(w.lowerBound, journal: true))
        #expect(!visits(TripTime.date("2027-10-17", "12:00")!, journal: true))
        #expect(visits(w.upperBound - 1, journal: true))
        #expect(!visits(w.upperBound - 1, journal: false))
        // the trip days are midnight of the first to midnight after the last, Japan time
        #expect(visits(TripTime.midnight("2027-10-18")!, journal: false))
        #expect(!visits(TripTime.midnight("2027-10-18")! - 1, journal: false))
        #expect(visits(TripTime.midnight("2027-10-30")! - 1, journal: false))
        #expect(!visits(TripTime.midnight("2027-10-30")!, journal: false))
        // far from the trip: never, whatever the switch
        #expect(!visits(TripTime.midnight("2027-06-01")!, journal: true))
        #expect(!visits(TripTime.date("2027-10-30", "12:00")!, journal: true))
    }

    @Test func rehearsalClockDoesNotOpenRealWindow() {
        let real = TripTime.midnight("2026-11-03")!, shifted = TripTime.date("2027-10-20", "12:00")!
        #expect(!policy.mayRecord(realNow: real, tripNow: shifted, rehearsing: false, enabled: true))
        #expect(policy.mayRecord(realNow: real, tripNow: shifted, rehearsing: true, enabled: true))
    }

    @Test func rehearsalFollowsItsOwnClockAndTheSwitch() {
        let inTrip = TripTime.date("2027-10-20", "12:00")!, before = TripTime.midnight("2027-06-01")!
        // the trip clock, not the real one, while rehearsing
        #expect(!policy.mayRecord(realNow: inTrip, tripNow: before, rehearsing: true, enabled: true))
        #expect(!policy.mayRecord(realNow: inTrip, tripNow: inTrip, rehearsing: true, enabled: false))
    }

    @Test func noDaysNoJournal() {
        let none = JournalPolicy(days: [])
        let t = TripTime.date("2027-10-20", "12:00")!
        #expect(none.window == nil)
        #expect(!none.mayRecord(realNow: t, tripNow: t, rehearsing: false, enabled: true))
        #expect(!none.wantsBackgroundWatch(at: t, journal: true, alwaysGranted: true))
        #expect(!none.wantsVisits(at: t, journal: true, alwaysGranted: true))
    }
}

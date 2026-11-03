import Foundation
import Testing
@testable import TripKit

/// The alighting alarm's rule (`AlarmService`): one piece of work per ride at a time, the latest
/// request winning, a cancel sticking even while the work waits on a permission prompt.
@MainActor @Suite struct OneAtATimeTests {
    /// Stands in for the permission prompt: the work waits on it until the test opens it.
    @MainActor final class Gate {
        private var waiter: CheckedContinuation<Void, Never>?
        private var arrival: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { c in
                waiter = c
                arrival?.resume()
                arrival = nil
            }
        }

        /// Returns once the work is waiting at the gate.
        func reached() async {
            if waiter != nil { return }
            await withCheckedContinuation { arrival = $0 }
        }

        func open() {
            waiter?.resume()
            waiter = nil
        }
    }

    @MainActor final class Log {
        var done: [String] = []
        var current: [Bool] = []
    }

    @Test func asksMadeWhileWorkingCollapseIntoTheLatest() async {
        let serial = OneAtATime<String>()
        let log = Log(), gate = Gate()
        let first = Task {
            await serial.run("ride", "first") { r, _ in
                if r == "first" { await gate.wait() }
                log.done.append(r)
            }
        }
        await gate.reached()
        #expect(serial.isRunning("ride"))
        // the positions that arrive while the prompt is up: each returns at once
        await serial.run("ride", "second") { r, _ in log.done.append("unexpected \(r)") }
        await serial.run("ride", "third") { r, _ in log.done.append("unexpected \(r)") }
        #expect(log.done.isEmpty)
        gate.open()
        await first.value
        // the first, then only the latest of those that waited: two alarms set in turn, never side by side
        #expect(log.done == ["first", "third"])
        #expect(!serial.isRunning("ride"))
    }

    @Test func aCancelWhileWaitingSticks() async {
        let serial = OneAtATime<String>()
        let log = Log(), gate = Gate()
        let first = Task {
            await serial.run("ride", "first") { r, ticket in
                await gate.wait()
                log.current.append(serial.isCurrent(ticket))
                log.done.append(r)
            }
        }
        await gate.reached()
        await serial.run("ride", "second") { _, _ in }
        // the ride ends, or its alarm is turned off, while the prompt is up
        serial.cancel("ride")
        gate.open()
        await first.value
        // the work learns it was overtaken (and takes back what it set); what waited is dropped
        #expect(log.current == [false])
        #expect(log.done == ["first"])
    }

    @Test func aRequestAfterTheCancelStillRuns() async {
        let serial = OneAtATime<String>()
        let log = Log(), gate = Gate()
        let first = Task {
            await serial.run("ride", "first") { r, ticket in
                if r == "first" { await gate.wait() }
                log.current.append(serial.isCurrent(ticket))
                log.done.append(r)
            }
        }
        await gate.reached()
        serial.cancel("ride")
        await serial.run("ride", "again") { _, _ in }
        gate.open()
        await first.value
        #expect(log.done == ["first", "again"])
        #expect(log.current == [false, true])
    }

    @Test func aWeakerRequestDoesNotReplaceAStrongerOne() async {
        let serial = OneAtATime<String>()
        let log = Log(), gate = Gate()
        // the timetable never takes the place of the GPS's time for a ride being followed
        let gpsFirst: (String, String?) -> Bool = { running, waiting in true }
        let timetable: (String, String?) -> Bool = { running, waiting in running != "gps" && waiting != "gps" }
        let first = Task {
            await serial.run("ride", "gps", overrides: gpsFirst) { r, _ in
                if log.done.isEmpty { await gate.wait() }
                log.done.append(r)
            }
        }
        await gate.reached()
        await serial.run("ride", "timetable", overrides: timetable) { _, _ in }
        await serial.run("ride", "gps", overrides: gpsFirst) { _, _ in }
        await serial.run("ride", "timetable", overrides: timetable) { _, _ in }
        gate.open()
        await first.value
        #expect(log.done == ["gps", "gps"])
    }

    @Test func keysDoNotWaitForEachOther() async {
        let serial = OneAtATime<String>()
        let log = Log(), gate = Gate()
        let first = Task {
            await serial.run("a", "a") { r, _ in
                await gate.wait()
                log.done.append(r)
            }
        }
        await gate.reached()
        await serial.run("b", "b") { r, _ in log.done.append(r) }
        #expect(log.done == ["b"])
        gate.open()
        await first.value
        #expect(log.done == ["b", "a"])
    }
}

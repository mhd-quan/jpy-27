import Testing
@testable import TripKit

/// The Map tab's camera rule (`MapTab.read`): items crossing the reading line close together fly the
/// camera once, to the last of them, once the line has rested; a rest after each flies each time; and a
/// fly asked for by hand drops the one waiting. Time moves only through the injected sleep.
@MainActor @Suite struct DebouncerTests {
    typealias ManualSleep = CoalescerTests.ManualSleep
    typealias LateSleep = CoalescerTests.LateSleep

    @Test func crossingsWithin150msFlyOnce() async {
        let clock = ManualSleep()
        var fired: [Int] = []
        let d = Debouncer<Int>(delay: .milliseconds(150), sleep: clock.sleep) { fired.append($0) }
        for i in 1...8 {
            d.send(i)
            if i < 8 { await clock.advance(.milliseconds(40)) }
        }
        await clock.settle()
        // each send stopped the timer before it: one left, the last one's
        #expect(clock.waiting == 1)
        await clock.advance(.milliseconds(149))
        #expect(fired.isEmpty)
        await clock.advance(.milliseconds(1))
        #expect(fired == [8])
        await clock.advance(.seconds(10))
        #expect(fired == [8])
        #expect(clock.waiting == 0)
    }

    @Test func restAfterEachCrossingFliesEachTime() async {
        let clock = ManualSleep()
        var fired: [Int] = []
        let d = Debouncer<Int>(delay: .milliseconds(150), sleep: clock.sleep) { fired.append($0) }
        d.send(1)
        await clock.advance(.milliseconds(149))
        #expect(fired.isEmpty)
        await clock.advance(.milliseconds(51))
        #expect(fired == [1])
        d.send(2)
        await clock.advance(.milliseconds(200))
        #expect(fired == [1, 2])
        d.send(3)
        await clock.advance(.milliseconds(200))
        #expect(fired == [1, 2, 3])
    }

    @Test func cancelDropsPendingFly() async {
        let clock = ManualSleep()
        var fired: [Int] = []
        let d = Debouncer<Int>(delay: .milliseconds(150), sleep: clock.sleep) { fired.append($0) }
        d.send(5)
        await clock.advance(.milliseconds(100))
        d.cancel()
        await clock.advance(.seconds(1))
        #expect(fired.isEmpty)
        #expect(clock.waiting == 0)
        // still works after a cancel, from the next send's own time
        d.send(6)
        await clock.advance(.milliseconds(149))
        #expect(fired.isEmpty)
        await clock.advance(.milliseconds(1))
        #expect(fired == [6])
    }

    @Test func aStoppedSleepThatWakesAnywayFiresNothing() async {
        let late = LateSleep()
        var fired: [Int] = []
        let d = Debouncer<Int>(delay: .milliseconds(150), sleep: late.sleep) { fired.append($0) }
        d.send(1)
        await CoalescerTests.settle()
        d.send(2)
        await CoalescerTests.settle()
        // the first sleep ignored its stop: both are still asleep
        #expect(late.waiting == 2)
        // both return as if neither had been stopped (`Task.sleep` does that when its time had come)
        late.wakeAll()
        await CoalescerTests.settle()
        #expect(fired == [2])
    }

    @Test func aBoolFiresOnlyItsLastValue() async {
        let clock = ManualSleep()
        var fired: [Bool] = []
        let d = Debouncer<Bool>(delay: .seconds(2), sleep: clock.sleep) { fired.append($0) }
        d.send(true)
        await clock.advance(.milliseconds(500))
        d.send(false)
        await clock.advance(.milliseconds(500))
        d.send(true)
        await clock.advance(.seconds(2))
        #expect(fired == [true])
        // no "only when different" here: the same value again fires again (a caller that wants it
        // compares in its `fire`)
        d.send(false)
        await clock.advance(.seconds(1))
        d.send(true)
        await clock.advance(.seconds(2))
        #expect(fired == [true, true])
    }

    @Test func aDebouncerLetGoFiresNothing() async {
        let clock = ManualSleep()
        var fired: [Int] = []
        var d: Debouncer<Int>? = Debouncer<Int>(delay: .milliseconds(150), sleep: clock.sleep) { fired.append($0) }
        d?.send(1)
        await clock.settle()
        weak let held = d
        d = nil
        await clock.advance(.seconds(1))
        #expect(fired.isEmpty)
        #expect(held == nil)
    }
}

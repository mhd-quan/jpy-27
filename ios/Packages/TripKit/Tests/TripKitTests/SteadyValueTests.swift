import Testing
@testable import TripKit

/// The network's stable "online" (`NetworkStatus.online` in the app): the first report at once, then a change only
/// once it has held 2 s, and only when it differs from what was published last. A flap shorter than that publishes
/// nothing, so a page's live map is never torn down and built again by it. Time moves only through the injected sleep.
@MainActor @Suite struct SteadyValueTests {
    typealias ManualSleep = CoalescerTests.ManualSleep
    typealias LateSleep = CoalescerTests.LateSleep

    @Test func firstReportIsPublishedAtOnce() async {
        let clock = ManualSleep()
        var published: [Bool] = []
        let steady = SteadyValue<Bool>(delay: .seconds(2), sleep: clock.sleep) { published.append($0) }
        // nothing was known before it: an offline launch is offline from the first report, not 2 s later
        steady.report(false)
        #expect(published == [false])
        #expect(clock.waiting == 0)
        await clock.advance(.seconds(10))
        #expect(published == [false])
    }

    @Test func aFlapShorterThanTheDelayPublishesNothing() async {
        let clock = ManualSleep()
        var published: [Bool] = []
        let steady = SteadyValue<Bool>(delay: .seconds(2), sleep: clock.sleep) { published.append($0) }
        steady.report(true)
        steady.report(false)
        await clock.advance(.milliseconds(1500))
        steady.report(true)
        await clock.advance(.seconds(10))
        // back where it was published: nothing to say
        #expect(published == [true])
        // ten flips in 20 s, never 2 s apart, publish nothing either
        for i in 0..<10 {
            steady.report(i.isMultiple(of: 2) ? false : true)
            await clock.advance(.milliseconds(1900))
        }
        await clock.advance(.seconds(10))
        #expect(published == [true])
    }

    @Test func aChangeThatHoldsIsPublishedOnceAfterTheDelay() async {
        let clock = ManualSleep()
        var published: [Bool] = []
        let steady = SteadyValue<Bool>(delay: .seconds(2), sleep: clock.sleep) { published.append($0) }
        steady.report(true)
        steady.report(false)
        await clock.advance(.milliseconds(1999))
        #expect(published == [true])
        await clock.advance(.milliseconds(1))
        #expect(published == [true, false])
        await clock.advance(.seconds(10))
        #expect(published == [true, false])
        // and back, the same way
        steady.report(true)
        await clock.advance(.seconds(2))
        #expect(published == [true, false, true])
    }

    @Test func aRepeatedReportDoesNotRestartTheWait() async {
        let clock = ManualSleep()
        var published: [Bool] = []
        let steady = SteadyValue<Bool>(delay: .seconds(2), sleep: clock.sleep) { published.append($0) }
        steady.report(true)
        steady.report(false)
        await clock.advance(.milliseconds(1500))
        // the path monitor says the same again (another interface, the same status): the change still holds
        // from when it began
        steady.report(false)
        await clock.advance(.milliseconds(500))
        #expect(published == [true, false])
        // a repeat of the published value with nothing waiting starts nothing
        steady.report(false)
        await clock.settle()
        #expect(clock.waiting == 0)
        await clock.advance(.seconds(10))
        #expect(published == [true, false])
    }

    @Test func onlyAValueThatDiffersFromThePublishedOneIsPublished() async {
        let clock = ManualSleep()
        var published: [Int] = []
        let steady = SteadyValue<Int>(delay: .seconds(2), sleep: clock.sleep) { published.append($0) }
        steady.report(1)
        steady.report(2)
        await clock.advance(.seconds(1))
        steady.report(1)
        await clock.advance(.seconds(3))
        // the wait ended on 1, which is what was published: compared with the published value, not the
        // last one reported
        #expect(published == [1])
        steady.report(3)
        await clock.advance(.seconds(1))
        steady.report(2)
        await clock.advance(.seconds(2))
        #expect(published == [1, 2])
    }

    @Test func aStaleWakeOfASupersededWaitPublishesNothing() async {
        let late = LateSleep()
        var published: [Bool] = []
        let steady = SteadyValue<Bool>(delay: .seconds(2), sleep: late.sleep) { published.append($0) }
        steady.report(true)
        steady.report(false)
        await CoalescerTests.settle()
        steady.report(true)
        await CoalescerTests.settle()
        #expect(late.waiting == 2)
        // the wait for `false`, stopped by the later report, wakes anyway: `false` never held
        late.wake(0)
        await CoalescerTests.settle()
        #expect(published == [true])
        // the wait for `true` ends: what was published already
        late.wake(0)
        await CoalescerTests.settle()
        #expect(published == [true])
    }

    @Test func aSteadyValueLetGoPublishesNothing() async {
        let clock = ManualSleep()
        var published: [Bool] = []
        var steady: SteadyValue<Bool>? = SteadyValue<Bool>(delay: .seconds(2), sleep: clock.sleep) { published.append($0) }
        steady?.report(true)
        steady?.report(false)
        await clock.settle()
        weak let held = steady
        steady = nil
        await clock.advance(.seconds(10))
        #expect(published == [true])
        #expect(held == nil)
    }
}

import Testing
@testable import TripKit

/// The reschedule's rule (`AppModel.requestReschedule`): requests close together are served by one
/// run, a sooner request brings the run forward and a later one never puts it off, one run at a time,
/// and `flush` returns only once nothing is left to run.
@MainActor @Suite struct CoalescerTests {
    /// A clock the test moves. A sleep waits until `now` plus its delay, as of when it began; one
    /// whose time has come returns at once; a cancelled one throws, as `Task.sleep` does.
    @MainActor final class ManualSleep {
        private(set) var now: Duration = .zero
        private var sleepers: [(id: Int, deadline: Duration, continuation: CheckedContinuation<Void, any Error>)] = []
        private var nextID = 0

        /// sleeps waiting for their time
        var waiting: Int { sleepers.count }

        func sleep(_ delay: Duration) async throws {
            let deadline = now + delay
            guard deadline > now else { return try Task.checkCancellation() }
            let id = nextID
            nextID += 1
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in
                    if Task.isCancelled {
                        c.resume(throwing: CancellationError())
                    } else {
                        sleepers.append((id, deadline, c))
                    }
                }
            } onCancel: {
                Task { @MainActor in self.cancel(id) }
            }
        }

        private func cancel(_ id: Int) {
            guard let i = sleepers.firstIndex(where: { $0.id == id }) else { return }
            sleepers.remove(at: i).continuation.resume(throwing: CancellationError())
        }

        /// Moves the clock on by `delay`, one deadline at a time, earliest first, and lets what each
        /// wakes run before the next. The timers asked for so far are asleep before the clock moves.
        func advance(_ delay: Duration) async {
            await settle()
            let end = now + delay
            while let next = sleepers.map(\.deadline).min(), next <= end {
                now = next
                let due = sleepers.filter { $0.deadline <= next }
                sleepers.removeAll { $0.deadline <= next }
                for s in due { s.continuation.resume() }
                await settle()
            }
            now = end
            await settle()
        }

        func settle() async { await CoalescerTests.settle() }
    }

    /// Lets every task queued on the main actor run until it waits on something again (a sleep, a
    /// gate): all of this runs there, so a few turns more than the longest chain is enough.
    static func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    /// A sleep that ends only when the test says, stopped or not: `Task.sleep` returns normally when
    /// its time had come just before the cancel, its wake already queued on the main actor.
    @MainActor final class LateSleep {
        private var sleepers: [CheckedContinuation<Void, Never>] = []

        var waiting: Int { sleepers.count }

        func sleep(_ delay: Duration) async {
            await withCheckedContinuation { sleepers.append($0) }
        }

        func wakeAll() {
            let woken = sleepers
            sleepers = []
            for s in woken { s.resume() }
        }
    }

    /// The first sleep waits until the test makes it fail, with the error the test gives; the rest
    /// are `clock`'s.
    @MainActor final class FailsWhenTold {
        /// an error of the sleep's own, not a cancellation
        struct Broken: Error {}
        private let clock: ManualSleep
        private var first: CheckedContinuation<Void, any Error>?
        private var used = false

        init(_ clock: ManualSleep) { self.clock = clock }

        func sleep(_ delay: Duration) async throws {
            guard used else {
                used = true
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, any Error>) in first = c }
                return
            }
            try await clock.sleep(delay)
        }

        func fail(with error: any Error) {
            first?.resume(throwing: error)
            first = nil
        }
    }

    /// Runs `body` and gives the main actor up to 200 turns to finish it: a `flush` that never
    /// returns fails the test instead of hanging the run.
    func finishes(_ body: @escaping @MainActor () async -> Void) async -> Bool {
        var done = false
        Task {
            await body()
            done = true
        }
        var turns = 0
        while !done, turns < 200 {
            await Task.yield()
            turns += 1
        }
        return done
    }

    @Test func burstOfRequestsRunsOnce() async {
        let clock = ManualSleep()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) { n += 1 }
        c.request(after: .milliseconds(300)); c.request(after: .milliseconds(300)); c.request(after: .milliseconds(300))
        await clock.settle()
        // one timer for the three
        #expect(clock.waiting == 1)
        await clock.advance(.milliseconds(299))
        #expect(n == 0)
        await clock.advance(.milliseconds(1))
        #expect(n == 1)
        await clock.advance(.seconds(10))
        #expect(n == 1)
        #expect(c.runs == 1)
        // a later request is served by a run of its own
        c.request(after: .milliseconds(300))
        await clock.advance(.milliseconds(300))
        #expect(n == 2)
        #expect(c.runs == 2)
    }

    @Test func flushRunsNowAndReturnsWhenDone() async {
        let clock = ManualSleep()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) { n += 1 }
        c.request(after: .seconds(10))
        #expect(await finishes { await c.flush() })
        // before the clock moved at all
        #expect(clock.now == .zero)
        #expect(n == 1)
        #expect(c.runs == 1)
        // the timer the flush took over does not run it again
        await clock.advance(.seconds(20))
        #expect(n == 1)
        #expect(clock.waiting == 0)
    }

    @Test func requestDuringRunRunsExactlyOnceMore() async {
        let clock = ManualSleep()
        let gate = OneAtATimeTests.Gate()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) {
            n += 1
            if n == 1 { await gate.wait() }
        }
        c.request(after: .zero)
        await gate.reached()
        // two requests while the first run waits, and their time comes before it is done
        c.request(after: .milliseconds(300)); c.request(after: .milliseconds(300))
        await clock.advance(.milliseconds(300))
        #expect(n == 1)
        gate.open()
        await clock.settle()
        #expect(n == 2)
        await clock.advance(.seconds(10))
        #expect(n == 2)
        #expect(c.runs == 2)
    }

    @Test func flushWaitsForInFlightRun() async {
        let clock = ManualSleep()
        let gate = OneAtATimeTests.Gate()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) {
            n += 1
            if n == 1 { await gate.wait() }
        }
        c.request(after: .milliseconds(300))
        await clock.advance(.milliseconds(300))
        await gate.reached()
        var flushed = false
        let flushing = Task {
            await c.flush()
            flushed = true
        }
        await clock.settle()
        #expect(!flushed)
        #expect(n == 1)
        gate.open()
        #expect(await finishes { await flushing.value })
        // the run under way began before the flush was asked for: one more after it
        #expect(flushed)
        #expect(n == 2)
    }

    @Test func earlierRequestPullsTheRunForward() async {
        let clock = ManualSleep()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) { n += 1 }
        c.request(after: .seconds(2))
        c.request(after: .zero)
        await clock.advance(.zero)
        #expect(n == 1)
        #expect(clock.now == .zero)
        // the two-second timer was served by that run
        await clock.advance(.seconds(5))
        #expect(n == 1)
        #expect(clock.waiting == 0)
    }

    @Test func aLaterRequestNeverPostponesTheRun() async {
        let clock = ManualSleep()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) { n += 1 }
        c.request(after: .milliseconds(300))
        await clock.advance(.milliseconds(200))
        // due at 500 ms and at 2.2 s: the run stays at 300 ms
        c.request(after: .milliseconds(300))
        c.request(after: .seconds(2))
        // due at 300 ms too: still one run
        c.request(after: .milliseconds(100))
        await clock.advance(.milliseconds(99))
        #expect(n == 0)
        await clock.advance(.milliseconds(1))
        #expect(n == 1)
        await clock.advance(.seconds(5))
        #expect(n == 1)
    }

    @Test func aShorterRequestDueLaterDoesNotPostponeTheRun() async {
        let clock = ManualSleep()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) { n += 1 }
        c.request(after: .milliseconds(300))
        await clock.advance(.milliseconds(200))
        // a shorter delay, but due at 350 ms: the run stays at 300 ms
        c.request(after: .milliseconds(150))
        await clock.advance(.milliseconds(100))
        #expect(n == 1)
        await clock.advance(.seconds(5))
        #expect(n == 1)
    }

    @Test func aStoppedTimerThatWakesAnywayRunsNothing() async {
        let late = LateSleep()
        var n = 0
        let c = Coalescer(sleep: late.sleep) { n += 1 }
        c.request(after: .seconds(10))
        await Self.settle()
        #expect(late.waiting == 1)
        #expect(await finishes { await c.flush() })
        #expect(n == 1)
        // its time had come as the flush stopped it: the sleep returns as if it had not been stopped
        late.wakeAll()
        await Self.settle()
        #expect(n == 1)
        #expect(c.isIdle)
    }

    @Test func aSleepThatFailsLeavesNothingWaiting() async {
        let clock = ManualSleep()
        let failing = FailsWhenTold(clock)
        var n = 0
        let c = Coalescer(sleep: failing.sleep) { n += 1 }
        c.request(after: .milliseconds(300))
        await clock.settle()
        failing.fail(with: FailsWhenTold.Broken())
        await clock.settle()
        #expect(c.isIdle)
        #expect(n == 0)
        // the next request is not taken for one already waiting
        c.request(after: .milliseconds(300))
        await clock.advance(.milliseconds(300))
        #expect(n == 1)
    }

    @Test func aSleepThatFailsLateTakesOnlyItsOwnTimerAway() async {
        let clock = ManualSleep()
        let failing = FailsWhenTold(clock)
        var n = 0
        let c = Coalescer(sleep: failing.sleep) { n += 1 }
        c.request(after: .seconds(10))
        // a newer, shorter request: a timer of its own, on the clock
        c.request(after: .milliseconds(300))
        await clock.settle()
        #expect(clock.waiting == 1)
        // the first sleep ends now, late, with a stop's error
        failing.fail(with: CancellationError())
        await clock.settle()
        // the newer timer still waits
        #expect(!c.isIdle)
        #expect(n == 0)
        await clock.advance(.milliseconds(300))
        #expect(n == 1)
        #expect(c.isIdle)
    }

    @Test func flushRunsWhatIsAskedWhileItRuns() async {
        let clock = ManualSleep()
        let gate = OneAtATimeTests.Gate()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) {
            n += 1
            if n == 1 { await gate.wait() }
        }
        var flushed = false
        let flushing = Task {
            await c.flush()
            flushed = true
        }
        await gate.reached()
        // asked for while the flush's own run goes on: run before the flush returns, not at its time
        c.request(after: .seconds(10))
        gate.open()
        #expect(await finishes { await flushing.value })
        #expect(flushed)
        #expect(n == 2)
        #expect(clock.now == .zero)
        #expect(c.isIdle)
        await clock.advance(.seconds(20))
        #expect(n == 2)
    }

    @Test func idleOnlyWhenNothingWaitsOrRuns() async {
        let clock = ManualSleep()
        let gate = OneAtATimeTests.Gate()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) {
            n += 1
            await gate.wait()
        }
        #expect(c.isIdle)
        c.request(after: .milliseconds(300))
        // a timer waits
        #expect(!c.isIdle)
        await clock.advance(.milliseconds(300))
        await gate.reached()
        // a run goes on, and counts from when it began
        #expect(!c.isIdle)
        #expect(c.runs == 1)
        gate.open()
        await clock.settle()
        #expect(n == 1)
        #expect(c.isIdle)
    }
}

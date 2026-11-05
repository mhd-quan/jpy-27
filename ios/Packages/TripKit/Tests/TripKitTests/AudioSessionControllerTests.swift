import Dispatch
import Foundation
import Synchronization
import Testing
@testable import TripKit

/// The session's calls run off the caller's thread, one event at a time, in the order the events were
/// handed in, a failed deactivation tried once more, the Speaker's session released after a beat
/// (`AudioSessionController`), against a session that records every call.
@MainActor @Suite struct AudioSessionControllerTests {
    typealias Call = AudioSessionOwners.Call
    static let speaker = AudioSessionOwnersTests.speaker
    static let listener = AudioSessionOwnersTests.listener
    static let fresh = AudioSessionOwnersTests.fresh

    // MARK: The test's session, sleep and timers

    /// Holds the session's queue at one point until the test opens it, and tells the test once the
    /// queue has got there.
    final class Gate: Sendable {
        private let opened = DispatchSemaphore(value: 0)
        private let state = Mutex<(entered: Bool, waiter: CheckedContinuation<Void, Never>?)>((false, nil))

        /// On the session's queue: blocks it until `open`.
        func wait() {
            let waiter = state.withLock { s in
                s.entered = true
                defer { s.waiter = nil }
                return s.waiter
            }
            waiter?.resume()
            opened.wait()
        }

        /// Returns once the queue is held at the gate, or once the test is cancelled (its time limit
        /// ran out: the queue never got there).
        func reached() async {
            await withTaskCancellationHandler {
                await withCheckedContinuation { c in
                    let now = state.withLock { s -> Bool in
                        if s.entered || Task.isCancelled { return true }
                        s.waiter = c
                        return false
                    }
                    if now { c.resume() }
                }
            } onCancel: {
                let waiter = state.withLock { s in
                    defer { s.waiter = nil }
                    return s.waiter
                }
                waiter?.resume()
            }
        }

        func open() { opened.signal() }
    }

    /// The session as the tests see it. Every call is recorded, with whether it ran on the
    /// controller's queue; `setCategory` changes what `current()` reads; calls fail or hold as a test
    /// sets them to.
    final class FakeSession: AudioSessionPort {
        struct Busy: Error {}
        struct Refused: Error {}
        private struct Inside {
            var setup: AudioSetup
            var log: [Call] = []
            /// calls (and reads, as nil) made anywhere but on the controller's queue
            var offQueue: [Call?] = []
            /// deactivations still to fail with `isBusy`
            var busy: Int
            var refusing: [Call]
        }

        private static let onQueue = DispatchSpecificKey<Bool>()
        /// the controller's queue, which the session can tell it runs on
        let queue = DispatchQueue(label: "test.audio-session")
        private let inside: Mutex<Inside>
        /// holds each activation while set
        private let holdActivate: Gate?

        init(busy: Int = 0, refusing: [Call] = [], holdActivate: Gate? = nil) {
            queue.setSpecific(key: Self.onQueue, value: true)
            inside = Mutex(Inside(setup: AudioSessionOwnersTests.fresh, busy: busy, refusing: refusing))
            self.holdActivate = holdActivate
        }

        var log: [Call] { inside.withLock { $0.log } }
        var offQueue: [Call?] { inside.withLock { $0.offQueue } }

        private var isOnQueue: Bool { DispatchQueue.getSpecific(key: Self.onQueue) == true }

        private func record(_ call: Call) throws {
            let onQueue = isOnQueue
            try inside.withLock { s throws(Refused) in
                s.log.append(call)
                if !onQueue { s.offQueue.append(call) }
                if s.refusing.contains(call) { throw Refused() }
            }
        }

        func current() -> AudioSetup {
            let onQueue = isOnQueue
            return inside.withLock { s in
                if !onQueue { s.offQueue.append(nil) }
                return s.setup
            }
        }

        func setCategory(_ setup: AudioSetup) throws {
            try record(.setCategory(setup))
            inside.withLock { $0.setup = setup }
        }

        func activate() throws {
            holdActivate?.wait()
            try record(.activate)
        }

        func deactivate() throws {
            try record(.deactivate)
            try inside.withLock { s throws(Busy) in
                guard s.busy > 0 else { return }
                s.busy -= 1
                throw Busy()
            }
        }

        func isBusy(_ error: any Error) -> Bool { error is Busy }
    }

    /// The retry's wait: each delay asked for, held at a gate when the test gives one.
    final class Sleeps: Sendable {
        private let asked = Mutex<[Duration]>([])
        private let hold: Gate?

        init(hold: Gate? = nil) { self.hold = hold }

        var delays: [Duration] { asked.withLock { $0 } }

        func sleep(_ delay: Duration) {
            asked.withLock { $0.append(delay) }
            hold?.wait()
        }
    }

    /// The release's timers: each kept with its delay until the test fires it.
    final class Timers: Sendable {
        private let pending = Mutex<[(delay: Duration, work: @Sendable () -> Void)]>([])

        var delays: [Duration] { pending.withLock { $0.map(\.delay) } }

        func after(_ delay: Duration, _ work: @escaping @Sendable () -> Void) {
            pending.withLock { $0.append((delay, work)) }
        }

        func fire(_ index: Int) {
            let work = pending.withLock { $0.indices.contains(index) ? $0[index].work : nil }
            guard let work else {
                Issue.record("no timer \(index) to fire")
                return
            }
            work()
        }
    }

    private func controller(_ session: FakeSession, sleeps: Sleeps = Sleeps(), timers: Timers = Timers()) -> AudioSessionController {
        AudioSessionController(port: session, speaker: Self.speaker, listener: Self.listener, queue: session.queue,
                               sleep: { sleeps.sleep($0) }, after: { timers.after($0, $1) })
    }

    /// Returns once everything queued so far has run.
    private func drained(_ session: FakeSession) async {
        await withCheckedContinuation { c in session.queue.async { c.resume() } }
    }

    /// A line said: returns its completion's verdict, and the calls made by the time it ran.
    private func say(_ controller: AudioSessionController, _ session: FakeSession) async -> (ok: Bool, log: [Call]) {
        await withCheckedContinuation { c in
            controller.say { ok in c.resume(returning: (ok, session.log)) }
        }
    }

    // MARK: Order and threads

    /// Rows 1, 4, 5, 6 and 8 in turn: each event's calls, in order, all on the session's queue, none
    /// on the caller's; a line's completion comes after its calls.
    @Test func eachEventMakesItsCallsOnTheSessionsQueue() async {
        let session = FakeSession()
        let timers = Timers()
        let audio = controller(session, timers: timers)
        let said = await say(audio, session)
        #expect(said.ok)
        #expect(said.log == [.setCategory(Self.speaker), .activate])
        audio.ended()
        await drained(session)
        #expect(timers.delays == [.milliseconds(500)])
        timers.fire(0)
        await drained(session)
        #expect(session.log.last == .deactivate)
        #expect(audio.state.holder == .nobody)
        #expect(await audio.listen(1))
        #expect(audio.state.holder == .listener(1))
        audio.listenEnded(1)
        await drained(session)
        #expect(session.log == [
            .setCategory(Self.speaker), .activate,
            .deactivate,
            .setCategory(Self.listener), .activate,
            .deactivate, .setCategory(Self.speaker),
        ])
        #expect(session.offQueue.isEmpty)
        #expect(audio.failedDeactivations == 0)
    }

    /// Row 3: a line while Nghe listens makes no call, and is spoken (its completion says so).
    @Test func aLineWhileListeningMakesNoCall() async {
        let session = FakeSession()
        let audio = controller(session)
        #expect(await audio.listen(1))
        let said = await say(audio, session)
        #expect(said.ok)
        #expect(said.log == [.setCategory(Self.listener), .activate])
    }

    /// Nothing said: an end times no release.
    @Test func anEndWithNothingSaidTimesNothing() async {
        let session = FakeSession()
        let timers = Timers()
        let audio = controller(session, timers: timers)
        audio.ended()
        await drained(session)
        #expect(timers.delays.isEmpty)
    }

    // MARK: The release

    /// Holds the session's queue until `gate` opens, as a long call would: what is handed in meanwhile
    /// waits behind it, in the order handed in.
    private func hold(_ session: FakeSession, at gate: Gate) async {
        session.queue.async { gate.wait() }
        await gate.reached()
    }

    /// Rows 2 and 5b: a line handed in before the release fires voids it, though neither has run yet:
    /// the session stays active.
    @Test func aLineHandedInBeforeTheReleaseFiresVoidsIt() async {
        let session = FakeSession()
        let timers = Timers()
        let audio = controller(session, timers: timers)
        _ = await say(audio, session)
        audio.ended()
        await drained(session)
        let gate = Gate()
        await hold(session, at: gate)
        let said = await withCheckedContinuation { c in
            audio.say { ok in c.resume(returning: ok) }
            timers.fire(0)
            gate.open()
        }
        #expect(said)
        await drained(session)
        #expect(session.log == [.setCategory(Self.speaker), .activate, .activate])
        #expect(audio.state.holder == .speaker)
    }

    /// A release that fired before a line is handed in runs first, though neither has run yet: the line
    /// activates again after the deactivation.
    @Test func aReleaseThatFiredFirstRunsFirst() async {
        let session = FakeSession()
        let timers = Timers()
        let audio = controller(session, timers: timers)
        _ = await say(audio, session)
        audio.ended()
        await drained(session)
        let gate = Gate()
        await hold(session, at: gate)
        let said = await withCheckedContinuation { c in
            timers.fire(0)
            audio.say { ok in c.resume(returning: ok) }
            gate.open()
        }
        #expect(said)
        #expect(session.log == [.setCategory(Self.speaker), .activate, .deactivate, .activate])
        #expect(audio.state.holder == .speaker)
    }

    // MARK: Failures

    /// Row 12: a deactivation refused as busy is tried once more, 150 ms later; then the setup from
    /// before listening is put back.
    @Test func aBusyDeactivationIsTriedOnceMoreAfter150ms() async {
        let session = FakeSession(busy: 1)
        let sleeps = Sleeps()
        let audio = controller(session, sleeps: sleeps)
        #expect(await audio.listen(1))
        audio.listenEnded(1)
        await drained(session)
        #expect(session.log == [.setCategory(Self.listener), .activate, .deactivate, .deactivate, .setCategory(Self.fresh)])
        #expect(sleeps.delays == [.milliseconds(150)])
        #expect(audio.failedDeactivations == 0)
    }

    /// Busy twice: given up after the second try, and the setup from before is not put back onto the
    /// session still active (R-232).
    @Test func aDeactivationBusyTwiceGivesUpAndPutsNothingBack() async {
        let session = FakeSession(busy: 2)
        let sleeps = Sleeps()
        let audio = controller(session, sleeps: sleeps)
        #expect(await audio.listen(1))
        audio.listenEnded(1)
        await drained(session)
        #expect(session.log == [.setCategory(Self.listener), .activate, .deactivate, .deactivate])
        #expect(sleeps.delays == [.milliseconds(150)])
        #expect(audio.failedDeactivations == 1)
    }

    /// Any other failure is not tried again, and stops the step there.
    @Test func anotherDeactivationFailureIsNotRetried() async {
        let session = FakeSession(refusing: [.deactivate])
        let sleeps = Sleeps()
        let audio = controller(session, sleeps: sleeps)
        #expect(await audio.listen(1))
        audio.listenEnded(1)
        await drained(session)
        #expect(session.log == [.setCategory(Self.listener), .activate, .deactivate])
        #expect(sleeps.delays.isEmpty)
        #expect(audio.failedDeactivations == 1)
    }

    /// Row 11a: a refused category stops the step: no activation in a category not asked for. The
    /// line's completion hears of it (the Speaker still speaks the line, R-231), and the release
    /// still follows.
    @Test func aRefusedCategoryMeansNoActivation() async {
        let session = FakeSession(refusing: [.setCategory(Self.speaker)])
        let timers = Timers()
        let audio = controller(session, timers: timers)
        let said = await say(audio, session)
        #expect(!said.ok)
        #expect(said.log == [.setCategory(Self.speaker)])
        audio.ended()
        await drained(session)
        timers.fire(0)
        await drained(session)
        #expect(session.log == [.setCategory(Self.speaker), .deactivate])
    }

    /// Row 11b: a refused activation is reported to Nghe; its stop then deactivates all the same
    /// (R-233) and puts the setup from before back.
    @Test func aRefusedActivationIsReportedAndTheStopStillDeactivates() async {
        let session = FakeSession(refusing: [.activate])
        let audio = controller(session)
        #expect(await audio.listen(1) == false)
        audio.listenEnded(1)
        await drained(session)
        #expect(session.log == [.setCategory(Self.listener), .activate, .deactivate, .setCategory(Self.fresh)])
    }

    // MARK: Nothing overtakes

    /// A line handed in while a deactivation waits for its second try runs after that try and after
    /// the rest of its step: the retry's wait holds the queue.
    @Test(.timeLimit(.minutes(1))) func nothingOvertakesTheRetry() async {
        let gate = Gate()
        let session = FakeSession(busy: 1)
        let audio = controller(session, sleeps: Sleeps(hold: gate))
        #expect(await audio.listen(1))
        audio.listenEnded(1)
        await gate.reached()
        let said = await withCheckedContinuation { c in
            audio.say { ok in c.resume(returning: ok) }
            gate.open()
        }
        #expect(said)
        #expect(session.log == [
            .setCategory(Self.listener), .activate,
            .deactivate, .deactivate, .setCategory(Self.fresh),
            .setCategory(Self.speaker), .activate,
        ])
    }

    /// (d): Nghe stopped while its activation runs: the stop's calls run after it, in order, and the
    /// listen still hears how its own calls went.
    @Test(.timeLimit(.minutes(1))) func aStopDuringTheActivationRunsAfterIt() async {
        let gate = Gate()
        let session = FakeSession(holdActivate: gate)
        let audio = controller(session)
        let listening = Task { await audio.listen(1) }
        await gate.reached()
        audio.listenEnded(1)
        gate.open()
        #expect(await listening.value)
        await drained(session)
        #expect(session.log == [.setCategory(Self.listener), .activate, .deactivate, .setCategory(Self.fresh)])
        #expect(audio.state.holder == .nobody)
    }
}

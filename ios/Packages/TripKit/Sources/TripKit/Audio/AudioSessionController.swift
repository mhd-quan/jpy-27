import Dispatch
import Foundation
import Synchronization

/// The calls `AudioSessionController` makes: the app's AVAudioSession on the phone. Each runs on the
/// controller's queue, never on the main thread, and may block.
public protocol AudioSessionPort: Sendable {
    /// the session's category, mode and options now
    func current() -> AudioSetup
    func setCategory(_ setup: AudioSetup) throws
    func activate() throws
    /// deactivates, telling other apps they may play again (`notifyOthersOnDeactivation`)
    func deactivate() throws
    /// the deactivation failed because audio was still playing or recording (`isBusy`): worth one more try
    func isBusy(_ error: any Error) -> Bool
    /// `call` failed for good, and its step stopped there: for the log. Told once per failure, on the queue.
    /// A deactivation refused as busy has failed for good only once its retry has failed too: a busy try
    /// that the retry made good is no failure, and is not told.
    func failed(_ call: AudioSessionOwners.Call, _ error: any Error)
}

/// The app's audio session, for its two owners (the Speaker, Nghe): `AudioSessionOwners` decides who
/// holds it, and this runs the calls that follow, off the caller's thread.
///
/// Everything happens on one private serial queue. An owner hands in an event (`say`, `ended`, `listen`,
/// `listenEnded`), which is queued before the owner's call returns, so the queue holds events in the order
/// they were issued. Each event is one job that reads the session's setup, steps the owners, and makes the
/// calls in order, start to finish, never yielding. A deactivation refused as busy is tried once more after
/// `retryDelay`, the queue's thread sleeping meanwhile. So no later event overtakes an earlier one, even
/// during that retry. A step stops at its first failed call. Nothing is put back onto a session that could
/// not be deactivated, and nothing activates in a category that could not be set.
///
/// The Speaker's release is not a job: its timer queues one when it fires, behind everything handed in
/// before, and that job does nothing unless the release is still due.
public final class AudioSessionController: Sendable {
    /// how long a deactivation refused as busy waits before its second and last try
    public static let retryDelay: Duration = .milliseconds(150)

    private struct Inside {
        var owners: AudioSessionOwners
        /// deactivations that failed for good (a busy one, only once its retry failed too): the session left
        /// active
        var failedDeactivations = 0
    }

    private let queue: DispatchQueue
    private let port: any AudioSessionPort
    private let inside: Mutex<Inside>
    /// blocks the queue's thread
    private let sleep: @Sendable (Duration) -> Void
    /// runs the work once the delay has passed
    private let after: @Sendable (Duration, @escaping @Sendable () -> Void) -> Void

    public convenience init(port: some AudioSessionPort, speaker: AudioSetup, listener: AudioSetup) {
        let queue = DispatchQueue(label: "tech.delphyra.jp27.audio-session", qos: .userInitiated)
        self.init(port: port, speaker: speaker, listener: listener, queue: queue,
                  sleep: { Thread.sleep(forTimeInterval: Self.seconds($0)) },
                  after: { delay, work in queue.asyncAfter(deadline: .now() + Self.seconds(delay), execute: work) })
    }

    /// For the tests: their own serial queue, sleep and timers.
    init(port: some AudioSessionPort, speaker: AudioSetup, listener: AudioSetup, queue: DispatchQueue,
         sleep: @escaping @Sendable (Duration) -> Void,
         after: @escaping @Sendable (Duration, @escaping @Sendable () -> Void) -> Void) {
        self.queue = queue
        self.port = port
        inside = Mutex(Inside(owners: AudioSessionOwners(speaker: speaker, listener: listener)))
        self.sleep = sleep
        self.after = after
    }

    /// who holds the session now, as of the last event run (for Settings › Chẩn đoán and the tests)
    public var state: AudioSessionOwners { inside.withLock { $0.owners } }

    /// deactivations that failed for good since launch: a busy one counts only once its retry has failed
    /// too, as `AudioSessionPort.failed` tells it
    public var failedDeactivations: Int { inside.withLock { $0.failedDeactivations } }

    /// The Speaker is about to read a line: queued now, behind every event handed in before. `done` runs
    /// on the main actor once the session's calls for it have run, true if they all succeeded. The line is
    /// spoken from there.
    public func say(then done: @escaping @MainActor @Sendable (Bool) -> Void) {
        queue.async { [self] in
            let found = port.current()
            let ok = run(inside.withLock { $0.owners.say(found: found) })
            Task { @MainActor in done(ok) }
        }
    }

    /// Nothing is left to say: queued now. The Speaker's session is released `releaseDelay` later, unless a
    /// line or Nghe comes in between.
    public func ended() {
        queue.async { [self] in
            guard let ticket = inside.withLock({ $0.owners.ended() }) else { return }
            after(AudioSessionOwners.releaseDelay) { [self] in
                // behind everything handed in before the timer fired: a line or a listen among them voids it
                queue.async { [self] in run(inside.withLock { $0.owners.releaseDue(ticket) }) }
            }
        }
    }

    /// Nghe starts the listen `id`: queued before this suspends. Returns once the session's calls for it
    /// have run, true if they all succeeded.
    public func listen(_ id: Int) async -> Bool {
        // nonisolated(nonsending): this runs on the caller's actor, and the continuation's body runs at
        // once, so the job is queued before the caller can issue anything else
        await withCheckedContinuation { c in
            queue.async { [self] in
                let found = port.current()
                c.resume(returning: run(inside.withLock { $0.owners.listen(id, found: found) }))
            }
        }
    }

    /// Nghe stops the listen `id`: queued now. Its calls run after those of every event handed in before,
    /// the listen's own among them.
    public func listenEnded(_ id: Int) {
        queue.async { [self] in
            let found = port.current()
            run(inside.withLock { $0.owners.listenEnded(id, found: found) })
        }
    }

    /// The calls of one step, in order, on the queue; true if all succeeded. The step stops at its first
    /// failed call, which the port is told of once (`failed`), after the retry of a busy deactivation.
    @discardableResult
    private func run(_ calls: [AudioSessionOwners.Call]) -> Bool {
        for call in calls {
            do {
                switch call {
                case .setCategory(let setup): try port.setCategory(setup)
                case .activate: try port.activate()
                case .deactivate: try deactivate()
                }
            } catch {
                if call == .deactivate { inside.withLock { $0.failedDeactivations += 1 } }
                port.failed(call, error)
                return false
            }
        }
        return true
    }

    /// Refused as busy (the audio still winding down): once more after `retryDelay`, the queue held
    /// meanwhile so that nothing handed in since runs first. Any other failure is not tried again.
    private func deactivate() throws {
        do {
            try port.deactivate()
        } catch let error where port.isBusy(error) {
            sleep(Self.retryDelay)
            try port.deactivate()
        }
    }

    /// `duration` in seconds, as `Thread.sleep` and `DispatchTime` take it
    static func seconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

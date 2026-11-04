import Foundation

/// One piece of work, run as seldom as the requests for it allow: requests close together are served
/// by one run, a sooner request brings the run forward and a later one never puts it off, runs never
/// overlap, and a request made while one runs gets exactly one more run after it, however many came.
///
/// The reschedule of reminders, geofences and alarms is the case: a tick, a skip, the app coming back
/// and the permission or position that follows each ask for it, often within a second of each other,
/// and the background refresh has to know when it is done (`flush`).
@MainActor public final class Coalescer {
    /// how many runs have begun, for the tests and Settings › Chẩn đoán
    public private(set) var runs = 0

    private let sleep: @Sendable (Duration) async throws -> Void
    private let work: @MainActor () async -> Void
    /// the timers waiting to start a run, each with the delay it was asked for with
    private var timers: [(id: Int, delay: Duration, task: Task<Void, Never>)] = []
    private var nextTimer = 0
    /// the runs going on, one after another
    private var running: Task<Void, Never>?
    /// a run is wanted that begins after the one going on
    private var again = false

    /// `sleep` is the only clock: tests pass one they move by hand.
    public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                work: @escaping @MainActor () async -> Void) {
        self.sleep = sleep
        self.work = work
    }

    /// Nothing waits to run and nothing runs.
    public var isIdle: Bool { timers.isEmpty && running == nil }

    /// A run begins `delay` from now at the latest: one already due sooner serves this request too.
    ///
    /// No clock is needed to tell which is sooner: every timer waiting was asked for before this
    /// request, so one asked for with a delay no longer than `delay` is due no later, and the request
    /// adds nothing. A shorter delay may be due sooner and gets a timer of its own. The first timer to
    /// go off starts the run and stops the others: a request never stops a timer, so a run is never
    /// put off. The timers waiting have ever shorter delays, so there are few.
    public func request(after delay: Duration) {
        if let shortest = timers.map(\.delay).min(), shortest <= delay { return }
        let id = nextTimer
        nextTimer += 1
        let task = Task {
            do {
                try await sleep(delay)
            } catch {
                // stopped (already gone from `timers`), or a sleep that failed: nothing waits on this
                // one any more, so it neither keeps the coalescer busy nor stands in for a later request
                timers.removeAll { $0.id == id }
                return
            }
            // stopped though the sleep ended normally: `Task.sleep` does that when its time had come
            // just before the stop, its wake already queued
            guard !Task.isCancelled else { return }
            due()
        }
        timers.append((id, delay, task))
    }

    /// Runs now, in place of any timer waiting, and returns once nothing is left to run. A run already
    /// going on is waited for and followed by one more (it began before this call, so it may not have
    /// seen what the caller changed); what is asked for meanwhile is run at once, not at its time.
    ///
    /// Not from inside the work: it would wait for itself. The caller being cancelled does not stop the
    /// wait (the run it waits for cannot be stopped either); check between steps instead.
    public func flush() async {
        repeat {
            stopTimers()
            start()
            while let run = running { await run.value }
        } while !timers.isEmpty
    }

    /// A timer went off: the run it starts serves every request waiting.
    private func due() {
        stopTimers()
        start()
    }

    private func stopTimers() {
        for timer in timers { timer.task.cancel() }
        timers = []
    }

    /// A run, or one more after the one going on.
    private func start() {
        guard running == nil else {
            again = true
            return
        }
        running = Task {
            repeat {
                // what was asked for until now is served by this run
                again = false
                runs += 1
                await work()
            } while again
            running = nil
        }
    }
}

import Foundation

/// The last of a run of values, handed on once they stop coming: each `send` puts the hand-on off to
/// `delay` after it, so values closer together than `delay` reach `fire` only as the last of them.
///
/// Unlike `Coalescer`, whose later requests never put a run off, this is a trailing debounce: what
/// matters is the value the sends came to rest on. The Map tab's camera is the case: items cross the
/// reading line many times a second during a swipe, and the map flies once, to the one the line stops on.
///
/// It does not compare values: `fire` gets the last value sent, even one equal to what it got last time
/// (`Equatable` is there for the callers' values, not used here). A caller that wants "only when
/// different" compares in its own `fire`.
@MainActor public final class Debouncer<Value: Sendable & Equatable> {
    private let delay: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let fire: @MainActor (Value) -> Void
    /// the wait for the last value sent
    private var pending: Task<Void, Never>?

    /// `sleep` is the only clock: tests pass one they move by hand.
    public init(delay: Duration,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                fire: @escaping @MainActor (Value) -> Void) {
        self.delay = delay
        self.sleep = sleep
        self.fire = fire
    }

    /// `v` goes to `fire` `delay` from now, unless another value is sent (or `cancel` called) first.
    public func send(_ v: Value) {
        pending?.cancel()
        // weak: a debouncer let go (its view gone) hands nothing on
        pending = Task { [weak self, sleep, delay] in
            do {
                try await sleep(delay)
            } catch {
                // stopped by a newer send or `cancel`, or a sleep that failed: nothing to hand on
                return
            }
            // stopped though the sleep ended normally: `Task.sleep` does that when its time had come
            // just before the stop, its wake already queued
            guard !Task.isCancelled, let self else { return }
            pending = nil
            fire(v)
        }
    }

    /// The value waiting is dropped; the next `send` starts afresh.
    public func cancel() {
        pending?.cancel()
        pending = nil
    }
}

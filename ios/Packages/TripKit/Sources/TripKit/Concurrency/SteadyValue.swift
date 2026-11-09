import Foundation

/// A value handed on once it holds. The first report is published at once: nothing was known before it.
/// After that, a change is published only once it has stood `delay` with no other change reported since,
/// and only when it differs from the value published last. A run of reports that ends where it began
/// publishes nothing.
///
/// The app's network status is the case (`NetworkStatus.online`). The path monitor flips on a flaky signal,
/// and every flip used to tear a page's live 3D map down and build it again. The wait is a `Debouncer`'s
/// (trailing): this class adds the first report and "only when different". A report equal to the last one
/// reported is not a change. The path says the same again on another interface, and the change still holds
/// from when it began.
@MainActor public final class SteadyValue<Value: Sendable & Equatable> {
    private let publish: @MainActor (Value) -> Void
    /// what `publish` got last; nil until the first report
    private var published: Value?
    /// the last report: a repeat of it is no change
    private var reported: Value?
    private var waiting: Debouncer<Value>!

    /// `sleep` is the only clock: tests pass one they move by hand.
    public init(delay: Duration,
                sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
                publish: @escaping @MainActor (Value) -> Void) {
        self.publish = publish
        // weak: a steady value let go publishes nothing
        waiting = Debouncer(delay: delay, sleep: sleep) { [weak self] value in self?.held(value) }
    }

    /// The value as it is now: published at once if it is the first, else once it has held.
    public func report(_ value: Value) {
        guard published != nil else {
            reported = value
            published = value
            publish(value)
            return
        }
        guard value != reported else { return }
        reported = value
        waiting.send(value)
    }

    /// `value` has stood `delay`: published if it is not what was published last.
    private func held(_ value: Value) {
        guard value != published else { return }
        published = value
        publish(value)
    }
}

import Foundation

/// One piece of work per key at a time, the latest request winning: a request made while the key's
/// work runs waits for it, in place of any request that was waiting before, and runs after it. A
/// cancel drops what waits, and tells the work still running that it was overtaken (`isCurrent`).
///
/// The alighting alarm is the case: every position of a followed ride asks for the alarm, and the
/// first ask waits for the permission prompt. Run side by side, each ask set an alarm of its own
/// once the prompt was answered, and only the last was remembered (and could be cancelled).
@MainActor public final class OneAtATime<Request> {
    /// the request each running key is working on
    private var running: [String: Request] = [:]
    private var waiting: [String: Request] = [:]
    private var epochs: [String: Int] = [:]

    public init() {}

    /// What a piece of work holds to ask, after each wait, whether it is still wanted.
    public struct Ticket: Sendable, Hashable {
        let key: String
        let epoch: Int
    }

    /// Runs `work` for `request`, then for whatever request is left waiting when it is done, until
    /// none is (with this call's `work`: one key, one kind of work). While the key's work runs,
    /// `request` is left waiting instead and this returns at once, unless `overrides` says it may
    /// not take the place of what runs or waits (both given).
    public func run(_ key: String, _ request: Request,
                    overrides: (_ running: Request, _ waiting: Request?) -> Bool = { _, _ in true },
                    work: @MainActor (Request, Ticket) async -> Void) async {
        if let current = running[key] {
            if overrides(current, waiting[key]) { waiting[key] = request }
            return
        }
        var next: Request? = request
        while let r = next {
            running[key] = r
            await work(r, Ticket(key: key, epoch: epochs[key, default: 0]))
            next = waiting.removeValue(forKey: key)
        }
        running[key] = nil
    }

    /// The work holding `ticket` has not been cancelled since it began.
    public func isCurrent(_ ticket: Ticket) -> Bool {
        epochs[ticket.key, default: 0] == ticket.epoch
    }

    /// Nothing more for `key`: what waits is dropped, and what runs finds its ticket no longer current.
    public func cancel(_ key: String) {
        epochs[key, default: 0] += 1
        waiting[key] = nil
    }

    public func isRunning(_ key: String) -> Bool { running[key] != nil }
}

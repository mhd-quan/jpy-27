import Foundation

/// At most `limit` pieces of work at once, one per key; the newest ask wins a place, and the oldest one
/// running is let go for it. It holds no work and no clock: it says what to start and what to cancel, and the
/// caller holds the tasks (the app's `Prefetch`: a day page loaded as its card rests or is touched).
///
/// - A key asked for while it runs is not started again: it becomes the newest, so an older one goes first.
/// - Each start hands out a ticket; only that ticket's finish frees the slot. A task cancelled to make room
///   that finishes after its key was asked for again frees nothing of the new run's.
public struct NewestFew<Key: Hashable & Sendable>: Sendable {
    /// One run of a key: handed out by `admit`, handed back to `finished`.
    public struct Ticket: Hashable, Sendable {
        public let key: Key
        let number: Int
    }

    public enum Admission: Equatable, Sendable {
        /// already running under this ticket: nothing to start, and it is now the newest
        case running(Ticket)
        /// start the work under this ticket, after cancelling the one named (the oldest), if any
        case start(Ticket, cancelling: Ticket?)
    }

    public let limit: Int
    /// what runs, oldest first
    private var held: [Ticket] = []
    /// tickets handed out so far: numbers each run
    private var runs = 0

    public init(limit: Int) {
        precondition(limit >= 1, "NewestFew needs room for one")
        self.limit = limit
    }

    /// the keys running, oldest first
    public var running: [Key] { held.map(\.key) }

    /// `key` is wanted: running already (it moves to the newest place), or to be started, the oldest one running
    /// cancelled to make room when all `limit` places are taken.
    public mutating func admit(_ key: Key) -> Admission {
        if let i = held.firstIndex(where: { $0.key == key }) {
            let ticket = held.remove(at: i)
            held.append(ticket)
            return .running(ticket)
        }
        runs += 1
        let ticket = Ticket(key: key, number: runs)
        let cancelled = held.count >= limit ? held.removeFirst() : nil
        held.append(ticket)
        return .start(ticket, cancelling: cancelled)
    }

    /// The work under `ticket` is done (or was cancelled and has stopped): its slot is free, if it still holds one.
    public mutating func finished(_ ticket: Ticket) {
        held.removeAll { $0 == ticket }
    }

    /// Everything goes: the tickets to cancel, oldest first.
    public mutating func removeAll() -> [Ticket] {
        defer { held = [] }
        return held
    }
}

/// Failures in a row, where requests that were in flight together count once: they failed for the
/// same reason (one outage), whichever comes back first. `ForecastService` sets WeatherKit aside
/// after two of these; two views asking at once must not make one outage look like two.
///
/// A failure counts only when its request began after the last failure that counted (its ticket
/// was taken since). A success starts the count again.
public struct FailureStreak: Sendable, Hashable {
    /// Taken before a request, handed back with its failure.
    public struct Ticket: Sendable, Hashable {
        let epoch: Int
    }

    /// failures in a row, overlapping ones counted once
    public private(set) var count = 0
    /// bumped by every failure that counts: a ticket taken before it belongs to that failure
    private var epoch = 0

    public init() {}

    public func ticket() -> Ticket { Ticket(epoch: epoch) }

    /// Notes a failed request; returns the count.
    @discardableResult
    public mutating func failed(_ ticket: Ticket) -> Int {
        guard ticket.epoch == epoch else { return count }
        count += 1
        epoch += 1
        return count
    }

    public mutating func succeeded() {
        count = 0
    }
}

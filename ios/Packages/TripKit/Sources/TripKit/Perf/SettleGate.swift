/// The rules of `transitionSettled` on a page that a transition brings in (`settles` in the app). The
/// page answers the tap that opened it once, on its first appearance; it waits for the transition while it
/// is not settled; a wait that runs out settles it, once; a wait cut short (the page went: closed, covered,
/// or left by a tab switch) leaves it unsettled, and the next appearance waits again. Settled never turns
/// back to false. So it can never stay false while the page shows, which Tasks 4.1 and 5.3 rely on.
public struct SettleGate: Sendable, Equatable {
    /// the first appearance happened (it claimed the tap)
    public private(set) var claimed = false
    /// the transition has had its time
    public private(set) var settled = false

    public init() {}

    /// An appearance: true only for the first, the one that claims the tap that opened the page.
    public mutating func appeared() -> Bool {
        guard !claimed else { return false }
        claimed = true
        return true
    }

    /// Whether an appearance waits for the transition: only while the page is not settled.
    public var waits: Bool { !settled }

    /// A wait ended, run out (`finished`) or cut short. True once: for the wait that settles the page.
    public mutating func waited(finished: Bool) -> Bool {
        guard finished, !settled else { return false }
        settled = true
        return true
    }
}

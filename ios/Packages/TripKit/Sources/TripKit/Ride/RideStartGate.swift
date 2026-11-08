/// The ride followed, and whether it has begun, for a start in two steps (`RideLiveService`): `select` takes the ride
/// at once, inside the tap's animation, and `begin` asks for its Live Activity and navigation positions a frame
/// later. Between the two another ride may be selected, the ride may be ended, or `start` (select and begin at
/// once) may begin it first; the gate lets one begin through per selection, for the ride selected only, and never
/// while its end is under way, so a ride never holds two Live Activities.
///
/// It also holds the end's claim (`claim`, `released`), which every end of a ride goes through once.
public struct RideStartGate: Sendable, Equatable {
    /// the ride followed
    public private(set) var selected: String?
    /// the ride whose end is under way: taken by the first end that gets there
    private var closing: String?
    /// the selected ride has begun
    private var begun = false

    public init() {}

    /// `id` becomes the ride followed, not yet begun. False, changing nothing, when it already is (the same-ride
    /// guard: a ride followed again is not reset, and its begin is not re-armed). An end under way for another
    /// ride stays its own (`released`).
    @discardableResult
    public mutating func select(_ id: String) -> Bool {
        guard selected != id else { return false }
        selected = id
        begun = false
        return true
    }

    /// The first end of the ride followed takes it; the others, and ends of a ride no longer followed, get false.
    public mutating func claim(_ id: String) -> Bool {
        guard selected == id, closing != id else { return false }
        closing = id
        return true
    }

    /// Whether the end of `id` is under way.
    public func isClosing(_ id: String) -> Bool {
        closing == id
    }

    /// The end of `id` has let go: if it is still the ride followed, nothing is followed; if another was selected
    /// meanwhile, only the claim of `id` goes, so `id` followed again later can be ended again.
    public mutating func released(_ id: String) {
        if selected == id {
            selected = nil
            begun = false
            closing = nil
        } else if closing == id {
            closing = nil
        }
    }

    /// Whether `id` may begin now: true once per selection, for the ride selected, and not while its end is under
    /// way. A begin for a ride since replaced, ended or begun gets false.
    public mutating func begin(_ id: String) -> Bool {
        guard selected == id, closing != id, !begun else { return false }
        begun = true
        return true
    }
}

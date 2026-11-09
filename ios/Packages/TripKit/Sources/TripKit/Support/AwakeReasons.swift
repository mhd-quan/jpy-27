/// Why the screen is kept from locking itself: one place holds every reason, so turning one off (the ride
/// ended, or the switch turned off) leaves the screen on for another (the phrase card still held up to
/// staff). Each reason is on or off; setting one twice is setting it once.
public struct AwakeReasons: Sendable, Equatable {
    public enum Reason: String, Sendable {
        /// Sổ tay's full-screen card, held up to the person across the counter
        case showCard
        /// a ride followed, with Settings › Giữ màn hình sáng khi đi tàu on, the app on screen
        case ride
    }

    private var on: Set<Reason> = []

    public init() {}

    public mutating func set(_ r: Reason, _ on: Bool) {
        if on { self.on.insert(r) } else { self.on.remove(r) }
    }

    /// some reason holds
    public var keepsAwake: Bool { !on.isEmpty }
}

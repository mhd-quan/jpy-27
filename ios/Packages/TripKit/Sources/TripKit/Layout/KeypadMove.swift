/// What a sheet's own number pad does when the system keyboard rises or goes down (`ExpenseEditor`): the other
/// way from the keyboard, on the keyboard's own timing, so the two read as one motion.
public enum KeypadMove: Equatable, Sendable {
    /// nothing to do
    case stay
    /// the pad shown or hidden, over `duration` seconds of the keyboard's curve; nil: at once, with no animation
    case move(shown: Bool, duration: Double?)

    /// From one keyboard notification: `keyboardShows` (will show, or will hide), `isLocal` (the notification's
    /// "is local" flag, nil when it has none), `padShown` now, `leaving` (the sheet is being closed by its own
    /// buttons) and the notification's animation `duration`.
    ///
    /// - Another app's keyboard (`isLocal == false`, on iPad) moves nothing.
    /// - The pad already where it would go stays.
    /// - The keyboard going down as the sheet leaves brings no pad back; hiding the pad is always allowed.
    /// - A duration that is not above 0 (none, 0, NaN) moves the pad with no curve.
    public static func on(keyboardShows: Bool, isLocal: Bool?, padShown: Bool, leaving: Bool, duration: Double?) -> KeypadMove {
        if isLocal == false { return .stay }
        let shown = !keyboardShows
        guard shown != padShown, !(shown && leaving) else { return .stay }
        return .move(shown: shown, duration: duration.flatMap { $0 > 0 ? $0 : nil })
    }
}

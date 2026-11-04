import SwiftUI

/// Named by what the motion is for, like `SensoryFeedback` (see `Components.swift`): one curve per
/// kind of moment, so the same kind of moment moves the same way on every page. Pass the token
/// through `Motion.reduced` when Reduce Motion is on.
///
/// `Animation` is `Sendable`, so these are plain `static let`s that nonisolated code can read.
nonisolated enum Motion {
    /// The finger is on it: a press, a key, a drag let go.
    static let press: Animation = .spring(duration: 0.3, bounce: 0.28)
    /// One of a few chosen: chips, checks, a category, a highlight, the amount on the keypad.
    static let pick: Animation = .snappy(duration: 0.25)
    /// Something that was not there arrives: a photo, a snapshot, a title. Never on a cache hit,
    /// never inside `drawingGroup`.
    static let arrive: Animation = .easeOut(duration: 0.2)
    /// A panel, a strip or a card comes to rest.
    static let settle: Animation = .spring(duration: 0.38, bounce: 0.14)
    /// The same, carrying on from the speed the finger let go at (points per second, as the drag
    /// reports it, divided by the distance still to go).
    static func settle(velocity: Double) -> Animation {
        .interpolatingSpring(duration: 0.38, bounce: 0.14, initialVelocity: velocity)
    }
    /// A long move the eye follows: a camera flight, the cover turning, the dial drawing.
    static let travel: Animation = .smooth(duration: 1.0)

    /// The short ease that stands in for a spring under Reduce Motion.
    private static let calm: Animation = .easeOut(duration: 0.15)

    /// The token to use when Reduce Motion is `reduce`. Pass one of the five tokens above
    /// (`settle(velocity:)` counts as `settle`).
    /// - `reduce` is false: `a`, unchanged.
    /// - `reduce` is true: `travel` gives `nil`, `arrive` stays as it is (it is already a short
    ///   ease), and every spring (`press`, `pick`, `settle`, `settle(velocity:)`) gives a 0.15 s
    ///   ease-out.
    ///
    /// `nil` means no animation at all: the caller jumps straight to the end, through
    /// `withAnimation(nil) { … }` or `.animation(nil, value: x)`.
    static func reduced(_ a: Animation, _ reduce: Bool) -> Animation? {
        guard reduce else { return a }
        if a == travel { return nil }
        if a == arrive { return a }
        return calm
    }
}

import SwiftUI

/// Named by what the motion is for, like `SensoryFeedback`: one curve per kind of moment.
/// Every animation of the app uses these (ios/README.md, "Chuyển động"; `scripts/lint-motion.mjs` checks it in CI);
/// `reduced` applies Reduce Motion.
nonisolated enum Motion {
    /// the finger is on it: a press, a key, a drag let go
    static let press: Animation = .spring(duration: 0.3, bounce: 0.28)
    /// one of a few chosen: chips, checks, a category, a highlight, the amount on the keypad
    static let pick: Animation = .snappy(duration: 0.25)
    /// something that was not there arrives: a photo, a snapshot, a title — never on a cache hit, never inside drawingGroup
    static let arrive: Animation = .easeOut(duration: 0.2)
    /// a panel, a strip or a card comes to rest
    static let settle: Animation = .spring(duration: 0.38, bounce: 0.14)
    /// the same, when a drag is let go with the finger's velocity
    static func settle(velocity: Double) -> Animation {
        .interpolatingSpring(duration: 0.38, bounce: 0.14, initialVelocity: velocity)
    }
    /// a long move the eye follows: a camera flight, the cover turning, the dial drawing
    static let travel: Animation = .smooth(duration: 1.0)

    /// The short ease that stands in for a spring or a `pick` under Reduce Motion: `arrive`'s curve on purpose.
    private static let short: Animation = arrive

    /// The same under Reduce Motion: springs and `pick` become a short ease, `arrive` stays,
    /// `travel` becomes none (nil: the change jumps). Anything that is not `arrive` or `travel`,
    /// `settle(velocity:)` included, takes the short ease.
    ///
    /// Apply it to the bare token and chain modifiers after it, because it matches by `Animation ==`:
    /// `Motion.reduced(Motion.travel, reduce)?.delay(0.1)`, never `Motion.reduced(Motion.travel.delay(0.1), reduce)`
    /// (that is not `travel` any more, so it would take the short ease instead of jumping).
    /// `scripts/lint-motion.mjs` fails a spring or travel token used outside it.
    static func reduced(_ a: Animation, _ reduce: Bool) -> Animation? {
        guard reduce else { return a }
        if a == arrive { return a }
        if a == travel { return nil }
        return short
    }
}

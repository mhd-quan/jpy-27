import Foundation

/// Amounts of money, the one rule for what an expense may hold, and sums that cannot trap.
///
/// The keypad stops below ten million yen; a file and the other phone are held to the same bound
/// (`LedgerValidation`). A row saved before the bound existed may still hold anything, so every
/// total goes through `total`/`difference`, which stop at the ends of `Int` instead of crashing:
/// one absurd row must never take the Spend tab down at every launch.
public nonisolated enum Yen {
    /// the most one expense may be: the keypad's cap
    public static let maxEntry = 9_999_999

    /// Whether an amount is one the keypad could have typed: 1 to `maxEntry`.
    public static func isValidEntry(_ yen: Int) -> Bool {
        yen >= 1 && yen <= maxEntry
    }

    /// The sum, held at `Int.max` or `Int.min` where it would overflow.
    public static func total<S: Sequence>(_ values: S) -> Int where S.Element == Int {
        var sum = 0
        for v in values {
            let (partial, overflow) = sum.addingReportingOverflow(v)
            sum = overflow ? (v > 0 ? Int.max : Int.min) : partial
        }
        return sum
    }

    /// `a − b` (what is left in a purse: in minus out), held at the ends of `Int`.
    public static func difference(_ a: Int, _ b: Int) -> Int {
        let (partial, overflow) = a.subtractingReportingOverflow(b)
        return overflow ? (b < 0 ? Int.max : Int.min) : partial
    }
}

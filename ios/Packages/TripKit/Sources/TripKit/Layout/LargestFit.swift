/// The largest size that fits, by halving the range: for type set as large as its room allows. The phrase card
/// (`TalkShowFit` in the app) asks it once per orientation, with a measurement of the Japanese at each size it tries.
public enum LargestFit {
    /// The largest `n` in `range` for which `fits(n)` holds. `fits` must be monotone: if a size fits, every smaller
    /// size fits too. The search is over whole numbers (one-point precision for type). When nothing above the lower
    /// bound fits, the answer is the lower bound, which is never asked about: nothing smaller can be given, so
    /// measuring it would change nothing. `fits` is asked at most ⌈log2(range.count)⌉ times (8 for 12...160), each
    /// size at most once, and never about a size outside `range`.
    public static func size(in range: ClosedRange<Int>, fits: (Int) -> Bool) -> Int {
        // the answer is in lo...hi, and lo is known to be it if nothing above it fits
        var lo = range.lowerBound
        var hi = range.upperBound
        while lo < hi {
            // rounded up, so that `lo = mid` always moves lo
            let mid = lo + (hi - lo + 1) / 2
            if fits(mid) {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }
}

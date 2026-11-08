import Testing
@testable import TripKit

/// The phrase card's type size (`TalkShowFit` in the app): the largest whole point size in 12...160 at which the
/// Japanese still fits its orientation's room, found by halving, never by trying each size.
@Suite struct LargestFitTests {
    /// the card's range
    let card = 12...160

    /// `LargestFit.size` with `fits(n) = n <= threshold`, and every size it asked about, in order
    private func search(_ range: ClosedRange<Int>, threshold: Int) -> (size: Int, asked: [Int]) {
        var asked: [Int] = []
        let size = LargestFit.size(in: range) { n in
            asked.append(n)
            return n <= threshold
        }
        return (size, asked)
    }

    @Test func everyThresholdGivesTheLargestThatFits() {
        for t in 0...200 {
            #expect(search(card, threshold: t).size == min(max(t, 12), 160), "threshold \(t)")
        }
    }

    @Test func nothingFitsGivesTheLowerBound() {
        // a phrase too long for the card even at 12 pt: 12, and the text's own scale factor does the rest
        #expect(LargestFit.size(in: card) { _ in false } == 12)
    }

    @Test func everythingFitsGivesTheUpperBound() {
        // a word of two characters
        #expect(LargestFit.size(in: card) { _ in true } == 160)
    }

    @Test func asksOnlyInsideTheRangeEachSizeOnceAndAtMostEightTimes() {
        // 149 sizes: ⌈log2 149⌉ = 8 measurements, the cost of one orientation
        for t in 0...200 {
            let asked = search(card, threshold: t).asked
            #expect(asked.allSatisfy { card.contains($0) }, "threshold \(t): \(asked)")
            #expect(Set(asked).count == asked.count, "threshold \(t): \(asked)")
            #expect(asked.count <= 8, "threshold \(t): \(asked.count) asks")
        }
    }

    @Test func theLowerBoundIsNeverAskedAbout() {
        // nothing smaller can be given, so measuring it would be wasted
        for t in 0...200 {
            #expect(!search(card, threshold: t).asked.contains(12), "threshold \(t)")
        }
    }

    @Test func aOneSizeRangeAsksNothing() {
        let (size, asked) = search(20...20, threshold: 0)
        #expect(size == 20)
        #expect(asked.isEmpty)
    }

    @Test func aMeasuredShapeAgreesWithALinearScan() {
        // glyphs of n × n points, flowed into a room of `area` square points: monotone like a real measurement
        for glyphs in [2, 9, 23, 60] {
            for area in stride(from: 1_000, through: 400_000, by: 7_919) {
                let fits = { (n: Int) in n * n * glyphs <= area }
                let scanned = card.reversed().first(where: fits) ?? card.lowerBound
                #expect(LargestFit.size(in: card, fits: fits) == scanned, "\(glyphs) glyphs in \(area)")
            }
        }
    }

    @Test func otherRangesFollowTheSameRule() {
        for range in [0...1, 5...6, 1...1000, -10...10] {
            for t in (range.lowerBound - 2)...(range.upperBound + 2) {
                let (size, asked) = search(range, threshold: t)
                #expect(size == min(max(t, range.lowerBound), range.upperBound), "\(range) threshold \(t)")
                #expect(asked.allSatisfy { range.contains($0) })
            }
        }
    }
}

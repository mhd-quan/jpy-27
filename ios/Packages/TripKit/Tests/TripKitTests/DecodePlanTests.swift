import Testing
@testable import TripKit

/// Which decode of a photo the app's photo cache draws where a view asks for the photo at a size (its longest side in
/// pixels). A decode of the whole photo serves every ask; a smaller copy only asks it is at most twice as large as,
/// so it is shrunk when drawn and never enlarged.
@Suite struct DecodePlanTests {
    private let webp = DecodePlan.Size(width: 800, height: 598)

    @Test func fullDecodeServesLargerAsks() {
        // the Commons WebP asked at 1800 gives its 800 px: nothing a decode of its own could add
        #expect(DecodePlan.serves(decoded: webp, sourceIsFull: true, asked: 1800))
        #expect(DecodePlan.serves(decoded: webp, sourceIsFull: true, asked: 801))
    }

    @Test func downsampledServesUpToTwice() {
        let card = DecodePlan.Size(width: 992, height: 1200)
        #expect(DecodePlan.serves(decoded: card, sourceIsFull: false, asked: 600))
        #expect(!DecodePlan.serves(decoded: card, sourceIsFull: false, asked: 599))
        #expect(DecodePlan.serves(decoded: card, sourceIsFull: false, asked: 1200))
        // never enlarged
        #expect(!DecodePlan.serves(decoded: card, sourceIsFull: false, asked: 1201))
        #expect(!DecodePlan.serves(decoded: card, sourceIsFull: false, asked: 1300))
    }

    @Test func smallerAskIsServed() {
        #expect(DecodePlan.serves(decoded: webp, sourceIsFull: true, asked: 96))
        #expect(!DecodePlan.serves(decoded: webp, sourceIsFull: false, asked: 96))
    }

    @Test func aWholeDecodeServesTheAskItWasMadeAt() {
        #expect(DecodePlan.serves(decoded: webp, sourceIsFull: true, asked: 800))
        #expect(DecodePlan.serves(decoded: webp, sourceIsFull: false, asked: 800))
    }

    @Test func theLongestSideIsWhatIsCompared() {
        // portrait: 900 wide, 1200 tall, like a cover asked at 1200
        let portrait = DecodePlan.Size(width: 900, height: 1200)
        #expect(DecodePlan.serves(decoded: portrait, sourceIsFull: false, asked: 1200))
        #expect(DecodePlan.serves(decoded: portrait, sourceIsFull: false, asked: 600))
        #expect(!DecodePlan.serves(decoded: portrait, sourceIsFull: false, asked: 599))
        // landscape the same way round
        let landscape = DecodePlan.Size(width: 1200, height: 900)
        #expect(DecodePlan.serves(decoded: landscape, sourceIsFull: false, asked: 1200))
        #expect(!DecodePlan.serves(decoded: landscape, sourceIsFull: false, asked: 1201))
        #expect(portrait.longest == 1200 && landscape.longest == 1200)
    }

    @Test func lessThanAskedIsTheWholePhoto() {
        // ImageIO never enlarges: a decode smaller than asked is the source itself
        #expect(DecodePlan.isFull(decoded: webp, asked: 1800))
        #expect(DecodePlan.isFull(decoded: webp, asked: 801))
        // exactly the ask may be a source larger than it, cut down: a downsample
        #expect(!DecodePlan.isFull(decoded: webp, asked: 800))
        #expect(!DecodePlan.isFull(decoded: webp, asked: 600))
    }

    @Test func wholeIsJudgedOnTheLongestSide() {
        let portrait = DecodePlan.Size(width: 1290, height: 1560)
        #expect(DecodePlan.isFull(decoded: portrait, asked: 2400))
        #expect(DecodePlan.isFull(decoded: portrait, asked: 1561))
        // the width alone is under the ask; the height is not
        #expect(!DecodePlan.isFull(decoded: portrait, asked: 1560))
        #expect(!DecodePlan.isFull(decoded: portrait, asked: 1300))
    }
}

import Testing
@testable import TripKit

/// Which photo decode already in memory serves a view's ask (the app's `PhotoCache.cached`): one decode per photo
/// on an album page, without drawing a small bitmap blown up or a huge one squeezed into a thumbnail.
///
/// The plan's Step 1 named "decoded 600 serves an ask of 1200": that is an upscale, the reverse of the rule it
/// describes ("as now", a larger decode serves a smaller ask). Ruling R-242 keeps the rule as it is today, and
/// R-243 bounds a whole decode below as well; the values here are the ruled ones.
@Suite struct DecodePlanTests {
    func serves(_ width: Double, _ height: Double, whole: Bool, _ asked: Int) -> Bool {
        DecodePlan.serves(decoded: Size(width: width, height: height), sourceIsFull: whole, asked: asked)
    }

    /// The whole photo, decoded because it was smaller than the ask: a larger ask would decode the very same
    /// pixels, however large it is.
    @Test func fullDecodeServesLargerAsks() {
        #expect(serves(800, 598, whole: true, 1800))
        #expect(serves(800, 598, whole: true, 2400))
        #expect(serves(800, 598, whole: true, 800))
    }

    /// A photo decoded smaller than its source serves its own ask and asks down to half of it.
    @Test func downsampledServesUpToTwice() {
        #expect(serves(1200, 897, whole: false, 600))
        #expect(serves(1200, 897, whole: false, 1200))
        #expect(!serves(1200, 897, whole: false, 599))
    }

    /// ... and never a larger ask: the source has more pixels than this decode kept.
    @Test func downsampledNeverServesALargerAsk() {
        #expect(!serves(600, 448, whole: false, 1200))
        #expect(!serves(600, 448, whole: false, 601))
    }

    /// A whole decode serves smaller asks down to half as well: a thumbnail drawn from a bitmap many times its
    /// size costs more on every frame than a decode of its own.
    @Test func smallerAskIsServed() {
        #expect(serves(800, 598, whole: true, 400))
        #expect(!serves(800, 598, whole: true, 399))
        #expect(!serves(800, 598, whole: true, 96))
    }

    /// The ask is a long edge (ImageIO's `kCGImageSourceThumbnailMaxPixelSize`), so a portrait photo counts by
    /// its height.
    @Test func longEdgeDecides() {
        #expect(serves(449, 800, whole: true, 800))
        #expect(serves(449, 800, whole: true, 1800))
        #expect(serves(300, 600, whole: false, 600))
        #expect(serves(300, 600, whole: false, 300))
        #expect(!serves(300, 600, whole: false, 299))
        #expect(!serves(300, 600, whole: false, 601))
    }

    /// Without the whole source, the same pixels are only a downsample: a larger ask decodes again.
    @Test func wholeNeedsTheFlag() {
        #expect(!serves(800, 598, whole: false, 1800))
        #expect(!serves(800, 598, whole: false, 801))
    }
}

import Testing
@testable import TripKit

/// The part of a photograph an album page's picture is composed from (the app's `PhotoCache.ambient`, ruling R-247):
/// what `scaledToFill()` shows of it in the page's box, centred, in whole pixels, never enlarged.
@Suite struct FillCropTests {
    func crop(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Size.Crop {
        Size.Crop(x: x, y: y, size: Size(width: width, height: height))
    }

    /// A landscape photograph in a portrait box: the full height, the middle of the width.
    @Test func landscapeKeepsTheHeight() {
        #expect(Size(width: 1800, height: 1200).fillCrop(Size(width: 400, height: 500)) == crop(420, 0, 960, 1200))
    }

    /// A portrait photograph in a wide box: the full width, the middle of the height.
    @Test func portraitKeepsTheWidth() {
        #expect(Size(width: 1200, height: 1800).fillCrop(Size(width: 400, height: 200)) == crop(0, 600, 1200, 600))
        // a phone's album box (402 × 524) over a 1350 × 1800 photograph: 1350 / (402 / 524) = 1759.7, so 1760
        #expect(Size(width: 1350, height: 1800).fillCrop(Size(width: 402, height: 524)) == crop(0, 20, 1350, 1760))
    }

    /// The same shape: the whole photograph.
    @Test func equalAspectIsTheWholePhotograph() {
        #expect(Size(width: 1200, height: 900).fillCrop(Size(width: 400, height: 300)) == crop(0, 0, 1200, 900))
        #expect(Size(width: 1800, height: 1200).fillCrop(Size(width: 600, height: 400)) == crop(0, 0, 1800, 1200))
    }

    /// A box larger than the photograph takes the photograph's own pixels, not more.
    @Test func neverEnlarged() {
        // 600 × (1206 / 1572) = 460.3, so 460 wide, centred in 800
        #expect(Size(width: 800, height: 600).fillCrop(Size(width: 1206, height: 1572)) == crop(170, 0, 460, 600))
    }

    /// The corner sits on a whole pixel, so the sharp photograph is drawn at its own pixels, not half a pixel off.
    @Test func wholePixelOrigin() {
        #expect(Size(width: 1001, height: 1000).fillCrop(Size(width: 100, height: 100)) == crop(0, 0, 1000, 1000))
        #expect(Size(width: 1000, height: 1003).fillCrop(Size(width: 100, height: 100)) == crop(0, 1, 1000, 1000))
    }

    @Test func emptyIsNil() {
        #expect(Size(width: 0, height: 1200).fillCrop(Size(width: 400, height: 500)) == nil)
        #expect(Size(width: 1800, height: 1200).fillCrop(Size(width: 400, height: 0)) == nil)
    }
}

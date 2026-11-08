import Testing
@testable import TripKit

@Suite struct HeroFootTests {
    /// a Commons landscape's veil: 160 px on its longest side
    let landscape = DecodePlan.Size(width: 160, height: 107)
    /// a portrait photo's veil
    let portrait = DecodePlan.Size(width: 120, height: 160)

    private func near(_ a: Double, _ b: Double, _ tolerance: Double = 1e-6) -> Bool { abs(a - b) <= tolerance }

    // MARK: Where the backdrop goes

    @Test func aLandscapeInAPortraitHeroSitsOnTheFootsBottom() throws {
        // the plain place page: a 402 × 440 hero, a foot of 193 points; the photo fills the hero's height, so the
        // bottom of the backdrop is the bottom of the foot, which a bitmap context counts as y = 0
        let layout = try #require(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: 440, foot: 193))
        let ky = Double(layout.canvas.height) / 193
        #expect(near(layout.draw.y, 0))
        #expect(near(layout.draw.height, 440 * ky))
        // centred across, as scaledToFill lays the photo
        #expect(near(layout.draw.x + layout.draw.width / 2, Double(layout.canvas.width) / 2))
        #expect(layout.draw.x < 0)
    }

    @Test func aPortraitInAWideHeroOverflowsHalfItsExcessBelow() throws {
        // the photo fills the hero's width and is cut as much at the top as at the bottom: 536 points tall in a
        // 440 point hero, 48 points below its bottom
        let layout = try #require(HeroFoot.layout(backdrop: portrait, heroWidth: 402, heroHeight: 440, foot: 193))
        let ky = Double(layout.canvas.height) / 193
        let kx = Double(layout.canvas.width) / 402
        #expect(near(layout.draw.y, -48 * ky))
        #expect(near(layout.draw.height, 536 * ky))
        #expect(near(layout.draw.x, 0))
        #expect(near(layout.draw.width, 402 * kx))
    }

    @Test func aFootTallerThanTheHeroLeavesTheBandAboveItEmpty() throws {
        // very large type: the foot rises 60 points above the hero's top, where there is no photo
        let layout = try #require(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: 440, foot: 500))
        let ky = Double(layout.canvas.height) / 500
        #expect(near(layout.draw.y, 0))
        #expect(near(Double(layout.canvas.height) - (layout.draw.y + layout.draw.height), 60 * ky))
    }

    @Test func theFootIsTheBottomOfTheSameFillAsTheWholeHero() throws {
        // the foot that is the whole hero draws the backdrop where AmbientFrame.fill puts it in the hero
        let layout = try #require(HeroFoot.layout(backdrop: portrait, heroWidth: 402, heroHeight: 440, foot: 440))
        let kx = Double(layout.canvas.width) / 402, ky = Double(layout.canvas.height) / 440
        let fill = AmbientFrame.fill(portrait, into: DecodePlan.Size(width: 402, height: 440))
        #expect(near(layout.draw.x, fill.x * kx))
        #expect(near(layout.draw.width, fill.width * kx))
        #expect(near(layout.draw.height, fill.height * ky))
        // centred both ways, so here the top-left and the bottom-left rectangles agree
        #expect(near(layout.draw.y, fill.y * ky))
    }

    // MARK: The canvas

    @Test func theCanvasIsTheBackdropsOwnPixelsBehindTheFoot() throws {
        // 4.112 points to a backdrop pixel: 402 × 193 points are 98 × 47 of its pixels
        let layout = try #require(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: 440, foot: 193))
        #expect(layout.canvas == DecodePlan.Size(width: 98, height: 47))
    }

    @Test func aLargeBackdropInASmallFootIsNeverUpsampled() throws {
        // a 1600 × 1200 picture in a 200 × 100 hero: 8 of its pixels to the point, and no more
        let backdrop = DecodePlan.Size(width: 1600, height: 1200)
        let layout = try #require(HeroFoot.layout(backdrop: backdrop, heroWidth: 200, heroHeight: 100, foot: 80))
        #expect(Double(layout.canvas.width) / 200 <= 8)
        #expect(Double(layout.canvas.height) / 80 <= 8 + 1e-9)
        #expect(layout.canvas.width <= backdrop.width)
        #expect(layout.canvas == DecodePlan.Size(width: 1600, height: 640))
    }

    @Test func noSideOfTheCanvasIsLongerThanTheBackdrops() throws {
        // a foot twenty times the hero's height would ask for more rows than the backdrop has
        let backdrop = DecodePlan.Size(width: 40, height: 30)
        let layout = try #require(HeroFoot.layout(backdrop: backdrop, heroWidth: 400, heroHeight: 100, foot: 2000))
        #expect(max(layout.canvas.width, layout.canvas.height) <= 40)
        #expect(layout.canvas.width >= 1 && layout.canvas.height >= 1)
    }

    @Test func aTinyFootStillHasAPixel() throws {
        let layout = try #require(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: 440, foot: 0.5))
        #expect(layout.canvas.height == 1)
    }

    @Test func nothingToDrawIsNone() {
        #expect(HeroFoot.layout(backdrop: DecodePlan.Size(width: 0, height: 107), heroWidth: 402, heroHeight: 440, foot: 193) == nil)
        #expect(HeroFoot.layout(backdrop: landscape, heroWidth: 0, heroHeight: 440, foot: 193) == nil)
        #expect(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: 0, foot: 193) == nil)
        #expect(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: 440, foot: 0) == nil)
        #expect(HeroFoot.layout(backdrop: landscape, heroWidth: .nan, heroHeight: 440, foot: 193) == nil)
        #expect(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: .infinity, foot: 193) == nil)
        #expect(HeroFoot.layout(backdrop: landscape, heroWidth: 402, heroHeight: 440, foot: -1) == nil)
    }

    // MARK: The look

    @Test func theRiseIsTheOldMask() {
        #expect(HeroFoot.rise == [AmbientFrame.Stop(shown: 0, at: 0), AmbientFrame.Stop(shown: 0.7, at: 0.45),
                                  AmbientFrame.Stop(shown: 1, at: 1)])
    }

    @Test func theShadeIsDeeperWithNothingUnderIt() {
        #expect(HeroFoot.shade(backdrop: true) == 0.42)
        #expect(HeroFoot.shade(backdrop: false) == 0.55)
    }
}

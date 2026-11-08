import Testing
@testable import TripKit

/// Where a detail page's photograph ends and when the bar takes the title (the app's `detailPage`): the old
/// `settle()` rule (scrolled past 0 and past the photograph's end less 130 pt), with the album pages' photograph
/// measured as `containerRelativeFrame` sizes it (ruling R-248).
@Suite struct HeroEdgeTests {
    /// A fixed photograph (the plain place page's 440 pt): the bar takes the title once 130 pt of it are left.
    @Test func fixedHeightTakesTheBarNearItsEnd() {
        #expect(HeroEdge(height: 440, offset: 0, insetTop: 0).bottom == 440)
        #expect(!HeroEdge(height: 440, offset: 310, insetTop: 0).past)
        #expect(HeroEdge(height: 440, offset: 311, insetTop: 0).past)
    }

    /// The distance scrolled is the offset plus the top inset: at rest the offset is minus the inset.
    @Test func scrolledCountsTheTopInset() {
        #expect(!HeroEdge(height: 440, offset: 251, insetTop: 59).past)
        #expect(HeroEdge(height: 440, offset: 252, insetTop: 59).past)
        #expect(!HeroEdge(height: 440, offset: -59, insetTop: 59).past)
    }

    /// At the top, never, however short the photograph; nor while the page is pulled down past the top.
    @Test func neverAtTheTop() {
        #expect(!HeroEdge(height: 100, offset: 0, insetTop: 0).past)
        #expect(HeroEdge(height: 100, offset: 1, insetTop: 0).past)
        #expect(!HeroEdge(height: 440, offset: -80, insetTop: 0).past)
        #expect(!HeroEdge(fraction: 0.1, containerHeight: 874, insetTop: 62, insetBottom: 34, offset: -62).past)
    }

    /// An album page's photograph: the scroll view's height less both insets, times the fraction, rounded as the
    /// page rounds it (874 − 62 − 34 = 778; × 0.6 = 466.8, so 467).
    @Test func fractionIsMeasuredLikeTheFrame() {
        let rest = HeroEdge(fraction: 0.6, containerHeight: 874, insetTop: 62, insetBottom: 34, offset: -62)
        #expect(rest.bottom == 467)
        #expect(!rest.past)
        #expect(!HeroEdge(fraction: 0.6, containerHeight: 874, insetTop: 62, insetBottom: 34, offset: 275).past)
        #expect(HeroEdge(fraction: 0.6, containerHeight: 874, insetTop: 62, insetBottom: 34, offset: 276).past)
    }

    /// Both insets come off before the fraction is taken, and the height is rounded to the nearest point, halves up.
    @Test func fractionRounding() {
        #expect(HeroEdge(fraction: 0.5, containerHeight: 900, insetTop: 50, insetBottom: 50, offset: 0).bottom == 400)
        #expect(HeroEdge(fraction: 0.5, containerHeight: 1001, insetTop: 0, insetBottom: 0, offset: 0).bottom == 501)
        #expect(HeroEdge(fraction: 0.56, containerHeight: 845, insetTop: 0, insetBottom: 0, offset: 0).bottom == 473)
    }

    /// Once measured, a share of the page is judged like a fixed photograph of that height.
    @Test func fractionMatchesFixed() {
        for offset in [-62.0, 0, 200, 275, 276, 600] {
            let share = HeroEdge(fraction: 0.6, containerHeight: 874, insetTop: 62, insetBottom: 34, offset: offset)
            #expect(share == HeroEdge(height: 467, offset: offset, insetTop: 62))
        }
    }
}

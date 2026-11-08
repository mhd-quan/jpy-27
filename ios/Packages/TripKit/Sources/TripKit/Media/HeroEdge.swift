import Foundation

/// Where a detail page's photograph ends, and whether the page has scrolled past it (the app's `detailPage`): the
/// bar shows no title and no edge over the photograph, and takes both once the photograph is nearly gone.
///
/// Judged whole from one reading of the scroll view's geometry, nothing kept from the reading before, so a page
/// still zooming open is judged on the height it lands at.
public struct HeroEdge: Equatable, Sendable {
    /// how far down the page's content the photograph ends
    public let bottom: Double
    /// the bar takes the title and its soft edge: the photograph has scrolled to within `margin` of its end
    public let past: Bool

    /// how much of the photograph is left when the bar takes the title
    public static let margin: Double = 130

    /// A photograph of a fixed height. `offset` and `insetTop` are the scroll view's content offset and top
    /// content inset: the distance scrolled is their sum.
    public init(height: Double, offset: Double, insetTop: Double) {
        let scrolled = offset + insetTop
        bottom = height
        // at the top, never: a photograph shorter than the margin would otherwise count as gone at rest
        past = scrolled > 0 && scrolled > height - Self.margin
    }

    /// A photograph that takes `fraction` of the page's height, sized as `containerRelativeFrame` sizes it: the
    /// scroll view's height less its top and bottom content insets, times the fraction, rounded to a whole point
    /// as the page rounds its photograph.
    public init(fraction: Double, containerHeight: Double, insetTop: Double, insetBottom: Double, offset: Double) {
        let height = ((containerHeight - insetTop - insetBottom) * fraction).rounded()
        self.init(height: height, offset: offset, insetTop: insetTop)
    }
}

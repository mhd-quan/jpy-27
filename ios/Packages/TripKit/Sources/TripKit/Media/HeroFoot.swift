import Foundation

/// The foot of a detail page's hero, where its name sits: a blurred copy of what is above it (a photograph's veil, or a
/// picture of its own) rising softly from nothing, with a shade for white type. The blur is not live: the part of the
/// backdrop behind the foot is drawn once into a small picture with the rise already in its alpha, so the zoom and the
/// scroll move a finished picture, with no material and no mask. Here: where that part is, how large the picture is,
/// and the rise and the shade.
public enum HeroFoot {
    /// How much of the backdrop shows (`shown`, 0 to 1) from the foot's top (`at` 0) to its bottom (1): the gradient
    /// the old material was masked with.
    public static let rise: [AmbientFrame.Stop] = [
        AmbientFrame.Stop(shown: 0, at: 0),
        AmbientFrame.Stop(shown: 0.7, at: 0.45),
        AmbientFrame.Stop(shown: 1, at: 1),
    ]

    /// The black at the foot's bottom, from clear at its top, laid over the backdrop: deeper when there is none, with
    /// no blur under the type.
    public static func shade(backdrop: Bool) -> Double {
        backdrop ? 0.42 : 0.55
    }

    /// A photograph's veil and the photograph it is of (its src): one that arrived, or the last one shown.
    public struct Kept<Image> {
        public let src: String
        public let image: Image

        public init(src: String, image: Image) {
            self.src = src
            self.image = image
        }
    }

    /// What is under the name, in this order: nothing with Reduce Transparency; the page's own picture
    /// (`backdrop`), which wins; nothing without a photograph (`veil`, its src); the veil that arrived for this
    /// photograph (`held`); the veil in memory (`cached`); the last veil shown for this photograph (`kept`), so memory
    /// letting the veil go while the page is open leaves it under the name. A veil of another photograph is never
    /// shown.
    public static func under<Image>(reduceTransparency: Bool, backdrop: Image?, veil: String?, held: Kept<Image>?,
                                    cached: Image?, kept: Kept<Image>?) -> Image? {
        if reduceTransparency { return nil }
        if let backdrop { return backdrop }
        guard let veil else { return nil }
        if let held, held.src == veil { return held.image }
        if let cached { return cached }
        if let kept, kept.src == veil { return kept.image }
        return nil
    }

    /// Whether the photograph's veil is derived now (background work): not in Low Power Mode, not with Reduce
    /// Transparency (none is shown), only for a photograph, not when the page's own picture is under the name, and
    /// not when memory has it already.
    public static func derivesVeil(lowPower: Bool, reduceTransparency: Bool, hasVeil: Bool, hasBackdrop: Bool,
                                   cached: Bool) -> Bool {
        !lowPower && !reduceTransparency && hasVeil && !hasBackdrop && !cached
    }

    /// The foot's picture: its size in pixels, and where the whole backdrop is drawn in it.
    public struct Layout: Equatable, Sendable {
        /// in pixels; the picture is shown stretched over the foot
        public let canvas: DecodePlan.Size
        /// the whole backdrop, in the canvas's pixels and a bitmap context's coordinates (origin at the bottom left)
        public let draw: AmbientFrame.Rect
    }

    /// The foot's picture for a backdrop of `backdrop` pixels under a hero of `heroWidth` × `heroHeight` points whose
    /// foot is its bottom `foot` points (the foot is as wide as the hero, and may rise above its top).
    ///
    /// The backdrop fills the whole hero as the photograph does (`AmbientFrame.fill`: covering it, centred), so the
    /// blur under the name is of the part of the photograph just above it; the picture is the bottom `foot` points of
    /// that, and nothing where the foot rises above the hero. It has the backdrop's own pixels per point, never more
    /// (never upsampled), and no side longer than the backdrop's longest: a 160 px veil gives at most 160 px a side.
    /// Nil when a size is not finite or there is nothing to draw.
    public static func layout(backdrop: DecodePlan.Size, heroWidth: Double, heroHeight: Double, foot: Double) -> Layout? {
        let sizes = [heroWidth, heroHeight, foot]
        guard backdrop.width >= 1, backdrop.height >= 1,
              sizes.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 100_000 }) else { return nil }
        // the hero in whole points, as the photograph's fill is laid out in it (at least one point)
        let hero = DecodePlan.Size(width: max(1, Int(heroWidth.rounded())), height: max(1, Int(heroHeight.rounded())))
        let heroW = Double(hero.width), heroH = Double(hero.height)
        let fill = AmbientFrame.fill(backdrop, into: hero)
        // backdrop pixels per point, as the fill scales it, and never more than its longest side over the picture's
        let scale = fill.width / Double(backdrop.width)
        let density = min(1 / scale, Double(backdrop.longest) / max(heroW, foot))
        let width = min(backdrop.longest, max(1, Int((heroW * density).rounded())))
        let height = min(backdrop.longest, max(1, Int((foot * density).rounded())))
        // each axis at its own rounding, as the picture is stretched over the foot
        let kx = Double(width) / heroW, ky = Double(height) / foot
        // the fill's top from the foot's top: the foot covers the hero's bottom `foot` points
        let top = fill.y - (heroH - foot)
        let bottom = foot - (top + fill.height)
        return Layout(canvas: DecodePlan.Size(width: width, height: height),
                      draw: AmbientFrame.Rect(x: fill.x * kx, y: bottom * ky, width: fill.width * kx, height: fill.height * ky))
    }
}

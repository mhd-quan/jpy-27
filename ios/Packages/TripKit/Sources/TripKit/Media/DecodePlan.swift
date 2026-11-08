/// Which decode of a photo the app's photo cache (`PhotoCache`) can draw where a view asks for the photo at a size,
/// instead of decoding it again. An ask is a longest side in pixels (ImageIO's `kCGImageSourceThumbnailMaxPixelSize`); a
/// decode is kept under the size it came out at, so asks that come out the same share it: the bundled Commons WebP
/// is 800 px, so the home's day card (1200) and the day page (1800) both get those 800 px, from one decode.
public enum DecodePlan {
    /// A decode's size in pixels.
    public struct Size: Hashable, Sendable {
        public var width: Int
        public var height: Int

        public init(width: Int, height: Int) {
            self.width = width
            self.height = height
        }

        /// what an ask is measured against
        public var longest: Int { max(width, height) }
    }

    /// Whether `decoded` can be drawn where a view asks for `maxPixel`. The whole photo serves every ask: a larger one
    /// would decode to the same pixels, and a smaller one, drawn from it, costs one decode less. A smaller copy serves
    /// only asks it is at most twice as large as: never enlarged, and not drawn so far down that drawing it costs more
    /// than a decode of its own.
    public static func serves(decoded: Size, sourceIsFull: Bool, asked maxPixel: Int) -> Bool {
        sourceIsFull || (decoded.longest >= maxPixel && decoded.longest <= 2 * maxPixel)
    }

    /// Whether a decode asked at `maxPixel` is the whole photo. ImageIO never enlarges, so one smaller than asked is the
    /// source itself; one exactly the ask may be a larger source cut down, and counts as a copy.
    public static func isFull(decoded: Size, asked maxPixel: Int) -> Bool {
        decoded.longest < maxPixel
    }
}

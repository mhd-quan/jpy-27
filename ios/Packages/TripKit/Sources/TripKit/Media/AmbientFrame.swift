import Foundation

/// An album page's photograph as the app draws it (`PhotoCache.ambient`): one picture made once, its blurred copy (the
/// veil) filling the hero and the sharp photo over it fading out from the middle down, so the zoom, a swipe and a scroll
/// move a finished picture. The picture has the hero's shape at the photo's own pixels, and is kept in memory and on disk
/// under the photo and the hero's size. The hero's height is a share of its page (`heroHeight`): the page's frame, the
/// bar's threshold over it and a prefetch of the picture all read it from here, so all three agree.
public enum AmbientFrame {
    /// A hero's height in points: `fraction` of its container's `length` (the container less the safe-area insets
    /// applied to it, as SwiftUI's `containerRelativeFrame` measures it), rounded to the point, halves up.
    public static func heroHeight(length: Double, fraction: Double) -> Double {
        (length * fraction).rounded()
    }

    /// The hero's size in whole points, as its picture is named.
    public struct Frame: Hashable, Sendable {
        public let width: Int
        public let height: Int

        /// Rounded to the point, halves up; nil when a side is not finite or rounds below one point.
        public init?(width: Double, height: Double) {
            guard width.isFinite, height.isFinite, width < 100_000, height < 100_000 else { return nil }
            let w = Int(width.rounded()), h = Int(height.rounded())
            guard w >= 1, h >= 1 else { return nil }
            self.width = w
            self.height = h
        }
    }

    /// The picture's size in pixels for a photo of `source` pixels in `frame`: the frame's shape at the photo's own
    /// pixels, never larger. The side that limits the photo is its whole side; the other is what the frame shows of it.
    /// A landscape photo in a portrait hero keeps its height and is cut at the sides, as the hero cuts it, instead of
    /// being enlarged to its width. Nil for a photo with no pixels.
    public static func canvas(source: DecodePlan.Size, frame: Frame) -> DecodePlan.Size? {
        guard source.width >= 1, source.height >= 1 else { return nil }
        let shape = Double(frame.width) / Double(frame.height)
        let width = min(Double(source.width), Double(source.height) * shape)
        let height = width / shape
        return DecodePlan.Size(width: min(source.width, max(1, Int(width.rounded()))),
                               height: min(source.height, max(1, Int(height.rounded()))))
    }

    /// A rectangle in a picture's pixels.
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// Where an image of `image` pixels goes to fill `canvas`, as SwiftUI's `scaledToFill` in a centred frame lays it:
    /// scaled to cover it, its shape kept, as much cut from each side. Centred both ways, so it is the same rectangle
    /// whether the picture counts from its top or its bottom.
    public static func fill(_ image: DecodePlan.Size, into canvas: DecodePlan.Size) -> Rect {
        let cw = Double(canvas.width), ch = Double(canvas.height)
        let scale = max(cw / Double(image.width), ch / Double(image.height))
        let w = Double(image.width) * scale, h = Double(image.height) * scale
        return Rect(x: (cw - w) / 2, y: (ch - h) / 2, width: w, height: h)
    }

    /// How much of the sharp photo shows (`shown`, 1 to 0) at each point from the top of the hero (`at` 0) to its
    /// bottom (1); the veil under it takes over, then the page's colour (the hero's dissolve). Below the last stop
    /// nothing of it shows.
    public struct Stop: Equatable, Sendable {
        public let shown: Double
        public let at: Double
    }

    /// The fade of the sharp photo into its veil: drawn into the picture, and the mask of the photo when there is no
    /// veil (Reduce Transparency).
    public static let fade: [Stop] = [
        Stop(shown: 1, at: 0),
        Stop(shown: 1, at: 0.48),
        Stop(shown: 0.65, at: 0.62),
        Stop(shown: 0.2, at: 0.76),
        Stop(shown: 0, at: 0.86),
    ]

    /// The recipe the pictures on disk were made by: the layers, the fade, the veil, the size rule. A change to any of
    /// them takes the next number, so a picture made the old way is never read again (the trim lets it go).
    public static let recipe = 1

    /// The picture's name in memory: the photo and the hero in whole points.
    public static func key(src: String, frame: Frame) -> String {
        "\(src)@amb@\(frame.width)x\(frame.height)"
    }

    /// The picture's file: FNV-1a 64 of the recipe and the key, in base 36, ".jpg". The same on every launch (Swift's
    /// `Hasher` is seeded per launch) and safe in a path (a src has "/" and ":").
    public static func fileName(key: String) -> String {
        fileName(key: key, recipe: recipe)
    }

    static func fileName(key: String, recipe: Int) -> String {
        var h = FNV1a()
        h.word(UInt64(truncatingIfNeeded: recipe))
        h.text(key)
        return String(h.value, radix: 36) + ".jpg"
    }

    /// Whether a name in the pictures' folder is one of the pictures (`fileName`): anything else there, a write still
    /// under way included, is neither counted nor deleted.
    public static func isPicture(_ name: String) -> Bool {
        guard name.hasSuffix(".jpg") else { return false }
        let stem = name.dropLast(4)
        return !stem.isEmpty && stem.allSatisfy { ("0"..."9").contains($0) || ("a"..."z").contains($0) }
    }

    /// A file in the pictures' folder: its size, and when it was last read or written.
    public struct StoredFile: Hashable, Sendable {
        public var name: String
        public var bytes: Int
        public var used: Date

        public init(name: String, bytes: Int, used: Date) {
            self.name = name
            self.bytes = bytes
            self.used = used
        }
    }

    /// The pictures to delete so the rest fit in `budget` bytes, sorted: the least recently used first, ties by name,
    /// while the pictures are over the budget. Only pictures (`isPicture`) count and go.
    public static func evicted(_ files: [StoredFile], toBytes budget: Int) -> [String] {
        let pictures = files.filter { isPicture($0.name) }
        var total = pictures.reduce(0) { $0 + $1.bytes }
        var out: [String] = []
        for file in pictures.sorted(by: { ($0.used, $0.name) < ($1.used, $1.name) }) where total > budget {
            out.append(file.name)
            total -= file.bytes
        }
        return out.sorted()
    }
}

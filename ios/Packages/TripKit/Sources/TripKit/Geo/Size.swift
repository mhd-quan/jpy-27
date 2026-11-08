import Foundation

/// A width and a height in points: a picture's, a view's. TripKit stays free of CoreGraphics.
public struct Size: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// Where the point (x, y) of a picture of this size lands when the picture fills `box` as SwiftUI's
    /// `scaledToFill()` lays it out: scaled to cover the box, centred, the overflow cropped. A map's stops are
    /// drawn over its picture this way (`SnapshotPin` in the app), so they stay on their places when the picture
    /// was drawn at another size than the one it is shown at.
    public func point(_ x: Double, _ y: Double, filling box: Size) -> (x: Double, y: Double) {
        guard width > 0, height > 0 else { return (x, y) }
        let scale = max(box.width / width, box.height / height)
        return (x * scale - (width * scale - box.width) / 2, y * scale - (height * scale - box.height) / 2)
    }
}

extension Size {
    /// A part of a picture, in its own pixels: x right and y down from its top-left corner.
    public struct Crop: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var size: Size

        public init(x: Double, y: Double, size: Size) {
            self.x = x
            self.y = y
            self.size = size
        }
    }

    /// The part of a picture of this size (in pixels) that shows when it fills a box of `frame`'s shape as
    /// SwiftUI's `scaledToFill()` lays it out: centred, the overflow cropped. In whole pixels and at the picture's
    /// own scale, never enlarged: an album page's picture (the app's `PhotoCache.ambient`) is composed from exactly
    /// this part, so its sharp photograph keeps its own pixels. nil for an empty picture or box.
    public func fillCrop(_ frame: Size) -> Crop? {
        guard width > 0, height > 0, frame.width > 0, frame.height > 0 else { return nil }
        let aspect = frame.width / frame.height
        // as wide as the box's shape allows at the picture's full height, or the full width
        let exact = min(width, height * aspect)
        let w = min(width, max(1, exact.rounded()))
        let h = min(height, max(1, (exact / aspect).rounded()))
        return Crop(x: ((width - w) / 2).rounded(.down), y: ((height - h) / 2).rounded(.down), size: Size(width: w, height: h))
    }
}

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

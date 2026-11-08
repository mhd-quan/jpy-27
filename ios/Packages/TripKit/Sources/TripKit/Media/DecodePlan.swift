import Foundation

/// Which decode of a photo, already in memory, serves a view's ask: the app's photo cache (`PhotoCache.cached`)
/// asks this of every decode it holds for the photo before it decodes again.
///
/// An ask is a long edge in pixels (ImageIO's thumbnail size). A decode is drawn for an ask when it holds enough
/// pixels for it (no upscale) and not more than twice as many along an edge (drawing a bitmap many times the size
/// it is shown at costs more on every frame than a decode of its own). The whole photo, decoded because the
/// source was smaller than the ask, is what any larger ask would decode too, so it serves every larger ask.
public enum DecodePlan {
    /// - Parameters:
    ///   - decoded: the decoded bitmap's size in pixels (a portrait photo counts by its height)
    ///   - sourceIsFull: the bitmap is the whole source: its long edge is the source's own
    ///   - maxPixel: the long edge asked for
    public static func serves(decoded: Size, sourceIsFull: Bool, asked maxPixel: Int) -> Bool {
        let edge = max(decoded.width, decoded.height)
        let asked = Double(maxPixel)
        guard edge <= 2 * asked else { return false }
        return sourceIsFull || edge >= asked
    }
}

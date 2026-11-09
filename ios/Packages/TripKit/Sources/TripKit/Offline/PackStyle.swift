import Foundation

/// The style an offline pack is made from. A pack names its style by URL, and MapLibre downloads that URL
/// before anything else; the app stores its own style there first (`MLNOfflineStorage.preloadData`), so the
/// URL is only a key: nobody needs to answer it, and the pack never asks the network for its style.
///
/// - Pinned build: the bundled bytes as they are, under the name the bundled style gives itself
///   (`metadata["jp27:build"]`). Earlier builds made their packs from the site's copy under that same URL,
///   which was these very bytes.
/// - The map on OpenFreeMap's current build (`currentTemplate`): the bundled style pointed at that build
///   (`StyleInfo.pointing`), under a key of its template, so two templates never share a URL.
///
/// The build a pack is tagged with (`PackTag`) is read from the bytes stored, not from what was asked.
public enum PackStyle {
    /// Where the keys live: the site's map folder, which earlier builds downloaded the style from.
    public static let base = "https://jpy27.delphyra.tech/map/"

    /// A style ready to store: its key, its bytes, and the tile build they hold.
    public struct Prepared: Sendable, Equatable {
        public let url: String
        public let style: Data
        public let build: TileBuild

        public init(url: String, style: Data, build: TileBuild) {
            self.url = url
            self.style = style
            self.build = build
        }
    }

    /// The style a pack is made from for the build the map reads: OpenFreeMap's current one when
    /// `currentTemplate` is set (it wins: that is what the map reads), else the pinned one, named
    /// `pinnedName`. Nil when there is nothing to store: no name and no template, a bundled style that is
    /// not one, or bytes that hold no tile build.
    public static func prepare(bundled: Data, pinnedName: String?, currentTemplate: String?) -> Prepared? {
        if let template = currentTemplate {
            guard let style = StyleInfo.pointing(style: bundled, at: template), let build = StyleInfo.build(style: style) else { return nil }
            return Prepared(url: base + "jp27-light@current-" + key(of: template) + ".json", style: style, build: build)
        }
        guard let name = pinnedName, let build = StyleInfo.build(style: bundled) else { return nil }
        return Prepared(url: base + "jp27-light@" + name + ".json", style: bundled, build: build)
    }

    /// A template's key: FNV-1a, 64 bits, over its UTF-8 bytes, as 16 lowercase hex digits. The same on
    /// every launch and every device (`Hasher` is seeded anew at each launch).
    public static func key(of template: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in template.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }
}

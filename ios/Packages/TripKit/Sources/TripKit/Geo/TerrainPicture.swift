import Foundation

/// A picture of the 3D terrain round Fuji: `FujiTerrainSnapshot` in the app, drawn once by MapKit's
/// snapshotter and kept in `Caches/Fuji`. This file holds four things.
///
/// - Its name: the kind of shot (a day's area or one viewpoint), the size, the scale and the scheme.
/// - The fingerprint stored beside it: the camera and the points it projects. A picture whose fingerprint
///   differs is a miss, drawn again under the same name.
/// - The launch trim.
/// - When the live map goes under the picture and the picture comes off it.
///
/// The snapshotter draws neither pins nor lines. The app draws them over the picture, at the points the
/// snapshot projected for them, which the `.json` beside the picture keeps:
/// `<stem>.heic` (or `.jpg`) and `<stem>.json`.
public enum TerrainPicture {
    /// Bumped when the app draws the picture differently (its map configuration, what it projects): every
    /// picture kept until then becomes a miss.
    public static let recipe = 1

    /// What a picture is of.
    public enum Kind: String, Hashable, Sendable {
        /// a day's area, or the whole region
        case area
        /// one viewpoint, seen from behind it
        case spot
    }

    /// Where the camera stands: what the picture's pixels depend on, with the size, scale and scheme in the
    /// name.
    public struct Camera: Hashable, Sendable {
        public var center: Coordinate
        /// metres from the camera to `center`
        public var distance: Double
        public var heading: Double
        public var pitch: Double

        public init(center: Coordinate, distance: Double, heading: Double, pitch: Double) {
            self.center = center
            self.distance = distance
            self.heading = heading
            self.pitch = pitch
        }
    }

    /// A viewpoint whose pin and line of sight the picture's points place.
    public struct Spot: Hashable, Sendable {
        public var id: String
        public var coordinate: Coordinate

        public init(id: String, coordinate: Coordinate) {
            self.id = id
            self.coordinate = coordinate
        }
    }

    // MARK: Names

    /// The shot's own name, `<kind>-<id>` (the id made safe, `SnapshotKey.fileSafe`): the start of its pictures'
    /// stems, and the key of the blurred copy under a hero's name.
    public static func name(kind: Kind, id: String) -> String {
        "\(kind.rawValue)-\(SnapshotKey.fileSafe(id))"
    }

    /// `<kind>-<id>-<w>x<h>@<scale>-<light|dark>`: the size in whole points; the scale whole ("3") or to two
    /// places ("2.5", "2.63"). Nil for a size under a point, a scale of nothing, or anything not finite.
    public static func stem(kind: Kind, id: String, width: Double, height: Double, scale: Double, dark: Bool) -> String? {
        guard width.isFinite, height.isFinite, scale.isFinite else { return nil }
        let w = width.rounded(), h = height.rounded()
        let hundredths = (scale * 100).rounded()
        guard w >= 1, h >= 1, hundredths >= 1, w < 100_000, h < 100_000, hundredths < 100_000 else { return nil }
        return "\(name(kind: kind, id: id))-\(Int(w))x\(Int(h))@\(scaleText(Int(hundredths)))-\(dark ? "dark" : "light")"
    }

    /// 300 → "3", 250 → "2.5", 263 → "2.63"
    private static func scaleText(_ hundredths: Int) -> String {
        let whole = hundredths / 100, part = hundredths % 100
        if part == 0 { return "\(whole)" }
        if part % 10 == 0 { return "\(whole).\(part / 10)" }
        return "\(whole).\(part < 10 ? "0" : "")\(part)"
    }

    /// A file of this cache, read back from the folder's listing.
    public struct FileName: Hashable, Sendable {
        public let stem: String
        /// "heic" or "jpg" (the picture), "json" (its points and fingerprint)
        public let ext: String
    }

    /// The names `stem` makes, with one of this cache's extensions; nil for any other name (a write still under
    /// way among them), which the cache neither counts nor deletes.
    public static func parse(_ name: String) -> FileName? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let ext = String(name[name.index(after: dot)...])
        guard ext == "heic" || ext == "jpg" || ext == "json" else { return nil }
        let stem = String(name[..<dot])
        var rest = Substring(stem)
        guard let kind = ["area-", "spot-"].first(where: { rest.hasPrefix($0) }) else { return nil }
        rest = rest.dropFirst(kind.count)
        guard let scheme = ["-light", "-dark"].first(where: { rest.hasSuffix($0) }) else { return nil }
        rest = rest.dropLast(scheme.count)
        guard let dash = rest.lastIndex(of: "-") else { return nil }
        let id = rest[..<dash]
        let size = rest[rest.index(after: dash)...]
        guard !id.isEmpty, id.allSatisfy(isSafe), isSize(size) else { return nil }
        return FileName(stem: stem, ext: ext)
    }

    /// what `SnapshotKey.fileSafe` leaves in an id
    private static func isSafe(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_")
    }

    /// `<digits>x<digits>@<digits>[.<digits>]`
    private static func isSize(_ s: Substring) -> Bool {
        let digits: (Substring) -> Bool = { !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }
        guard let x = s.firstIndex(of: "x"), let at = s.firstIndex(of: "@"), x < at else { return false }
        let scale = s[s.index(after: at)...].split(separator: ".", omittingEmptySubsequences: false)
        guard scale.count == 1 || scale.count == 2 else { return false }
        return digits(s[..<x]) && digits(s[s.index(after: x)..<at]) && scale.allSatisfy(digits)
    }

    // MARK: Fingerprint

    /// FNV-1a 64 in base 36 of what places the picture and its points: the recipe, the camera, the summit and the
    /// viewpoints, which are sorted by id, so their order does not count. Kept in the picture's `.json`: a picture
    /// read back serves only with the same fingerprint, so a trip data update (a viewpoint added or moved, and with
    /// it the area's camera) or a new way of drawing it never shows a stale picture with missing pins.
    public static func fingerprint(camera: Camera, summit: Coordinate, spots: [Spot], recipe: Int = recipe) -> String {
        var h = FNV1a()
        h.word(UInt64(truncatingIfNeeded: recipe))
        for d in [camera.center.lat, camera.center.lng, camera.distance, camera.heading, camera.pitch, summit.lat, summit.lng] {
            h.number(d)
        }
        h.word(UInt64(spots.count))
        for s in spots.sorted(by: { $0.id < $1.id }) {
            h.text(s.id)
            h.number(s.coordinate.lat)
            h.number(s.coordinate.lng)
        }
        return String(h.value, radix: 36)
    }

    // MARK: The folder

    /// A file in the folder as listed: its size and its last use (the modification date, which a read touches).
    public typealias StoredFile = SnapshotKey.StoredFile

    /// The names to delete so the folder's pictures fit in `budget` bytes, sorted. A picture and its `.json` go
    /// together, counted as one, its use the newer of the two; the least recently used first, ties by stem, while
    /// over the budget. A name the cache did not make (`parse`) is neither counted nor deleted.
    public static func evicted(_ files: [StoredFile], toBytes budget: Int) -> [String] {
        // the rule `MapSnapshots` trims by, with this cache's names
        SnapshotKey.evictedPairs(files, toBytes: budget) { parse($0)?.stem }
    }

    // MARK: Picture and live map

    /// What covers the live map, or stands in for it.
    public enum Cover: Hashable, Sendable {
        /// the picture, with its pins and lines
        case picture
        /// no picture and no network: the viewpoints round the summit by bearing and distance
        case plot
        /// no picture yet: the plain ground the picture or the live map comes in over
        case placeholder
    }

    /// How long the cover stays over a live map just mounted: a SwiftUI `Map` says nothing when it has drawn
    /// itself.
    public static let beat: Duration = .milliseconds(800)

    /// The live map is mounted once the page has come on screen and the network is steady, never inside the
    /// transition; once mounted it stays while the view lives, whatever the network does next.
    public static func mounts(mounted: Bool, settled: Bool, online: Bool) -> Bool {
        mounted || (settled && online)
    }

    /// The cover: none once lifted; else the picture, but over a live map only if a picture was the cover when it was
    /// mounted (`pictureAtMount`; any value while not mounted); else, with no live map and no network, the plot; else
    /// the placeholder, until the beat lifts it. A picture finished in the background during the beat (a first visit
    /// online) waits for the next visit: one fade, the placeholder's at the lift, not the picture's and then its own.
    public static func cover(picture: Bool, pictureAtMount: Bool, mounted: Bool, lifted: Bool, online: Bool) -> Cover? {
        if lifted { return nil }
        if picture && (!mounted || pictureAtMount) { return .picture }
        if !mounted && !online { return .plot }
        return .placeholder
    }

    /// The beat runs, and the cover lifts when it ends, only over a mounted live map while online: offline the
    /// live map may have nothing to show under it.
    public static func beats(mounted: Bool, lifted: Bool, online: Bool) -> Bool {
        mounted && !lifted && online
    }

    /// A picture is drawn (background work: the snapshotter loads its tiles) only once the page has come on screen,
    /// with a steady network, out of Low Power Mode. One already made is shown in any case.
    public static func draws(settled: Bool, online: Bool, lowPower: Bool) -> Bool {
        settled && online && !lowPower
    }
}

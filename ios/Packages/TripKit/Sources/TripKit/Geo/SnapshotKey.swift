import Foundation

/// The name of a picture of a map (`StaticTripMap` in the app, drawn once by MapLibre's snapshotter and
/// kept in `Caches/MapSnapshots`): the same on every launch for the same picture, different for any change
/// that shows in it. What a map draws comes in as plain values (`Shape`): the app maps its own routes and
/// pins onto them. Whether a stop was visited is not part of it: the picture always shows the stop as not
/// visited, and the app draws the visit over the picture, so a mark never draws a new one.
///
/// Files: `<frameID>-<hash>.jpg` (the picture) and `<frameID>-<hash>.json` (where its pins landed). One
/// frame (a day's map, a hotel's neighbourhood) keeps one picture: a new one for the frame prunes the
/// others (`stale`); the launch trim keeps the folder under a size (`evicted`).
public struct SnapshotKey: Hashable, Sendable {
    /// the frame, made safe for a file name (`fileSafe`); may contain "-", never "."
    public let frameID: String
    /// FNV-1a 64 of the picture's inputs, in base 36: no "-"
    public let hash: String

    public var fileName: String { "\(frameID)-\(hash).jpg" }
    /// where the picture's pins landed, beside it
    public var pointsFileName: String { "\(frameID)-\(hash).json" }

    // MARK: What a picture draws

    /// The picture's size in points.
    public struct Size: Hashable, Sendable {
        public var width: Double
        public var height: Double

        public init(width: Double, height: Double) {
            self.width = width
            self.height = height
        }
    }

    /// A line, as the app's `MapRoute` draws it.
    public struct Route: Hashable, Sendable {
        public var id: String
        public var points: [Coordinate]
        /// "#RRGGBB"
        public var color: String
        public var width: Double
        public var dashed: Bool
        public var opacity: Double
        /// faded while another route is in focus
        public var dims: Bool

        public init(id: String, points: [Coordinate], color: String, width: Double = 4.5, dashed: Bool = false,
                    opacity: Double = 1, dims: Bool = true) {
            self.id = id
            self.points = points
            self.color = color
            self.width = width
            self.dashed = dashed
            self.opacity = opacity
            self.dims = dims
        }
    }

    /// A pin, as the app's `MapPin` draws it.
    public struct Pin: Hashable, Sendable {
        public var id: String
        public var coordinate: Coordinate
        /// the look, by the app's `MapPin.Kind` raw value; `visitedKind` counts as `unvisitedKind`
        public var kind: String
        public var label: String?
        public var number: Int?
        /// the label drawn beside the pin
        public var titled: Bool

        public init(id: String, coordinate: Coordinate, kind: String, label: String? = nil, number: Int? = nil, titled: Bool = false) {
            self.id = id
            self.coordinate = coordinate
            self.kind = kind
            self.label = label
            self.number = number
            self.titled = titled
        }
    }

    /// Everything a picture draws.
    public struct Shape: Hashable, Sendable {
        public var routes: [Route]
        public var pins: [Pin]
        /// the walked trail, as heat
        public var heat: [Coordinate]
        /// the route drawn wider, the others faded
        public var focus: String?

        public init(routes: [Route] = [], pins: [Pin] = [], heat: [Coordinate] = [], focus: String? = nil) {
            self.routes = routes
            self.pins = pins
            self.heat = heat
            self.focus = focus
        }
    }

    /// A visited stop's look (the app's `MapPin.Kind.done`), drawn over the picture, never into it.
    public static let visitedKind = "done"
    /// The look a visited stop has in the picture (`MapPin.Kind.stop`).
    public static let unvisitedKind = "stop"

    /// What a picture draws, as one number: compute it once per content (it reads every point). Every
    /// group is counted before its items, so two different contents cannot run into the same bytes.
    public static func fingerprint(_ shape: Shape) -> UInt64 {
        var h = FNV1a()
        h.number(Double(shape.routes.count))
        for r in shape.routes {
            h.text(r.id)
            h.text(r.color)
            h.number(r.width)
            h.number(r.opacity)
            h.number(r.dashed ? 1 : 0)
            h.number(r.dims ? 1 : 0)
            h.number(Double(r.points.count))
            for p in r.points {
                h.number(p.lat)
                h.number(p.lng)
            }
        }
        h.number(Double(shape.pins.count))
        for p in shape.pins {
            h.text(p.id)
            h.text(p.kind == visitedKind ? unvisitedKind : p.kind)
            h.number(p.coordinate.lat)
            h.number(p.coordinate.lng)
            h.text(p.label ?? "")
            h.number(Double(p.number ?? -1))
            h.number(p.titled ? 1 : 0)
        }
        h.number(Double(shape.heat.count))
        for c in shape.heat {
            h.number(c.lat)
            h.number(c.lng)
        }
        h.text(shape.focus ?? "")
        return h.value
    }

    /// The picture of `content` (a `fingerprint`) in a frame, at a size (rounded to the point: a layout's
    /// fractions do not change the picture) and scale, light or dark, with `insets` (top, left, bottom,
    /// right) kept clear around the content, read from the `tiles` build, by the app's `build` (whose
    /// style draws it).
    public static func make(frameID: String, content: UInt64, size: Size, scale: Double, dark: Bool, insets: [Double],
                            tiles: String, build: String) -> SnapshotKey {
        var h = FNV1a()
        h.word(content)
        h.number(size.width.rounded())
        h.number(size.height.rounded())
        h.number(scale)
        h.number(dark ? 1 : 0)
        h.number(Double(insets.count))
        for v in insets { h.number(v) }
        h.text(tiles)
        h.text(build)
        return SnapshotKey(frameID: fileSafe(frameID), hash: String(h.value, radix: 36))
    }

    /// An id as a file name: ASCII letters, digits and "-" stay; every other byte of its UTF-8 (":" and
    /// ">" of item ids, "/", ".", "_" itself) becomes "_" and two hex digits. Two ids never give one name.
    public static func fileSafe(_ id: String) -> String {
        var out = ""
        for b in id.utf8 {
            switch b {
            case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"),
                 UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "-"):
                out.unicodeScalars.append(Unicode.Scalar(b))
            default:
                out += "_" + hex(b)
            }
        }
        return out
    }

    private static func hex(_ b: UInt8) -> String {
        let digits = Array("0123456789ABCDEF")
        return String([digits[Int(b >> 4)], digits[Int(b & 0xF)]])
    }

    // MARK: The folder

    /// A file name the cache made, read back.
    public struct FileName: Hashable, Sendable {
        public let frameID: String
        public let hash: String
        /// "jpg" or "json"
        public let ext: String
    }

    /// `<frameID>-<hash>.jpg` or `.json`, split at the last "-" (frames contain "-", hashes do not); nil for
    /// any other name, the old format's `<key>.png` among them.
    public static func parse(_ name: String) -> FileName? {
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let ext = String(name[name.index(after: dot)...])
        guard ext == "jpg" || ext == "json" else { return nil }
        let stem = name[..<dot]
        guard let dash = stem.lastIndex(of: "-") else { return nil }
        let hash = String(stem[stem.index(after: dash)...])
        guard !hash.isEmpty else { return nil }
        return FileName(frameID: String(stem[..<dash]), hash: hash, ext: ext)
    }

    /// The names in `names` (the folder's listing) to delete once `key`'s picture is stored: the other
    /// pictures of the same frame, and their pins, sorted. The frame is compared whole, never as a prefix;
    /// a picture without a frame prunes nothing.
    public static func stale(_ names: [String], keeping key: SnapshotKey) -> [String] {
        guard !key.frameID.isEmpty else { return [] }
        return names.filter { name in
            guard let file = parse(name) else { return false }
            return file.frameID == key.frameID && file.hash != key.hash
        }.sorted()
    }

    /// A file in the folder, as listed: its size and its last use (the modification date, which a read touches).
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

    /// The names to delete so the folder's pictures fit in `budget` bytes, sorted: every file of the old
    /// format (`.png`), then whole pictures (the jpg and its json together), least recently used first. A
    /// name the cache did not make is neither counted nor deleted.
    public static func evicted(_ files: [StoredFile], toBytes budget: Int) -> [String] {
        let old = files.filter { $0.name.hasSuffix(".png") }.map(\.name)
        let pictures = evictedPairs(files, toBytes: budget) { name in parse(name).map { "\($0.frameID)-\($0.hash)" } }
        return (old + pictures).sorted()
    }

    /// The one pair-eviction rule of the folder trims (`evicted` here, `TerrainPicture.evicted`). Files are grouped by
    /// the stem `stem` reads from each name; nil is a name the cache did not make, neither counted nor deleted. A group
    /// is as large as its files together and as recent as its newest one. Whole groups go, the least recently used
    /// first and ties by stem, while the total is over `budget`. The names, sorted.
    static func evictedPairs(_ files: [StoredFile], toBytes budget: Int, stem: (String) -> String?) -> [String] {
        var pictures: [String: (bytes: Int, used: Date, names: [String])] = [:]
        for f in files {
            guard let key = stem(f.name) else { continue }
            var p = pictures[key] ?? (0, .distantPast, [])
            p.bytes += f.bytes
            p.used = max(p.used, f.used)
            p.names.append(f.name)
            pictures[key] = p
        }
        var total = pictures.values.reduce(0) { $0 + $1.bytes }
        var out: [String] = []
        let oldestFirst = pictures.sorted { ($0.value.used, $0.key) < ($1.value.used, $1.key) }
        for (_, p) in oldestFirst where total > budget {
            out += p.names
            total -= p.bytes
        }
        return out.sorted()
    }
}

/// FNV-1a, 64 bits, over the bytes the key's inputs are written as: the same value for the same input on
/// every launch and every machine.
struct FNV1a {
    private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

    mutating func byte(_ b: UInt8) {
        value = (value ^ UInt64(b)) &* 0x0000_0100_0000_01B3
    }

    /// UTF-8, then a 0 (so "ab", "c" and "a", "bc" differ)
    mutating func text(_ s: String) {
        for b in s.utf8 { byte(b) }
        byte(0)
    }

    /// the eight bytes of the IEEE 754 value, least significant first
    mutating func number(_ d: Double) {
        word(d.bitPattern)
    }

    mutating func word(_ w: UInt64) {
        var bits = w
        for _ in 0 ..< 8 {
            byte(UInt8(truncatingIfNeeded: bits))
            bits >>= 8
        }
    }
}

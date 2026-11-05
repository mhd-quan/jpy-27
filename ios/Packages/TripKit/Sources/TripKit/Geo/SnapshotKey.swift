import Foundation

/// The name of a map's picture (the app's `StaticTripMap`, drawn by MapLibre's snapshotter and kept in
/// `Caches/MapSnapshots/`): the frame it shows, and a hash of everything that changes its pixels, so a picture
/// is drawn once and found again on every launch.
///
/// The stops are not in the picture: the app draws them over it (`SnapshotPin`), so marking one visited changes
/// neither the picture nor its name, and nothing is drawn or written for it. A stop still counts here by its id
/// and place (`Pin.overlaid`): the camera frames on it, and its point on the picture is kept with the picture.
///
/// One picture per frame on disk: once a frame's new picture is written, its others go (`stale`). At launch the
/// folder is held to a budget, the pictures of the build before this one first (`trimmed`). Names that are not
/// ours are never returned by either.
public struct SnapshotKey: Hashable, Sendable {
    /// the map's place in the app ("1" for day 1's page, a stay's id, a walk's sight, a shopping slot)
    public let frameID: String
    /// base 36 of the fingerprint of what is drawn: `[0-9a-z]+`, never a "-"
    public let hash: String

    /// "<frameID>-<hash>.heic": HEIC, or JPEG under the same name where HEIC cannot be written (ImageIO reads
    /// an image by its content, not its name)
    public var fileName: String { stem + Self.image }
    /// "<frameID>-<hash>.json": the picture's size and where each stop sits on it
    public var pinsFileName: String { stem + Self.pins }

    private var stem: String { "\(frameID)-\(hash)" }
    private static let image = ".heic"
    private static let pins = ".json"

    // MARK: - Fingerprints

    /// FNV-1a, 64 bits, over what it is given: the same value for the same input on every launch and every
    /// phone (Swift's `Hasher` changes with each launch). Each part is closed off, so "ab" then "c" is not
    /// "a" then "bc", and two lists are not one.
    public struct Fingerprint: Sendable, Equatable {
        public private(set) var value: UInt64 = 0xcbf2_9ce4_8422_2325

        public init() {}

        mutating func mix(_ bytes: some Sequence<UInt8>) {
            for b in bytes { value = (value ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
        }

        /// a whole number as it is: a count, another fingerprint
        public mutating func add(_ word: UInt64) {
            var bits = word
            for _ in 0 ..< 8 {
                mix(CollectionOfOne(UInt8(truncatingIfNeeded: bits)))
                bits >>= 8
            }
        }

        public mutating func add(_ text: String) {
            mix(text.utf8)
            mix(CollectionOfOne(0))
        }

        /// −0 reads as 0: two equal numbers are one input
        public mutating func add(_ number: Double) {
            add((number == 0 ? 0 : number).bitPattern)
        }

        public mutating func add(_ flag: Bool) {
            add(flag ? 1 as UInt64 : 0)
        }

        /// in order, the count first
        public mutating func add(_ coords: [Coordinate]) {
            add(UInt64(coords.count))
            for c in coords {
                add(c.lat)
                add(c.lng)
            }
        }
    }

    /// A list of points, in order: a route's line, the heat of a walked trail.
    public static func fingerprint(_ coords: [Coordinate]) -> UInt64 {
        var f = Fingerprint()
        f.add(coords)
        return f.value
    }

    /// One pin of the map, as the key reads it.
    public struct Pin: Sendable, Hashable {
        public var id: String
        public var coordinate: Coordinate
        /// what the picture draws of it (kind, number, title); not read for an overlaid pin
        public var look: String
        /// drawn over the picture instead of into it (a stop, visited or not): counts by id and place alone
        public var overlaid: Bool

        public init(id: String, coordinate: Coordinate, look: String, overlaid: Bool) {
            self.id = id
            self.coordinate = coordinate
            self.look = look
            self.overlaid = overlaid
        }
    }

    /// Whether a pin of this kind, by the raw name of the app's `MapPin.Kind`, is drawn over the picture instead of
    /// into it: the stops, visited ("done") or not ("stop"), and no other kind. The app asks this wherever it
    /// decides (the key, the content it draws, the stops it lays over): a visited stop drawn into the picture would
    /// cost a snapshot and a file for every mark.
    public static func isOverlaid(kind: String) -> Bool { overlaidKinds.contains(kind) }

    private static let overlaidKinds: Set<String> = ["stop", "done"]

    /// The map's pins, in order. An overlaid pin counts by its id and place only, so its look (a stop marked
    /// visited) never reaches the key; any other pin by its look too.
    public static func fingerprint(_ pins: [Pin]) -> UInt64 {
        var f = Fingerprint()
        f.add(UInt64(pins.count))
        for p in pins {
            f.add(p.id)
            f.add([p.coordinate])
            f.add(p.overlaid)
            if !p.overlaid { f.add(p.look) }
        }
        return f.value
    }

    /// The key of a picture. `route` and `pins` are fingerprints made once per map, not per frame drawn:
    /// `route` of everything drawn but the pins (the lines' looks and points, the heat, the focus, the insets,
    /// the app's build, whose style and code draw it), `pins` from `fingerprint(_: [Pin])`. The size counts to
    /// the nearest point, so a layout pass that lands a fraction off draws nothing new.
    public static func make(frameID: String, route: UInt64, pins: UInt64, size: Size, scale: Double, dark: Bool, tiles: String) -> SnapshotKey {
        var f = Fingerprint()
        f.add(route)
        f.add(pins)
        f.add(size.width.rounded())
        f.add(size.height.rounded())
        f.add(scale)
        f.add(dark)
        f.add(tiles)
        return SnapshotKey(frameID: frameID, hash: String(f.value, radix: 36))
    }

    // MARK: - The folder

    /// The files to delete once `key`'s picture is written: the frame's other pictures, image and pins. Never
    /// another frame's (a name is split at its last "-", so "1" is not "10" and "slot-1" is not "slot-1-1"),
    /// never a name that is not ours, and nothing for an empty frame, which no two maps could share safely.
    public static func stale(_ names: [String], keeping key: SnapshotKey) -> [String] {
        guard !key.frameID.isEmpty else { return [] }
        return names.filter { name in
            guard let ours = parse(name) else { return false }
            return ours.frameID == key.frameID && ours.hash != key.hash
        }
    }

    /// A file in the folder, as listed.
    public struct File: Sendable, Hashable {
        public var name: String
        public var bytes: Int
        public var modified: Date

        public init(name: String, bytes: Int, modified: Date) {
            self.name = name
            self.bytes = bytes
            self.modified = modified
        }
    }

    /// The files to delete at launch: every picture of the build before this one ("<base 36>.png", one per stop
    /// marked, which nothing reads any more), then whole pictures, oldest first, until ours fit in
    /// `budget` bytes. Names that are not ours are neither deleted nor counted.
    public static func trimmed(_ files: [File], toBytes budget: Int) -> [String] {
        var out = files.filter { isOld($0.name) }.map(\.name)
        var pictures: [String: (bytes: Int, modified: Date, names: [String])] = [:]
        for file in files {
            guard let ours = parse(file.name) else { continue }
            let stem = "\(ours.frameID)-\(ours.hash)"
            var picture = pictures[stem] ?? (0, .distantPast, [])
            picture.bytes += file.bytes
            picture.modified = max(picture.modified, file.modified)
            picture.names.append(file.name)
            pictures[stem] = picture
        }
        var total = pictures.values.reduce(0) { $0 + $1.bytes }
        let oldestFirst = pictures.sorted { ($0.value.modified, $0.key) < ($1.value.modified, $1.key) }
        for (_, picture) in oldestFirst {
            guard total > budget else { break }
            out += picture.names.sorted()
            total -= picture.bytes
        }
        return out
    }

    /// "<frameID>-<hash>.heic" or ".json", split at the last "-".
    private static func parse(_ name: String) -> (frameID: Substring, hash: Substring)? {
        let stem: Substring
        if name.hasSuffix(image) {
            stem = name.dropLast(image.count)
        } else if name.hasSuffix(pins) {
            stem = name.dropLast(pins.count)
        } else {
            return nil
        }
        guard let dash = stem.lastIndex(of: "-") else { return nil }
        let hash = stem[stem.index(after: dash)...]
        guard !hash.isEmpty, hash.allSatisfy(\.isBase36) else { return nil }
        return (stem[..<dash], hash)
    }

    /// The name the build before this one gave a picture: "<base 36>.png".
    private static func isOld(_ name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        let stem = name.dropLast(4)
        return !stem.isEmpty && stem.allSatisfy(\.isBase36)
    }
}

private extension Character {
    /// ASCII 0–9, a–z: what `String(_:radix: 36)` writes
    var isBase36: Bool {
        guard let a = asciiValue else { return false }
        return (48...57).contains(a) || (97...122).contains(a)
    }
}

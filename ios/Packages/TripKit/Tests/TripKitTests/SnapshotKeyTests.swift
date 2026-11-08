import Foundation
import Testing
@testable import TripKit

/// The name of a map's picture (`StaticTripMap` in the app): what it draws, minus whether a stop was
/// visited (drawn over the picture), and how it is drawn; one file per frame in `Caches/MapSnapshots`.
@Suite struct SnapshotKeyTests {
    private let ueno = Coordinate(35.7141, 139.7774)
    private let asakusa = Coordinate(35.7101, 139.7967)
    private let tiles = "https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf"

    private func shape(kind: String = "stop", points: [Coordinate]? = nil, color: String = "#0079C2") -> SnapshotKey.Shape {
        SnapshotKey.Shape(
            routes: [SnapshotKey.Route(id: "m:ueno>asakusa", points: points ?? [ueno, asakusa], color: color, width: 5)],
            pins: [SnapshotKey.Pin(id: "ueno", coordinate: ueno, kind: kind, label: "Ueno", number: 1)]
        )
    }

    private func key(_ shape: SnapshotKey.Shape, frameID: String = "1", width: Double = 361, height: Double = 240,
                     scale: Double = 3, dark: Bool = false, insets: [Double] = [28, 28, 28, 28],
                     tiles: String? = nil, build: String = "42") -> SnapshotKey {
        SnapshotKey.make(frameID: frameID, content: SnapshotKey.fingerprint(shape), size: SnapshotKey.Size(width: width, height: height),
                         scale: scale, dark: dark, insets: insets, tiles: tiles ?? self.tiles, build: build)
    }

    @Test func keyIgnoresVisitedState() {
        // the same stops, one of them marked: the picture is the same, the mark is drawn over it
        #expect(SnapshotKey.fingerprint(shape(kind: SnapshotKey.visitedKind)) == SnapshotKey.fingerprint(shape(kind: SnapshotKey.unvisitedKind)))
        #expect(key(shape(kind: "done")) == key(shape(kind: "stop")))
        // any other look of the pin is drawn into the picture
        #expect(key(shape(kind: "stay")) != key(shape(kind: "stop")))
        #expect(key(shape(kind: "done")) != key(shape(kind: "highlight")))
    }

    @Test func keyChangesWithRouteAndScheme() {
        let base = key(shape())
        let moved = key(shape(points: [ueno, Coordinate(35.7101, 139.7968)]))
        let recoloured = key(shape(color: "#E5171F"))
        let dark = key(shape(), dark: true)
        #expect(Set([base, moved, recoloured, dark]).count == 4)
    }

    @Test func keyChangesWithEveryInput() {
        let r = SnapshotKey.Route(id: "m:ueno>asakusa", points: [ueno, asakusa], color: "#0079C2", width: 5)
        let p = SnapshotKey.Pin(id: "ueno", coordinate: ueno, kind: "stop", label: "Ueno", number: 1)
        func with(_ change: (inout SnapshotKey.Route, inout SnapshotKey.Pin, inout SnapshotKey.Shape) -> Void) -> SnapshotKey {
            var route = r, pin = p, extra = SnapshotKey.Shape()
            change(&route, &pin, &extra)
            return key(SnapshotKey.Shape(routes: [route] + extra.routes, pins: [pin] + extra.pins, heat: extra.heat, focus: extra.focus))
        }
        let base = with { _, _, _ in }
        let variants: [(String, SnapshotKey)] = [
            ("route id", with { r, _, _ in r = SnapshotKey.Route(id: "m:ueno>ueno", points: r.points, color: r.color, width: r.width) }),
            ("route width", with { r, _, _ in r.width = 3.5 }),
            ("route dash", with { r, _, _ in r.dashed = true }),
            ("route opacity", with { r, _, _ in r.opacity = 0.5 }),
            ("route dims", with { r, _, _ in r.dims = false }),
            ("point order", with { r, _, _ in r.points.reverse() }),
            ("another route", with { _, _, s in s.routes = [SnapshotKey.Route(id: "walk", points: [ueno, asakusa], color: "#8E8E93")] }),
            ("pin id", with { _, p, _ in p = SnapshotKey.Pin(id: "ueno-park", coordinate: p.coordinate, kind: p.kind, label: p.label, number: p.number) }),
            ("pin latitude", with { _, p, _ in p.coordinate.lat += 0.0001 }),
            ("pin longitude", with { _, p, _ in p.coordinate.lng += 0.0001 }),
            ("pin label", with { _, p, _ in p.label = "Ueno Park" }),
            ("pin number", with { _, p, _ in p.number = 2 }),
            ("pin without number", with { _, p, _ in p.number = nil }),
            ("pin titled", with { _, p, _ in p.titled = true }),
            ("pin kind", with { _, p, _ in p.kind = "along" }),
            ("another pin", with { _, _, s in s.pins = [SnapshotKey.Pin(id: "asakusa", coordinate: asakusa, kind: "stop")] }),
            ("heat", with { _, _, s in s.heat = [ueno] }),
            ("focus", with { _, _, s in s.focus = "m:ueno>asakusa" }),
            ("frame", key(shape(), frameID: "2")),
            ("width", key(shape(), width: 360)),
            ("height", key(shape(), height: 300)),
            ("scale", key(shape(), scale: 2)),
            ("dark", key(shape(), dark: true)),
            ("inset top", key(shape(), insets: [30, 28, 28, 28])),
            ("inset left", key(shape(), insets: [28, 30, 28, 28])),
            ("inset bottom", key(shape(), insets: [28, 28, 30, 28])),
            ("inset right", key(shape(), insets: [28, 28, 28, 30])),
            ("tiles", key(shape(), tiles: "https://tiles.openfreemap.org/planet/20261101_001001_pt/{z}/{x}/{y}.pbf")),
            ("build", key(shape(), build: "43")),
        ]
        #expect(base == key(shape()))
        for (name, variant) in variants {
            #expect(variant != base, "\(name) does not change the key")
        }
        // and no two changes land on the same name
        #expect(Set(variants.map(\.1)).count == variants.count)
    }

    @Test func keyRoundsTheSize() {
        // a GeometryReader's size wobbles below a point; the picture does not change for it
        #expect(key(shape(), width: 361.2, height: 239.6) == key(shape(), width: 361, height: 240))
    }

    @Test func fingerprintIsStable() {
        // values from an FNV-1a 64 written apart from this code, with the same byte rules: the name of a
        // picture is the same on every launch (Swift's Hasher is not)
        #expect(SnapshotKey.fingerprint(shape(kind: "done")) == 16_513_413_208_146_130_955)
        #expect(SnapshotKey.fingerprint(SnapshotKey.Shape()) == 15_304_778_913_451_835_775)
        #expect(key(shape(kind: "done")).fileName == "1-33na48mrm5np.jpg")
        var fnv = FNV1a()
        for b in "a".utf8 { fnv.byte(b) }
        #expect(fnv.value == 0xaf63_dc4c_8601_ec8c)
    }

    @Test func fileNamesAreFrameThenHash() {
        let k = key(shape(), frameID: "w-kamo-north-delta-morning-1")
        #expect(k.frameID == "w-kamo-north-delta-morning-1")
        #expect(k.fileName == "w-kamo-north-delta-morning-1-\(k.hash).jpg")
        #expect(k.pointsFileName == "w-kamo-north-delta-morning-1-\(k.hash).json")
        #expect(!k.hash.isEmpty)
        #expect(!k.hash.contains("-"))
        #expect(SnapshotKey.parse(k.fileName)?.frameID == k.frameID)
        #expect(SnapshotKey.parse(k.pointsFileName)?.hash == k.hash)
    }

    @Test func frameIDsAreSafeFileNames() {
        #expect(SnapshotKey.fileSafe("m:ueno>asakusa") == "m_3Aueno_3Easakusa")
        #expect(SnapshotKey.fileSafe("w-kamo-1") == "w-kamo-1")
        #expect(SnapshotKey.fileSafe("resol-akihabara") == "resol-akihabara")
        #expect(SnapshotKey.fileSafe("a_b") == "a_5Fb")
        #expect(SnapshotKey.fileSafe("a/b.c") == "a_2Fb_2Ec")
        #expect(SnapshotKey.fileSafe("") == "")
        #expect(SnapshotKey.fileSafe("Hồ") == "H_E1_BB_93")
        // two ids never share a name
        let ids = ["a:b", "a>b", "a_b", "a_3Ab", "a-b", "a b", "a.b", "a/b", "A:b"]
        #expect(Set(ids.map(SnapshotKey.fileSafe)).count == ids.count)
        #expect(key(shape(), frameID: "m:ueno>asakusa").frameID == "m_3Aueno_3Easakusa")
    }

    @Test func fileNameGroupsByFrame() {
        let keep = SnapshotKey(frameID: "w-kamo-1", hash: "abc")
        let names = [
            "w-kamo-1-abc.jpg", "w-kamo-1-abc.json",
            "w-kamo-1-old.jpg", "w-kamo-1-old.json",
            // a frame whose name starts with the kept one, and one the kept one starts with
            "w-kamo-12-xyz.jpg", "w-kamo-xyz.jpg",
            "1-abc.jpg",
            // the old format, a picture with no frame, a half-written file, files not named by the app
            "legacy0z9.png", "-zzz.jpg", ".dat.nosync12.ab", "w-kamo-1-.jpg", "w-kamo-1-old.txt", "notes",
        ]
        #expect(SnapshotKey.stale(names.shuffled(), keeping: keep) == ["w-kamo-1-old.jpg", "w-kamo-1-old.json"])
        #expect(SnapshotKey.stale(names, keeping: SnapshotKey(frameID: "w-kamo", hash: "q")) == ["w-kamo-xyz.jpg"])
        // a picture with no frame never prunes anything, its own frame-less files included
        #expect(SnapshotKey.stale(names, keeping: SnapshotKey(frameID: "", hash: "abc")).isEmpty)
        #expect(SnapshotKey.parse("legacy0z9.png") == nil)
        #expect(SnapshotKey.parse("-zzz.jpg")?.frameID == "")
    }

    @Test func trimDeletesLegacyThenLeastRecentlyUsed() {
        let t0 = Date(timeIntervalSince1970: 1_762_560_000)
        func file(_ name: String, _ kb: Int, _ minutes: Double) -> SnapshotKey.StoredFile {
            SnapshotKey.StoredFile(name: name, bytes: kb * 1024, used: t0.addingTimeInterval(minutes * 60))
        }
        let files = [
            file("oldkey.png", 900, 50),
            file("1-a.jpg", 200, 10), file("1-a.json", 1, 0),
            // the newest use of a picture is its jpg's (a read touches it), even with an older json
            file("2-b.jpg", 200, 30), file("2-b.json", 1, 1),
            file("3-c.jpg", 200, 20), file("3-c.json", 1, 2),
            file("notes.txt", 5000, 0),
        ]
        // 603 KB of pictures, 410 KB allowed: the least recently used goes first, both of its files
        #expect(SnapshotKey.evicted(files.shuffled(), toBytes: 410 * 1024) == ["1-a.jpg", "1-a.json", "oldkey.png"])
        #expect(SnapshotKey.evicted(files, toBytes: 300 * 1024) == ["1-a.jpg", "1-a.json", "3-c.jpg", "3-c.json", "oldkey.png"])
        // under the budget only the old format goes; a file not named by the app is neither counted nor deleted
        #expect(SnapshotKey.evicted(files, toBytes: 40 << 20) == ["oldkey.png"])
        #expect(SnapshotKey.evicted(files, toBytes: 0) == files.map(\.name).filter { $0 != "notes.txt" }.sorted())
    }
}

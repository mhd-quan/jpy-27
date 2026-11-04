import Foundation
import Testing
@testable import TripKit

/// The names of the map pictures in `Caches/MapSnapshots/` (the app's `StaticTripMap`): one picture per frame,
/// found again across launches; marking a stop visited never renames it; a frame's pruning never reaches
/// another frame's pictures; the trim at launch deletes the old build's pictures, then the oldest.
@Suite struct SnapshotKeyTests {
    typealias Pin = SnapshotKey.Pin

    let tiles = "https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf"
    let size = Size(width: 361, height: 240)

    func key(_ frameID: String = "1", route: UInt64 = 1, pins: UInt64 = 2, size: Size? = nil, scale: Double = 3,
             dark: Bool = false, tiles: String? = nil) -> SnapshotKey {
        SnapshotKey.make(frameID: frameID, route: route, pins: pins, size: size ?? self.size, scale: scale, dark: dark,
                         tiles: tiles ?? self.tiles)
    }

    /// Day 1's stops (numbered, overlaid) and its hotel (drawn into the picture).
    let day: [Pin] = [
        Pin(id: "akihabara", coordinate: Coordinate(35.6984, 139.7731), look: "stop·1·", overlaid: true),
        Pin(id: "kanda-myojin", coordinate: Coordinate(35.7020, 139.7679), look: "stop·2·", overlaid: true),
        Pin(id: "resol-akihabara", coordinate: Coordinate(35.6960, 139.7745), look: "stay··", overlaid: false),
    ]

    // MARK: - The key

    @Test func keyIgnoresVisitedState() {
        var visited = day
        visited[1].look = "done·2·"
        #expect(SnapshotKey.fingerprint(visited) == SnapshotKey.fingerprint(day))
        #expect(key(pins: SnapshotKey.fingerprint(visited)) == key(pins: SnapshotKey.fingerprint(day)))

        // what the picture does draw still counts: the same change on the hotel renames the picture
        var restyled = day
        restyled[2].look = "station··"
        #expect(SnapshotKey.fingerprint(restyled) != SnapshotKey.fingerprint(day))
        // and an overlaid pin still counts by its place (the camera frames on it) and its id (its stored point)
        var moved = day
        moved[1].coordinate.lng += 0.0001
        #expect(SnapshotKey.fingerprint(moved) != SnapshotKey.fingerprint(day))
        var renamed = day
        renamed[1].id = "yushima"
        #expect(SnapshotKey.fingerprint(renamed) != SnapshotKey.fingerprint(day))
        // a pin drawn into the picture instead of over it is another picture
        var drawnIn = day
        drawnIn[1].overlaid = false
        #expect(SnapshotKey.fingerprint(drawnIn) != SnapshotKey.fingerprint(day))
        // one more stop is another picture
        #expect(SnapshotKey.fingerprint(Array(day.prefix(2))) != SnapshotKey.fingerprint(day))
    }

    @Test func keyChangesWithRouteAndScheme() {
        let line = [Coordinate(35.6812, 139.7671), Coordinate(35.6984, 139.7731), Coordinate(35.7020, 139.7679)]
        var nudged = line
        nudged[1].lng += 0.00001
        let base = key(route: SnapshotKey.fingerprint(line))

        #expect(key(route: SnapshotKey.fingerprint(line)) == base)
        #expect(key(route: SnapshotKey.fingerprint(nudged)) != base)
        #expect(key(route: SnapshotKey.fingerprint(line), dark: true) != base)
        #expect(key(route: SnapshotKey.fingerprint(line), tiles: "https://tiles.openfreemap.org/planet/20261101_001001_pt/{z}/{x}/{y}.pbf") != base)
        #expect(key(route: SnapshotKey.fingerprint(line), scale: 2) != base)
        #expect(key(route: SnapshotKey.fingerprint(line), pins: 3) != base)
        #expect(key(route: SnapshotKey.fingerprint(line), size: Size(width: 362, height: 240)) != base)
        #expect(key(route: SnapshotKey.fingerprint(line), size: Size(width: 361, height: 241)) != base)
        // a layout pass that lands a fraction of a point off draws nothing new
        #expect(key(route: SnapshotKey.fingerprint(line), size: Size(width: 360.7, height: 240.3)) == base)
        // the frame names the file, not the picture
        let other = key("2", route: SnapshotKey.fingerprint(line))
        #expect(other != base && other.hash == base.hash)
    }

    /// Pinned (the value was worked out apart, in Python, from the bytes `make` is meant to read): a change to what the hash reads, or in what order, renames every picture on every phone (each
    /// is then drawn again once, and the old ones are pruned or trimmed).
    @Test func aKeyIsTheSameOnEveryLaunch() {
        let k = SnapshotKey.make(frameID: "1", route: 1, pins: 2, size: Size(width: 361, height: 240), scale: 3, dark: false, tiles: "t")
        #expect(k.hash == "2ufi3zsvz1nuq")
        #expect(k.fileName == "1-2ufi3zsvz1nuq.heic")
        #expect(k.pinsFileName == "1-2ufi3zsvz1nuq.json")
    }

    @Test func fingerprintIsFNV1a() {
        var f = SnapshotKey.Fingerprint()
        #expect(f.value == 0xcbf2_9ce4_8422_2325)
        f.mix(Array("a".utf8))
        #expect(f.value == 0xaf63_dc4c_8601_ec8c)
        var g = SnapshotKey.Fingerprint()
        g.mix(Array("foobar".utf8))
        #expect(g.value == 0x8594_4171_f739_67e8)
    }

    @Test func fingerprintReadsOrderAndBoundaries() {
        let a = Coordinate(35.68, 139.76), b = Coordinate(35.69, 139.77), c = Coordinate(35.70, 139.78)
        #expect(SnapshotKey.fingerprint([a, b]) != SnapshotKey.fingerprint([b, a]))
        #expect(SnapshotKey.fingerprint([Coordinate(-0.0, 139.7)]) == SnapshotKey.fingerprint([Coordinate(0.0, 139.7)]))

        var split1 = SnapshotKey.Fingerprint(), split2 = SnapshotKey.Fingerprint()
        split1.add([a, b]); split1.add([c])
        split2.add([a]); split2.add([b, c])
        #expect(split1.value != split2.value)

        var text1 = SnapshotKey.Fingerprint(), text2 = SnapshotKey.Fingerprint()
        text1.add("#E07A2F"); text1.add("w")
        text2.add("#E07A2"); text2.add("Fw")
        #expect(text1.value != text2.value)

        var on = SnapshotKey.Fingerprint(), off = SnapshotKey.Fingerprint()
        on.add(true)
        off.add(false)
        #expect(on.value != off.value)
    }

    // MARK: - Prune: one picture per frame

    @Test func fileNameGroupsByFrame() {
        let keep = SnapshotKey(frameID: "1", hash: "k1")
        #expect(keep.fileName == "1-k1.heic" && keep.pinsFileName == "1-k1.json")
        let names = [
            "1-k1.heic", "1-k1.json",              // the picture kept
            "1-old.heic", "1-old.json",            // the frame's earlier picture
            "1-half.json",                         // the pins of a picture whose image never landed
            "10-a.heic", "10-a.json", "12-b.heic", // other days
            "kawaguchiko-c.heic",
            "3ovrwcbmd3drs.png",                   // a picture of the build before 4.1 (trim's)
            "notes.txt", ".DS_Store", "1-.heic", "1-AB.heic", "1-k1.jpg", "1-x.heic.tmp",
        ]
        #expect(Set(SnapshotKey.stale(names, keeping: keep)) == ["1-old.heic", "1-old.json", "1-half.json"])
    }

    @Test func framesWhoseNamesShareAPrefixStayApart() {
        let names = ["slot-1-aa.heic", "slot-1-1-bb.heic", "slot-1-1-cc.heic", "slot-1-1b-dd.heic"]
        #expect(SnapshotKey.stale(names, keeping: SnapshotKey(frameID: "slot-1", hash: "aa")).isEmpty)
        #expect(SnapshotKey.stale(names, keeping: SnapshotKey(frameID: "slot-1-1", hash: "bb")) == ["slot-1-1-cc.heic"])
        #expect(SnapshotKey.stale(["1-a.heic", "10-b.heic", "11-c.heic"], keeping: SnapshotKey(frameID: "1", hash: "z")) == ["1-a.heic"])
    }

    @Test func anEmptyFrameIDPrunesNothing() {
        let names = ["-aa.heic", "-bb.heic", "-bb.json", "1-cc.heic"]
        #expect(SnapshotKey.stale(names, keeping: SnapshotKey(frameID: "", hash: "aa")).isEmpty)
    }

    /// The frames the app names (DayView, StaysView's neighbourhood and highlight pages, SlotView), from the data
    /// the app ships: no two maps share a frame, and each frame's pruning leaves every other frame's picture alone.
    /// Uniqueness rests on the data's ids; this pins it.
    @Test func bundledFramesAreUniqueAndPruneApart() throws {
        let store = Bundle_.store
        let guide = try #require(store.guide)
        var frames = (store.trip.days + store.trip.altDays).map(\.key)
        frames += guide.stays.map(\.id)
        frames += guide.stays.flatMap { stay in
            (stay.around?.walks ?? []).flatMap { walk in walk.highlights.indices.map { "\(walk.id)-\($0)" } }
        }
        frames += guide.shopping.slots.map(\.id)
        #expect(frames.count > 40)
        #expect(Set(frames).count == frames.count)
        #expect(frames.allSatisfy { !$0.isEmpty && !$0.contains("/") })

        let names = frames.map { "\($0)-h.heic" }
        for frame in frames {
            #expect(SnapshotKey.stale(names, keeping: SnapshotKey(frameID: frame, hash: "k")) == ["\(frame)-h.heic"])
        }
    }

    // MARK: - Trim at launch

    let t0 = Date(timeIntervalSince1970: 1_793_862_000)

    func picture(_ stem: String, bytes: Int, ageDays: Double) -> [SnapshotKey.File] {
        let at = t0.addingTimeInterval(-ageDays * 86_400)
        return [SnapshotKey.File(name: stem + ".heic", bytes: bytes, modified: at),
                SnapshotKey.File(name: stem + ".json", bytes: 1, modified: at)]
    }

    @Test func trimDeletesTheOldBuildsPicturesFirst() {
        let old = [SnapshotKey.File(name: "3ovrwcbmd3drs.png", bytes: 400_000, modified: t0),
                   SnapshotKey.File(name: "a0.png", bytes: 300_000, modified: t0)]
        let files = old + picture("1-k", bytes: 10, ageDays: 3)
        #expect(Set(SnapshotKey.trimmed(files, toBytes: 1_000)) == ["3ovrwcbmd3drs.png", "a0.png"])
    }

    @Test func trimDeletesWholePicturesOldestFirstUntilUnderBudget() {
        let files = picture("2-new", bytes: 10, ageDays: 1) + picture("1-oldest", bytes: 10, ageDays: 9)
            + picture("kawaguchiko-mid", bytes: 10, ageDays: 4)
        // 33 bytes: the oldest picture goes whole, then 22 fit
        #expect(Set(SnapshotKey.trimmed(files, toBytes: 22)) == ["1-oldest.heic", "1-oldest.json"])
        #expect(Set(SnapshotKey.trimmed(files, toBytes: 21)) == ["1-oldest.heic", "1-oldest.json", "kawaguchiko-mid.heic", "kawaguchiko-mid.json"])
        #expect(SnapshotKey.trimmed(files, toBytes: 33).isEmpty)
        #expect(SnapshotKey.trimmed([], toBytes: 0).isEmpty)
    }

    @Test func trimNeverTouchesNamesThatAreNotOurs() {
        let foreign = [SnapshotKey.File(name: "notes.txt", bytes: 50_000_000, modified: t0.addingTimeInterval(-1e6)),
                       SnapshotKey.File(name: "1-k.heic.sb-12ab", bytes: 50_000_000, modified: t0),
                       SnapshotKey.File(name: "Old.png", bytes: 5, modified: t0)]
        let files = foreign + picture("1-k", bytes: 10, ageDays: 1)
        #expect(SnapshotKey.trimmed(files, toBytes: 100).isEmpty)
        #expect(Set(SnapshotKey.trimmed(files, toBytes: 0)) == ["1-k.heic", "1-k.json"])
    }

    // MARK: - Pins over a cropped picture

    @Test func pinsFollowTheCrop() {
        let picture = Size(width: 360, height: 240)
        #expect(picture.point(90, 60, filling: Size(width: 360, height: 240)) == (90, 60))
        // narrower box: the same scale, 30 pt cropped off each side
        #expect(picture.point(90, 60, filling: Size(width: 300, height: 240)) == (60, 60))
        // twice as wide: twice the scale, 120 pt cropped off top and bottom
        #expect(picture.point(180, 120, filling: Size(width: 720, height: 240)) == (360, 120))
        #expect(picture.point(0, 0, filling: Size(width: 720, height: 240)) == (0, -120))
        // a picture half the size, drawn up
        #expect(Size(width: 180, height: 120).point(45, 30, filling: Size(width: 360, height: 240)) == (90, 60))
    }
}

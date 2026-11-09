import Foundation
import Testing
@testable import TripKit

/// The style an offline pack is made from is the app's own, stored in MapLibre's database under a URL that
/// is only a key (nobody answers it): the bundled bytes under the build's name, or the bundled style on
/// OpenFreeMap's current build under a key of its own.
@Suite struct PackStyleTests {
    /// a bundled style: its tiles "T1", its name "B1"
    let bundled = Data(#"{"version":8,"metadata":{"jp27:build":"B1","jp27:tiles":"T1","keep":1},"sources":{"omt":{"type":"vector","tiles":["T1"]}},"layers":[]}"#.utf8)

    @Test func pinnedUsesBundledBytesAndName() throws {
        let p = try #require(PackStyle.prepare(bundled: bundled, pinnedName: "B1", currentTemplate: nil))
        #expect(p.url == PackStyle.base + "jp27-light@B1.json")
        #expect(p.url == "https://jpy27.delphyra.tech/map/jp27-light@B1.json")
        #expect(p.style == bundled)
        #expect(p.build == TileBuild(template: "T1"))
        // the name given, not the one in the bytes: it is the URL earlier builds made their packs under
        let other = try #require(PackStyle.prepare(bundled: bundled, pinnedName: "B2", currentTemplate: nil))
        #expect(other.url == PackStyle.base + "jp27-light@B2.json")
        #expect(other.style == bundled)
    }

    @Test func currentRewritesTilesAndKeysByTemplate() throws {
        for pinnedName in [nil, "B1"] as [String?] {
            // the map reads the current build: that wins over the pinned name
            let p = try #require(PackStyle.prepare(bundled: bundled, pinnedName: pinnedName, currentTemplate: "T2"))
            #expect(p.build == TileBuild(template: "T2"))
            #expect(StyleInfo.build(style: p.style) == TileBuild(template: "T2"))
            #expect(StyleInfo.styleBuild(style: p.style) == nil)
            #expect(p.url == PackStyle.base + "jp27-light@current-" + PackStyle.key(of: "T2") + ".json")
            #expect(p.style == StyleInfo.pointing(style: bundled, at: "T2"))
        }
        // two templates, two keys
        let t3 = try #require(PackStyle.prepare(bundled: bundled, pinnedName: "B1", currentTemplate: "T3"))
        let t2 = try #require(PackStyle.prepare(bundled: bundled, pinnedName: "B1", currentTemplate: "T2"))
        #expect(t3.url != t2.url)
        #expect(t3.build == TileBuild(template: "T3"))
        // never the pinned style's URL
        #expect(t2.url != PackStyle.base + "jp27-light@B1.json")
    }

    @Test func keyIsFNV1a64Hex() {
        #expect(PackStyle.key(of: "") == "cbf29ce484222325")
        #expect(PackStyle.key(of: "a") == "af63dc4c8601ec8c")
        #expect(PackStyle.key(of: "A") != PackStyle.key(of: "B"))
        // sixteen digits even when the hash starts with a zero
        #expect(PackStyle.key(of: "T0") == "09350007b5c731a9")
        // the UTF-8 bytes of the string, not its scalars: "é" is two bytes (one scalar would be af64644c8602d3a4)
        #expect(PackStyle.key(of: "é") == "0ac21707b7181e01")
        // a real template
        #expect(PackStyle.key(of: "https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf") == "210a86fc4ef04844")
        for s in ["", "a", "T0", "https://tiles.openfreemap.org/planet/x/{z}/{x}/{y}.pbf"] {
            let key = PackStyle.key(of: s)
            #expect(key.count == 16)
            #expect(key.allSatisfy { "0123456789abcdef".contains($0) })
            // the same every time (not `Hasher`, which changes from one launch to the next)
            #expect(PackStyle.key(of: s) == key)
        }
    }

    @Test func nothingToPrepareIsNil() {
        #expect(PackStyle.prepare(bundled: bundled, pinnedName: nil, currentTemplate: nil) == nil)
        // nothing to rewrite
        #expect(PackStyle.prepare(bundled: Data("x".utf8), pinnedName: nil, currentTemplate: "T2") == nil)
        #expect(PackStyle.prepare(bundled: Data("x".utf8), pinnedName: "B1", currentTemplate: "T2") == nil)
        // a bundled style with no basemap tiles holds no build
        let noTiles = Data(#"{"version":8,"metadata":{"jp27:build":"B1"},"sources":{"omt":{"type":"vector","url":"https://tiles.openfreemap.org/planet"}}}"#.utf8)
        #expect(PackStyle.prepare(bundled: noTiles, pinnedName: "B1", currentTemplate: nil) == nil)
        #expect(PackStyle.prepare(bundled: Data("x".utf8), pinnedName: "B1", currentTemplate: nil) == nil)
        // an empty template names no build
        #expect(PackStyle.prepare(bundled: bundled, pinnedName: "B1", currentTemplate: "") == nil)
    }

    @Test func preparedStyleMakesAPackOfItsBuild() throws {
        let pinned = try #require(PackStyle.prepare(bundled: bundled, pinnedName: "B1", currentTemplate: nil))
        let current = try #require(PackStyle.prepare(bundled: bundled, pinnedName: "B1", currentTemplate: "T2"))
        for p in [pinned, current] {
            #expect(OfflineArea.step(.files(style: p.style, tileJSON: nil), mapBuild: p.build, askedOn: p.build, again: false) == .add(p.build))
        }
    }

    /// The style the app ships: pinned, it is the very file the site kept under its name, so packs made by
    /// earlier builds (from the site) and by this one share a URL and its bytes.
    @Test func theShippedStyleIsPreparedUnderItsName() throws {
        let shipped = try Bundle_.data("../public/map/jp27-light.json")
        let name = try #require(StyleInfo.styleBuild(style: shipped))
        let p = try #require(PackStyle.prepare(bundled: shipped, pinnedName: name, currentTemplate: nil))
        #expect(p.url == "https://jpy27.delphyra.tech/map/jp27-light@\(name).json")
        #expect(p.style == (try Bundle_.data("../public/map/jp27-light@\(name).json")))
        #expect(p.build == StyleInfo.build(style: shipped))
        let other = "https://tiles.openfreemap.org/planet/20261101_080012_pt/{z}/{x}/{y}.pbf"
        let c = try #require(PackStyle.prepare(bundled: shipped, pinnedName: name, currentTemplate: other))
        #expect(c.build == TileBuild(template: other))
        #expect(OfflineArea.step(.files(style: c.style, tileJSON: nil), mapBuild: c.build, askedOn: c.build, again: false) == .add(c.build))
    }
}

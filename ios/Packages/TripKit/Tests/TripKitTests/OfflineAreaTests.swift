import Foundation
import Testing
@testable import TripKit

/// An offline area is done only when its pack holds every tile of the build the map reads, and a
/// download is "Xong" only when every area of it is.
@Suite struct OfflineAreaTests {
    let build = TileBuild(template: "https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf")
    let other = TileBuild(template: "https://tiles.openfreemap.org/planet/20261101_080012_pt/{z}/{x}/{y}.pbf")
    var tag: PackTag { PackTag(area: "tokyo", build: build, styleURL: "") }

    func phase(_ state: PackState, _ completed: UInt64, _ expected: UInt64, maximum: UInt64? = nil, tag: PackTag?? = .none,
               error: String? = nil, previous: AreaPhase? = nil) -> AreaPhase {
        OfflineArea.phase(state: state, completed: completed, expected: expected, maximum: maximum ?? expected,
                          tag: tag ?? self.tag, mapBuild: build, error: error, previous: previous)
    }

    // MARK: The job

    @Test func aRegionWhosePackCouldNotBeMadeFailsTheJob() {
        let r = OfflineJob(areas: ["tokyo", "kyoto"], photos: false)
            .result(phases: ["tokyo": .complete(build), "kyoto": .failed("Không tạo được vùng tải")], photos: .finished, mapBuild: build)
        #expect(!r.success); #expect(r.failed == ["kyoto"]); #expect(r.subtitle != "Xong")
        #expect(r.done == 1)
        #expect(r.subtitle == "Bản đồ 1/2 vùng · 1 lỗi")
    }

    @Test func mapOnlyJobIsDoneOnlyWhenEveryAreaIsComplete() {
        let job = OfflineJob(areas: ["tokyo", "kyoto", "nara"], photos: false)
        let running = job.result(phases: ["tokyo": .complete(build), "kyoto": .complete(build), "nara": .downloading(completed: 5, expected: 10)],
                                 photos: .finished, mapBuild: build)
        #expect(!running.success); #expect(running.done == 2); #expect(running.failed.isEmpty); #expect(!running.paused)
        #expect(running.subtitle == "Bản đồ 2/3 vùng")
        let done = job.result(phases: ["tokyo": .complete(build), "kyoto": .complete(build), "nara": .complete(build)],
                              photos: .finished, mapBuild: build)
        #expect(done == JobResult(success: true, done: 3, failed: [], paused: false, subtitle: "Xong"))
    }

    @Test func pausedIsNotDone() {
        let r = OfflineJob(areas: ["tokyo", "kyoto", "nara"], photos: false)
            .result(phases: ["tokyo": .complete(build), "kyoto": .paused, "nara": .failed("x")], photos: .finished, mapBuild: build)
        #expect(!r.success); #expect(r.paused); #expect(r.subtitle == "Đã dừng")
        #expect(r.failed == ["nara"]); #expect(r.done == 1)
    }

    @Test func waitingRegionIsNotComplete() {
        let r = OfflineJob(areas: ["tokyo", "kyoto"], photos: false)
            .result(phases: ["tokyo": .complete(build), "kyoto": .waitingForNetwork], photos: .finished, mapBuild: build)
        #expect(!r.success); #expect(r.failed.isEmpty); #expect(!r.paused); #expect(r.done == 1)
    }

    @Test func anAreaOfAnotherBuildOrStaleIsAFailureNotDone() {
        let r = OfflineJob(areas: ["tokyo", "kyoto", "nara", "osaka"], photos: false)
            .result(phases: ["tokyo": .complete(other), "kyoto": .stale(other), "nara": .stale(nil), "osaka": .complete(build)],
                    photos: .finished, mapBuild: build)
        #expect(!r.success); #expect(r.done == 1)
        #expect(r.failed == ["kyoto", "nara", "tokyo"])
        #expect(r.subtitle == "Bản đồ 1/4 vùng · 3 lỗi")
        // twelve names: a set listing them in order by chance is one in 479 001 600
        let many = ["toba", "ise", "kyoto", "hakone", "osaka", "nara", "tokyo", "shima", "kawaguchiko", "tokaido", "uji", "fuji"]
        let all = OfflineJob(areas: Set(many), photos: false)
            .result(phases: Dictionary(uniqueKeysWithValues: many.map { ($0, AreaPhase.failed("x")) }), photos: .finished, mapBuild: build)
        #expect(all.failed == ["fuji", "hakone", "ise", "kawaguchiko", "kyoto", "nara", "osaka", "shima", "toba", "tokaido", "tokyo", "uji"])
    }

    @Test func anAreaNobodyKnowsIsNeitherDoneNorFailed() {
        let r = OfflineJob(areas: ["tokyo", "kyoto"], photos: false)
            .result(phases: ["tokyo": .complete(build)], photos: .finished, mapBuild: build)
        #expect(!r.success); #expect(r.done == 1); #expect(r.failed.isEmpty); #expect(r.subtitle == "Bản đồ 1/2 vùng")
        for p: AreaPhase in [.requested, .creating] {
            let s = OfflineJob(areas: ["kyoto"], photos: false).result(phases: ["kyoto": p], photos: .finished, mapBuild: build)
            #expect(!s.success); #expect(s.failed.isEmpty); #expect(!s.paused)
        }
    }

    @Test func photosThatFailedFailTheJobEvenWithEveryAreaDone() {
        let r = OfflineJob(areas: ["tokyo"], photos: true)
            .result(phases: ["tokyo": .complete(build)], photos: PhotoState(failed: 3, left: 3, paused: false), mapBuild: build)
        #expect(!r.success); #expect(r.done == 1); #expect(r.failed.isEmpty); #expect(!r.paused)
        #expect(r.subtitle == "Bản đồ 1/1 vùng · 3 ảnh chưa tải được")
        let photosOnly = OfflineJob(areas: [], photos: true).result(phases: [:], photos: PhotoState(failed: 2, left: 0, paused: false), mapBuild: build)
        #expect(!photosOnly.success); #expect(photosOnly.subtitle == "2 ảnh chưa tải được")
        let fine = OfflineJob(areas: [], photos: true).result(phases: [:], photos: .finished, mapBuild: build)
        #expect(fine.success); #expect(fine.subtitle == "Xong")
    }

    @Test func pausedPhotosAreNotDone() {
        let paused = PhotoState(failed: 0, left: 40, paused: true)
        let r = OfflineJob(areas: ["tokyo"], photos: true).result(phases: ["tokyo": .complete(build)], photos: paused, mapBuild: build)
        #expect(!r.success); #expect(r.paused); #expect(r.subtitle == "Đã dừng"); #expect(r.done == 1)
        let photosOnly = OfflineJob(areas: [], photos: true).result(phases: [:], photos: paused, mapBuild: build)
        #expect(!photosOnly.success); #expect(photosOnly.paused); #expect(photosOnly.subtitle == "Đã dừng")
        // paused with nothing left to download is still a pause the travellers made
        let nothingLeft = OfflineJob(areas: [], photos: true).result(phases: [:], photos: PhotoState(failed: 0, left: 0, paused: true), mapBuild: build)
        #expect(!nothingLeft.success); #expect(nothingLeft.paused)
    }

    @Test func unfinishedPhotosAreNotDone() {
        let r = OfflineJob(areas: ["tokyo"], photos: true)
            .result(phases: ["tokyo": .complete(build)], photos: PhotoState(failed: 0, left: 12, paused: false), mapBuild: build)
        #expect(!r.success); #expect(!r.paused); #expect(r.failed.isEmpty)
        #expect(r.subtitle == "Bản đồ 1/1 vùng · 12 ảnh chưa tải được")
        // the failed ones are among those left: counted once
        let both = OfflineJob(areas: [], photos: true).result(phases: [:], photos: PhotoState(failed: 2, left: 5, paused: false), mapBuild: build)
        #expect(!both.success); #expect(both.subtitle == "5 ảnh chưa tải được")
    }

    @Test func aJobWithoutPhotosIgnoresThem() {
        for photos in [PhotoState(failed: 3, left: 10, paused: false), PhotoState(failed: 0, left: 10, paused: true), PhotoState(failed: 1, left: 0, paused: true)] {
            let r = OfflineJob(areas: ["tokyo"], photos: false).result(phases: ["tokyo": .complete(build)], photos: photos, mapBuild: build)
            #expect(r == JobResult(success: true, done: 1, failed: [], paused: false, subtitle: "Xong"))
            let open = OfflineJob(areas: ["tokyo", "kyoto"], photos: false).result(phases: ["tokyo": .complete(build), "kyoto": .failed("x")], photos: photos, mapBuild: build)
            #expect(open.subtitle == "Bản đồ 1/2 vùng · 1 lỗi"); #expect(!open.paused)
        }
    }

    @Test func aJobIsSavedAndReadBack() throws {
        let job = OfflineJob(areas: ["tokyo", "kyoto"], photos: true)
        let back = try JSONDecoder().decode(OfflineJob.self, from: JSONEncoder().encode(job))
        #expect(back.areas == job.areas); #expect(back.photos)
    }

    // MARK: One area

    @Test func completeNeedsTheMaximumKnown() {
        let p = OfflineArea.phase(state: .active, completed: 10, expected: 10, maximum: .max, tag: PackTag(area: "tokyo", build: build, styleURL: ""), mapBuild: build, error: nil)
        #expect(p == .downloading(completed: 10, expected: 10))
    }

    @Test func completeByStateOrByEveryResource() {
        #expect(phase(.complete, 0, 0) == .complete(build))
        #expect(phase(.active, 10, 10) == .complete(build))
        #expect(phase(.active, 11, 10) == .complete(build))
        #expect(phase(.inactive, 10, 10) == .complete(build))
        // nothing counted yet is not everything
        #expect(phase(.active, 0, 0) == .downloading(completed: 0, expected: 0))
        #expect(phase(.active, 9, 10) == .downloading(completed: 9, expected: 10))
    }

    @Test func aPackSaysWhereItIs() {
        #expect(phase(.inactive, 3, 10) == .paused)
        #expect(phase(.active, 3, 10, error: "Không kết nối được, đang thử lại") == .waitingForNetwork)
        #expect(phase(.inactive, 3, 10, error: "Không kết nối được, đang thử lại") == .paused)
        #expect(phase(.invalid, 3, 10) == .failed("Vùng tải đã hỏng, tải lại"))
        // an invalid pack's context cannot be read (MapLibre raises): no tag, still broken, not stale
        #expect(phase(.invalid, 0, 0, tag: .some(nil)) == .failed("Vùng tải đã hỏng, tải lại"))
        #expect(phase(.invalid, 0, 0, tag: PackTag(area: "tokyo", build: other, styleURL: "")) == .failed("Vùng tải đã hỏng, tải lại"))
        #expect(phase(.unknown, 0, 0) == .requested)
        #expect(phase(.unknown, 0, 0, previous: .paused) == .paused)
        #expect(phase(.unknown, 0, 0, previous: .complete(build)) == .complete(build))
    }

    @Test func aCompletePackStaysCompleteWhileItCountsAgainAfterResume() {
        #expect(phase(.active, 0, 1, previous: .complete(build)) == .complete(build))
        #expect(phase(.active, 500, 1000, previous: .complete(build)) == .complete(build))
        #expect(phase(.active, 0, 1, error: "x", previous: .complete(build)) == .complete(build))
        // complete for another build says nothing about this one
        #expect(phase(.active, 0, 1, previous: .complete(other)) == .downloading(completed: 0, expected: 1))
        // a pack that is gone is gone
        #expect(phase(.invalid, 0, 1, previous: .complete(build)) == .failed("Vùng tải đã hỏng, tải lại"))
        #expect(phase(.active, 0, 1, previous: .downloading(completed: 900, expected: 1000)) == .downloading(completed: 0, expected: 1))
    }

    @Test func packOfAnotherBuildIsStale() {
        let old = PackTag(area: "tokyo", build: other, styleURL: "")
        #expect(phase(.complete, 10, 10, tag: old) == .stale(other))
        #expect(phase(.active, 3, 10, tag: old) == .stale(other))
        #expect(phase(.complete, 10, 10, tag: old, previous: .complete(build)) == .stale(other))
    }

    @Test func legacyContextIsStale() {
        #expect(phase(.complete, 10, 10, tag: .some(nil)) == .stale(nil))
        #expect(phase(.active, 3, 10, tag: .some(nil), previous: .complete(build)) == .stale(nil))
    }

    // MARK: Under way

    @Test func underWayIsAskedForBeingMadeDownloadingOrWaiting() {
        let going: [AreaPhase] = [.requested, .creating, .downloading(completed: 1, expected: 2), .waitingForNetwork]
        let stopped: [AreaPhase] = [.paused, .complete(build), .complete(other), .stale(nil), .stale(other), .failed("x")]
        for p in going { #expect(p.isUnderWay, "\(p)") }
        for p in stopped { #expect(!p.isUnderWay, "\(p)") }
    }

    // MARK: What a refresh makes of an area

    @Test func aPackForTheMapsBuildSaysWhereTheAreaIs() {
        for p: AreaPhase in [.requested, .downloading(completed: 3, expected: 10), .waitingForNetwork, .paused, .complete(build)] {
            for previous: AreaPhase? in [nil, .failed("x"), .creating, .requested, .complete(build)] {
                for requested in [false, true] {
                    #expect(OfflineArea.settle(current: p, older: nil, previous: previous, requested: requested)
                            == OfflineArea.Settled(phase: p, make: false, dropOld: false))
                }
            }
        }
    }

    @Test func aFailedAreaIsNeverForgotten() {
        // a pack that could not be made leaves the area with no pack: a refresh used to forget it, reason and all
        for requested in [false, true] {
            for older: AreaPhase? in [nil, .stale(other), .stale(nil)] {
                let s = OfflineArea.settle(current: nil, older: older, previous: .failed("Không tạo được vùng tải"), requested: requested)
                #expect(s.phase == .failed("Không tạo được vùng tải"))
                // made again by a tap or at the next launch, never by a refresh: one runs on every change of the packs
                #expect(!s.make)
                #expect(!s.dropOld)
            }
        }
    }

    @Test func anAreaBeingMadeIsLeftAlone() {
        // paused while it is made (not asked for any more): still made, then left inactive
        for requested in [false, true] {
            for older: AreaPhase? in [nil, .stale(other)] {
                #expect(OfflineArea.settle(current: nil, older: older, previous: .creating, requested: requested)
                        == OfflineArea.Settled(phase: .creating, make: false, dropOld: false))
            }
        }
    }

    @Test func anAreaAskedForWithNoPackForTheMapIsMadeAgain() {
        // after a relaunch (a failure of the last one included), after the map moved to another build, or asked for
        // before MapLibre had read its packs
        let previous: [AreaPhase?] = [nil, .requested, .downloading(completed: 5, expected: 10), .complete(other), .complete(build),
                                      .paused, .waitingForNetwork, .stale(nil)]
        for p in previous {
            for older: AreaPhase? in [nil, .stale(other), .stale(nil)] {
                #expect(OfflineArea.settle(current: nil, older: older, previous: p, requested: true)
                        == OfflineArea.Settled(phase: .requested, make: true, dropOld: false))
            }
        }
    }

    @Test func aPackOfAnotherBuildIsStaleUntilTheAreaIsAskedFor() {
        for previous: AreaPhase? in [nil, .complete(build), .downloading(completed: 1, expected: 2), .paused, .requested] {
            #expect(OfflineArea.settle(current: nil, older: .stale(other), previous: previous, requested: false)
                    == OfflineArea.Settled(phase: .stale(other), make: false, dropOld: false))
            #expect(OfflineArea.settle(current: nil, older: .stale(nil), previous: previous, requested: false)
                    == OfflineArea.Settled(phase: .stale(nil), make: false, dropOld: false))
        }
    }

    @Test func anAreaWithNothingIsNothing() {
        for previous: AreaPhase? in [nil, .requested, .paused, .complete(build), .downloading(completed: 1, expected: 2), .stale(other)] {
            #expect(OfflineArea.settle(current: nil, older: nil, previous: previous, requested: false)
                    == OfflineArea.Settled(phase: nil, make: false, dropOld: false))
        }
    }

    @Test func anOlderPackGoesOnlyOnceTheNewOneIsComplete() {
        // while the new one downloads the old one is kept (MapLibre stores a resource once for every pack using it)
        for p: AreaPhase in [.requested, .downloading(completed: 9, expected: 10), .waitingForNetwork, .paused] {
            for requested in [false, true] {
                #expect(!OfflineArea.settle(current: p, older: .stale(other), previous: nil, requested: requested).dropOld)
            }
        }
        #expect(OfflineArea.settle(current: .complete(build), older: .stale(other), previous: .downloading(completed: 9, expected: 10), requested: false)
                == OfflineArea.Settled(phase: .complete(build), make: false, dropOld: true))
        #expect(OfflineArea.settle(current: .complete(build), older: .stale(nil), previous: nil, requested: true).dropOld)
        #expect(!OfflineArea.settle(current: .complete(build), older: nil, previous: nil, requested: false).dropOld)
    }

    // MARK: The style a pack is made from

    @Test func aPackHoldsTheBuildOfItsStyleOrOfTheTileJSONItNames() {
        let pinned = Data(#"{"version":8,"sources":{"omt":{"type":"vector","tiles":["\#(build.template)"]}}}"#.utf8)
        let current = Data(#"{"version":8,"sources":{"omt":{"type":"vector","url":"https://tiles.openfreemap.org/planet"}}}"#.utf8)
        func tileJSON(_ b: TileBuild) -> Data { Data(#"{"tilejson":"3.0.0","tiles":["\#(b.template)"]}"#.utf8) }
        #expect(OfflineArea.packBuild(style: pinned, tileJSON: nil, mapBuild: build) == build)
        // the style's own tiles decide: a TileJSON beside them changes nothing
        #expect(OfflineArea.packBuild(style: pinned, tileJSON: tileJSON(other), mapBuild: build) == build)
        #expect(OfflineArea.packBuild(style: pinned, tileJSON: tileJSON(other), mapBuild: other) == nil)
        #expect(OfflineArea.packBuild(style: pinned, tileJSON: nil, mapBuild: other) == nil)
        #expect(OfflineArea.packBuild(style: current, tileJSON: tileJSON(build), mapBuild: build) == build)
        #expect(OfflineArea.packBuild(style: current, tileJSON: tileJSON(other), mapBuild: build) == nil)
        #expect(OfflineArea.packBuild(style: current, tileJSON: nil, mapBuild: build) == nil)
        #expect(OfflineArea.packBuild(style: current, tileJSON: Data("<html>".utf8), mapBuild: build) == nil)
        // a page that is not a style (the site's 404 page) holds nothing, whatever the TileJSON says
        for page in [Data("<html>Not found</html>".utf8), Data(#"{"version":8,"sources":{}}"#.utf8)] {
            #expect(OfflineArea.packBuild(style: page, tileJSON: tileJSON(build), mapBuild: build) == nil)
            #expect(OfflineArea.packBuild(style: page, tileJSON: nil, mapBuild: build) == nil)
        }
    }

    @Test func theShippedStylesMakePacksOfTheirBuild() throws {
        let bundled = try Bundle_.data("../public/map/jp27-light.json")
        let pinned = try #require(StyleInfo.build(style: bundled))
        let name = try #require(StyleInfo.styleBuild(style: bundled))
        let immutable = try Bundle_.data("../public/map/jp27-light@\(name).json")
        #expect(OfflineArea.packBuild(style: immutable, tileJSON: nil, mapBuild: pinned) == pinned)
        #expect(OfflineArea.packBuild(style: immutable, tileJSON: nil, mapBuild: other) == nil)
        let current = try Bundle_.data("../public/map/jp27-light-current.json")
        #expect(OfflineArea.packBuild(style: current, tileJSON: Data(#"{"tiles":["\#(other.template)"]}"#.utf8), mapBuild: other) == other)
        #expect(OfflineArea.packBuild(style: current, tileJSON: nil, mapBuild: pinned) == nil)
    }

    @Test func theCurrentStyleIsTheBundledOneOnTheResolvedBuild() throws {
        let bundled = try Bundle_.data("../public/map/jp27-light.json")
        let out = try #require(StyleInfo.pointing(style: bundled, at: other.template))
        #expect(StyleInfo.build(style: out) == other)
        // the metadata named the bundled build and its immutable copy: this style is neither
        #expect(StyleInfo.styleBuild(style: out) == nil)
        let json = try #require(JSONSerialization.jsonObject(with: out) as? [String: Any])
        let was = try #require(JSONSerialization.jsonObject(with: bundled) as? [String: Any])
        #expect(((json["metadata"] as? [String: Any]) ?? [:]).keys.allSatisfy { !$0.hasPrefix("jp27:") })
        let omt = try #require((json["sources"] as? [String: Any])?["omt"] as? [String: Any])
        #expect(omt["url"] == nil)
        #expect(omt["tiles"] as? [String] == [other.template])
        #expect(omt["minzoom"] as? Int == 0)
        #expect(omt["maxzoom"] as? Int == 14)
        // the rest is the bundled style
        #expect((json["layers"] as? [Any])?.count == (was["layers"] as? [Any])?.count)
        #expect(json["glyphs"] as? String == was["glyphs"] as? String)
        #expect((json["sources"] as? [String: Any])?.count == (was["sources"] as? [String: Any])?.count)
        // a style on a TileJSON (`url`) is pointed at the build too; other metadata stays
        let viaURL = Data(#"{"version":8,"metadata":{"jp27:build":"b-1","jp27:tiles":"t","keep":1},"sources":{"omt":{"type":"vector","url":"https://tiles.openfreemap.org/planet"}}}"#.utf8)
        let pointed = try #require(StyleInfo.pointing(style: viaURL, at: build.template))
        #expect(StyleInfo.build(style: pointed) == build)
        let p = try #require(JSONSerialization.jsonObject(with: pointed) as? [String: Any])
        #expect(((p["sources"] as? [String: Any])?["omt"] as? [String: Any])?["url"] == nil)
        #expect((p["metadata"] as? [String: Any])?.keys.sorted() == ["keep"])
        for junk in [Data("<html>".utf8), Data(#"{"sources":{}}"#.utf8), Data(#"{"version":8}"#.utf8), Data(#"{"sources":{"omt":1}}"#.utf8)] {
            #expect(StyleInfo.pointing(style: junk, at: build.template) == nil)
        }
    }

    // MARK: The pack's context

    @Test func aTagIsReadBackFromItsContext() throws {
        let tag = PackTag(area: "kyoto", build: build, styleURL: "https://jpy27.delphyra.tech/map/jp27-light@x.json")
        let json = try #require(JSONSerialization.jsonObject(with: tag.context) as? [String: Any])
        #expect(json["v"] as? Int == 2)
        #expect(PackTag.read(tag.context) == tag)
        #expect(PackTag.area(of: tag.context) == "kyoto")
    }

    @Test func olderContextsHaveNoTagButKeepTheirArea() {
        let v1 = Data(#"{"area":"tokyo","tiles":"https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf"}"#.utf8)
        #expect(PackTag.read(v1) == nil)
        #expect(PackTag.area(of: v1) == "tokyo")
        let plain = Data("kawaguchiko".utf8)
        #expect(PackTag.read(plain) == nil)
        #expect(PackTag.area(of: plain) == "kawaguchiko")
        let v3 = Data(#"{"v":3,"area":"nara","build":{"template":"t"},"styleURL":""}"#.utf8)
        #expect(PackTag.read(v3) == nil)
        #expect(PackTag.area(of: v3) == "nara")
        for junk in [Data(), Data([0xff, 0xfe]), Data(#"{"foo":1}"#.utf8), Data(#"{"area":""}"#.utf8), Data("Tokyo city".utf8)] {
            #expect(PackTag.read(junk) == nil)
            #expect(PackTag.area(of: junk) == nil)
        }
    }

    // MARK: Styles

    @Test func theTilesAreReadFromAStyleOrATileJSON() {
        let style = Data(#"{"version":8,"sources":{"dem":{"type":"raster-dem","tiles":[1]},"omt":{"type":"vector","tiles":["\#(build.template)","b"]}},"layers":[]}"#.utf8)
        #expect(StyleInfo.build(style: style) == build)
        let tileJSON = Data(#"{"tilejson":"3.0.0","tiles":["\#(other.template)"],"maxzoom":14}"#.utf8)
        #expect(StyleInfo.build(tileJSON: tileJSON) == other)
        #expect(StyleInfo.build(style: tileJSON) == nil)
        #expect(StyleInfo.build(tileJSON: style) == nil)
        let viaTileJSON = Data(#"{"version":8,"sources":{"omt":{"type":"vector","url":"https://tiles.openfreemap.org/planet"}}}"#.utf8)
        #expect(StyleInfo.build(style: viaTileJSON) == nil)
        #expect(StyleInfo.build(style: Data(#"{"sources":{"omt":{"tiles":[]}}}"#.utf8)) == nil)
        #expect(StyleInfo.build(style: Data(#"{"sources":{"omt":{"tiles":[""]}}}"#.utf8)) == nil)
        #expect(StyleInfo.build(tileJSON: Data(#"{"tiles":[""]}"#.utf8)) == nil)
        #expect(StyleInfo.build(style: Data("<html>".utf8)) == nil)
        #expect(StyleInfo.styleBuild(style: Data(#"{"metadata":{"jp27:build":"b-1"},"sources":{}}"#.utf8)) == "b-1")
        #expect(StyleInfo.styleBuild(style: Data(#"{"metadata":{"other":1},"sources":{}}"#.utf8)) == nil)
        #expect(StyleInfo.styleBuild(style: Data(#"{"metadata":{"jp27:build":""}}"#.utf8)) == nil)
        #expect(StyleInfo.styleBuild(style: style) == nil)
        // each reader reads its own part: an odd value in the other part does not hide it
        let oddName = Data(#"{"metadata":{"jp27:build":5},"sources":{"omt":{"tiles":["\#(build.template)"]}}}"#.utf8)
        #expect(StyleInfo.build(style: oddName) == build)
        #expect(StyleInfo.styleBuild(style: oddName) == nil)
        let oddTiles = Data(#"{"metadata":{"jp27:build":"b-1"},"sources":{"omt":{"tiles":[1]}}}"#.utf8)
        #expect(StyleInfo.styleBuild(style: oddTiles) == "b-1")
        #expect(StyleInfo.build(style: oddTiles) == nil)
    }

    /// The styles the app ships and the site serves (scripts/export-ios.mjs): each pins an OpenFreeMap
    /// build, says so in its metadata, and has its immutable copy, named by the build and the style's
    /// content, next to it. Read from the files, so a re-pin needs no change here.
    @Test(arguments: ["light", "dark"]) func tilesTemplateIsReadFromTheShippedStyle(theme: String) throws {
        let data = try Bundle_.data("../public/map/jp27-\(theme).json")
        let tiles = try #require(StyleInfo.build(style: data)).template
        let match = try #require(tiles.wholeMatch(of: /https:\/\/tiles\.openfreemap\.org\/planet\/([^\/]+)\/\{z\}\/\{x\}\/\{y\}\.pbf/))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let metadata = try #require(json["metadata"] as? [String: Any])
        #expect(metadata["jp27:tiles"] as? String == tiles)
        let name = try #require(StyleInfo.styleBuild(style: data))
        #expect(name.wholeMatch(of: /[^\/]+-[0-9a-f]{8}/) != nil)
        #expect(name.hasPrefix("\(match.1)-"))
        let pinned = try Bundle_.data("../public/map/jp27-\(theme)@\(name).json")
        #expect(StyleInfo.styleBuild(style: pinned) == name)
        #expect(StyleInfo.build(style: pinned)?.template == tiles)
        // the fallback names no build: its tiles come from the TileJSON
        let current = try Bundle_.data("../public/map/jp27-\(theme)-current.json")
        #expect(StyleInfo.build(style: current) == nil)
        #expect(StyleInfo.styleBuild(style: current) == nil)
    }
}

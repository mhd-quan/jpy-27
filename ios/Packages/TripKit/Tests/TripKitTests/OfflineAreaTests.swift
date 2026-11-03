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
            .result(phases: ["tokyo": .complete(build), "kyoto": .failed("Không tạo được vùng tải")], photosFailed: 0, mapBuild: build)
        #expect(!r.success); #expect(r.failed == ["kyoto"]); #expect(r.subtitle != "Xong")
        #expect(r.done == 1)
        #expect(r.subtitle == "Bản đồ 1/2 vùng · 1 lỗi")
    }

    @Test func mapOnlyJobIsDoneOnlyWhenEveryAreaIsComplete() {
        let job = OfflineJob(areas: ["tokyo", "kyoto", "nara"], photos: false)
        let running = job.result(phases: ["tokyo": .complete(build), "kyoto": .complete(build), "nara": .downloading(completed: 5, expected: 10)],
                                 photosFailed: 0, mapBuild: build)
        #expect(!running.success); #expect(running.done == 2); #expect(running.failed.isEmpty); #expect(!running.paused)
        #expect(running.subtitle == "Bản đồ 2/3 vùng")
        let done = job.result(phases: ["tokyo": .complete(build), "kyoto": .complete(build), "nara": .complete(build)],
                              photosFailed: 0, mapBuild: build)
        #expect(done == JobResult(success: true, done: 3, failed: [], paused: false, subtitle: "Xong"))
    }

    @Test func pausedIsNotDone() {
        let r = OfflineJob(areas: ["tokyo", "kyoto", "nara"], photos: false)
            .result(phases: ["tokyo": .complete(build), "kyoto": .paused, "nara": .failed("x")], photosFailed: 0, mapBuild: build)
        #expect(!r.success); #expect(r.paused); #expect(r.subtitle == "Đã dừng")
        #expect(r.failed == ["nara"]); #expect(r.done == 1)
    }

    @Test func waitingRegionIsNotComplete() {
        let r = OfflineJob(areas: ["tokyo", "kyoto"], photos: false)
            .result(phases: ["tokyo": .complete(build), "kyoto": .waitingForNetwork], photosFailed: 0, mapBuild: build)
        #expect(!r.success); #expect(r.failed.isEmpty); #expect(!r.paused); #expect(r.done == 1)
    }

    @Test func anAreaOfAnotherBuildOrStaleIsAFailureNotDone() {
        let r = OfflineJob(areas: ["tokyo", "kyoto", "nara", "osaka"], photos: false)
            .result(phases: ["tokyo": .complete(other), "kyoto": .stale(other), "nara": .stale(nil), "osaka": .complete(build)],
                    photosFailed: 0, mapBuild: build)
        #expect(!r.success); #expect(r.done == 1)
        #expect(r.failed == ["kyoto", "nara", "tokyo"])
        #expect(r.subtitle == "Bản đồ 1/4 vùng · 3 lỗi")
        let many = ["a", "b", "c", "d", "e", "f"]
        let all = OfflineJob(areas: Set(many), photos: false)
            .result(phases: Dictionary(uniqueKeysWithValues: many.map { ($0, AreaPhase.failed("x")) }), photosFailed: 0, mapBuild: build)
        #expect(all.failed == many)
    }

    @Test func anAreaNobodyKnowsIsNeitherDoneNorFailed() {
        let r = OfflineJob(areas: ["tokyo", "kyoto"], photos: false)
            .result(phases: ["tokyo": .complete(build)], photosFailed: 0, mapBuild: build)
        #expect(!r.success); #expect(r.done == 1); #expect(r.failed.isEmpty); #expect(r.subtitle == "Bản đồ 1/2 vùng")
        for p: AreaPhase in [.requested, .creating] {
            let s = OfflineJob(areas: ["kyoto"], photos: false).result(phases: ["kyoto": p], photosFailed: 0, mapBuild: build)
            #expect(!s.success); #expect(s.failed.isEmpty); #expect(!s.paused)
        }
    }

    @Test func photosThatFailedFailTheJobEvenWithEveryAreaDone() {
        let r = OfflineJob(areas: ["tokyo"], photos: true)
            .result(phases: ["tokyo": .complete(build)], photosFailed: 3, mapBuild: build)
        #expect(!r.success); #expect(r.done == 1); #expect(r.failed.isEmpty)
        #expect(r.subtitle == "Bản đồ 1/1 vùng · 3 ảnh chưa tải được")
        let photosOnly = OfflineJob(areas: [], photos: true).result(phases: [:], photosFailed: 2, mapBuild: build)
        #expect(!photosOnly.success); #expect(photosOnly.subtitle == "2 ảnh chưa tải được")
        let fine = OfflineJob(areas: [], photos: true).result(phases: [:], photosFailed: 0, mapBuild: build)
        #expect(fine.success); #expect(fine.subtitle == "Xong")
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

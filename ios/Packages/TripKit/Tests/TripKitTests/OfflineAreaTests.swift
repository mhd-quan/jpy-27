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

    @Test func anAreaRemovedDuringTheJobIsNeitherDoneNorFailedAndTheEndSaysSo() {
        // Xoá on its row clears its phase: the job still counts it, so its end line gives the reason
        let r = OfflineJob(areas: ["tokyo", "kyoto"], photos: false)
            .result(phases: ["tokyo": .complete(build)], photos: .finished, mapBuild: build)
        #expect(!r.success); #expect(r.done == 1); #expect(r.failed.isEmpty); #expect(r.subtitle == "Bản đồ 1/2 vùng · 1 vùng đã xoá")
        let two = OfflineJob(areas: ["tokyo", "kyoto", "nara"], photos: false)
            .result(phases: ["tokyo": .failed("x")], photos: .finished, mapBuild: build)
        #expect(two.subtitle == "Bản đồ 0/3 vùng · 1 lỗi · 2 vùng đã xoá")
        // a pause still reads as one
        #expect(OfflineJob(areas: ["tokyo", "kyoto"], photos: false).result(phases: ["tokyo": .paused], photos: .finished, mapBuild: build)
                .subtitle == "Đã dừng")
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

    // MARK: The extras: day maps, Fuji, forecasts

    /// every area of `job` complete, the photos on disk
    func ended(_ job: OfflineJob, extras: [OfflineExtra: ExtraState] = [:], ready: [ReadyItem: ReadyState] = [:],
               photos: PhotoState = .finished) -> JobResult {
        job.result(phases: Dictionary(uniqueKeysWithValues: job.areas.map { ($0, AreaPhase.complete(build)) }), photos: photos,
                   mapBuild: build, extras: extras, ready: ready)
    }

    /// every item ready, with `changes` over it
    func ready(_ changes: [ReadyItem: ReadyState] = [:]) -> [ReadyItem: ReadyState] {
        var all = Dictionary(uniqueKeysWithValues: ReadyItem.allCases.map { ($0, ReadyState.ready) })
        all.merge(changes) { _, new in new }
        return all
    }

    let allDone: [OfflineExtra: ExtraState] = [
        .dayMaps: ExtraState(done: 13, total: 13, paused: false),
        .fuji: ExtraState(done: 69, total: 69, paused: false),
        .forecasts: ExtraState(done: 32, total: 32, paused: false),
    ]

    @Test func anExtraIsAnItemOfTheReadinessList() {
        // the raw values are saved with the job
        #expect(OfflineExtra.allCases.map(\.rawValue) == ["dayMaps", "fuji", "forecasts"])
        #expect(OfflineExtra.allCases.map(\.item) == [.dayMaps, .fuji, .forecasts])
        for item in ReadyItem.allCases {
            let extra = OfflineExtra(item)
            #expect(extra?.item == ([.dayMaps, .fuji, .forecasts].contains(item) ? item : nil))
        }
    }

    @Test func tảiTấtCảTakesTheExtrasMissingAndRecountsThePicturesThatAreThere() {
        // every item ready: the day maps and Fuji still go, only to count from the disk and keep their names from the
        // launch trim; the forecasts, fresh, do not
        #expect(OfflineExtra.forEverything(ready()) == [.dayMaps, .fuji])
        #expect(OfflineExtra.forEverything(ready([.forecasts: .missing(done: 30, total: 32)])) == [.dayMaps, .fuji, .forecasts])
        // a page to open first: nothing to draw them at, so left out
        #expect(OfflineExtra.forEverything(ready([.dayMaps: .needsSetup("Mở trang Hôm nay một lần"), .fuji: .needsSetup("Mở trang Fuji một lần")])).isEmpty)
        // not read yet, missing, under way, failed: taken
        for state: ReadyState? in [nil, .missing(done: 3, total: 13), .working(0.5), .waitingForNetwork, .failed("x")] {
            var s = ready()
            s[.fuji] = state
            s[.forecasts] = state
            #expect(OfflineExtra.forEverything(s) == [.dayMaps, .fuji, .forecasts])
        }
        // the other items take no extra
        #expect(OfflineExtra.forEverything(ready([.maps: .missing(done: 0, total: 11), .translation: .missing(done: nil, total: nil)])) == [.dayMaps, .fuji])
        #expect(OfflineExtra.forEverything(ready([.fuji: .unsupported("x")])) == [.dayMaps])
    }

    @Test func decodesJobSavedBeforeExtras() throws {
        let job = try JSONDecoder().decode(OfflineJob.self, from: Data(#"{"areas":["tokyo"],"photos":true}"#.utf8))
        #expect(job.areas == ["tokyo"]); #expect(job.photos); #expect(job.extras == []); #expect(!job.everything)
    }

    @Test func aJobWithExtrasIsSavedAndReadBackAndAnOlderBuildStillReadsIt() throws {
        let job = OfflineJob(areas: ["tokyo"], photos: true, extras: [.dayMaps, .forecasts], everything: true)
        let data = try JSONEncoder().encode(job)
        let back = try JSONDecoder().decode(OfflineJob.self, from: data)
        #expect(back.areas == ["tokyo"]); #expect(back.photos); #expect(back.extras == [.dayMaps, .forecasts]); #expect(back.everything)
        let plain = try JSONDecoder().decode(OfflineJob.self, from: JSONEncoder().encode(OfflineJob(areas: [], photos: false, extras: [.fuji])))
        #expect(plain.extras == [.fuji]); #expect(!plain.everything); #expect(plain.areas.isEmpty); #expect(!plain.photos)
        // the form an earlier build reads: its two keys as they were, the new ones beside them
        struct Earlier: Decodable { let areas: Set<String>; let photos: Bool }
        let earlier = try JSONDecoder().decode(Earlier.self, from: data)
        #expect(earlier.areas == ["tokyo"]); #expect(earlier.photos)
    }

    @Test func anExtraThisBuildDoesNotKnowIsDroppedNotTheJob() throws {
        func read(_ json: String) throws -> OfflineJob { try JSONDecoder().decode(OfflineJob.self, from: Data(json.utf8)) }
        // a later build's name, read after a downgrade: the others and the areas stay
        let later = try read(#"{"areas":["tokyo"],"photos":true,"extras":["fuji","tides","dayMaps"],"everything":true}"#)
        #expect(later.extras == [.fuji, .dayMaps]); #expect(later.areas == ["tokyo"]); #expect(later.photos); #expect(later.everything)
        // garbled values: no extras, not everything, the rest kept
        for json in [#"{"areas":["kyoto"],"photos":true,"extras":"fuji","everything":"yes"}"#,
                     #"{"areas":["kyoto"],"photos":true,"extras":[1,2],"everything":null}"#,
                     #"{"areas":["kyoto"],"photos":true,"extras":null}"#] {
            let job = try read(json)
            #expect(job.extras == []); #expect(!job.everything); #expect(job.areas == ["kyoto"]); #expect(job.photos)
        }
    }

    @Test func extrasMustFinishForSuccess() {
        let job = OfflineJob(areas: ["tokyo"], photos: true, extras: [.dayMaps])
        let r = ended(job, extras: [.dayMaps: ExtraState(done: 20, total: 24, paused: false)])
        #expect(!r.success); #expect(!r.paused); #expect(r.done == 1); #expect(r.failed.isEmpty)
        #expect(r.subtitle.contains("Ảnh bản đồ 20/24 ngày"))
        #expect(r.subtitle == "Bản đồ 1/1 vùng · Ảnh bản đồ 20/24 ngày")
        // the extras alone are the job
        let alone = ended(OfflineJob(areas: [], photos: false, extras: [.dayMaps]), extras: [.dayMaps: ExtraState(done: 20, total: 24, paused: false)])
        #expect(!alone.success); #expect(alone.subtitle == "Ảnh bản đồ 20/24 ngày")
        // one short of all
        let one = ended(OfflineJob(areas: [], photos: false, extras: [.fuji]), extras: [.fuji: ExtraState(done: 68, total: 69, paused: false)])
        #expect(!one.success); #expect(one.subtitle == "Fuji 68/69 ảnh")
    }

    @Test func extrasDoneIsSuccess() {
        let job = OfflineJob(areas: ["tokyo"], photos: true, extras: [.dayMaps, .fuji, .forecasts])
        #expect(ended(job, extras: allDone) == JobResult(success: true, done: 1, failed: [], paused: false, subtitle: "Xong"))
        // nothing to draw is nothing missing, and a count over its total is all there
        let none = ended(OfflineJob(areas: [], photos: false, extras: [.dayMaps, .fuji]),
                         extras: [.dayMaps: ExtraState(done: 0, total: 0, paused: false), .fuji: ExtraState(done: 70, total: 69, paused: false)])
        #expect(none == JobResult(success: true, done: 0, failed: [], paused: false, subtitle: "Xong"))
        // the extras done do not make up for the rest
        let photos = ended(job, extras: allDone, photos: PhotoState(failed: 0, left: 2, paused: false))
        #expect(!photos.success); #expect(photos.subtitle == "Bản đồ 1/1 vùng · 2 ảnh chưa tải được")
        let maps = job.result(phases: ["tokyo": .failed("x")], photos: .finished, mapBuild: build, extras: allDone)
        #expect(!maps.success); #expect(maps.subtitle == "Bản đồ 0/1 vùng · 1 lỗi")
    }

    @Test func extraSubtitles() {
        let fuji = ended(OfflineJob(areas: [], photos: false, extras: [.fuji]), extras: [.fuji: ExtraState(done: 60, total: 70, paused: false)])
        #expect(fuji.subtitle == "Fuji 60/70 ảnh"); #expect(!fuji.success)
        let stale = ended(OfflineJob(areas: [], photos: false, extras: [.forecasts]), extras: [.forecasts: ExtraState(done: 30, total: 32, paused: false)])
        #expect(stale.subtitle == "Dự báo chưa mới"); #expect(!stale.success)
        // only the job's own extras are looked at: the others' states, failing or paused, change nothing
        let others: [OfflineExtra: ExtraState] = [
            .dayMaps: ExtraState(done: 0, total: 13, paused: false),
            .fuji: ExtraState(done: 60, total: 70, paused: false),
            .forecasts: ExtraState(done: 0, total: 32, paused: true),
        ]
        let onlyFuji = ended(OfflineJob(areas: [], photos: false, extras: [.fuji]), extras: others)
        #expect(onlyFuji.subtitle == "Fuji 60/70 ảnh"); #expect(!onlyFuji.paused)
        #expect(ended(OfflineJob(areas: ["tokyo"], photos: false), extras: others) == JobResult(success: true, done: 1, failed: [], paused: false, subtitle: "Xong"))
        // an extra of the job with no state is not done, and says so
        let uncounted = ended(OfflineJob(areas: [], photos: false, extras: [.dayMaps, .fuji, .forecasts]))
        #expect(!uncounted.success); #expect(!uncounted.paused)
        #expect(uncounted.subtitle == "Ảnh bản đồ chưa tải · Fuji chưa tải · Dự báo chưa mới")
        for extra in OfflineExtra.allCases {
            var some = allDone
            some[extra] = nil
            let r = ended(OfflineJob(areas: ["tokyo"], photos: true, extras: Set(OfflineExtra.allCases)), extras: some)
            #expect(!r.success)
            #expect(r.subtitle == "Bản đồ 1/1 vùng · " + ["Ảnh bản đồ chưa tải", "Fuji chưa tải", "Dự báo chưa mới"][OfflineExtra.allCases.firstIndex(of: extra)!])
        }
    }

    @Test func theEndLineKeepsOneOrderWhateverTheSet() {
        // a set of three is listed in any order: the line follows the readiness list's
        let job = OfflineJob(areas: ["tokyo", "kyoto", "nara"], photos: true, extras: [.forecasts, .fuji, .dayMaps])
        let r = job.result(phases: ["tokyo": .complete(build), "kyoto": .failed("x")], photos: PhotoState(failed: 1, left: 3, paused: false),
                           mapBuild: build, extras: [
                               .forecasts: ExtraState(done: 31, total: 32, paused: false),
                               .fuji: ExtraState(done: 60, total: 69, paused: false),
                               .dayMaps: ExtraState(done: 12, total: 13, paused: false),
                           ])
        #expect(r.subtitle == "Bản đồ 1/3 vùng · 1 lỗi · 1 vùng đã xoá · 3 ảnh chưa tải được · Ảnh bản đồ 12/13 ngày · Fuji 60/69 ảnh · Dự báo chưa mới")
        #expect(r.done == 1); #expect(r.failed == ["kyoto"]); #expect(!r.paused)
    }

    @Test func pausedExtraIsPaused() {
        let job = OfflineJob(areas: ["tokyo"], photos: true, extras: [.dayMaps, .fuji, .forecasts])
        for extra in OfflineExtra.allCases {
            // never counted, partway, or all there: a pause the travellers made is a pause
            for state in [ExtraState(done: 0, total: 0, paused: true), ExtraState(done: 3, total: 13, paused: true), ExtraState(done: 13, total: 13, paused: true)] {
                var states = allDone
                states[extra] = state
                let r = ended(job, extras: states)
                #expect(!r.success); #expect(r.paused); #expect(r.subtitle == "Đã dừng"); #expect(r.done == 1)
            }
        }
        // paused over the other parts' words
        let more = job.result(phases: ["tokyo": .failed("x")], photos: PhotoState(failed: 0, left: 5, paused: false), mapBuild: build,
                              extras: [.fuji: ExtraState(done: 1, total: 69, paused: true)])
        #expect(more.paused); #expect(more.subtitle == "Đã dừng"); #expect(more.failed == ["tokyo"])
    }

    // MARK: Tải tất cả: every item, judged after one more look

    @Test func tảiTấtCảIsXongOnlyWhenEveryItemIsReady() {
        let job = OfflineJob(areas: ["tokyo"], photos: true, extras: Set(OfflineExtra.allCases), everything: true)
        #expect(ended(job, extras: allDone, ready: ready()) == JobResult(success: true, done: 1, failed: [], paused: false, subtitle: "Xong"))
        // a phone that cannot have a pack is not missing it
        let cannot = ready([.translation: .unsupported("Máy này chưa dịch được Nhật sang Việt"), .speech: .unsupported("Máy này chưa nghe được tiếng Nhật")])
        #expect(ended(job, extras: allDone, ready: cannot).subtitle == "Xong")
        // the packs: asked for, not there by the end (the job's areas said as every job says them)
        let packs = ended(job, extras: allDone, ready: ready([.translation: .missing(done: nil, total: nil), .speech: .working(0.4)]))
        #expect(!packs.success); #expect(!packs.paused); #expect(packs.done == 1)
        #expect(packs.subtitle == "Bản đồ 1/1 vùng · Gói dịch chưa tải · Gói nghe chưa tải")
        #expect(ended(job, extras: allDone, ready: ready([.speech: .failed("Không có mạng")])).subtitle == "Bản đồ 1/1 vùng · Gói nghe chưa tải")
        #expect(ended(job, extras: allDone, ready: ready([.translation: .waitingForNetwork])).subtitle == "Bản đồ 1/1 vùng · Gói dịch chưa tải")
        // an item not read is not ready
        var unread = ready()
        unread[.speech] = nil
        #expect(ended(job, extras: allDone, ready: unread).subtitle == "Bản đồ 1/1 vùng · Gói nghe chưa tải")
        #expect(ended(job, extras: allDone, ready: [:]).subtitle
            == "Bản đồ chưa tải · Ảnh quán, khách sạn chưa tải · Ảnh bản đồ chưa tải · Fuji chưa tải · Dự báo chưa mới · Gói dịch chưa tải · Gói nghe chưa tải")
    }

    @Test func tảiTấtCảSaysWhatAPageMustBeOpenedForAsMissing() {
        // not worked (nothing to fetch them at), still judged at the end
        let job = OfflineJob(areas: [], photos: true, extras: [.forecasts], everything: true)
        let r = ended(job, extras: [.forecasts: ExtraState(done: 32, total: 32, paused: false)],
                      ready: ready([.dayMaps: .needsSetup("Mở trang Hôm nay một lần"), .fuji: .needsSetup("Mở trang Fuji một lần")]))
        #expect(!r.success); #expect(r.subtitle == "Ảnh bản đồ chưa tải · Fuji chưa tải")
        // counted by the look: their counts
        let counted = ended(job, extras: [.forecasts: ExtraState(done: 32, total: 32, paused: false)],
                            ready: ready([.dayMaps: .missing(done: 12, total: 13), .fuji: .missing(done: 60, total: 69), .forecasts: .missing(done: 30, total: 32)]))
        #expect(counted.subtitle == "Ảnh bản đồ 12/13 ngày · Fuji 60/69 ảnh · Dự báo chưa mới")
        // a count with a part unknown is no count
        #expect(ended(job, extras: [.forecasts: ExtraState(done: 32, total: 32, paused: false)], ready: ready([.fuji: .missing(done: 3, total: nil)])).subtitle
            == "Fuji chưa tải")
        #expect(ended(job, extras: [.forecasts: ExtraState(done: 32, total: 32, paused: false)], ready: ready([.dayMaps: .missing(done: nil, total: 13)])).subtitle
            == "Ảnh bản đồ chưa tải")
    }

    @Test func tảiTấtCảSaysEachItemOnce() {
        let job = OfflineJob(areas: ["tokyo", "kyoto"], photos: true, extras: Set(OfflineExtra.allCases), everything: true)
        var states = allDone
        states[.dayMaps] = ExtraState(done: 12, total: 13, paused: false)
        states[.fuji] = nil
        // the job's own count first; the look's count where the job has none
        let r = job.result(phases: ["tokyo": .complete(build), "kyoto": .downloading(completed: 1, expected: 2)],
                           photos: PhotoState(failed: 0, left: 3, paused: false), mapBuild: build, extras: states,
                           ready: ready([.maps: .missing(done: 10, total: 11), .photos: .missing(done: 170, total: 180),
                                         .dayMaps: .missing(done: 11, total: 13), .fuji: .missing(done: 50, total: 69)]))
        #expect(r.subtitle == "Bản đồ 1/2 vùng · 3 ảnh chưa tải được · Ảnh bản đồ 12/13 ngày · Fuji 50/69 ảnh")
        // the job's own parts all there, the look finds less (a picture trimmed, a pack of an old build): the look's words
        let later = ended(job, extras: allDone, ready: ready([.maps: .missing(done: 10, total: 11), .photos: .missing(done: 170, total: 180),
                                                               .dayMaps: .missing(done: 11, total: 13), .fuji: .missing(done: 68, total: 69),
                                                               .forecasts: .missing(done: 31, total: 32)]))
        #expect(!later.success)
        #expect(later.subtitle == "Bản đồ 10/11 vùng · 10 ảnh chưa tải được · Ảnh bản đồ 11/13 ngày · Fuji 68/69 ảnh · Dự báo chưa mới")
        // maps and photos the look cannot count
        let uncounted = ended(job, extras: allDone, ready: ready([.maps: .failed("x"), .photos: .needsSetup("x")]))
        #expect(uncounted.subtitle == "Bản đồ chưa tải · Ảnh quán, khách sạn chưa tải")
        // a count that is all there yet not ready (a photo on disk the list still waits for) is no count
        let whole = ended(job, extras: allDone, ready: ready([.photos: .missing(done: 180, total: 180), .dayMaps: .missing(done: 13, total: 13)]))
        #expect(whole.subtitle == "Bản đồ 2/2 vùng · Ảnh quán, khách sạn chưa tải · Ảnh bản đồ chưa tải")
        // no area in the job (all were there when it started), the maps not ready by the end
        let noAreas = ended(OfflineJob(areas: [], photos: false, everything: true), ready: ready([.maps: .missing(done: 10, total: 11)]))
        #expect(!noAreas.success); #expect(noAreas.subtitle == "Bản đồ 10/11 vùng")
    }

    @Test func tảiTấtCảPausedIsPaused() {
        let job = OfflineJob(areas: ["tokyo"], photos: true, extras: Set(OfflineExtra.allCases), everything: true)
        var states = allDone
        states[.fuji] = ExtraState(done: 12, total: 69, paused: true)
        let r = ended(job, extras: states, ready: ready([.fuji: .missing(done: 12, total: 69), .translation: .missing(done: nil, total: nil)]))
        #expect(!r.success); #expect(r.paused); #expect(r.subtitle == "Đã dừng")
    }

    @Test func aJobThatIsNotTảiTấtCảDoesNotLookAtTheList() {
        let job = OfflineJob(areas: ["tokyo"], photos: true, extras: Set(OfflineExtra.allCases))
        let nothing = Dictionary(uniqueKeysWithValues: ReadyItem.allCases.map { ($0, ReadyState.missing(done: 0, total: 5)) })
        #expect(ended(job, extras: allDone, ready: nothing) == JobResult(success: true, done: 1, failed: [], paused: false, subtitle: "Xong"))
        #expect(ended(job, extras: allDone, ready: [:]).subtitle == "Xong")
        // its extras without a state keep their words, not the list's counts
        #expect(ended(job, extras: [:], ready: nothing).subtitle == "Bản đồ 1/1 vùng · Ảnh bản đồ chưa tải · Fuji chưa tải · Dự báo chưa mới")
    }

    @Test func theEndLineIsNeverEmpty() {
        let phases: [[String: AreaPhase]] = [[:], ["tokyo": .complete(build)], ["tokyo": .failed("x")], ["tokyo": .paused], ["tokyo": .waitingForNetwork]]
        let photoStates = [PhotoState.finished, PhotoState(failed: 1, left: 1, paused: false), PhotoState(failed: 0, left: 4, paused: true)]
        let extraStates: [ExtraState?] = [nil, ExtraState(done: 0, total: 0, paused: false), ExtraState(done: 2, total: 5, paused: false),
                                          ExtraState(done: 5, total: 5, paused: false), ExtraState(done: 1, total: 5, paused: true)]
        let readies: [[ReadyItem: ReadyState]] = [[:], ready(), ready([.translation: .missing(done: nil, total: nil)]),
                                                  ready([.maps: .missing(done: 1, total: 2), .dayMaps: .needsSetup("x")])]
        var seen = 0
        for areas in [Set<String>(), ["tokyo"]] {
            for photos in [false, true] {
                for everything in [false, true] {
                    for extras in [Set<OfflineExtra>(), [.fuji], Set(OfflineExtra.allCases)] {
                        let job = OfflineJob(areas: areas, photos: photos, extras: extras, everything: everything)
                        for p in phases {
                            for s in photoStates {
                                for e in extraStates {
                                    for list in readies {
                                        let states = e.map { e in Dictionary(uniqueKeysWithValues: OfflineExtra.allCases.map { ($0, e) }) } ?? [:]
                                        let r = job.result(phases: p, photos: s, mapBuild: build, extras: states, ready: list)
                                        #expect(!r.subtitle.isEmpty)
                                        #expect(r.success == (r.subtitle == "Xong"))
                                        #expect(!r.subtitle.hasPrefix(" · ") && !r.subtitle.hasSuffix(" · ") && !r.subtitle.contains(" ·  · "))
                                        if r.paused { #expect(r.subtitle == "Đã dừng") }
                                        seen += 1
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        #expect(seen == 2 * 2 * 2 * 3 * 5 * 3 * 5 * 4)
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
                    // a make still under way changes nothing: the area has its pack (the map moved back to its build)
                    for making in [false, true] {
                        #expect(OfflineArea.settle(current: p, older: nil, previous: previous, requested: requested, making: making)
                                == OfflineArea.Settled(phase: p, make: false, dropOld: false))
                    }
                }
            }
        }
    }

    @Test func aFailedAreaIsNeverForgotten() {
        // a pack that could not be made leaves the area with no pack: a refresh used to forget it, reason and all
        for requested in [false, true] {
            for older: AreaPhase? in [nil, .stale(other), .stale(nil)] {
                let s = OfflineArea.settle(current: nil, older: older, previous: .failed("Không tạo được vùng tải"), requested: requested, making: false)
                #expect(s.phase == .failed("Không tạo được vùng tải"))
                // made again by a tap or at the next launch, never by a refresh: one runs on every change of the packs
                #expect(!s.make)
                #expect(!s.dropOld)
            }
        }
    }

    @Test func anAreaBeingMadeIsLeftAlone() {
        // paused while it is made (not asked for any more): `.paused` at once, still made, then left inactive
        for previous: AreaPhase in [.creating, .paused] {
            for requested in [false, true] {
                for older: AreaPhase? in [nil, .stale(other)] {
                    #expect(OfflineArea.settle(current: nil, older: older, previous: previous, requested: requested, making: true)
                            == OfflineArea.Settled(phase: previous, make: false, dropOld: false))
                }
            }
        }
    }

    @Test func anAreaLeftPreparingWithNoMakeUnderWayIsMadeAgain() {
        // its make is over and the area has no pack for the map's build: the map moved while the pack was added, so
        // the new pack holds the old build. "Đang chuẩn bị…" for ever (the job never ending) became: made again.
        for older: AreaPhase? in [nil, .stale(other)] {
            #expect(OfflineArea.settle(current: nil, older: older, previous: .creating, requested: true, making: false)
                    == OfflineArea.Settled(phase: .requested, make: true, dropOld: false))
            // asked for no more: what it has
            #expect(OfflineArea.settle(current: nil, older: older, previous: .creating, requested: false, making: false)
                    == OfflineArea.Settled(phase: older, make: false, dropOld: false))
        }
    }

    @Test func anAreaAskedForWithNoPackForTheMapIsMadeAgain() {
        // after a relaunch (a failure of the last one included), after the map moved to another build, or asked for
        // before MapLibre had read its packs
        let previous: [AreaPhase?] = [nil, .requested, .downloading(completed: 5, expected: 10), .complete(other), .complete(build),
                                      .paused, .waitingForNetwork, .stale(nil)]
        for p in previous {
            for older: AreaPhase? in [nil, .stale(other), .stale(nil)] {
                #expect(OfflineArea.settle(current: nil, older: older, previous: p, requested: true, making: false)
                        == OfflineArea.Settled(phase: .requested, make: true, dropOld: false))
            }
        }
    }

    @Test func aPackOfAnotherBuildIsStaleUntilTheAreaIsAskedFor() {
        for previous: AreaPhase? in [nil, .complete(build), .downloading(completed: 1, expected: 2), .paused, .requested] {
            #expect(OfflineArea.settle(current: nil, older: .stale(other), previous: previous, requested: false, making: false)
                    == OfflineArea.Settled(phase: .stale(other), make: false, dropOld: false))
            #expect(OfflineArea.settle(current: nil, older: .stale(nil), previous: previous, requested: false, making: false)
                    == OfflineArea.Settled(phase: .stale(nil), make: false, dropOld: false))
        }
    }

    @Test func anAreaWithNothingIsNothing() {
        for previous: AreaPhase? in [nil, .requested, .paused, .complete(build), .downloading(completed: 1, expected: 2), .stale(other)] {
            #expect(OfflineArea.settle(current: nil, older: nil, previous: previous, requested: false, making: false)
                    == OfflineArea.Settled(phase: nil, make: false, dropOld: false))
        }
    }

    @Test func anOlderPackGoesOnlyOnceTheNewOneIsComplete() {
        // while the new one downloads the old one is kept (MapLibre stores a resource once for every pack using it)
        for p: AreaPhase in [.requested, .downloading(completed: 9, expected: 10), .waitingForNetwork, .paused] {
            for requested in [false, true] {
                #expect(!OfflineArea.settle(current: p, older: .stale(other), previous: nil, requested: requested, making: false).dropOld)
            }
        }
        #expect(OfflineArea.settle(current: .complete(build), older: .stale(other), previous: .downloading(completed: 9, expected: 10), requested: false, making: false)
                == OfflineArea.Settled(phase: .complete(build), make: false, dropOld: true))
        #expect(OfflineArea.settle(current: .complete(build), older: .stale(nil), previous: nil, requested: true, making: false).dropOld)
        #expect(!OfflineArea.settle(current: .complete(build), older: nil, previous: nil, requested: false, making: false).dropOld)
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

    // MARK: What a make does once it has read the style

    func pinnedStyle(_ b: TileBuild) -> Data { Data(#"{"version":8,"sources":{"omt":{"type":"vector","tiles":["\#(b.template)"]}}}"#.utf8) }
    var currentStyle: Data { Data(#"{"version":8,"sources":{"omt":{"type":"vector","url":"https://tiles.openfreemap.org/planet"}}}"#.utf8) }
    func tileJSON(_ b: TileBuild) -> Data { Data(#"{"tilejson":"3.0.0","tiles":["\#(b.template)"]}"#.utf8) }

    @Test func aStyleOfTheMapsBuildMakesThePack() {
        for again in [false, true] {
            // the map moved during the read, to the build the style holds: made, of that build
            for askedOn in [build, other] {
                #expect(OfflineArea.step(.files(style: pinnedStyle(build), tileJSON: nil), mapBuild: build, askedOn: askedOn, again: again)
                        == .add(build))
                #expect(OfflineArea.step(.files(style: currentStyle, tileJSON: tileJSON(build)), mapBuild: build, askedOn: askedOn, again: again)
                        == .add(build))
            }
        }
    }

    @Test func aMoveOfTheMapDuringTheReadReadsTheStyleOnceMore() {
        // the map moved to another build while the style was read (the pinned one gone, or OpenFreeMap's moved on):
        // nothing is at fault, so the style is stored again for the build the map reads now
        let served: [ServedStyle] = [.files(style: pinnedStyle(other), tileJSON: nil), .files(style: currentStyle, tileJSON: tileJSON(other)),
                                     .files(style: currentStyle, tileJSON: nil), .refused(OfflineArea.otherBuild),
                                     .refused("Không nạp được style của bản đồ")]
        for s in served {
            #expect(OfflineArea.step(s, mapBuild: build, askedOn: other, again: false) == .again)
            // moved again during the second read: it fails, saying so, and "Thử lại" reads it once more
            #expect(OfflineArea.step(s, mapBuild: build, askedOn: other, again: true) == .fail(OfflineArea.moved))
        }
    }

    @Test func aStyleOfAnotherBuildOrNoneFailsWithTheReasonGiven() {
        for again in [false, true] {
            #expect(OfflineArea.step(.files(style: pinnedStyle(other), tileJSON: nil), mapBuild: build, askedOn: build, again: again)
                    == .fail(OfflineArea.otherBuild))
            #expect(OfflineArea.step(.files(style: Data("<html>".utf8), tileJSON: nil), mapBuild: build, askedOn: build, again: again)
                    == .fail(OfflineArea.otherBuild))
            #expect(OfflineArea.step(.refused("Không nạp được style của bản đồ"), mapBuild: build, askedOn: build, again: again)
                    == .fail("Không nạp được style của bản đồ"))
        }
    }

    @Test func aTileJSONAheadOfTheMapSaysTheSourceMovedNotUpdateTheApp() {
        // OpenFreeMap moved on, and the app has not looked yet at this launch (`checkPinnedTiles`): updating the app
        // would not help, so the area does not say so
        #expect(OfflineArea.step(.files(style: currentStyle, tileJSON: tileJSON(other)), mapBuild: build, askedOn: build, again: false)
                == .fail(OfflineArea.moved))
        #expect(!OfflineArea.moved.contains("cập nhật app"))
        #expect(OfflineArea.moved != OfflineArea.otherBuild)
        #expect(!OfflineArea.moved.isEmpty)
    }

    @Test func otherBuildTellsTheUserToReopenTheApp() {
        #expect(OfflineArea.otherBuild == "Style của bản đồ không khớp bản đang dùng — mở lại app rồi thử lại")
        // reopening reads the build again; updating the app would not help
        #expect(OfflineArea.otherBuild.contains("mở lại app"))
        #expect(!OfflineArea.otherBuild.contains("cập nhật app"))
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

    // MARK: The overview pack

    @Test func overviewBoundsEveryBoxWithPad() throws {
        let boxes = [(sw: Coordinate(35.0, 139.0), ne: Coordinate(35.5, 139.5)), (sw: Coordinate(34.5, 135.5), ne: Coordinate(35.1, 136.0))]
        let o = try #require(OfflineArea.overview(of: boxes, pad: 0.1))
        #expect(abs(o.sw.lat - 34.4) < 1e-9); #expect(abs(o.sw.lng - 135.4) < 1e-9)
        #expect(abs(o.ne.lat - 35.6) < 1e-9); #expect(abs(o.ne.lng - 139.6) < 1e-9)
        // the order of the boxes does not matter, and the pad is 0.1 unless said
        let reversed = try #require(OfflineArea.overview(of: boxes.reversed()))
        #expect(reversed.sw == o.sw); #expect(reversed.ne == o.ne)
        // one box: that box, padded on every side
        let one = try #require(OfflineArea.overview(of: [(sw: Coordinate(34.5, 135.5), ne: Coordinate(35.1, 136.0))], pad: 0.25))
        #expect(abs(one.sw.lat - 34.25) < 1e-9); #expect(abs(one.sw.lng - 135.25) < 1e-9)
        #expect(abs(one.ne.lat - 35.35) < 1e-9); #expect(abs(one.ne.lng - 136.25) < 1e-9)
        // a box inside another adds nothing; the north and the east may come from different boxes
        let mixed = try #require(OfflineArea.overview(of: [(sw: Coordinate(34.0, 135.0), ne: Coordinate(36.0, 136.0)),
                                                          (sw: Coordinate(34.5, 135.2), ne: Coordinate(35.0, 135.8)),
                                                          (sw: Coordinate(34.2, 137.0), ne: Coordinate(34.8, 140.0))], pad: 0))
        #expect(mixed.sw == Coordinate(34.0, 135.0)); #expect(mixed.ne == Coordinate(36.0, 140.0))
    }

    @Test func overviewOfNothingIsNil() {
        #expect(OfflineArea.overview(of: []) == nil)
        #expect(OfflineArea.overviewID == "overview")
        // an id an older pack's plain context could carry too
        #expect(PackTag.area(of: Data(OfflineArea.overviewID.utf8)) == OfflineArea.overviewID)
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

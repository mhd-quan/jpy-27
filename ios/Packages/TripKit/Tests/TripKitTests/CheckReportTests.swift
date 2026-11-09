import Foundation
import Testing
import TripKit

/// Settings › Hỗ trợ › Kiểm tra (spec 2.3): each check's level, the order they are shown and kept in, and the one line
/// the main page says of a run.
@Suite struct CheckReportTests {
    private func result(_ id: CheckID, _ level: CheckLevel) -> CheckResult {
        CheckResult(id: id, level: level, line: "x")
    }

    // MARK: summary, storage, clock

    @Test func allOkSaysOk() {
        let all = CheckID.allCases.map { result($0, .ok) }
        #expect(CheckReport.summary(all) == "Ổn")
    }

    @Test func countsWarningsAndErrors() {
        let mixed = [result(.permissions, .warning), result(.offline, .error), result(.storage, .warning), result(.clock, .ok)]
        #expect(CheckReport.summary(mixed) == "1 lỗi · 2 cảnh báo")
        let warnings = [result(.permissions, .warning), result(.sync, .warning), result(.clock, .ok)]
        #expect(CheckReport.summary(warnings) == "2 cảnh báo")
        #expect(CheckReport.summary([result(.network, .error)]) == "1 lỗi")
    }

    @Test func levelsAreOrderedOkWarningError() {
        #expect(CheckLevel.ok < .warning)
        #expect(CheckLevel.warning < .error)
        #expect([CheckLevel.error, .ok, .warning].max() == .error)
    }

    @Test func storageWarnsUnderOneGB() {
        #expect(CheckReport.storage(freeBytes: 999_999_999) == .warning)
        #expect(CheckReport.storage(freeBytes: 1_000_000_000) == .ok)
        #expect(CheckReport.storage(freeBytes: 0) == .warning)
    }

    @Test func clockWarnsWhileRehearsing() {
        #expect(CheckReport.clock(rehearsing: true) == CheckResult(id: .clock, level: .warning, line: "Đang chạy thử: giờ của app khác giờ thật"))
        #expect(CheckReport.clock(rehearsing: false) == CheckResult(id: .clock, level: .ok, line: "Giờ thật"))
    }

    @Test func resultsRoundTripAsJSON() throws {
        let results = [
            CheckResult(id: .storage, level: .warning, line: "Trống 800 MB"),
            CheckResult(id: .network, level: .error, line: "Máy chủ bản đồ không trả lời"),
            CheckResult(id: .clock, level: .ok, line: "Giờ thật"),
        ]
        let data = try JSONEncoder().encode(results)
        #expect(try JSONDecoder().decode([CheckResult].self, from: data) == results)
    }

    // MARK: order

    @Test func orderedByCheckID() {
        let shuffled = [result(.clock, .ok), result(.network, .error), result(.permissions, .ok), result(.storage, .warning)]
        #expect(CheckReport.ordered(shuffled).map(\.id) == [.permissions, .storage, .network, .clock])
    }

    @Test func checkIDsInTheSpecsOrder() {
        #expect(CheckID.allCases == [.permissions, .offline, .storage, .records, .reminders, .sync, .network, .clock])
    }

    // MARK: network

    @Test func noNetworkWarnsWithoutAsking() {
        let r = CheckReport.network(online: false, tiles: nil, forecast: nil)
        #expect(r == CheckResult(id: .network, level: .warning, line: "Không có mạng"))
        // whatever was answered before, no network is what it says
        #expect(CheckReport.network(online: false, tiles: .status(200), forecast: .status(200)).line == "Không có mạng")
    }

    @Test func bothAnsweringIsOk() {
        #expect(CheckReport.network(online: true, tiles: .status(200), forecast: .status(200))
            == CheckResult(id: .network, level: .ok, line: "Bản đồ và dự báo trả lời"))
        // the forecast server answers its bare URL with a client error some days: it answered
        #expect(CheckReport.network(online: true, tiles: .status(204), forecast: .status(400)).level == .ok)
        #expect(CheckReport.network(online: true, tiles: .status(304), forecast: .status(405)).level == .ok)
    }

    @Test func aServerNotAnsweringIsAnError() {
        let tiles = CheckReport.network(online: true, tiles: CheckReport.Answer.none, forecast: .status(200))
        #expect(tiles == CheckResult(id: .network, level: .error, line: "Máy chủ bản đồ không trả lời"))
        let forecast = CheckReport.network(online: true, tiles: .status(200), forecast: CheckReport.Answer.none)
        #expect(forecast == CheckResult(id: .network, level: .error, line: "Máy chủ dự báo không trả lời"))
        let both = CheckReport.network(online: true, tiles: CheckReport.Answer.none, forecast: CheckReport.Answer.none)
        #expect(both == CheckResult(id: .network, level: .error, line: "Máy chủ bản đồ không trả lời · Máy chủ dự báo không trả lời"))
    }

    @Test func aGoneBuildWarns() {
        #expect(CheckReport.network(online: true, tiles: .status(404), forecast: .status(200))
            == CheckResult(id: .network, level: .warning, line: "Build bản đồ không còn trên máy chủ (404)"))
        #expect(CheckReport.network(online: true, tiles: .status(410), forecast: .status(200)).line == "Build bản đồ không còn trên máy chủ (410)")
    }

    @Test func serverErrorsWarn() {
        #expect(CheckReport.network(online: true, tiles: .status(503), forecast: .status(200))
            == CheckResult(id: .network, level: .warning, line: "Máy chủ bản đồ lỗi (503)"))
        #expect(CheckReport.network(online: true, tiles: .status(403), forecast: .status(200)).line == "Máy chủ bản đồ lỗi (403)")
        #expect(CheckReport.network(online: true, tiles: .status(200), forecast: .status(502))
            == CheckResult(id: .network, level: .warning, line: "Máy chủ dự báo lỗi (502)"))
    }

    @Test func aRedirectElsewhereWarnsOnce() {
        let one = CheckReport.network(online: true, tiles: .elsewhere, forecast: .status(200))
        #expect(one == CheckResult(id: .network, level: .warning, line: "Wi‑Fi chuyển sang trang khác (cần đăng nhập?)"))
        // a login page catches both: said once
        #expect(CheckReport.network(online: true, tiles: .elsewhere, forecast: .elsewhere).line == "Wi‑Fi chuyển sang trang khác (cần đăng nhập?)")
    }

    @Test func anUnknownBuildWarns() {
        #expect(CheckReport.network(online: true, tiles: nil, forecast: .status(200))
            == CheckResult(id: .network, level: .warning, line: "Không biết build bản đồ đang đọc"))
    }

    @Test func theWorstPartGivesTheLevel() {
        let r = CheckReport.network(online: true, tiles: .status(404), forecast: CheckReport.Answer.none)
        #expect(r.level == .error)
        #expect(r.line == "Build bản đồ không còn trên máy chủ (404) · Máy chủ dự báo không trả lời")
    }

    // MARK: offline

    private var allReady: [ReadyItem: ReadyState] {
        Dictionary(uniqueKeysWithValues: ReadyItem.allCases.map { ($0, ReadyState.ready) })
    }

    @Test func offlineReadyIsOk() {
        #expect(CheckReport.offline(allReady, mapsStale: false, downloading: nil) == CheckResult(id: .offline, level: .ok, line: "Sẵn sàng"))
        var unsupported = allReady
        unsupported[.speech] = .unsupported("Máy này không có")
        #expect(CheckReport.offline(unsupported, mapsStale: false, downloading: nil).level == .ok)
    }

    @Test func offlineMissingWarns() {
        var s = allReady
        s[.photos] = .missing(done: 3, total: 10)
        s[.fuji] = .needsSetup("Mở trang Fuji một lần")
        #expect(CheckReport.offline(s, mapsStale: false, downloading: nil) == CheckResult(id: .offline, level: .warning, line: "Thiếu 2 mục"))
        #expect(CheckReport.offline(allReady, mapsStale: true, downloading: nil) == CheckResult(id: .offline, level: .warning, line: "Cần tải lại"))
        #expect(CheckReport.offline(allReady, mapsStale: false, downloading: 0.42) == CheckResult(id: .offline, level: .warning, line: "Đang tải 42%"))
        // never read yet: not ready
        #expect(CheckReport.offline([:], mapsStale: false, downloading: nil).level == .warning)
    }

    @Test func offlineFailureIsAnError() {
        var s = allReady
        s[.maps] = .failed("Không kết nối được")
        #expect(CheckReport.offline(s, mapsStale: false, downloading: nil) == CheckResult(id: .offline, level: .error, line: "Thiếu 1 mục"))
        // a failure still wins while a download runs
        #expect(CheckReport.offline(s, mapsStale: false, downloading: 0.5).level == .error)
    }
}

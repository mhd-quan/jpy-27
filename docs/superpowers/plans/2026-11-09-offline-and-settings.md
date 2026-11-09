# JP27 iOS — Dùng khi mất sóng, Cài đặt theo trang, log xuất được

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gói bản đồ offline tải được mà không cần site; một nút kéo về mọi thứ app cần khi mất sóng, có danh sách
sẵn sàng; Cài đặt chia trang, có Kiểm tra và Nhà phát triển trong cả Release; log lưu 14 ngày, xuất `.zip`.

**Architecture:** Mọi quy tắc có thể sai (khoá và bytes của style nạp, khung Toàn tuyến, trạng thái sẵn sàng và câu
tổng hợp, thứ tự tải, việc tải mở rộng, dòng log, làm tròn toạ độ, giữ/xoá log, hàng đợi log, kết quả kiểm tra, lý do
giữ màn hình sáng) nằm trong TripKit và có test trên Linux. Phần app mỏng: đọc hệ thống (MapLibre, MapKit,
AssetInventory, Translation, MetricKit, UIKit), gọi TripKit, vẽ.

**Tech Stack:** Swift 6.2 / SwiftUI (iOS 26), MapLibre Native 7.0.0, MapKit, Translation, Speech (`SpeechTranscriber`,
`AssetInventory`), MetricKit, Synchronization (`Mutex`), Network (`NWPathMonitor`); TripKit (Swift Package, test bằng
`swift test` trên Linux).

**Spec:** `docs/superpowers/specs/2026-11-08-offline-and-settings-design.md`

## Global Constraints

- Hợp đồng `docs/superpowers/plans/2026-11-04-execution-contract-phase4-5.md` áp dụng nguyên văn (ghế, effort, báo
  cáo, CI), trừ: ruling của lượt này đánh số từ **R-600**; tài liệu kiểm trên máy là
  `docs/superpowers/checklists/2026-11-device-offline-settings.md`.
- iOS `26.0`, `SWIFT_VERSION 6.0`, app mặc định `MainActor`; Xcode 26.2 trong CI. Không dùng gì chỉ Swift 6.3 nhận.
- Không `Task.detached`, `DispatchQueue.global`, `@unchecked Sendable`, `nonisolated(unsafe)`, `MainActor.assumeIsolated`
  khi không có lý do ghi ngay trên dòng.
- TripKit không import framework chỉ có trên Apple (không UIKit, MapLibre, MapKit, Speech, Translation, MetricKit);
  mọi test chạy bằng `swift test` trên Linux. `Mutex` (Synchronization) chỉ dùng trong app.
- Không lỗi lưu im lặng (`node scripts/lint-saves.mjs` sạch). Chuyển động qua token, tôn trọng Reduce Motion
  (`node scripts/lint-motion.mjs` 0 lỗi). Low Power Mode dừng việc nền không do người dùng bấm.
- Chữ tiếng Việt, cùng giọng hiện có; mỗi trang con nhiều nhất một câu chú thích ngắn (khoảng một dòng).
- Không đụng `src/data` (R-86). Giữ quy tắc chạy thử. Không tên model trong repo; push qua `bin/push-gate`.
- MapLibre giữ `exactVersion: 7.0.0`. Không thêm dependency.
- Code app chỉ biên dịch trong CI "App builds": dòng "0 warnings in the build, 0 in ios/JP27, ios/JP27Widgets,
  ios/Shared" phải là 0/0. API hệ thống mới phải kiểm bằng `bin/apple-decl` hoặc `bin/maplibre-header`; chỗ không
  kiểm được ghi `UNVERIFIED-COMPILE` trong report.
- Mọi bước "trên máy" chép vào tài liệu kiểm trên máy với ô trống, không bao giờ báo là đã làm.
- Log: không chữ người dùng tự gõ, không tên máy của người kia, toạ độ làm tròn 0,01°; giữ 14 ngày, tối đa 10 MB.

## Review Focus

1. **App bị tắt giữa lúc gói đang tải, mở lại khi không có mạng:** gói tiếp tục phải tìm thấy style đã nạp, không hỏi
   mạng → Task 1: `configure` nạp style xong mới bắt đầu theo dõi gói; dòng thiết bị 1.3.
2. **Việc tải lưu bởi bản trước (không có `extras`)** được mở bằng bản này → Task 6:
   `decodesJobSavedBeforeExtras`.
3. **Không ghi được log (đĩa đầy, file bị khoá khi máy khoá màn hình):** app không treo, hàng đợi không phình mãi →
   Task 2: `queueDropsOldestPastCap`; lỗi hiện ở trang Log (Task 7).
4. **Đang Chạy thử (đồng hồ chuyến lệch):** giờ của log là giờ thật của máy, kiểm tra báo đang chạy thử → Task 2
   `lineTimeIsTheGivenInstant` (app truyền `Date()`, không đồng hồ chuyến); Task 7 `clockWarnsWhileRehearsing`.
5. **Tắt "Giữ màn hình sáng khi đi tàu" lúc thẻ đưa nhân viên xem đang mở:** màn hình vẫn sáng → Task 4
   `removingOneReasonKeepsTheOther`.

---

## Bản đồ thay đổi

| File | Trách nhiệm | Task |
| --- | --- | --- |
| `TripKit/Offline/PackStyle.swift` (mới) | khoá URL, bytes, build của style nạp cho gói | 1 |
| `TripKit/Offline/OfflineArea.swift` | `overview(of:)`; câu `otherBuild` mới; `OfflineJob.extras` | 1, 6 |
| `TripKit/Offline/Readiness.swift` (mới) | mục sẵn sàng, trạng thái, câu tổng hợp, thứ tự tải, độ mới dự báo | 5 |
| `TripKit/Log/LogLine.swift`, `LogRetention.swift`, `LogQueue.swift` (mới) | dòng log, làm tròn, giữ/xoá, hàng đợi | 2 |
| `TripKit/Support/CheckReport.swift`, `AwakeReasons.swift` (mới) | kết quả kiểm tra; lý do giữ màn hình sáng | 7, 4 |
| `JP27/Services/OfflineMaps.swift` | nạp style, Toàn tuyến, bỏ đường hỏi site | 1 |
| `JP27/Services/AppLog.swift` (mới) | ghi log, đọc, xoá, xuất `.zip` | 2 |
| `JP27/Services/Perf.swift` | `MetricsInbox` nhận `MXDiagnosticPayload` | 2 |
| `JP27/Services/OfflineReadiness.swift` (mới) | đọc trạng thái 7 mục; gói ngôn ngữ | 5 |
| `JP27/Services/OfflineExtras.swift` (mới) | vẽ sẵn ảnh bản đồ ngày, ảnh Fuji; làm mới dự báo | 6 |
| `JP27/Features/Settings/*.swift` | tách trang, ô biểu tượng, bố cục, trang mới | 4, 5, 7 |
| nhiều file Services/Data/App | ghi sự kiện vào log | 3 |

---

### Task 1: Style của gói nằm trong app; gói Toàn tuyến (spec 1.1, 1.2)

Bậc **T1**. Sửa lỗi người dùng thấy: mọi vùng báo "Không kết nối được máy chủ bản đồ".

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Offline/PackStyle.swift`
- Modify: `ios/Packages/TripKit/Sources/TripKit/Offline/OfflineArea.swift` (`overview`, câu `otherBuild`)
- Modify: `ios/JP27/Services/OfflineMaps.swift` (`Area`, `configure`, `make`, `served`, `packStyle`, `fakeOtherStyle`, `tilesMoved`)
- Modify: `ios/JP27/Features/Settings/SettingsView.swift` (bỏ công tắc "Giả style khác bản")
- Modify: `ios/README.md` (đoạn "gói bản đồ offline (style lấy từ …, cần deploy site trước …)")
- Create: `docs/superpowers/checklists/2026-11-device-offline-settings.md`
- Test: `ios/Packages/TripKit/Tests/TripKitTests/PackStyleTests.swift`, `OfflineAreaTests.swift`

**Interfaces:**
- Produces:
  - `public enum PackStyle { static let base = "https://jpy27.delphyra.tech/map/"; static func prepare(bundled: Data, pinnedName: String?, currentTemplate: String?) -> Prepared?; static func key(of template: String) -> String }`
  - `public struct PackStyle.Prepared: Sendable, Equatable { let url: String; let style: Data; let build: TileBuild }`
  - `public static func OfflineArea.overview(of boxes: [(sw: Coordinate, ne: Coordinate)], pad: Double = 0.1) -> (sw: Coordinate, ne: Coordinate)?`
  - `public static let OfflineArea.overviewID = "overview"`
  - App: `OfflineMaps.Area` thêm `let zoom: ClosedRange<Double>` (vùng thường `9...16`, Toàn tuyến `5...10`).

- [ ] **Step 1: Test hỏng cho `PackStyle`** trong `PackStyleTests.swift` (fixture: style JSON có `sources.omt.tiles = ["T1"]` và `metadata["jp27:build"] = "B1"`):
  - `pinnedUsesBundledBytesAndName`: `prepare(bundled: f, pinnedName: "B1", currentTemplate: nil)` → `url == PackStyle.base + "jp27-light@B1.json"`, `style == f`, `build == TileBuild(template: "T1")`.
  - `currentRewritesTilesAndKeysByTemplate`: `currentTemplate: "T2"` → `build == TileBuild(template: "T2")`, `StyleInfo.build(style: p.style) == TileBuild(template: "T2")`, `StyleInfo.styleBuild(style: p.style) == nil`, `url == PackStyle.base + "jp27-light@current-" + PackStyle.key(of: "T2") + ".json"`.
  - `keyIsFNV1a64Hex`: `key(of: "") == "cbf29ce484222325"`, `key(of: "a") == "af63dc4c8601ec8c"`, `key(of: "A") != key(of: "B")`.
  - `nothingToPrepareIsNil`: `pinnedName: nil, currentTemplate: nil` → nil; bundled `Data("x".utf8)` với `currentTemplate: "T2"` → nil; bundled không có `omt.tiles` với `pinnedName: "B1"` → nil.
  - `preparedStyleMakesAPackOfItsBuild`: với cả hai trường hợp trên, `OfflineArea.step(.files(style: p.style, tileJSON: nil), mapBuild: p.build, askedOn: p.build, again: false) == .add(p.build)`.
- [ ] **Step 2: Test hỏng cho `overview`** trong `OfflineAreaTests.swift`:
  - `overviewBoundsEveryBoxWithPad`: hộp (35.0,139.0)-(35.5,139.5) và (34.5,135.5)-(35.1,136.0), `pad: 0.1` → sw `(34.4, 135.4)`, ne `(35.6, 139.6)` (so sai số 1e-9).
  - `overviewOfNothingIsNil`: `overview(of: [])` → nil.
- [ ] **Step 3: Chạy** `swift test --filter "PackStyleTests|OfflineAreaTests"` — hỏng vì thiếu ký hiệu.
- [ ] **Step 4: Viết `PackStyle`** theo Interfaces. `key` là FNV-1a 64 bit trên UTF-8 (offset `0xcbf29ce484222325`, prime `0x100000001b3`), 16 chữ hex thường, không dùng `Hasher` (đổi mỗi lần chạy). Ghim: bytes nguyên văn, build từ `StyleInfo.build(style:)`. Hiện tại: `StyleInfo.pointing(style:at:)`, build `TileBuild(template:)`. Viết `overview` và hằng `overviewID`. Đổi `OfflineArea.otherBuild` thành `"Style của bản đồ không khớp bản đang dùng — mở lại app rồi thử lại"` (site không còn trong đường tải).
- [ ] **Step 5: Chạy lại** — PASS; `swift test` toàn bộ xanh.
- [ ] **Step 6: Nối vào `OfflineMaps`.**
  - `Area` thêm `zoom`; `add(_:tag:style:number:)` dùng `area.zoom.lowerBound/upperBound` thay `9`/`16`, và `style` là `URL(string: prepared.url)`.
  - `configure`: thêm vùng `Area(id: OfflineArea.overviewID, name: "Toàn tuyến", sw:, ne:, zoom: 5...10)` từ `overview(of:)` của các vùng; Toàn tuyến đứng đầu, các vùng khác theo tên. Trước khi gắn `watch` (KVO `packs`), `await preloadStyle()` để gói tải dở không bao giờ tiếp tục khi style chưa nạp (Review Focus 1). `configure` được gọi từ nơi đồng bộ: bọc phần gắn `watch` trong một `Task` trên main actor, giữ `watch == nil` làm cờ chạy một lần (đặt một cờ `preparing` để lần gọi thứ hai không tạo Task thứ hai).
  - `private func preloadStyle() async -> PackStyle.Prepared?`: đọc style đóng trong app (`bundledStyle()`), `PackStyle.prepare(bundled:pinnedName:currentTemplate: Self.currentTemplate)`, rồi `MLNOfflineStorage.shared.preloadData(_:for:modificationDate:expirationDate:eTag:mustRevalidate:completionHandler:)` với `expirationDate` = 1/1/2030, `mustRevalidate: false`, bọc bằng `withCheckedContinuation`; handler (gọi trên main queue) trả lỗi thì kết quả nil. Kiểm tên Swift của selector bằng `bin/maplibre-header MLNOfflineStorage.h`; nếu header chỉ cho tên ObjC, ghi `UNVERIFIED-COMPILE`.
  - `make`: thay `packStyle`/`served` bằng `preloadStyle()`; có `Prepared` thì `served = .files(style: p.style, tileJSON: nil)`, không thì `.refused("Không nạp được style của bản đồ")`. `OfflineArea.step` giữ nguyên.
  - `tilesMoved`: `Task { _ = await preloadStyle(); refresh() }`.
  - Xoá `packStyle(current:)`, `served(_:current:)`, `fakeOtherStyle` và công tắc của nó trong Cài đặt. Giữ `checkPinnedTiles`, `currentTileJSON`, `remoteStyle` (dự phòng của `style(dark:)`).
- [ ] **Step 7: Tài liệu.** README: style của gói nằm trong app, không cần site; site chỉ còn cho web. Tạo checklist thiết bị với § 1:
  1. Có mạng, tải vùng "Nara" → "Đã tải", có dung lượng.
  2. Bật Chế độ máy bay, mở Bản đồ ở Nara, zoom 9–16 → đủ đường, chữ. Nếu vùng vẫn báo không kết nối được: MapLibre không đọc style đã nạp; đường lui là gắn lại tên miền cho Worker.
  3. Đang tải một vùng lớn, vuốt tắt app; bật Chế độ máy bay, mở app; tắt Chế độ máy bay → vùng tải tiếp, không báo lỗi style.
  4. Tải "Toàn tuyến"; Chế độ máy bay; thu nhỏ bản đồ toàn Kantō–Kansai → có nền ở zoom 5–10.
  5. Trang một ngày đi qua hai vùng, ảnh bản đồ chưa lưu, Chế độ máy bay → ảnh vẽ được (Toàn tuyến đã tải).
- [ ] **Step 8: Kiểm và commit.** `swift test`; `node --test 'scripts/*.test.mjs'`; `node scripts/lint-saves.mjs`; `node scripts/lint-motion.mjs`; push qua `bin/push-gate`; CI 0/0.

```bash
git commit -m "Offline packs read the style the app carries; an overview pack for the whole route"
```

---

### Task 2: Log — dòng, giữ/xoá, ghi ra file, báo cáo crash, xuất `.zip` (spec 3.1, 3.3 phần xuất)

Bậc **T1** (ghi file từ nhiều luồng, dữ liệu riêng tư).

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Log/LogLine.swift`, `LogRetention.swift`, `LogQueue.swift`
- Create: `ios/JP27/Services/AppLog.swift`
- Modify: `ios/JP27/Services/Perf.swift` (`MetricsInbox`)
- Modify: `ios/JP27/App/AppModel.swift` (`deactivate`: `await AppLog.flush()` dưới background task đang có), `ios/JP27/App/JP27App.swift` (dòng mở app)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/LogTests.swift`

**Interfaces:**
- Produces (TripKit):
  - `public enum LogLevel: String, Codable, Sendable, Comparable, CaseIterable { case info, warning, error }`
  - `public enum LogCategory: String, Codable, Sendable, CaseIterable { case app, offline, map, alarm, notify, ride, location, sync, records, forecast, talk, settings, check, dev, metrics }`
  - `public struct LogLine: Codable, Sendable, Equatable { let t: Date; let level: LogLevel; let cat: LogCategory; let msg: String; let fields: [String: String]?; func encoded() -> Data; static func decode(_ line: Data) -> LogLine? }`
  - `public enum LogRedact { static func round(_ c: Coordinate) -> Coordinate; static func text(_ c: Coordinate) -> String }`
  - `public struct LogFile: Sendable, Equatable { let name: String; let bytes: Int }`
  - `public enum LogRetention { static let maxAgeDays = 14; static let maxBytes = 10_000_000; static func dayName(_ date: Date, in timeZone: TimeZone) -> String; static func toDelete(_ files: [LogFile], today: String) -> [String] }`
  - `public struct LogQueue: Sendable { init(cap: Int = 2000); mutating func append(_ line: LogLine); mutating func drain() -> [LogLine]; var count: Int; var dropped: Int }`
- Produces (app): `nonisolated enum AppLog { static func info/warning/error(_ cat: LogCategory, _ msg: String, _ fields: [String: String] = [:]); static func flush() async; static func recent(limit: Int, minimum: LogLevel) async -> [LogLine]; static func usage() async -> Int; static func clear() async; static func export(info: [String: String]) async throws -> URL; static func lastWriteError() async -> String? }`

- [ ] **Step 1: Test hỏng** trong `LogTests.swift`:
  - `lineEncodesOneJSONObjectPerLine`: `msg: "a\nb"` → `encoded()` kết thúc bằng một `\n` duy nhất; `LogLine.decode(encoded) == line`.
  - `lineTimeIsTheGivenInstant`: `t = Date(timeIntervalSince1970: 1_800_000_000.5)` → chuỗi mã hoá chứa `"t":"2027-01-15T08:00:00.500Z"`; khoá sắp xếp (`"cat"` đứng trước `"level"`).
  - `fieldsOmittedWhenNil`: `fields: nil` → không có khoá `"fields"`.
  - `roundsCoordinatesToHundredths`: `(35.6895, 139.6917)` → `(35.69, 139.69)`; `text` → `"35.69,139.69"`; `(-0.005, 0.004)` → `(-0.01, 0.0)`.
  - `dayNameUsesTheGivenZone`: `1_800_000_000` (08:00 UTC) trong `Asia/Tokyo` → `"2027-01-15.jsonl"`; lúc 20:00 UTC trong Tokyo → ngày hôm sau.
  - `retentionDropsOlderThan14Days`: hôm nay `2026-11-09.jsonl` → xoá `2026-10-26.jsonl`, giữ `2026-10-27.jsonl`.
  - `retentionTrimsOldestUntilUnderCap`: `11-07`, `11-08`, `11-09` mỗi file 4_000_000 byte, hôm nay `11-09` → `["2026-11-07.jsonl"]`.
  - `retentionNeverDeletesToday`: chỉ hôm nay, 12_000_000 byte → `[]`.
  - `retentionIgnoresOtherNames`: `notes.txt`, thư mục `diagnostics` → không bao giờ trong kết quả.
  - `queueDropsOldestPastCap`: `cap: 3`, thêm 5 dòng → `drain()` trả 3 dòng mới nhất theo thứ tự, `dropped == 2`; `drain()` lần hai rỗng.
- [ ] **Step 2: Chạy** `swift test --filter LogTests` — hỏng.
- [ ] **Step 3: Viết TripKit.** `encoded()`: `JSONEncoder` với `.sortedKeys`, ngày bằng `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` (UTC). `toDelete`: chỉ tên khớp `yyyy-MM-dd.jsonl`; giữ hôm nay và 13 ngày trước; rồi xoá cũ nhất tới khi tổng ≤ `maxBytes`; không bao giờ hôm nay.
- [ ] **Step 4: Chạy lại** — PASS.
- [ ] **Step 5: Viết `AppLog`.** Hàng đợi là `Mutex<LogQueue>` (`import Synchronization`) để `info/warning/error` gọi được từ mọi luồng mà giữ thứ tự; mỗi dòng cũng gửi tới `Logger(subsystem: "tech.delphyra.jp27", category: cat.rawValue)` (`.public`, vì đã không chứa dữ liệu riêng). Một `actor LogWriter` rút hàng đợi vào `Application Support/Logs/<dayName>.jsonl` (múi giờ của máy): lần thêm đầu tiên sau khi hàng đợi rỗng hẹn một lần rút sau 2 giây; đủ 64 dòng thì rút ngay; mở file bằng `FileHandle(forWritingTo:)` + `seekToEnd`, tạo nếu chưa có, thư mục có `isExcludedFromBackup`. Sau mỗi lần rút đổi ngày, chạy `LogRetention.toDelete`. Lỗi ghi lưu vào `lastWriteError`, không throw ra ngoài. `t` luôn là `Date()` (giờ thật), không đồng hồ chuyến.
- [ ] **Step 6: Báo cáo crash và treo máy.** `MetricsInbox` thêm `func didReceive(_ payloads: [MXDiagnosticPayload])`: ghi `jsonRepresentation()` vào `Logs/diagnostics/<timeStampEnd ISO>.json` (giữ 20 file mới nhất), và `AppLog.error(.metrics, "Báo cáo crash, treo máy", ["crashes": "\(n)", "hangs": "\(m)"])`.
- [ ] **Step 7: Xuất.** `export(info:)` (`@concurrent`): `flush`, chép `Logs/` (gồm `diagnostics/`) và `Caches/metrics` vào thư mục tạm `JP27-log-<yyyyMMdd-HHmm>/`, ghi `info.json` (`JSONSerialization`, `.sortedKeys`), nén bằng `NSFileCoordinator().coordinate(readingItemAt:options: .forUploading, error:)`, rồi chuyển file zip tới `FileManager.default.temporaryDirectory/JP27-log-<…>.zip` trước khi khối kết thúc. Kiểm `NSFileCoordinator.ReadingOptions.forUploading` bằng `bin/apple-decl`.
- [ ] **Step 8: Mở và đóng app.** `JP27AppDelegate.didFinishLaunching`: `AppLog.info(.app, "Mở app", ["version":, "build":, "ios":])`; `AppModel.activate`: `info(.app, "Vào app")`; `deactivate`: `info(.app, "Rời app")` rồi `await AppLog.flush()` trong background task sẵn có hoặc một `beginBackgroundTask` riêng.
- [ ] **Step 9: Checklist thiết bị § 2:**
  1. Dùng app 5 phút, rời app, mở lại; Cài đặt › Hỗ trợ › Log có dòng "Mở app", "Rời app", "Vào app" theo đúng thứ tự giờ.
  2. Xuất log → file `.zip` mở được bằng Tệp, có `*.jsonl` và `info.json`.
  3. Sau một lần app bị crash (nếu có), lần mở hôm sau có dòng "Báo cáo crash, treo máy".
- [ ] **Step 10: Kiểm và commit** như Task 1.

```bash
git commit -m "A log kept on the phone for 14 days, with crash reports, exported as a zip"
```

---

### Task 3: Ghi sự kiện vào log (spec 3.2)

Bậc **T2**. Chỉ thêm lời gọi `AppLog`; không đổi hành vi.

**Files (Modify):** `Data/Records.swift`, `App/AppModel.swift` (`report`, `Records.problem` lúc mở), `Services/OfflineMaps.swift` (+ `Downloads`), `Services/Media.swift` (`OfflinePhotos`, audio), `Services/AlarmService.swift`, `Services/NotificationService.swift`, `Services/LocationService.swift`, `Services/RideLiveService.swift`, `Services/LedgerSync.swift`, `Services/ForecastService.swift`, `Features/Talk/TalkShared.swift`, `Features/Talk/TalkListener.swift`.

**Interfaces:** Consumes `AppLog` (Task 2), `LogRedact` (Task 2).

- [ ] **Step 1: Thay `Logger` riêng** ở `Records.swift:360`, `LedgerSync.swift:864`, `Media.swift:1246` bằng `AppLog` cùng nhóm (`records`, `sync`, `talk`). Chuỗi `privacy: .private` cũ: bỏ phần riêng, giữ phần mô tả.
- [ ] **Step 2: Thêm các dòng.**

  | Nhóm | Nơi | Dòng (mức) | Trường |
  | --- | --- | --- | --- |
  | records | `AppModel.report` | "Không lưu được" (error) | `what`, `error` |
  | records | lúc mở sổ, `Records.problem != nil` | "Sổ mở lỗi" (error) | `problem` |
  | offline | `preloadStyle` | "Nạp style" (info / error) | `build`, `url` |
  | offline | `make` thất bại, `add` thất bại | "Không tạo được vùng" (error) | `area`, `reason` |
  | offline | `packError` | "Lỗi gói, đang thử lại" (warning) | `area`, `code` |
  | offline | vùng vừa `.complete` | "Vùng xong" (info) | `area`, `bytes` |
  | offline | `Downloads.start`, `finish` | "Bắt đầu tải", "Kết thúc tải" (info / warning khi không thành công) | `areas`, `photos`, `subtitle` |
  | offline | `OfflinePhotos` hết lượt | "Ảnh tải xong" (info / warning) | `saved`, `failed` |
  | map | `checkPinnedTiles` | "Kiểm build tile" (info) | `status`, `moved` |
  | alarm | đặt, đổi, huỷ, lỗi | "Đặt báo thức"… (info / error) | `ride`, `at` (giờ), `error` |
  | notify | lần đặt lại xong | "Đặt nhắc" (info) | `count` |
  | location | vào/ra geofence | "Vào vùng", "Ra vùng" (info) | `place` (id), `at` (`LogRedact.text`) |
  | ride | `select`, `begin`, kết thúc | "Chọn chuyến"… (info) | `ride` (id) |
  | sync | kết nối, gửi, nhận, lỗi | (info / error) | `peer` (8 ký tự đầu của dấu vân tay hex), không tên máy |
  | forecast | tải xong, lỗi | (info / warning) | `key`, `source` |
  | talk | trạng thái gói dịch, cài gói nghe | (info / error) | `status` |

  Không đưa vào trường: ghi chú, tên khoản chi, chữ nhật ký, tên máy, toạ độ chưa làm tròn.
- [ ] **Step 3: Grep kiểm.** `grep -rn "AppLog\." ios/JP27 | grep -E "note|title|name|deviceName|coordinate\b"` — từng dòng khớp phải là id hay giá trị đã làm tròn; ghi kết quả vào report.
- [ ] **Step 4: Checklist thiết bị § 3:** tải một vùng, đặt một báo thức thử (Nhà phát triển), đồng bộ với máy kia → log có dòng của từng việc; mở `.jsonl` đã xuất, tìm tên máy kia và một ghi chú đã gõ → không thấy.
- [ ] **Step 5: Kiểm và commit.**

```bash
git commit -m "Log what the app does: saves, downloads, alarms, rides, fences, sync, forecasts, language packs"
```

---

### Task 4: Cài đặt theo trang, ô biểu tượng, Trải nghiệm, Riêng tư (spec 2.1, 2.2, 2.5)

Bậc **T2**.

**Files:**
- Create: `ios/JP27/Features/Settings/SettingsKit.swift` (`SettingsIcon`, `SettingsLabel`, `SettingsPage`, `ProgressRing`)
- Create: `TripPages.swift` (Ngày thay thế, Đi bộ, Chạy thử), `ExperiencePages.swift` (Giao diện, Bản đồ), `PrivacyPages.swift` (Quyền, Nhật ký vị trí), `OfflinePage.swift` (phần offline hiện có), `SupportPages.swift` (Số đo, Nguồn), `DeveloperPage.swift` (nội dung Chẩn đoán hiện có, còn `#if DEBUG` như cũ tới Task 7)
- Modify: `SettingsView.swift` (chỉ còn trang chính)
- Create: `ios/Packages/TripKit/Sources/TripKit/Support/AwakeReasons.swift`; Create app `ios/JP27/Services/KeepAwake.swift`
- Modify: `Features/Talk/TalkShared.swift:98-99`, `Services/Media.swift` (`Speaker.say`), `Design/TripMap.swift` + `Features/Map/MapTab.swift` (khoá kính, bóng), `App/AppModel.swift` (giữ sáng khi đi tàu)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/AwakeReasonsTests.swift`

**Interfaces:**
- Produces:
  - `public struct AwakeReasons: Sendable, Equatable { enum Reason: String, Sendable { case showCard, ride }; mutating func set(_ r: Reason, _ on: Bool); var keepsAwake: Bool }`
  - App: `enum KeepAwake { static func set(_ r: AwakeReasons.Reason, _ on: Bool) }` → `UIApplication.shared.isIdleTimerDisabled = reasons.keepsAwake`.
  - App: `enum SpeechPace: String { case normal, slow; static let key = "talk.pace" }`; `Speaker.say(_ ja: String, slow: Bool? = nil)` — nil đọc theo `SpeechPace`.
  - Khoá mới: `MapPacer.glassKey = "map.glass"` (mặc định true), `MapPacer.reliefKey = "map.relief"` (mặc định false), `KeepAwake.rideKey = "ride.keepAwake"` (mặc định false).
  - `SettingsIcon(symbol:tint:)` giữ chữ ký; `SettingsLabel(title:symbol:tint:value:)` giữ chữ ký; trở thành `internal` (không còn `private`) để các file trang dùng chung.

- [ ] **Step 1: Test hỏng** `AwakeReasonsTests`: `emptyKeepsNothingAwake`; `anyReasonKeepsAwake`; `removingOneReasonKeepsTheOther` (bật `showCard`, bật `ride`, tắt `ride` → `keepsAwake == true`); `settingTwiceIsOnce` (bật `ride` hai lần, tắt một lần → false).
- [ ] **Step 2: Chạy** `swift test --filter AwakeReasonsTests` — hỏng. **Step 3:** viết `AwakeReasons` (một `Set<Reason>`). **Step 4:** PASS.
- [ ] **Step 5: Ô biểu tượng.** `SettingsIcon`: `Image(systemName:).resizable().scaledToFit().fontWeight(.semibold).foregroundStyle(.white).frame(width: 18, height: 18)` trong khung 30×30, nền `tint.gradient`, `RoundedRectangle(cornerRadius: 8, style: .continuous)`, `.clipShape` theo cùng hình. Mọi biểu tượng trong Cài đặt (cả `PermissionRow`) dùng nó.
- [ ] **Step 6: Tách file** theo danh sách Files, không đổi hành vi của từng phần khi chuyển. `OfflineMaps.fakeOtherStyle` đã bỏ ở Task 1.
- [ ] **Step 7: Trang chính** theo spec 2.2, các nhóm và giá trị:
  - **Cần xem** (chỉ khi có): sổ lỗi (`Records.problem`, kèm nút gửi file như nay); quyền tắt ("\(n) quyền đang tắt" → trang Quyền); bản đồ cũ ("Bản đồ offline cần tải lại" → trang offline); lỗi báo thức gần nhất (`model.alarms.lastError`). Task 5 thêm "chưa sẵn sàng", Task 7 thêm "đang giả lỗi".
  - **Chuyến đi:** như nay.
  - **Trải nghiệm:** Giao diện › (giá trị `Appearance.label`); Bản đồ › (giá trị "Kính" / "Kính · bóng núi" / "Không kính" …); Đọc tiếng Nhật (`Picker` dạng menu ngay trên dòng: "Bình thường", "Chậm"); Giữ màn hình sáng khi đi tàu (`Toggle` ngay trên dòng). Chú thích nhóm: "Đọc tiếng Nhật: tốc độ của nút đọc. Giữ sáng: chỉ khi đang theo dõi chuyến."
  - **Riêng tư:** Quyền › (giá trị "\(on)/\(total) đã bật", đếm từ cùng các trạng thái trang Quyền vẽ); Nhật ký vị trí › (giá trị "Bật"/"Tắt"; trang có công tắc, xoá lịch sử, số chỗ ghé · điểm vết).
  - **Dùng khi mất sóng** › (giá trị như `offlineValue` hiện có; Task 5 thay).
  - **Hỗ trợ:** Số đo ›, Nguồn và ghi công ›, Nhà phát triển › (Task 7 thêm Kiểm tra, Log).
  - Chân trang: `"JP27 \(CFBundleShortVersionString) (\(CFBundleVersion)) · Dữ liệu nghiên cứu ngày \(researched)."`
- [ ] **Step 8: Trang Bản đồ.** "Kính trên bản đồ" (`map.glass`), "Bóng địa hình" với dòng phụ "Tốn pin hơn" (`map.relief`); chú thích một câu. `MapTab`: `.environment(\.mapGlass, glass)` (bỏ `|| !readings`); `TripMap`: `c.showsRelief(relief, in: map)` (bỏ `readings &&`). "Đo khung hình bản đồ" (`debug.mapFrames`) chuyển sang Nhà phát triển.
- [ ] **Step 9: Hai tuỳ chọn.** `Speaker.say(_:slow:)` đọc `SpeechPace` khi `slow == nil`; các lời gọi `slow: true` giữ nguyên. `TalkShared` thay `isIdleTimerDisabled = true/false` bằng `KeepAwake.set(.showCard, true/false)`. `AppModel`: `KeepAwake.set(.ride, keepAwakeSetting && live.ride != nil && !asleep)` khi một trong ba đổi (`activate`, `deactivate`, chọn/kết thúc chuyến, đổi công tắc).
- [ ] **Step 9b: Ghi log đổi tuỳ chọn.** Mỗi lần đổi Giao diện, kính, bóng, tốc độ đọc, giữ sáng, nhật ký vị trí, ngày thay thế, tốc độ đi bộ, chạy thử: `AppLog.info(.settings, "<tên tuỳ chọn>", ["value": …])` (giá trị là lựa chọn, không chữ tự gõ).
- [ ] **Step 10: Chú thích ngắn.** Mỗi trang con nhiều nhất một câu; thay câu dài của "Đo khung hình bản đồ" bằng: "Hiện ở góc bản đồ thời gian của từng khung hình."
- [ ] **Step 11: Checklist thiết bị § 4:**
  1. Mọi ô biểu tượng ở trang chính và các trang con nằm gọn trong ô (chụp màn, sáng và tối, cỡ chữ lớn nhất). **duyệt thiết kế**
  2. Tắt "Kính trên bản đồ" → các nút trên bản đồ không còn kính, không cần bật đo.
  3. "Đọc tiếng Nhật: Chậm" → nút đọc ở Nói chuyện đọc chậm; "Đọc chậm" vẫn chậm khi đặt Bình thường.
  4. Bật "Giữ màn hình sáng khi đi tàu", theo dõi một chuyến, để yên 5 phút → màn hình không khoá; kết thúc chuyến → khoá theo cài đặt máy.
  5. Mở thẻ đưa nhân viên xem trong lúc đi tàu, tắt công tắc giữ sáng → thẻ vẫn giữ sáng.
- [ ] **Step 12: Kiểm và commit.**

```bash
git commit -m "Settings in pages: fitted icons, Experience and Privacy groups, map options that apply, reading pace, screen kept on during a ride"
```

---

### Task 5: Sẵn sàng khi mất sóng — trạng thái 7 mục, gói ngôn ngữ (spec 1.3)

Bậc **T2**.

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Offline/Readiness.swift`, test `ReadinessTests.swift`
- Create: `ios/JP27/Services/OfflineReadiness.swift`
- Modify: `Services/Media.swift` (`Prefetch`: tách `dayMapRequest`, lưu `lastPage`), `Features/Today/TodayHome.swift` (lưu cỡ trang khi đo), `Features/Fuji/FujiTerrainSnapshot.swift` (lưu cỡ, `has(_:)`), `Services/ForecastService.swift` (`fetched(_:)`), `Features/Settings/OfflinePage.swift`, `SettingsView.swift` (giá trị, Cần xem)

**Interfaces:**
- Produces (TripKit):
  - `public enum ReadyItem: String, CaseIterable, Codable, Sendable { case maps, dayMaps, photos, fuji, forecasts, translation, speech }` (thứ tự hiển thị)
  - `public enum ReadyState: Sendable, Equatable { case ready; case missing(done: Int?, total: Int?); case working(Double); case waitingForNetwork; case failed(String); case unsupported(String); case needsSetup(String) }`
  - `public enum Readiness { static let forecastFresh: TimeInterval = 43_200; static func summary(_ s: [ReadyItem: ReadyState], mapsStale: Bool, downloading: Double?) -> String; static func plan(_ s: [ReadyItem: ReadyState]) -> [ReadyItem]; static func forecasts(fetched: [Date?], now: Date) -> ReadyState }`
- Produces (app):
  - `@Observable final class OfflineReadiness { private(set) var states: [ReadyItem: ReadyState]; func refresh() async; func installSpeech() async }` — sở hữu bởi `Downloads` (`downloads.readiness`).
  - `Prefetch.dayMapRequest(_ day: Day, photo: Photo?, model: AppModel, page: Page) async -> MapSnapshots.Request?`; `Prefetch.lastPage: Page?` (lưu `UserDefaults` khoá `"prefetch.page"`: width, length, scale, dark).
  - `FujiTerrainPictures.lastSizes: (area: CGSize?, spot: CGSize?, scale: CGFloat?)` (khoá `"fuji.sizes"`); `func has(_ r: Request) async -> Bool` (memory hoặc đĩa, không vẽ).
  - `ForecastService.fetched(_ key: String) -> Date?` (bộ nhớ, rồi đĩa).

- [ ] **Step 1: Test hỏng** `ReadinessTests`:
  - `allReadyIsReady`: mọi mục `.ready` → `"Sẵn sàng"`.
  - `unsupportedDoesNotCount`: `speech: .unsupported(…)`, còn lại ready → `"Sẵn sàng"`.
  - `countsWhatIsMissing`: `photos: .missing(done: 3, total: 9)`, `translation: .missing(nil, nil)` → `"Thiếu 2 mục"`.
  - `downloadingWins`: `downloading: 0.424` → `"Đang tải 42%"` (cả khi `mapsStale`).
  - `staleMapsBeforeCount`: `mapsStale: true`, không tải → `"Cần tải lại"`.
  - `planOrder`: mọi mục thiếu → `[.translation, .speech, .photos, .maps, .dayMaps, .fuji, .forecasts]`; mục ready hay unsupported bị bỏ; `needsSetup` bị bỏ.
  - `forecastsFreshWithin12Hours`: `now`, mọi ngày trong vòng 12 giờ → `.ready`; một nil trong 3 → `.missing(done: 2, total: 3)`; một ngày 12 giờ 1 giây trước → `.missing(done: 2, total: 3)`.
- [ ] **Step 2–4:** chạy hỏng, viết `Readiness`, PASS.
- [ ] **Step 5: Đọc trạng thái (app).** `OfflineReadiness.refresh()`:
  - `maps`: mọi vùng của `OfflineMaps.areas` hoàn tất → ready; đang tải → `working(fraction)`; còn lại `missing(done: complete.count, total: areas.count)`.
  - `dayMaps`: `Prefetch.lastPage == nil` → `needsSetup("Mở trang Hôm nay một lần")`; nếu không, với mọi ngày trong `model.days` và ngày thay thế, đếm `MapSnapshots.shared.stored(request) != nil` (request từ `dayMapRequest`).
  - `photos`: `OfflinePhotos.saved/total`.
  - `fuji`: thiếu cỡ → `needsSetup("Mở trang Fuji một lần")`; nếu không, đếm `has(_:)` cho mỗi điểm ngắm (`.spot`, cỡ thẻ) và mỗi `FujiArea.allCases` (`.area`, cỡ hero), **cả sáng và tối** (R-600 trong ledger: thẻ điểm ngắm theo màu ảnh của nó, không theo Giao diện, nên luôn cần cả hai).
  - `forecasts`: `Readiness.forecasts(fetched:)` trên khoá `"summit"` và id mọi điểm ngắm.
  - `translation`: `LanguageAvailability().status(from: .init(identifier: "ja"), to: .init(identifier: "vi"))`: `.installed` → ready, `.supported` → missing, `.unsupported` → unsupported.
  - `speech`: `SpeechTranscriber.supportedLocale(equivalentTo: ja-JP)` nil → `unsupported("Máy này chưa nghe được tiếng Nhật")`; nếu không `AssetInventory.status(forModules:)`: installed → ready, downloading → `working`, supported → missing, unsupported → unsupported. Kiểm chữ ký bằng `bin/apple-decl Speech/AssetInventory`.
  - `installSpeech()`: `AssetInventory.assetInstallationRequest(supporting:)` rồi `downloadAndInstall()`; lỗi → `failed(error.localizedDescription)`.
- [ ] **Step 6: Lưu cỡ.** `TodayHome` lưu `Prefetch.lastPage` khi probe đo được (chỉ khi khác lần trước). `TerrainLayers` lưu cỡ theo `camera.kind` khi `size` đổi.
- [ ] **Step 7: Trang.** `OfflinePage` mở đầu bằng nhóm "Sẵn sàng khi mất sóng": 7 dòng theo `ReadyItem.allCases` (tên: "Bản đồ", "Ảnh bản đồ các ngày", "Ảnh quán, khách sạn", "Ảnh địa hình Fuji", "Dự báo mây", "Gói dịch Nhật–Việt", "Gói nghe tiếng Nhật"), mỗi dòng có trạng thái bằng chữ và nút riêng khi thiếu (bản đồ: mở danh sách vùng; ảnh: tải ảnh; gói dịch: `translator.download()` với `.talkTranslation(translator)` gắn trên trang; gói nghe: `installSpeech()`; ba mục còn lại: Task 6). Danh sách vùng như cũ thành trang con "Bản đồ". `refresh()` khi trang mở và mỗi khi việc tải đổi trạng thái.
- [ ] **Step 8: Trang chính.** Giá trị của "Dùng khi mất sóng" = `Readiness.summary(states, mapsStale: !offline.stale.isEmpty, downloading: downloads.busy ? downloads.fraction : nil)`. Cần xem thêm "Chưa sẵn sàng khi mất sóng" khi tóm tắt không phải "Sẵn sàng" và hôm nay (giờ thật) từ 14 ngày trước `trip.meta.start` tới hết `trip.meta.end`.
- [ ] **Step 9: Checklist thiết bị § 5:** mỗi dòng đúng trạng thái trước và sau khi tải riêng mục đó; gói dịch hiện hộp xác nhận của iOS; máy không có tiếng Nhật cho nghe (nếu có) ghi "Máy này chưa nghe được tiếng Nhật".
- [ ] **Step 10: Kiểm và commit.**

```bash
git commit -m "Offline readiness: seven items with their state, the language packs downloadable from Settings"
```

---

### Task 6: Tải tất cả (spec 1.4)

Bậc **T1** (việc nền dài, lưu qua lần mở app, Live Activity).

**Files:**
- Modify: `ios/Packages/TripKit/Sources/TripKit/Offline/OfflineArea.swift` (`OfflineJob.extras`, `result`), test `OfflineAreaTests.swift`
- Create: `ios/JP27/Services/OfflineExtras.swift`
- Modify: `Services/OfflineMaps.swift` (`Downloads`), `Services/MotionService.swift` (`NetworkStatus.expensive`), `Features/Settings/OfflinePage.swift`

**Interfaces:**
- Consumes: `Readiness.plan`, `OfflineReadiness` (Task 5), `Prefetch.dayMapRequest`, `FujiTerrainPictures.lastSizes/has` (Task 5).
- Produces:
  - `public enum OfflineExtra: String, Codable, Sendable, CaseIterable { case dayMaps, fuji, forecasts }`
  - `public struct ExtraState: Sendable, Equatable { let done: Int; let total: Int; let paused: Bool }`
  - `OfflineJob.init(areas:photos:extras: Set<OfflineExtra> = [])`; `let extras: Set<OfflineExtra>` (giải mã thiếu khoá → `[]`)
  - `OfflineJob.result(phases:photos:mapBuild:extras: [OfflineExtra: ExtraState] = [:]) -> JobResult`
  - App: `Downloads.downloadEverything()`; `NetworkStatus.expensive: Bool` (`path.isExpensive`).

- [ ] **Step 1: Test hỏng** trong `OfflineAreaTests.swift`:
  - `decodesJobSavedBeforeExtras`: `{"areas":["tokyo"],"photos":true}` → `extras == []`.
  - `extrasMustFinishForSuccess`: mọi vùng xong, ảnh xong, `extras: [.dayMaps: ExtraState(done: 20, total: 24, paused: false)]` → `success == false`, subtitle chứa `"Ảnh bản đồ 20/24 ngày"`.
  - `extrasDoneIsSuccess`: mọi extra `done == total` → `"Xong"`.
  - `extraSubtitles`: fuji `60/70` → `"Fuji 60/70 ảnh"`; forecasts `0/1` → `"Dự báo chưa mới"`.
  - `pausedExtraIsPaused`: một extra `paused: true` → `"Đã dừng"`.
- [ ] **Step 2–4:** chạy hỏng, viết, PASS.
- [ ] **Step 5: `OfflineExtras`** (`@Observable final class`, sở hữu bởi `Downloads`): chạy lần lượt `dayMaps`, `fuji`, `forecasts` của việc tải, chỉ khi không vùng nào và ảnh không còn chạy, và khi `network.raw`; mất mạng thì chờ (`waitingForNetwork`) rồi đi tiếp khi có lại.
  - `dayMaps`: với mỗi ngày còn thiếu ảnh, `MapSnapshots.shared.snapshot(for: request)` lần lượt từng ngày (một lần vẽ một lúc).
  - `fuji`: với mỗi request còn thiếu (điểm ngắm và khu, sáng và tối), `FujiTerrainPictures.shared.picture(for:)` lần lượt.
  - `forecasts`: `model.forecasts.hours(key, at:, online: true)` cho đỉnh và mọi điểm ngắm còn cũ.
  - Mỗi bước có `done/total`; `pause()` dừng sau bước đang chạy; `state(_:) -> ExtraState`. Ghi log mỗi phần bắt đầu và kết thúc (`offline`).
- [ ] **Step 6: `Downloads`.** `downloadEverything()`: việc tải nhận mọi vùng còn thiếu (`maps.downloadAll()`), ảnh (`photos.download()`), và `extras` theo `Readiness.plan` của `readiness.states`. `busy`, `fraction` (mỗi extra nặng 1), `progressLine` (thêm `"Ảnh bản đồ x/y"`, `"Fuji x/y"`, `"Dự báo"`), `judgeable`, `finish` (`result(…, extras:)`), `expired` (`extras.pause()` khi ở nền) theo cùng cách đang làm với ảnh.
- [ ] **Step 7: Nút.** Trên `OfflinePage`, nút "Tải tất cả": nếu `network.expensive` hiện alert "Đang dùng dữ liệu di động" / "Bản đồ và ảnh có thể tốn vài trăm MB." với "Tải luôn" và "Đợi Wi‑Fi" (huỷ). Bấm (hoặc "Tải luôn"): gói dịch (`translator.download()`) và gói nghe (`installSpeech()`) bắt đầu ngay nếu thiếu, rồi `downloadEverything()`. Ba dòng mục `dayMaps`, `fuji`, `forecasts` có nút tải riêng gọi cùng đường với một extra.
- [ ] **Step 8: Checklist thiết bị § 6:**
  1. Wi‑Fi, "Tải tất cả" từ đầu → mọi dòng tới "Sẵn sàng" (hoặc "không hỗ trợ"); Live Activity ghi tiến độ cả ảnh bản đồ và Fuji; kết thúc ghi "Xong".
  2. Dữ liệu di động → hỏi trước; "Đợi Wi‑Fi" không tải gì.
  3. Rời app giữa lúc vẽ ảnh Fuji, dừng từ Live Activity → mở lại ghi "Đã dừng"; "Tải tất cả" lại đi tiếp từ chỗ thiếu.
  4. Sau khi xong, Chế độ máy bay: mở từng ngày, trang Fuji, thẻ điểm ngắm, Nói chuyện (dịch, nghe) → đều dùng được; dự báo ghi giờ cập nhật.
- [ ] **Step 9: Kiểm và commit.**

```bash
git commit -m "Download everything: maps, photos, day map pictures, Fuji terrain, forecasts and language packs in one job"
```

---

### Task 7: Hỗ trợ — Kiểm tra, trang Log, Nhà phát triển trong Release (spec 2.3, 2.4, 3.3)

Bậc **T2**.

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Support/CheckReport.swift`, test `CheckReportTests.swift`
- Create: `ios/JP27/Features/Settings/ChecksPage.swift`, `LogPage.swift`
- Modify: `DeveloperPage.swift`, `SettingsView.swift` (Hỗ trợ, Cần xem: dải giả lỗi)
- Modify (bỏ `#if DEBUG` của công cụ và phần đứng sau nó): `Data/Records.swift` (`failSaves`, `failReads`, `PretendFailure`), `App/UniqueProbe.swift`, `Services/NotificationService.swift:220`, `Services/AlarmService.swift:197`, `Services/Media.swift:634`, `Design/StaticTripMap.swift:461,476`, `Features/Fuji/FujiTerrainSnapshot.swift:361,709`, `Services/RideLiveService.swift:303`, `Features/Plan/RideView.swift:166,209,218` (sau công tắc `dev.rideDetails`). Giữ `#if DEBUG` ở `TripMap.swift:746` (ghi "bản Debug").

**Interfaces:**
- Consumes: `AppLog` (Task 2), `Readiness.summary` + `OfflineReadiness` (Task 5).
- Produces:
  - `public enum CheckLevel: Int, Codable, Sendable, Comparable { case ok, warning, error }`
  - `public enum CheckID: String, Codable, Sendable, CaseIterable { case permissions, offline, storage, records, reminders, sync, network, clock }`
  - `public struct CheckResult: Codable, Sendable, Equatable { let id: CheckID; let level: CheckLevel; let line: String }`
  - `public enum CheckReport { static func summary(_ r: [CheckResult]) -> String; static func storage(freeBytes: Int64) -> CheckLevel; static func clock(rehearsing: Bool) -> CheckResult }`

- [ ] **Step 1: Test hỏng** `CheckReportTests`:
  - `allOkSaysOk`: → `"Ổn"`.
  - `countsWarningsAndErrors`: 1 error, 2 warning → `"1 lỗi · 2 cảnh báo"`; chỉ 2 warning → `"2 cảnh báo"`.
  - `storageWarnsUnderOneGB`: `999_999_999` → `.warning`; `1_000_000_000` → `.ok`.
  - `clockWarnsWhileRehearsing`: `clock(rehearsing: true)` → `CheckResult(id: .clock, level: .warning, line: "Đang chạy thử: giờ của app khác giờ thật")`; false → `.ok`, `"Giờ thật"`.
  - `resultsRoundTripAsJSON`: mã hoá rồi giải mã một mảng → bằng nhau.
- [ ] **Step 2–4:** chạy hỏng, viết, PASS.
- [ ] **Step 5: Trang Kiểm tra.** "Chạy kiểm tra" chạy 8 mục theo `CheckID.allCases` (spec 2.3), mỗi mục một dòng ✓/!/✕ và một dòng ngắn: quyền (đếm như trang Quyền); offline (`Readiness.summary`); bộ nhớ (`volumeAvailableCapacityForImportantUsage` và dung lượng `Application Support` + `Caches` + gói bản đồ `offline.totalBytes`); sổ (`Records.problem`, `model.saveIssue`); nhắc giờ và báo thức (`UNUserNotificationCenter.current().pendingNotificationRequests().count`, `alarms.lastError`, `model.reschedules`); đồng bộ (`ledgerSync.lastSync`, chưa bao giờ → warning); mạng (`network.raw`, rồi HEAD tile `0/0/0` của build đang đọc và `https://api.open-meteo.com/v1/forecast` với timeout 10 giây); đồng hồ (`CheckReport.clock(rehearsing: model.rehearsing)`). Lưu mảng kết quả và giờ chạy (`UserDefaults` khoá `"checks.last"`), ghi mỗi kết quả vào log (`check`). Giá trị dòng ở trang chính: `CheckReport.summary` của lần gần nhất, hoặc "Chưa chạy".
- [ ] **Step 6: Trang Log.** Danh sách `AppLog.recent(limit: 200, minimum:)` với `Picker` phân đoạn "Tất cả" / "Cảnh báo" / "Lỗi"; mỗi dòng: giờ (`HH:mm:ss`), nhóm, câu, mức bằng màu. "Xuất log": `AppLog.export(info:)` với `info` gồm phiên bản, build, `UIDevice.current.systemVersion`, đời máy (`utsname.machine`), ngôn ngữ, múi giờ, chỗ trống, `Appearance`, `SpeechPace`, giữ sáng, kính, bóng, tóm tắt offline, kết quả kiểm tra gần nhất (JSON); rồi bảng chia sẻ cho URL đó. "Xoá log" có alert xác nhận. `AppLog.lastWriteError()` có thì hiện ở đầu trang. Giá trị dòng ở trang chính: `ByteCountFormatter` của `AppLog.usage()`.
- [ ] **Step 7: Nhà phát triển trong Release.** Bỏ `#if DEBUG` theo danh sách Files. "Giả lỗi lưu" và "Giả lỗi đọc sổ chi": đổi sang một giá trị khác Tắt phải qua alert "Bật giả lỗi?" / "Lưu sẽ báo lỗi tới khi tắt hoặc mở lại app." Thêm công tắc "Chi tiết kiểm tra ở màn đi tàu" (`dev.rideDetails`, mặc định tắt) cho các dòng của `RideView`. "Đo khung hình bản đồ" ở đây. Mỗi lần dùng một công cụ: `AppLog.info(.dev, "<tên công cụ>")`. Trang chính, nhóm Cần xem: khi `Records.failSaves != .off || Records.failReads`, dải đỏ "Đang giả lỗi lưu" với nút "Tắt".
- [ ] **Step 8: Hỗ trợ trên trang chính:** Kiểm tra ›, Log ›, Số đo ›, Nguồn và ghi công ›, Nhà phát triển ›.
- [ ] **Step 9: README.** Mục Cài đặt và mục chẩn đoán của `ios/README.md` theo bố cục mới; nhắc Nhà phát triển có cả trong Release.
- [ ] **Step 10: Checklist thiết bị § 7:**
  1. Bản Release: Nhà phát triển có đủ công cụ; bật "Giả lỗi lưu: Mọi lần lưu" hỏi trước; trang chính hiện dải đỏ; "Tắt" tắt ngay; mở lại app thì đã tắt.
  2. "Chạy kiểm tra" khi có mạng và khi Chế độ máy bay: mục mạng đổi đúng; có dòng tương ứng trong log.
  3. Xuất log, gửi qua AirDrop sang máy tính, giải nén: có `info.json` với kết quả kiểm tra.
- [ ] **Step 11: Kiểm và commit.**

```bash
git commit -m "Support: a checks page, the log page with export, developer tools in Release behind confirmations"
```

---

## Kết thúc

- Review toàn nhánh ở `max`, một đợt sửa, một re-review có phạm vi (hợp đồng § 2).
- Báo cáo `docs/superpowers/reports/<ngày>-offline-settings-report.md` (tóm tắt tiếng Việt, đã kiểm, chưa đo, ruling kèm giá
  nếu sai).
- PR vào `main` từ `local/loving-feynman-6wu9ru`, mục "Việc của người dùng" trỏ tới checklist thiết bị. Không merge.

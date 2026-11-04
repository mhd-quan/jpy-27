# Global constraints (verbatim from the plan, docs/superpowers/plans/2026-11-03-ios-hardening-and-smoothness.md § Global Constraints)
## Global Constraints

- iOS deployment target `26.0`; Xcode 26; `SWIFT_VERSION: "6.0"`; app code mặc định `MainActor` (`SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, `ios/project.yml`).
- TripKit: `swift-tools-version: 6.0`, `platforms: [.iOS("26.0"), .macOS("15.0")]`, **không import framework chỉ có trên Apple** (không CryptoKit, SwiftData, CoreLocation, AlarmKit, UIKit, MapLibre). Mọi test mới phải chạy được bằng `swift test` trong container `swift:6.2-noble`.
- Không có test target cho app (`project.yml` không có target test; CI chạy Ubuntu). Logic phải nằm trong TripKit để được test; phần app kiểm bằng checklist trên máy + Instruments (Task 6.2).
- MapLibre giữ `exactVersion: 7.0.0` (`ios/project.yml`); không nâng trong kế hoạch này.
- SwiftData: chỉ thêm thuộc tính optional/có default thì không cần migration; đổi `#Unique` hay ý nghĩa cột thì phải có `VersionedSchema` + `SchemaMigrationPlan` (đúng như chú thích `Records.container()`).
- Không bao giờ mất dữ liệu âm thầm: mọi lỗi ghi đều tới UI; đường "sổ phụ" (`Records.problem`) giữ nguyên.
- Trần số tiền nhập: `9_999_999` yên — một hằng duy nhất `Yen.maxEntry` dùng cho bàn phím, CSV, dữ liệu từ máy kia.
- Bộ từ haptic giữ nguyên tên (`press`, `pick`, `page`, `snap`, `key`, `done`, `warn`, `fail`, `notch`, `.start/.stop`; `ios/README.md` § Rung).
- Chữ trên UI tiếng Việt, cùng giọng hiện có; số tiền qua `Fmt.yen`.
- Tôn trọng Reduce Motion và Low Power Mode ở mọi animation và việc nền mới.
- Đo hiệu năng chỉ trên bản **Release**, mở từ màn hình chính (scheme `Run` đã là Release).
- Mục tiêu đo (spec D): chạm → khung đầu < 50 ms; 0 hitch khi zoom mở trang ngày, trang địa điểm, thẻ Fuji; 0 khung rớt khi cú vuốt ảnh dừng.
- Commit message tiếng Anh, mô tả như lịch sử hiện có, mỗi task một hoặc vài commit; CI `TripKit` phải xanh trước khi merge.

# Plus: execution contract §4 (docs/superpowers/plans/2026-11-03-execution-contract.md) — Swift 6.3 concurrency rules, API ledger, data compatibility, UI copy, git rules. Read §4 in full.
Note: the plan's Global Constraints line about CI says swift:6.2-noble; ruling R-03 moved CI and TripKit to Swift 6.3 (tools 6.3, swift:6.3-noble, Xcode 26.6 app job).

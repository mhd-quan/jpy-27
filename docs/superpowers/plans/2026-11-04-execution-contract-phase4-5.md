# Hợp đồng thực thi — Bước 0, Task 0.2 và Phase 4–5 của kế hoạch iOS tháng 11

Kế hoạch: `docs/superpowers/plans/2026-11-03-ios-hardening-and-smoothness.md` (gọi tắt **plan**). Spec:
`docs/superpowers/specs/2026-11-03-ios-review.md`. Bàn giao: `docs/superpowers/handoffs/2026-11-04-phase-4-5/README.md`.
Khuôn: hợp đồng Phase 1–3 (`docs/superpowers/plans/2026-11-03-execution-contract.md`).

Tài liệu này quy định **ai làm, với năng lực nào, biết gì, và phải chứng minh gì** trước khi một task được
tính là xong. Mọi agent implementer và reviewer đọc file này trước brief của mình. Chỗ nào file này và brief
khác nhau thì file này thắng ở phần quy trình, brief thắng ở phần giá trị (số, chuỗi, chữ ký hàm, test case).
Ruling của lượt này đánh số từ R-200 và nằm trong ledger của controller; brief nào chịu ảnh hưởng thì
nhận nguyên văn ruling đó.

## 1. Môi trường: cái gì kiểm được ở đâu

Đo ngày 4/11/2026 ở commit `9ace045` (đầu R-157: Swift 6.2.3, Xcode 26.2).

| Cần kiểm | Ở đâu | Kết quả đo |
| --- | --- | --- |
| TripKit `swift test` | Máy agent: toolchain Swift **6.2.3** tải từ swift.org, `export PATH=/home/user/toolchains/swift-6.2.3-RELEASE-ubuntu24.04/usr/bin:$PATH`. CI: container `swift:6.2.3-noble` | 359 test / 27 suite xanh, không warning |
| Pipeline dữ liệu | Node 22, `node --test 'scripts/*.test.mjs'`, `node scripts/lint-saves.mjs`, `node scripts/check-plan.mjs` | 64 test xanh; lint và check-plan exit 0 |
| **Biên dịch app** (SwiftUI, MapLibre, MapKit, AVFoundation, ActivityKit, MetricKit) | **Không có trên máy agent.** CI job `app` ("App builds"): `macos-26`, Xcode **26.2** (Swift 6.2.3), simulator, không ký | Xanh, "0 warnings in the build, 0 in ios/JP27, ios/JP27Widgets, ios/Shared" |
| Chạy app, Instruments, simulator, GPS, hai máy | Chỉ máy thật của người dùng | Gom vào `docs/perf/2026-11-device-perf-phase4-5.md` (Bước 0: checklist Phase 1–3) |
| **Đo hiệu năng** | **Chỉ người dùng, trên máy, bản Release**, mở từ màn hình chính | Agent không bao giờ báo là đã đo |
| Chữ ký API Apple | `.superpowers/sdd/2026-11-03-ios-hardening-and-smoothness/bin/apple-decl <framework>/<type>/<member>` | Chạy được |
| Header MapLibre 7.0.0 | `…/bin/maplibre-header MLNMapSnapshotter.h` (tag `ios-v7.0.0`) | Chạy được |

Hệ quả: code app chỉ được "biên dịch bằng mắt" cho tới khi CI `app` chạy. Vì vậy (a) logic có thể sai nằm
trong TripKit; (b) phần app mỏng, và mọi API hệ thống mới có trích dẫn (§ 4.3); (c) CI `app` đỏ, hay có
warning, là finding Critical của task vừa xong, vào fix loop như mọi finding khác. Code không được dùng gì
mà chỉ Swift 6.3 / Xcode mới hơn 26.2 nhận.

## 2. Các ghế và mức effort

Effort chọn theo hậu quả của một quyết định sai *không bị test bắt*, không theo độ dài task. Model chọn theo
skill SDD: bậc mạnh nhất cho mọi ghế T1/T2, mọi reviewer task, review toàn nhánh và vòng sửa 4–5; bậc chuẩn
cho implementer T3, mutation probe, và re-review không chạm đồng thời hay dữ liệu lưu. Lý do lệch khỏi mặc
định "model rẻ nhất làm được": code app chỉ biên dịch trên CI (mỗi vòng khoảng 7 phút), nên một lỗi biên
dịch của implementer đắt hơn ghế của nó.

| Ghế | Effort | Vì sao mức này |
| --- | --- | --- |
| Implementer **T1** (máy trạng thái, đồng thời, cache trên đĩa, việc ngoài main) | `xhigh` | Lỗi im lặng: session âm thanh bị giữ, file cache bị xoá nhầm, ảnh sai trang |
| Implementer **T2** (logic có spec đầy đủ + nối app) | `high` | Spec đủ chi tiết, rủi ro nằm ở phần nối |
| Implementer **T3** (lô sửa nhỏ cùng dạng) | `medium` | Chép theo spec, review bắt phần còn lại |
| Task reviewer (spec + chất lượng + biên dịch bằng mắt) | bằng bậc của task, tối thiểu `high` | Reviewer là lưới duy nhất cho code app cho tới khi CI chạy |
| Mutation probe (TripKit) | `medium` | Việc cơ học |
| Re-review của một vòng sửa | `medium`; `high` khi bản sửa chạm đồng thời hay dữ liệu lưu | Diff nhỏ, phạm vi đã khoá |
| Vòng sửa 4–5 (implementer mới) | effort của task **+1 bậc** | Ba vòng không xong nghĩa là implementer không thấy lỗi của mình |
| Review toàn nhánh | `max` | Một lần, trên toàn bộ diff, có danh sách minor và parked |

Implementer không bao giờ chạy song song (cùng sửa `AppModel.swift`, `Media.swift`, `TripMap.swift`).
Reviewer và mutation probe của cùng một task chạy song song (probe ở worktree riêng, không ghi vào cây chính).

## 3. Mỗi agent biết gì

**Implementer nhận:** (1) brief của task, trích nguyên văn từ plan, là nguồn duy nhất của mọi giá trị;
(2) file này; (3) `interfaces.md` trong workspace — chữ ký *thật sự đã vào code* của các task trước, thắng
plan chỗ hai bên khác nhau; (4) các ruling chạm tới task; (5) các bẫy đã biết, đưa sau khi đọc pre-mortem
(§ 6, ST-2); (6) đường dẫn file report. **Không nhận:** cả plan, lịch sử phiên, report của task khác.

**Reviewer nhận:** brief, report của implementer, review package (diff có ngữ cảnh), Global Constraints
nguyên văn của plan, § 4 của file này, và các ruling chạm tới task. **Không nhận:** ý kiến của controller
về code, lời giải thích riêng của implementer ngoài report.

**Mutation probe nhận:** danh sách file nguồn TripKit mới/đổi, bộ lọc test của task, worktree riêng.

Số dòng trong brief là của commit `4b2e419`; Phase 1–3 đã dời nhiều file (`Media.swift`, `TalkListener.swift`,
`RideLiveService.swift`, `AppModel.swift`, `Records.swift`, `OfflineMaps.swift`, `LocationService.swift`,
`SettingsView.swift`, `ExpenseEditor.swift`) — tìm theo tên symbol.

## 4. Yêu cầu kỹ thuật (Definition of Done)

### 4.1 Bằng chứng

- **TDD:** RED là lệnh đã chạy + output fail + vì sao fail đúng lý do; GREEN là lệnh + output pass. Test
  "phải fail hôm nay" mà pass ngay → phát hiện đó sai: ghi vào report, không giữ test giả.
- Trước khi commit: `cd ios/Packages/TripKit && swift test` toàn bộ bằng Swift 6.2.3 (ghi số test), và khi
  task chạm `scripts/`: `node --test 'scripts/*.test.mjs'` (không dùng `node --test scripts/`),
  `node scripts/lint-saves.mjs`, `node scripts/check-plan.mjs; echo exit=$?`. Phase 4–5 không chạm
  `src/data/` (R-86); mọi diff ở đó là finding.
- Output test sạch: warning mới của compiler trong TripKit là finding.
- **Không bao giờ** sinh lại fixture, nới assertion, `.disabled`, hay xoá test để có màu xanh.

### 4.2 Swift 6.2 và đồng thời

Nền: Swift 6.2.3 / Xcode 26.2 (bản thấp nhất được hỗ trợ, bản trên máy Mac của người dùng); ngôn ngữ Swift 6
(`SWIFT_VERSION: "6.0"` là chế độ ngôn ngữ, không phải bản compiler).

- **App** (`JP27`, `JP27Widgets`): `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` và
  `SWIFT_APPROACHABLE_CONCURRENCY: YES` (gồm `NonisolatedNonsendingByDefault`). Mọi khai báo mặc định trên
  main actor; một hàm `nonisolated … async` chạy **trên actor của nơi gọi**, không tự rời main.
- Việc chặn hay nặng gọi từ main (giải mã/ghép ảnh, đọc/ghi file cache, `AVAudioSession.setActive/
  setCategory`, style snapshot, băm toạ độ) nằm trong `@concurrent nonisolated static func … async` nhận và
  trả giá trị `Sendable`, theo mẫu `Media.swift` (`load(_:maxPixel:network:)`) và `TripMap.swift` (`read`).
  Việc cần thứ tự (session âm thanh) đi qua một executor tuần tự (ruling P4b).
- Kiểu giá trị app dùng ngoài main khai báo `nonisolated`.
- Code mới không dùng `Task.detached`, `DispatchQueue.global().async`, `@unchecked Sendable`,
  `nonisolated(unsafe)`, `MainActor.assumeIsolated` — trừ khi report nêu lý do và chỗ thay thế không có.
- Một `Task {}` thả trôi chỉ hợp lệ khi không ai cần biết nó xong; đường nào iOS cần chờ phải `await` tới
  cùng. Việc nền mới (nạp trước, snapshot, ghép ảnh) huỷ được và tôn trọng Low Power Mode.
- **TripKit:** `swift-tools-version: 6.2`, bật `NonisolatedNonsendingByDefault` và
  `InferIsolatedConformances`; không đặt default isolation MainActor. Lớp điều phối có trạng thái
  (`Coalescer`, `Debouncer`, …) ghi `@MainActor` tường minh; kiểu giá trị là `Sendable`. Không import
  framework chỉ có trên Apple.

### 4.3 API hệ thống không biên dịch được ở đây

Mỗi symbol của framework Apple hay MapLibre mà diff **dùng lần đầu trong repo** (hoặc dùng với chữ ký
khác) có một dòng trong mục **API ledger** của report:
`symbol — nguồn (file:dòng đã dùng sẵn trong repo, hoặc lệnh apple-decl/maplibre-header và chữ ký nó in) — iOS tối thiểu`.
Symbol không trích được thì ghi `UNVERIFIED` và lý do; reviewer coi mỗi `UNVERIFIED` là một rủi ro phải
nhìn. API có `introducedAt` > iOS 26.0 bị cấm. Luật thread của MapLibre (ví dụ `MLNMapSnapshotter`) trích
từ header, không đoán.

### 4.4 Dữ liệu người dùng

- Không mất dữ liệu âm thầm: lỗi lưu tới UI (`persist`/`commit`). Không thêm `try? …save()`, không đọc sổ
  chi bằng `try? …fetch` (`lint-saves` chặn cả hai).
- Đổi dạng dữ liệu đã lưu (`UserDefaults`, SwiftData, file cache có người đọc lại) phải đọc được dạng cũ,
  hoặc report nêu vì sao dạng cũ bỏ được (ví dụ một cache tái tạo được).
- Xoá file chỉ trong thư mục cache mà task sở hữu (`Caches/Snapshots`, `Caches/Ambient`, `Caches/Fuji`,
  `Caches/metrics`), không bao giờ ngoài nó.
- Chạy thử (`Shared.rehearsing`) không đặt báo thức thật, không ghi nhật ký thật, không gửi/ack sổ chi;
  R-153: chuyến chạy thử không đụng báo thức thật.

### 4.5 Chữ trên UI

Tiếng Việt, cùng giọng với chữ sẵn có quanh chỗ sửa (câu ngắn, không dấu chấm than, số tiền qua `Fmt.yen`).
Haptic dùng đúng bộ tên trong `ios/README.md` § Rung. Animation mới dùng token của `Motion` (sau 5.8a) và
`Motion.reduced` cho Reduce Motion.

### 4.6 Git

- Chỉ commit trên nhánh hiện tại (`claude/ios-phases-4-5`). Không push, không đổi nhánh, không rebase,
  không tạo PR — controller push sau khi task qua review.
- Commit message tiếng Anh theo giọng lịch sử (`git log --oneline -20`), kết thúc bằng các dòng
  attribution mà phiên làm việc quy định (controller chép nguyên văn vào dispatch).
- Không ghi tên hay mã model vào code, comment, docs, commit (ngoài dòng attribution).
- Chỉ sửa file brief liệt kê. File khác cần chạm → mục "File ngoài danh sách" trong report, kèm lý do.

### 4.7 Bước "Đo", "chụp màn", "duyệt thiết kế", "spike trên máy"

Agent không có máy. Những bước này **không bao giờ** được báo là đã làm. Implementer chép chúng (đã chỉnh
theo code thật: tên công tắc, màn, signpost, file) vào `docs/perf/2026-11-device-perf-phase4-5.md` dưới
tiêu đề task của mình, kèm ô trống để người dùng điền số hay kết luận, và ghi mã kịch bản S1–S10 của
`docs/perf/2026-11-baseline.md` khi bước đo một kịch bản. Bước kiểm trên máy của Bước 0 (sửa đúng/sai)
chép vào `docs/superpowers/checklists/2026-11-device-phase1-3.md`. Công tắc hay dòng Chẩn đoán mà bước cần
là code của task (chỉ bản Debug, trừ khi brief nói khác; Chẩn đoán › Số đo có trong mọi bản).

### 4.8 Không dispatch agent con

Implementer và reviewer làm hết phần việc của mình; không tạo subagent, không tự gọi reviewer.

## 5. Thứ tự, tách task, bậc

Bước 0 đi PR riêng và merge trước (plan cấm trộn đúng/sai với làm mượt). Bước 1 (phần code của 0.2) đi
trước mọi task Phase 4 (P3); commit của nó là **baseline commit** để người dùng đo. 5.8 tách đôi (P1);
5.5 trước 5.3 (P2); 5.4 trước 5.3 (P12).

| # | Dispatch | Bậc | Implementer | Reviewer | Mutation probe |
| --- | --- | --- | --- | --- | --- |
| 0 | Bước 0: New-1 (`ended` theo đồng hồ), New-2 (`Presence.takes` khi đồng hồ lùi), M3 (formatter với số hữu hạn cực lớn); New-3, nit `.ack` nếu rẻ | T2 | high | high | có (`RideClock`, `Presence`) |
| 0.2 | Perf: signpost, `transitionSettled`, Chẩn đoán › Số đo, MetricKit; `docs/perf/2026-11-baseline.md` | T2 | high | high | — |
| 4.1 | `StaticTripMap`, `SnapshotKey` | T1 | xhigh | xhigh | có (`SnapshotKey`) |
| 4.2 | Audio session ngoài main, nhả có hẹn, máy trạng thái session (P4, P4b) | T1 | xhigh | xhigh | có |
| 4.3 | Low Power Mode quan sát được | T3 | medium | high | — |
| 5.8a | `Motion.swift` + README | T3 | medium | high | — |
| 5.1 | `HeroPipeline`, `DecodePlan` | T1 | xhigh | xhigh | có (`DecodePlan`) |
| 5.2 | `DetailHero` không blur thật | T2 | high | high | — |
| 5.5 | Khung đầu là khung cuối (P6) | T2 | high | high | — |
| 5.4 | Tab Bản đồ, `Debouncer` | T2 | high | high | có (`Debouncer`) |
| 5.3 | Fuji 3D theo phương án dự phòng (P7, P11, P12) | T1 | xhigh | xhigh | có, nếu có logic thuần mới |
| 5.6 | Thẻ câu | T2 | high | high | — |
| 5.7 | Nạp trước, chính sách "≤ 3 đang chạy" trong TripKit (P16) | T2 | high | high | có |
| 5.9 | Việc nhỏ (P5, P13) | T2 | high | high | — |
| 5.8b | Ánh xạ token, `lint-motion.mjs`, bước CI | T3 | medium | high | — |
| — | Review toàn nhánh | — | — | max | — |

## 6. Stress test

| Mã | Kiểm cái gì | Cách | Đạt khi | Không đạt thì |
| --- | --- | --- | --- | --- |
| ST-1 | Môi trường giống CI | Swift 6.2.3 ở máy agent = `swift:6.2.3-noble` = Xcode 26.2; chạy cả bộ ở commit gốc | Ba nơi cùng xanh trước task đầu tiên | Sửa môi trường trước khi giao task |
| ST-2 | Brief và context có đủ không | Mỗi implementer T1/T2 viết **pre-mortem** trước khi code rồi dừng. Controller chấm với danh sách bẫy viết sẵn mà agent không thấy | Bắt được mọi bẫy mức chặn | Bẫy bị sót đưa vào lệnh tiếp tục; sót ≥ 2 bẫy mức chặn → tăng effort một bậc |
| ST-3 | Reviewer có bắt được lỗi không | Một lần, sau 4.2: cài 3 lỗi vào bản sao diff đã sạch — một lỗi đồng thời (lệnh session chạy trên main), một test không assert gì, một lỗi biên dịch phía app — đưa reviewer như diff thật | 3/3 | Reviewer bậc đó lên `max`, ghi vào ledger |
| ST-4 | Test có đủ chặt không | Mutation probe cho mọi kiểu TripKit mới: 6–10 biến thể lỗi thực tế, chạy test của task | Không biến thể nào sống, hoặc biến thể sống là tương đương | Mỗi biến thể sống là finding Important "thiếu test" |
| ST-5 | Biên dịch bằng mắt có đúng không | CI `app` sau mỗi lần push; đọc dòng `N warnings in the build, M in ios/JP27, ios/JP27Widgets, ios/Shared` | Xanh, 0 và 0 | Critical của task đó, vào fix loop trước khi giao task kế |

## 7. Khi nào dừng hỏi

Ngoài điểm dừng sau Bước 0 (PR riêng, người dùng merge), chỉ bốn trường hợp: thao tác không đảo ngược;
việc nhạy cảm bảo mật; tác dụng phụ ngoài nhánh mà thông lệ phải hỏi; plan hỏng tới mức mọi hướng đều là
đoán. Còn lại controller ra ruling, ghi `Ruling: <quyết định> — <vì sao> — <giá phải trả nếu sai>` vào
ledger và đi tiếp.

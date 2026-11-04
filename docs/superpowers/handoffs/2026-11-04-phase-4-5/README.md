# Bàn giao: Phase 4–5 của kế hoạch iOS JP27

Viết ngày 4/11/2026. Lượt trước (controller SDD) đã làm xong Phase 0–3. Tài liệu này dành cho agent
nhận Phase 4 (chokepoint) và Phase 5 (mở/thu mượt). Nó tự đủ: workspace `.superpowers/sdd/…` của lượt
trước không đi theo container mới. Những gì còn dùng được đều đã chép vào thư mục này.

## 0. Đọc theo thứ tự

1. Tài liệu này.
2. Báo cáo Phase 0–3, [`docs/superpowers/reports/2026-11-04-phases-0-3-report.md`](../../reports/2026-11-04-phases-0-3-report.md). Đọc các mục "Trước khi phát hành" và "Hành vi còn lại"; danh sách phán quyết đọc lướt.
3. Kế hoạch, [`docs/superpowers/plans/2026-11-03-ios-hardening-and-smoothness.md`](../../plans/2026-11-03-ios-hardening-and-smoothness.md). Đọc:
   - Global Constraints và Review Focus 5;
   - "Bản đồ thay đổi" và "Thứ tự và phụ thuộc";
   - **Task 0.2**, **Phase 4**, **Phase 5**, **Task 6.2**;
   - "Rủi ro và cách giữ".
4. Spec, [`docs/superpowers/specs/2026-11-03-ios-review.md`](../../specs/2026-11-03-ios-review.md): mục B (chokepoint), C (độ mượt), D (đo).
5. Hợp đồng thực thi của Phase 1–3, [`docs/superpowers/plans/2026-11-03-execution-contract.md`](../../plans/2026-11-03-execution-contract.md). Đây là khuôn để viết hợp đồng cho Phase 4–5 (§ 5 dưới đây).
6. [`interfaces-phase0-3.md`](interfaces-phase0-3.md): chữ ký và hành vi *thật sự* đã vào code ở từng task. Chỗ nào khác plan thì file này đúng.
7. [`docs/superpowers/checklists/2026-11-device-phase1-3.md`](../../checklists/2026-11-device-phase1-3.md): xem các bước kiểm trên máy được viết theo dạng nào.

## 1. Trạng thái lúc bàn giao

**Đã có trên `main`** (merge từ nhánh `claude/festive-maxwell-om1zy7`, base `4b2e419`):
- T0: Swift 6.3; CI có job "App builds".
- 0.1: gate khả thi của lịch.
- Phase 1: 1.1 báo thức, 1.2 lên lịch lại, 1.3 tiền, 1.4 lưu không im lặng, 1.5 đồng bộ có ack.
- Phase 2: 2.1a/b/c id ổn định.
- Phase 3: 3.1a/b offline, 3.2 nhật ký, 3.3a/b theo dõi trong ngày, 3.4a/b/c vòng đời.
- Một đợt sửa cuối, sau review toàn nhánh.

**Đã kiểm ở đầu nhánh:**
- TripKit 359 test / 27 suite.
- Node 64 test.
- `lint-saves`, `check-plan`, `check-ids` và `ios:data` đều sạch.
- CI xanh, dòng tổng kết "0 warnings in the build, 0 in ios/JP27, ios/JP27Widgets, ios/Shared".

**Chưa làm:**
- **Task 0.2 (đo nền)** được hoãn theo ruling R-01, vì cần máy thật và chỉ phục vụ Phase 4–5. Phần code của nó là việc đầu tiên của lượt này (§ 4, Bước 1).
- **Device checklist Phase 1–3**, phần của người dùng.
- **Ba lỗi đúng/sai nhỏ còn mở**, làm ở § 4, Bước 0:
  - New-1 và New-2, từ lần review lại cuối;
  - M3 của 3.4c.

## 2. Môi trường (đã đo ở lượt trước)

| Việc | Ở đâu | Ghi chú |
| --- | --- | --- |
| TripKit | `export PATH=/opt/swift/usr/bin:$PATH; cd ios/Packages/TripKit && swift test` | Swift 6.3.3, khoảng 17 s cho cả bộ |
| JS | `node --test 'scripts/*.test.mjs'` | Viết đúng như vậy. `node --test scripts/` fail trên Node 22 |
| Lint/gate | `node scripts/lint-saves.mjs`, `node scripts/check-plan.mjs`, `npm run ios:data && git status --porcelain` | Cả ba đều chạy trong job CI `data` |
| **Biên dịch app** | **chỉ CI**: job `app` ("App builds"), `macos-26`, Xcode 26.6 | Đọc bước "Warnings" (§ 2.1 dưới bảng). CI đỏ hoặc có warning là finding Critical |
| Chạy app, Instruments, simulator, AlarmKit, GPS | **không có** | Mọi bước "Đo", "chụp màn", "duyệt thiết kế", "spike trên máy" là việc của người dùng |
| Chữ ký API Apple | `kit/bin/apple-decl alarmkit/alarmmanager/alarms` | Đọc JSON tài liệu Apple: in declaration và iOS tối thiểu. Đường dẫn lấy theo URL của trang tài liệu, viết thường |
| Header MapLibre 7.0.0 | `kit/bin/maplibre-header MLNMapSnapshotter.h` | Lấy theo tag `ios-v7.0.0`, đúng bản `project.yml` ghim |
| Gói review | `kit/bin/review-pkg BASE HEAD OUT` (chạy ở gốc repo) | Bỏ JSON sinh ra (một dòng 1–2 MB), thay bằng diff ngữ nghĩa |

### 2.1 Những điều cần biết khi làm việc trong môi trường này

- **Đọc kết quả CI:** dùng `get_job_logs` của GitHub MCP cho job "App builds", lấy khoảng 50 dòng cuối, rồi tìm dòng `N warnings in the build, M in ios/JP27, …`.
- **Chờ CI:** CI cần nhiều phút. Đừng poll; dùng `send_later` để nhắc chính mình, sau đó đọc `ReadNotifications`. Chỉ giao task kế tiếp khi CI xanh ở base của nó.
- **Cài đặt đồng thời:**
  - App chạy `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` + `SWIFT_APPROACHABLE_CONCURRENCY: YES`. Một hàm `nonisolated … async` chạy trên actor của nơi gọi; muốn rời main thì phải dùng `@concurrent nonisolated static func`. Mẫu có sẵn: `Media.swift` `load(_:maxPixel:network:)`, `TripMap.swift` `read`.
  - TripKit dùng tools 6.3, bật `NonisolatedNonsendingByDefault` + `InferIsolatedConformances`, không đặt default MainActor.
- **Stop hook:** hook "There are uncommitted changes" bật lên khi một implementer đang làm dở, ví dụ test RED chưa commit. Không commit hộ; chờ implementer commit.
- **Container có thể khởi động lại:** implementer commit ngay khi test xanh; controller push sau review.

## 3. Lượt trước đã chạy thế nào, và nên giữ gì

**Quy trình** theo `superpowers:subagent-driven-development`, cộng stress test của hợp đồng § 6. Với mỗi task:
1. Dispatch implementer ở chế độ **pre-mortem rồi dừng**. Controller chấm pre-mortem theo một danh sách bẫy viết riêng mà implementer không thấy (ST-2), ra ruling, rồi viết file `go-<task>.md`.
2. Implementer làm theo TDD và commit (không push).
3. Controller kiểm lại tại máy: `swift test`, node test, lint, grep tên model, không có diff `src/data`. Sau đó push.
4. Dựng `review-pkg`, gửi reviewer (cùng bậc với task, tối thiểu `high`). Mutation probe chạy song song cho task có logic TripKit mới.
5. Vòng sửa: gửi `SendMessage` cho đúng implementer cũ, sau đó review lại trong phạm vi bản sửa.
6. Chờ CI "App builds" xanh, 0 warning (ST-5).
7. Ghi ledger (`Task X: complete`) và thêm mục vào `interfaces.md`.

Cuối cùng: một review toàn nhánh ở mức `max`, **một** đợt sửa, một lần review lại có giới hạn phạm vi, rồi phán xử phần còn lại (không có đợt sửa thứ hai).

**Kết quả:**
- Pre-mortem bắt được mọi bẫy mức chặn ở các task sau.
- Task bậc T1 nào cũng có reviewer tìm ra lỗi thật.
- Review cuối không có lỗi Critical hay Important.

**Bài học, nên mang theo:**
1. **Số dòng trong plan là của commit `4b2e419`.** Phase 1–3 đã dời nhiều file mà Phase 4–5 đụng tới: `Media.swift` (Speaker), `TalkListener.swift`, `RideLiveService.swift`, `AppModel.swift`, `Records.swift`, `OfflineMaps.swift`, `LocationService.swift`, `SettingsView.swift`, `ExpenseEditor.swift`. Tìm theo tên symbol, đừng theo số dòng.
2. **Brief phải liệt kê mọi chỗ đọc một trạng thái bị đổi.** 3.4b từng sót hai chỗ đọc của chạy thử: nhánh discard trong init, và guard của `planWakeAlarms`. Grep hết các chỗ đọc trước khi viết dispatch.
3. **Một ruling đổi máy trạng thái cũng là code.** Lỗi New-1 sinh ra từ một câu trong brief của controller ("clear `ended` on every crossing"). Ruling nào chạm trạng thái thì phải bắt reviewer lần theo nó trên cả hai đồng hồ (giờ thật / chạy thử).
4. **Review package toàn nhánh rất lớn** vì có `trip.json`/`schedule.json` sinh ra. `review-pkg` đã bỏ chúng. Diff toàn nhánh nên tách làm hai: nguồn và test.
5. **Không ghi tên hay mã model vào bất kỳ file nào của repo** (code, comment, docs, commit message ngoài dòng attribution). Lượt trước sót hai chỗ trong hợp đồng thực thi, đã sửa trước khi merge.
6. **Phần app chỉ được biên dịch trên CI**, nên reviewer phải đọc code app như compiler đọc. Mỗi symbol Apple hay MapLibre dùng lần đầu phải có trong mục "API ledger" của report (hợp đồng § 4.3).

## 4. Việc phải làm, theo thứ tự đề xuất

### Bước 0 — ba sửa đúng/sai còn mở (PR riêng, trước Phase 4)

Plan cấm *"trộn một task đúng/sai với một task làm mượt trong cùng PR"*, nên ba sửa này đi PR riêng và merge trước. Làm xong, người dùng chạy được device checklist Phase 1–3 trên một bản đúng.

**New-1. Đang chạy thử, "Kết thúc" một chuyến gần ga bị bỏ ngay.**
- **Ở đâu:** `RideLiveService.claim` (`if clock.endIsKept { ended.insert }`), kết hợp với `AppModel.autoStartRide`.
- **Chuyện gì xảy ra:** chuyến chạy thử không vào `ended`, nên `release` → `rideEnded` → `refresh` → `autoStartRide` theo dõi lại chính chuyến đó, nếu đồng hồ chạy thử nằm trong [giờ đi − 20, giờ đi + 10] phút và máy cách ga đi dưới 400 m.
- **Sửa:**
  - Tách `ended` theo đồng hồ, thành một tập cho giờ thật và một tập cho chạy thử.
  - Chỉ ghi một lần kết thúc khi chuyến kết thúc trên đúng đồng hồ nó được theo dõi (`clock.rehearsal == model.rehearsing`).
  - Mỗi lần offset đổi, chỉ xoá tập của chạy thử.
  - `wasEnded` đọc tập của đồng hồ hiện tại.
  - Bỏ `forgetEnded()` toàn phần.
  - Chỉnh `RideClock.endIsKept` và test của nó (TripKit).
- **Kết quả mong muốn:**
  - Chuyến thật kết thúc bằng tay vẫn kết thúc sau một vòng chạy thử.
  - Chuyến thật kết thúc vì đổi đồng hồ thì không bị giữ, nên checklist 3.4a.9 gạch 3 vẫn đạt.
  - Chuyến chạy thử kết thúc bằng tay giữ kết thúc trong lần chạy thử đó.

**New-2. Chỉnh lùi đồng hồ máy thì mọi fix vị trí bị bỏ cho tới khi mở lại app.**
- **Ở đâu:** TripKit `Presence.takes(accuracy:at:newest:)`, với `newest: fixedAt`, được gọi từ `LocationService.accept` và `didUpdateLocations`. `fixedAt` không bao giờ được đặt lại.
- **Sửa:** cho một fix mới qua quy tắc thứ tự. Hai cách:
  - nhận nó khi `at >= newest || now − at < 5 s`;
  - hoặc đặt lại `fixedAt` khi nó muộn hơn `now`.

  Pin bằng test trong `TrackingTests`, viết RED trước. Checklist có chỉnh lùi đồng hồ ở bước 1.5.5 và khi chuẩn bị 3.4b.

**M3 (3.4c). Số hữu hạn cực lớn vẫn làm formatter crash.**
- **Ở đâu:** `TripTime.swift`, các chỗ `Int(m.rounded(.towardZero))` / `Int(r.rounded())` trong `Fmt.decimal` và `Fmt.km`. Khi |x| ≥ khoảng 9,2e18 thì trap; `km` âm rất lớn cũng trap ở nhánh mét.
- **Sửa:** chặn trước khi đổi sang `Int` và trả "—", giống NaN/±∞ (R-149). Thêm case vào `formatsEdges`, RED trước.

**Làm thêm nếu rẻ** (Minor, đã ghi trong báo cáo):
- New-3: `SpendWallet.csv()` đọc sổ bằng `try?`. Đổi thành `throws` và `try` trong closure `DataRepresentation`.
- Nit `.ack`: trong handler `.ack` của `LedgerSync`, gọi `snapshot()` trước `peerHas`.

**Bậc:** T2, effort `high`. Mutation probe cho `RideClock`/`Presence`.

**Checklist:** thêm bước kiểm cho New-1 và New-2 vào `docs/superpowers/checklists/2026-11-device-phase1-3.md`.

### Bước 1 — Task 0.2, phần code; mốc baseline

Phần code của 0.2 làm được, và **là điều kiện của 4.1, 5.3, 5.4**. Gồm:
- `Perf.swift`: signpost, `TransitionMark`, `MetricsInbox`, `Perf.mark`.
- `EnvironmentValues.transitionSettled`.
- Mốc trong `Presentation.swift` và `AppModel.present/navigate`.
- Chẩn đoán › Số đo.
- Đăng ký MetricKit.

**Mốc baseline:** phép đo nền (0.2 Step 3) phải chạy trên một bản **chưa có code Phase 4–5**. Ghi SHA của commit 0.2 vào `docs/perf/2026-11-baseline.md`, gọi là "baseline commit". Người dùng build đúng commit đó để đo, lúc nào cũng được, nên lượt này không phải chờ số đo mới làm tiếp.

**Những gì agent viết vào `docs/perf/2026-11-baseline.md`:** quy trình đo (Release, mở từ màn hình chính, sạc đầy, mỗi kịch bản 5 lần, lấy trung vị), bảng S1–S10 với các ô số để trống, và các template Instruments cần dùng.

**Bậc:** T2 `high`. Rủi ro nằm ở callback hoàn tất của zoom trong `Presentation.swift`; đọc trước xem host zoom thật sự báo xong ở đâu.

### Phase 4, rồi Phase 5

**Các xung đột tìm được khi quét plan.** Controller ra ruling cho chúng trước khi giao Task 4.1, và ghi vào ledger:

| # | Xung đột | Đề xuất |
| --- | --- | --- |
| P1 | 5.1, 5.3, 5.4, 5.9 dùng `Motion.arrive`/`Motion.pick`, nhưng `Motion.swift` do 5.8 tạo, mà 5.8 nằm sau | Tách 5.8: **5.8a** (chỉ `Motion.swift` + mục README, trước 5.1), **5.8b** (ánh xạ ~82 chỗ gọi + `lint-motion.mjs` + bước CI, cuối Phase 5) |
| P2 | 5.3 Step 4 đặt map thứ hai "trong `LazyVStack` (Task 5.5)", nhưng 5.5 nằm sau 5.3 | Làm 5.5 trước 5.3 |
| P3 | 4.1 Step 3 và 5.3 chờ `transitionSettled`; 5.4 đếm `Perf.mark("map.fly")` | Bước 1 (0.2 code) đi trước mọi task Phase 4 |
| P4 | 4.2 chuyển `AVAudioSession` ra khỏi main. R-146/R-150 (3.4b) cố ý để các lệnh session trên main **cho tới 4.2**, và ngữ nghĩa phải giữ: Speaker rảnh → deactivate (notifyOthers) rồi mới khôi phục `prior`; đang đọc dở → `Speaker.adoptSession()` sang `.playback/.spokenAudio/.duckOthers` (`takeSession`, chỉ một chỗ), để `ended` deactivate | 4.2 dời **cả** `Speaker` lẫn `TalkListener.giveSessionBack`/`activate` trong cùng một task. Thứ tự giữa Listen và Speaker khi đã async là chỗ dễ có race: rút "ai đang giữ session, có lần nhả nào đang hẹn không, `prior` là gì" thành một máy trạng thái thuần trong TripKit có test. Xếp bậc T1 `xhigh` |
| P5 | 5.9 tách `Activity.request` ra khỏi animation. API hiện tại là `RideLiveService.start(_:model:)`, không có `select`/`begin`; `start` có quy tắc chạy thử của R-153 (ghi nhận chuyến chạy thử lúc start; chỉ huỷ báo thức của chuyến theo dõi trên giờ thật khi không chạy thử) | Tách sao cho R-153 và quy tắc "một Live Activity" (3.4a) không đổi; reviewer lần theo cả hai đồng hồ |
| P6 | 5.5 `ExpenseDraft.make` gom logic của `setUp`. `ExpenseEditor` đã có validation (1.3, `Yen.isValidEntry`), lỗi lưu tới UI (1.4) và lỗi đọc sổ (R-154) | `ExpenseDraft` giữ nguyên ba đường đó. Lint `lint-saves` phải còn sạch |
| P7 | 5.3 Step 1 là spike trên máy (snapshot có giữ địa hình 3D không), mà agent không có máy | Viết theo **phương án dự phòng**: hero là ảnh snapshot cache, map sống gắn sau `transitionSettled`, ảnh gỡ khi map báo đã vẽ. Phương án này đúng dù kết quả spike thế nào. Spike thành bước của người dùng; nếu snapshot ra 3D thì một task sau rút gọn lại |
| P8 | 5.1 và 5.2 cần **duyệt thiết kế** trước khi merge (ảnh trước/sau), agent không chụp được | Gom các bước chụp màn vào checklist hiệu năng của người dùng. PR cuối có mục "Cần duyệt thiết kế"; người dùng quyết định merge |
| P9 | Mỗi task Phase 4–5 "chỉ xong khi số đo không tệ hơn baseline", mà agent không đo được | Task xong về code khi qua review + CI. Bước đo chép vào `docs/perf/2026-11-device-perf-phase4-5.md` theo task, có ô số để điền. Báo cáo cuối nói rõ "chưa đo" |

**Thứ tự đề xuất và bậc.** Bậc theo hậu quả của một lỗi mà test không bắt được:

| Thứ tự | Task | Bậc / effort | Mutation probe | Ghi chú |
| --- | --- | --- | --- | --- |
| 1 | 4.1 StaticTripMap | T1 `xhigh` | có (`SnapshotKey`) | MapLibre snapshotter ngoài main: luật thread của `MLNMapSnapshotter` phải trích từ header. Việc xoá file cache (`prune`, `trim`) chỉ được chạm `Caches/Snapshots` |
| 2 | 4.2 Audio session | T1 `xhigh` | có (máy trạng thái session) | P4 |
| 3 | 4.3 Low Power Mode | T3 `medium` | — | `TodayHome.swift` (hai chỗ đọc `isLowPowerModeEnabled` trong body), `AppModel.lowPower`. Xác nhận B3/B4 đã xong ở 1.2 (xem `interfaces-phase0-3.md` § 1.2) |
| 4 | 5.8a Motion tokens | T3 `medium` | — | P1 |
| 5 | 5.1 HeroPipeline | T1 `xhigh` | có (`DecodePlan`) | Task lớn nhất; có thể tách 5.1a (cache, `derive`, tone-2) và 5.1b (`ambient`, `AmbientPhoto`, bỏ state trong transition). Bộ nhớ: `totalCostLimit` 128 MB |
| 6 | 5.2 DetailHero | T2 `high` | — | Duyệt thiết kế (P8); sửa `ios/README.md` |
| 7 | 5.5 Khung đầu | T2 `high` | — | P2, P6 |
| 8 | 5.3 Fuji 3D | T1 `xhigh` | có (`stableOnline`, nếu rút được thành logic thuần) | P7. `NetworkStatus` nằm ở `MotionService.swift` |
| 9 | 5.4 Map tab | T2 `high` | có (`Debouncer`) | `Debouncer` khác `Coalescer` (trailing) |
| 10 | 5.6 Thẻ câu | T2 `high` | — | Đo cỡ chữ bằng `UIFont`; nhớ theo (câu, hướng, Dynamic Type) |
| 11 | 5.7 Nạp trước | T2 `high` | có (chính sách "≤ 3 đang chạy, cái mới huỷ cái cũ nhất", nếu rút thành kiểu thuần) | Cần 5.1 (`ambient`) và 4.3 (`lowPower`) |
| 12 | 5.9 Việc nhỏ | T2 `high` | — | P5; haptic theo bộ tên trong `ios/README.md` § Rung |
| 13 | 5.8b Motion everywhere | T3 `medium` | — | `lint-motion.mjs` có test node viết RED trước; thêm bước vào job `data` |
| — | Review toàn nhánh | `max` | — | Một đợt sửa, một lần review lại, phán xử phần còn lại |

### Việc của người dùng (gom vào một tài liệu, không chặn agent)

- Đo baseline trên baseline commit (0.2 Step 3).
- Các bước "Đo" của từng task, và các ảnh chụp trước/sau cho 5.1, 5.2.
- Spike 3D của 5.3.
- Task 6.2: đo lại sau Phase 4–5; theo dõi MetricKit trong một tuần.
- Device checklist Phase 1–3 (sau Bước 0).

## 5. Hợp đồng thực thi cho Phase 4–5

Viết `docs/superpowers/plans/2026-11-04-execution-contract-phase4-5.md` theo khuôn của hợp đồng cũ, đổi các chỗ sau:
- **§ 1:** thêm dòng "Đo hiệu năng: chỉ người dùng, trên máy, bản Release".
- **§ 2:** ghế và effort theo bảng ở § 4. Chọn model cho từng ghế theo skill SDD; không ghi tên model vào file.
- **§ 4.7:** bước "Đo" và "duyệt thiết kế" đi vào `docs/perf/2026-11-device-perf-phase4-5.md`, không bao giờ báo là đã làm.
- **§ 5:** bảng dispatch mới (Bước 0, Bước 1, các task ở § 4).
- **§ 6:**
  - ST-3 (cài lỗi để thử reviewer) làm một lần sau 4.2, với một lỗi đồng thời (lệnh session trên main), một test không assert gì và một lỗi biên dịch phía app.
  - ST-4 (mutation probe) cho mọi kiểu TripKit mới.
- Giữ nguyên **§ 4.1–4.6** (bằng chứng TDD, Swift 6.3, API ledger, dữ liệu người dùng, chữ trên UI, git), trừ dòng attribution: lấy theo phiên của bạn.

## 6. Quy tắc không được phá

- **R-86 (đầu `src/data/id-renames.ts`):** cho tới khi cả hai máy đã chạy bản có bước chuyển record (2.1c), không thêm hay bớt item ở ngày 1 và ngày 8, và không đổi `line`/`from`/`to`/`via`/`path` của leg nào. Phase 4–5 không có lý do chạm `src/data`; mọi diff ở đó là finding.
- **Chạy thử** (`Shared.rehearsing`): không đặt báo thức thật, không ghi nhật ký thật, không gửi/ack sổ chi. R-153 cũng áp dụng: chuyến chạy thử không đụng báo thức thật.
- **Lỗi lưu không im lặng:** không `try? …save()`, không đọc sổ chi bằng `try? …fetch`. `lint-saves` chặn cả hai.
- Chữ trên UI tiếng Việt, cùng giọng; tiền qua `Fmt.yen`; haptic theo bộ tên.
- Reduce Motion và Low Power Mode được tôn trọng ở mọi animation và việc nền mới.
- MapLibre giữ `exactVersion: 7.0.0`. Không dùng API có `introducedAt` > iOS 26.0.
- Code mới không dùng `Task.detached`, `DispatchQueue.global().async`, `@unchecked Sendable`, `nonisolated(unsafe)`, `MainActor.assumeIsolated` nếu không nêu lý do (hợp đồng § 4.2).
- Không ghi tên hay mã model vào repo.

## 7. Bộ đồ nghề trong thư mục này

| File | Dùng làm gì |
| --- | --- |
| `interfaces-phase0-3.md` | Chép thành `interfaces.md` của workspace mới. Thêm một mục cho mỗi task xong |
| `kit/implementer-common.md` | Cách implementer làm việc: pre-mortem rồi dừng, TDD, report, API ledger |
| `kit/reviewer-common.md` | Rubric reviewer: spec, chất lượng, đọc code app như compiler |
| `kit/rereviewer-common.md` | Review lại trong phạm vi một vòng sửa |
| `kit/mutation-probe.md` | Cách chạy mutation probe trong worktree riêng |
| `kit/review-constraints.md` | Global Constraints và § 4 rút gọn đưa reviewer |
| `kit/bin/apple-decl`, `kit/bin/maplibre-header`, `kit/bin/review-pkg` | § 2 |

Các file `kit/*.md` viết cho Phase 1–3, nên có đường dẫn workspace cũ (`.superpowers/sdd/2026-11-03-…`) và tên hợp đồng cũ. Chép chúng vào workspace mới (`scripts/sdd-workspace PLAN_FILE` của skill in đường dẫn), sửa các đường dẫn đó, và thêm mục "đo do người dùng làm" vào `implementer-common.md`.

Workspace mới thuộc **cùng plan file**, nhưng ledger thì mới. Sau dòng định danh của ledger
(`# SDD ledger — plan: …`), ghi ngay một dòng `Task <N>: complete — see docs/superpowers/reports/2026-11-04-phases-0-3-report.md`
cho mỗi task 0.1, 1.1–1.5, 2.1, 3.1–3.4. Có các dòng này thì skill không dispatch lại những task đó, và bắt đầu ở Bước 0.

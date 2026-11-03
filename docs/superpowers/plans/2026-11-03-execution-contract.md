# Hợp đồng thực thi — Phase 1–3 của kế hoạch iOS tháng 11

Kế hoạch: `docs/superpowers/plans/2026-11-03-ios-hardening-and-smoothness.md` (gọi tắt **plan**). Spec:
`docs/superpowers/specs/2026-11-03-ios-review.md`. Tài liệu này quy định **ai làm, với năng lực nào, biết
gì, và phải chứng minh gì** trước khi một task được tính là xong. Mọi agent implementer và reviewer đọc
file này trước brief của mình. Chỗ nào file này và brief khác nhau thì file này thắng ở phần quy trình,
brief thắng ở phần giá trị (số, chuỗi, chữ ký hàm, test case).

## 1. Môi trường: cái gì kiểm được ở đâu

Đã đo ngày 3/11/2026 ở commit `5782638`.

| Cần kiểm | Ở đâu | Kết quả đo |
| --- | --- | --- |
| TripKit `swift test` | Máy agent: `export PATH=/opt/swift/usr/bin:$PATH` (Swift **6.3.3**). CI: container `swift:6.3-noble` (sau T0) | 74 test / 11 suite xanh, 25 s |
| Pipeline dữ liệu | Node 22.23, `npm ci` đã chạy | `npm run ios:data` + sinh lại fixture: không diff; `check-plan` exit 0 |
| **Biên dịch app** (SwiftUI, AlarmKit, SwiftData, MultipeerConnectivity, MapLibre, ActivityKit) | **Không có trên máy agent.** CI job `app` (T0): `macos-26`, Xcode **26.6** (Swift 6.3.3), simulator, không ký | Chạy sau mỗi lần controller push |
| Chạy app, AlarmKit reo, hai máy ghép sổ, GPS, Instruments | Chỉ máy thật của người dùng | Gom vào checklist Task 6.1 |
| Chữ ký API Apple | `.superpowers/sdd/2026-11-03-ios-hardening-and-smoothness/bin/apple-decl <framework>/<type>/<member>` (đọc JSON tài liệu Apple; ví dụ `apple-decl alarmkit/alarmmanager/alarms` → `var alarms: [Alarm] { get throws }`) | Chạy được |
| Header MapLibre 7.0.0 | `…/bin/maplibre-header MLNOfflinePack.h` (tag `ios-v7.0.0`) | Chạy được |

Hệ quả: **code app chỉ được "biên dịch bằng mắt" cho tới khi CI `app` chạy.** Vì vậy (a) logic có thể sai
nằm trong TripKit như plan đã thiết kế; (b) phần app phải mỏng và mọi API hệ thống mới phải có trích dẫn
(§4.3); (c) CI `app` đỏ là một finding Critical của task vừa xong, vào fix loop như mọi finding khác.

## 2. Các ghế và mức effort

Mọi ghế chạy **Opus 5.5**. Effort chọn theo hậu quả của một quyết định sai *không bị test bắt*, không theo
độ dài task.

| Ghế | Effort | Vì sao mức này |
| --- | --- | --- |
| Implementer bậc **T1** (máy trạng thái, đồng thời, migration dữ liệu, hai máy) | `xhigh` | Lỗi ở đây im lặng: báo thức không reo, khoản chi mất, dấu đã ghé dời sang mục khác |
| Implementer bậc **T2** (logic có spec đầy đủ + nối app) | `high` | Spec đủ chi tiết, rủi ro nằm ở phần nối |
| Implementer bậc **T3** (lô sửa nhỏ cùng dạng) | `medium` | Chép theo spec, review bắt phần còn lại |
| Task reviewer (spec + chất lượng + biên dịch bằng mắt) | bằng bậc của task, tối thiểu `high` | Reviewer là lưới duy nhất cho code app cho tới khi CI chạy |
| Mutation probe (TripKit) | `medium` | Việc cơ học: viết biến thể lỗi, chạy test, đếm biến thể sống |
| Re-review của một vòng sửa | `medium`; `high` khi bản sửa chạm đồng thời hay lưu dữ liệu | Diff nhỏ, phạm vi đã khoá |
| Vòng sửa 4–5 (implementer mới) | effort của task **+1 bậc** (`high`→`xhigh`, `xhigh`→`max`) | Ba vòng không xong nghĩa là implementer không thấy lỗi của mình |
| Review toàn nhánh cuối Phase 3 | `max` | Một lần, trên toàn bộ diff, có danh sách minor và parked |

Implementer không bao giờ chạy song song (cùng sửa `AppModel.swift`). Reviewer và mutation probe của
cùng một task chạy song song (probe ở worktree riêng, không ghi vào cây chính).

## 3. Mỗi agent biết gì

**Implementer nhận:** (1) brief của task, trích nguyên văn từ plan, là nguồn duy nhất của mọi giá trị;
(2) file này; (3) `interfaces.md` trong workspace, tức chữ ký *thật sự đã vào code* của các task trước, có
thể khác plan; (4) các ruling của controller chạm tới task; (5) các bẫy đã biết, đưa sau khi đọc pre-mortem
(§6, ST-2); (6) đường dẫn file report. **Không nhận:** cả plan, lịch sử phiên, report của task khác.

**Reviewer nhận:** brief, report của implementer, review package (diff có ngữ cảnh), Global Constraints
nguyên văn của plan, §4 của file này. **Không nhận:** ý kiến của controller về code, lời giải thích riêng
của implementer ngoài report.

**Mutation probe nhận:** danh sách file nguồn TripKit mới/đổi, bộ lọc test của task, worktree riêng.

Số dòng trong brief là của commit `4b2e419`; các task trước làm lệch dòng — tìm theo tên symbol.

## 4. Yêu cầu kỹ thuật (Definition of Done)

### 4.1 Bằng chứng

- **TDD:** RED là lệnh đã chạy + output fail + vì sao fail đúng lý do; GREEN là lệnh + output pass. Test
  "phải fail hôm nay" mà pass ngay → phát hiện đó sai: ghi vào report, không giữ test giả.
- Trước khi commit: `cd ios/Packages/TripKit && swift test` toàn bộ (ghi số test), và khi task chạm
  `scripts/` hay `src/data/`: `node --test 'scripts/*.test.mjs'` (không dùng `node --test scripts/`: Node 22.23 nạp thư mục như một module và fail), `node scripts/check-plan.mjs; echo exit=$?`,
  `npm run ios:data && git status --porcelain` (diff dữ liệu phải là diff mà task định ra).
- Output test sạch: warning mới của compiler trong TripKit là finding.
- **Không bao giờ** sinh lại fixture, nới assertion, `.disabled`, hay xoá test để có màu xanh. Sinh lại
  fixture chỉ sau khi gate khả thi xanh, và report nói vì sao output đổi (bài học A8).

### 4.2 Swift 6.3 và đồng thời

Nền: Swift 6.3.3 / Xcode 26.6; ngôn ngữ Swift 6 (`SWIFT_VERSION: "6.0"` là chế độ ngôn ngữ, không phải
bản compiler).

- **App** (`JP27`, `JP27Widgets`): đã chạy `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` và
  `SWIFT_APPROACHABLE_CONCURRENCY: YES` (gồm `NonisolatedNonsendingByDefault`). Nghĩa là: mọi khai báo
  mặc định trên main actor; một hàm `nonisolated … async` chạy **trên actor của nơi gọi**, không tự rời
  main.
- Việc chặn hay nặng mà gọi từ main (đọc/ghi file lớn, giải mã CSV người dùng chọn, mã hoá/băm cả sổ,
  `AVAudioSession.setActive/setCategory`, giải mã ảnh) phải nằm trong một hàm
  `@concurrent nonisolated static func … async` nhận và trả giá trị `Sendable`, theo mẫu sẵn có ở
  `JP27/Services/Media.swift` (`load(_:maxPixel:network:)`) và `JP27/Design/TripMap.swift` (`read`).
- Kiểu giá trị app dùng ngoài main (payload mạng, kết quả giải mã) khai báo `nonisolated` như
  `SyncPayload` hiện có.
- Code mới không dùng `Task.detached`, `DispatchQueue.global().async`, `@unchecked Sendable`,
  `nonisolated(unsafe)`, `MainActor.assumeIsolated` — trừ khi report nêu lý do và chỗ thay thế không có.
- Một `Task {}` thả trôi chỉ hợp lệ khi không ai cần biết nó xong; đường nào mà iOS cần chờ (nền,
  background task, hoàn tất của một thao tác người dùng) phải `await` tới cùng (đây đúng là lớp lỗi A5).
- **TripKit** (sau T0): `swift-tools-version: 6.3`, bật `NonisolatedNonsendingByDefault` và
  `InferIsolatedConformances`; **không** đặt default isolation MainActor cho TripKit — nó là thư viện kiểu
  giá trị mà widget và code `nonisolated` của app gọi đồng bộ. Lớp điều phối có trạng thái (`OneAtATime`,
  `WakeAlarms`, `Coalescer`) ghi `@MainActor` tường minh; kiểu giá trị là `Sendable`.

### 4.3 API hệ thống không biên dịch được ở đây

Mỗi symbol của framework Apple hay MapLibre mà diff **dùng lần đầu trong repo** (hoặc dùng với chữ ký
khác) phải có một dòng trong mục **API ledger** của report:
`symbol — nguồn (file:dòng đã dùng sẵn trong repo, hoặc lệnh apple-decl/maplibre-header và chữ ký nó in) — iOS tối thiểu`.
Symbol không trích được thì ghi `UNVERIFIED` và lý do; reviewer coi mỗi `UNVERIFIED` là một rủi ro phải
nhìn. API có `introducedAt` > iOS 26.0 bị cấm.

### 4.4 Dữ liệu người dùng

- Không mất dữ liệu âm thầm: lỗi lưu tới UI (sau Task 1.4: qua `persist`/`commit`). Không thêm
  `try? …save()` (sau 1.4 có lint trong CI).
- Đổi dạng dữ liệu đã lưu (`UserDefaults`, SwiftData, payload notification, payload giữa hai máy) phải đọc
  được dạng cũ, và report nêu dạng cũ → dạng mới ra sao.
- Chạy thử (`clockOffset ≠ 0`) không đặt báo thức thật, không ghi nhật ký thật, không gửi/ack sổ chi
  (Review Focus 3 của plan). Giữ các guard sẵn có (ví dụ `guard clockOffset == 0` trong
  `AppModel.planWakeAlarms`).

### 4.5 Chữ trên UI

Tiếng Việt, cùng giọng với chữ sẵn có quanh chỗ sửa (câu ngắn, không dấu chấm than, số tiền qua
`Fmt.yen`). Haptic dùng đúng bộ tên trong `ios/README.md` § Rung.

### 4.6 Git

- Chỉ commit trên nhánh hiện tại (`claude/festive-maxwell-om1zy7`). Không push, không đổi nhánh, không
  rebase, không tạo PR — controller push sau khi task qua review.
- Commit message tiếng Anh theo giọng lịch sử (`git log --oneline -20`), kết thúc bằng hai dòng:

```
Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Htz1qfRDfwUJVYxzyR76MR
```

- Không ghi tên hay mã model vào code, comment, commit.
- Chỉ sửa file brief liệt kê. File khác cần chạm → mục "File ngoài danh sách" trong report, kèm lý do.

### 4.7 Bước "Kiểm trên máy"

Agent không có máy. Bước kiểm trên máy của brief **không** được báo là đã làm; agent chép nó (đã chỉnh
theo code thật) vào `docs/superpowers/checklists/2026-11-device-phase1-3.md` dưới tiêu đề task của mình.
Công tắc Chẩn đoán mà bước kiểm cần (ví dụ "Báo thức thử sau 2 phút", "Giả lỗi lưu") là code của task, chỉ
có trong bản Debug (`#if DEBUG`).

### 4.8 Không dispatch agent con

Implementer và reviewer làm hết phần việc của mình; không tạo subagent, không tự gọi reviewer.

## 5. Thứ tự, tách task, bậc

Task 0.2 (đo nền) cần máy thật và phục vụ Phase 4–5: hoãn (ruling R-01). Task 0.1 chạy trước vì 2.1 và 3.3
dựa vào nó (R-02). T0 là task mới theo yêu cầu dùng Swift 6.3 (R-03). Task lớn được tách để mỗi diff
review được trong một lượt (R-04).

| # | Dispatch | Bậc | Implementer | Reviewer | Mutation probe |
| --- | --- | --- | --- | --- | --- |
| T0 | Swift 6.3 cho TripKit + CI, job biên dịch app trên `macos-26` | T2 | high | high | — |
| 0.1 | Gate khả thi của lịch | T2 | high | high | có |
| 1.1 | Báo thức: giữ/đặt/thay khi đã xác nhận | T1 | xhigh | xhigh | có |
| 1.2 | Reschedule: `Coalescer`, nền await | T1 | xhigh | xhigh | có |
| 1.3 | Tiền: validation chung, tổng không trap | T2 | high | high | có |
| 1.4 | Lưu bền | T1 | xhigh | xhigh | — |
| 1.5 | Đồng bộ sổ chi có ack | T1 | xhigh | xhigh | có |
| 2.1a | ID trong dữ liệu (JS, export, CI) | T2 | high | high | — |
| 2.1b | ID trong TripKit | T1 | xhigh | xhigh | có |
| 2.1c | ID trong app: migration, notification, fence, widget | T1 | xhigh | xhigh | — |
| 3.1a | Offline: `OfflineArea` + export style bất biến | T2 | high | high | có |
| 3.1b | Offline: `OfflineMaps`/`Downloads`/Cài đặt | T1 | xhigh | xhigh | — |
| 3.2 | Nhật ký vị trí | T2 | high | high | có |
| 3.3a | Tàu đang đi, ngày không giờ, snapshot | T1 | xhigh | xhigh | có |
| 3.3b | ETA theo quãng, phà, kẹp báo thức GPS | T1 | xhigh | xhigh | có |
| 3.4a | Chuyến mồ côi, cờ cũ, fence ngày mai, giờ Live Activity, prompt đã qua | T2 | high | high | — |
| 3.4b | Nghe nhả session, chạy thử offset ~0 | T2 | high | high | — |
| 3.4c | Lô P3 | T3 | medium | high | — |

## 6. Stress test

| Mã | Kiểm cái gì | Cách | Đạt khi | Không đạt thì |
| --- | --- | --- | --- | --- |
| ST-1 | Môi trường giống CI | Toolchain 6.3.3 ở máy agent = `swift:6.3-noble` = Xcode 26.6; chạy cả bộ ở commit gốc trên cả ba | Ba nơi cùng xanh trước task đầu tiên | Sửa môi trường trước khi giao task |
| ST-2 | Brief và context có đủ không, agent ở effort này có thấy bẫy không | Mỗi implementer T1/T2 viết **pre-mortem** trước khi code rồi dừng. Controller chấm nó với một danh sách bẫy viết sẵn mà agent không thấy | Bắt được mọi bẫy mức chặn | Bẫy bị sót được đưa vào lệnh tiếp tục; sót ≥ 2 bẫy mức chặn → tăng effort một bậc cho task đó |
| ST-3 | Reviewer có bắt được lỗi không | Hai lần (sau 1.1 và sau 1.4): cài 3 lỗi vào một bản sao diff đã sạch (một lỗi logic, một test không assert gì, một lỗi biên dịch phía app), đưa reviewer như diff thật | 3/3 | Reviewer bậc đó lên `max`, ghi vào ledger |
| ST-4 | Test có đủ chặt không | Mutation probe: 6–10 biến thể lỗi thực tế của code TripKit mới (có lỗi gốc của review), chạy test của task | Không biến thể nào sống, hoặc biến thể sống là tương đương | Mỗi biến thể sống là finding Important "thiếu test" |
| ST-5 | Biên dịch bằng mắt có đúng không | CI `app` sau mỗi lần push | Xanh | Critical của task đó, vào fix loop trước khi giao task kế |

## 7. Khi nào dừng hỏi

Chỉ bốn trường hợp: thao tác không đảo ngược; việc nhạy cảm bảo mật; tác dụng phụ ngoài nhánh mà thông
lệ phải hỏi (merge, PR, publish); plan hỏng tới mức mọi hướng đều là đoán. Còn lại controller ra ruling,
ghi `Ruling: <quyết định> — <vì sao> — <giá phải trả nếu sai>` vào ledger và đi tiếp.

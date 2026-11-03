# JP27 iOS — Vá lỗi đúng/sai, gỡ chokepoint và làm mượt chuyển trang

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đưa app iPhone JP27 tới mức tin được trên đường đi (báo thức, sổ chi, dấu đã ghé, bản đồ offline, nhật ký không sai và không âm thầm hỏng), rồi làm mọi lần mở/thu trang đạt 0 hitch ở 120 Hz.

**Architecture:** Mọi quyết định có thể sai (giữ/đặt báo thức, ack đồng bộ, validate tiền, cửa sổ nhật ký, trạng thái tải từng vùng, ID từng lần ghé, tính khả thi của lịch) được rút thành hàm/kiểu thuần trong `ios/Packages/TripKit` để test trên Linux trong CI; phần app chỉ còn adapter mỏng gọi framework hệ thống (AlarmKit, SwiftData, MultipeerConnectivity, MapLibre, CoreLocation). Phần mượt đi theo một nguyên tắc: **khung đầu của transition là khung cuối** — mọi thứ trang đích cần (ảnh đã ghép, màu, snapshot bản đồ, layout) được chuẩn bị trước hoặc ngoài main thread, không gì được ghi vào state hay animate trong lúc zoom.

**Tech Stack:** Swift 6 / SwiftUI (iOS 26, Liquid Glass), SwiftData, AlarmKit, ActivityKit, CoreLocation, MultipeerConnectivity + CryptoKit, MapLibre Native 7.0.0, MapKit, ImageIO; TripKit (Swift Package, Swift Testing, chạy trên `swift:6.2-noble`); Node 22 cho pipeline dữ liệu (`scripts/*.mjs`); GitHub Actions (`.github/workflows/tripkit.yml`).

**Spec:** `docs/superpowers/specs/2026-11-03-ios-review.md` (review gốc: mục A lỗi, B chokepoint, C độ mượt, D đo). Kế hoạch dẫn chiếu từng mục bằng mã `A1…A8`, `B1…B5`, `C1…C9`, `D`.

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

## Review Focus

1. **Cài bản mới lên máy đã có dữ liệu cũ** (Checkmark/Skip mang `identity` kiểu `stop:x#1`, notification đã gửi chỉ có `day`+`index`, fence lưu trong `UserDefaults["fences"]`, `alarms.scheduled` cũ): người dùng mong mọi dấu nằm đúng lần ghé cũ, notification cũ không đánh dấu nhầm → Task 2.1 có `legacyRecordsMapToStableIDs`, `legacyArrivedPayloadIsIgnored`.
2. **App bị kill giữa `AlarmManager.schedule` và lúc lưu `alarms.scheduled`**: báo thức mồ côi reo mà nút tắt trong app không huỷ được → Task 1.1 có `reconcileCancelsSystemAlarmsTheAppForgot`.
3. **Chạy thử (`clockOffset ≠ 0`)**: đồng hồ lệch không được làm nhật ký ghi ngoài chuyến thật, không đặt báo thức thật, không gửi/ack sổ chi → Task 3.2 có `rehearsalClockDoesNotOpenRealWindow`; Task 1.5 có `pausedSessionNeitherSendsNorAcks`.
4. **Mạng chập chờn trên tàu**: MCSession rớt giữa lúc gửi state và nhận ack; pack offline mất mạng giữa chừng → Task 1.5 có `disconnectForgetsUnackedSend`; Task 3.1 có `waitingRegionIsNotComplete`.
5. **Bật/tắt Nguồn điện thấp hay Reduce Motion khi màn đang mở**: bản đồ tĩnh, bìa trang chủ và animation phải đổi theo ngay → Task 4.3 (`AppModel.lowPower` quan sát `NSProcessInfoPowerStateDidChange`) và Task 5.8 (`Motion.reduced` cho Reduce Motion) có bước kiểm trên máy tương ứng.

---

## Bản đồ thay đổi

### TripKit (logic, test được trên Linux)

| File | Trách nhiệm | Task |
| --- | --- | --- |
| `Sources/TripKit/Ride/WakeAlarms.swift` (mới) | `WakeReconciler` (giữ/đặt/huỷ), `AlarmScheduling` (protocol), `WakeAlarms` (điều phối, thay lõi của `AlarmService`) | 1.1 |
| `Sources/TripKit/Concurrency/Coalescer.swift` (mới) | dồn nhiều yêu cầu thành một lần chạy; `flush()` chạy ngay và chờ xong | 1.2 |
| `Sources/TripKit/Money/Yen.swift` (mới) | `Yen.maxEntry`, `Yen.isValidEntry`, `Yen.total` (không trap) | 1.3 |
| `Sources/TripKit/Money/LedgerCSV.swift` (mới, chuyển từ `SpendWallet.swift`) | đọc/ghi CSV, trả dòng bị loại kèm lý do | 1.3 |
| `Sources/TripKit/Money/LedgerMerge.swift` | `sanitized` dùng `LedgerValidation`, trả cả số dòng bị loại | 1.3 |
| `Sources/TripKit/Money/LedgerSyncSession.swift` (mới) | máy trạng thái gửi/ack/nack mỗi peer | 1.5 |
| `Sources/TripKit/Plan/ItemIdentity.swift` | ID cố định từ dữ liệu; `legacyIdentity` chỉ còn cho migration | 2.1 |
| `Sources/TripKit/Model/Trip.swift` | `PlanRules.grace`/`.tight`; `Stop.id`, `Move.id`, `DayItem.id`, `Trip.idRenames` | 0.1, 2.1 |
| `Sources/TripKit/Plan/Reminders.swift`, `Tracking/Tracking.swift` | `Reminder.itemID`, `Fence.itemID` thay `index` | 2.1 |
| `Sources/TripKit/Offline/OfflineArea.swift` (mới) | pha từng vùng, nhãn build thật của pack, kết quả job | 3.1 |
| `Sources/TripKit/Plan/ItemRef.swift` (mới) | tham chiếu `day` + `id` cho notification/widget | 2.1 |
| `Sources/TripKit/Plan/Itinerary.swift`, `PlanEngine.swift`, `Replanner.swift`, `Ride/RideTracker.swift` | ngưỡng chung; tàu đang đi; ngày không giờ; ETA theo quãng; phà | 0.1, 3.3 |
| `Sources/TripKit/Concurrency/Debouncer.swift` (mới) | trailing debounce cho camera tab Bản đồ | 5.4 |
| `Sources/TripKit/Geo/SnapshotKey.swift` (mới) | key snapshot không chứa trạng thái ghim, gom theo khung | 4.1 |
| `Sources/TripKit/Media/DecodePlan.swift` (mới) | khi nào một bản đã giải mã phục vụ được cỡ xin | 5.1 |
| `Sources/TripKit/Tracking/JournalPolicy.swift` (mới) | cửa sổ ghi nhật ký theo giờ thật của chuyến | 3.2 |

### App

| File | Thay đổi | Task |
| --- | --- | --- |
| `JP27/Services/AlarmService.swift` | thành adapter AlarmKit của `AlarmScheduling` + bọc `WakeAlarms` | 1.1 |
| `JP27/App/AppModel.swift`, `JP27/App/JP27App.swift` | `reschedule() async`, `Coalescer`, background refresh await | 1.2 |
| `JP27/Services/LocationService.swift` | `onMoved` chỉ ở nền; theo dõi nền theo `JournalPolicy` | 1.2, 3.2 |
| `JP27/Data/Records.swift` | `commit()` ném lỗi, `Ledger.apply` rollback; chuyển `identity` sang ID mới một lần (schema không đổi) | 1.4, 2.1 |
| `JP27/Services/LedgerSync.swift` | ack/nack, `send` báo lỗi, trạng thái thật | 1.5 |
| `JP27/Features/Spend/*.swift`, `Journal/JournalView.swift` | validation chung, tổng không trap, lỗi lưu lên UI | 1.3, 1.4 |
| `JP27/Services/NotificationService.swift` | payload `item` thay `index` | 2.1 |
| `JP27/Services/OfflineMaps.swift` | `AreaPhase` từng vùng, `OfflineJob`, `PackTag` mang build thật của pack | 3.1 |
| `JP27/Features/Settings/SettingsView.swift` | công tắc "Ghi nhật ký vị trí", "Xoá lịch sử vị trí" | 3.2 |
| `JP27/Design/TripMap.swift` | `StaticTripMap` cache đồng bộ, JPEG/HEIC, hoãn snapshot, live map không trống | 4.1 |
| `JP27/Services/Media.swift` | `AudioSessionController`; `HeroPipeline` (giải mã một lần, ghép sẵn) | 4.2, 5.1 |
| `JP27/Design/Components.swift`, `Features/Plan/PlaceView.swift`, `DayView.swift`, `StaysView.swift`, `FujiView.swift` | hero ghép sẵn, bỏ blur thật, bỏ animate trong `drawingGroup` | 5.1–5.3 |
| `JP27/Features/Map/MapTab.swift` | highlight tức thì, camera debounce | 5.4 |
| `JP27/Services/RideLiveService.swift`, `MotionService.swift`, `JP27/Features/Talk/TalkListener.swift` | chuyến mồ côi, cờ cũ, giờ thật cho Live Activity, `NetworkStatus` ổn định, Nghe nhả session | 3.3, 3.4, 5.3 |
| `JP27/Features/Fuji/FujiTerrainSnapshot.swift` (mới), `Features/Plan/FujiView.swift` | địa hình từ snapshot, map sống sau zoom | 5.3 |
| `JP27/Design/Motion.swift` (mới) | 5 token chuyển động | 5.8 |
| `JP27/Services/Perf.swift` (mới) | signpost + MetricKit | 0.2 |

### Pipeline dữ liệu

| File | Thay đổi | Task |
| --- | --- | --- |
| `scripts/check-plan.mjs`, `scripts/plan-rules.mjs`, `scripts/check-plan.test.mjs` (mới) | exit ≠ 0 khi bất khả thi, ngưỡng một chỗ, đuôi chặng đi bộ | 0.1 |
| `scripts/export-ios.mjs`, `public/map/*.json` | `rules.grace/tight`; `id` từng item; `metadata` + style bất biến `@<build>` | 0.1, 2.1, 3.1 |
| `.github/workflows/tripkit.yml` | gate khả thi, gate ID, lint `try? save()`, lint chuyển động | 0.1, 2.1, 1.4, 5.8 |
| `scripts/lint-saves.mjs`, `scripts/lint-motion.mjs` (mới) | chặn `try? …save()` và curve rời rạc quay lại | 1.4, 5.8 |
| `src/data/days.ts`, `src/data/id-renames.ts` (mới), `scripts/check-ids.mjs` (mới) | ID cố định cho từng lần ghé, đổi tên phải khai báo | 2.1 |

---

## Thứ tự và phụ thuộc

```
Phase 0  0.1 gate khả thi ── 0.2 đo nền (baseline trước khi sửa)
Phase 1  1.1 báo thức      (độc lập)
         1.2 reschedule ── (1.1 dùng planWake async)
         1.3 tiền ── 1.4 lưu bền ── 1.5 ack đồng bộ
Phase 2  2.1 ID cố định    (sau 0.1: cùng sửa days.ts/export; sau 1.2, 1.4: chạm AppModel, Records)
Phase 3  3.1 offline       (độc lập)
         3.2 nhật ký       (sau 1.2: LocationService)
         3.3 theo dõi trong ngày (sau 0.1: ngưỡng chung; sau 2.1: Reminder/Fence theo id)
         3.4 vòng đời phía app   (fence: sau 2.1)
Phase 4  4.1 StaticTripMap ── 4.2 audio session ── 4.3 dọn reschedule còn lại
Phase 5  5.1 HeroPipeline ── 5.2 DetailHero ── 5.7 nạp trước
         5.3 Fuji map, 5.4 Map tab, 5.5 khung đầu, 5.6 thẻ câu, 5.8 token, 5.9 việc nhỏ
Phase 6  6.1 kiểm trên máy ── 6.2 đo sau, so baseline
```

Phase 1–3 sửa đúng/sai và có thể phát hành riêng (một TestFlight/bản cài) trước Phase 4–5. Không trộn
một task đúng/sai với một task làm mượt trong cùng PR: lỗi hồi quy của bên này không được che bên kia.

---
## Phase 0 — Lưới an toàn và số đo nền

### Task 0.1: Gate tính khả thi của lịch, tách khỏi test parity (A8)

**Vì sao:** `scripts/check-plan.mjs:119` in kết luận nhưng không bao giờ đặt exit code: đổi Nezu Jinja
sang 06:00 thì in "302 min short" mà vẫn `exit=0` (đã chạy lại, xác nhận). CI (`tripkit.yml:21-23`) chỉ
so fixture với output, và `PlanEngineTests.matchesCheckPlanScript` (`PlanEngineTests.swift:10-21`) chỉ so
Swift với JS: lịch hỏng + fixture sinh lại = cả ba xanh (`ios/README.md:36` còn dặn sinh lại fixture mỗi
khi lịch đổi). Ngưỡng là số trơn ở ba nơi: trễ chuyến `clock - 1` (`check-plan.mjs:87`,
`PlanEngine.swift:300`), trễ điểm dừng `clock - 2` (`check-plan.mjs:106`, `PlanEngine.swift:306`), sát giờ
`< 3` (`check-plan.mjs:109`, `PlanEngine.swift:309`), và một bản thứ tư `spare < -1` (`Replanner.swift:33`).
Vì `660 < 662 - 2` sai, Nezu trễ 2 phút rơi xuống nhánh "sát giờ" và in `only -2 min to spare`. Đọc thêm
thấy một lỗi chưa ai nêu: đoạn cuối của một chặng đi bộ có `via` (sau điểm dừng cuối nằm trên nó) **không
bao giờ được cộng** (`check-plan.mjs:116` chỉ có comment; bản Swift cùng lỗ ở `PlanEngine.swift:159`) —
ngày 10 mất ~32 phút trước chuyến Keihan 8:30, ngày 8 mất ~16 phút. README gốc (`README.md:55`) nói
`--fresh` cho check-plan, nhưng script không đọc argv (`--fresh` là của `build-geo.mjs` và các build khác).

**Files:**
- Modify: `scripts/plan-rules.mjs` (thêm `GRACE`, `TIGHT`)
- Modify: `scripts/check-plan.mjs` (export `checkPlan(days)`, main guard, `process.exitCode`, dòng `≈` cho trễ trong dung sai, cộng đuôi chặng đi bộ)
- Create: `scripts/check-plan.test.mjs` (`node --test`)
- Modify: `scripts/export-ios.mjs:228` (`rules: { dwell: DWELL, wait: WAIT, grace: GRACE, tight: TIGHT }`)
- Modify: `ios/Packages/TripKit/Sources/TripKit/Model/Trip.swift:22-28` (`PlanRules.grace`, `.tight`, optional, default `{move: 1, stop: 2}`, `3`)
- Modify: `ios/Packages/TripKit/Sources/TripKit/Plan/PlanEngine.swift:150-165, 281-327` (ngưỡng từ `rules`, `Finding.Kind.grace`, đuôi chặng đi bộ)
- Modify: `ios/Packages/TripKit/Sources/TripKit/Plan/Replanner.swift:30-33` (dùng `rules.grace.stop`)
- Create: `ios/Packages/TripKit/Tests/TripKitTests/PlanFeasibilityTests.swift`
- Modify: `src/data/days.ts:139` (Nezu Jinja 11:00 → 11:05, đã mô phỏng: không đẩy điểm nào sau nó)
- Modify: `.github/workflows/tripkit.yml` (bước gate riêng)
- Modify: `README.md:55`, `ios/README.md:36` (ngưỡng; `--fresh` đúng chỗ; "sinh lại fixture chỉ sau khi gate khả thi đã xanh")
- Regenerate: `ios/Packages/TripKit/Tests/TripKitTests/Fixtures/check-plan.txt`, `ios/JP27/Resources/Trip/trip.json` (qua `npm run ios:data`)

**Interfaces:**
- Produces (JS): `export const GRACE = { move: 1, stop: 2 }`, `export const TIGHT = 3`; `export function checkPlan(days) -> { lines: string[], late: number, withinGrace: number }`; CLI in như cũ + `process.exitCode = late > 0 ? 1 : 0`.
- Produces (Swift): `PlanRules.Grace { move: Int, stop: Int }`, `PlanRules.grace`, `PlanRules.tight`; `PlanEngine.Finding.Kind` thêm `.grace`; dòng in của `.grace`: `  ≈ 11:00 Nezu Jinja: 2 min late, within the 2-min grace`; verdict khi có grace: `every timed stop can be reached (1 within the grace)`.

- [ ] **Step 1: Test Swift độc lập với parity**

```swift
@Suite struct PlanFeasibilityTests {
    let store = Bundle_.store
    var engine: PlanEngine { PlanEngine(store: store) }

    @Test func everyTimedItemCanBeReached() {
        for day in store.trip.days + store.trip.altDays {
            #expect(!engine.check(day).contains { $0.kind == .late }, "Day \(day.key)")
        }
    }
    @Test func noTightFindingIsNegative() {
        for day in store.trip.days + store.trip.altDays {
            for f in engine.check(day) where f.kind == .tight { #expect(f.minutes >= 0, "\(f.line)") }
        }
    }
    @Test func aStopMovedBeforeItCanBeReachedIsLate() throws {
        let store = try TripStore.patched { trip in trip.setStop(day: "2", place: "nezu-shrine", at: "6:00") }
        let late = PlanEngine(store: store).check(store.day("2")!).filter { $0.kind == .late }
        #expect(late.map(\.minutes) == [302])
    }
    @Test func theTailOfAWalkIsCountedBeforeTheNextRide() {
        let day = store.day("10")!
        let keihan = engine.simulate(day).first { day.items[$0.index].move?.at == "8:30" }!
        #expect(keihan.ready >= 8 * 60 + 15)
    }
}
```

`TripStore.patched` (helper mới trong `Support.swift`): đọc `trip.json` thành `[String: Any]`, cho closure sửa, rồi `TripStore(tripJSON:guideJSON:)`; `setStop(day:place:at:)` là extension trên dictionary trong file test. `Finding.minutes` thêm nếu chưa có (đọc `PlanEngine.swift:281-290` trước).

- [ ] **Step 2: Run → FAIL** — `cd ios/Packages/TripKit && swift test --filter PlanFeasibilityTests`: `theTailOfAWalkIsCountedBeforeTheNextRide` fail (ready ≈ 7:45); `noTightFindingIsNegative` fail (Nezu −2).
- [ ] **Step 3: Cộng đuôi chặng đi bộ ở cả hai bản.** Khi gặp một move không phải đi bộ, hay hết ngày, mà `pendingWalk` còn: `clock += min * (km - doneKm) / km`, rồi xoá `pendingWalk`. JS trước, Swift theo đúng cùng công thức.
- [ ] **Step 4: Ngưỡng một chỗ + `.grace`.** `GRACE`/`TIGHT` vào `plan-rules.mjs` và `trip.json` qua export; Swift đọc từ `store.trip.rules`; nhánh `at < clock` nhưng `at >= clock - grace` in dòng `≈`, không bao giờ in "to spare" âm.
- [ ] **Step 5: Chạy JS, đọc output mới, sửa dữ liệu nếu đuôi chặng làm lộ điểm trễ**

Run: `node scripts/check-plan.mjs; echo exit=$?`
Expected trước khi sửa dữ liệu: dòng `≈ 11:00 Nezu Jinja: 2 min late, within the 2-min grace`, và có thể thêm dòng `!` ở ngày 8 hoặc 10 do Step 3. Mỗi dòng `!` được sửa trong `days.ts` (dời giờ hoặc ghi chú đi tàu thay đi bộ), ghi lý do vào commit. Nezu → `11:05`.
Expected sau: `every timed stop can be reached`, `exit=0`.

- [ ] **Step 6: Test JS cho exit code**

```js
// scripts/check-plan.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { checkPlan } from './check-plan.mjs';
import { DAYS } from '../src/data/days.ts';

test('the shipped plan passes and exits 0', () => {
  assert.equal(spawnSync('node', ['scripts/check-plan.mjs']).status, 0);
});
test('a stop moved before it can be reached fails', () => {
  const days = structuredClone(DAYS);
  days.find((d) => d.n === 2).items.find((i) => i.place === 'nezu-shrine').at = '6:00';
  const r = checkPlan(days);
  assert.equal(r.late, 1);
  assert.match(r.lines.join('\n'), /302 min short/);
});
```

Run: `node --test scripts/` → PASS.

- [ ] **Step 7: Gate CI riêng.** Trong job `data` của `tripkit.yml`, *trước* `npm run ios:data`: `- name: Plan is feasible` / `run: node scripts/check-plan.mjs && node --test scripts/`. Bước so fixture giữ nguyên (parity), job `swift` chạy `PlanFeasibilityTests` cùng các test khác.
- [ ] **Step 8: Sinh lại dữ liệu và fixture, chạy cả bộ**

Run: `npm run ios:data && node scripts/check-plan.mjs > ios/Packages/TripKit/Tests/TripKitTests/Fixtures/check-plan.txt && git diff --stat`
Run: `cd ios/Packages/TripKit && swift test` → PASS (`matchesCheckPlanScript` và `PlanFeasibilityTests` cùng xanh).

- [ ] **Step 9: Commit**

```bash
git add scripts src/data/days.ts ios/JP27/Resources/Trip ios/Shared/schedule.json ios/Packages/TripKit README.md ios/README.md .github/workflows/tripkit.yml
git commit -m "Plan check: fail on a plan that cannot be kept, count the tail of a walk, one set of thresholds"
```

---

### Task 0.2: Số đo nền trước khi sửa phần mượt (D)

**Vì sao:** Phase 4–5 chỉ có ý nghĩa khi so được trước/sau trên cùng kịch bản. App chưa có signpost nào
quanh transition, chưa thu MetricKit.

**Files:**
- Create: `ios/JP27/Services/Perf.swift`
- Modify: `ios/JP27/App/AppModel.swift` (`present(_:from:)`, `navigate`), `ios/JP27/Design/Presentation.swift` (điểm bắt đầu/kết thúc zoom), `ios/JP27/Features/Settings/SettingsView.swift` (Chẩn đoán › Số đo)
- Create: `docs/perf/2026-11-baseline.md`

**Interfaces:**
- Produces: `enum Perf { static let signposter: OSSignposter; static func transition(_ name: StaticString) -> TransitionMark }`, `struct TransitionMark { func firstFrame(); func settled() }` (khoảng signpost `transition` với event `first-frame`); `final class MetricsInbox: NSObject, MXMetricManagerSubscriber` (lưu payload JSON vào `Caches/metrics/`, giữ 14 bản gần nhất); `Perf.mark(_ name: StaticString)` (`mxSignpost` để MetricKit gom `MXSignpostMetric`); `extension EnvironmentValues { @Entry var transitionSettled: Bool = true }` — host zoom trong `Presentation.swift` đặt `false` khi bắt đầu và `true` ở callback hoàn tất; trang push (NavigationStack) đặt `true` sau `onAppear` + 350 ms. Task 4.1, 5.3 chờ giá trị này bằng `.task(id: transitionSettled)`.

- [ ] **Step 1:** Viết `Perf.swift`; đặt mốc: chạm (nơi gọi `present`/`NavigationLink` của 10 kịch bản dưới) → `firstFrame()` trong `onAppear` của trang đích → `settled()` khi transition xong (callback hoàn tất của zoom trong `Presentation.swift`; với push dùng `onAppear` + `Task.yield()` hai lần). Đăng ký `MXMetricManager.shared.add(MetricsInbox.shared)` trong `JP27AppDelegate.didFinishLaunching`.
- [ ] **Step 2:** Chẩn đoán › Số đo: bảng `scrollHitchTimeRatio` (từ `MXAnimationMetric`), thời gian mở app, khoảng signpost trung vị theo tên; nút chia sẻ JSON.
- [ ] **Step 3: Đo nền** — bản Release, mở từ màn hình chính, máy sạc đầy, nhiệt độ bình thường. Instruments template **Animation Hitches** + instrument **SwiftUI** (View Body / View Properties) + **os_signpost**. Mỗi kịch bản 5 lần, lấy trung vị:

| Mã | Kịch bản |
| --- | --- |
| S1 | Trang chủ: chạm thẻ ngày giữa carousel → trang ngày zoom mở |
| S2 | Tab Bản đồ: chạm ghim → sheet địa điểm |
| S3 | Lịch trình → trang Fuji |
| S4 | Trang Fuji → thẻ điểm ngắm |
| S5 | Trang địa điểm: vuốt 3 ảnh, dừng |
| S6 | Tab Bản đồ: vuốt nhanh dòng thời gian qua 8 mục |
| S7 | Chi tiêu: chạm "Ghi chi" |
| S8 | Sổ tay: thẻ câu toàn màn hình, xoay ngang/dọc |
| S9 | Trang ngày: chạm dấu tích 5 lần |
| S10 | Mở app nguội, trước chuyến |

Ghi vào `docs/perf/2026-11-baseline.md`: chạm → khung đầu (ms), số hitch, tổng thời gian hitch (ms), số lần body chạy của view trang đích, và ảnh chụp Instruments cho S1–S5.
- [ ] **Step 4: Commit**

```bash
git add ios/JP27/Services/Perf.swift ios/JP27/App/AppModel.swift ios/JP27/Design/Presentation.swift ios/JP27/Features/Settings/SettingsView.swift docs/perf/2026-11-baseline.md
git commit -m "Measure transitions: signposts from tap to settled, MetricKit hitch ratio in Diagnostics, baseline"
```

---

## Phase 1 — Lỗi đúng/sai mức P0

### Task 1.1: Báo thức — tách "giữ" khỏi "đặt", thay thế chỉ khi đã xác nhận (A1)

**Vì sao:** `AlarmService.planWake` (`ios/JP27/Services/AlarmService.swift:91-101`) lọc `wanted` theo
`at > now + 60` rồi huỷ mọi báo thức timetable không có trong danh sách đã lọc: báo thức còn 45 giây bị
huỷ. `place` (`:131-163`) gọi `remove(rideID)` ở dòng 139, *trước* khi kiểm `r.at > now + 30`, quyền và
kết quả `AlarmManager.schedule`: một vị trí GPS báo giờ mới quá sát, hay quyền bị từ chối, hay schedule
throw, đều để người ngủ gật không còn báo thức nào. Thêm một lỗ chưa ai nêu: `scheduled` chỉ lưu ở
`UserDefaults` sau khi `schedule` trả về; app bị kill giữa hai bước thì AlarmKit giữ một báo thức app
không còn biết để huỷ.

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Ride/WakeAlarms.swift`
- Modify: `ios/JP27/Services/AlarmService.swift` (toàn bộ phần điều phối chuyển vào TripKit; giữ `AlightAlarm`, `requestAuthorization`, presentation)
- Modify: `ios/JP27/App/AppModel.swift:401-405` (`planWakeAlarms` trả `async`, xem Task 1.2)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/WakeAlarmsTests.swift`

**Interfaces:**
- Consumes: `OneAtATime<Request>` (`Concurrency/OneAtATime.swift`), `WakePlanner.Wake`.
- Produces:
  - `public enum AlarmSource: String, Codable, Sendable { case timetable, ride }`
  - `public struct AlarmSlot: Codable, Sendable, Hashable { public let id: UUID; public let at: Date; public let source: AlarmSource }`
  - `public struct WakeRequest: Sendable, Hashable { public let rideID: String; public let station: String; public let at: Date; public let source: AlarmSource }`
  - `public enum WakeReconciler` với `static let timetableLead: TimeInterval = 60`, `static let rideLead: TimeInterval = 30`, `static let moveSlack: TimeInterval = 120`,
    `static func keeps(_ slot: AlarmSlot, rideID: String, wanted: Set<String>, isOn: Bool, now: Date) -> Bool`,
    `static func placement(current: AlarmSlot?, request: WakeRequest, now: Date) -> Placement` với `public enum Placement: Equatable, Sendable { case skip, relabel(AlarmSource), replace }`.
  - `@MainActor public protocol AlarmScheduling: AnyObject { var isAuthorized: Bool { get }; func requestAuthorization() async -> Bool; func schedule(id: UUID, request: WakeRequest) async throws; func cancel(id: UUID) throws; func systemAlarmIDs() throws -> Set<UUID> }`
  - `@MainActor public final class WakeAlarms` với `init(scheduler: any AlarmScheduling, saved: [String: AlarmSlot], now: @escaping () -> Date = Date.init, onChange: @escaping ([String: AlarmSlot]) -> Void)`,
    `func planWake(_ wanted: [WakeRequest], isOn: (String) -> Bool) async`,
    `func alight(_ request: WakeRequest) async`, `func cancel(_ rideID: String)`,
    `func reconcile() ` (so `scheduled` với `systemAlarmIDs()`), `var scheduled: [String: AlarmSlot] { get }`.

Quy tắc (viết đúng như vậy trong doc comment của `WakeReconciler`):
- **Giữ** một báo thức timetable đang có khi ride còn trong `wanted` (theo `rideID`, *không* lọc theo giờ) và công tắc của ride đang bật. Báo thức đã qua giờ (`at <= now`) coi như đã reo: bỏ khỏi `scheduled`, không gọi cancel.
- **Đặt mới** chỉ khi `request.at > now + lead` (`timetableLead` cho `.timetable`, `rideLead` cho `.ride`).
- `placement`: không có cái cũ → `.replace` nếu đủ lead, không thì `.skip`; cái cũ là `.ride` mà request `.timetable` → `.skip`; lệch dưới `moveSlack` → `.relabel(.ride)` nếu request là `.ride` khác nguồn, không thì `.skip`; request không đủ lead → `.skip` (**cái cũ giữ nguyên**); còn lại `.replace`.
- **Thay thế:** schedule cái mới (UUID mới) → kiểm `ticket` còn hiện hành → ghi `scheduled[rideID]` và gọi `onChange` (lưu) → *rồi mới* `cancel(old.id)`. Cancel cái cũ lỗi thì id vào `orphans` và được thử lại ở `reconcile()`.
- Quyền bị từ chối, schedule throw, hay hết lead sau khi chờ prompt (gọi lại `placement` sau mỗi `await`) → `return`, cái cũ giữ nguyên.
- `reconcile()`: id trong `systemAlarmIDs()` mà không có trong `scheduled` → cancel; entry trong `scheduled` mà hệ thống không còn → bỏ (đã reo hay bị tắt).

- [ ] **Step 1: Viết test (thất bại vì chưa có kiểu)**

```swift
@Suite @MainActor struct WakeAlarmsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func keepsWantedAlarmDueIn45Seconds() async {
        let s = FakeScheduler()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: s.seed(), at: now + 45, source: .timetable)], now: { now }) { _ in }
        await a.planWake([WakeRequest(rideID: "r1", station: "Odawara", at: now + 45, source: .timetable)], isOn: { _ in true })
        #expect(a.scheduled["r1"] != nil)
        #expect(s.cancelled.isEmpty)
    }

    @Test func doesNotPlaceNewAlarmInsideLead() async {
        let s = FakeScheduler()
        let a = WakeAlarms(scheduler: s, saved: [:], now: { now }) { _ in }
        await a.planWake([WakeRequest(rideID: "r1", station: "X", at: now + 45, source: .timetable)], isOn: { _ in true })
        #expect(s.scheduledRequests.isEmpty)
    }

    @Test func cancelsAlarmNoLongerWantedOrSwitchedOff() async { /* r1 gone from wanted → cancelled; r2 wanted but isOn false → cancelled */ }

    @Test func failedScheduleKeepsOldAlarm() async {
        let s = FakeScheduler(); s.failNext = true
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 900, source: .ride))
        #expect(a.scheduled["r1"]?.id == old)
        #expect(!s.cancelled.contains(old))
    }

    @Test func deniedPermissionKeepsOldAlarm() async { /* s.authorized = false, s.grant = false → old kept */ }
    @Test func replacementTooLateKeepsOldAlarm() async { /* GPS asks now+20 s, old at now+300 → old kept, nothing scheduled */ }

    @Test func oldIsCancelledOnlyAfterNewIsConfirmed() async {
        let s = FakeScheduler()
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .ride))
        #expect(s.log == [.schedule(a.scheduled["r1"]!.id), .cancel(old)])
    }

    @Test func timetableNeverReplacesRide() async { /* ride slot at +600, timetable request at +1200 → unchanged */ }
    @Test func cancelWhileAwaitingPermissionDropsTheNewAlarm() async { /* s.suspendAuthorization; a.cancel("r1") meanwhile; resume → nothing left scheduled, new id cancelled */ }
    @Test func reconcileCancelsSystemAlarmsTheAppForgot() async {
        let s = FakeScheduler()
        let orphan = s.seed()
        let a = WakeAlarms(scheduler: s, saved: [:], now: { now }) { _ in }
        a.reconcile()
        #expect(s.cancelled == [orphan])
    }
    @Test func reconcileForgetsAlarmsTheSystemNoLongerHas() { /* saved r1 with id not in system → scheduled empty, onChange called */ }
}
```

`FakeScheduler` (trong file test): ghi `log: [Call]`, `scheduledRequests`, `cancelled: Set<UUID>`; có `failNext`, `authorized`, `grant`, và `suspendAuthorization` (một `CheckedContinuation` để test giữa lúc chờ prompt); `seed()` thêm một id vào "hệ thống" và trả về nó. Mọi test truyền `now: { now }` (đồng hồ cố định); `WakeAlarms` đọc giờ qua closure này sau *mỗi* `await` (giờ có thể đã trôi trong lúc chờ prompt).

- [ ] **Step 2: Chạy test, phải fail**

Run: `cd ios/Packages/TripKit && swift test --filter WakeAlarmsTests`
Expected: FAIL — `cannot find 'WakeAlarms' in scope`.

- [ ] **Step 3: Viết `WakeReconciler` và `WakeAlarms` trong `Sources/TripKit/Ride/WakeAlarms.swift`**

`WakeAlarms` dùng `OneAtATime<WakeRequest>` y như `AlarmService` hiện nay (cùng `overrides`: một request `.ride` luôn thay được; `.timetable` không thay `.ride` đang chạy/chờ). `planWake` làm hai lượt: huỷ theo `keeps`, rồi `alight` cho từng request `.timetable` không có slot `.ride`. Không `try?` trơn: mọi lỗi của scheduler được ghi vào `lastError: String?` (để Cài đặt › Chẩn đoán hiện) và để nguyên trạng thái cũ.

- [ ] **Step 4: Chạy test, phải pass**

Run: `cd ios/Packages/TripKit && swift test --filter WakeAlarmsTests`
Expected: PASS, 12 test.

- [ ] **Step 5: Thay lõi của `AlarmService` bằng `WakeAlarms`**

`AlarmService` (app) còn: `AlarmKitScheduler: AlarmScheduling` (gói `AlarmManager.shared.schedule(id:configuration:)`, `cancel(id:)`, `authorizationState`, và `systemAlarmIDs()` đọc `try AlarmManager.shared.alarms.map(\.id)` — kiểm tên API trên Xcode 26 trước khi viết); `choices` như cũ; `scheduled` đọc từ `WakeAlarms`, đổi sang lưu `[String: AlarmSlot]` JSON cùng key `alarms.scheduled` (decoder chấp nhận dạng cũ `Saved` thiếu `source` → `.timetable`). `@Observable` vẫn ở `AlarmService`: `onChange` của `WakeAlarms` gán vào một `private(set) var scheduled` để view nào đọc `isSet/time(of:)` được vẽ lại. Gọi `alarms.reconcile()` trong `AppModel.activate()` lần đầu sau khi về từ nền.

- [ ] **Step 6: Kiểm trên máy (không có test app)**

Chạy thử với clock thật trên máy (AlarmKit không chạy simulator): đặt một ride giả ở ngày mai trong bản debug bằng Cài đặt › Chẩn đoán (nếu chưa có công tắc "Báo thức thử sau 2 phút", thêm ở task này: gọi `alarms.alight(WakeRequest(… at: now + 120, source: .ride))`). Mở lại app ở giây 75 → báo thức vẫn reo. Tắt quyền báo thức trong Cài đặt iOS rồi đi tiếp → báo thức cũ vẫn reo.

- [ ] **Step 7: Commit**

```bash
git add ios/Packages/TripKit/Sources/TripKit/Ride/WakeAlarms.swift ios/Packages/TripKit/Tests/TripKitTests/WakeAlarmsTests.swift ios/JP27/Services/AlarmService.swift ios/JP27/App/AppModel.swift
git commit -m "Alarms: keep what is still wanted, replace only once the new one is set"
```

---

### Task 1.2: Reschedule có cấu trúc — background refresh await, dồn lần chạy (A5, B3, B4)

**Vì sao:** `JP27App` (`ios/JP27/App/JP27App.swift:28-31`) `await model.refreshInBackground()`, nhưng
`refreshInBackground` (`AppModel.swift:803-806`) → `refresh(reschedule: true)` → `rescheduleAll()`
(`:388-394`) tạo `Task { await notifications.schedule … }` và `planWakeAlarms()` tạo `Task { await
alarms.planWake … }`: closure return ngay, iOS có thể suspend app trước khi thông báo và báo thức được
đặt. Cùng hàm này chạy đồng bộ trong tap của dấu tích (`toggleDone`, `:447-458`; cả `toggleSkip`,
`apply`, `rideArrived`, `visited`, `notificationAction`) và hai lần liên tiếp khi mở app trước chuyến
(`activate` → `refresh(reschedule: true)`; rồi `requestLocation()` ở `LocationService.swift:116` →
`didUpdateLocations` (`:305-314`) → `moved(to:)` → `onMoved` → `rescheduleAll`).

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Concurrency/Coalescer.swift`
- Modify: `ios/JP27/App/AppModel.swift` (`rescheduleAll`, `refresh`, `toggleDone`, `toggleSkip`, `apply`, `rideArrived`, `visited`, `notificationAction`, `refreshInBackground`, `planWakeAlarms`, `setWakeAlarm`)
- Modify: `ios/JP27/App/JP27App.swift:28-41`
- Modify: `ios/JP27/Services/LocationService.swift:305-314`
- Modify: `ios/JP27/Services/NotificationService.swift` (`schedule` đã `async`; bảo đảm nó chỉ return khi `replace` xong — hiện đúng, giữ nguyên)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/CoalescerTests.swift`

**Interfaces:**
- Produces: `@MainActor public final class Coalescer` với
  `public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, work: @escaping @MainActor () async -> Void)`,
  `public func request(after delay: Duration)` (yêu cầu sau ghi đè hẹn trước nếu hẹn *sớm hơn*; không bao giờ lùi một hẹn đã có),
  `public func flush() async` (huỷ hẹn, chạy ngay; nếu đang chạy thì chờ lần đó xong rồi chạy thêm đúng một lần nếu có yêu cầu mới trong lúc chạy; return khi không còn gì),
  `public private(set) var runs: Int` (cho test và Chẩn đoán).
- Produces (app): `AppModel.reschedule() async` (await `notifications.schedule`, `location.updateFences`, `await alarms.planWake`), `AppModel.requestReschedule(after: Duration = .zero)`.

- [ ] **Step 1: Test `Coalescer` với đồng hồ giả**

```swift
@Suite @MainActor struct CoalescerTests {
    @Test func burstOfRequestsRunsOnce() async {
        let clock = ManualSleep()
        var n = 0
        let c = Coalescer(sleep: clock.sleep) { n += 1 }
        c.request(after: .milliseconds(300)); c.request(after: .milliseconds(300)); c.request(after: .milliseconds(300))
        await clock.advance(.milliseconds(300))
        #expect(n == 1)
    }
    @Test func flushRunsNowAndReturnsWhenDone() async { /* request(after: 10 s); await flush() → n == 1 before any advance */ }
    @Test func requestDuringRunRunsExactlyOnceMore() async { /* work suspends on a continuation; request twice meanwhile; resume → n == 2 */ }
    @Test func flushWaitsForInFlightRun() async { /* run started by timer is suspended; flush() does not return until it resumes */ }
    @Test func earlierRequestPullsTheRunForward() async { /* request(after: 2 s) then request(after: 0) → runs at 0 */ }
}
```

`ManualSleep` (file test): giữ các continuation theo thời điểm, `advance(_:)` resume những cái tới hạn.

- [ ] **Step 2: Run → FAIL** — `swift test --filter CoalescerTests`, lỗi `cannot find 'Coalescer'`.

- [ ] **Step 3: Viết `Coalescer`.** Một `Task` hẹn giờ (`pending`), một `Task` đang chạy (`running`), cờ `again`. `flush()` = huỷ `pending`, `await running?.value`, rồi nếu còn yêu cầu (hoặc chưa chạy lần nào cho lần flush này) thì chạy và await.

- [ ] **Step 4: Run → PASS** — `swift test --filter CoalescerTests`.

- [ ] **Step 5: Nối vào `AppModel`**
  - `private lazy var rescheduler = Coalescer { [weak self] in await self?.reschedule() }`.
  - `func reschedule() async`: tính `reminders` (như `:390`), `await notifications.schedule(reminders, clockOffset:)`, `location.updateFences(model: self)`, rồi `await planWakeAlarms()` (đổi thành `async`, bỏ `Task {}` bên trong).
  - `rescheduleAll()` đổi tên thành `requestReschedule(after:)`; `refresh(reschedule: true)` gọi `requestReschedule(after: .zero)`.
  - `toggleDone`, `toggleSkip`, `apply`: cập nhật `marks/skips`, save, `refresh(reschedule: false)` (cursor và màn đổi ngay), rồi `requestReschedule(after: .milliseconds(300))` — geofence và UserDefaults không còn nằm trên frame có animation dấu tích (B3).
  - `activate()`: `requestReschedule(after: .milliseconds(150))` để lần do `onAuthorizationChange`/`onMoved` sát sau đó gộp vào cùng một lần (B4).
  - Đường bị đánh thức ở nền (`visited`, `fenceEvent`, `onMoved`, `rideArrived` khi `applicationState != .active`): bọc trong `BackgroundWork.run(name:) { await self.rescheduler.flush() }` — helper mới trong `AppModel.swift` gói `UIApplication.beginBackgroundTask(withName:expirationHandler:)`/`endBackgroundTask`.
  - `refreshInBackground()`: `refresh(reschedule: false)`; `await rescheduler.flush()`; `publishSnapshot(force: true)`. Mỗi bước kiểm `Task.isCancelled` trước bước sau (SwiftUI huỷ task khi iOS báo hết giờ).

- [ ] **Step 6: Sửa handler nền trong `JP27App`**

```swift
.backgroundTask(.appRefresh(Self.refreshID)) {
    Self.scheduleRefresh()            // next one first: an expiry below must not lose the chain
    await model.refreshInBackground() // returns only when notifications, fences and alarms are set
}
```

- [ ] **Step 7: `requestLocation()` không còn tính là "đã di chuyển"**

Trong `LocationService.locationManager(_:didUpdateLocations:)`: `publish` và `onUpdate` như cũ; chỉ gọi `moved(to:)` khi `!foreground` (significant change ở nền). Cập nhật doc comment của `onMoved`.

- [ ] **Step 8: Kiểm trên máy**
  - Cài đặt › Chẩn đoán hiện `rescheduler.runs`: mở app trước chuyến (bản Release) → tăng đúng 1.
  - Instruments › Time Profiler, chạm dấu tích 10 lần: không còn `CLLocationManager startMonitoring`/`UserDefaults set` trong khung của tap.
  - Background: `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"tech.delphyra.jp27.refresh"]` trong LLDB khi app ở nền; breakpoint cuối `refreshInBackground` phải chạm *trước* log "task completed" của BGTaskScheduler.

- [ ] **Step 9: Commit**

```bash
git add ios/Packages/TripKit/Sources/TripKit/Concurrency/Coalescer.swift ios/Packages/TripKit/Tests/TripKitTests/CoalescerTests.swift ios/JP27/App/AppModel.swift ios/JP27/App/JP27App.swift ios/JP27/Services/LocationService.swift
git commit -m "Reschedule as one awaited job: background refresh waits for it, taps and launches coalesce"
```

---

### Task 1.3: Tiền — một validation cho mọi đường vào, tổng không bao giờ trap (A3)

**Vì sao:** Bàn phím chặn ở `SpendKeypad.limit = 9_999_999` (`SpendWallet.swift:168`), nhưng import CSV
chỉ kiểm `yen > 0` (`SpendWallet.swift:356`) và dữ liệu từ máy kia chỉ được lọc theo ngày
(`LedgerMerge.sanitized`, `LedgerMerge.swift:172-177`). Một dòng `9223372036854775807` cộng một dòng `1`
cùng nhóm làm `spent[...] += e.yen` (`SpendTab.swift:355`) trap; vì dòng đã lưu, tab crash ở mọi lần mở.
Các chỗ cộng khác cũng trap được: `SpendTab.swift:96`, `:164`, `:378-379`, `:421`; `SpendWallet.swift:13-16`;
`BudgetView.swift:229`; `JournalView.swift:37`; `ShoppingView.swift:61`.

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Money/Yen.swift`
- Create: `ios/Packages/TripKit/Sources/TripKit/Money/LedgerCSV.swift` (chuyển `parse`, `field`, `header`, ánh xạ dòng → `LedgerRecord` từ `SpendWallet.swift:277-408`; ISO8601 parse bằng `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` để chạy trên Linux)
- Modify: `ios/Packages/TripKit/Sources/TripKit/Money/LedgerMerge.swift:165-177`
- Modify: `ios/JP27/Features/Spend/SpendWallet.swift` (`SpendLedgerFile` gọi `LedgerCSV`; `SpendKeypad.limit = Yen.maxEntry`; `SpendWallet` dùng `Yen.total`)
- Modify: `ios/JP27/Features/Spend/SpendTab.swift`, `BudgetView.swift`, `ShoppingView.swift`, `ios/JP27/Features/Journal/JournalView.swift` (mọi tổng qua `Yen.total`)
- Modify: `ios/JP27/Features/Spend/SpendTab.swift` (mục "Khoản cần sửa" cho dòng đã lưu mà không hợp lệ)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/MoneyValidationTests.swift`

**Interfaces:**
- Produces:
  - `public enum Yen { public static let maxEntry = 9_999_999; public static func isValidEntry(_ yen: Int) -> Bool; public static func total<S: Sequence>(_ values: S) -> Int where S.Element == Int }` — `total` cộng bằng `addingReportingOverflow`, bão hoà ở `Int.max`/`Int.min` thay vì trap; `public static func difference(_ a: Int, _ b: Int) -> Int` trừ bão hoà (ví = nạp − chi).
  - `public enum LedgerValidation { public enum Problem: Sendable, Hashable { case amount, futureDate, text } ; public static let maxText = 500; public static func problems(_ r: LedgerRecord, now: Date) -> Set<Problem> }`
  - `LedgerMerge.sanitized(_:now:) -> LedgerState` giữ chữ ký, thêm `public static func screened(_ s: LedgerState, now: Date) -> (state: LedgerState, rejected: [UUID])`; `sanitized` = `screened(...).state`.
  - `public enum LedgerCSV { public static let header: [String]; public static func encode(_ rows: [LedgerRecord], placeName: (String?) -> String?) -> String; public static func decode(_ text: String) -> (records: [LedgerRecord], rejected: [RowProblem]) }`, `public struct RowProblem: Sendable, Hashable { public let line: Int; public let reason: Reason; public enum Reason: Sendable, Hashable { case id, date, amount(String), text } }`.
  - Trong app: `SpendLedgerFile.Outcome` thêm `var skipped = 0`, summary thêm "bỏ qua N dòng không hợp lệ (dòng 4, 9…)".

- [ ] **Step 1: Test**

```swift
@Suite struct MoneyValidationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func totalSaturatesInsteadOfTrapping() {
        #expect(Yen.total([Int.max, 1]) == Int.max)
        #expect(Yen.total([1_200, 800]) == 2_000)
    }

    @Test func csvRowAboveTheKeypadCapIsRejected() {
        let csv = LedgerCSV.header.joined(separator: ",") + "\r\n"
            + "\(UUID()),2027-10-20T03:00:00.000Z,d3,12:00,9223372036854775807,food,,cash,,,,other,\r\n"
            + "\(UUID()),2027-10-20T03:01:00.000Z,d3,12:01,1,food,,cash,,,,other,\r\n"
        let (records, rejected) = LedgerCSV.decode(csv)
        #expect(records.map(\.yen) == [1])
        #expect(rejected == [RowProblem(line: 2, reason: .amount("9223372036854775807"))])
    }

    @Test func capItselfIsAccepted() { #expect(Yen.isValidEntry(9_999_999)); #expect(!Yen.isValidEntry(10_000_000)); #expect(!Yen.isValidEntry(0)) }

    @Test func otherPhonesRowsAreScreenedTheSameWay() {
        let bad = LedgerRecord(id: UUID(), yen: Int.max, category: "food", method: "cash", at: now, origin: "b")
        let ok = LedgerRecord(id: UUID(), yen: 900, category: "food", method: "cash", at: now, origin: "b")
        let (state, rejected) = LedgerMerge.screened(LedgerState(records: [bad, ok]), now: now)
        #expect(state.records.map(\.id) == [ok.id])
        #expect(rejected == [bad.id])
    }

    @Test func overlongNoteIsRejected() { /* note of 501 chars → .text */ }
    @Test func csvRoundTripsWhatItWrites() { /* encode 3 records → decode → same records (ids, yen, dates to the ms) */ }
    @Test func csvKeepsQuotedCommasAndLineBreaks() { /* note "a, \"b\"\nc" survives */ }
}
```

- [ ] **Step 2: Run → FAIL** — `swift test --filter MoneyValidationTests`.
- [ ] **Step 3: Viết `Yen.swift`, `LedgerCSV.swift`, `screened`.** `LedgerValidation.problems`: `amount` khi `!Yen.isValidEntry(yen)`; `futureDate` như luật `clockSlack` hiện có; `text` khi `note`/`placeName` vượt `maxText` ký tự.
- [ ] **Step 4: Run → PASS** — `swift test --filter MoneyValidationTests` và cả `LedgerMergeTests` (không đổi hành vi cũ).
- [ ] **Step 5: Nối vào app**
  - `SpendLedgerFile.merge` gọi `LedgerCSV.decode`, rồi `LedgerMerge.screened`; `Outcome.skipped = rejected.count + screenedOut.count`.
  - `LedgerSync.open(.state)` dùng `screened` (bỏ `sanitized`), ghi số dòng bị loại vào trạng thái sync (Task 1.5 hiện ra).
  - Mọi tổng tiền trong các file đã liệt kê đổi sang `Yen.total(...)`; `SpendWallet` tính `Yen.difference(Yen.total(inflow), Yen.total(outflow))` (thêm `#expect(Yen.difference(Int.min, 1) == Int.min)` vào Step 1).
  - Dòng đã lưu từ trước bản này mà không hợp lệ: không cộng vào tổng nào (`Expense.isCountable = Yen.isValidEntry(yen)`), hiện trong một section "Khoản cần sửa" đầu sổ với nút Sửa/Xoá. Không tự xoá.
- [ ] **Step 6: Kiểm trên máy** — import file CSV trong test Step 1 (lưu vào `docs/superpowers/fixtures/overflow.csv`, commit cùng task) → alert "Đã thêm 1 khoản, bỏ qua 1 dòng không hợp lệ (dòng 2)"; tab Chi tiêu mở được, tổng = ¥1.
- [ ] **Step 7: Commit**

```bash
git add ios/Packages/TripKit/Sources/TripKit/Money ios/Packages/TripKit/Tests/TripKitTests/MoneyValidationTests.swift ios/JP27/Features/Spend ios/JP27/Features/Journal/JournalView.swift ios/JP27/Services/LedgerSync.swift docs/superpowers/fixtures/overflow.csv
git commit -m "Money: one validation for the keypad, CSV and the other phone; totals that cannot trap"
```

---

### Task 1.4: Lưu bền — lỗi ghi tới UI, không còn `try? save()` trên đường của người dùng (A2, phần lưu)

**Vì sao:** `ExpenseEditor.save` (`ExpenseEditor.swift:258-280`) gọi `try? model.context.save()`, rung
`done` và đóng editor dù save lỗi. `Ledger.apply` (`Records.swift:355-385`) `try? context.save()` rồi trả
`c` như đã ghi; `LedgerSync.open(.state)` (`LedgerSync.swift:389-397`) dùng kết quả đó để `stamp`. Cùng
mẫu ở `AppModel.swift:455, 476, 511, 522, 579, 596, 602, 638`, `ShoppingView.swift:167, 235`,
`SpendTab.swift:204`, `Records.swift:383, 412`. Thêm một rủi ro đọc code mà thấy: `Checkmark`/`Skip` có
`#Unique([\.day, \.index])` (`Records.swift:12, 33`), còn `loadRecords` (`AppModel.swift:547-582`) sửa
`index` của nhiều hàng trong một lượt; hai hàng đổi chỗ cho nhau thì save vi phạm unique, bị `try?` nuốt,
và lần mở sau lặp lại y như vậy.

**Files:**
- Modify: `ios/JP27/Data/Records.swift` (helper `commit`, `Ledger.apply` ném lỗi + rollback, `Ledger.delete/keepApart/restore` ném lỗi)
- Modify: `ios/JP27/App/AppModel.swift` (mọi `try? context.save()` → `commit`, `saveIssue`)
- Modify: `ios/JP27/App/JP27App.swift` (`RootView` hiện `saveIssue`)
- Modify: `ios/JP27/Features/Spend/ExpenseEditor.swift`, `SpendTab.swift`, `ShoppingView.swift`, `SpendWallet.swift` (`SpendTopupSheet`)

**Interfaces:**
- Produces (app):
  - `struct SaveIssue: Identifiable, Equatable { let id = UUID(); let what: String; let error: String }`
  - `extension ModelContext { @MainActor func commit() throws(SaveFailure) }` — `save()`; lỗi → `rollback()` rồi ném `SaveFailure(underlying:)`. `rollback` để bộ nhớ khớp đĩa: view không hiện một khoản chưa từng được ghi.
  - `AppModel.var saveIssue: SaveIssue?`; `AppModel.persist(_ what: String) -> Bool` (gọi `commit`, đặt `saveIssue` khi lỗi).
  - `Ledger.apply(_:to:) throws -> LedgerChanges`, `Ledger.merge(_:into:) throws -> (merged:, changes:)`.
  - `AppModel.logExpense(...) -> Expense?` (nil khi lưu lỗi).

- [ ] **Step 1: `commit()` và `SaveIssue`.** Thêm vào `Records.swift`. `RootView` thêm `.alert(item: $model.saveIssue)` với tiêu đề "Chưa lưu được", nội dung `"\(what): \(error)"`, nút "Thử lại" (gọi lại `persist`) và "Để sau".
- [ ] **Step 2: `ExpenseEditor.save`** — `if model.persist("Khoản chi") { saved.toggle(); dismiss() } else { failed.toggle() }`; `.sensoryFeedback(.fail, trigger: failed)`; editor ở lại, giữ nguyên số đã gõ. Cùng mẫu cho `SpendTopupSheet`, `ShoppingView` (mua/bỏ mua), `SpendTab.delete`.
- [ ] **Step 3: Marks/skips** — `toggleDone`, `markDone`, `toggleSkip`, `apply(_ plan:)`: ghi state trong bộ nhớ chỉ sau khi `persist` thành công; lỗi thì `loadRecords()` lại từ đĩa (state về đúng cái đã lưu). `loadRecords` sửa index theo hai pha (đặt mọi hàng cần đổi sang index âm tạm `-1 - i`, `commit`, rồi đặt giá trị thật, `commit`) để không bao giờ vi phạm `#Unique` giữa chừng — chỉ cần tới khi Task 2.1 bỏ hẳn unique theo index.
- [ ] **Step 4: `Ledger.apply` ném lỗi.** `LedgerSync.open(.state)`: `do { try Ledger.merge(...) } catch { session.saveFailed(...) ; send(.nack) ; return }` — chi tiết ở Task 1.5. `SpendLedgerFile.merge` ném tiếp lỗi lên alert sẵn có ở `SpendTab.swift:133-140`.
- [ ] **Step 5: Kiểm trên máy** — trong bản Debug thêm công tắc Chẩn đoán "Giả lỗi lưu" (`Records.failNextSave = true`, `commit()` ném trước khi gọi `save()`): sửa một khoản → alert, editor không đóng, không rung `done`; ghép hai máy → dòng sync không ghi "đã đồng bộ".
- [ ] **Step 6: Gate** — `scripts/lint-saves.mjs`: fail khi một dòng Swift trong `ios/JP27` khớp `try\?\s*\(?\s*[\w.]+\.save\(\)` mà không có comment `// save: best-effort` trên cùng dòng. Chỉ hai chỗ được đánh dấu như vậy: gộp sổ phụ (`Records.swift:248`) và chép sang rehearsal (`Records.swift:280`) — cả hai có đường dự phòng riêng. Thêm `node scripts/lint-saves.mjs` vào job `data` của `tripkit.yml`.
- [ ] **Step 7: Commit**

```bash
git add ios/JP27 scripts/lint-saves.mjs .github/workflows/tripkit.yml
git commit -m "Saves that fail say so: editors stay open, the ledger rolls back, sync is never stamped on a failed write"
```

---

### Task 1.5: Đồng bộ sổ chi có ack — "đã đồng bộ" chỉ khi máy kia đã lưu (A2, phần đồng bộ)

**Vì sao:** `push(to:force:)` (`LedgerSync.swift:446-451`) gán `sent[k] = state` sau `seal`, còn
`SyncLink.send` (`:729-733`) `try? session.send(...)`: một lần gửi lỗi được coi như đã gửi và heartbeat
(`:265-270`, `pushAll` → `push` không `force`) bỏ qua vì `sent[k] == state`. Bên nhận `stamp(p.name)`
(`:394`) trước khi biết `Ledger.merge` có lưu được không. Không có tin nào báo ngược rằng bên nhận đã ghi.

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Money/LedgerSyncSession.swift`
- Modify: `ios/JP27/Services/LedgerSync.swift` (`SyncPayload` thêm `.ack`, `.nack`; `.state` mang digest; `SyncLink.send` trả `Bool`; trạng thái dựa vào `LedgerSyncSession`)
- Modify: `ios/JP27/Features/Spend/LedgerSyncView.swift`, `SpendTab.swift` (`SpendSyncLine`) — dòng trạng thái mới
- Test: `ios/Packages/TripKit/Tests/TripKitTests/LedgerSyncSessionTests.swift`

**Interfaces:**
- Produces:
  - `public struct LedgerDigest: Codable, Sendable, Hashable { public let value: String; public init(_ value: String) }` — app tính bằng `SHA256` của `JSONEncoder` với `.sortedKeys` trên `LedgerState` (đã sắp theo id) — TripKit không biết cách tính, chỉ so sánh.
  - `public struct LedgerSyncSession: Sendable` (một mỗi peer) với
    `public mutating func didSend(_ d: LedgerDigest, at: Date)` (chỉ gọi khi transport nhận),
    `public mutating func peerHas(_ d: LedgerDigest)` (từ `.ack(d)` hoặc khi peer gửi state có digest `d` — peer chỉ gửi state đã lưu),
    `public mutating func peerFailed(_ d: LedgerDigest, reason: String)` (từ `.nack`),
    `public mutating func disconnected()` (quên lần gửi chưa ack),
    `public func needsSend(current: LedgerDigest, now: Date, resendAfter: TimeInterval = 15) -> Bool` (current ≠ cái peer có, và chưa gửi current hoặc gửi đã quá `resendAfter` chưa ack),
    `public func isSynced(current: LedgerDigest) -> Bool`,
    `public private(set) var lastFailure: String?`,
    `public var paused: Bool` (chạy thử: `needsSend` luôn false; `LedgerSync` cũng không trả `.ack` khi paused).
  - `nonisolated enum SyncPayload { case intro(install:), state(LedgerState, digest: String?), ack(digest: String), nack(digest: String, reason: String), touched }` — `digest` optional để giải mã được tin của bản cũ.
  - `LedgerSync.Status` (enum thay `status: String` tính tay): `.off`, `.paused`, `.waiting(name:)`, `.sending(name:)`, `.synced(name:, at:)`, `.unconfirmed(name:)` (peer bản cũ không ack), `.failed(name:, reason:)`; `status` string sinh từ enum.

Luồng (viết vào doc comment của `LedgerSync`):
1. A gửi `.state(S_A, d_A)`; transport nhận → `session.didSend(d_A)`; transport lỗi → không ghi gì, heartbeat gửi lại.
2. B nhận: `screened` → `try Ledger.merge` → lưu được: gửi `.ack(d_A)`; nếu `M ≠ S_A` gửi `.state(M, d_M)`; `session.peerHas(d_A)` (A chắc chắn có S_A). Lưu lỗi: gửi `.nack(d_A, reason)`, không stamp, `Status.failed`.
3. A nhận `.ack(d_A)` → `peerHas(d_A)`; nhận `.state(M, d_M)` → merge (= M), lưu được → `peerHas(d_M)`, gửi `.ack(d_M)`.
4. Stamp "Đã đồng bộ lúc …" (và `lastSync`) chỉ khi `session.isSynced(current: digest(local))` *và* lần lưu gần nhất của máy này thành công.
5. Heartbeat 15 s: `for each peer where session.needsSend(...) → push`. `force` cũ (lúc kết nối, lúc chạm) vẫn gửi ngay.

- [ ] **Step 1: Test**

```swift
@Suite struct LedgerSyncSessionTests {
    let t0 = Date(timeIntervalSince1970: 0)
    let a = LedgerDigest("a"), b = LedgerDigest("b")

    @Test func notSyncedUntilAcked() {
        var s = LedgerSyncSession()
        s.didSend(a, at: t0)
        #expect(!s.isSynced(current: a))
        s.peerHas(a)
        #expect(s.isSynced(current: a))
    }
    @Test func unsentStateIsAlwaysDue() { #expect(LedgerSyncSession().needsSend(current: a, now: t0)) }
    @Test func sentButUnackedIsResentAfter15Seconds() {
        var s = LedgerSyncSession(); s.didSend(a, at: t0)
        #expect(!s.needsSend(current: a, now: t0 + 14))
        #expect(s.needsSend(current: a, now: t0 + 15))
    }
    @Test func ackOfAnOlderStateDoesNotCoverTheCurrentOne() {
        var s = LedgerSyncSession(); s.didSend(a, at: t0); s.peerHas(a)
        #expect(!s.isSynced(current: b)); #expect(s.needsSend(current: b, now: t0))
    }
    @Test func nackKeepsItDueAndSaysWhy() { /* peerFailed(a, "disk full") → needsSend true, lastFailure == "disk full" */ }
    @Test func disconnectForgetsUnackedSend() { /* didSend(a), disconnected() → needsSend(current: a, now: t0+1) true */ }
    @Test func pausedSessionNeitherSendsNorAcks() { var s = LedgerSyncSession(); s.paused = true; #expect(!s.needsSend(current: a, now: t0)) }
}
```

- [ ] **Step 2: Run → FAIL** — `swift test --filter LedgerSyncSessionTests`.
- [ ] **Step 3: Viết `LedgerSyncSession`** (struct thuần, không đồng hồ trong — thời gian truyền vào).
- [ ] **Step 4: Run → PASS.**
- [ ] **Step 5: Nối vào `LedgerSync`**
  - `peers[k]` thêm `var session = LedgerSyncSession()`; bỏ `sent: [Int: LedgerState]`.
  - `SyncLink.send(_:to:) -> Bool`: `do { try session.send(...); return true } catch { logger.error(...); return false }`; `LedgerSync.send/seal` trả `Bool` lên `push`.
  - `push(to:force:)`: `guard force || peers[k].session.needsSend(current: digest, now: Date())`; `if seal(.state(state, digest: d.value), to: k) { peers[k]?.session.didSend(d, at: Date()) }`.
  - `open(.state)`: như luồng ở trên; `cached = nil` chỉ khi merge lưu được.
  - `.disconnected`: `peers.removeValue` đã quên session — đúng ý `disconnected()`.
  - Peer bản cũ (gửi `.state` không `digest`, không bao giờ ack): coi state nhận được là `peerHas(digest(remote))` như bước 3 (nó đã lưu trước khi gửi ở bản cũ? *không chắc* → dùng `.unconfirmed(name:)`: "Đã gửi cho Lan · chờ máy kia cập nhật app để xác nhận"), không bao giờ ghi "Đã đồng bộ" cho peer không ack.
  - `hello` thêm `v: Int?` (2 cho bản này); chỉ để hiện "máy kia cần cập nhật" sớm.
- [ ] **Step 6: Kiểm trên hai máy thật** (MultipeerConnectivity không chạy trên simulator đủ tin): (1) bật "Giả lỗi lưu" trên máy B → máy A hiện "Lan chưa lưu được: …", không có "đã đồng bộ"; tắt giả lỗi → trong ≤ 15 s cả hai hiện "đã đồng bộ". (2) Tắt Wi‑Fi máy A ngay sau khi sửa một khoản, bật lại → khoản sang máy B mà không cần sửa thêm. (3) Đang chạy thử (rehearsal) → không gửi, không ack (`paused`).
- [ ] **Step 7: Commit**

```bash
git add ios/Packages/TripKit/Sources/TripKit/Money/LedgerSyncSession.swift ios/Packages/TripKit/Tests/TripKitTests/LedgerSyncSessionTests.swift ios/JP27/Services/LedgerSync.swift ios/JP27/Features/Spend
git commit -m "Ledger sync: acknowledged after the save, resent until it is; status says what is true"
```

---
## Phase 2 — ID cố định cho từng lần ghé (A6)

### Task 2.1: ID viết trong dữ liệu, dùng chung cho record, geofence, notification, widget

**Vì sao:** Không item nào có ID: `stop(...)` (`src/data/days.ts:78-86`) không có, move chỉ có
`leg.id` = `line.from.to.hash(via, path)` (`days.ts:67-76`) — một khoá hình học, sửa một waypoint là
đổi. App suy ra danh tính theo thứ tự (`ItemIdentity.swift:8-20`): ngày 8 thuê kimono (`days.ts:365`,
09:30) là `stop:wargo-gion`, trả (`days.ts:372`, 14:30) là `stop:wargo-gion#1`. Bỏ mục thuê (chính phương
án thay ở `days.ts:383` làm thế) thì mục trả thành `stop:wargo-gion`, `resolve` (`:25-31`) và
`loadRecords` (`AppModel.swift:552-561`) dời dấu "đã thuê" sang mục trả. Ngày 1 có cùng mẫu
(`resol-akihabara`: gửi hành lý 12:00 `days.ts:103`, nhận phòng 15:00 `:107`). Những khoá theo index khác
sẽ gãy cùng lúc: `Reminder.id` `"dep-\(day)-\(index)"`/`"res-…"` (`Reminders.swift:51, 53`), payload
"Đã tới" `day`+`index` (`NotificationService.swift:205-207, 238-245`), `Fence.index`
(`Tracking.swift:18`, lưu dạng chuỗi ở `LocationService.swift:211`), `Snapshot.index` của widget
(`Shared/Shared.swift:70`, `NextStopTimeline.swift:14, 74`), `uses` chỉ giữ lần ghé đầu mỗi ngày
(`export-ios.mjs:81`).

**Quyết định:** ID **viết trong `days.ts`**, không suy từ giờ hay thứ tự (dời giờ là kiểu sửa hay gặp
nhất — Task 0.1 vừa dời Nezu). Mặc định `s:<place>` cho stop, `m:<from>><to>` cho move (không dùng
`leg.id`, không chứa line). Khi một place hay một cặp from/to lặp trong ngày, hay stop không có place, thì
**bắt buộc** có `key`: `stop('9:30', 'wargo-gion', …, { key: 'rent' })` → `s:wargo-gion:rent`. Schema
SwiftData **không đổi**: cột `identity` có sẵn (`Records.swift:20, 38`) chứa ID mới sau một lượt chuyển
đổi một lần.

**Files:**
- Modify: `src/data/days.ts` (`stop`, `leg`, `walk` nhận `key?`; tính `id`; thêm key cho mọi chỗ lặp)
- Create: `src/data/id-renames.ts` (`export const ID_RENAMES: Record<string, Record<string, string>>`, ban đầu rỗng)
- Create: `scripts/check-ids.mjs`, `scripts/check-ids.test.mjs`
- Modify: `scripts/export-ios.mjs:79-85` (`uses` mọi lần ghé, kèm `id`), `:166-169` (`id` trong `dayOut`), `:338` (`id` trong `slimDay`), thêm `idRenames` vào `trip.json`, kiểm trùng cạnh kiểm sẵn có ở `:393-396`
- Modify: `ios/Packages/TripKit/Sources/TripKit/Model/Trip.swift:352-372` (`Stop.id`, `Move.id`, `DayItem.id`, `Trip.idRenames`)
- Modify: `ios/Packages/TripKit/Sources/TripKit/Plan/ItemIdentity.swift` (viết lại)
- Modify: `ios/Packages/TripKit/Sources/TripKit/Plan/Reminders.swift`, `Tracking/Tracking.swift` (`itemID`)
- Create: `ios/Packages/TripKit/Sources/TripKit/Plan/ItemRef.swift`
- Modify: `ios/JP27/App/AppModel.swift` (`loadRecords` chuyển đổi một lần, `markDone`/`toggleDone`/`toggleSkip` xoá theo `identity`, `fenceEvent`, `notificationAction`, `publishSnapshot`)
- Modify: `ios/JP27/Services/NotificationService.swift`, `LocationService.swift` (fence lưu JSON), `ios/Shared/Shared.swift`, `ios/JP27Widgets/NextStopTimeline.swift`, `NextStopWidget.swift`
- Modify: `.github/workflows/tripkit.yml` (`fetch-depth: 0`, bước `node scripts/check-ids.mjs`)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/ItemIdentityTests.swift` (chuyển các test identity từ `PlanClockTests.swift:150-175` sang, sửa kỳ vọng)

**Interfaces:**
- Produces (JS): `stop(at, place, title, text?, cost?, optional?, opts?: { key?: string })`; `walk/leg(..., opts: LegOpts & { key?: string })`; mỗi item có `id: string`. `scripts/check-ids.mjs`: (1) mọi item có `id`, duy nhất trong ngày; (2) so với `git show origin/main:ios/JP27/Resources/Trip/trip.json`: một `id` biến mất trong khi place của nó vẫn còn trong ngày đó → fail, trừ khi có trong `ID_RENAMES[day][old]`. Base chưa có id (lần đầu) → bỏ qua so sánh.
- Produces (Swift):
  - `Stop.id: String`, `Move.id: String`, `DayItem.id: String`; `Trip.idRenames: [String: [String: String]]` (default rỗng).
  - `Day.identity(of index: Int) -> String?` = `items[index].id`; `Day.index(of id: String) -> Int?`; `Day.resolve(_ index: Int, identity: String?) -> Int?` khớp chính xác theo id (không còn "gần nhất").
  - `Day.legacyIdentity(of:)` (thuật toán cũ, đổi tên, `internal`) và `Day.migrate(legacy: String?, index: Int, renames: [String: String]) -> String?`: identity mới đi qua `renames`; identity cũ (`stop:`/`move:`) → index theo thuật toán cũ trên plan hiện tại → `items[i].id`; nil identity → `items[index].id` nếu index còn.
  - `public struct ItemRef: Codable, Hashable, Sendable { public let day: String; public let id: String }`, `public static func arrived(from info: [AnyHashable: Any]) -> ItemRef?` (cần cả `day` và `item` là String; payload chỉ có `index` → nil).
  - `Reminder.itemID: String?` (thay `index` cho dep/res; bookings giữ `index` riêng là `booking: Int?`); id `dep-<day>-<itemID>`, `res-<day>-<itemID>`.
  - `Fence.itemID: String?` thay `index`; `Fence: Codable`.
  - App: `NotificationService.Action.markArrived(ItemRef)`; `Snapshot.itemID: String` (giữ `index` cho widget bản cũ đọc).

- [ ] **Step 1: Test JS trước**

```js
// scripts/check-ids.test.mjs
test('every item has an id, unique within its day', () => { for (const d of [...DAYS, ...ALT_DAYS]) { const ids = d.items.map((i) => i.id); assert.equal(new Set(ids).size, ids.length, `day ${d.n}`); assert.ok(ids.every(Boolean)); } });
test('day 8 rent and return are two visits', () => {
  const d8 = DAYS.find((d) => d.n === 8);
  assert.deepEqual(d8.items.filter((i) => i.place === 'wargo-gion').map((i) => [i.id, i.at]), [['s:wargo-gion:rent', '9:30'], ['s:wargo-gion:return', '14:30']]);
});
test('an id that disappears while its place stays fails without a rename', () => { /* compare(base, head) with return's id changed → errors.length === 1; with ID_RENAMES entry → 0 */ });
```

Run: `node --test scripts/check-ids.test.mjs` → FAIL (chưa có `id`).

- [ ] **Step 2: Thêm `id` vào helper, chạy `node scripts/check-ids.mjs` để liệt kê mọi chỗ lặp, thêm `key` cho từng chỗ** (ít nhất ngày 1 `bags`/`checkin`, ngày 8 `rent`/`return`; walk lặp from/to trong cùng ngày nếu có). Run: `node --test scripts/check-ids.test.mjs` → PASS.
- [ ] **Step 3: Export.** `id` vào `dayOut` và `slimDay`; `uses` thành mọi lần ghé `{ day, at, id }`; `idRenames`. Run: `npm run ios:data && git diff --stat` — chỉ `trip.json`, `schedule.json` đổi, mỗi item thêm `"id"`.
- [ ] **Step 4: Test Swift**

```swift
@Suite struct ItemIdentityTests {
    let store = Bundle_.store

    @Test func everyItemHasAUniqueID() { for d in store.trip.days + store.trip.altDays { let ids = d.items.map(\.id); #expect(Set(ids).count == ids.count, "Day \(d.key)") } }
    @Test func idsSurviveRemovingAnEarlierVisit() throws {
        let store = try TripStore.patched { $0.removeItem(day: "8", id: "s:wargo-gion:rent") } // removeItem: thêm vào Support.swift cạnh setStop (Task 0.1)
        let d8 = store.day("8")!
        #expect(d8.index(of: "s:wargo-gion:return") != nil)
        #expect(d8.index(of: "s:wargo-gion:rent") == nil)
        #expect(d8.resolve(5, identity: "s:wargo-gion:rent") == nil)
    }
    @Test func idsSurviveRetimingAndEditingAWalk() throws { /* patch Nezu at → 11:20 and a walk's via → ids unchanged */ }
    @Test func legacyRecordsMapToStableIDs() {
        let d8 = store.day("8")!
        let i = d8.index(of: "s:wargo-gion:return")!
        #expect(d8.migrate(legacy: "stop:wargo-gion#1", index: i, renames: [:]) == "s:wargo-gion:return")
        #expect(d8.migrate(legacy: "stop:wargo-gion", index: 0, renames: [:]) == "s:wargo-gion:rent")
    }
    @Test func renamedIDsFollowTheirRecord() { /* renames ["s:x": "s:y"] → migrate(legacy: "s:x") == "s:y" */ }
    @Test func legacyArrivedPayloadIsIgnored() {
        #expect(ItemRef.arrived(from: ["day": "8", "index": 12]) == nil)
        #expect(ItemRef.arrived(from: ["day": "8", "item": "s:wargo-gion:return"]) == ItemRef(day: "8", id: "s:wargo-gion:return"))
    }
    @Test func remindersAreKeyedByItemID() { /* every dep/res reminder id ends with its itemID; none contains a bare index */ }
    @Test func fencesCarryTheItemID() { /* FencePlanner fences for day 8 with cursor 0: food/station fences have itemID == the item's id */ }
}
```

Run: `cd ios/Packages/TripKit && swift test --filter ItemIdentityTests` → FAIL.

- [ ] **Step 5: Model + `ItemIdentity` + `ItemRef` + Reminders + Fence.** Run lại → PASS; cả `swift test` (DecodingTests, LiveTests, PlanClockTests đã chuyển test identity) → PASS.
- [ ] **Step 6: App.**
  - `loadRecords`: nếu `Shared.defaults["records.ids"] != 2`, đổi `identity` của mọi `Checkmark`/`Skip` qua `day.migrate(legacy:index:renames:)` (hàng không map được: giữ nguyên, không hiện, không xoá), `commit()`, đặt cờ. Sau đó resolve chỉ theo id; `index` là cache, sửa theo hai pha như Task 1.4.
  - `toggleDone`/`toggleSkip` xoá theo `identity == id` thay `index == index` (`AppModel.swift:450, 505`).
  - `NotificationService.arrived(at:…, item: ItemRef?)` ghi `info["day"]`, `info["item"]`; `didReceive` dùng `ItemRef.arrived(from:)`; `.markArrived(ref)` → `store.day(ref.day)?.index(of: ref.id)` → `markDone`. Payload cũ (chỉ `index`) → mở trang ngày (`.open(.day(day))`) thay vì đánh dấu.
  - Fence lưu `JSONEncoder` của `[String: Fence]` dưới key mới `fences.v2`; key cũ `fences` bị xoá; `fence(_:)` đọc key mới (vùng cũ còn đăng ký sẽ được `updateFences` thay ngay lần reschedule đầu, và một entry không đọc được thì bỏ qua — đúng hành vi hiện có).
  - `Snapshot` thêm `itemID`; widget dùng `itemID` cho link, giữ `index` cho tới khi widget cũ không còn đọc.
- [ ] **Step 7: CI.** `actions/checkout@v4` với `fetch-depth: 0` ở job `data`; bước `- name: Item ids are stable` / `run: node scripts/check-ids.mjs && node --test scripts/`.
- [ ] **Step 8: Kiểm trên máy** — không dùng chạy thử (store của rehearsal bị xoá khi dừng). Cài bản cũ, đánh dấu tay mục 09:30 (thuê) ở trang ngày 8 — đánh dấu tay không cần đang trong ngày đó — rồi cài bản mới đè lên: dấu vẫn ở mục thuê, mục trả 14:30 chưa đánh dấu. Một notification "Đã tới" gửi từ bản cũ, bấm sau khi cập nhật → chỉ mở trang ngày, không đánh dấu gì.
- [ ] **Step 9: Commit**

```bash
git add src/data scripts ios/JP27/Resources/Trip ios/Shared ios/Packages/TripKit ios/JP27 ios/JP27Widgets .github/workflows/tripkit.yml
git commit -m "Every visit has an id of its own, written in the data: records, fences, reminders and the widget follow it"
```

---

## Phase 3 — Lỗi đúng/sai mức P1

### Task 3.1: Bản đồ offline — "Xong" chỉ khi từng vùng xong, nhãn là phiên bản tile thật (A4)

**Vì sao (đã đọc lại từng dòng):**
- Tạo pack lỗi (`OfflineMaps.swift:253-266`): `problems[id] = …; unwant(id); running.remove(id)` → vùng ra khỏi `pending` (`:133`), `busy` (`:431`) thành false, `report()` (`:569-571`) gọi `finish()` (`:586-590`): `completedUnitCount = totalUnitCount`, subtitle `photos.failed > 0 ? … : "Xong"`, `setTaskCompleted(success: photos.failed == 0)`. Một job chỉ có bản đồ báo "Xong" và thành công. Tệ hơn: `progress[id] = 0` ở `:268` làm lần `refresh` sau (`:214`) gọi `forget(id)`, xoá luôn `problems[id]` (`:319`); vùng không còn được muốn nên lần mở app sau (`:220`) không thử lại.
- `pause` (`:284`) cũng `unwant` → `finish()` → "Xong".
- Bản đồ đọc style trong bundle (`:27-32`, gọi từ `TripMap.swift:91, 136, 189, 984`); pack tải style từ web (`:242` `remoteStyle(dark: false, current:)` → `https://jpy27.delphyra.tech/map/jp27-light[-current].json`, `:108-110`); nhãn lấy từ bundle (`:232` `tilesNow`, `:37-43` `pinned` đọc `sources.omt.tiles[0]` của style trong app, `:244` `Tag(area:, tiles: now)`; pack đời cũ cũng được gán `pinned` ở `:400`). Web lên build B khi app còn A: pack chứa tile B, nhãn A, bản đồ xin tile A → trượt offline, mà `refresh` (`:201`) thấy nhãn khớp nên coi là xong, `needsReload` không bật. Chế độ "current" tệ hơn: nhãn là chữ `"current"` trong khi TileJSON đổi hằng tuần (`src/lib/mapStyle.ts:310-312`). Style xuất ra không có trường phiên bản nào.
- `needsReload` nằm trong bộ nhớ và `stale` rỗng mỗi lần mở, nên `:217` hỏi lại *mỗi lần mở app* (comment `:16`, `:128` nói "một lần").

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Offline/OfflineArea.swift`
- Modify: `ios/JP27/Services/OfflineMaps.swift` (`OfflineMaps`, `Downloads`)
- Modify: `scripts/export-ios.mjs:384-391` (`metadata` trong style; thêm file bất biến `public/map/jp27-light@<build>.json`, `jp27-dark@<build>.json`)
- Modify: `ios/JP27/Features/Settings/SettingsView.swift` (dòng trạng thái từng vùng và của job)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/OfflineAreaTests.swift`; `scripts/export-ios.test.mjs` (metadata khớp template)

**Interfaces:**
- Produces:
  - `public struct TileBuild: Codable, Sendable, Hashable { public let template: String }` và `public enum StyleInfo { public static func build(style: Data) -> TileBuild?; public static func build(tileJSON: Data) -> TileBuild? }` (đọc `sources.omt.tiles[0]`, hoặc `tiles[0]` của TileJSON).
  - `public struct PackTag: Codable, Sendable, Hashable { public var v = 2; public let area: String; public let build: TileBuild; public let styleURL: String }` — ghi vào `pack.context`; tag v1 / không đọc được → `.stale(nil)`.
  - `public enum AreaPhase: Sendable, Hashable { case requested, creating, downloading(completed: UInt64, expected: UInt64), waitingForNetwork, paused, complete(TileBuild), stale(TileBuild?), failed(String) }`.
  - `public enum OfflineArea { public static func phase(state: PackState, completed: UInt64, expected: UInt64, maximum: UInt64, tag: PackTag?, mapBuild: TileBuild, error: String?) -> AreaPhase }` — `complete` khi `state == .complete || (expected > 0 && completed == expected && maximum == expected)`; không bao giờ hạ `.complete` vì một lần báo `completed == 0` ngay sau `resume()`; tag khác `mapBuild` → `.stale`. `PackState` là enum của TripKit gương `MLNOfflinePackState` (`unknown, inactive, active, complete, invalid`).
  - `public struct OfflineJob: Codable, Sendable { public let areas: Set<String>; public let photos: Bool; public func result(phases: [String: AreaPhase], photosFailed: Int, mapBuild: TileBuild) -> JobResult }`, `public struct JobResult: Sendable, Equatable { public let success: Bool; public let done: Int; public let failed: [String]; public let paused: Bool; public var subtitle: String }` — `success` chỉ khi mọi vùng `.complete(mapBuild)` và `photosFailed == 0`; subtitle "Xong" / "Bản đồ 8/10 vùng · 2 lỗi" / "Đã dừng".
- App: `OfflineMaps.phases: [String: AreaPhase]` thay các set `progress/complete/running/checking/problems/stale` (tên cũ thành computed để trang Cài đặt ít phải đổi); `requests` (thay `wanted`) lưu `UserDefaults`, vùng lỗi giữ lý do và được thử lại; `mapBuild` thay `tilesNow` (chế độ current: `currentTilesStyle` ghi `tiles: [resolved]` thay `url`, lưu `map.currentTemplate`); `needsReload` chỉ bật khi `map.reloadAskedFor != mapBuild.template`, và ghi lại khi đã hỏi.

- [ ] **Step 1: Test**

```swift
@Suite struct OfflineAreaTests {
    let build = TileBuild(template: "https://tiles.openfreemap.org/planet/20261025_080012_pt/{z}/{x}/{y}.pbf")

    @Test func aRegionWhosePackCouldNotBeMadeFailsTheJob() {
        let r = OfflineJob(areas: ["tokyo", "kyoto"], photos: false)
            .result(phases: ["tokyo": .complete(build), "kyoto": .failed("Không tạo được vùng tải")], photosFailed: 0, mapBuild: build)
        #expect(!r.success); #expect(r.failed == ["kyoto"]); #expect(r.subtitle != "Xong")
    }
    @Test func mapOnlyJobIsDoneOnlyWhenEveryAreaIsComplete() { /* one .downloading → !success */ }
    @Test func pausedIsNotDone() { /* .paused → r.paused, subtitle "Đã dừng" */ }
    @Test func waitingRegionIsNotComplete() { /* .waitingForNetwork → !success */ }
    @Test func completeNeedsTheMaximumKnown() {
        let p = OfflineArea.phase(state: .active, completed: 10, expected: 10, maximum: .max, tag: PackTag(area: "tokyo", build: build, styleURL: ""), mapBuild: build, error: nil)
        #expect(p == .downloading(completed: 10, expected: 10))
    }
    @Test func packOfAnotherBuildIsStale() { /* tag.build ≠ mapBuild, state .complete → .stale(tag.build) */ }
    @Test func legacyContextIsStale() { /* tag nil → .stale(nil) */ }
    @Test func tilesTemplateIsReadFromTheShippedStyle() throws {
        #expect(StyleInfo.build(style: try Bundle_.data("../public/map/jp27-light.json")) == build)
    }
}
```

- [ ] **Step 2: Run → FAIL** — `swift test --filter OfflineAreaTests`.
- [ ] **Step 3: Viết `OfflineArea.swift`.** Run → PASS.
- [ ] **Step 4: Export.** Thêm `metadata: { "jp27:tiles": template, "jp27:build": "<build>" }` vào hai style và ghi thêm bản bất biến `@<build>`; test JS: mọi style xuất ra có `metadata["jp27:tiles"] === sources.omt.tiles[0]`. Deploy site trước khi phát hành app (ghi vào checklist Task 6.1): app mới tải style `@<build>` mà nó được build cùng.
- [ ] **Step 5: `OfflineMaps.download(_:)` thành `async`:** `.creating` → GET style `remoteStyle(build: mapBuild)` (URL bất biến) → `StyleInfo.build(style:)` (chế độ current: GET thêm TileJSON) → khác `mapBuild` thì `.failed("Bản đồ trên web khác bản trong app — cập nhật app hoặc thử lại sau")` → `addPack` với `PackTag(build: actual)` → lỗi thì `.failed(reason)` và **không** `unwant`. `refresh()`: không bao giờ `forget` một vùng `.failed`; đọc `state` trước `context` (gửi tin cho pack `.invalid` sẽ raise); khoá pack theo `PackTag.area`, không theo `ObjectIdentifier` (`reloadPacks` thay object).
- [ ] **Step 6: `Downloads`.** Mỗi lần bấm tải tạo một `OfflineJob` (lưu, để tải tiếp lần mở sau); `busy` = có vùng của job đang `requested/creating/downloading/waitingForNetwork` hoặc ảnh đang chạy; `finish()` dùng `OfflineJob.result` cho `completedUnitCount`, subtitle và `setTaskCompleted(success:)`.
- [ ] **Step 7: Kiểm trên máy** — (1) chặn `jpy27.delphyra.tech` bằng Network Link Conditioner "100% Loss" rồi tải một vùng: dòng vùng ghi lỗi, job không "Xong", mở lại app vẫn thấy lỗi và nút Thử lại. (2) Bật Chế độ máy bay giữa lúc tải trên tàu (giả lập): "Chờ có mạng", không "Xong". (3) Đổi build trong style của site (staging) khác app: vùng tải mới báo khác bản; vùng đã tải bằng build cũ hiện "Tải từ nguồn cũ" và alert tải lại chỉ hỏi một lần.
- [ ] **Step 8: Commit**

```bash
git add ios/Packages/TripKit/Sources/TripKit/Offline ios/Packages/TripKit/Tests/TripKitTests/OfflineAreaTests.swift ios/JP27/Services/OfflineMaps.swift ios/JP27/Features/Settings/SettingsView.swift scripts/export-ios.mjs scripts/export-ios.test.mjs public/map
git commit -m "Offline maps: done means every area is complete, each pack knows the tile build it holds"
```

---

### Task 3.2: Nhật ký vị trí — chỉ trong chuyến, công tắc riêng, xoá được (A7)

**Vì sao:** Có quyền Always là `startBackgroundWatch()` (`LocationService.swift:63, 68-71, 271`) bật visit
và significant changes vô thời hạn. `AppModel.visited` (`:623-640`) chèn `Visit` dù `today == nil`
(`matchPlan` trả nil nhưng hàng vẫn được ghi ở `:635`). `positionChanged` (`:610-617`) chèn `Trace` theo
`shouldTrace` mà không xét ngày; significant change ở nền cũng tới đây (`LocationService.swift:305-313`
→ `onUpdate`). Màn Nhật ký chỉ truy vấn trong cửa sổ từng ngày (`JournalView.swift:24-25`), nên lịch sử
ngoài chuyến không bao giờ hiện và không có chỗ nào xoá (`SettingsView` không có thao tác nào với
`Visit`/`Trace`). Quyền Always hiện được xin chung một câu "Món nên gọi khi tới quán, ga trên tàu, nhật ký"
(`SettingsView.swift:384`).

**Files:**
- Create: `ios/Packages/TripKit/Sources/TripKit/Tracking/JournalPolicy.swift`
- Modify: `ios/JP27/App/AppModel.swift` (`visited`, `positionChanged`, `activate` dọn một lần)
- Modify: `ios/JP27/Services/LocationService.swift` (`startBackgroundWatch` theo policy; `stopBackgroundWatch()`; gọi lại khi pha chuyến đổi)
- Modify: `ios/JP27/Features/Settings/SettingsView.swift` (công tắc "Ghi nhật ký vị trí", "Xoá lịch sử vị trí", sửa câu giải thích quyền), `ios/JP27/Features/Journal/JournalView.swift` (thẻ bật ghi khi đang tắt)
- Modify: `ios/Shared/Shared.swift` (`Key.journal`)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/JournalPolicyTests.swift`

**Interfaces:**
- Produces: `public struct JournalPolicy: Sendable { public init(days: [Day], margin: TimeInterval = 6 * 3600); public var window: Range<Date>? /* nửa đêm JST ngày đầu − margin ..< nửa đêm JST sau ngày cuối + margin */; public func mayRecord(realNow: Date, tripNow: Date, rehearsing: Bool, enabled: Bool) -> Bool /* chạy thử: xét tripNow, vì record vào store của rehearsal và bị xoá cùng nó; không chạy thử: chỉ realNow */; public func wantsBackgroundWatch(at: Date, journal: Bool, alwaysGranted: Bool) -> Bool /* trong [window.lower − 24 h, window.upper) và Always; visits chỉ khi journal hoặc đang trong ngày chuyến (tự đánh dấu điểm) */ }`.
- App: `Shared.journalEnabled: Bool` (mặc định **tắt**; hỏi một lần ở thẻ Hôm nay ngày đầu chuyến và trong Nhật ký); `AppModel.purgeLocationHistory(outsideTripOnly: Bool) -> Int`.

Ngoài chạy thử, thời gian xét là **đồng hồ thật** (`Date()`), không phải `Shared.now` có `clockOffset`. Trong chạy thử, record đi vào store của rehearsal (bị xoá khi kết thúc) nên được xét theo `tripNow` — để thử nhật ký trước chuyến mà không đụng tới dữ liệu thật.

- [ ] **Step 1: Test**

```swift
@Suite struct JournalPolicyTests {
    let store = Bundle_.store
    var policy: JournalPolicy { JournalPolicy(days: store.trip.days) }

    @Test func windowCoversTheTripDaysInJapanTime() {
        let w = policy.window!
        #expect(w.lowerBound == TripTime.midnight("2027-10-18")! - 6 * 3600)
        #expect(w.upperBound == TripTime.midnight("2027-10-30")! + 6 * 3600)
    }
    @Test func nothingIsRecordedMonthsBefore() { let t = TripTime.midnight("2027-06-01")!; #expect(!policy.mayRecord(realNow: t, tripNow: t, rehearsing: false, enabled: true)) }
    @Test func nothingIsRecordedWhenSwitchedOff() { let t = TripTime.date("2027-10-20", "12:00")!; #expect(!policy.mayRecord(realNow: t, tripNow: t, rehearsing: false, enabled: false)) }
    @Test func backgroundWatchOnlyNearTheTrip() { /* 2027-10-16 → false; 2027-10-17 12:00 → true; 2027-10-31 → false */ }
    @Test func rehearsalClockDoesNotOpenRealWindow() {
        let real = TripTime.midnight("2026-11-03")!, shifted = TripTime.date("2027-10-20", "12:00")!
        #expect(!policy.mayRecord(realNow: real, tripNow: shifted, rehearsing: false, enabled: true))
        #expect(policy.mayRecord(realNow: real, tripNow: shifted, rehearsing: true, enabled: true))
    }
}
```

- [ ] **Step 2: Run → FAIL**; **Step 3:** viết `JournalPolicy`; **Step 4: Run → PASS** (`swift test --filter JournalPolicyTests`).
- [ ] **Step 5: Nối vào app.**
  - `visited`: vẫn dùng visit để đánh dấu điểm dừng hôm nay (`matchPlan`), nhưng chỉ `insert(Visit)` khi `policy.mayRecord(...)`; `walkStart` (học tốc độ đi bộ, `:483-500`) chịu được không có Visit (đã trả nil).
  - `positionChanged`: `Trace` chỉ khi `mayRecord`.
  - `LocationService.startBackgroundWatch()` chỉ khi `policy.wantsBackgroundWatch(...)`; thêm `stopBackgroundWatch()` (`stopMonitoringVisits`, `stopMonitoringSignificantLocationChanges`); `AppModel.refresh` gọi lại mỗi khi `phase` đổi (đã có chỗ gọi `location.follow(self)` ở `:315`).
  - `activate()`: một lần (`journal.purged.v1`), xoá mọi `Visit`/`Trace` ngoài `window`; `commit()`.
  - Cài đặt: section "Nhật ký" với công tắc "Ghi nhật ký vị trí" (chú thích: "Chỉ trong 18–29/10/2027, chỉ trên máy này") và nút phá huỷ "Xoá lịch sử vị trí" (xác nhận, báo số mục đã xoá). Dòng quyền vị trí đổi thành "Nhắc khi tới quán, tới ga" — không còn nói nhật ký.
- [ ] **Step 6: Kiểm trên máy** — trước chuyến, có Always: Cài đặt iOS › Quyền riêng tư › Dịch vụ định vị › JP27 không còn mũi tên "dùng gần đây" sau vài giờ di chuyển; dữ liệu cũ ngoài chuyến bị xoá ở lần mở đầu (Chẩn đoán hiện số hàng `Visit`/`Trace`).
- [ ] **Step 7: Commit**

```bash
git add ios/Packages/TripKit/Sources/TripKit/Tracking/JournalPolicy.swift ios/Packages/TripKit/Tests/TripKitTests/JournalPolicyTests.swift ios/JP27 ios/Shared/Shared.swift
git commit -m "Journal: record only during the trip and only when asked, watch in the background only near it, delete on request"
```

---
### Task 3.3: Theo dõi trong ngày — tàu đang đi không bị báo trễ, ngày không giờ, phà, ETA (lỗi mới từ audit)

Những lỗi dưới đây không có trong review; lượt audit tìm ra bằng đọc code và `trip.json` (đã kiểm lại:
ngày 12 có `0/3` item mang giờ; `r-4-ashiCruise-moto-hakone-port` và `r-7-tobaFerry-toba-marine-terminal`
có `alight.idx = 0`). Mỗi lỗi bắt đầu bằng một test **phải fail** trên code hiện tại; test nào pass ngay thì
phát hiện đó sai, bỏ, ghi lại trong commit.

1. **Tàu đang đi hay đã đi bị báo lỡ (P1).** `Itinerary.cursor` (`Itinerary.swift:96-110`): khi chưa có dấu
   nào, cursor theo đồng hồ (`slots.first { $0.end > now }`); đang ngồi Romancecar 7:37 lúc 8:30 thì cursor
   là chính chuyến đó (leg chỉ được đánh dấu khi tới), `toReach` là quãng đi bộ từ toa tàu về Shinjuku, và
   `firstMiss` (`Replanner.swift:31-35`) trả "trễ ~650 phút … đi chuyến sau". `ceiling` dừng ở move cứng đầu
   tiên nên đứng ở điểm sau chuyến không kéo được cursor qua nó. `publishSnapshot` (`AppModel.swift:699`)
   coi mỗi lần `late` đổi là thay đổi → `reloadTimelines` theo mỗi 0,5 km, đốt ngân sách reload của widget.
2. **Ngày không có giờ "hết" từ 01:15 (P1).** Ngày 12 không item nào có `at`: đồng hồ bắt đầu 0:00
   (`PlanEngine.swift:146, 164` `ready = clock ?? at ?? 0`), mọi slot xong trước ~1:15, cursor = `items.count`
   cả ngày (Hôm nay "Hết lịch", widget rỗng, không fence, Nhật ký đánh dấu bỏ hết), và nhắc buổi sáng
   (`Reminders.swift:38`, `start - 30`) reo **23:30 đêm 28/10** có âm thanh.
3. **ETA và báo thức GPS từ một lần đo tốc độ (P1).** `RideTracker.minutesLeft` (`RideTracker.swift:75`)
   `if let v = speedKmh, v > 15 { return left / v * 60 }`: tàu chậm vào ga ở 16 km/h → ETA ~209 phút thay ~66,
   lệch ≥ 120 s nên `alarms.alight` dời báo thức muộn ~2,4 giờ; điểm sau tàu đứng (dưới 15 km/h, về timetable)
   thì dời lại. Mất GPS đúng lúc chậm (hầm, túi áo) thì báo thức muộn đứng nguyên.
4. **Phà thẳng báo "chuẩn bị xuống" từ lúc lên (P2).** `alightSoon` (`RideTracker.swift:59-60`) đúng ở km 0
   khi `alight.idx = 0`; prompt = 0 nên `at = now`, bị guard 30 s từ chối → báo thức bật cho phà không bao giờ
   được đặt.

**Files:** Modify `ios/Packages/TripKit/Sources/TripKit/Plan/Itinerary.swift`, `PlanEngine.swift`, `Replanner.swift`, `Reminders.swift`, `Ride/RideTracker.swift`; Modify `ios/JP27/App/AppModel.swift` (`project` truyền ride đang theo dõi; `publishSnapshot`), `ios/JP27/Services/RideLiveService.swift:63-74`. Test: `ios/Packages/TripKit/Tests/TripKitTests/LiveTests.swift` (thêm vào các suite sẵn có).

**Interfaces:**
- `Itinerary.project(_:done:now:position:pace:skips:riding: Ride? = nil)` — có `riding` thì bắt đầu từ item sau leg cuối của ride, đồng hồ = ETA của nó.
- `Itinerary.cursor(...)`: một move cứng đã qua giờ, mà vị trí cách ga lên > 1 km hoặc nằm trên tuyến (`RideTracker.status(at:).offTrackKm < 1`), coi như đã đi: ứng viên được vượt `ceiling`. Ngày mà không slot nào có `planned` hay `started` trước `now` thì bỏ qua đồng hồ (cursor 0 tới khi có dấu hoặc vị trí).
- `PlanEngine.simulate`: item cứng ở `o.from` mà vòng `Presence` chứa vị trí → `ready = min(now, planned)`.
- `ReminderPlanner.reminders(for:)`: không nhắc buổi sáng khi slot đầu `planned == nil && !started`.
- `RideTracker`: `public mutating func record(km: Double, at: Date)` giữ lịch sử (km, thời điểm) 5 phút; `minutesLeft(km:speedKmh:)` dùng tốc độ dọc tuyến tính từ lịch sử 2–5 phút gần nhất khi có (`speedKmh` tức thời chỉ khi chưa có lịch sử), và kết quả luôn kẹp trong `[0.6, 1.5] ×` ETA timetable; `minutesToAlightPrompt` với `prevIdx == 0` dùng ngưỡng đuôi `km >= total - max(0.8, 0.15 * total)`, không có thì `minutesLeft - 3`.
- App: `RideLiveService` không bao giờ dời báo thức GPS **muộn hơn** báo thức timetable của ride (`min(at, planned)`); `publishSnapshot` làm tròn `late` theo bước 5 phút trước khi so, so cả `day`, và `setOff` không còn là `now`.

- [ ] **Step 1: Test (mỗi cái phải fail hôm nay)**

```swift
// day 4: item 2 is the 7:37 Romancecar, ride r-4-romancecar-st-shinjuku-odakyu (105 min, 88.7 km)
var romancecar: Ride { store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" }! }

@Test func aTrainBeingRiddenIsNotLate() {
    let day4 = store.day("4")!, track = store.track(of: romancecar)
    let mid = track[track.count / 2]
    #expect(Itinerary(store: store).project(day4, done: [], now: 510, position: mid).replan == nil)
}
@Test func aTakenTrainDoesNotHoldTheCursor() {
    let r = Itinerary(store: store).project(store.day("4")!, done: [1], now: 630, position: store.place("onshi-hakone-park")!.coordinate)
    #expect(r.cursor >= 3); #expect(r.replan?.target != 2)
}
@Test func anUntimedDayIsNotOverAtNight() {
    let day12 = store.day("12")!
    #expect(Itinerary(store: store).cursor(day12, done: [], now: 480) == 0)
    let morning = ReminderPlanner(store: store).reminders(for: day12).first { $0.kind == .morning }
    #expect(morning.map { $0.fire >= TripTime.midnight("2027-10-29")! } ?? true)
}
@Test func aDirectFerryIsNotAlightingAtBoarding() {
    let t = RideTracker(ride: store.trip.rides.first { $0.id == "r-4-ashiCruise-moto-hakone-port" }!, store: store)
    #expect(t.status(km: 0).alightSoon == false)
    #expect(t.status(km: 5.7).alightSoon == true)   // the cruise is 5.9 km
    #expect(t.minutesToAlightPrompt(km: 0)! > 0)
}
@Test func slowingIntoAStationDoesNotPushTheAlarm() {
    let t0 = Date(timeIntervalSince1970: 0)
    var t = RideTracker(ride: romancecar, store: store)
    t.record(km: 28.0, at: t0); t.record(km: 30.9, at: t0 + 120)   // ~87 km/h over two minutes, slowing into Machida
    let timetable = RideTracker(ride: romancecar, store: store).minutesToAlightPrompt(km: 30.9)!
    #expect(t.minutesToAlightPrompt(km: 30.9, speedKmh: 16)! / timetable < 1.5)   // ~3.2 today
}
```

(`status(km:off:)` và `status(at:)` ở `RideTracker.swift:40, 45`; `track(of:)` ở `TripStore.swift:151`. `RideTracker` đang là `struct` bất biến: `record` biến nó thành có trạng thái — `RideLiveService` giữ một bản `var` cho mỗi ride.)

- [ ] **Step 2: Run → FAIL** — `swift test --filter "ReplanTests|RideTests|TrackingTests"`; test nào pass ngay → bỏ phát hiện đó.
- [ ] **Step 3: Sửa theo Interfaces**, từng phát hiện một commit; chạy lại toàn bộ `swift test` sau mỗi cái (đặc biệt `standingAtAStopHoldsTheDayThere`, `waypointsLeaveBeforeTheTrain`, `matchesCheckPlanScript`, `PlanFeasibilityTests` — `ready = min(now, planned)` không được đổi output của check-plan vì check-plan không có `position`).
- [ ] **Step 4: App** — `project` truyền `live.ride`; `RideLiveService` kẹp báo thức; `publishSnapshot` như Interfaces.
- [ ] **Step 5: Commit** (mỗi phát hiện) — ví dụ `git commit -m "Plan: a train being ridden is not a missed train"`.

### Task 3.4: Vòng đời ở phía app — chuyến mồ côi, cờ cũ, fence của ngày mai, đồng hồ của Live Activity, Nghe (lỗi mới từ audit)

Không test được trên Linux; mỗi mục có bước kiểm trên máy.

- [ ] **Live Activity mồ côi / chuyến không bao giờ kết thúc** (`RideLiveService.swift:50, 61, 83-93`; không chỗ nào đọc `Activity<RideAttributes>.activities`): trong `activate()` kết thúc mọi activity có `rideID != live.ride?.id`; tự kết thúc ride sau `plannedArrival + max(30 phút, 0,5 × thời lượng)` hoặc sau 10 phút ở xa tuyến > 3 km (tắt GPS dẫn đường, `CLBackgroundActivitySession`, huỷ báo thức GPS, mở lại `autoStartRide`). Kiểm: kill app giữa chuyến, mở lại → chỉ còn một Live Activity; xuống tàu sớm → 10 phút sau GPS dẫn đường tắt (biểu tượng định vị trên thanh trạng thái đổi).
- [ ] **Cờ `motion.riding` cũ tự khởi động chuyến** (`MotionService.swift:44-51`: `stop()` không reset `walking`/`riding`; `activate` gọi `motion.start()` rồi `refresh()` ngay, `autoStartRide` ở `AppModel.swift:374` đọc giá trị phiên trước): reset cả hai trong `stop()`.
- [ ] **Fence quán của ngày mai mời "Đã tới"** (`AppModel.swift:656`; `FencePlanner` gán index cho quán ngày mai ở `Tracking.swift:67-70`): chỉ đặt `planned` khi `fence.day == today?.key` (sau Task 2.1 là `fence.itemID` + `fence.day == today?.key`); test TripKit tuỳ chọn: fence quán ngày mai có `itemID == nil`.
- [ ] **Giờ tới của Live Activity theo đồng hồ chuyến** (`RideLiveService.swift:66` dùng `model.now` — lệch khi chạy thử, làm tròn phút, đứng yên ở nền — trong khi widget đếm `Text(timerInterval: Date.now ... arrival)` theo giờ thật): `ContentState.arrival` tính từ `Date()`; nhãn trong app giữ đồng hồ chuyến. `RideLiveActivity.swift:191` `Text(arrival, style: .time)` đặt `.environment(\.timeZone, TripTime.zone)`.
- [ ] **Báo thức GPS khi điểm nhắc đã qua** (`RideLiveService.swift:72` xin `now + max(0, prompt)` cả khi prompt < 0,5 phút, mà guard 30 s từ chối): prompt < 1 phút → một notification time-sensitive "Sắp tới …" ngay, một lần mỗi ride (nhớ trong `AlarmService`).
- [ ] **Nghe (`TalkListener`)** — bản tối thiểu ở đây, Task 4.2 sau đó gom phần session vào `AudioSessionController`: quan sát `AVAudioSession.interruptionNotification`, `AVAudioEngineConfigurationChange`, `UIApplication.didEnterBackgroundNotification` → `stop()` (hiện UI vẫn "đang nghe" sau cuộc gọi/Siri/AirPods); bỏ buffer khi `Speaker.shared.speaking != nil` (chế độ `.measurement` ở `TalkListener.swift:166` không khử vọng, app tự chép lời mình đọc); `stop()` trả category về như trước khi nghe — nếu không, `Speaker.say` không bao giờ nhận session và `ended` (`Media.swift:555`) không bao giờ deactivate, nhạc bị duck tới khi tắt app. 
- [ ] **Chạy thử với offset ~0** (`SettingsView.swift:812` `clockOffset = picked.timeIntervalSince(Date())`; trong chuyến picker kẹp về now → offset ≈ −0,3 s, rehearsal bật, khoản chi ghi trong lúc đó mất khi "Về giờ thật"): làm tròn phút, |offset| < 60 s coi là 0; thêm huy hiệu "Đang chạy thử" ngoài Cài đặt (thanh phụ trên tab bar hoặc tiêu đề Chi tiêu).
- [ ] **Việc P3 gom một commit:** widget reload khi `clockOffset`/`alternatives` đổi lúc snapshot nil (`AppModel.swift:114-127`); widget dùng `beginLabel` của snapshot (`NextStopTimeline.swift:76-81`); nút vị trí "Khi dùng app" mở Cài đặt iOS sau lần hỏi Always đầu tiên (`SettingsView.swift:389`, như `TodayTab.swift:641-648` đã làm với cờ `asked`); dòng thông báo khi chưa hỏi ghi "Cho phép" thay "Mở Cài đặt"; `CloudForecast` gộp các lỗi WeatherKit đồng thời thành một lần đếm, lọc giờ theo đồng hồ thật (`CloudForecast.swift:26`); nhãn VoiceOver cho "Trễ 12′" và view compact/minimal của Live Activity; `Fmt.km(0.996)` → "1,0 km", `Fmt.decimal(-0.4, digits: 1)` → "−0,4" (`TripTime.swift:151, 161` — hai cái này có test Linux `formatsEdges`).
- [ ] **Commit** theo nhóm: `"Rides end when they are over and one Live Activity is left"`, `"Motion, fences and the rehearsal clock no longer act on stale state"`, `"Listen stops when the audio is taken and gives the session back"`, `"Small fixes: widget reloads, labels, permission rows, formats"`.

---

## Phase 4 — Chokepoints (B)

> Phase 4–5 không đổi đúng/sai, nên không có test TDD cho phần view; mỗi task có (a) phần logic tách ra
> TripKit được test, (b) bước đo lại đúng kịch bản của Task 0.2 và ghi vào `docs/perf/`. Một task chỉ
> xong khi số đo của kịch bản nó nhắm không tệ hơn baseline ở mọi kịch bản khác.

### Task 4.1: `StaticTripMap` — khung đầu có ảnh, không snapshot trong lúc zoom, live map không trống (B1, B5)

**Vì sao (đã kiểm):** `@State image` khởi đầu nil (`TripMap.swift:816`), cache chỉ đọc trong `.task`
(`:862-867`) nên khung đầu luôn là ô xám dù ảnh đã trong bộ nhớ. Ảnh đĩa là `pngData()` (`:971`) — giải
mã đã ở ngoài main (`:978-981`), nên đây là độ trễ, không phải jank. Lần đầu `.task` chạy snapshotter
ngay lúc appear, `SnapshotStyler.apply` chạy trên main (`:1041-1044`) giữa transition. Chạm (`:856`)
crossfade sang `MLNMapView` chưa nạp style. Badge `.thinMaterial` (`:847`). Key băm `p.kind.rawValue`
gồm `.done` (`:897`, nguồn `model.isDone` ở `:780`) và `tilesNow`, build number (`:904-905`); không có gì
dọn thư mục → mỗi lần đánh dấu thêm một file. Key còn tính FNV từng byte qua mọi toạ độ tuyến (`:889-906`)
hai lần mỗi lượt body (`:862`, `:952`). Và vì `AmbientPageStyle` đặt `colorScheme` theo màu trang
(`Components.swift:700`), request đọc scheme (`TripMap.swift:830`): màu trang tới giữa lúc zoom đổi key và
vẽ snapshot thứ hai. Về Low Power Mode: chỗ đọc ở `TripMap.swift:575` là `MapPacer.allowed`, được hỏi từ
`didRender` nên *có* cập nhật — review sai chỗ này; chỗ đọc trong body thật sự là `TodayHome.swift:99` và
`:117` (bìa trang chủ), sửa ở Task 4.3.

**Files:**
- Modify: `ios/JP27/Design/TripMap.swift` (`StaticTripMap`, `MapSnapshots`, `MapContent.day`, `TripMap.Coordinator`)
- Create: `ios/Packages/TripKit/Sources/TripKit/Geo/SnapshotKey.swift` (fingerprint + key thuần, test được)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/SnapshotKeyTests.swift`

**Interfaces:**
- Produces (TripKit): `public struct SnapshotKey: Hashable, Sendable { public let frameID: String; public let hash: String; public var fileName: String /* "<frameID>-<hash>.jpg" */ }`, `public static func make(frameID: String, route: [Coordinate], pins: [Coordinate], size: Size, scale: Double, dark: Bool, tiles: String) -> SnapshotKey` — **không** có trạng thái đã ghé của ghim; `public static func fingerprint(_ coords: [Coordinate]) -> UInt64` (tính một lần khi dựng `MapContent.day`).
- Produces (app): `MapSnapshots.cached(_ key: SnapshotKey) -> UIImage?` (đọc NSCache đồng bộ), `MapSnapshots.prune(keeping: SnapshotKey)` (xoá file cùng `frameID` khác `hash`), `MapSnapshots.trim(toBytes: 40 << 20)` lúc mở app; `TripMap(onReady: () -> Void)` gọi từ `mapViewDidFinishRenderingMap(_:fullyRendered: true)`; `SnapshotPin` overlay (SwiftUI) vẽ trạng thái đã ghé lên ảnh tại `snapshot.point(for:)` đã lưu cùng ảnh (`<frameID>-<hash>.json`).

- [ ] **Step 1: Test key** — `keyIgnoresVisitedState` (hai bộ ghim giống toạ độ, khác `.done` → cùng key), `keyChangesWithRouteAndScheme`, `fileNameGroupsByFrame` (`prune` chỉ chạm cùng `frameID`). Run: `swift test --filter SnapshotKeyTests` → FAIL → viết → PASS.
- [ ] **Step 2: Khung đầu** — `picture(size:)` dùng `image ?? MapSnapshots.shared.cached(key)`; ảnh đĩa ghi `heicData()` (fallback `jpegData(compressionQuality: 0.85)`), đọc bằng `UIImage.byPreparingForDisplay()` ngoài main.
- [ ] **Step 3: Hoãn snapshot** — không có trong cache thì `.task` chờ `transitionSettled == true` (Task 0.2) hoặc tối đa 400 ms rồi mới `render`; `SnapshotStyler.apply` chuyển ra ngoài main (snapshotter chạy trên queue riêng của nó; chỉ phần đọc `UITraitCollection` ở main). Task 5.7 làm phần lớn cache ấm trước khi tới đây.
- [ ] **Step 4: Scheme của key** là scheme của **canvas** (`tone.canvas(...).scheme`, tính được từ `PhotoCache.knownTone` trước khi trang mở), không phải `@Environment(\.colorScheme)` bị `ambientPage` ghi đè.
- [ ] **Step 5: Live map không trống** — `ZStack { TripMap(onReady:) ; picture }`: ảnh tĩnh ở trên, chỉ gỡ khi `onReady`; kiểm `MapSnapshots.frame` (`:1005`) và `Coordinator.fit` (`:318`) đóng khung giống hệt (đặt cạnh nhau ở Chẩn đoán, chụp màn so).
- [ ] **Step 6: Badge** — `Palette.card.opacity(0.92)` trong `Capsule`, bỏ `.thinMaterial`.
- [ ] **Step 7: Đo S1, S9** (Instruments): khung đầu của trang ngày có bản đồ; đánh dấu 5 lần → `Caches/Snapshots` không tăng số file.
- [ ] **Step 8: Commit** — `git commit -m "Static map: first frame from memory, snapshot after the zoom, live map only once drawn, one file per frame"`

### Task 4.2: Audio session ngoài main, nhả có hẹn (B2)

**Vì sao:** `Speaker.ended` → `setActive(false, options: .notifyOthersOnDeactivation)` trên main
(`Media.swift:560`, qua `Task { @MainActor }` ở `:567/:572`); `setCategory` mỗi lần chạm (`:539`). Thêm:
ngay sau `didFinish`, deactivate hay lỗi `isBusy` mà `try?` giấu đi, nên nhạc của app khác có thể bị
duck mãi — chính lỗi mà comment ở đó nói đang sửa.

**Files:** Modify `ios/JP27/Services/Media.swift` (`Speaker`); Modify `ios/JP27/Features/Talk/TalkListener.swift` nếu nó cũng đụng `AVAudioSession` (đọc trước).

**Interfaces:** `nonisolated enum AudioSessionController { @concurrent static func activate(category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions) async throws; @concurrent static func deactivate() async -> Bool /* một lần thử lại sau 150 ms khi isBusy */ }`; `Speaker.release: Task<Void, Never>?` — `ended` hẹn 500 ms rồi `deactivate`; `say` huỷ hẹn; `setCategory` chỉ khi category/mode/options khác lần trước (nhớ trong `AudioSessionController`).

- [ ] **Step 1:** Viết theo interface. **Step 2:** Time Profiler: đọc 10 câu liên tiếp trong lúc cuộn Sổ tay → không còn `AVAudioSession setActive` trên main thread; mở Nhạc, đọc một câu, dừng → nhạc trở lại âm lượng thường trong ≤ 1 s. **Step 3: Commit** — `git commit -m "Speech: audio session work off the main thread, released after a beat, failures retried"`

### Task 4.3: Low Power Mode quan sát được; dọn reschedule còn sót (B5, B3, B4)

**Files:** Modify `ios/JP27/App/AppModel.swift` (`var lowPower: Bool`, cập nhật từ `NotificationCenter` `.NSProcessInfoPowerStateDidChange` trên main), `ios/JP27/Features/Today/TodayHome.swift:99, 117` (đọc `model.lowPower`), `ios/JP27/Design/TripMap.swift:575` (giữ nguyên — đã đúng, thêm comment vì sao).

- [ ] **Step 1:** Thêm `lowPower`, thay hai chỗ đọc. **Step 2:** Trên máy: bìa trang chủ đang lật, bật Nguồn điện thấp từ Control Center → dừng lật ngay; tắt → lật lại. **Step 3:** Xác nhận B3/B4 đã xong ở Task 1.2 (`rescheduler.runs` = 1 khi mở app; không có công việc CoreLocation trong khung của tap). **Step 4: Commit** — `git commit -m "Low Power Mode followed live on the home cover"`

---

## Phase 5 — Mở/thu mượt (C)

### Task 5.1: `HeroPipeline` — giải mã một lần, ghép sẵn ảnh nét + lớp mờ + gradient (C1)

**Vì sao (đã kiểm):** Ba lần giải mã mỗi ảnh: tone `image(photo, maxPixel: 96)` (`Media.swift:134`), veil
160 (`:175`), ảnh 1800 (`Components.swift:591`); `cached()` (`Media.swift:70-78`) chỉ dùng lại bản giải mã
tới 2× cỡ xin, nên bản 1800 không phục vụ 96/160. Ảnh Commons đóng gói là WebP 800×598, ImageIO không có
giải mã WebP thu nhỏ → mỗi thumbnail là một lần giải mã đủ 800 px; "1800" thực ra trả ảnh 800. Cache khoá
theo cỡ *xin* chứ không theo cỡ *giải mã* (`Media.swift:64-78, 98-100`): thẻ ngày xin 1200
(`TodayHome.swift:451`), trang ngày xin 1800 → cùng một WebP giải mã hai lần trên đường home → ngày. Veil
fade `withAnimation(.easeOut(duration: 0.25))` (`Components.swift:614`, transition `:587`), ảnh fade 0,2 s
ở `Media.swift:473` (`PlacePhoto`, transition `:461`) — cả hai bên trong `.drawingGroup()`
(`Components.swift:606`), nên texture phẳng được vẽ lại mỗi khung của hai lần fade. `tone()` tải ảnh từ
mạng (`network: true`, `Media.swift:94, 113`) cho *mọi* ảnh của album ngay lúc mở (`StaysView.swift:176-184`,
`PlaceView.swift:246-248`, `FujiView.swift:429-431`) và `saveTones()` ghi lại cả file JSON mỗi ảnh
(`Media.swift:136`). `veil()` chạy trên actor với CoreImage CPU (`Media.swift:42, 172-183, 179`), chặn mọi
`image()` xếp sau. State `heroHeight` (`PlaceView.swift:199`, khởi đầu 520; cùng mẫu `DayView.swift:34`)
và `tones` (`PlaceView.swift:244, 249`) ghi giữa transition, dựng lại cả trang dù `knownTone` đã cho cùng
canvas. Canvas dùng `tone(page) ?? first` (`Media.swift:340`) nên mỗi lần vuốt đổi màu cả trang với
`.animation(.easeInOut(duration: 0.45), value: canvas)` (`PlaceView.swift:238`, `Components.swift:701`).

**Files:**
- Modify: `ios/JP27/Services/Media.swift` (`PhotoCache`: mục "full"; `derive`; `ambient`; tone không mạng; lưu tone gộp; veil `@concurrent`)
- Modify: `ios/JP27/Design/Components.swift` (`AmbientPhoto`, `AmbientHero`, `ambientPage`, `detailPage`)
- Modify: `ios/JP27/Features/Plan/PlaceView.swift`, `DayView.swift`, `StaysView.swift`, `FujiView.swift` (bỏ `heroHeight` state, bỏ ghi `tones` trong transition)
- Create: `ios/Packages/TripKit/Sources/TripKit/Media/DecodePlan.swift` (quy tắc cache theo cỡ giải mã, thuần)
- Test: `ios/Packages/TripKit/Tests/TripKitTests/DecodePlanTests.swift`

**Interfaces:**
- Produces (TripKit): `public enum DecodePlan { public static func serves(decoded: Size, sourceIsFull: Bool, asked maxPixel: Int) -> Bool }` — bản đã giải mã đủ (nguồn nhỏ hơn cỡ xin) phục vụ mọi cỡ xin ≥ nó; bản thu nhỏ phục vụ cỡ xin tới 2× như hiện nay.
- Produces (app):
  - `PhotoCache.derive(_ full: CGImage) -> Derived` (`@concurrent nonisolated static`): `veil` = vẽ full vào `CGContext` 160 px rồi blur; `tone` = `AmbientTone.sample(full)` (vốn đã crop và vẽ vào 12×6). File tone mới `Photos/tones-2.json`, ghi gộp một lần mỗi lượt (debounce 1 s).
  - `PhotoCache.ambient(_ photo: Photo, size: CGSize, scheme: ColorScheme) async -> UIImage?` — ghép veil (aspect-fill), ảnh nét (aspect-fill), mask gradient của `Components.swift:593-599` thành **một** `UIImage` ở bề rộng nguồn (800 px), khoá `"<src>@amb@<w>x<h>@<scheme>"`, NSCache + đĩa (`Caches/Ambient/`).
  - `AmbientPhoto` thành một `Image(uiImage:)`, không mask, không `drawingGroup`; ảnh tới lần đầu (không có trong cache) dùng `.transition(.opacity)` với `Motion.arrive` *bên ngoài* mọi `drawingGroup`; có trong cache thì không animate.
  - Tone chỉ cho ảnh đầu khi mở trang (`network: false` nếu ảnh chưa có sẵn — khi đó giữ màu giấy, không tải); ảnh khác tính khi cú vuốt dừng (`onScrollPhaseChange(.idle)`), không mạng.
  - Màu trang: **giữ theo ảnh đầu** suốt trang (khuyến nghị); phương án thay cần duyệt thiết kế: đổi khi cú vuốt dừng, chỉ nền đổi, `Motion.arrive`. Bỏ `.animation(... value: canvas)` toàn trang ở cả hai chỗ.
  - `detailPage(heroFraction: CGFloat)` thay `heroHeight`: ngưỡng tính trong `onScrollGeometryChange` từ `geo.containerSize.height * fraction`; xoá `settle()`, `DetailScroll`, `.onChange(of: heroHeight)`.

- [ ] **Step 1: Test `DecodePlan`** — `fullDecodeServesLargerAsks` (decoded 800, sourceIsFull, asked 1800 → true), `downsampledServesUpToTwice` (decoded 600, asked 1200 → true, asked 1300 → false), `smallerAskIsServed` (decoded 800, asked 96 → true). Run → FAIL → viết → PASS.
- [ ] **Step 2: `derive` + tone-2.** Kiểm một lần bằng tay: tone từ `derive` của 20 ảnh đóng gói lệch ≤ 0,02 (mỗi kênh) so với đường 96 px cũ — viết script nhỏ trong Chẩn đoán (bản Debug) in độ lệch lớn nhất.
- [ ] **Step 3: `ambient` + `AmbientPhoto` một ảnh.** Giữ đường Reduce Transparency (`plain`) như cũ.
- [ ] **Step 4: Bỏ `heroHeight` state, bỏ ghi `tones` trong transition, bỏ animate canvas.**
- [ ] **Step 5: Đo S1–S5**: SwiftUI instrument → số lần body của `PlaceView`/`PlanDayContent` trong lúc zoom ≤ 2; Animation Hitches → 0 hitch trong zoom; S5 → 0 khung rớt khi cú vuốt dừng. Chụp màn trước/sau một trang địa điểm, một trang ngày, một khách sạn, một điểm ngắm, sáng và tối: đặt cạnh nhau trong `docs/perf/` để duyệt thiết kế (sự khác duy nhất được chấp nhận: màu trang không đổi theo ảnh khi vuốt).
- [ ] **Step 6: Commit** — `git commit -m "Album pages: one decode per photo, one pre-composed hero, nothing animates inside the flattened layer"`

### Task 5.2: `DetailHero` không còn blur thật (C2)

**Vì sao:** `HeroBlur` (`Components.swift:443-447`) là `.fill(.ultraThinMaterial).mask { LinearGradient }`
dưới chân mọi `DetailHero` (`:431`; dùng ở `PlaceView.swift:104`, `AtPlaceView.swift:41`,
`FujiView.swift:94`); ở trang Fuji nó nằm trên `Map` sống (`FujiView.swift:97`) bay 1,2 s khi đổi vùng
(`:122`). `ios/README.md` (§ Mượt ở 120 Hz, dòng cuối) ghi rõ đây là chỗ **cố ý chưa đổi** vì đổi cách
nhìn — task này cần duyệt thiết kế trước khi merge.

**Files:** Modify `ios/JP27/Design/Components.swift` (`HeroBlur(backdrop: UIImage?)`), các chỗ dùng; Modify `ios/README.md` (bỏ dòng "Chưa đổi").

- [ ] **Step 1:** `HeroBlur(backdrop:)`: có `backdrop` (veil của ảnh từ Task 5.1, hoặc snapshot đã blur của bản đồ Fuji từ Task 5.3) → vẽ aspect-fill dưới gradient sẵn có (`:448`); không có → chỉ gradient, độ đục 0,55.
- [ ] **Step 2:** Simulator › Debug › Color Offscreen-Rendered: chân hero không còn vàng trong lúc zoom và cuộn; Metal System Trace trên máy trong S3: thời gian GPU mỗi khung giảm so baseline.
- [ ] **Step 3:** Chụp màn trước/sau cho duyệt thiết kế. **Step 4: Commit** — `git commit -m "Detail hero foot from the pre-blurred photo, not a live material"`

### Task 5.3: Bản đồ Fuji 3D — ảnh cache trước, map sống sau zoom, mạng chập chờn không dựng lại (C3)

**Vì sao:** `.mapStyle(.hybrid(elevation: .realistic…))` ở `FujiMap.swift:240`, dùng làm hero trang Fuji
(`FujiView.swift:97`) và thẻ điểm ngắm (`:546`, `FujiSightMap`, hero ở `:364`), cả hai
`.allowsHitTesting(false)` (`:105`, `:553`), rẽ nhánh theo `model.network.online` (`:96`, `:545`).
`NetworkStatus` (`MotionService.swift:86-88`) ghi mỗi lần path đổi, không debounce → mỗi lần lật là huỷ/dựng
lại map 3D. `FujiSpotPage` còn dựng thêm một map 3D sống dưới màn (`FujiView.swift:393-399`) trong stack
không lazy, ngay lúc thẻ zoom.

**Files:** Create `ios/JP27/Features/Fuji/FujiTerrainSnapshot.swift`; Modify `ios/JP27/Features/Plan/FujiView.swift`, `ios/JP27/Features/Fuji/FujiMap.swift`, `ios/JP27/Services/MotionService.swift` (`NetworkStatus`).

**Interfaces:** `struct FujiTerrainSnapshot: View { init(camera: FujiCamera, size: CGSize) }` — `MKMapSnapshotter` với `options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)`, `options.camera` từ `FujiCamera.area`/`.spot`; cache `Caches/Fuji/<area|spot>-<w>x<h>@<scale>-<scheme>.heic`. `NetworkStatus.online` chỉ đổi sau 2 s ổn định và chỉ khi khác giá trị cũ (`stableOnline`); `NetworkStatus.raw` giữ giá trị tức thời cho ai cần.

- [ ] **Step 1 (spike, 1–2 giờ, trên máy):** snapshot có giữ địa hình 3D và pitch không. Có → ảnh là hero, map sống chỉ khi người dùng chạm. Không (ra phẳng) → hero là ảnh cache, map sống gắn sau `transitionSettled == true`, nằm dưới ảnh, ảnh gỡ khi map báo đã vẽ xong. Ghi kết quả spike vào `docs/perf/`.
- [ ] **Step 2:** Viết `FujiTerrainSnapshot` theo kết quả; đổi vùng (`:122`) với map sống thì giữ animation camera, với ảnh thì crossfade ảnh của vùng mới (`Motion.arrive`).
- [ ] **Step 3:** `stableOnline` cho hai nhánh online/offline; đã từng hiện map sống thì giữ tới khi rời trang.
- [ ] **Step 4:** Map thứ hai ở `FujiSpotPage` (`:393-399`) dùng cùng `FujiTerrainSnapshot`, trong `LazyVStack` (Task 5.5).
- [ ] **Step 5: Đo S3, S4** — 0 hitch trong zoom; Network Link Conditioner bật/tắt mạng 10 lần trong 20 s khi trang Fuji đang mở → map không dựng lại (Instruments › Allocations: không thêm `MKMapView`).
- [ ] **Step 6: Commit** — `git commit -m "Fuji: terrain from a cached snapshot, the live map after the zoom, a flaky network no longer rebuilds it"`

### Task 5.4: Tab Bản đồ — highlight tức thì, camera bay một lần khi đường đọc đứng yên (C4)

**Vì sao:** `MapTab.swift:186` `withAnimation(.smooth(duration: 0.25)) { active = i; side = nil }`, `:190`
`fly(...)`, `:840-843` dải điểm `withAnimation(.smooth) { proxy.scrollTo(...) }` — mỗi mục qua đường đọc.
Mỗi lần còn chạy lại cả body của `MapTab` → `TripMap.updateUIView` → `apply` (`TripMap.swift:141`), và khởi
động lại animation camera của MapLibre (`:305-330`).

**Files:** Create `ios/Packages/TripKit/Sources/TripKit/Concurrency/Debouncer.swift`; Modify `ios/JP27/Features/Map/MapTab.swift` (`MapTimeline.reading`, `read()`), `ios/JP27/Design/TripMap.swift` (chỉ `apply` khi đầu vào bản đồ thật sự đổi). Test: `ios/Packages/TripKit/Tests/TripKitTests/DebouncerTests.swift`.

**Interfaces:** `@MainActor public final class Debouncer<Value: Sendable & Equatable> { public init(delay: Duration, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, fire: @escaping @MainActor (Value) -> Void); public func send(_ v: Value) /* mỗi lần gửi đặt lại hẹn */; public func cancel() }` (khác `Coalescer`: trailing debounce). `MapTimeline` báo `onRead(Int?, scrolling: Bool)` (`scrolling` = `frames.touching` hoặc phase khác `.idle`).

- [ ] **Step 1: Test** `crossingsWithin150msFlyOnce` (gửi 1,2,3,…,8 cách nhau 40 ms, rồi dừng → `fire` đúng một lần với 8), `restAfterEachCrossingFliesEachTime` (cách nhau 200 ms → 3 lần), `cancelDropsPendingFly`. Run → FAIL → viết `Debouncer` → PASS.
- [ ] **Step 2:** `read()`: `active` đổi ngay, không animation khi `scrolling` (có animation `Motion.pick` khi chạm chọn một mục); camera qua `Debouncer(delay: .milliseconds(150))`; dải điểm cuộn không animation khi `scrolling`, chỉ khi mục đích thật sự đổi.
- [ ] **Step 3:** `TripMap.updateUIView` so đầu vào (route, pins, selection) với lần trước, giống thì bỏ qua `apply`.
- [ ] **Step 4: Đo S6** — vuốt nhanh 8 mục: số lần `fly` = 1 (đếm bằng signpost `Perf.mark("map.fly")`), 0 hitch trên dòng thời gian.
- [ ] **Step 5: Commit** — `git commit -m "Map tab: the timeline highlights at once, the camera flies once the reading line rests"`

### Task 5.5: Khung đầu là khung cuối — editor tính sẵn, trang dài lazy (C5)

**Vì sao:** `ExpenseEditor.swift:79` `.onAppear(perform: setUp)` ghi 6 state (mới) / 8 (sửa) ở `:218-239`;
`onAppear` thường chạy trước commit đầu nên không chắc thấy nhảy, nhưng tốn một lượt body thứ hai, và vì
`ready` đã true, `onChange(of: place)` (`:80-87`) bắn thêm một `withAnimation(.snappy)` thừa. Stack không
lazy cho cả trang: `PlaceView.swift:48`, `:196/:203`; `RideView.swift:31`; `FujiSpotPage`
(`FujiView.swift:361/:376`, và `:18-26`). `PlanRideContent` đọc `model.live.ride`, `model.live.status`
trong body (`RideView.swift:27, 40`) → cả trang tàu vẽ lại theo mỗi điểm GPS.

**Files:** Modify `ios/JP27/Features/Spend/ExpenseEditor.swift`, `ios/JP27/Features/Plan/PlaceView.swift`, `RideView.swift`, `FujiView.swift`.

**Interfaces:** `struct ExpenseDraft: Equatable { var value: Int; var category: SpendCategory; var method: PayMethod; var dayKey: String?; var place: String?; var placeName: String; var note: String }`, `static func ExpenseDraft.make(placeID: String?, yen: Int?, editing: Expense?, model: AppModel) -> ExpenseDraft` (logic của `setUp` + `nearestPlanned`); `ExpenseEditor.init(placeID:yen:editing:model: AppModel = .shared)` đặt `_draft = State(initialValue:)`; bỏ `ready`. `PlanStationStrip` (view con) là chỗ duy nhất đọc `model.live`.

- [ ] **Step 1:** `ExpenseDraft` + init; `onChange(of: place)` chỉ chạy khi người dùng chọn (so với giá trị khởi đầu).
- [ ] **Step 2:** Hero giữ trong `VStack`, phần dưới thành `LazyVStack` (như `DayView.swift:37`, `StaysView.swift:126`); kiểm `ViewThatFits` con không nhảy khi đo muộn (cuộn chậm qua từng section ở cỡ chữ lớn nhất của Dynamic Type).
- [ ] **Step 3:** `PlanStationStrip`.
- [ ] **Step 4: Đo S7, S2** — body count của `ExpenseEditor` lúc mở = 1; chạm → khung đầu của trang địa điểm dài nhất (đếm section) giảm so baseline.
- [ ] **Step 5: Commit** — `git commit -m "First frame is the last: the expense editor starts filled in, long pages lay out lazily"`

### Task 5.6: Thẻ câu toàn màn hình — chỉ animate phép xoay (C6)

**Vì sao (đúng một phần):** `TalkShared.swift:66` đổi khung, `:69-70` chữ 160 pt với
`.minimumScaleFactor(0.08)`, `:91-94` padding/frame, `:95` `.animation(.smooth(duration: 0.35), value:
sideways)`. SwiftUI nội suy hình học đã resolve chứ không fit lại chữ mỗi khung — nên vấn đề thật là chữ
nhảy sang ngắt dòng và cỡ cuối ngay khung 1 trong khi khung và phép xoay còn đang nội suy.

**Files:** Modify `ios/JP27/Features/Talk/TalkShared.swift`.

**Interfaces:** `TalkShowLayout(box: CGSize)` — hai bản dựng sẵn (dọc, ngang), đổi bằng `.id(sideways)` với một `Transition` tự viết chỉ áp `rotationEffect` + `opacity`; cỡ chữ mỗi hướng tính một lần bằng `UIFont` + `NSString.boundingRect` (tìm nhị phân trong `[12, 160]`), nhớ theo (câu, hướng, Dynamic Type).

- [ ] **Step 1:** Viết theo interface. **Step 2:** SwiftUI instrument trong S8: không có cập nhật layout của `Text` nào trong lúc xoay ngoài khung đầu và cuối; nhìn bằng mắt: chữ không nhảy ngắt dòng giữa chừng. **Step 3: Commit** — `git commit -m "Phrase card turns sideways by rotation alone, each orientation laid out once"`

### Task 5.7: Nạp trước trang đích (C7)

**Files:** Modify `ios/JP27/Services/Media.swift` (`enum Prefetch`), `ios/JP27/Design/Theme.swift:186, 244-249` (`PressableStyle.onPress`, truyền qua `PressableButton` tới `SettleStyle`), `ios/JP27/Features/Today/TodayHome.swift:113-119, 420, 433`.

**Interfaces:** `enum Prefetch { @MainActor static func day(_ key: String, model: AppModel, priority: TaskPriority); static func place(_ id: String, model: AppModel, priority: TaskPriority); static func cancelAll() }` — `day`: `HomePicks.photo(for:)` (`TodayHome.swift:988`) → `PhotoCache.ambient(...)` (Task 5.1) + tone → `MapSnapshots.shared.image(for: Request(content: .day(day, model:), insets: 28, size: (screenWidth − 2·Metrics.gutter, 240), scale:, dark: <scheme của canvas>))` (bản đồ ở `DayView.swift:149-151`). Giữ tối đa 3 lần nạp đang chạy; lần mới huỷ lần cũ nhất.

- [ ] **Step 1:** `HomeDays` (`TodayHome.swift:433`): `.onScrollPhaseChange { if new == .idle, let key = focus { Prefetch.day(key, model:, priority: .utility) } }` — theo `idle`, không theo mỗi lần `focus` đổi, để một cú fling không nạp từng thẻ.
- [ ] **Step 2:** `PressableStyle.onPress` (gọi khi `configuration.isPressed` thành true); dùng ở thẻ ngày (`:420`, `priority: .userInitiated`) và ảnh bìa (`:113-119`, `.place`).
- [ ] **Step 3:** Low Power Mode (`model.lowPower`) → chỉ nạp khi chạm, không nạp khi thẻ nằm giữa.
- [ ] **Step 4: Đo S1** — chạm → khung đầu < 50 ms; trang ngày mở ra đã có ảnh, màu, bản đồ ở khung đầu (quay màn 240 fps nếu cần nhìn từng khung).
- [ ] **Step 5: Commit** — `git commit -m "Prefetch the day page when its card rests in the middle or is touched"`

### Task 5.8: Ngôn ngữ chuyển động — 5 token, lint trong CI (C8)

**Vì sao:** 82 chỗ gọi, ~29 curve: `.snappy` 24 chỗ, `.smooth` mặc định 15, `.smooth` với 13 thời lượng
khác nhau (0.2–1.4), `.easeOut` 0.2/0.25, `.easeInOut` 0.45/10, bốn spring khác nhau
(`Theme.swift:248`, `MapTab.swift:90, 628, 729`), `.bouncy` (`TodayTab.swift:452`), keyframes
(`TodayHome.swift:272`), crossfade UIView (`Theme.swift:66`). `Theme.swift` chưa có token nào; mẫu gần nhất
là `Metrics` và bộ `SensoryFeedback` theo ý nghĩa (`Components.swift:10, 26`). Thêm: `.transition(.blurReplace)`
(`TodayHome.swift:181, 388, 771`) là filter blur; `:181` là chú thích bìa, đổi mỗi lần bìa lật.

**Files:** Create `ios/JP27/Design/Motion.swift`; Modify mọi file trong bảng của báo cáo (danh sách đầy đủ: `grep -rnE "\.(snappy|smooth|easeOut|easeInOut|bouncy|spring|interpolatingSpring)\b|withAnimation \{" ios/JP27`); Create `scripts/lint-motion.mjs`; Modify `.github/workflows/tripkit.yml`; Modify `ios/README.md` (mục "Chuyển động" cạnh "Rung").

**Interfaces:**

```swift
/// Named by what the motion is for, like `SensoryFeedback`: one curve per kind of moment.
nonisolated enum Motion {
    /// the finger is on it: a press, a key, a drag let go
    static let press: Animation = .spring(duration: 0.3, bounce: 0.28)
    /// one of a few chosen: chips, checks, a category, a highlight, the amount on the keypad
    static let pick: Animation = .snappy(duration: 0.25)
    /// something that was not there arrives: a photo, a snapshot, a title — never on a cache hit, never inside drawingGroup
    static let arrive: Animation = .easeOut(duration: 0.2)
    /// a panel, a strip or a card comes to rest
    static let settle: Animation = .spring(duration: 0.38, bounce: 0.14)
    static func settle(velocity: Double) -> Animation { .interpolatingSpring(duration: 0.38, bounce: 0.14, initialVelocity: velocity) }
    /// a long move the eye follows: a camera flight, the cover turning, the dial drawing
    static let travel: Animation = .smooth(duration: 1.0)
    /// the same under Reduce Motion: springs become a short ease, travel becomes none
    static func reduced(_ a: Animation, _ reduce: Bool) -> Animation?
}
```

- [ ] **Step 1:** `Motion.swift`; ánh xạ: `.snappy*`, `.smooth(0.2…0.3)`, `.bouncy` → `pick`; `SettleStyle`, `SpendKeyStyle` → `press`; ảnh/veil/snapshot/tiêu đề → `arrive`; panel, `scrollTo`, dải, thẻ xoay → `settle`; camera, bìa, vào trang, vẽ biểu đồ → `travel`. Giữ một ngoại lệ có comment: trôi chậm 10 s của bìa (`TodayHome.swift:213`).
- [ ] **Step 2:** `.blurReplace` → `.opacity` ở ba chỗ.
- [ ] **Step 3: `scripts/lint-motion.mjs`** — fail khi thấy `.snappy(`, `.smooth(`, `.easeOut(`, `.easeInOut(`, `.bouncy`, `.spring(`, `.interpolatingSpring(` ngoài `Design/Motion.swift` và các dòng có `// motion: one-off` ; thêm bước vào job `data` của `tripkit.yml`.
- [ ] **Step 4:** Reduce Motion bật: đi qua S1–S8, không còn spring nảy, camera không bay (nhảy thẳng).
- [ ] **Step 5: Commit** — `git commit -m "Five motion tokens named by what moves, checked in CI"`

### Task 5.9: Việc nhỏ (C9)

- [ ] **ActivityKit ngoài animation:** `TodayTab.swift:452` và `RideView.swift:171` — `withAnimation(Motion.pick) { model.live.select(ride) }` (đặt `ride`/`tracker` đồng bộ, đủ cho morph `glassEffectID("ride")`), còn `Activity.request` + `ActivityAuthorizationInfo().areActivitiesEnabled` + `location.startLive` (`RideLiveService.swift:21, 49-50`) vào `Task { @MainActor in await Task.yield(); model.live.begin() }`. Đo bằng Time Profiler: tap → khung đầu của nút "Theo dõi chuyến".
- [ ] **Dòng dịch trên ảnh menu:** `MenuScanView.swift:278` `.thinMaterial` → `Palette.card.opacity(0.9)` (mẫu ở `TodayHome.swift:493-494`). Bỏ dòng "Chưa đổi…" tương ứng trong `ios/README.md`.
- [ ] **Bàn phím số vs bàn phím hệ thống:** `ExpenseEditor.swift:62` `.animation(.snappy, value: writing)` → `padShown` lái bởi `keyboardWillShowNotification`/`WillHide`, dùng đúng `UIKeyboardAnimationDurationUserInfoKey` với `.spring(duration: d, bounce: 0)`; `SpendWallet.swift:229` → `Motion.pick`.
- [ ] **Haptic chuẩn bị trước:** `Components.swift:64-66`, `LedgerSync.swift:493` tạo generator mỗi lần, không `prepare()`. `enum Haptic { static let light, rigid, medium: UIImpactFeedbackGenerator; static let notify: UINotificationFeedbackGenerator; static func prepare(_ kind:) }`; gọi `prepare` từ `SettleStyle` khi nhấn xuống, `SettlePick` lúc `.tracking` (`Components.swift:90-93`), `MapTimeline` khi `frames.touching` thành true (`MapTab.swift:978`).
- [ ] **Commit** — `git commit -m "Small things: Live Activity outside the animation, solid menu labels, keypad on the keyboard's curve, prepared haptics"`

---
## Phase 6 — Kiểm trên máy, đo lại, phát hành

### Task 6.1: Checklist đúng/sai trên máy thật (sau Phase 1–3)

Hai iPhone (một có UWB), bản Release cài đè lên bản đang có dữ liệu (đúng Review Focus 1). Mỗi dòng ghi
đạt/không và ảnh chụp vào `docs/perf/2026-11-device-check.md`.

- [ ] Báo thức: mở app ở giây 45 trước giờ reo → vẫn reo (A1); ride đang theo dõi, GPS báo giờ mới quá sát → báo thức cũ vẫn reo; tắt quyền báo thức → báo thức cũ vẫn reo; kill app ngay sau khi bật báo thức cho một ride rồi mở lại → Chẩn đoán không còn báo thức mồ côi (Review Focus 2).
- [ ] Nền: khoá máy 2 giờ trước chuyến (rehearsal tắt) → `BGTaskScheduler` chạy một lần (Chẩn đoán ghi giờ lần chạy cuối, số thông báo pending, số báo thức) và mọi thứ đã đặt trước khi task báo xong (A5).
- [ ] Sổ chi: giả lỗi lưu ở máy B → máy A không "đã đồng bộ"; tắt Wi‑Fi giữa lúc gửi → gửi lại khi có (A2); CSV tràn số → bỏ qua đúng dòng, tab mở được (A3).
- [ ] ID: cài đè lên bản cũ có dấu ở ngày 8 → dấu nằm đúng; notification "Đã tới" cũ → chỉ mở trang ngày (A6, Review Focus 1).
- [ ] Offline: tải với máy chủ bị chặn, mất mạng giữa chừng, tạm dừng → không "Xong" (A4, Review Focus 4); deploy site trước, rồi cài app, tải một vùng, bật Chế độ máy bay → bản đồ vùng đó có đủ tile.
- [ ] Nhật ký: Always + công tắc tắt → không có `Visit`/`Trace` mới; bật trong chuyến (rehearsal) → có, và mất khi dừng chạy thử (A7, Review Focus 3).
- [ ] Lịch: `node scripts/check-plan.mjs` exit 0 trên `main`; một PR thử dời Nezu về 06:00 → CI đỏ ở bước "Plan is feasible" (A8).
- [ ] Theo dõi (chạy thử ngày 4 và ngày 12): ngồi trên Romancecar giữa đường → không có "Trễ … đi chuyến sau"; ngày 12 lúc 8:00 → Hôm nay hiện điểm đầu, không "Hết lịch", không có nhắc 23:30 đêm trước; thuyền hồ Ashi → không "Chuẩn bị xuống" lúc lên (Task 3.3).
- [ ] Vòng đời (Task 3.4): kill app giữa chuyến → mở lại còn một Live Activity; Nghe rồi gọi điện → UI dừng nghe; sau Nghe, đọc một câu khi đang phát nhạc → nhạc trở lại âm lượng thường.

### Task 6.2: Đo lại và theo dõi sau phát hành (sau Phase 4–5)

- [ ] Chạy lại đúng 10 kịch bản của Task 0.2, cùng máy, cùng điều kiện; ghi `docs/perf/2026-11-after.md` cạnh baseline. Đạt khi: S1, S2, S4 chạm → khung đầu < 50 ms; S1–S4 0 hitch trong zoom; S5 0 khung rớt khi cú vuốt dừng; S6 một lần `map.fly`; S9 không có công việc CoreLocation/UserDefaults trong khung tap; không kịch bản nào tệ hơn baseline.
- [ ] MetricKit: một tuần dùng thường ngày trên hai máy; `scrollHitchTimeRatio` trung vị so với tuần trước khi cài (Chẩn đoán › Số đo › Chia sẻ). Mục tiêu: < 5 ms/s.
- [ ] Phát hành theo thứ tự: deploy site (`public/map/jp27-*@<build>.json` từ Task 3.1) → cài app trên cả hai máy cùng ngày (Task 1.5: bản cũ không ack, sẽ hiện "chờ máy kia cập nhật").

---

## Rủi ro và cách giữ

| Rủi ro | Ở đâu | Giữ bằng |
| --- | --- | --- |
| Tên/hình dạng API AlarmKit (`AlarmManager.shared.alarms`) khác giả định | Task 1.1 Step 5 | kiểm trên Xcode 26 trước khi viết adapter; nếu không có danh sách hệ thống, `reconcile()` chỉ dọn phía app và ghi rõ giới hạn trong doc comment |
| Chuyển đổi identity cũ gán nhầm khi plan đã đổi giữa hai bản | Task 2.1 Step 6 | migration chạy một lần, hàng không map được giữ nguyên (không hiện, không xoá); dữ liệu thật trước chuyến gần như chỉ có dấu tay khi thử |
| Hai máy khác bản trong lúc cập nhật | Task 1.5 | payload mới optional; bản cũ bỏ qua `.ack`; trạng thái `.unconfirmed` thay vì nói dối |
| Snapshot MapKit không ra 3D | Task 5.3 Step 1 | spike trước; phương án dự phòng đã viết sẵn |
| Hero ghép sẵn tốn bộ nhớ (≈ 3,4 MB mỗi ảnh 800 px) | Task 5.1 | NSCache giới hạn theo `totalCostLimit` hiện có (128 MB); trang album chỉ ghép ảnh đầu khi mở, ảnh khác khi vuốt tới |
| Đổi cách nhìn (blur thật → blur dựng sẵn; màu trang không đổi theo ảnh) | Task 5.1, 5.2 | chụp màn trước/sau, duyệt thiết kế trước khi merge; `ios/README.md` ghi lại quyết định |
| Gate mới làm CI đỏ trên PR không liên quan | Task 0.1, 2.1, 1.4, 5.8 | gate chỉ đọc dữ liệu đang có; chạy cả bốn trên `main` trước khi bật bắt buộc |
| Đuôi chặng đi bộ (Task 0.1) làm lộ điểm trễ mới | Task 0.1 Step 5 | sửa dữ liệu trong cùng PR, ghi lý do từng dòng |

## Ngoài phạm vi

- Nâng MapLibre khỏi 7.0.0; đổi nguồn tile.
- Test target cho app trên macOS CI (cân nhắc sau: một job `macos-15` chạy `xcodebuild test` cho adapter AlarmKit/SwiftData).
- Đổi giao diện ngoài những chỗ task nêu.

## Truy vết spec → task

| Spec | Task |
| --- | --- |
| A1 báo thức | 1.1 |
| A2 lưu bền, ack | 1.4, 1.5 |
| A3 tiền | 1.3 |
| A4 offline | 3.1 |
| A5 background refresh | 1.2 |
| A6 ID lần ghé | 2.1 |
| A7 nhật ký | 3.2 |
| A8 gate lịch | 0.1 |
| B1 StaticTripMap | 4.1 |
| B2 audio session | 4.2 |
| B3 tap → reschedule | 1.2 (Step 5), 4.3 |
| B4 requestLocation → onMoved | 1.2 (Step 7), 4.3 |
| B5 Low Power Mode, key snapshot | 4.3, 4.1 |
| C1–C9 | 5.1–5.9 (C1 → 5.1, C2 → 5.2, …, C9 → 5.9) |
| D đo | 0.2, 6.2 |
| Thêm từ audit | 0.1 (đuôi chặng đi bộ, README `--fresh`), 1.1 (báo thức mồ côi), 1.4 (`#Unique` theo index), 3.1 (pause báo "Xong", `needsReload` hỏi mỗi lần mở), 4.1 (scheme đổi giữa zoom, key băm trên main), 4.2 (`isBusy` bị nuốt), 5.1 (cache theo cỡ xin, tone tải mạng lúc zoom, veil trên actor), 5.3 (map 3D thứ hai), 5.5 (trang tàu vẽ lại theo GPS), 5.8 (`blurReplace`), 3.3 (tàu đang đi bị báo trễ, ngày 12 không giờ, ETA một lần đo, phà), 3.4 (Live Activity mồ côi, cờ chuyển động cũ, fence ngày mai, giờ Live Activity, Nghe giữ session, offset chạy thử ~0, P3) |

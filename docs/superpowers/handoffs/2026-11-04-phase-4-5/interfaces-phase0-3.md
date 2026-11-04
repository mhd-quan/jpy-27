# Interfaces as landed (controller-maintained; beats the plan where they differ)

Base for Phase 1–3: 5782638. Nothing landed yet.

## T0 (eaf8a23)
- TripKit `swift-tools-version: 6.3` at T0; **6.2 since R-157** (the owner's Mac has Swift 6.2.x); both targets `swiftSettings: concurrency` = [NonisolatedNonsendingByDefault, InferIsolatedConformances]; no default isolation.
- `Tests/TripKitTests/ConcurrencyRulesTests.swift` pins: nonisolated async runs on caller's actor.
- CI `.github/workflows/tripkit.yml`: jobs `data` (Node 22), `swift` (swift:6.2.3-noble since R-157), `app` ("App builds", macos-26, Xcode 26.2 since R-157, xcodegen, simulator build unsigned, warnings summary, log artifact). `permissions: contents: read`; `workflow_dispatch`.
- JS tests command: `node --test 'scripts/*.test.mjs'` (R-19).

## 0.1 (e801b14..5fa4654)
- JS: `scripts/plan-rules.mjs` exports `GRACE = { move: 1, stop: 2 }`, `TIGHT = 3`. `scripts/check-plan.mjs` exports `checkPlan(days) -> { lines, late, withinGrace, ready }` and `main(days = [...DAYS, ...ALT_DAYS])` (prints, sets process.exitCode); import has no side effects.
- trip.json/schedule.json `rules` gain `grace: {move: 1, stop: 2}`, `tight: 3`.
- Swift: `PlanRules.Grace { move, stop }` (Hashable), `PlanRules.grace: Grace`, `PlanRules.tight: Int` — non-optional, decodeIfPresent defaults 1/2/3. `PlanEngine.Finding.Kind.grace`; line `  ≈ HH:MM Name: N min late, within the 2-min grace` (non-errand stops only). Verdict suffix ` (N within the grace)`.
- Walk tail counted before the next non-walk move (clamped ≥ 0) in `run` and in live projections (`resumedWalk` resumes unless the walk's end was passed).
- Replanner `firstMiss`: hard move grace.move, hard stop grace.stop.
- Test helpers (Tests/TripKitTests/Support.swift): `TripStore.patched { trip in … }`, `setStop(day:place:at:)`, `setMove(...)`, `editItem(...)` on the JSON dictionary.
- Data: Nezu Jinja (day 2) 11:05.
- CI `data` job: step "Plan is feasible" = `node scripts/check-plan.mjs && node --test 'scripts/*.test.mjs'` before ios:data.

## 1.1 (1e3c188..6b8b4f6) — TripKit `Ride/WakeAlarms.swift`
- `AlarmSource: String, Codable {timetable, ride}`; `AlarmSlot {id: UUID, at: Date, source}` (tolerant decode: missing source = .timetable); `WakeRequest {rideID, station, at, source}`.
- `WakeReconciler` constants `timetableLead 60`, `rideLead 30`, `moveSlack 120`; `keeps(_:rideID:wanted:isOn:now:)` (.ride ignores wanted/isOn; past `at <= now` not kept); `placement(current:request:now:) -> Placement`.
- `SystemAlarmState {scheduled, countdown, paused, alerting, unknown}`.
- `@MainActor protocol AlarmScheduling: AnyObject` — `isAuthorized`, `requestAuthorization() async throws -> Bool`, `schedule(id:request:) async throws`, `cancel(id:) throws`, `systemAlarms() throws -> [UUID: SystemAlarmState]`.
- `@MainActor final class WakeAlarms(scheduler:saved:[String: AlarmSlot]? (nil = unreadable), now:, rehearsing: () -> Bool = {false}, onChange:)` — `scheduled` (didSet → onChange), `lastError`, `planWake(_:isOn:) async`, `alight(_:) async`, `requestAuthorization() async -> Bool`, `cancel(_ rideID)`, `reconcile()` (no-op unless authorized; cancels unknown ids only when `.scheduled`; never cancels unknown strays when saved was nil).
- App: `AlarmService` (AlarmKit adapter `AlarmKitScheduler`), `planWake(_:) async`, `alight(rideID:station:at:source:) async`, `reconcile()`, `lastError` (store problem first), Debug `systemAlarmsSummary()`.
- `AppModel.planWakeAlarms() async` (private), call sites still `Task { await planWakeAlarms() }` at AppModel.swift:396 and :420 — R-06: Task 1.2 removes these wrappers. `alarms.reconcile()` in `activate()` right after `asleep = false` (:229) — must stay first in activate.
- GPS path: RideLiveService.swift:74 `Task { await model.alarms.alight(...) }` (not on a path iOS waits for).

## 1.2 (a06e44e..2dbcf95) — TripKit `Concurrency/Coalescer.swift`
- `@MainActor public final class Coalescer(sleep: @escaping @Sendable (Duration) async throws -> Void = Task.sleep, work: @escaping @MainActor () async -> Void)`; `request(after:)` (delay dominance, never postpones, first timer to fire runs and cancels the rest), `flush() async` (counts as a request; waits for an in-flight run then runs; returns when nothing is left; must not be awaited from inside `work`), `runs` (begun), `isIdle`.
- App `AppModel`: `@ObservationIgnored private lazy var rescheduler`; `private func reschedule() async` (notifications → fences → `await planWakeAlarms()`); `requestReschedule(after:)`; `refresh(reschedule: Bool, after delay: Duration = .zero)` — with reschedule true it only requests the job (no sync fence update). Taps: persist statement, then `refresh(reschedule: true, after: .milliseconds(300))` (R-37; Task 1.4 inserts "save failed → reload, return" after persist). `activate`: `alarms.reconcile()` first, then refresh after 150 ms. `deactivate` flushes under BackgroundWork when not idle.
- `BackgroundWork.run(name:_:)` (begin/end exactly once) and `finishRescheduleInBackground` helper; background paths onMoved, rideArrived (not active), visited/markArrived (only when marked), fenceEvent (post only).
- `refreshInBackground`: refresh(false) → isCancelled → await flush → isCancelled → publishSnapshot. JP27App: scheduleRefresh() first.
- LocationService: `moved(to:)` only when not foreground. Settings › Chẩn đoán: run count row (all builds).
- Parked: R-43 (ride stream → moved() → full reschedule every 500 m) → Task 3.3a/3.3b.

## 1.3 (3fa8078..4a4ec0e) — TripKit Money
- `Yen` (nonisolated): `maxEntry 9_999_999`, `isValidEntry`, `total` (saturating), `difference` (saturating), `Key` + `keyed(_:_:limit:) -> Int?` (keypad step).
- `LedgerValidation` (in LedgerMerge.swift): `Problem {amount, futureDate, text}`, `maxText 500` (Characters), `problems(_:now:)`.
- `LedgerMerge.screened(_:now:) -> (state, rejected: [UUID])`; `sanitized = screened.state`; `reply(local:remote:now:) -> LedgerState?` (R-53: nil unless the other phone would gain something this phone vouches for).
- `LedgerCSV`: `header` (13 cols), `encode`, `decode -> (records, rejected: [RowProblem])` (line = spreadsheet row number, R-46), integer-ms dates (R-45), `summary(...)` text builder; `RowProblem {line, reason: id|date|amount(String)|text}`.
- `Fmt.grouped` via magnitude; `BudgetStatus`/`CashPlan` saturating.
- App: `Expense.isCountable`; "Khoản cần sửa" section; `SpendLedgerFile.merge` async (decode @concurrent inside the security scope); `Outcome.skipped/lines`; `LedgerSync.rejected` (count, replaced per `.state`, not persisted — Task 1.5 shows it); LedgerSync `.state`: `screened` → merge → `reply` → seal if non-nil; `stamp` unchanged.
- CI: "App builds" job runs TripKit `swift test` on macOS (R-48).

## 1.4 (5bf1c6b..b444f14; closes after re-review) — durable saves
- TripKit `Plan/RecordIndexes.swift`: `RecordIndexes.moves([Record(day:index:target:deleted:)]) -> Moves {aside, home}` (record position → new index; aside indexes fresh, below min(0, day's lowest); orphans sitting on a target moved aside). `Day.resolve(-k, identity:)` finds a moved-aside row by identity (pinned).
- App `Data/Records.swift`: `SaveFailure` (LocalizedError), `SaveIssue {id, what, message}`, `ModelContext.commit() throws(SaveFailure)` (rolls back everything pending, then throws), `#if DEBUG Records.failSaves: FailSaves {off, next, all}` (not persisted; "next" turns itself off after one failed commit; best-effort copies unaffected). Exactly two `// save: best-effort` lines (Records.swift), pinned by the lint test.
- `Ledger.apply/merge/keepApart/restore` are `throws(SaveFailure)`; `Ledger.delete` stays a stager (caller persists once; it throws on a failed read since the final fix wave, R-154). `kept`/pace written only after a successful commit.
- `AppModel`: `saveIssue`, `persist(_ what:, retry:) -> Bool` (R-54: retry tied to the issue id; dropped on plan change/switchRecords/apply success), `loadRecords(persisting: Bool = true)` two-phase via RecordIndexes; failure paths reload with `persisting: false` (R-60). `logExpense -> Expense?`; toggleDone/toggleSkip/apply return Bool (@discardableResult). Alerts: root at level 0, top sheet (Presentation.swift), local in ExpenseEditor/SpendTopupSheet/SpendBuySheet/LedgerSyncSheet (R-55). `CheckButton` action returns Bool; `done` only on success, `.fail` otherwise. Debug `uniqueProbe()` in App/UniqueProbe.swift.
- LedgerSync `.state`: screened → `try Ledger.merge` (catch: `saveFailure = …`, `// Task 1.5: nack`, return — no stamp, no cached reset, no seal, no sent[k]) → saveFailure nil, cached nil, stamp → reply → seal. `status` shows saveFailure while the peer is near (A9; 1.5 replaces with Status).
- CI `data` job: "Saves are not silent" = `node scripts/lint-saves.mjs`; regex catches `try?` before `.save()` (incl. `?.`/`!.`), `.commit()`, and `Ledger.apply|merge|keepApart|restore(`.
- Parked → 2.1 (R-61): un-mark/un-skip delete by stored (day, index); after a failed phase 1 the stored index can match a neighbour's row — 2.1 deletes by identity, with a test.

## 2.1a (d56edfd..de66fb4) — ids in the data
- `src/data/days.ts`: `stop(at, place, title, text?, cost?, optional?, opts?: { key? })`, `walk/leg(..., opts: LegOpts & { key? })` (key destructured out before the leg and its hash: every `leg.id`/paths key unchanged); `stop/walk/leg` exported. Item `id`: `s:<place>`, `s:<place>:<key>`, `s::<key>` (placeless; `stop()` throws with neither place nor key), `m:<from>><to>[:<key>]`; key `/^[a-z0-9-]+$/` enforced at definition. Repeats today: day 1 `resol-akihabara` (`bags`/`checkin`), day 8 `wargo-gion` (`rent`/`return`).
- `src/data/id-renames.ts`: `ID_RENAMES: Record<dayKey, Record<old, new>>` (empty).
- Export: item `id` in trip.json and schedule.json; `uses` = every visit `{day, at, id}`; `idRenames` in trip.json; export throws on `problems(fromExport(...))`.
- `scripts/check-ids.mjs`: `problems` (unique per day; repeat ⇒ every visit keyed, R-78), `compare(base, head, renames)` (R-73 "looks renamed" by anchor: stop place / move from>to / `s::`), `renameProblems` (target exists, renamed id gone, day exists), `keptRenames` (shipped renames stay), `fromSource`/`fromExport` (by dayKey), `main(refs, days, log, load)` (first ref whose trip.json has ids; ref not a commit / git failure → exit 1; no file / no ids → printed skip).
- CI `data` job: checkout `fetch-depth: 0`; step "Item ids are stable": pull_request → origin/$BASE_REF; push → `before` if a commit, else `HEAD^ origin/main`. Limitation (R-80): until main carries ids, PRs skip; push-to-push can let a red push be followed by a green one — final review diffs ids d56edfd → tip.

## 2.1b (de66fb4..88adbea) — ids in TripKit
- `Stop.id`, `Move.id` (item id, NOT `move.leg.id` — geometry), `DayItem.id`; `Trip.idRenames: [day: [old: new]]` via `@ManyByKey` (Model/Defaults.swift; empty when the key is missing — schedule.json has none).
- `Plan/ItemIdentity.swift`: `identity(of:) = items[i].id`; `index(of:)`; `resolve(_:identity:)` — nil identity → index while the day has it; `stop:`/`move:` → the old algorithm on the current plan (R-83); otherwise exact by id (fast path at the index), never nearest. `renamed(_:renames:)` (R-77: one lookup; an id the day has is never renamed; R-88: legacy guard due in 2.1c). `migrate(legacy:index:renames:)`: nil → id at index; legacy → id of the item the old algorithm finds (nil if gone); new-format → `renamed` (unknown passes through). `legacyIdentity(of:)` internal.
- `Plan/ItemRef.swift`: `ItemRef {day, id}` Codable/Hashable/Sendable; `userInfo: [String: String]` (`["day", "item"]`); `arrived(from: [AnyHashable: Any]) -> ItemRef?` (both String; index-only → nil).
- `Reminder.itemID: String?` (dep/res), `Reminder.booking: Int?`; ids `dep-<day>-<itemID>`, `res-<day>-<itemID>` (ids contain ':'/'>'); `Reminder.index` kept for the app (R-82).
- `Fence: Codable`, `Fence.itemID: String?` (food stops, departures; each from its own day); `Fence.id` unchanged `kind:placeID`; `index` and the init's `index:` kept (R-82).
- Tests: `Support.swift` `removeItem(day:id:)`; ItemIdentityTests (17); 1.4 pin stays in PlanClockTests. 225/21.
- App call sites (2.1b report): `identity(of:)` AppModel :537, 592, 612, 683, 703; `resolve` :670, 692; ReminderPlanner :429; Reminder NotificationService :84, 97–121, 141–170 (`index` :157); Fence LocationService :204–230 (`index` :213), :253; AppModel :213, 879–897 (`index` :885, :892). The 2.1b build already writes new-format ids for new marks/skips.

## 2.1c (88adbea..fe14c66) — the app on item ids
- TripKit `Day.read(_ index:, identity:, renames:, converted:) -> (identity, index?)` — the one reading of a stored row: nil identity → item at index; new id → `renamed` then exact; legacy and !converted → `migrate`; legacy and converted → hidden (index nil, kept). `Day.records(of:among:renames:converted:)` — rows that read as an item (un-mark/un-skip deletes these). `Day.renamed` leaves legacy ids alone (R-88).
- `RecordIndexes.slots(for:holding:)` / `slot(for:holding:)` — insert index: the target unless a stored row holds it, else fresh below 0 (distinct across a batch).
- `ItemRef.locate(in: TripStore) -> (day, index)?` (renames → index(of:); nil → open the day), `ItemRef.arrivedDay(from:)`.
- `Fence.archive(_:) throws -> Data` / `Fence.unarchive(_:) -> [String: Fence]` (per entry, bad entry skipped); `Fence.index` and `Reminder.index` removed; `Fence.id` = `kind:placeID` unchanged (pinned).
- App: `records.ids` (= 2) in Shared.defaults, written only on the real store (`container === records && Records.problem == nil`) and only by a writing load whose Checkmark AND Skip fetches both succeeded, after phase 1 commits (R-90, R-94); rehearsal/side/in-memory read as unconverted. A generic `fetch(_:for:retry:) -> [T]?` reports read failures as failed writes. `fences.v2` replaces `fences`. `NotificationService.Action.markArrived(ItemRef)`; `arrived(at:store:people:item:)` writes `ItemRef.userInfo`. `Snapshot.itemID: String` (index dropped, R-92). Debug-only Chẩn đoán buttons post old/new "Đã tới".
- Release rule (R-86, in the checklist): the build that ships the conversion must not add/remove items on days with a repeated place (1, 8) nor change a move's line/from/to/via/path.

## 3.1a (fe14c66..a758481) — offline decisions in TripKit, content-addressed styles
- `Offline/OfflineArea.swift`: `TileBuild {template}`; `StyleInfo.build(style:)` (`sources.omt.tiles[0]`; nil for `-current`), `build(tileJSON:)` (`tiles[0]`), `styleBuild(style:)` (`metadata["jp27:build"]`), readers decode independently; `PackState: Int` mirrors `MLNOfflinePackState` raw values (unknown 0, inactive, active, complete, invalid); `PackTag {v = 2, area, build, styleURL}`, `read(_:)` v2 only, `area(of:)` v2/v1 JSON/raw string.
- `AreaPhase` (requested, creating, downloading(c,e), waitingForNetwork, paused, complete(TileBuild), stale(TileBuild?), failed(String)); not Codable. `OfflineArea.phase(state:completed:expected:maximum:tag:mapBuild:error:previous:)`: invalid → failed("Vùng tải đã hỏng, tải lại") first; tag nil → stale(nil) (v1 included, R-99); other build → stale; complete when state == .complete or (expected > 0 && completed >= expected && maximum == expected); previous .complete(mapBuild) kept while a resumed pack counts again; unknown → previous ?? requested; active + error → waitingForNetwork; inactive → paused.
- `OfflineJob {areas: Set<String>, photos: Bool}` Codable; `result(phases:photos: PhotoState(failed:left:paused:), mapBuild:) -> JobResult {success, done, failed (sorted), paused, subtitle}`: "Xong" only on success; paused → "Đã dừng"; else "Bản đồ d/t vùng · k lỗi · N ảnh chưa tải được"; an area missing from phases is neither done nor failed; a job without photos ignores PhotoState (`.finished`).
- Export: pinned styles carry `metadata {"jp27:tiles": template, "jp27:build": "<tile build>-<sha256[0..8] of the style without metadata>"}`; also written as `public/map/jp27-<theme>@<jp27:build>.json` (never rewritten or deleted; today `jp27-light@20261025_080012_pt-f5133df5.json`); `-current` styles: no `jp27:*`, no @ copy. `scripts/export-ios.test.mjs` reads the committed outputs (the script writes on import).
- Checklist "Task 3.1a": deploy the site (with the @ files) before releasing the app.

## 3.1b (a758481..a39a43d) — offline maps in the app
- TripKit additions: `AreaPhase.isUnderWay` (requested, creating, downloading, waitingForNetwork); `OfflineArea.settle(…) -> Settled` (per-area refresh rule: never forgets `.failed`, never re-makes `.failed`/`.creating`; an old pack goes only once the new one is complete, R-103); `OfflineArea.packBuild` (the style check); `StyleInfo.pointing(style:at:)` (current-mode style, `jp27:*` dropped).
- App `OfflineMaps`: `phases: [String: AreaPhase]` (+ stored `progress`, `bytes`, `problems` beside `.waitingForNetwork`); `complete`/`stale` computed; requests under `map.wanted`; `map.currentTemplate` (current mode; `map.currentTiles` dropped), `map.reloadAskedFor` (asked once per template, written on answer); `download` sets phases synchronously, `make` async (style GET of `jp27-light@<jp27:build>.json` or `-current` + TileJSON, re-checks `.creating` and the map's build after awaits); failures in memory, retried at the next launch or by a tap; `TripMap` snapshot key reads `OfflineMaps.mapBuild.template`. Debug "Giả style khác bản".
- `Downloads`: `job: OfflineJob?` saved per tap (`downloads.job`), restored ∩ defined areas (R-104), judged only after packs read and photos counted; `busy` from `isUnderWay`; `finish` uses `JobResult` (full bar and success only on success); progress line while running. `OfflinePhotos.paused` (cleared when every photo is on disk).
- Parked (R-106): taps during "Đang chuẩn bị…" (two packs / pause invisible), build move around `make`. Landed in the final fix wave (see below).

## 3.2 (a39a43d..c98fd61) — the location journal
- TripKit `Tracking/JournalPolicy.swift`: `JournalPolicy(days:margin: = 6 h)`; `window` = JST midnight of the first day − margin ..< JST midnight after the last + margin (nil without days); internal `tripDays`; `mayRecord(realNow:tripNow:rehearsing:enabled:)` (rehearsing → trip clock, else real clock only); `wantsBackgroundWatch(at:journal:alwaysGranted:)` = Always ∧ `[window.lower − 24 h, window.upper)` (significant changes; the journal switch does not change it); `wantsVisits` = the watch ∧ ((journal ∧ window) ∨ tripDays) (R-111).
- TripKit `Tracking/StayMemory.swift`: `Codable` `stays: [Stay {arrival, departure?, placeID?}]`, no coordinates; `report(_:placeID:now:) -> Report {stay, marks}` — same stay = arrivals within 120 s; the first report matching a place marks; later reports only fill a missing departure (never overwrite one) and a missing place (which then marks); forgets 24 h after departure (`keep`, edge `>=`), an open stay after 3 days (`keepOpen`); `departure(from:since:until:)` (arrival ≥ since, departure ≤ until, latest). Stored in `Shared.defaults` under `visits.seen`.
- App: `Shared.journalEnabled` (`journal.enabled`, missing = off); `LocationService.applyBackgroundWatch()` reads `backgroundWatch: () -> BackgroundWatch {visits, significantChanges}`; first call per launch starts or stops both, then only on change; called from `start()`, auth change, every `AppModel.refresh`, the switch. `AppModel.mayRecord` (`rehearsing && container !== records` for the trip clock); traces stamped `Shared.now`; `visited` → `StayMemory.report` → `keepInJournal` (only when `mayRecord`; reporting fetch, a failed read writes nothing) → mark at the stay's arrival; `walkStart` falls back to `StayMemory.departure` (R-108).
- `purgeLocationHistory(outsideTripOnly:) -> Int` (fetch, delete, `commit()`; failure → `report("Xoá lịch sử vị trí", …)` + "Thử lại", returns 0); `purgeOutsideTripOnce()` at the end of `activate()`, real main store only, flag `journal.purged.v1` after commit. Settings "Nhật ký" (switch, "Xoá lịch sử vị trí", re-count after delete); Chẩn đoán "Lịch sử vị trí: chỗ ghé · điểm vết". Today `TodayJournalQuestion`: `journal.asked`, or a rehearsal-only key removed when the rehearsal ends. Always usage text updated (R-109).
- Parked → final report: m3 (hand-marking the bag drop before iOS's arrival report still marks check-in, pre-existing), m7 (rehearsal visits carry real CLVisit times), m10 (side-merged / unreadable stores are not purged by the button).

## 3.3a (c98fd61..d45d472) — the day past a taken train; the untimed day; the snapshot
- `Itinerary.cursor(...)` signature unchanged; internal `locate(day, done:, now:, position:, skips:) -> (cursor, riding: (last: Int, ride: Ride)?)`. Untimed day: `timed = slots.contains { planned < now }`; untimed + nothing marked → cursor 0; the two-hour filter only on timed days (R-121). A hard move whose time has come (`<=`, R-123) is *taken* (widens candidates) when you are outside its boarding circle and > 1 km from it or on its line; *ridden* (moves the cursor to its last leg + 1) when also on its line (`offTrackKm < 1`), > 1 km from boarding, not within 1 km of a place the day named before it (R-114 c), and no more than 10 min behind its timetable position at your km — `Itinerary.due(ride, km:)` = departure + km / ride.km × the slowest planned run ("35–45" → 45, R-130); a ride without a timetable is never ridden (base) — (exempt at the ride's end) (R-125).
- `project(..., riding: Ride? = nil) -> (cursor, slots, replan, riding: Ride?)`: an explicit ride counts when it is today's, its legs are one consecutive run, its time has come (untimed: at once) (R-115), and a known position is not > `RideTracker.offTrack` (1.5 km) off its track away from its destination (R-126); then `.live(from: k + 1, now: arrival)`; `arrival` = on track `max(now + minutesLeft(km:), plannedArrival)`, else `max(now, plan end)`. No position → no inference (R-119).
- `PlanEngine.Options.position`; `present`: item `o.from` hard, clock set, you inside its place's circle → `ready = min(now, planned)` — for a move only until `planned + rules.grace.move` (R-124), for a stop unlimited. Plan runs (`Options()`) unchanged: check-plan parity holds.
- `ReminderPlanner.reminders(for:)`: no morning reminder when the day's first slot has no planned time (day 12). `Replan.lateStep(_:)` (5-min steps). `Itinerary.holdsReschedule(for:at:)` / `rideHold = 60`: only on the ride's day from departure − 30 to its plan end + 60 (R-118/R-127). `RideTracker.offTrack = 1.5` (shared with `RideLiveService`).
- App: `project()` passes `riding: live.hasArrived ? nil : live.ride`; `autoStartRide` offers the projection's `riding` first, a later candidate needs `nearStation` while riding; `publishSnapshot` changes on day / item / lateStep / setOff > 120 s / advice / a late snapshot ≥ 20 min old, `setOff` from the plan, `lastSnapshot` reset when `next` is nil; `location.onMoved` skips only the full reschedule while a followed ride holds it. Today: on a day with no planned time at all (`Itinerary.isUntimed(day)`, day 12) the card names the item at the cursor without a time until the day's items are done; every other day keeps "Hết lịch hôm nay" when `next` is nil (R-122/R-128). Test `everyRideEndsOnItsTrack` pins what R-126 relies on (R-129).
- Residuals → final report: day 12's empty widget (R-120; the widget's own plan clock has no untimed rule), ≈ 10-min silent window along the line after a train left (R-125), a transient false "late" in the first km of an unfollowed ride (m3), no position → no inference (R-119).

## 3.3b (d45d472..89f4a0a) — the ride's ETA from its history; the direct ferry; the GPS alarm never after the timetable's
- `RideTracker` (still a `Sendable` struct, now stateful): `record(km:at:)` with the fix's own time (`LocationService.fixedAt` = `CLLocation.timestamp`, set on the live stream and `didUpdateLocations`; nothing recorded without it); samples not after the newest ignored, > 350 km/h jumps ignored, a backward km held at the newest, 300 s kept; pace only over ≥ 120 s. `minutesLeft(km:speedKmh:)`: pace ?? instant speed; > 15 km/h measured, clamped to [0.6 × fast-end, 1.5 × slow-end] timetable ETA (remaining distance at the timetable pace, R-134); otherwise / fresh tracker = the timetable value exactly (3.3a's projection unchanged, R-133).
- `isDirect` (`prevIdx == 0`): `tail = max(total/2, total − max(0.8, 0.15 × total))` for `Status.alightSoon` and `minutesToAlightPrompt` (R-135).
- `RideTracker.alarm(km:speedKmh:at:notAfter:scheduled:now:)` (mutating): `min(gps, timetable alarm)`; nil once the timetable alarm's time has passed (R-131); once an alarm for the ride has rung, only the timetable alarm while still ahead (R-136) — at most two rings. `WakePlanner.alarm(for:)` = the instant `wakes` sets (planned arrival − lead, `isWorthAnAlarm` only). `WakeAlarms` has no past-time notice path (pinned).
- App `RideLiveService`: one `@ObservationIgnored` tracker per ride (fresh on a new ride), recorded in place; `arrival` and the alarm anchored at the fix's time, converted with `clockOffset`; Live Activity, Today's ride line and RideView read `live.arrival`. `RideTracker.offTrack` shared. `#if DEBUG` caption under RideView's alarm switch ("Báo thức hh:mm · GPS/lịch").
- Residuals → final report: two ETA figures (measured on the ride line, timetable pace in the projection/widget); the cap binds on time on Romancecar/Kintetsu-Nara; a ride followed after its timetable alarm gets no GPS alarm; the next train after a miss rings once at the first train's time; the arrival swings ~20 min at stops; a relaunch after an early ring may ring a third time.

## 3.4a (89f4a0a..9d14821) — rides end; one Live Activity; motion, fences on fresh state
- TripKit `Ride/RideTracker.swift` (3.3b's `alarm`/`record`/`minutesLeft` untouched):
  - `Ending {arrived, offLine, overdue}` and the constants:
    - `farOff = 3.0` km;
    - `offLineFor = 600` s;
    - `closeAfterArrival = 90` s;
    - `overdueAfter = 30` min;
    - `overdueShare = 0.5`;
    - `onLineFresh = 120` s;
    - `overdueCapAfter = 60` min.
  - `note(offTrackKm:at:)`:
    - fix times only (R-138);
    - counts only after one fix within `offTrack`;
    - a fix ≤ 3 km resets the count;
    - remembers whether the latest fix was on the line.
  - `ending(arrivedAt:followedAt:tripNow:now:)`:
    - arrived: 90 s, real clock;
    - off the line: off-line fixes spanning 600 s;
    - overdue: `tripNow ≥ deadline`. It is held while the latest fix is within `offTrack` and ≤ 120 s old, up to `deadline + max(60, stated max)` min (R-141).
  - `deadline(followedAt:)` = max(planned slow-end arrival, followedAt + slow duration) + max(30, 0.5 × slow duration). A ride without `min` counts 0.
  - `wake(…, canNotify:) -> Wake {alarm, notice, nothing}` wraps `alarm`. It gives a notice when:
    - the prompt is < 60 s away, counted from the fix;
    - nothing has rung;
    - no set alarm rings within 120 s;
    - the ride has not arrived;
    - `canNotify` holds. When false, it returns exactly `alarm`'s result (R-143).
  - `static arrival(minutesLeft:fixedAt:clockOffset:) -> (shown, live)`: `shown` is on the trip clock, floored to the minute; `live` is the real clock, for the Live Activity.
- TripKit `Tracking/Tracking.swift`: `Fence.plannedItem(today:) -> Int?`. Nil unless `fence.day == today.key` and the item is still in the day. FencePlanner is unchanged.
- App `RideLiveService`:
  - Every end goes through `claim` (the synchronous `closing` latch), then `release`. `release` does `ended.insert`, `alarms.cancel`, `activity.end`, the reset, `location.follow`, then `model.rideEnded()`.
  - A newer ride that wins the race gets its claim back.
  - Dismissal: `arrivedLinger` (15 min) after an arrival; at once otherwise.
  - `wasEnded(_:)`: autostart skips ended rides for the rest of the launch.
  - `endOrphans()` runs only in `activate()`, right after `alarms.reconcile()`. It ends only activities whose id differs from the held one (R-139).
  - `endAtOnce(model:)` is called whenever `clockOffset` changes (R-142, widened by R-153 in the final fix wave).
  - Final fix wave (R-153): TripKit `RideClock(rehearsal:)` — `endCancelsAlarm(rehearsingNow:)` = followed on the real clock and not rehearsing now; `endIsKept` = real rides only. `RideLiveService` records the clock at `start`; `claim(_:model:)` decides both (synchronously, before anything waits) and inserts into `ended`; `release` cancels the alarm only when the claim said so; `start`'s cancel of the previous ride follows the same rule. `forgetEnded()` clears `ended`, called by `setClock` on every crossing (after `endAtOnce`).
  - Debug: the `deadline` caption.
- App `AppModel`:
  - `rideEnded()` → `refresh(reschedule: true)`, plus the background finish. The timetable alarm comes back while it is still ahead.
  - `onMoved` calls `live.update` first.
  - `fenceEvent` computes today from `Shared.now` at the event.
- `AlarmService.firstNotice(for:)` is once per ride. It is persisted in `alarms.noticed`, with 2-day pruning; during a rehearsal it is kept in memory only.
- `NotificationService.alightSoon(_:)` sends the notice; `alertsAuthorized` is `.authorized` only.
- `MotionService.stop()` clears walking and riding.
- **Residuals → final report:**
  - A traveller who sits still after getting off is ended only at the app's next run (a checklist step covers this).
  - A ride followed by mistake the day before keeps navigation-grade GPS on until its deadline.
  - After a relaunch, autostart may follow the same ride again.
  - One extra notice is possible if AlarmService dropped a slot that had already rung.

## 3.4b (9d14821..5cd956b) — the rehearsal clock; Listen gives the audio back
- TripKit `Time/RehearsalClock.swift`:
  - `offset(_:)`: non-finite → 0; |raw| < 60 → 0; otherwise the nearest whole minute; never −0.
  - `isRehearsing(_:)`.
  - `start(at:realNow:current:) -> TimeInterval?` returns nil:
    - for a pick in the trip clock's current minute;
    - when the offset would be 0;
    - when it equals the running offset.

    So it never ends a rehearsal.
- `Shared.clockOffset`: both the getter and the setter apply the rule. `Shared.rehearsing`. `Shared.storedClockOffset` is the raw value, read only by R-145's legacy detection.
- `AppModel`:
  - `clockOffset` is `private(set)`. `rehearse(at:)` and `endRehearsal()` → `setClock`, which:
    - writes `Shared`;
    - on any change of the offset, runs `live.endAtOnce` (R-142, R-153); on a real crossing (by the rule), then `live.forgetEnded()` and `switchRecords`;
    - calls `refresh(reschedule: true)`.
  - The init's legacy ~0: `Records.setRehearsalAside()` throws unless every file moved. Offset 0 is written only on success; otherwise the raw value stays and the next launch retries. `rehearse` retries too, and refuses to start if that fails.
  - All decisions go through `rehearsing` / `Shared.rehearsing`: `setPaused`, `WakeAlarms`, `firstNotice`, `planWakeAlarms`, `mayRecord`.
- Settings:
  - The picker is seeded from `Shared.now`; an untouched seed means "now".
  - The button is disabled when `start` returns nil.
- Badge "Đang chạy thử":
  - in `NowAccessory` (glyph, "Chạy thử ·", VoiceOver label); `NowAccessorySlot` stays shown while rehearsing;
  - as the SpendTab subtitle "Đang chạy thử · sổ riêng".
- Listen (`TalkListener`):
  - Observers, added per listen with an id and removed first in `stop()` and in deinit: interruption began, `AVAudioEngineConfigurationChange`, `didEnterBackground`.
  - The tap drops buffers while `Speaker.voice` (a `SpeakingFlag`: `Atomic<Bool>` in a `Sendable` class) is on.
  - `giveSessionBack()`:
    - nothing being read → deactivate with notifyOthers, then restore `prior`;
    - mid-line → `Speaker.adoptSession()`, which moves to the Speaker's `.playback/.spokenAudio/.duckOthers` (`takeSession`, the one place) and leaves it to the Speaker's `ended` to deactivate.
  - Session calls stay on the main actor, an exception to contract § 4.2 until Task 4.2.
- **Residuals → final report:**
  - If the synthesizer never calls back, the flag stays on and Listen is deaf (as `speaking` sticks today; checklist step 6).
  - A partial set-aside splits the files under two names.
  - The stopSpeaking fallback is planned if checklist step 7 fails.
  - The Chi tiêu title height with an empty subtitle is unverified (checklist step 1).

## 3.4c (5cd956b..4818577) — the P3 batch
- TripKit:
  - `TripTime.beginLabel(planned:begin:)`: the planned time if there is one, else `clock(begin)`.
  - `Fmt.km`: the unit is chosen after rounding (0.996 → "1 km").
  - `Fmt.decimal`: the sign is taken from the rounded value (U+2212, never "−0").
  - Both formatters return "—" for NaN/±∞.
  - `Concurrency/FailureStreak` (`ticket`, `failed(_:)`, `succeeded`): failures that overlap count once.
- App:
  - `AppModel`: a one-shot `widgetOutdated` flag. It is set by `setClock` and by `alternatives` on a real change, and makes `publishSnapshot` reload once in the nil case.
  - The location row and `TodayAlwaysCard` share `AppModel.locationAskedAlwaysKey`.
  - The notification row shows `.ask` while undetermined.
  - `ForecastService` counts failures through `FailureStreak`.
  - `CloudForecast` and `FujiFinderView` work in real-clock hours.
- Widgets:
  - The snapshot branch re-labels from the begin it shows; `WidgetStop.planned` is new.
  - VoiceOver labels on "Trễ" and on the Live Activity's compact and minimal views.
- **Residuals → final report:**
  - M1: one dead tap on a phone that used the old location row.
  - M3: a huge finite value still traps `Fmt.decimal`.
  - The alternatives reload is backed by code review only.
  - VoiceOver on the Dynamic Island is unverified (checklist 8–9).

## Final fix wave (4818577..HEAD)
- R-153 (rides on the rehearsal clock): see § 3.4a and § 3.4b above.
- R-154 (money reads), app `Data/Records.swift`: `Ledger.fetch(_:in:) throws(SaveFailure)` (every ledger read a decision is made on; `#if DEBUG Records.failReads`, Settings › Chẩn đoán "Giả lỗi đọc sổ chi", not persisted); `Ledger.state`, `delete`, `folded` throw; `apply` stages then commits, and a failed read rolls back what it staged (no write, so no duplicate insert); `merge`/`restore` use `try state`. `AppModel.deleteExpense`/`unbuy`: a failed read rolls back and is reported like a failed write (`unread`). `LedgerSync.snapshot()` returns nil on a failed read (no digest, no stamp). `LedgerSyncView` shows a failed read of the folded rows inline. `lint-saves`: also flags `try?` before `fetch…(`/`delete(model:` in `Ledger` blocks and in any func/init whose code names `Ledger.` ("no silent money read").
- R-156 (background fixes): TripKit `Presence.fixAccuracy = 200`, `Presence.takes(accuracy:at:newest:)` (accuracy in [0, 200) and not older than the newest fix used). `LocationService.didUpdateLocations` publishes, sets `fixedAt` and calls `onUpdate` only when it takes the fix; the background re-plan (`moved(to:)`) still runs on any fix.
- 1.5 parked (A5 m2/m3, A6): `LedgerSyncSession.peerHas(_:current: = nil)` and `received(_:failure:current: = nil)`: a peer's failure clears only when the digest it failed on, or this phone's current one, is held there; `lastFailure` reads it. Docs: after a nack a send is due at once and goes at the next heartbeat; `LedgerMerge` reply doc names the heartbeat resend. Test fuzz `editsInFlightReconnectsAndTheTruth(seed:)` (5 seeds × 600 runs).
- 2.1b parked (A7): `scripts/check-ids.mjs` exports `baseDays(ref, cwd = root)`; a temp-repo test pins that the base's shipped `idRenames` reach the check.
- 3.1b parked (A10), TripKit `Offline/OfflineArea.swift`: `settle(current:older:previous:requested:making:)` — with no pack for the map's build, an area whose make is under way keeps its phase (`.creating`, or `.paused` by a tap); a `.creating` area with no make under way is made again when asked for. `OfflineArea.step(_ served: ServedStyle, mapBuild:askedOn:again:) -> MakeStep {add(TileBuild), again, fail(String)}`: the style of the map's build adds; a move of the map's build during the read → `again` once, then `fail(moved)`; a TileJSON naming a build the map does not read yet → `fail(moved)`; else the site's reason or `otherBuild`. `OfflineArea.moved = "Nguồn bản đồ vừa đổi — thử lại"`. `ServedStyle {files(style:tileJSON:), refused(String)}` moved from the app. `OfflineJob.result`: areas with no phase add "N vùng đã xoá".
- App `OfflineMaps`: `making: [String: Int]` (make numbers, from `download` until the pack is added, the area fails or is removed); `make` re-checks after each await (`still`: same number, no current pack, `.creating`/`.paused`); the add completion clears its own number before `refresh`; `pause` turns `.creating` into `.paused` (still made, then inactive; a failure leaves it paused); `remove` clears the number; `keeps(_:over:)` shared by `refresh` and `currentPack`; the bundled style read once (`bundled`).
- R-155: the release rule is the header of `src/data/id-renames.ts`.

import Foundation
import Observation
import SwiftData
import SwiftUI
import TripKit
import UIKit
import WidgetKit

enum AppTab: Hashable {
    case today, map, plan, talk, spend
}

/// Pushed destinations, shared by every tab's NavigationStack.
enum Route: Hashable {
    case day(String)
    case place(String)
    case ride(String)
    case journal(String)
    case food
    case stays
    case stay(String)
    case fuji
    case trains
    case bookings
    case handbook
    case scenario(String)
    case budget
    case shopping
    case slot(String)
    /// a sight on one of a hotel's walks that the trip has no page of its own for
    case highlight(stay: String, walk: String, index: Int)
}

/// Modal destinations.
enum AppSheet: Identifiable, Hashable {
    case place(String)
    case ride(String)
    case expense(placeID: String?, yen: Int?)
    /// what to order, how to say it and how to pay, on arriving at a place
    case atPlace(String)
    case menuScan(String?)
    case listen
    case fujiFinder
    /// a Fuji viewpoint as a card, like a place; `fromMap` when the 3D map is already under it
    case fujiSpot(String, fromMap: Bool)
    case journal(String)
    case settings

    var id: String {
        switch self {
        case .place(let id): "place-\(id)"
        case .ride(let id): "ride-\(id)"
        case .expense(let p, let y): "expense-\(p ?? "")-\(y ?? 0)"
        case .atPlace(let id): "at-\(id)"
        case .menuScan(let id): "scan-\(id ?? "")"
        case .listen: "listen"
        case .fujiFinder: "fuji"
        case .fujiSpot(let id, _): "fujispot-\(id)"
        case .journal(let d): "journal-\(d)"
        case .settings: "settings"
        }
    }
}

/// The app's state: the plan, the clock, where you are in today, and what was recorded.
@Observable final class AppModel {
    static let shared = AppModel()

    let store: TripStore
    let itinerary: Itinerary
    /// when the location journal records, and what is watched in the background
    let journalPolicy: JournalPolicy
    /// the records on disk
    private let records: ModelContainer
    /// what the app reads and writes: the records, or the rehearsal's own copy of them while one
    /// runs (`clockOffset`, `Records.rehearsal`)
    private(set) var container: ModelContainer
    /// the last rehearsal's store, kept open until the next one starts: a view may still hold one
    /// of its rows for a moment after the switch back
    @ObservationIgnored private var retired: ModelContainer?
    /// shown once at launch when the records could not be opened as usual (`Records.problem`)
    var storeAlert = false
    /// a write to the records that failed, for the alert in front (`persist`); the sheets that save
    /// take theirs and show it themselves (`takeSaveIssue`)
    var saveIssue: SaveIssue?
    /// "Thử lại" for `saveIssue`: the action again, asking for what it wanted (done, dropped, deleted)
    /// rather than flipping anything, and reading what is on disk now. Dropped when another issue
    /// takes its place, and when the plan or the records change under it (`forgetRetry`).
    private var retry: (issue: UUID, run: @MainActor () -> Void)?
    var context: ModelContext { container.mainContext }
    /// a rehearsal is running: the clock is shifted and the records are the rehearsal's
    var rehearsing: Bool { RehearsalClock.isRehearsing(clockOffset) }

    let location = LocationService()
    let notifications = NotificationService()
    let alarms = AlarmService()
    let live = RideLiveService()
    let motion = MotionService()
    let forecasts = ForecastService()
    /// map areas and photos kept for no signal, downloaded app-wide
    let downloads = Downloads()
    var offline: OfflineMaps { downloads.maps }
    let photos = PhotoLibrary()
    let network = NetworkStatus()
    /// the two phones' ledgers as one, while both are open near each other
    let ledgerSync = LedgerSync()

    // navigation
    var tab: AppTab = .today
    /// sheets on screen, bottom first; see `present(_:from:)`
    var sheets: [Presented] = []
    var todayPath = NavigationPath()
    var planPath = NavigationPath()
    var talkPath = NavigationPath()
    var spendPath = NavigationPath()
    /// a place the map should frame next time it shows
    var mapFocus: String?
    /// a day the map should show next time it shows
    var mapDay: String?

    // clock and choices
    private(set) var now: Date = Shared.now
    var alternatives: Set<String> = Shared.alternatives {
        didSet {
            Shared.alternatives = alternatives
            forgetRetry()
            refresh(reschedule: true)
        }
    }

    /// The location journal's switch (Settings › Nhật ký): stays and the walked trace are kept only
    /// with it on, and only during the trip (`journalPolicy`).
    var journalEnabled: Bool = Shared.journalEnabled {
        didSet {
            Shared.journalEnabled = journalEnabled
            // visits are watched off the trip days only for the journal
            location.applyBackgroundWatch()
        }
    }

    /// The Today question about the journal, once answered (`@AppStorage`, the app's own defaults).
    /// While rehearsing the answer goes under a key of its own, removed when the rehearsal ends: a
    /// rehearsal never answers it for the trip.
    nonisolated static let journalAskedKey = "journal.asked"
    nonisolated static let journalAskedRehearsalKey = "journal.asked.rehearsal"

    /// Bumped each time location history is deleted, for what counts it (Settings › Chẩn đoán).
    private(set) var historyDeletions = 0

    /// Seconds added to the real clock while rehearsing, by `RehearsalClock`'s rule: whole minutes,
    /// 0 for the real clock. Set only through `rehearse(at:)` and `endRehearsal()`.
    private(set) var clockOffset: TimeInterval = Shared.clockOffset

    /// "Chạy thử từ thời điểm này": the trip clock moved to `picked`. Nothing when that is about now
    /// (no rehearsal at real time, and never the end of one) or the rehearsal already running.
    func rehearse(at picked: Date) {
        guard let offset = RehearsalClock.start(at: picked, realNow: Date(), current: clockOffset) else { return }
        setClock(offset)
    }

    /// "Về giờ thật": the real clock again, and the rehearsal's records thrown away.
    func endRehearsal() {
        setClock(0)
    }

    private func setClock(_ offset: TimeInterval) {
        let was = rehearsing
        clockOffset = RehearsalClock.offset(offset)
        Shared.clockOffset = clockOffset
        if was != rehearsing {
            // a rehearsal starts or ends: a followed ride's times belong to the other clock
            live.endAtOnce(model: self)
            switchRecords()
        }
        refresh(reschedule: true)
    }

    private(set) var pace: PaceModel

    // derived
    private(set) var days: [Day] = []
    private(set) var phase: TripPhase = .after
    private(set) var cursor = 0
    private(set) var projection: [PlanEngine.Slot] = []
    private(set) var replan: Replan?
    private(set) var next: Waypoint?
    private(set) var marks: [String: [Int: Date]] = [:]
    private(set) var skips: [String: Set<Int>] = [:]

    private var clockTask: Task<Void, Never>?
    /// runs `reschedule`, one run at a time, requests close together served by one run
    @ObservationIgnored private lazy var rescheduler = Coalescer { [weak self] in await self?.reschedule() }
    private var lastProjected: Coordinate?
    /// the next activation comes back from the background (or is the first): restart what
    /// `deactivate` stopped. A moment inactive (Control Center, a notification pulled down) stops nothing.
    @ObservationIgnored private var asleep = true
    /// the pinned tile build was asked about and answered, this launch
    @ObservationIgnored private var tilesChecked = false

    var guide: Guide { store.guide! }
    var people: Int { store.trip.meta.people }
    var rate: Double { store.trip.meta.rate }

    var today: Day? {
        if case .during(let d) = phase { return d }
        return nil
    }

    var tomorrow: Day? {
        guard let today, let i = days.firstIndex(where: { $0.key == today.key }), days.indices.contains(i + 1) else { return nil }
        return days[i + 1]
    }

    /// The day to show when nothing says otherwise: today, else the first day.
    var focusDay: Day {
        switch phase {
        case .during(let d): d
        case .before(_, let first): first
        case .after: days.last ?? store.trip.days[0]
        }
    }

    var position: Coordinate? { location.position }

    var activeRide: Ride? { live.ride }

    init() {
        do {
            store = try TripStore.load(from: .main)
        } catch {
            fatalError("trip.json and guide.json ship with the app: \(error)")
        }
        itinerary = Itinerary(store: store)
        journalPolicy = JournalPolicy(days: store.trip.days)
        let real = Records.container()
        records = real
        if Shared.rehearsing {
            container = Records.rehearsal(copying: real, fresh: false)
        } else {
            container = real
            if Shared.storedClockOffset != 0 {
                // an older build started a "rehearsal" at about now (a picker left at now): what it
                // recorded was recorded at real time, so its store is set aside, never deleted
                Shared.clockOffset = 0
                Records.setRehearsalAside()
            } else {
                // a rehearsal that ended with the app closed leaves its store behind
                Records.discardRehearsal()
            }
            UserDefaults.standard.removeObject(forKey: Self.journalAskedRehearsalKey)
        }
        storeAlert = Records.problem != nil
        if let data = Shared.defaults.data(forKey: "paceModel"), let p = try? JSONDecoder().decode(PaceModel.self, from: data) {
            pace = p
        } else {
            pace = PaceModel()
        }
        loadRecords()
        ledgerSync.setPaused(rehearsing)
        refresh(reschedule: false)
        location.onUpdate = { [weak self] in self?.positionChanged($0) }
        location.onVisit = { [weak self] in self?.visited($0) }
        location.onFence = { [weak self] fence, entered in self?.fenceEvent(fence, entered: entered) }
        location.onAuthorizationChange = { [weak self] in
            guard let self else { return }
            // granted from the prompt: the app only went inactive under it, so start what it allows now
            location.follow(self)
            requestReschedule()
        }
        location.backgroundWatch = { [weak self] in self?.backgroundWatch() ?? .off }
        location.onMoved = { [weak self] in
            guard let self else { return }
            // a move that wakes the app in the background is a moment to see whether a followed ride
            // is over (no timer runs while the app is suspended)
            live.update(model: self)
            // a followed ride re-projects the day as it goes (every half kilometre, `positionChanged`)
            // and re-plans everything when it arrives (`rideArrived`): the significant changes on the
            // way do not each run the full reschedule under a background task. Only while it has not
            // arrived, and an hour past its planned arrival at most (`Itinerary.holdsReschedule`)
            if let ride = live.ride, !live.hasArrived, itinerary.holdsReschedule(for: ride, at: Shared.now) { return }
            requestReschedule()
            if inBackground { finishRescheduleInBackground() }
        }
        motion.onPace = { [weak self] kmh, minutes in self?.learnPace(kmh: kmh, minutes: minutes) }
        notifications.onAction = { [weak self] in self?.notificationAction($0) }
    }

    // MARK: - Lifecycle

    /// Foreground. Back from the background (or at launch): start the clock, resume what tracking
    /// the phase calls for, refresh schedules. Back from a moment inactive (Control Center, the
    /// notifications pulled down, the app switcher glanced at), nothing was stopped: the clock only
    /// catches up.
    func activate() {
        guard asleep else {
            refresh(reschedule: false)
            return
        }
        asleep = false
        // what was set while away, made to match the system's: an alarm the app was killed before
        // saving is taken back, one that rang is forgotten (before the plan sets what is missing)
        alarms.reconcile()
        // a Live Activity a killed run left on the lock screen: ended, nothing else touched
        live.endOrphans()
        startClock()
        location.resume(for: self)
        motion.start()
        // a moment later, so what the return sets off just after it (the permission's answer, a
        // move reported as the app opens) joins the same run
        refresh(reschedule: true, after: .milliseconds(150))
        Task {
            // reminders are the point of the app on the road: ask once, at first launch
            await notifications.refreshStatus()
            if notifications.undetermined { await notifications.requestAuthorization() }
            await HeroExporter.exportIfNeeded(store: store)
            // once per launch, as soon as it is online and gets an answer
            if !tilesChecked, network.online { tilesChecked = await OfflineMaps.checkPinnedTiles() }
        }
        // the colour of the photograph each page opens on, read once in the background (and kept),
        // so no page re-colours itself while it zooms open
        let covers = ambientCovers()
        Task(priority: .utility) {
            try? await Task.sleep(for: .seconds(2))
            await PhotoCache.shared.warmTones(covers)
        }
        offline.configure(store: store)
        downloads.photos.configure(remotePhotos())
        downloads.back()
        ledgerSync.activate(context: context)
        purgeOutsideTripOnce()
    }

    /// The trip's photos that are not in the bundle: restaurants, shops, a hotel's neighbourhood.
    private func remotePhotos() -> [Photo] {
        let stays = guide.stays.flatMap { s -> [Photo] in
            guard let around = s.around else { return [] }
            return around.photos + around.walks.flatMap { $0.highlights.flatMap(\.images) }
        }
        return store.trip.places.flatMap(\.images) + stays
    }

    /// The photograph each ambient page opens on: places, Fuji viewpoints, a hotel's neighbourhood,
    /// the walks' highlights, days.
    private func ambientCovers() -> [Photo] {
        var out = store.places.values.compactMap(\.hero)
        for spot in guide.fuji.spots {
            let place = store.place(spot.id)?.images ?? []
            if let first = spot.images.first ?? place.first(where: { $0.kind == "view" || $0.kind == "exterior" }) { out.append(first) }
        }
        for stay in guide.stays {
            if let first = stay.around?.photos.first { out.append(first) }
            out += stay.around?.walks.flatMap { $0.highlights.compactMap(\.images.first) } ?? []
        }
        out += days.compactMap { HomePicks.photo(for: $0, store: store) }
        return out
    }

    /// Background: stop the clock and what only the screen needs. The position stream stays only for
    /// a ride being followed (its background session keeps it alive under the lock screen); visits,
    /// geofences and significant changes still wake the app.
    func deactivate() {
        asleep = true
        clockTask?.cancel()
        clockTask = nil
        motion.stop()
        location.pause(riding: activeRide != nil)
        downloads.leaving()
        ledgerSync.deactivate()
        publishSnapshot(force: true)
        // a tick made just before leaving is still waiting out its 300 ms: finished now, under a
        // background task, not left for the next return
        if !rescheduler.isIdle { finishRescheduleInBackground() }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.refresh(reschedule: false)
            }
        }
    }

    /// Recompute everything that depends on the clock, the position and what was recorded.
    ///
    /// Runs every 20 seconds, so it only writes what changed: every write to an observed property
    /// redraws the views that read it, whether or not the value is new. The clock moves on the
    /// minute (nothing shows seconds).
    ///
    /// With `reschedule`, reminders, geofences and alarms are made to match too, `delay` from now
    /// (`requestReschedule`): a tap waits out its own animation, the return to the app what follows
    /// it. Without, only the watched circles follow a cursor that moved.
    func refresh(reschedule: Bool, after delay: Duration = .zero) {
        let t = Shared.now
        if reschedule || Int(t.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) { now = t }
        let chosen = store.days(choosing: alternatives)
        if chosen.map(\.key) != days.map(\.key) { days = chosen }
        let p = itinerary.phase(at: now, days: days)
        if Self.signature(p) != Self.signature(phase) {
            phase = p
            // a trip day began or ended: the position stream follows (see LocationService.follow)
            location.follow(self)
        }
        let moved = project()
        if reschedule {
            // the circles too, with the rest of the job
            requestReschedule(after: delay)
        } else if moved {
            // the watched circles follow the cursor
            location.updateFences(model: self)
        }
        // visits and significant changes start and stop near the trip, whose edges are not the
        // phase's (a day before, six hours after); unchanged, this reaches no Core Location call
        location.applyBackgroundWatch()
    }

    private static func signature(_ p: TripPhase) -> String {
        switch p {
        case .before(let days, let first): "before \(days) \(first.key)"
        case .during(let d): "during \(d.key)"
        case .after: "after"
        }
    }

    /// Projects the rest of today; true when the cursor moved.
    @discardableResult
    private func project() -> Bool {
        guard let day = today, let minutes = TripTime.minutes(of: now, on: day.date) else {
            let moved = cursor != 0
            if cursor != 0 { cursor = 0 }
            if !projection.isEmpty { projection = [] }
            if replan != nil { replan = nil }
            if next != nil { next = nil }
            publishSnapshot(force: false)
            return moved
        }
        let done = Set((marks[day.key] ?? [:]).keys)
        // the cursor comes with the projection: by the marks, the clock, where you stand, and the ride
        // followed (one that has arrived is only waiting to close: where you stand says more)
        let result = itinerary.project(day, done: done, now: minutes, position: position, pace: pace.factor, skips: skips[day.key] ?? [], riding: live.hasArrived ? nil : live.ride)
        let moved = result.cursor != cursor
        if moved { cursor = result.cursor }
        if result.slots != projection { projection = result.slots }
        if result.replan != replan { replan = result.replan }
        let n = itinerary.next(day, cursor: cursor)
        if n != next { next = n }
        autoStartRide(day, minutes: minutes, riding: result.riding)
        live.update(model: self)
        publishSnapshot(force: false)
        return moved
    }

    /// Start following a fixed departure on its own, from twenty minutes before it: near its
    /// station or already moving like a train. iOS lets an app start a Live Activity only while it
    /// is on screen, so the window is wide (any glance at the app on the way to the platform), and
    /// the station's geofence sends a notification whose "Theo dõi chuyến" opens the app to do it.
    /// The ride the projection already has you on (`riding`: on its line, past its station) comes
    /// first: once you are on it the cursor is past its departure, and the next one is a later ride.
    /// While you are on that one, the train's motion is its own: a later ride needs its station.
    private func autoStartRide(_ day: Day, minutes: Double, riding: Ride?) {
        // a ride that has arrived is only waiting to close: the connecting one starts over it
        guard live.ride == nil || live.hasArrived, live.isAvailable, UIApplication.shared.applicationState == .active else { return }
        let on = riding.flatMap { r in day.items.compactMap(\.move).first { $0.leg.id == r.legs.first } }
        var candidates: [(move: Move, current: Bool)] = []
        if let on { candidates.append((on, true)) }
        if let later = itinerary.nextDeparture(day, cursor: cursor) { candidates.append((later.move, false)) }
        for (move, current) in candidates {
            // a ride ended since launch (by hand, arrived, left, long past) is not started again on its own
            guard let planned = TripTime.minutes(move.at).map(Double.init),
                  (planned - 20 ... planned + 10).contains(minutes),
                  let ride = store.ride(startingWith: move.leg.id, on: day), !live.wasEnded(ride.id)
            else { continue }
            let nearStation = position.flatMap { p in store.place(move.leg.from).map { Geo.km($0.coordinate, p) < 0.4 } } ?? false
            let moving = motion.riding && (current || riding == nil)
            if nearStation || moving { live.start(ride, model: self) }
            return
        }
    }

    /// A ride reached its end: its legs are done. A mark that cannot be saved stops the rest; "Thử
    /// lại" marks the whole ride again.
    func rideArrived(_ ride: Ride) {
        guard let day = store.day(ride.day) else { return }
        for (i, item) in day.items.enumerated() {
            if let m = item.move, ride.legs.contains(m.leg.id), !isDone(day, i),
               !markDone(day, i, source: "ride", retry: { [weak self] in self?.rideArrived(ride) }) { break }
        }
        refresh(reschedule: true)
        // under the lock screen the ride's background positions end with it
        if inBackground { finishRescheduleInBackground() }
    }

    /// The followed ride ended, by any path (`RideLiveService.release`): the day projected without it,
    /// and reminders, geofences and alarms made to match, the timetable's alarm for it included while
    /// it is still ahead; the re-plans its hold kept back happen now. Under the lock screen, under a
    /// background task.
    func rideEnded() {
        refresh(reschedule: true)
        if inBackground { finishRescheduleInBackground() }
    }

    /// Reminders, geofences and alarms made to match within `delay` (`reschedule`), in one run with
    /// every other request close to it (`Coalescer`). Asked for when any of them may change: a mark,
    /// a skip, a day swapped, the rehearsal clock, the permission, a move, a return to the app.
    func requestReschedule(after delay: Duration = .zero) {
        rescheduler.request(after: delay)
    }

    /// Reminders, geofences and alarms, made to match the plan, the clock and what is done; returns
    /// once all three are set. Only `rescheduler` runs it, so two runs never overlap: a change made
    /// while one runs is picked up by the run after it.
    private func reschedule() async {
        // a departure or reservation already done, dropped, or behind something done has no reminder
        let reminders = ReminderPlanner(store: store).upcoming(days: days, now: now) { day, i in self.isSettled(day, i) }
        await notifications.schedule(reminders, clockOffset: clockOffset)
        location.updateFences(model: self)
        await planWakeAlarms()
    }

    /// The app is not on screen: woken in the background, or on its way there.
    private var inBackground: Bool { UIApplication.shared.applicationState != .active }

    /// What was asked for runs now (`Coalescer.flush`), under a background task, so iOS does not
    /// suspend the app before reminders, fences and alarms are set. For what wakes the app in the
    /// background (a significant move, a visit or a "Đã tới" that marked a stop, a ride arriving
    /// under the lock screen) and for leaving it.
    private func finishRescheduleInBackground() {
        BackgroundWork.run(name: "Đặt lại nhắc giờ, geofence, báo thức") { [weak self] in await self?.rescheduler.flush() }
    }

    /// How many times reminders, geofences and alarms were set again since launch, for Settings ›
    /// Chẩn đoán; read when shown, not observed.
    var reschedules: Int { rescheduler.runs }

    /// Alarms from the timetable for the long train rides of today and tomorrow (`WakePlanner`:
    /// 25 minutes or more on a train, never a boat, a bus or the metro), four minutes before the
    /// planned arrival, so the 7:37 Romancecar has its alarm from the evening before. Reconciled on
    /// every change of plan: rides taken, days swapped and alarms turned off are cancelled. Not on
    /// the rehearsal clock, whose times are not real ones.
    private func planWakeAlarms() async {
        guard !rehearsing else { return }
        let wakes = WakePlanner(store: store).wakes(days: days, now: now) { day, i in self.marks[day.key]?[i] != nil }
        await alarms.planWake(wakes)
    }

    /// The ride's own switch: on by default for the rides worth an alarm, off for the rest (a
    /// followed boat ride rings no one on deck unless asked to).
    func wakeAlarmIsOn(_ ride: Ride) -> Bool {
        alarms.isOn(ride.id, default: WakePlanner(store: store).isWorthAnAlarm(ride))
    }

    /// Off cancels what is set, at once; on sets the timetable's alarm again with the next run of
    /// the reschedule (after the switch's animation, like any tap, and never beside another run's
    /// alarms), or the GPS one at the next position of a followed ride.
    func setWakeAlarm(_ on: Bool, for ride: Ride) {
        alarms.setOn(on, rideID: ride.id)
        if on { requestReschedule(after: .milliseconds(300)) }
    }

    // MARK: - Minutes

    /// Minutes since the day's midnight in Japan.
    func minutes(on day: Day) -> Double {
        TripTime.minutes(of: now, on: day.date) ?? 0
    }

    func date(_ day: Day, minutes: Double) -> Date {
        TripTime.date(day.date, minutes: minutes) ?? now
    }

    /// Projected slot of an item today, when it is still ahead.
    func slot(_ index: Int) -> PlanEngine.Slot? {
        projection.first { $0.index == index }
    }

    // MARK: - Marks and skips

    func isDone(_ day: Day, _ index: Int) -> Bool { marks[day.key]?[index] != nil }
    /// done, dropped, or before the last item marked done (the day has moved past it)
    func isSettled(_ day: Day, _ index: Int) -> Bool {
        isDone(day, index) || isSkipped(day, index) || (marks[day.key]?.keys.max() ?? -1) > index
    }
    func isSkipped(_ day: Day, _ index: Int) -> Bool { skips[day.key]?.contains(index) == true }
    func doneCount(_ day: Day) -> Int { marks[day.key]?.count ?? 0 }
    func marked(_ day: Day) -> [Int: Date] { marks[day.key] ?? [:] }

    /// Marks item `index` done, or takes the mark off. False when the change could not be saved: the
    /// marks are read again from the disk and the alert says so.
    @discardableResult
    func toggleDone(_ day: Day, _ index: Int) -> Bool {
        setDone(!isDone(day, index), day, index)
    }

    /// Item `index` done or not, by hand; true when it is so on disk now.
    private func setDone(_ done: Bool, _ day: Day, _ index: Int) -> Bool {
        guard done != isDone(day, index) else { return true }
        if done {
            guard markDone(day, index, source: "hand") else { return false }
        } else {
            let key = day.key
            let again: @MainActor () -> Void = { [weak self] in _ = self?.setDone(false, day, index) }
            guard let rows = fetch(FetchDescriptor<Checkmark>(predicate: #Predicate { $0.day == key }), for: "Bỏ đánh dấu", retry: again) else { return false }
            // the item's own rows, wherever each sits: never another item's row on its index
            for n in ownRows(of: index, day, rows.map { (index: $0.index, identity: $0.identity) }) { context.delete(rows[n]) }
            guard persist("Bỏ đánh dấu", retry: again) else {
                loadRecords(persisting: false)
                return false
            }
            marks[day.key]?[index] = nil
        }
        // the screen moves on at once; a reminder, a fence or an alarm may belong to what was just
        // marked, and is set after the tick's animation, not on its frame
        refresh(reschedule: true, after: .milliseconds(300))
        return true
    }

    /// Marks item `index` done; false when it already was, the day has no such item, or the mark
    /// could not be saved or placed (the day's marks could not be read): the alert says so, and its
    /// "Thử lại" runs `retry`, by default this mark again. After a failed save the marks are read
    /// again from the disk.
    @discardableResult
    func markDone(_ day: Day, _ index: Int, at: Date? = nil, source: String, retry: (@MainActor () -> Void)? = nil) -> Bool {
        guard day.items.indices.contains(index), !isDone(day, index) else { return false }
        let when = at ?? now
        let again: @MainActor () -> Void = retry ?? { [weak self] in
            guard let self, markDone(day, index, at: when, source: source) else { return }
            refresh(reschedule: true, after: .milliseconds(300))
        }
        let key = day.key
        guard let rows = fetch(FetchDescriptor<Checkmark>(predicate: #Predicate { $0.day == key }), for: "Đánh dấu điểm", retry: again) else { return false }
        // on the item's index, unless a row still holds it: inserted there, it would replace that row
        context.insert(Checkmark(day: key, index: RecordIndexes.slot(for: index, holding: rows.map(\.index)), at: when, source: source, identity: day.identity(of: index)))
        guard persist("Đánh dấu điểm", retry: again) else {
            loadRecords(persisting: false)
            return false
        }
        marks[day.key, default: [:]][index] = when
        // a stop reached on foot teaches the pace: the walk before it, planned against actual,
        // timed from when the walk began, never from the arrival at the place before (that would
        // count the visit there as walking)
        if index > 0, case .move(let m) = day.items[index - 1], store.mode(of: m.leg) == .walk,
           let w = m.leg.walk, let left = walkStart(day, walk: index - 1, until: when) {
            pace.add(planned: Double(w.min), actual: when.timeIntervalSince(left) / 60)
            savePace()
        }
        return true
    }

    /// When the walk at item `walk` began, if anything recorded it: the end of the ride that
    /// brought you to its start (you step off and walk), or the departure iOS reported from the
    /// stop before it (the journal's stay, else the stay remembered without it, `StayMemory`).
    /// Unknown otherwise, and then nothing is learnt from the walk.
    private func walkStart(_ day: Day, walk: Int, until: Date) -> Date? {
        guard walk > 0 else { return nil }
        switch day.items[walk - 1] {
        case .move(let m) where store.mode(of: m.leg) != .walk:
            return marks[day.key]?[walk - 1]
        case .stop(let s):
            guard let place = store.place(s.place) else { return nil }
            let since = until.addingTimeInterval(-3 * 3600)
            let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival >= since }))) ?? []
            let journal = visits
                .filter { Presence.isAt(Coordinate($0.lat, $0.lng), place) }
                .compactMap(\.departure)
                .filter { $0 <= until }
                .max()
            // without the journal, the stay iOS reported there (by the place it matched)
            return journal ?? stays.departure(from: place.id, since: since, until: until)
        default:
            return nil
        }
    }

    /// Drops item `index`, or keeps it again. False when the change could not be saved: the skips are
    /// read again from the disk and the alert says so.
    @discardableResult
    func toggleSkip(_ day: Day, _ index: Int) -> Bool {
        setSkipped(!isSkipped(day, index), day, index)
    }

    /// Item `index` dropped or not; true when it is so on disk now.
    private func setSkipped(_ skipped: Bool, _ day: Day, _ index: Int) -> Bool {
        guard skipped != isSkipped(day, index) else { return true }
        let key = day.key
        let what = skipped ? "Bỏ điểm" : "Giữ lại điểm"
        let again: @MainActor () -> Void = { [weak self] in _ = self?.setSkipped(skipped, day, index) }
        guard let rows = fetch(FetchDescriptor<Skip>(predicate: #Predicate { $0.day == key }), for: what, retry: again) else { return false }
        if skipped {
            // as a mark (`markDone`): never onto a row that still holds the item's index
            context.insert(Skip(day: key, index: RecordIndexes.slot(for: index, holding: rows.map(\.index)), at: now, identity: day.identity(of: index)))
        } else {
            for n in ownRows(of: index, day, rows.map { (index: $0.index, identity: $0.identity) }) { context.delete(rows[n]) }
        }
        guard persist(what, retry: again) else {
            loadRecords(persisting: false)
            return false
        }
        if skipped { skips[key, default: []].insert(index) } else { skips[key]?.remove(index) }
        refresh(reschedule: true, after: .milliseconds(300))
        return true
    }

    /// Take the replanner's advice: drop its stops. False when that could not be saved (the skips
    /// are read again from the disk, and the alert says so).
    @discardableResult
    func apply(_ plan: Replan) -> Bool {
        guard let day = today else { return false }
        let drop = plan.drop.filter { !isSkipped(day, $0) }
        // again only on the same day: the advice is about its items
        let again: @MainActor () -> Void = { [weak self] in
            guard let self, today?.key == day.key else { return }
            _ = apply(plan)
        }
        let key = day.key
        guard let rows = fetch(FetchDescriptor<Skip>(predicate: #Predicate { $0.day == key }), for: "Bỏ điểm theo gợi ý", retry: again) else { return false }
        // each on its item's index unless a row holds it, never two on one (`RecordIndexes.slots`)
        for (i, slot) in zip(drop, RecordIndexes.slots(for: drop, holding: rows.map(\.index))) {
            context.insert(Skip(day: key, index: slot, at: now, identity: day.identity(of: i)))
        }
        guard persist("Bỏ điểm theo gợi ý", retry: again) else {
            loadRecords(persisting: false)
            return false
        }
        for i in drop { skips[day.key, default: []].insert(i) }
        // the day is not the one an earlier failed write was about any more
        forgetRetry()
        refresh(reschedule: true, after: .milliseconds(300))
        return true
    }

    /// A rehearsal starts or ends: from now on everything reads and writes the rehearsal's records,
    /// or the real ones again, and the rehearsal's are thrown away. The sync with the other phone
    /// waits while a rehearsal runs, so nothing practised reaches it.
    private func switchRecords() {
        // "Thử lại" would write to the records just left
        forgetRetry()
        if rehearsing {
            retired = nil
            container = Records.rehearsal(copying: records, fresh: true)
        } else {
            retired = container
            container = records
            Records.discardRehearsal()
            // the rehearsal's answer to the journal question goes with it
            UserDefaults.standard.removeObject(forKey: Self.journalAskedRehearsalKey)
        }
        loadRecords()
        ledgerSync.setPaused(rehearsing)
        ledgerSync.activate(context: context)
    }

    /// The marks and skips, each on the item it was recorded for. An update may have edited the
    /// plan since (an item added before it, one taken out): a record follows its item by its id
    /// (`Day.read`), through the renames the update shipped, its stored index is corrected, and a
    /// record whose item is gone is kept but left out.
    ///
    /// Records from before ids are converted once, on the plan of the build that first loads them (the
    /// plan they were written under, when an update is released that way): named the old way ("stop:",
    /// "move:"), each becomes its item's id; with no identity at all, the id of the item at its index.
    /// One that finds no item keeps its old name and is shown nowhere, then and after. Only the real
    /// records are marked converted (`recordsConverted`).
    ///
    /// The indexes are corrected in two writes (`RecordIndexes`): a record is unique by day and index,
    /// and moving 3 → 4 while another still sits on 4 would clash halfway through one write. First
    /// the duplicates go, every record is named by its id, and every record changing index steps aside
    /// below 0; then each goes to its item's index. A write that fails leaves what is on screen right
    /// (it comes from the ids, not the stored indexes), and the next load tries again.
    ///
    /// Without `persisting` it only reads: after a write that failed, so the user's alert and its
    /// "Thử lại" stay that write's, and a fix still waiting goes with the next load that writes (at
    /// launch, or when the records switch).
    private func loadRecords(persisting: Bool = true) {
        let converted = recordsConverted
        let again: @MainActor () -> Void = { [weak self] in self?.loadRecords() }
        let fetchedChecks: [Checkmark]?, fetchedSkips: [Skip]?
        if persisting {
            fetchedChecks = fetch(FetchDescriptor<Checkmark>(), for: "Dấu đã đi và điểm bỏ", retry: again)
            fetchedSkips = fetch(FetchDescriptor<Skip>(), for: "Dấu đã đi và điểm bỏ", retry: again)
        } else {
            // after a failed write: what can be read is shown, and the alert stays that write's
            fetchedChecks = try? context.fetch(FetchDescriptor<Checkmark>())
            fetchedSkips = try? context.fetch(FetchDescriptor<Skip>())
        }
        // Writes only after every record was read: a table that could not be read looks empty, and a
        // load that went on would mark the real records converted with its old names never converted,
        // hiding them for good (`markRecordsConverted`). Such a load shows what it read, writes
        // nothing, and the alert says the records could not be read; the next load that writes tries.
        let writing = persisting && fetchedChecks != nil && fetchedSkips != nil
        let checks = fetchedChecks ?? [], dropped = fetchedSkips ?? []
        var changed = false
        var marks: [String: [Int: Date]] = [:]
        var held: [String: [Int: Checkmark]] = [:]
        var checkRows: [RecordIndexes.Record] = []
        for c in checks {
            let read = store.day(c.day).map { $0.read(c.index, identity: c.identity, renames: renames($0), converted: converted) }
            guard let read, let i = read.index else {
                checkRows.append(RecordIndexes.Record(day: c.day, index: c.index, target: nil))
                continue
            }
            if let other = held[c.day]?[i] {
                // two records came to one item: one is kept, with the earlier time
                guard writing else { continue }
                if c.at < other.at { other.at = c.at }
                context.delete(c)
                changed = true
                checkRows.append(RecordIndexes.Record(day: c.day, index: c.index, target: nil, deleted: true))
                continue
            }
            if writing, c.identity != read.identity { c.identity = read.identity; changed = true }
            held[c.day, default: [:]][i] = c
            marks[c.day, default: [:]][i] = c.at
            checkRows.append(RecordIndexes.Record(day: c.day, index: c.index, target: i))
        }
        var skips: [String: Set<Int>] = [:]
        var skipRows: [RecordIndexes.Record] = []
        for k in dropped {
            let read = store.day(k.day).map { $0.read(k.index, identity: k.identity, renames: renames($0), converted: converted) }
            guard let read, let i = read.index else {
                skipRows.append(RecordIndexes.Record(day: k.day, index: k.index, target: nil))
                continue
            }
            if skips[k.day]?.contains(i) == true {
                guard writing else { continue }
                context.delete(k)
                changed = true
                skipRows.append(RecordIndexes.Record(day: k.day, index: k.index, target: nil, deleted: true))
                continue
            }
            if writing, k.identity != read.identity { k.identity = read.identity; changed = true }
            skips[k.day, default: []].insert(i)
            skipRows.append(RecordIndexes.Record(day: k.day, index: k.index, target: i))
        }
        self.marks = marks
        self.skips = skips
        guard writing else { return }
        let checkMoves = RecordIndexes.moves(checkRows), skipMoves = RecordIndexes.moves(skipRows)
        guard changed || !checkMoves.isEmpty || !skipMoves.isEmpty else {
            // every record read, nothing to convert or nothing left to: each found is named by its id
            markRecordsConverted()
            return
        }
        for (n, index) in checkMoves.aside { checks[n].index = index }
        for (n, index) in skipMoves.aside { dropped[n].index = index }
        guard persist("Dấu đã đi và điểm bỏ", retry: again) else { return }
        // the ids are on disk, written with the first step
        markRecordsConverted()
        guard !checkMoves.home.isEmpty || !skipMoves.home.isEmpty else { return }
        for (n, index) in checkMoves.home { checks[n].index = index }
        for (n, index) in skipMoves.home { dropped[n].index = index }
        _ = persist("Dấu đã đi và điểm bỏ", retry: again)
    }

    /// The records read and written are the real ones, opened as usual: not a rehearsal's copy, and
    /// not the side store (or the memory) a records file that would not open leaves (`Records.problem`).
    private var onRealRecords: Bool { container === records && Records.problem == nil }

    /// The real records name every item they find by its id: an identity of the old scheme still in
    /// them found no item on the plan it was written under, and is shown nowhere (`Day.read`). Never
    /// so for another store: a rehearsal's copy, or the side store, is converted on each load that
    /// writes it, which on one plan changes nothing twice.
    private var recordsConverted: Bool {
        onRealRecords && Shared.defaults.integer(forKey: Shared.Key.recordIDs) == 2
    }

    /// After a load of the real records that read every mark and skip and then wrote their ids, or
    /// found nothing to write; never after a read that failed (an unread table looks empty) nor
    /// before the write is on disk. Once set, an old name is never converted again (`Day.read`).
    private func markRecordsConverted() {
        guard onRealRecords, !recordsConverted else { return }
        Shared.defaults.set(2, forKey: Shared.Key.recordIDs)
    }

    /// The renames an update shipped for `day` (`Trip.idRenames`).
    private func renames(_ day: Day) -> [String: String] {
        store.trip.idRenames[day.key] ?? [:]
    }

    /// The rows among `rows` (a day's marks or skips, as stored) that are item `index`'s, read as a load
    /// reads them: what taking its mark or its skip off deletes.
    private func ownRows(of index: Int, _ day: Day, _ rows: [(index: Int, identity: String?)]) -> [Int] {
        day.records(of: index, among: rows, renames: renames(day), converted: recordsConverted)
    }

    /// What `descriptor` finds in the records, for a write that must know what is there first; nil when
    /// they could not be read, which the alert tells as the write that did not happen (`what`, `retry`).
    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>, for what: String, retry: @escaping @MainActor () -> Void) -> [T]? {
        do {
            return try context.fetch(descriptor)
        } catch {
            report(what, SaveFailure(underlying: error), retry: retry)
            return nil
        }
    }

    // MARK: - Money

    /// nil when it could not be saved (`saveIssue` says why; nothing of it is kept).
    @discardableResult
    func logExpense(yen: Int, category: SpendCategory, method: PayMethod, placeID: String?, note: String = "", itemID: String? = nil) -> Expense? {
        logExpense(yen: yen, category: category, method: method, placeID: placeID, placeName: nil, day: today?.key, note: note, itemID: itemID)
    }

    /// An expense counted toward a chosen day, at a place from the data or one named by hand; nil
    /// when it could not be saved (`saveIssue` says why; nothing of it is kept, and whatever else was
    /// waiting to go with it, like the purchase it pays for, is taken back too).
    @discardableResult
    func logExpense(yen: Int, category: SpendCategory, method: PayMethod, placeID: String?, placeName: String?, day: String?, note: String = "", itemID: String? = nil) -> Expense? {
        let e = Expense(yen: yen, category: category, method: method, placeID: placeID, placeName: placeName, day: day, note: note, at: now, coordinate: position, itemID: itemID)
        context.insert(e)
        return persist("Khoản chi") ? e : nil
    }

    /// Cash withdrawn or Suica topped up; false when it could not be saved.
    @discardableResult
    func topUp(yen: Int, method: PayMethod) -> Bool {
        context.insert(Topup(yen: yen, method: method, at: now))
        return persist(method == .cash ? "Rút tiền" : "Nạp Suica")
    }

    /// Deletes an expense, leaving the deletion for the other phone; false when it could not be saved.
    @discardableResult
    func deleteExpense(_ id: UUID) -> Bool {
        for e in (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id }))) ?? [] {
            Ledger.delete(e, in: context)
        }
        return persist("Xoá khoản chi", retry: { [weak self] in _ = self?.deleteExpense(id) })
    }

    /// An item no longer bought: the purchase and the expenses that paid for it, through the ledger so
    /// the other phone drops them too, in one write; false when it could not be saved (all of it stays).
    @discardableResult
    func unbuy(_ itemID: String) -> Bool {
        let linked: String? = itemID
        try? context.delete(model: Purchase.self, where: #Predicate { $0.itemID == itemID })
        for e in (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.itemID == linked }))) ?? [] {
            Ledger.delete(e, in: context)
        }
        return persist("Bỏ đã mua", retry: { [weak self] in _ = self?.unbuy(itemID) })
    }

    /// Two rows that look like one expense logged twice, said to be two (`Ledger.keepApart`); false
    /// when that could not be saved, and the pair is asked about again.
    @discardableResult
    func keepApart(_ a: UUID, _ b: UUID) -> Bool {
        do {
            try Ledger.keepApart(a, b, in: context)
            return true
        } catch {
            report("Giữ cả hai khoản", error, retry: { [weak self] in _ = self?.keepApart(a, b) })
            return false
        }
    }

    // MARK: - Saving

    /// Writes what is waiting in the records. False when the write failed: everything waiting was
    /// taken back (`ModelContext.commit`), so the screens show what is on disk, and `saveIssue` tells
    /// the user `what` was not saved and why. `retry` is "Thử lại": the action again, from what is on
    /// disk then; without one the alert only says so.
    func persist(_ what: String, retry: (@MainActor () -> Void)? = nil) -> Bool {
        do {
            try context.commit()
            return true
        } catch {
            report(what, error, retry: retry)
            return false
        }
    }

    private func report(_ what: String, _ failure: SaveFailure, retry: (@MainActor () -> Void)?) {
        let issue = SaveIssue(what: what, error: failure.localizedDescription)
        saveIssue = issue
        self.retry = retry.map { (issue.id, $0) }
    }

    /// Whether `issue`, on the alert, can be tried again.
    func canRetry(_ issue: SaveIssue) -> Bool { retry?.issue == issue.id }

    /// "Thử lại" on the alert for `issue`.
    func retrySave(_ issue: SaveIssue) {
        guard let retry, retry.issue == issue.id else { return }
        self.retry = nil
        retry.run()
    }

    /// The failed write's issue, for a sheet that shows it itself (its own "Thử lại" saves again):
    /// taken off the alert in front, in the same moment, so it is never shown twice.
    func takeSaveIssue() -> SaveIssue? {
        defer {
            saveIssue = nil
            retry = nil
        }
        return saveIssue
    }

    /// The plan, the day or the records changed under a failed write: its "Thử lại" could meet other
    /// items, or other records, and is dropped (the alert keeps only its "OK").
    private func forgetRetry() {
        if retry != nil { retry = nil }
    }

    // MARK: - Position, visits, fences

    /// Every fix. On a ride each one moves the Live Activity on, but the plan barely moves with the
    /// train (the cursor is past the ride once it is under way, its arrival barely moves, and the
    /// clock re-projects every 20 seconds): it is projected again every half kilometre then, instead
    /// of every 30 m (about every second at speed).
    private func positionChanged(_ p: Coordinate) {
        let riding = activeRide != nil
        if riding { live.update(model: self) }
        if let last = lastProjected, Geo.km(last, p) < (riding ? 0.5 : 0.03) { return }
        lastProjected = p
        // the journal's trace: during the trip, with the switch on (`journalPolicy`)
        if mayRecord, location.shouldTrace(p) { context.insert(Trace(at: Shared.now, coordinate: p)) }
        refresh(reschedule: false)
    }

    /// iOS reports a stay twice: on arrival (no departure yet), then on leaving (both times).
    /// One stay marks one stop, once: the stop it is nearest to, when it is first reported
    /// (`StayMemory`, kept without the journal). The second report only completes the stay; a stay
    /// first reported already with its departure still counts. The journal keeps the stay too,
    /// when it records (`mayRecord`).
    private func visited(_ v: VisitRecord) {
        let match = matchPlan(v.coordinate)
        var memory = stays
        let outcome = memory.report(v, placeID: match.flatMap { day, i in day.items[i].stop?.place }, now: Date())
        stays = memory
        keepInJournal(outcome.stay, at: v.coordinate)
        var marked = false
        if outcome.marks, let (day, i) = match { marked = markDone(day, i, at: outcome.stay.arrival, source: "visit") }
        refresh(reschedule: marked)
        if marked, inBackground { finishRescheduleInBackground() }
    }

    /// The stay in the journal, in a write of its own (a mark that cannot be saved does not take it
    /// back with it): a new one, or the departure and place of the one kept on arrival. Nothing
    /// outside the trip or with the switch off (`mayRecord`).
    private func keepInJournal(_ stay: StayMemory.Stay, at coordinate: Coordinate) {
        guard mayRecord else { return }
        let from = stay.arrival.addingTimeInterval(-120), to = stay.arrival.addingTimeInterval(120)
        let again: @MainActor () -> Void = { [weak self] in self?.keepInJournal(stay, at: coordinate) }
        // a table that could not be read is not "no stay there": that would write the stay twice. Said,
        // and nothing written; iOS's leaving report, or "Thử lại", tries again
        guard let near = fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival >= from && $0.arrival <= to }), for: "Chỗ đã ghé", retry: again) else { return }
        let v = VisitRecord(arrival: stay.arrival, departure: stay.departure, coordinate: coordinate)
        if let same = near.first(where: { $0.record.isSameStay(as: v) }) {
            // nothing new: no write
            guard (same.departure == nil && stay.departure != nil) || (same.placeID == nil && stay.placeID != nil) else { return }
            if same.departure == nil { same.departure = stay.departure }
            if same.placeID == nil { same.placeID = stay.placeID }
        } else {
            context.insert(Visit(arrival: stay.arrival, departure: stay.departure, coordinate: coordinate, placeID: stay.placeID))
        }
        _ = persist("Chỗ đã ghé", retry: again)
    }

    /// The stays iOS reported lately, without their coordinates (`StayMemory`), in the App Group's
    /// defaults: a stay's second report often relaunches the app hours after the first.
    private var stays: StayMemory {
        get { Shared.defaults.data(forKey: Shared.Key.stays).flatMap { try? JSONDecoder().decode(StayMemory.self, from: $0) } ?? StayMemory() }
        set { Shared.defaults.set(try? JSONEncoder().encode(newValue), forKey: Shared.Key.stays) }
    }

    /// Today's stop a stay belongs to: the nearest one whose `Presence` circle holds it, done or
    /// not (a stay at a stop already marked marks nothing else), from just behind the cursor on.
    private func matchPlan(_ p: Coordinate) -> (Day, Int)? {
        guard let day = today else { return nil }
        let done = Set((marks[day.key] ?? [:]).keys)
        return itinerary.stop(at: p, in: day, from: max(0, cursor - 2), done: done).map { (day, $0) }
    }

    /// A circle entered, usually with the app woken in the background for it: the notification is
    /// posted under a background task, so iOS does not suspend the app before it is.
    private func fenceEvent(_ fence: Fence, entered: Bool) {
        guard entered, let place = store.place(fence.placeID) else { return }
        // today by the trip's clock now: woken in the background, `today` is still the day the app was
        // suspended on. A circle of another day (tomorrow's first meal, watched from the evening
        // before; a station kept from yesterday) offers nothing of its day (`Fence.plannedItem`)
        var day: Day?
        if case .during(let d) = itinerary.phase(at: Shared.now, days: days) { day = d }
        switch fence.kind {
        case .food, .snack:
            // a planned stop not yet done can be marked from the notification
            var planned: ItemRef?
            if let d = day, let i = fence.plannedItem(today: d), !isDone(d, i), let id = fence.itemID { planned = ItemRef(day: d.key, id: id) }
            let item = planned
            BackgroundWork.run(name: "Báo khi tới quán") {
                await self.notifications.arrived(at: place, store: self.store, people: self.people, item: item)
            }
        case .station:
            // the circle's item, by its id: what was kept before a relaunch may predate an update that
            // moved it in the day
            if let day, let i = fence.plannedItem(today: day), case .move(let m) = day.items[i],
               let ride = store.ride(startingWith: m.leg.id, on: day) {
                BackgroundWork.run(name: "Báo khi tới ga") { await self.notifications.atStation(place, ride: ride, departure: m.at) }
            }
        case .stay:
            break
        }
    }

    // MARK: - Location journal

    /// A stay or a trace point may be written now (`JournalPolicy.mayRecord`): by the real clock,
    /// or the trip clock while a rehearsal writes to its own store (never when the rehearsal fell
    /// back on the real records, which happens when its store will not open).
    private var mayRecord: Bool {
        journalPolicy.mayRecord(realNow: Date(), tripNow: Shared.now, rehearsing: rehearsing && container !== records, enabled: journalEnabled)
    }

    /// Visits and significant changes in the background (`JournalPolicy`), by the trip clock while
    /// rehearsing, the real one otherwise; "Về giờ thật" refreshes, which applies the real one again.
    private func backgroundWatch() -> BackgroundWatch {
        let at = rehearsing ? Shared.now : Date()
        let always = location.isAlways
        return BackgroundWatch(
            visits: journalPolicy.wantsVisits(at: at, journal: journalEnabled, alwaysGranted: always),
            significantChanges: journalPolicy.wantsBackgroundWatch(at: at, journal: journalEnabled, alwaysGranted: always))
    }

    /// Deletes the location history (stays and trace points). Everything: from the real records
    /// (the side store, when the records would not open) and, while rehearsing, from the rehearsal's
    /// store too. With `outsideTripOnly`: what lies outside the trip's window
    /// (`JournalPolicy.window`), from the real records only, and only when they opened as usual.
    /// Returns how many rows went; 0 when a write failed, which the alert says.
    @discardableResult
    func purgeLocationHistory(outsideTripOnly: Bool) -> Int {
        purgeHistory(outsideTripOnly: outsideTripOnly, retry: { [weak self] in _ = self?.purgeLocationHistory(outsideTripOnly: outsideTripOnly) }) ?? 0
    }

    /// `purgeLocationHistory`, nil when a write failed (reported, with `retry` as its "Thử lại").
    private func purgeHistory(outsideTripOnly: Bool, retry: @escaping @MainActor () -> Void) -> Int? {
        var stores = [records.mainContext]
        if outsideTripOnly {
            // only the main store, opened as usual: never a side store or the memory
            guard Records.problem == nil else { return 0 }
        } else if container !== records {
            stores.append(context)
        }
        var deleted = 0
        for target in stores {
            guard let n = purge(target, outsideTripOnly: outsideTripOnly, retry: retry) else { return nil }
            deleted += n
        }
        return deleted
    }

    /// One store's stays and trace points deleted (all, or those outside the trip's window) and
    /// committed; nil when that failed (reported, nothing deleted from that store).
    private func purge(_ target: ModelContext, outsideTripOnly: Bool, retry: @escaping @MainActor () -> Void) -> Int? {
        do {
            let visits: [Visit], traces: [Trace]
            if outsideTripOnly {
                guard let window = journalPolicy.window else { return 0 }
                let lo = window.lowerBound, hi = window.upperBound
                visits = try target.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival < lo || $0.arrival >= hi }))
                traces = try target.fetch(FetchDescriptor<Trace>(predicate: #Predicate { $0.at < lo || $0.at >= hi }))
            } else {
                visits = try target.fetch(FetchDescriptor<Visit>())
                traces = try target.fetch(FetchDescriptor<Trace>())
            }
            guard !visits.isEmpty || !traces.isEmpty else { return 0 }
            for v in visits { target.delete(v) }
            for t in traces { target.delete(t) }
            try target.commit()
            historyDeletions += 1
            return visits.count + traces.count
        } catch {
            report("Xoá lịch sử vị trí", error as? SaveFailure ?? SaveFailure(underlying: error), retry: retry)
            return nil
        }
    }

    /// Once (`journal.purged.v1`), the history earlier builds recorded outside the trip, months of
    /// it, deleted from the real records. Only when the main store opened as usual, and marked done
    /// only once that write is on disk. Once only: a stay delivered inside the window can begin
    /// before it, and a purge run again during the trip would take it.
    private func purgeOutsideTripOnce() {
        guard Records.problem == nil, !Shared.defaults.bool(forKey: Shared.Key.journalPurged) else { return }
        guard purgeHistory(outsideTripOnly: true, retry: { [weak self] in self?.purgeOutsideTripOnce() }) != nil else { return }
        Shared.defaults.set(true, forKey: Shared.Key.journalPurged)
    }

    /// The stays and trace points in the records the app reads now, for Settings › Chẩn đoán; nil
    /// when they could not be counted.
    func locationHistoryCount() -> (visits: Int, traces: Int)? {
        guard let visits = try? context.fetchCount(FetchDescriptor<Visit>()),
              let traces = try? context.fetchCount(FetchDescriptor<Trace>()) else { return nil }
        return (visits, traces)
    }

    private func learnPace(kmh: Double, minutes: Double) {
        pace.add(activeKmh: kmh, over: minutes)
        savePace()
    }

    private func savePace() {
        if let data = try? JSONEncoder().encode(pace) { Shared.defaults.set(data, forKey: "paceModel") }
        Shared.defaults.set(pace.factor, forKey: Shared.Key.pace)
    }

    // MARK: - Widget

    private var lastSnapshot: Snapshot?

    private func publishSnapshot(force: Bool) {
        guard let day = today, let next, let itemID = day.identity(of: next.index) else {
            // forgotten, so the same item coming back is sent again
            if lastSnapshot != nil { lastSnapshot = nil }
            if Shared.snapshot != nil {
                Shared.snapshot = nil
                WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
            }
            return
        }
        let slot = slot(next.index)
        let late = replan.map(\.lateBy)
        // the plan's time to set off, late or not: a time that moved with the clock made every
        // refresh a new snapshot. Running late shows as `late` (and "Đang đi" once that time is past)
        let setOff = date(day, minutes: next.setOff)
        let snap = Snapshot(
            day: day.key, itemID: itemID, title: next.title, placeID: next.placeID,
            setOff: setOff, begin: date(day, minutes: slot?.begin ?? next.begin), kind: "\(next.kind)",
            late: late, advice: replan.flatMap { advice($0, day: day) }, generated: now)
        // lateness counts in five-minute steps (the exact minutes still go out with each snapshot sent),
        // a new advice is sent at once, and a late snapshot is sent again before the widget's half
        // hour of trusting it runs out
        let changed = lastSnapshot.map { last -> Bool in
            if last.day != snap.day || last.itemID != snap.itemID { return true }
            if Replan.lateStep(last.late) != Replan.lateStep(snap.late) || last.advice != snap.advice { return true }
            if abs(last.setOff.timeIntervalSince(snap.setOff)) > 120 { return true }
            return snap.late != nil && snap.generated.timeIntervalSince(last.generated) >= 20 * 60
        } ?? true
        guard force || changed else { return }
        lastSnapshot = snap
        Shared.snapshot = snap
        WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
    }

    /// "Bỏ Umezono thì kịp Ginza Line 16:15"
    func advice(_ plan: Replan, day: Day) -> String? {
        guard case .move(let m) = day.items[plan.target] else {
            let title = day.items[plan.target].stop?.title ?? ""
            return plan.works ? "Bỏ \(dropNames(plan, day)) thì kịp \(title)" : nil
        }
        let line = store.line(m.leg.line)?.name ?? ""
        let at = m.at ?? ""
        return plan.works ? "Bỏ \(dropNames(plan, day)) thì kịp \(line) \(at)" : "Không kịp \(line) \(at) dù bỏ bớt — đi chuyến sau"
    }

    func dropNames(_ plan: Replan, _ day: Day) -> String {
        plan.drop.compactMap { i in day.items[i].stop.flatMap { s in store.place(s.place)?.name ?? s.title } }.formatted(.list(type: .and))
    }

    // MARK: - Links

    func open(_ url: URL) {
        if let link = DeepLink(url) { navigate(link) }
    }

    func navigate(_ link: DeepLink) {
        switch link {
        case .today:
            tab = .today
        case .place(let id):
            show(.place(id))
        case .walk(let id):
            walk(to: id)
        case .ride(let id):
            show(.ride(id))
        case .day(let key):
            tab = .plan
            planPath = NavigationPath([Route.day(key)])
        case .spend(let place):
            tab = .spend
            show(.expense(placeID: place, yen: nil))
        case .journal(let key):
            show(.journal(key))
        case .menu(let id):
            show(.atPlace(id))
        }
    }

    // MARK: - Sheets

    /// Opens `sheet` over what is on screen, growing out of the control marked `sheetSource(source)`.
    /// Only the top of the stack takes touches, so whoever calls this is on top. A sheet already
    /// open further down is returned to instead of opened twice.
    func present(_ sheet: AppSheet, from source: String? = nil) {
        if let i = sheets.firstIndex(where: { $0.id == sheet.id }) {
            sheets.removeSubrange((i + 1)...)
            return
        }
        sheets.append(Presented(sheet: sheet, source: source))
    }

    /// From a link or a notification: this sheet alone, over whatever tab is showing.
    func show(_ sheet: AppSheet) {
        sheets = [Presented(sheet: sheet, source: nil)]
    }

    func dismissSheets() {
        sheets = []
    }

    /// Walking directions in Apple Maps: turn-by-turn on foot is what MapLibre cannot give.
    func walk(to placeID: String) {
        guard let p = store.place(placeID) else { return }
        walk(to: p.coordinate, named: p.ja ?? p.name)
    }

    /// The same for a point that is not a place of the trip (a sight on a hotel's walk).
    func walk(to point: Coordinate, named name: String) {
        var c = URLComponents(string: "maps://")!
        c.queryItems = [
            URLQueryItem(name: "daddr", value: "\(point.lat),\(point.lng)"),
            URLQueryItem(name: "dirflg", value: "w"),
            URLQueryItem(name: "q", value: name),
        ]
        if let url = c.url { UIApplication.shared.open(url) }
    }

    private func notificationAction(_ action: NotificationService.Action) {
        switch action {
        case .open(let link): navigate(link)
        case .startRide(let rideID):
            if let ride = store.trip.rides.first(where: { $0.id == rideID }) ?? store.trip.altRides.first(where: { $0.id == rideID }) {
                live.start(ride, model: self)
            }
        case .markArrived(let ref):
            // "Đã tới" on the lock screen wakes the app in the background. The visit as a record finds
            // it (`ItemRef.locate`); one the plan no longer has marks nothing, and its day is shown
            // instead, as for a notification from before ids
            guard let (day, i) = ref.locate(in: store) else {
                navigate(.day(ref.day))
                return
            }
            let marked = markDone(day, i, source: "fence")
            refresh(reschedule: marked)
            if marked, inBackground { finishRescheduleInBackground() }
        }
    }

    /// Background refresh: returns once reminders, geofences and alarms are set and the widget is
    /// current. iOS's time running out cancels the task: what is left of it is skipped then.
    func refreshInBackground() async {
        refresh(reschedule: false)
        guard !Task.isCancelled else { return }
        await rescheduler.flush()
        guard !Task.isCancelled else { return }
        publishSnapshot(force: true)
    }
}

/// Work iOS lets finish while the app is in the background (about half a minute): a background task
/// is held from the call until `body` is done, or until iOS says the time is up, whichever comes
/// first. `body` goes on after that until the app is suspended.
enum BackgroundWork {
    static func run(name: String, _ body: @escaping @MainActor () async -> Void) {
        let held = Held()
        // called on the main thread when the time is up
        held.id = UIApplication.shared.beginBackgroundTask(withName: name) { held.end() }
        Task {
            await body()
            held.end()
        }
    }

    /// The background task, ended once: by the work being done or by the time running out.
    private final class Held {
        var id: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
}

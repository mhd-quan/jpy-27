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
    let container: ModelContainer
    /// shown once at launch when the records could not be opened as usual (`Records.problem`)
    var storeAlert = false
    var context: ModelContext { container.mainContext }

    let location = LocationService()
    let notifications = NotificationService()
    let alarms = AlarmService()
    let live = RideLiveService()
    let motion = MotionService()
    let forecasts = ForecastService()
    let offline = OfflineMaps()
    let photos = PhotoLibrary()
    let network = NetworkStatus()

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
            refresh(reschedule: true)
        }
    }

    var clockOffset: TimeInterval = Shared.clockOffset {
        didSet {
            Shared.clockOffset = clockOffset
            refresh(reschedule: true)
        }
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
    private var lastProjected: Coordinate?

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
        container = Records.container()
        storeAlert = Records.problem != nil
        if let data = Shared.defaults.data(forKey: "paceModel"), let p = try? JSONDecoder().decode(PaceModel.self, from: data) {
            pace = p
        } else {
            pace = PaceModel()
        }
        loadRecords()
        refresh(reschedule: false)
        location.onUpdate = { [weak self] in self?.positionChanged($0) }
        location.onVisit = { [weak self] in self?.visited($0) }
        location.onFence = { [weak self] fence, entered in self?.fenceEvent(fence, entered: entered) }
        location.onAuthorizationChange = { [weak self] in self?.rescheduleAll() }
        location.onMoved = { [weak self] in self?.rescheduleAll() }
        motion.onPace = { [weak self] kmh, minutes in self?.learnPace(kmh: kmh, minutes: minutes) }
        notifications.onAction = { [weak self] in self?.notificationAction($0) }
    }

    // MARK: - Lifecycle

    /// Foreground: start the clock, resume what tracking the phase calls for, refresh schedules.
    func activate() {
        startClock()
        location.resume(for: self)
        motion.start()
        refresh(reschedule: true)
        Task {
            // reminders are the point of the app on the road: ask once, at first launch
            await notifications.refreshStatus()
            if notifications.undetermined { await notifications.requestAuthorization() }
            await HeroExporter.exportIfNeeded(store: store)
            await OfflineMaps.checkPinnedTiles()
        }
        offline.configure(store: store)
    }

    func deactivate() {
        clockTask?.cancel()
        clockTask = nil
        publishSnapshot(force: true)
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
    func refresh(reschedule: Bool) {
        let t = Shared.now
        if reschedule || Int(t.timeIntervalSince1970 / 60) != Int(now.timeIntervalSince1970 / 60) { now = t }
        let chosen = store.days(choosing: alternatives)
        if chosen.map(\.key) != days.map(\.key) { days = chosen }
        let p = itinerary.phase(at: now, days: days)
        if Self.signature(p) != Self.signature(phase) { phase = p }
        project()
        if reschedule { rescheduleAll() }
    }

    private static func signature(_ p: TripPhase) -> String {
        switch p {
        case .before(let days, let first): "before \(days) \(first.key)"
        case .during(let d): "during \(d.key)"
        case .after: "after"
        }
    }

    private func project() {
        guard let day = today, let minutes = TripTime.minutes(of: now, on: day.date) else {
            if cursor != 0 { cursor = 0 }
            if !projection.isEmpty { projection = [] }
            if replan != nil { replan = nil }
            if next != nil { next = nil }
            publishSnapshot(force: false)
            return
        }
        let done = Set((marks[day.key] ?? [:]).keys)
        // the cursor comes with the projection: by the marks, the clock, and where you stand
        let result = itinerary.project(day, done: done, now: minutes, position: position, pace: pace.factor, skips: skips[day.key] ?? [])
        if result.cursor != cursor { cursor = result.cursor }
        if result.slots != projection { projection = result.slots }
        if result.replan != replan { replan = result.replan }
        let n = itinerary.next(day, cursor: cursor)
        if n != next { next = n }
        autoStartRide(day, minutes: minutes)
        live.update(model: self)
        publishSnapshot(force: false)
    }

    /// Start following a fixed departure on its own, from twenty minutes before it: near its
    /// station or already moving like a train. iOS lets an app start a Live Activity only while it
    /// is on screen, so the window is wide (any glance at the app on the way to the platform), and
    /// the station's geofence sends a notification whose "Theo dõi chuyến" opens the app to do it.
    private func autoStartRide(_ day: Day, minutes: Double) {
        guard live.ride == nil, live.isAvailable, UIApplication.shared.applicationState == .active,
              let dep = itinerary.nextDeparture(day, cursor: cursor),
              let planned = TripTime.minutes(dep.move.at).map(Double.init),
              (planned - 20 ... planned + 10).contains(minutes),
              let ride = store.ride(startingWith: dep.move.leg.id, on: day)
        else { return }
        let nearStation = position.flatMap { p in store.place(dep.move.leg.from).map { Geo.km($0.coordinate, p) < 0.4 } } ?? false
        if nearStation || motion.riding { live.start(ride, model: self) }
    }

    /// A ride reached its end: its legs are done.
    func rideArrived(_ ride: Ride) {
        guard let day = store.day(ride.day) else { return }
        for (i, item) in day.items.enumerated() {
            if let m = item.move, ride.legs.contains(m.leg.id) { markDone(day, i, source: "ride") }
        }
        refresh(reschedule: false)
    }

    func rescheduleAll() {
        let reminders = ReminderPlanner(store: store).upcoming(days: days, now: now, pace: pace.factor)
        Task { await notifications.schedule(reminders, clockOffset: clockOffset) }
        location.updateFences(model: self)
        planWakeAlarms()
    }

    /// Alarms from the timetable for the long train rides of today and tomorrow (`WakePlanner`:
    /// 25 minutes or more on a train, never a boat, a bus or the metro), four minutes before the
    /// planned arrival, so the 7:37 Romancecar has its alarm from the evening before. Reconciled on
    /// every change of plan: rides taken, days swapped and alarms turned off are cancelled. Not on
    /// the rehearsal clock, whose times are not real ones.
    private func planWakeAlarms() {
        guard clockOffset == 0 else { return }
        let wakes = WakePlanner(store: store).wakes(days: days, now: now) { day, i in self.marks[day.key]?[i] != nil }
        Task { await alarms.planWake(wakes.map { ($0.rideID, $0.station, $0.at) }) }
    }

    /// The ride's own switch: on by default for the rides worth an alarm, off for the rest (a
    /// followed boat ride rings no one on deck unless asked to).
    func wakeAlarmIsOn(_ ride: Ride) -> Bool {
        alarms.isOn(ride.id, default: WakePlanner(store: store).isWorthAnAlarm(ride))
    }

    /// Off cancels what is set; on sets the timetable's alarm again, or the GPS one at the next
    /// position of a followed ride.
    func setWakeAlarm(_ on: Bool, for ride: Ride) {
        alarms.setOn(on, rideID: ride.id)
        if on { planWakeAlarms() }
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
    func isSkipped(_ day: Day, _ index: Int) -> Bool { skips[day.key]?.contains(index) == true }
    func doneCount(_ day: Day) -> Int { marks[day.key]?.count ?? 0 }
    func marked(_ day: Day) -> [Int: Date] { marks[day.key] ?? [:] }

    func toggleDone(_ day: Day, _ index: Int) {
        if isDone(day, index) {
            let key = day.key
            try? context.delete(model: Checkmark.self, where: #Predicate<Checkmark> { $0.day == key && $0.index == index })
            marks[day.key]?[index] = nil
        } else {
            markDone(day, index, source: "hand")
        }
        try? context.save()
        refresh(reschedule: false)
    }

    func markDone(_ day: Day, _ index: Int, at: Date? = nil, source: String) {
        guard !isDone(day, index) else { return }
        let when = at ?? now
        context.insert(Checkmark(day: day.key, index: index, at: when, source: source))
        marks[day.key, default: [:]][index] = when
        // a stop reached on foot teaches the pace: the walk before it, planned against actual,
        // timed from when the walk began, never from the arrival at the place before (that would
        // count the visit there as walking)
        if index > 0, case .move(let m) = day.items[index - 1], store.mode(of: m.leg) == .walk,
           let w = m.leg.walk, let left = walkStart(day, walk: index - 1, until: when) {
            pace.add(planned: Double(w.min), actual: when.timeIntervalSince(left) / 60)
            savePace()
        }
        try? context.save()
    }

    /// When the walk at item `walk` began, if anything recorded it: the end of the ride that
    /// brought you to its start (you step off and walk), or the departure iOS reported from the
    /// stop before it. Unknown otherwise, and then nothing is learnt from the walk.
    private func walkStart(_ day: Day, walk: Int, until: Date) -> Date? {
        guard walk > 0 else { return nil }
        switch day.items[walk - 1] {
        case .move(let m) where store.mode(of: m.leg) != .walk:
            return marks[day.key]?[walk - 1]
        case .stop(let s):
            guard let place = store.place(s.place) else { return nil }
            let since = until.addingTimeInterval(-3 * 3600)
            let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival >= since }))) ?? []
            return visits
                .filter { Presence.isAt(Coordinate($0.lat, $0.lng), place) }
                .compactMap(\.departure)
                .filter { $0 <= until }
                .max()
        default:
            return nil
        }
    }

    func toggleSkip(_ day: Day, _ index: Int) {
        let key = day.key
        if isSkipped(day, index) {
            try? context.delete(model: Skip.self, where: #Predicate<Skip> { $0.day == key && $0.index == index })
            skips[key]?.remove(index)
        } else {
            context.insert(Skip(day: key, index: index, at: now))
            skips[key, default: []].insert(index)
        }
        try? context.save()
        refresh(reschedule: true)
    }

    /// Take the replanner's advice: drop its stops.
    func apply(_ plan: Replan) {
        guard let day = today else { return }
        for i in plan.drop where !isSkipped(day, i) {
            context.insert(Skip(day: day.key, index: i, at: now))
            skips[day.key, default: []].insert(i)
        }
        try? context.save()
        refresh(reschedule: true)
    }

    private func loadRecords() {
        let checks = (try? context.fetch(FetchDescriptor<Checkmark>())) ?? []
        marks = Dictionary(grouping: checks, by: \.day).mapValues { Dictionary($0.map { ($0.index, $0.at) }, uniquingKeysWith: min) }
        let dropped = (try? context.fetch(FetchDescriptor<Skip>())) ?? []
        skips = Dictionary(grouping: dropped, by: \.day).mapValues { Set($0.map(\.index)) }
    }

    // MARK: - Money

    @discardableResult
    func logExpense(yen: Int, category: SpendCategory, method: PayMethod, placeID: String?, note: String = "", itemID: String? = nil) -> Expense {
        logExpense(yen: yen, category: category, method: method, placeID: placeID, placeName: nil, day: today?.key, note: note, itemID: itemID)
    }

    /// An expense counted toward a chosen day, at a place from the data or one named by hand.
    @discardableResult
    func logExpense(yen: Int, category: SpendCategory, method: PayMethod, placeID: String?, placeName: String?, day: String?, note: String = "", itemID: String? = nil) -> Expense {
        let e = Expense(yen: yen, category: category, method: method, placeID: placeID, placeName: placeName, day: day, note: note, at: now, coordinate: position, itemID: itemID)
        context.insert(e)
        try? context.save()
        return e
    }

    func topUp(yen: Int, method: PayMethod) {
        context.insert(Topup(yen: yen, method: method, at: now))
        try? context.save()
    }

    // MARK: - Position, visits, fences

    private func positionChanged(_ p: Coordinate) {
        if let last = lastProjected, Geo.km(last, p) < 0.03 { return }
        lastProjected = p
        if location.shouldTrace(p) { context.insert(Trace(at: now, coordinate: p)) }
        refresh(reschedule: false)
    }

    /// iOS reports a stay twice: on arrival (no departure yet), then on leaving (both times).
    /// One stay marks one stop, once: the stop it is nearest to, when it is first reported. The
    /// second report only completes the record; a stay first reported already with its departure
    /// still counts.
    private func visited(_ v: VisitRecord) {
        let from = v.arrival.addingTimeInterval(-120), to = v.arrival.addingTimeInterval(120)
        let near = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival >= from && $0.arrival <= to }))) ?? []
        if let same = near.first(where: { VisitRecord(arrival: $0.arrival, departure: $0.departure, coordinate: Coordinate($0.lat, $0.lng)).isSameStay(as: v) }) {
            if same.departure == nil { same.departure = v.departure }
            if same.placeID == nil, let (day, i) = matchPlan(v.coordinate) {
                same.placeID = day.items[i].stop?.place
                markDone(day, i, at: same.arrival, source: "visit")
            }
        } else {
            let match = matchPlan(v.coordinate)
            context.insert(Visit(arrival: v.arrival, departure: v.departure, coordinate: v.coordinate, placeID: match.flatMap { day, i in day.items[i].stop?.place }))
            if let (day, i) = match { markDone(day, i, at: v.arrival, source: "visit") }
        }
        try? context.save()
        refresh(reschedule: false)
    }

    /// Today's stop a stay belongs to: the nearest one whose `Presence` circle holds it, done or
    /// not (a stay at a stop already marked marks nothing else), from just behind the cursor on.
    private func matchPlan(_ p: Coordinate) -> (Day, Int)? {
        guard let day = today else { return nil }
        let done = Set((marks[day.key] ?? [:]).keys)
        return itinerary.stop(at: p, in: day, from: max(0, cursor - 2), done: done).map { (day, $0) }
    }

    private func fenceEvent(_ fence: Fence, entered: Bool) {
        guard entered, let place = store.place(fence.placeID) else { return }
        switch fence.kind {
        case .food, .snack:
            // a planned stop not yet done can be marked from the notification
            var planned: Int?
            if let i = fence.index, let d = store.day(fence.day), !isDone(d, i) { planned = i }
            Task { await notifications.arrived(at: place, store: store, people: people, day: planned == nil ? nil : fence.day, index: planned) }
        case .station:
            if let day = store.day(fence.day), let i = fence.index, case .move(let m) = day.items[i],
               let ride = store.ride(startingWith: m.leg.id, on: day) {
                Task { await notifications.atStation(place, ride: ride, departure: m.at) }
            }
        case .stay:
            break
        }
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
        guard let day = today, let next else {
            if Shared.snapshot != nil {
                Shared.snapshot = nil
                WidgetCenter.shared.reloadTimelines(ofKind: Shared.widgetKind)
            }
            return
        }
        let slot = slot(next.index)
        let late = replan.map(\.lateBy)
        // running late means leave now; otherwise the plan's time to set off
        let setOff = late != nil ? now : date(day, minutes: next.setOff)
        let snap = Snapshot(
            day: day.key, index: next.index, title: next.title, placeID: next.placeID,
            setOff: setOff, begin: date(day, minutes: slot?.begin ?? next.begin), kind: "\(next.kind)",
            late: late, advice: replan.flatMap { advice($0, day: day) }, generated: now)
        let changed = lastSnapshot.map { $0.index != snap.index || $0.late != snap.late || abs($0.setOff.timeIntervalSince(snap.setOff)) > 120 } ?? true
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
        var c = URLComponents(string: "maps://")!
        c.queryItems = [
            URLQueryItem(name: "daddr", value: "\(p.lat),\(p.lng)"),
            URLQueryItem(name: "dirflg", value: "w"),
            URLQueryItem(name: "q", value: p.ja ?? p.name),
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
        case .markArrived(let day, let index):
            if let d = store.day(day) { markDone(d, index, source: "fence") }
            refresh(reschedule: false)
        }
    }

    /// Background refresh: keep reminders and the widget current.
    func refreshInBackground() async {
        refresh(reschedule: true)
        publishSnapshot(force: true)
    }
}

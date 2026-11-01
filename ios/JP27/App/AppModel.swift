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
    var sheet: AppSheet?
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
    func refresh(reschedule: Bool) {
        now = Shared.now
        days = store.days(choosing: alternatives)
        phase = itinerary.phase(at: now, days: days)
        project()
        if reschedule { rescheduleAll() }
    }

    private func project() {
        guard let day = today, let minutes = TripTime.minutes(of: now, on: day.date) else {
            cursor = 0
            projection = []
            replan = nil
            next = nil
            publishSnapshot(force: false)
            return
        }
        let done = Set(marks[day.key]?.keys.map { $0 } ?? [])
        let result = itinerary.project(day, done: done, now: minutes, position: position, pace: pace.factor, skips: skips[day.key] ?? [])
        cursor = itinerary.cursor(day, done: done, now: minutes)
        projection = result.slots
        replan = result.replan
        next = itinerary.next(day, cursor: cursor)
        autoStartRide(day, minutes: minutes)
        live.update(model: self)
        publishSnapshot(force: false)
    }

    /// Start following a fixed departure on its own: at its time, near its station, app in use.
    private func autoStartRide(_ day: Day, minutes: Double) {
        guard live.ride == nil, live.isAvailable, UIApplication.shared.applicationState == .active,
              let dep = itinerary.nextDeparture(day, cursor: cursor),
              let planned = TripTime.minutes(dep.move.at).map(Double.init),
              (planned - 5 ... planned + 10).contains(minutes),
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
        // a stop reached on foot teaches the pace: the walk before it, planned against actual
        if index > 0, case .move(let m) = day.items[index - 1], store.mode(of: m.leg) == .walk,
           let w = m.leg.walk, let left = previousMark(day, before: index - 1) {
            pace.add(planned: Double(w.min), actual: when.timeIntervalSince(left) / 60)
            savePace()
        }
        try? context.save()
    }

    private func previousMark(_ day: Day, before index: Int) -> Date? {
        (marks[day.key] ?? [:]).filter { $0.key < index }.max { $0.key < $1.key }?.value
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
        let e = Expense(yen: yen, category: category, method: method, placeID: placeID, day: today?.key, note: note, at: now, coordinate: position, itemID: itemID)
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

    private func visited(_ v: VisitRecord) {
        let match = matchPlan(v.coordinate)
        context.insert(Visit(arrival: v.arrival, departure: v.departure, coordinate: v.coordinate, placeID: match.flatMap { day, i in day.items[i].stop?.place }))
        if let (day, i) = match, v.departure == nil { markDone(day, i, at: v.arrival, source: "visit") }
        try? context.save()
        refresh(reschedule: false)
    }

    /// The next not-done stop of today within 120 m of a point.
    private func matchPlan(_ p: Coordinate) -> (Day, Int)? {
        guard let day = today else { return nil }
        for (i, s) in day.stops where i >= max(0, cursor - 2) && !isDone(day, i) {
            if let place = store.place(s.place), Geo.km(place.coordinate, p) < 0.12 { return (day, i) }
        }
        return nil
    }

    private func fenceEvent(_ fence: Fence, entered: Bool) {
        guard entered, let place = store.place(fence.placeID) else { return }
        switch fence.kind {
        case .food, .snack:
            Task { await notifications.arrived(at: place, store: store, people: people) }
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
            sheet = .place(id)
        case .walk(let id):
            walk(to: id)
        case .ride(let id):
            sheet = .ride(id)
        case .day(let key):
            tab = .plan
            planPath = NavigationPath([Route.day(key)])
        case .spend(let place):
            tab = .spend
            sheet = .expense(placeID: place, yen: nil)
        case .journal(let key):
            sheet = .journal(key)
        case .menu(let id):
            sheet = .atPlace(id)
        }
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

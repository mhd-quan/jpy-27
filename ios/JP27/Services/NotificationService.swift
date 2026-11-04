import Foundation
import Observation
import TripKit
import UserNotifications

/// Local notifications for the plan. Departures and reservations are Time Sensitive (they break
/// through Focus); arrivals at a place are active; the evening journal is passive.
@Observable final class NotificationService: NSObject {
    enum Action {
        case open(DeepLink)
        case startRide(String)
        /// "Đã tới" on a planned food stop's notification: that visit is done
        case markArrived(ItemRef)
    }

    var onAction: ((Action) -> Void)?
    private(set) var authorized = false
    /// notifications may be shown as alerts (`.authorized` only, not provisional, which arrive quietly
    /// in the Notification Centre): a followed ride says a stop too close for an alarm in one
    /// (`RideTracker.wake`). Read at once, not awaited; kept by `refreshStatus`, which runs on every
    /// return to the app (`AppModel.activate`) and after every request.
    @ObservationIgnored private(set) var alertsAuthorized = false
    /// never asked yet
    private(set) var undetermined = true
    private let center = UNUserNotificationCenter.current()

    enum Category {
        static let departure = "departure"
        static let food = "food"
        /// a food stop of the plan: "Đã tới" marks it done from the lock screen, app closed
        static let plannedFood = "food.planned"
        static let plain = "plain"
    }

    enum ActionID {
        static let startRide = "ride.start"
        static let menu = "food.menu"
        static let spend = "food.spend"
        static let arrived = "arrived"
    }

    override init() {
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.departure, actions: [
                UNNotificationAction(identifier: ActionID.startRide, title: "Theo dõi chuyến", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "tram.fill")),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.food, actions: [
                UNNotificationAction(identifier: ActionID.menu, title: "Món nên gọi", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "fork.knife")),
                UNNotificationAction(identifier: ActionID.spend, title: "Ghi chi", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "yensign")),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.plannedFood, actions: [
                UNNotificationAction(identifier: ActionID.arrived, title: "Đã tới", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark")),
                UNNotificationAction(identifier: ActionID.menu, title: "Món nên gọi", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "fork.knife")),
                UNNotificationAction(identifier: ActionID.spend, title: "Ghi chi", options: [.foreground], icon: UNNotificationActionIcon(systemImageName: "yensign")),
            ], intentIdentifiers: []),
        ])
        Task { await refreshStatus() }
    }

    func refreshStatus() async {
        let settings = await center.notificationSettings()
        authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        alertsAuthorized = settings.authorizationStatus == .authorized
        undetermined = settings.authorizationStatus == .notDetermined
    }

    func requestAuthorization() async {
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        undetermined = false
        // what the answer left, for `alertsAuthorized`
        await refreshStatus()
    }

    // MARK: Plan reminders

    /// bumped by every `schedule`: a call still queued behind another when a newer one comes is
    /// skipped, since the newer one makes the pending reminders match a plan at least as recent
    @ObservationIgnored private var generation = 0
    /// the call making the pending reminders match, which the next one waits for
    @ObservationIgnored private var scheduling: Task<Void, Never>?

    /// Make the plan's pending reminders match `reminders`. Fire times are trip time; when rehearsing
    /// with a shifted clock they are moved back onto the real clock. Interval triggers stay right
    /// across time zones.
    ///
    /// Calls run one after another, and one overtaken while it waits its turn is skipped: two calls
    /// side by side could read the pending list before the other's removals and additions landed,
    /// and leave an older plan's reminder pending. Only what changed is touched: a reminder already
    /// pending with the same text and (to the half minute) the same time is left as it is, so a
    /// return to the app re-adds nothing.
    func schedule(_ reminders: [Reminder], clockOffset: TimeInterval) async {
        generation += 1
        let mine = generation
        let before = scheduling
        let task = Task {
            await before?.value
            guard mine == generation else { return }
            await replace(with: reminders, clockOffset: clockOffset)
        }
        scheduling = task
        await task.value
    }

    private func replace(with reminders: [Reminder], clockOffset: TimeInterval) async {
        let pending = await center.pendingNotificationRequests()
        // by identifier: the reminder and its fire time on the real clock
        var wanted: [String: (reminder: Reminder, fire: Date)] = [:]
        for r in reminders {
            let real = r.fire.addingTimeInterval(-clockOffset)
            guard real.timeIntervalSinceNow > 1 else { continue }
            wanted["plan.\(r.id)"] = (r, real)
        }
        var stale: [String] = []
        var kept = Set<String>()
        for old in pending where old.identifier.hasPrefix("plan.") {
            if let w = wanted[old.identifier], Self.same(old, content(w.reminder, fire: w.fire)) {
                kept.insert(old.identifier)
            } else {
                stale.append(old.identifier)
            }
        }
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
        for (id, w) in wanted where !kept.contains(id) {
            let interval = w.fire.timeIntervalSinceNow
            guard interval > 1 else { continue }
            // made here, just before it is handed over, as each request always was
            let request = UNNotificationRequest(identifier: id, content: content(w.reminder, fire: w.fire), trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try? await center.add(request)
        }
    }

    /// A pending request that would show what `new` shows, at the same time. The time is the one
    /// written into the content (`fire`): an interval trigger read back from the pending list
    /// reports its next date counted from now, not from when it was set.
    private static func same(_ old: UNNotificationRequest, _ new: UNNotificationContent) -> Bool {
        let a = old.content
        guard a.title == new.title, a.body == new.body,
              a.interruptionLevel == new.interruptionLevel,
              a.categoryIdentifier == new.categoryIdentifier,
              let at = (a.userInfo["fire"] as? String).flatMap({ Double($0) }),
              let bt = (new.userInfo["fire"] as? String).flatMap({ Double($0) })
        else { return false }
        return abs(at - bt) < 30 && (a.userInfo["link"] as? String) == (new.userInfo["link"] as? String)
    }

    /// `sending`: a new content the caller owns, so the request made from it can be handed to the
    /// notification center's async `add` (a main-actor result otherwise stays on the main actor).
    private func content(_ r: Reminder, fire: Date) -> sending UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = r.title
        content.body = r.body
        content.threadIdentifier = r.day.map { "day-\($0)" } ?? "trip"
        content.interruptionLevel = switch r.level {
        case .timeSensitive: .timeSensitive
        case .active: .active
        case .passive: .passive
        }
        content.relevanceScore = r.level == .timeSensitive ? 1 : r.level == .active ? 0.6 : 0.2
        content.sound = r.level == .passive ? nil : .default
        var info: [String: String] = ["fire": String(fire.timeIntervalSince1970)]
        switch r.kind {
        case .departure:
            content.categoryIdentifier = Category.departure
            if let day = r.day, let id = r.itemID, let d = AppModel.shared.store.day(day), let i = d.index(of: id), case .move(let m) = d.items[i],
               let ride = AppModel.shared.store.ride(startingWith: m.leg.id, on: d) {
                info["ride"] = ride.id
                info["link"] = DeepLink.ride(ride.id).url.absoluteString
            } else {
                info["link"] = DeepLink.today.url.absoluteString
            }
        case .reservation:
            content.categoryIdentifier = Category.plain
            info["link"] = r.placeID.map { DeepLink.place($0).url.absoluteString } ?? DeepLink.today.url.absoluteString
        case .journal:
            content.categoryIdentifier = Category.plain
            info["link"] = r.day.map { DeepLink.journal($0).url.absoluteString } ?? DeepLink.today.url.absoluteString
        case .morning, .booking:
            content.categoryIdentifier = Category.plain
            info["link"] = DeepLink.today.url.absoluteString
        }
        content.userInfo = info
        return content
    }

    // MARK: Location-triggered

    /// Near a restaurant or a snack stop: what to order, how to pay, what it will cost.
    /// Near a food place: what to order and how to pay. For a stop of the plan (`item`), "Đã tới"
    /// marks it done without opening the app, for when iOS is slow to report the visit.
    func arrived(at place: Place, store: TripStore, people: Int, item: ItemRef? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = place.name
        var lines: [String] = []
        if let top = (place.menu?.items ?? []).sorted(by: { $0.rank < $1.rank }).first {
            lines.append("Nên gọi \(top.ja) — \(top.shortVi)" + (top.yen.map { " \(Fmt.yen($0))" } ?? ""))
        } else if let get = place.snack?.get.first {
            lines.append("Nên mua \(get.ja) — \(get.vi)" + (get.yen.map { " \(Fmt.yen($0))" } ?? ""))
        }
        switch place.payment {
        case .cash: lines.append("Chỉ tiền mặt")
        case .card: lines.append("Trả thẻ được")
        default: break
        }
        if let est = Spend.estimate(stop: nil, place: place, people: people) { lines.append("Dự kiến \(est.label)") }
        content.body = lines.joined(separator: " · ")
        content.categoryIdentifier = item != nil ? Category.plannedFood : Category.food
        content.interruptionLevel = .active
        content.relevanceScore = 0.8
        content.sound = .default
        content.threadIdentifier = "nearby"
        var info: [String: Any] = ["link": DeepLink.menu(place.id).url.absoluteString, "place": place.id]
        // the visit by its id (`ItemRef.userInfo`), which still names it after an update moved it
        for (key, value) in item?.userInfo ?? [:] { info[key] = value }
        content.userInfo = info
        try? await center.add(UNNotificationRequest(identifier: "near.\(place.id)", content: content, trigger: nil))
    }

    #if DEBUG
    /// Settings › Chẩn đoán: a planned food stop's notification as builds before item ids posted it,
    /// its "Đã tới" carrying the day and the item's index only (the old keys spelled here on purpose),
    /// for the device checks of Task 2.1c (docs/superpowers/checklists/2026-11-device-phase1-3.md).
    func arrivedAsBeforeIDs(at place: Place, day: String, index: Int) async {
        let content = UNMutableNotificationContent()
        content.title = place.name
        content.body = "Thử: thông báo kiểu cũ, ngày \(day), mục \(index)"
        content.categoryIdentifier = Category.plannedFood
        content.interruptionLevel = .active
        content.sound = .default
        content.threadIdentifier = "nearby"
        content.userInfo = ["link": DeepLink.menu(place.id).url.absoluteString, "place": place.id, "day": day, "index": index]
        try? await center.add(UNNotificationRequest(identifier: "near.\(place.id)", content: content, trigger: nil))
    }
    #endif

    /// At the boarding station of a fixed departure: which train, which side, start the Live Activity.
    func atStation(_ station: Place, ride: Ride, departure: String?) async {
        let content = UNMutableNotificationContent()
        content.title = "\(ride.title)" + (departure.map { " \($0)" } ?? "")
        content.body = ["Ở \(station.name)", ride.seatVerdict].compactMap { $0 }.joined(separator: " · ")
        content.categoryIdentifier = Category.departure
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.sound = .default
        content.userInfo = ["link": DeepLink.ride(ride.id).url.absoluteString, "ride": ride.id]
        try? await center.add(UNNotificationRequest(identifier: "station.\(ride.id)", content: content, trigger: nil))
    }

    /// On a followed ride, the stop before yours too close for an alarm (`RideTracker.wake`): said
    /// now, as the alarm would have said it.
    func alightSoon(_ ride: Ride) async {
        let content = UNMutableNotificationContent()
        content.title = "Sắp tới \(ride.toName)"
        content.body = ride.alight?.announce ?? "Chuẩn bị xuống"
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1
        content.sound = .default
        content.userInfo = ["link": DeepLink.ride(ride.id).url.absoluteString, "ride": ride.id]
        try? await center.add(UNNotificationRequest(identifier: "alight.\(ride.id)", content: content, trigger: nil))
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let link = (info["link"] as? String).flatMap(URL.init(string:))
        let ride = info["ride"] as? String
        let place = info["place"] as? String
        let item = ItemRef.arrived(from: info)
        let day = ItemRef.arrivedDay(from: info)
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case ActionID.startRide:
                if let ride { self.onAction?(.startRide(ride)) }
            case ActionID.arrived:
                // one posted before items had ids carries only an index, which an update may have
                // given to another item: its day is shown (once the app is opened), nothing is marked
                if let item {
                    self.onAction?(.markArrived(item))
                } else if let day {
                    self.onAction?(.open(.day(day)))
                }
            case ActionID.spend:
                self.onAction?(.open(.spend(place: place)))
            case ActionID.menu:
                if let place { self.onAction?(.open(.menu(place))) }
            default:
                if let link, let l = DeepLink(link) { self.onAction?(.open(l)) }
            }
        }
    }
}

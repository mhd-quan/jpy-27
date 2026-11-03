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
        case markArrived(day: String, index: Int)
    }

    var onAction: ((Action) -> Void)?
    private(set) var authorized = false
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
        undetermined = settings.authorizationStatus == .notDetermined
    }

    func requestAuthorization() async {
        authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        undetermined = false
    }

    // MARK: Plan reminders

    /// Replace the plan's pending reminders. Fire times are trip time; when rehearsing with a shifted
    /// clock they are moved back onto the real clock. Interval triggers stay right across time zones.
    func schedule(_ reminders: [Reminder], clockOffset: TimeInterval) async {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("plan.") })
        for r in reminders {
            let real = r.fire.addingTimeInterval(-clockOffset)
            let interval = real.timeIntervalSinceNow
            guard interval > 1 else { continue }
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
            var info: [String: String] = [:]
            switch r.kind {
            case .departure:
                content.categoryIdentifier = Category.departure
                if let day = r.day, let i = r.index, let d = AppModel.shared.store.day(day), case .move(let m) = d.items[i],
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
            let request = UNNotificationRequest(identifier: "plan.\(r.id)", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try? await center.add(request)
        }
    }

    // MARK: Location-triggered

    /// Near a restaurant or a snack stop: what to order, how to pay, what it will cost.
    /// Near a food place: what to order and how to pay. For a stop of the plan (`day`, `index`),
    /// "Đã tới" marks it done without opening the app, for when iOS is slow to report the visit.
    func arrived(at place: Place, store: TripStore, people: Int, day: String? = nil, index: Int? = nil) async {
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
        content.categoryIdentifier = day != nil && index != nil ? Category.plannedFood : Category.food
        content.interruptionLevel = .active
        content.relevanceScore = 0.8
        content.sound = .default
        content.threadIdentifier = "nearby"
        var info: [String: Any] = ["link": DeepLink.menu(place.id).url.absoluteString, "place": place.id]
        if let day, let index {
            info["day"] = day
            info["index"] = index
        }
        content.userInfo = info
        try? await center.add(UNNotificationRequest(identifier: "near.\(place.id)", content: content, trigger: nil))
    }

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
        let day = info["day"] as? String
        let index = info["index"] as? Int
        let action = response.actionIdentifier
        await MainActor.run {
            switch action {
            case ActionID.startRide:
                if let ride { self.onAction?(.startRide(ride)) }
            case ActionID.arrived:
                if let day, let index { self.onAction?(.markArrived(day: day, index: index)) }
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

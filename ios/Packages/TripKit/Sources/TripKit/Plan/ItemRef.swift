import Foundation

/// One visit of the plan, by day and id: what a notification, a geofence or the widget points at, and
/// what still points at the same visit after an update moved it in the day.
public struct ItemRef: Codable, Hashable, Sendable {
    public let day: String
    public let id: String

    public init(day: String, id: String) {
        self.day = day
        self.id = id
    }

    /// What a "Đã tới" notification carries for the visit, beside its link and place.
    public var userInfo: [String: String] { ["day": day, "item": id] }

    /// The visit a "Đã tới" notification is for. One posted before items had ids carries only the
    /// item's index, which an update may have given to another item: nil, so nothing is marked.
    public static func arrived(from info: [AnyHashable: Any]) -> ItemRef? {
        guard let day = info["day"] as? String, let id = info["item"] as? String else { return nil }
        return ItemRef(day: day, id: id)
    }
}

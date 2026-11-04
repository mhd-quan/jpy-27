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
        guard let day = arrivedDay(from: info), let id = info["item"] as? String else { return nil }
        return ItemRef(day: day, id: id)
    }

    /// Where the visit is on `store`'s plan now, its day and its item's index: by its id, through the
    /// renames an update shipped for that day (`Trip.idRenames`), as a record finds its item. nil when
    /// the plan no longer has it: then nothing is marked, and the app opens its day instead.
    public func locate(in store: TripStore) -> (day: Day, index: Int)? {
        guard let day = store.day(day),
              let index = day.index(of: day.renamed(id, renames: store.trip.idRenames[day.key] ?? [:]))
        else { return nil }
        return (day, index)
    }

    /// The day a "Đã tới" notification is for, whether or not it names the visit: one posted before
    /// items had ids opens its day instead of marking anything.
    public static func arrivedDay(from info: [AnyHashable: Any]) -> String? {
        info["day"] as? String
    }
}

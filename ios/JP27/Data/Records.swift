import Foundation
import SwiftData
import TripKit

// What the travellers record during the trip. The plan itself never changes on the phone; these
// sit beside it and refer to it by day key, item index and place id.

/// A plan item done: a stop visited, a ride taken. Marked by hand, by a geofence, or by a visit.
@Model final class Checkmark {
    #Unique<Checkmark>([\.day, \.index])
    var day: String
    var index: Int
    var at: Date
    /// hand, fence, visit
    var source: String

    init(day: String, index: Int, at: Date, source: String = "hand") {
        self.day = day
        self.index = index
        self.at = at
        self.source = source
    }
}

/// A stop dropped on the day, usually on the replanner's advice.
@Model final class Skip {
    #Unique<Skip>([\.day, \.index])
    var day: String
    var index: Int
    var at: Date

    init(day: String, index: Int, at: Date) {
        self.day = day
        self.index = index
        self.at = at
    }
}

/// Money spent, for the party, in yen.
@Model final class Expense {
    var id: UUID
    var yen: Int
    /// SpendCategory raw value
    var category: String
    /// PayMethod raw value
    var method: String
    var placeID: String?
    /// a place the data does not have, named by hand
    var placeName: String?
    /// the trip day it counts toward (it may be logged later)
    var day: String?
    var note: String
    var at: Date
    var lat: Double?
    var lng: Double?
    /// a basket or catalogue item this pays for
    var itemID: String?

    init(yen: Int, category: SpendCategory, method: PayMethod, placeID: String? = nil, placeName: String? = nil, day: String? = nil, note: String = "", at: Date, coordinate: Coordinate? = nil, itemID: String? = nil) {
        id = UUID()
        self.yen = yen
        self.category = category.rawValue
        self.method = method.rawValue
        self.placeID = placeID
        self.placeName = placeName
        self.day = day
        self.note = note
        self.at = at
        lat = coordinate?.lat
        lng = coordinate?.lng
        self.itemID = itemID
    }

    var spendCategory: SpendCategory { SpendCategory(rawValue: category) ?? .extra }
    var payMethod: PayMethod { PayMethod(rawValue: method) ?? .cash }
}

/// Money moved, not spent: cash withdrawn at an ATM, Suica topped up.
@Model final class Topup {
    var id: UUID
    var yen: Int
    /// cash or ic
    var method: String
    var at: Date

    init(yen: Int, method: PayMethod, at: Date) {
        id = UUID()
        self.yen = yen
        self.method = method.rawValue
        self.at = at
    }
}

/// A basket or catalogue item bought.
@Model final class Purchase {
    #Unique<Purchase>([\.itemID])
    var itemID: String
    var qty: Int
    var yen: Int?
    var placeID: String?
    var at: Date

    init(itemID: String, qty: Int, yen: Int?, placeID: String?, at: Date) {
        self.itemID = itemID
        self.qty = qty
        self.yen = yen
        self.placeID = placeID
        self.at = at
    }
}

/// A stay Core Location noticed (CLVisit).
@Model final class Visit {
    var arrival: Date
    var departure: Date?
    var lat: Double
    var lng: Double
    /// the plan place it matched, if any
    var placeID: String?

    init(arrival: Date, departure: Date?, coordinate: Coordinate, placeID: String?) {
        self.arrival = arrival
        self.departure = departure
        lat = coordinate.lat
        lng = coordinate.lng
        self.placeID = placeID
    }

    var record: VisitRecord { VisitRecord(arrival: arrival, departure: departure, coordinate: Coordinate(lat, lng)) }
}

/// A sparse location sample (one per ~80 m or per few minutes) for the day's heatmap.
@Model final class Trace {
    var at: Date
    var lat: Double
    var lng: Double

    init(at: Date, coordinate: Coordinate) {
        self.at = at
        lat = coordinate.lat
        lng = coordinate.lng
    }

    var coordinate: Coordinate { Coordinate(lat, lng) }
}

enum Records {
    static let schema = Schema([Checkmark.self, Skip.self, Expense.self, Topup.self, Purchase.self, Visit.self, Trace.self])

    /// In the App Group, so the widget could read it later; one store for everything recorded.
    static func container() -> ModelContainer {
        // without the App Group (a profile that grants another group, or none) keep the records in
        // the app's own container: on disk, only the widget cannot see them
        let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroup) != nil
        let config = ModelConfiguration("Trip", schema: schema, groupContainer: shared ? .identifier(Shared.appGroup) : .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // a schema the store cannot migrate: keep the app usable rather than crash on launch
            return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        }
    }
}

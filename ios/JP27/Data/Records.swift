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
    /// nil when logged on this phone; else the install it was merged from (`SpendLedgerFile`).
    /// Counted in the budget, not in this phone's purses.
    var device: String?

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

    /// What went wrong opening the records, said plainly to the user; nil when all is well.
    private(set) static var problem: String?
    /// the file the user can send for a rescue when the main store would not open
    private(set) static var unreadable: URL?

    private static var folder: URL { URL.applicationSupportDirectory }
    static var mainURL: URL { folder.appending(path: "Trip.store") }
    private static var sideURL: URL { folder.appending(path: "Trip-side.store") }

    /// The records, on disk, in the app's own container: the widget reads a snapshot, never this
    /// store, so it has no reason to live in the App Group, whose name follows the signing profile
    /// (sign another way and a group store is simply gone).
    ///
    /// Never quietly in memory: if the store will not open (say an update changed a model in a way
    /// SwiftData cannot migrate; add only optional properties, or ones with a default, unless a
    /// `SchemaMigrationPlan` comes with the change), the file is left exactly as it is, what is
    /// recorded from then on goes to a side store on disk, and `problem` says so. Once the main
    /// store opens again, the side store's records are folded back in.
    static func container() -> ModelContainer {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        adoptGroupStore()
        do {
            let main = try ModelContainer(for: schema, configurations: [ModelConfiguration("Trip", schema: schema, url: mainURL)])
            foldSideStore(into: main)
            return main
        } catch {
            unreadable = mainURL
            do {
                let side = try ModelContainer(for: schema, configurations: [ModelConfiguration("TripSide", schema: schema, url: sideURL)])
                problem = "Không mở được sổ ghi chép cũ. Dữ liệu cũ vẫn còn nguyên trong máy, chưa bị xoá; từ giờ app ghi vào một sổ phụ và sẽ gộp lại khi sổ cũ mở được. Lỗi: \(error.localizedDescription)"
                return side
            } catch {
                problem = "Không mở được sổ ghi chép nào trên máy. Những gì ghi từ giờ chỉ giữ tới khi tắt app. Lỗi: \(error.localizedDescription)"
                return try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
            }
        }
    }

    /// Builds before this one kept the store in the App Group: copy it over once, if this build can
    /// still see that group. The group's copy is left in place.
    private static func adoptGroupStore() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: mainURL.path),
              let group = fm.containerURL(forSecurityApplicationGroupIdentifier: Shared.appGroup)
        else { return }
        let old = group.appending(path: "Library/Application Support/Trip.store")
        guard fm.fileExists(atPath: old.path) else { return }
        for suffix in ["", "-shm", "-wal"] {
            let from = URL(fileURLWithPath: old.path + suffix), to = URL(fileURLWithPath: mainURL.path + suffix)
            if fm.fileExists(atPath: from.path) { try? fm.copyItem(at: from, to: to) }
        }
    }

    /// Records written to the side store while the main one would not open, moved into it; the
    /// side store is then set aside (renamed, not deleted).
    private static func foldSideStore(into main: ModelContainer) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: sideURL.path),
              let side = try? ModelContainer(for: schema, configurations: [ModelConfiguration("TripSide", schema: schema, url: sideURL)])
        else { return }
        let from = ModelContext(side), to = ModelContext(main)
        for e in (try? from.fetch(FetchDescriptor<Expense>())) ?? [] {
            let id = e.id
            guard ((try? to.fetchCount(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id }))) ?? 0) == 0 else { continue }
            to.insert(e.copy())
        }
        for t in (try? from.fetch(FetchDescriptor<Topup>())) ?? [] {
            let id = t.id
            guard ((try? to.fetchCount(FetchDescriptor<Topup>(predicate: #Predicate { $0.id == id }))) ?? 0) == 0 else { continue }
            let copy = Topup(yen: t.yen, method: PayMethod(rawValue: t.method) ?? .cash, at: t.at)
            copy.id = t.id
            to.insert(copy)
        }
        // unique by day and index, or by item: inserting one that exists updates it
        for c in (try? from.fetch(FetchDescriptor<Checkmark>())) ?? [] { to.insert(Checkmark(day: c.day, index: c.index, at: c.at, source: c.source)) }
        for k in (try? from.fetch(FetchDescriptor<Skip>())) ?? [] { to.insert(Skip(day: k.day, index: k.index, at: k.at)) }
        for p in (try? from.fetch(FetchDescriptor<Purchase>())) ?? [] { to.insert(Purchase(itemID: p.itemID, qty: p.qty, yen: p.yen, placeID: p.placeID, at: p.at)) }
        for v in (try? from.fetch(FetchDescriptor<Visit>())) ?? [] { to.insert(Visit(arrival: v.arrival, departure: v.departure, coordinate: Coordinate(v.lat, v.lng), placeID: v.placeID)) }
        for t in (try? from.fetch(FetchDescriptor<Trace>())) ?? [] { to.insert(Trace(at: t.at, coordinate: t.coordinate)) }
        guard (try? to.save()) != nil else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-shm", "-wal"] {
            let at = URL(fileURLWithPath: sideURL.path + suffix)
            if fm.fileExists(atPath: at.path) {
                try? fm.moveItem(at: at, to: folder.appending(path: "Trip-side-merged-\(stamp).store" + suffix))
            }
        }
    }
}

extension Expense {
    /// The same expense, for another store: same id, so it is never counted twice.
    func copy() -> Expense {
        let c = Expense(yen: yen, category: spendCategory, method: payMethod, placeID: placeID, placeName: placeName,
                        day: day, note: note, at: at, coordinate: lat.flatMap { la in lng.map { Coordinate(la, $0) } }, itemID: itemID)
        c.id = id
        c.device = device
        return c
    }
}

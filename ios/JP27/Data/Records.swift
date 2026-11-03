import Foundation
import SwiftData
import TripKit

// What the travellers record during the trip. The plan itself never changes on the phone; these
// sit beside it and refer to it by day key, item index and place id. An update can change the plan,
// so a mark or a skip also keeps which item it is for (`Day.identity`), and is put back on that
// item when the plan around it moved (`AppModel.loadRecords`).

/// A plan item done: a stop visited, a ride taken. Marked by hand, by a geofence, or by a visit.
@Model final class Checkmark {
    #Unique<Checkmark>([\.day, \.index])
    var day: String
    var index: Int
    var at: Date
    /// hand, fence, visit
    var source: String
    /// the item it is for (`Day.identity(of:)`); nil on rows from builds that did not keep it.
    /// Optional, so the store migrates without a plan.
    var identity: String?

    init(day: String, index: Int, at: Date, source: String = "hand", identity: String? = nil) {
        self.day = day
        self.index = index
        self.at = at
        self.source = source
        self.identity = identity
    }
}

/// A stop dropped on the day, usually on the replanner's advice.
@Model final class Skip {
    #Unique<Skip>([\.day, \.index])
    var day: String
    var index: Int
    var at: Date
    /// as `Checkmark.identity`
    var identity: String?

    init(day: String, index: Int, at: Date, identity: String? = nil) {
        self.day = day
        self.index = index
        self.at = at
        self.identity = identity
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
    /// nil when logged on this phone; else the install it came from (`LedgerSync`, `SpendLedgerFile`).
    /// Counted in the budget, not in this phone's purses.
    var device: String?
    /// When it was last written (logged or edited), by the real clock: the later write wins when the
    /// two phones merge. nil on rows from before edits were dated.
    var updatedAt: Date?

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
        updatedAt = Date()
    }

    var spendCategory: SpendCategory { SpendCategory(rawValue: category) ?? .extra }
    var payMethod: PayMethod { PayMethod(rawValue: method) ?? .cash }
}

/// An expense deleted: kept so the deletion reaches the other phone, and the other phone's copy
/// does not bring the row back (`LedgerMerge`).
@Model final class ExpenseTombstone {
    #Unique<ExpenseTombstone>([\.id])
    var id: UUID
    var at: Date
    /// the row it was taken for a copy of, when it went as one logged on both phones
    var duplicateOf: UUID?
    /// the row as it was (JSON `LedgerRecord`), to bring back one wrongly taken for a copy
    var record: Data?

    init(id: UUID, at: Date, duplicateOf: UUID? = nil, record: Data? = nil) {
        self.id = id
        self.at = at
        self.duplicateOf = duplicateOf
        self.record = record
    }
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
    static let schema = Schema([Checkmark.self, Skip.self, Expense.self, ExpenseTombstone.self, Topup.self, Purchase.self, Visit.self, Trace.self])

    /// What went wrong opening the records, said plainly to the user; nil when all is well.
    private(set) static var problem: String?
    /// the file the user can send for a rescue when the main store would not open
    private(set) static var unreadable: URL?

    #if DEBUG
    /// Settings › Chẩn đoán › "Giả lỗi lưu": while on, every `commit` fails, before anything is
    /// written, as a full disk would. The two best-effort copies (the side store folded in, the
    /// rehearsal's copy) do not commit and are left alone. Off at every launch.
    static var failSaves = false
    #endif

    private static var folder: URL { URL.applicationSupportDirectory }
    static var mainURL: URL { folder.appending(path: "Trip.store") }
    private static var sideURL: URL { folder.appending(path: "Trip-side.store") }
    private static var rehearsalURL: URL { folder.appending(path: "Trip-rehearsal.store") }

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
        let to = ModelContext(main)
        copyRecords(from: ModelContext(side), to: to, history: true)
        guard (try? to.save()) != nil else { return } // save: best-effort, the side store stays and is folded in at the next launch
        let stamp = Int(Date().timeIntervalSince1970)
        for suffix in ["", "-shm", "-wal"] {
            let at = URL(fileURLWithPath: sideURL.path + suffix)
            if fm.fileExists(atPath: at.path) {
                try? fm.moveItem(at: at, to: folder.appending(path: "Trip-side-merged-\(stamp).store" + suffix))
            }
        }
    }

    // MARK: - Rehearsal

    /// The records a rehearsal writes to (`AppModel.clockOffset`): a store of its own, beside the
    /// real one. It starts as a copy of the real records (expenses, top-ups, purchases, stops done and
    /// dropped, not the location history), takes everything recorded while the shifted clock runs,
    /// and is thrown away when the clock goes back to real time. So a day walked through today is not
    /// half done when it comes in October 2027, a stop dropped while practising stays in the plan,
    /// and practice spending never reaches the budget or the other phone.
    ///
    /// `fresh` starts it again from the real records; otherwise one left by a rehearsal still
    /// running when the app was closed is picked up. If the store will not open, the rehearsal runs
    /// in memory: still apart from the real records, only gone when the app quits.
    static func rehearsal(copying real: ModelContainer, fresh: Bool) -> ModelContainer {
        if fresh { discardRehearsal() }
        let existed = FileManager.default.fileExists(atPath: rehearsalURL.path)
        let container = (try? ModelContainer(for: schema, configurations: [ModelConfiguration("TripRehearsal", schema: schema, url: rehearsalURL)]))
            ?? (try? ModelContainer(for: schema, configurations: [ModelConfiguration("TripRehearsalMemory", schema: schema, isStoredInMemoryOnly: true)]))
            ?? real
        guard container !== real else { return real }
        if !existed || container.configurations.first?.isStoredInMemoryOnly == true {
            let to = ModelContext(container)
            copyRecords(from: real.mainContext, to: to, history: false)
            try? to.save() // save: best-effort, a rehearsal without the copy starts from empty records, never the real ones
        }
        return container
    }

    /// The rehearsal's store, deleted. A container still open on it keeps working on the unlinked
    /// file until it goes, so this is safe while the last rehearsal's rows are still on screen.
    static func discardRehearsal() {
        let fm = FileManager.default
        for suffix in ["", "-shm", "-wal"] {
            let at = URL(fileURLWithPath: rehearsalURL.path + suffix)
            if fm.fileExists(atPath: at.path) { try? fm.removeItem(at: at) }
        }
    }

    /// Every record of one store put into another. Expenses and top-ups that exist there (by id) are
    /// left; the rest are unique by day and index, by item or by id, so inserting one that exists
    /// updates it. Visits and the location trace only with `history`.
    private static func copyRecords(from: ModelContext, to: ModelContext, history: Bool) {
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
        // unique by day and index, by item or by id: inserting one that exists updates it
        for t in (try? from.fetch(FetchDescriptor<ExpenseTombstone>())) ?? [] {
            to.insert(ExpenseTombstone(id: t.id, at: t.at, duplicateOf: t.duplicateOf, record: t.record))
        }
        for c in (try? from.fetch(FetchDescriptor<Checkmark>())) ?? [] { to.insert(Checkmark(day: c.day, index: c.index, at: c.at, source: c.source, identity: c.identity)) }
        for k in (try? from.fetch(FetchDescriptor<Skip>())) ?? [] { to.insert(Skip(day: k.day, index: k.index, at: k.at, identity: k.identity)) }
        for p in (try? from.fetch(FetchDescriptor<Purchase>())) ?? [] { to.insert(Purchase(itemID: p.itemID, qty: p.qty, yen: p.yen, placeID: p.placeID, at: p.at)) }
        guard history else { return }
        for v in (try? from.fetch(FetchDescriptor<Visit>())) ?? [] { to.insert(Visit(arrival: v.arrival, departure: v.departure, coordinate: Coordinate(v.lat, v.lng), placeID: v.placeID)) }
        for t in (try? from.fetch(FetchDescriptor<Trace>())) ?? [] { to.insert(Trace(at: t.at, coordinate: t.coordinate)) }
    }
}

// MARK: - Saving

/// A write to the records that did not reach the disk.
nonisolated struct SaveFailure: LocalizedError {
    let underlying: any Error

    var errorDescription: String? { underlying.localizedDescription }
}

#if DEBUG
/// What `Records.failSaves` makes every save fail with.
private nonisolated struct PretendFailure: LocalizedError {
    var errorDescription: String? { "Giả lỗi lưu (Chẩn đoán)" }
}
#endif

/// A write that failed, as the user is told (`AppModel.persist`): what was not saved, and why.
struct SaveIssue: Identifiable, Equatable {
    let id = UUID()
    let what: String
    let error: String
}

extension ModelContext {
    /// Writes what is waiting. A write that fails is taken back whole (`rollback`) before this
    /// throws, so what the screens read matches the disk: no view shows an expense, a mark or a
    /// merged ledger that was never written, and nothing half-written waits for the next save.
    @MainActor func commit() throws(SaveFailure) {
        #if DEBUG
        if Records.failSaves {
            rollback()
            throw SaveFailure(underlying: PretendFailure())
        }
        #endif
        do {
            try save()
        } catch {
            rollback()
            throw SaveFailure(underlying: error)
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
        c.updatedAt = updatedAt
        return c
    }
}

// MARK: - The ledger between two phones

/// The records' side of `LedgerMerge`: the ledger as plain values, and the merged ledger written back.
@MainActor enum Ledger {
    /// Pairs the travellers said are two expenses, not one logged twice (`LedgerMerge.pairKey`).
    static var kept: [String] {
        get { Shared.defaults.stringArray(forKey: "ledger.kept") ?? [] }
        set { Shared.defaults.set(newValue, forKey: "ledger.kept") }
    }

    static func state(_ context: ModelContext) -> LedgerState {
        let me = SpendLedgerFile.installID
        let rows = (try? context.fetch(FetchDescriptor<Expense>())) ?? []
        let tombs = (try? context.fetch(FetchDescriptor<ExpenseTombstone>())) ?? []
        return LedgerState(records: rows.map { $0.record(me: me) }, tombstones: tombs.map(\.value), kept: kept)
    }

    /// Writes what the merge changed; returns it. A write that fails is taken back, and none of it
    /// is kept (`ModelContext.commit`), the pairs kept apart included.
    @discardableResult
    static func apply(_ c: LedgerChanges, to context: ModelContext) throws(SaveFailure) -> LedgerChanges {
        guard !c.isEmpty else { return c }
        let me = SpendLedgerFile.installID
        for r in c.upserts {
            let id = r.id
            if let e = try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id })).first {
                e.take(r, me: me)
            } else {
                let e = Expense(yen: r.yen, category: .extra, method: .cash, at: r.at)
                e.id = r.id
                e.take(r, me: me)
                context.insert(e)
            }
        }
        for id in c.deletions {
            for e in (try? context.fetch(FetchDescriptor<Expense>(predicate: #Predicate { $0.id == id }))) ?? [] { context.delete(e) }
        }
        for t in c.tombstones {
            let id = t.id
            if let old = try? context.fetch(FetchDescriptor<ExpenseTombstone>(predicate: #Predicate { $0.id == id })).first {
                old.at = t.at
                old.duplicateOf = t.duplicateOf
                old.record = t.record.flatMap { try? JSONEncoder().encode($0) }
            } else {
                context.insert(ExpenseTombstone(t))
            }
        }
        try context.commit()
        // kept beside the records, so only once they are written
        if let k = c.kept { kept = k }
        return c
    }

    /// Merges a ledger from elsewhere (the other phone, a file) into this one; throws, with nothing
    /// of it kept, when it could not be written.
    @discardableResult
    static func merge(_ remote: LedgerState, into context: ModelContext) throws(SaveFailure) -> (merged: LedgerState, changes: LedgerChanges) {
        let local = state(context)
        let merged = LedgerMerge.merge(local, remote)
        return (merged, try apply(LedgerMerge.changes(from: local, to: merged), to: context))
    }

    /// Deletes an expense and leaves the deletion for the other phone. Not written yet: the caller
    /// saves it (`AppModel.persist`) with whatever else goes in the same write.
    static func delete(_ e: Expense, in context: ModelContext) {
        // after the row's own last write, whatever the clocks did
        let at = max(Date(), e.version.addingTimeInterval(0.001))
        let id = e.id
        if let old = try? context.fetch(FetchDescriptor<ExpenseTombstone>(predicate: #Predicate { $0.id == id })).first {
            old.at = at
        } else {
            context.insert(ExpenseTombstone(id: id, at: at))
        }
        context.delete(e)
    }

    /// Two rows said to be separate expenses: not asked again, on either phone. Kept only once what
    /// waits in the records is written; when that fails, the pair is asked about again.
    static func keepApart(_ a: UUID, _ b: UUID, in context: ModelContext) throws(SaveFailure) {
        try context.commit()
        kept = Array(Set(kept + [LedgerMerge.pairKey(a, b)])).sorted()
        // the pair travels with the ledger, outside the records: the sync is told
        LedgerSync.shared?.ledgerChanged()
    }

    /// Rows taken for the other phone's copy, newest first, that are still gone.
    static func folded(_ context: ModelContext) -> [LedgerTombstone] {
        let tombs = (try? context.fetch(FetchDescriptor<ExpenseTombstone>(predicate: #Predicate { $0.duplicateOf != nil }))) ?? []
        let alive = Set(((try? context.fetch(FetchDescriptor<Expense>())) ?? []).map(\.id))
        return tombs.map(\.value).filter { $0.record != nil && !alive.contains($0.id) }.sorted { $0.at > $1.at }
    }

    /// Brings back a row wrongly taken for a copy, and keeps the pair apart; throws, with nothing
    /// brought back, when it could not be written.
    static func restore(_ t: LedgerTombstone, in context: ModelContext) throws(SaveFailure) {
        let local = state(context)
        guard let back = LedgerMerge.restore(t, in: local, now: Date()) else { return }
        try apply(LedgerMerge.changes(from: local, to: back), to: context)
    }
}

extension Expense {
    /// The write that counts when the phones merge.
    var version: Date { updatedAt ?? at }

    /// Marks an edit made on this phone.
    func touch() {
        updatedAt = max(Date(), version.addingTimeInterval(0.001))
    }

    func record(me: String) -> LedgerRecord {
        LedgerRecord(id: id, yen: yen, category: category, method: method, placeID: placeID, placeName: placeName, day: day,
                     note: note, at: at, updatedAt: updatedAt, lat: lat, lng: lng, itemID: itemID, origin: device ?? me)
    }

    func take(_ r: LedgerRecord, me: String) {
        yen = r.yen
        category = r.category
        method = r.method
        placeID = r.placeID
        placeName = r.placeName
        day = r.day
        note = r.note
        at = r.at
        updatedAt = r.updatedAt
        lat = r.lat
        lng = r.lng
        itemID = r.itemID
        device = r.origin == me ? nil : r.origin
    }
}

extension ExpenseTombstone {
    convenience init(_ t: LedgerTombstone) {
        self.init(id: t.id, at: t.at, duplicateOf: t.duplicateOf, record: t.record.flatMap { try? JSONEncoder().encode($0) })
    }

    var value: LedgerTombstone {
        LedgerTombstone(id: id, at: at, duplicateOf: duplicateOf, record: record.flatMap { try? JSONDecoder().decode(LedgerRecord.self, from: $0) })
    }
}

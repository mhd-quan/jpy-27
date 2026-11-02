import Foundation

// The two phones keep one ledger between them with no server: each sends the other everything it
// has (expenses, the ones deleted, the pairs said not to be duplicates), each merges what it gets
// with the same rules, and both end with the same ledger whichever merged first.

/// An expense as the phones exchange it: plain values, nothing of SwiftData.
public struct LedgerRecord: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var yen: Int
    public var category: String
    public var method: String
    public var placeID: String?
    public var placeName: String?
    /// the trip day it counts toward
    public var day: String?
    public var note: String
    public var at: Date
    /// when it was last written, on the phone that wrote it; nil for rows from before edits were dated
    public var updatedAt: Date?
    public var lat: Double?
    public var lng: Double?
    public var itemID: String?
    /// the install that logged it
    public var origin: String

    public init(id: UUID, yen: Int, category: String, method: String, placeID: String? = nil, placeName: String? = nil,
                day: String? = nil, note: String = "", at: Date, updatedAt: Date? = nil, lat: Double? = nil, lng: Double? = nil,
                itemID: String? = nil, origin: String) {
        self.id = id
        self.yen = yen
        self.category = category
        self.method = method
        self.placeID = placeID
        self.placeName = placeName
        self.day = day
        self.note = note
        self.at = at
        self.updatedAt = updatedAt
        self.lat = lat
        self.lng = lng
        self.itemID = itemID
        self.origin = origin
    }

    /// Which write is the latest: the edit time, else when it was logged.
    public var version: Date { updatedAt ?? at }
}

/// An expense deleted, kept so the deletion reaches the other phone and is not undone by its copy.
public struct LedgerTombstone: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var at: Date
    /// set when the row went as the other phone's copy of this one
    public var duplicateOf: UUID?
    /// the row as it was, for bringing back a row wrongly taken for a copy
    public var record: LedgerRecord?

    public init(id: UUID, at: Date, duplicateOf: UUID? = nil, record: LedgerRecord? = nil) {
        self.id = id
        self.at = at
        self.duplicateOf = duplicateOf
        self.record = record
    }
}

/// Everything one phone knows of the ledger, in a fixed order so two equal ledgers compare equal.
public struct LedgerState: Codable, Sendable, Equatable {
    public private(set) var records: [LedgerRecord]
    public private(set) var tombstones: [LedgerTombstone]
    /// pairs the travellers said are two expenses, not one logged twice (`LedgerMerge.pairKey`)
    public private(set) var kept: [String]

    public init(records: [LedgerRecord], tombstones: [LedgerTombstone] = [], kept: [String] = []) {
        self.records = records.sorted { $0.id.uuidString < $1.id.uuidString }
        self.tombstones = tombstones.sorted { $0.id.uuidString < $1.id.uuidString }
        self.kept = Array(Set(kept)).sorted()
    }

    private enum CodingKeys: String, CodingKey { case records, tombstones, kept }

    /// Put back in order whatever order it came in, so equal ledgers stay equal.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(records: try c.decode([LedgerRecord].self, forKey: .records),
                  tombstones: try c.decodeIfPresent([LedgerTombstone].self, forKey: .tombstones) ?? [],
                  kept: try c.decodeIfPresent([String].self, forKey: .kept) ?? [])
    }

    public static let empty = LedgerState(records: [])
}

/// What a phone has to write to turn its ledger into the merged one.
public struct LedgerChanges: Sendable, Equatable {
    /// rows to insert, or to overwrite where the id exists
    public var upserts: [LedgerRecord] = []
    /// rows to remove
    public var deletions: [UUID] = []
    /// tombstones to store (new, or newer than the one stored)
    public var tombstones: [LedgerTombstone] = []
    /// the full set of pairs kept apart, when it changed
    public var kept: [String]?
    /// rows removed as the other phone's copy of one kept
    public var folded: [LedgerTombstone] = []

    public var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty && tombstones.isEmpty && kept == nil }
}

/// Two rows that may be one expense logged on both phones, for the travellers to decide.
public struct LedgerPair: Sendable, Hashable {
    public let a: UUID
    public let b: UUID
    public var key: String { LedgerMerge.pairKey(a, b) }
}

public enum LedgerMerge {
    /// Two phones logging one meal do it within this of each other.
    public static let sameMeal: TimeInterval = 3 * 3600
    /// For rows with no place, only this close counts.
    public static let sameMoment: TimeInterval = 30 * 60

    public static func pairKey(_ a: UUID, _ b: UUID) -> String {
        let (x, y) = (a.uuidString, b.uuidString)
        return x < y ? "\(x)|\(y)" : "\(y)|\(x)"
    }

    /// The ledger both phones end with. The same whichever side is `a`, and merging again changes nothing:
    /// - per id, the latest write wins (`version`; equal versions are settled by content, the same way on both);
    /// - a deletion wins over any write not newer than it, and is kept;
    /// - a meal logged on both phones (rows of different phones with the same place, category, amount and
    ///   day, within three hours) is folded into one: the row with the smaller id stays, the other goes as
    ///   its copy, unless the travellers said the two are separate.
    public static func merge(_ a: LedgerState, _ b: LedgerState) -> LedgerState {
        var tombs: [UUID: LedgerTombstone] = [:]
        for t in a.tombstones + b.tombstones {
            tombs[t.id] = tombs[t.id].map { later($0, t) } ?? t
        }
        var rows: [UUID: LedgerRecord] = [:]
        for r in a.records + b.records {
            rows[r.id] = rows[r.id].map { later($0, r) } ?? r
        }
        for (id, t) in tombs {
            if let r = rows[id], r.version <= t.at { rows[id] = nil }
        }
        let kept = Set(a.kept).union(b.kept)
        return fold(LedgerState(records: Array(rows.values), tombstones: Array(tombs.values), kept: Array(kept)))
    }

    /// The writes that turn `local` into `merged`.
    public static func changes(from local: LedgerState, to merged: LedgerState) -> LedgerChanges {
        var c = LedgerChanges()
        let had = Dictionary(local.records.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        let now = Set(merged.records.map(\.id))
        c.upserts = merged.records.filter { had[$0.id] != $0 }
        c.deletions = local.records.map(\.id).filter { !now.contains($0) }
        let stored = Dictionary(local.tombstones.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        c.tombstones = merged.tombstones.filter { stored[$0.id] != $0 }
        c.folded = c.tombstones.filter { $0.duplicateOf != nil && c.deletions.contains($0.id) }
        if merged.kept != local.kept { c.kept = merged.kept }
        return c
    }

    /// Rows of the two phones that look like one expense but differ enough to ask: the same place on the
    /// same day within three hours (another amount, say), or no place, the same kind and amount within
    /// half an hour. Pairs already kept apart are left out.
    public static func nearDuplicates(_ s: LedgerState) -> [LedgerPair] {
        var pairs: [LedgerPair] = []
        let kept = Set(s.kept)
        forEachClosePair(s.records) { a, b in
            guard a.origin != b.origin, !kept.contains(pairKey(a.id, b.id)), !isSameExpense(a, b) else { return }
            let gap = abs(a.at.timeIntervalSince(b.at))
            let placed = samePlace(a, b) && sameDay(a, b) && gap <= sameMeal
            let unplaced = !hasPlace(a) && !hasPlace(b) && a.category == b.category && a.yen == b.yen && gap <= sameMoment
            if placed || unplaced {
                let (x, y) = a.id.uuidString < b.id.uuidString ? (a.id, b.id) : (b.id, a.id)
                pairs.append(LedgerPair(a: x, b: y))
            }
        }
        return pairs.sorted { $0.key < $1.key }
    }

    /// A row folded as a copy, brought back: written now, so it outranks its deletion, and its pair is
    /// kept apart so neither phone folds it again.
    public static func restore(_ t: LedgerTombstone, in s: LedgerState, now: Date) -> LedgerState? {
        guard var r = t.record, let other = t.duplicateOf else { return nil }
        r.updatedAt = max(now, t.at.addingTimeInterval(0.001))
        var records = s.records.filter { $0.id != r.id }
        records.append(r)
        return LedgerState(records: records, tombstones: s.tombstones, kept: s.kept + [pairKey(r.id, other)])
    }

    // MARK: - Rules

    static func isSameExpense(_ a: LedgerRecord, _ b: LedgerRecord) -> Bool {
        a.origin != b.origin && a.yen == b.yen && a.category == b.category && samePlace(a, b) && sameDay(a, b)
            && abs(a.at.timeIntervalSince(b.at)) <= sameMeal
    }

    static func hasPlace(_ r: LedgerRecord) -> Bool {
        r.placeID != nil || !(r.placeName.map(normal) ?? "").isEmpty
    }

    static func samePlace(_ a: LedgerRecord, _ b: LedgerRecord) -> Bool {
        if let x = a.placeID, let y = b.placeID { return x == y }
        guard a.placeID == nil, b.placeID == nil, let x = a.placeName.map(normal), let y = b.placeName.map(normal), !x.isEmpty else { return false }
        return x == y
    }

    static func sameDay(_ a: LedgerRecord, _ b: LedgerRecord) -> Bool {
        if let x = a.day, let y = b.day { return x == y }
        return TripTime.isoDate(of: a.at) == TripTime.isoDate(of: b.at)
    }

    private static func normal(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Folds rows logged on both phones; deterministic, so both phones fold the same rows.
    static func fold(_ s: LedgerState) -> LedgerState {
        let kept = Set(s.kept)
        var candidates: [(keep: LedgerRecord, drop: LedgerRecord)] = []
        forEachClosePair(s.records) { a, b in
            guard isSameExpense(a, b), !kept.contains(pairKey(a.id, b.id)) else { return }
            candidates.append(a.id.uuidString < b.id.uuidString ? (a, b) : (b, a))
        }
        guard !candidates.isEmpty else { return s }
        candidates.sort { ($0.keep.id.uuidString, $0.drop.id.uuidString) < ($1.keep.id.uuidString, $1.drop.id.uuidString) }
        var dropped: Set<UUID> = []
        var tombs = Dictionary(s.tombstones.map { ($0.id, $0) }, uniquingKeysWith: { x, _ in x })
        for (keep, drop) in candidates where !dropped.contains(keep.id) && !dropped.contains(drop.id) {
            dropped.insert(drop.id)
            // dated at the row's own version: the deletion outranks it, and both phones write the same one
            tombs[drop.id] = LedgerTombstone(id: drop.id, at: drop.version, duplicateOf: keep.id, record: drop)
        }
        return LedgerState(records: s.records.filter { !dropped.contains($0.id) }, tombstones: Array(tombs.values), kept: s.kept)
    }

    /// Each pair of rows logged within three hours of each other, once.
    private static func forEachClosePair(_ records: [LedgerRecord], _ body: (LedgerRecord, LedgerRecord) -> Void) {
        let byTime = records.sorted { $0.at < $1.at }
        for i in byTime.indices {
            var j = i + 1
            while j < byTime.count, byTime[j].at.timeIntervalSince(byTime[i].at) <= sameMeal {
                body(byTime[i], byTime[j])
                j += 1
            }
        }
    }

    private static func later(_ x: LedgerRecord, _ y: LedgerRecord) -> LedgerRecord {
        if x.version != y.version { return x.version > y.version ? x : y }
        return tie(x) >= tie(y) ? x : y
    }

    private static func later(_ x: LedgerTombstone, _ y: LedgerTombstone) -> LedgerTombstone {
        if x.at != y.at { return x.at > y.at ? x : y }
        return (x.duplicateOf?.uuidString ?? "") >= (y.duplicateOf?.uuidString ?? "") ? x : y
    }

    /// Settles two different writes with the same time the same way on both phones.
    private static func tie(_ r: LedgerRecord) -> String {
        [String(r.yen), r.category, r.method, r.placeID ?? "", r.placeName ?? "", r.day ?? "", r.note,
         String(r.at.timeIntervalSinceReferenceDate), r.itemID ?? "", r.origin].joined(separator: "\u{1F}")
    }
}

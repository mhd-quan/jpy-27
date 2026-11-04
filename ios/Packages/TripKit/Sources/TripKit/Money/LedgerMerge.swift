import Foundation

// The two phones keep one ledger between them with no server: each sends the other everything it
// has (expenses, the ones deleted, the pairs said not to be duplicates), each merges what it gets
// with the same rules, and both end with the same ledger whichever merged first. Merging never
// drops a row on its own: two rows that look like one expense logged on both phones are asked
// about (`nearDuplicates`), because two people buying the same ¥1.200 bowl at one counter is as
// likely as one bowl logged twice.

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
    /// set when the row went as the other phone's copy of this one (builds before the travellers
    /// were always asked folded such rows by themselves; their deletions still travel)
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
    /// rows removed as the other phone's copy of one kept (only ever from an older build's merge)
    public var folded: [LedgerTombstone] = []

    public var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty && tombstones.isEmpty && kept == nil }
}

/// Two rows that may be one expense logged on both phones, for the travellers to decide.
public struct LedgerPair: Sendable, Hashable {
    public let a: UUID
    public let b: UUID
    /// same place, kind, amount and day: one payment logged twice, or two people paying the same
    public let same: Bool
    /// the row to keep if they are one payment: the one paid from a phone's own cash or Suica, whose
    /// purse already counts it (`LedgerMerge.keeper`); nil when that does not tell them apart
    public let keep: UUID?
    public var key: String { LedgerMerge.pairKey(a, b) }

    public init(a: UUID, b: UUID, same: Bool = false, keep: UUID? = nil) {
        self.a = a
        self.b = b
        self.same = same
        self.keep = keep
    }
}

/// What an expense may hold, the same however it came in: typed on the keypad, read from a file
/// (`LedgerCSV`), or sent by the other phone (`LedgerMerge.screened`).
public nonisolated enum LedgerValidation {
    public enum Problem: Sendable, Hashable {
        /// outside 1…`Yen.maxEntry`
        case amount
        /// written more than `LedgerMerge.clockSlack` ahead of this phone's clock
        case futureDate
        /// a note or place name longer than `maxText`
        case text
    }

    /// the longest note or typed place name, in characters
    public static let maxText = 500

    public static func problems(_ r: LedgerRecord, now: Date) -> Set<Problem> {
        var p = contentProblems(r)
        let limit = now.addingTimeInterval(LedgerMerge.clockSlack)
        if r.version > limit || r.at > limit { p.insert(.futureDate) }
        return p
    }

    /// The problems that do not depend on the clock (all a file can be checked for as it is read).
    static func contentProblems(_ r: LedgerRecord) -> Set<Problem> {
        var p: Set<Problem> = []
        if !Yen.isValidEntry(r.yen) { p.insert(.amount) }
        if r.note.count > maxText || (r.placeName?.count ?? 0) > maxText { p.insert(.text) }
        return p
    }
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
    /// - every row is kept otherwise: rows that look like one expense logged on both phones are left for
    ///   the travellers to settle (`nearDuplicates`), never folded here. An earlier build folded them by
    ///   itself and lost real expenses (two ¥1.200 bowls at one ticket machine became one).
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
        return LedgerState(records: Array(rows.values), tombstones: Array(tombs.values), kept: Array(kept))
    }

    /// How far ahead of this phone's clock a write may be dated: phones set by the network agree to
    /// the second, and a day covers one set by hand to the wrong date.
    public static let clockSlack: TimeInterval = 24 * 3600

    /// A ledger from elsewhere (the other phone, a file), with what this phone's keypad could not have
    /// written left out, and which rows those were. A row is left out for any `LedgerValidation`
    /// problem: an amount outside 1…`Yen.maxEntry`, a write dated more than `clockSlack` ahead of `now`,
    /// a note or place name too long. Deletions dated that far ahead are left out too: one dated 2099
    /// would outrank every write to its row from then on, so a row could never come back. Nothing
    /// already on this phone is touched: merging never drops a local row.
    public static func screened(_ s: LedgerState, now: Date) -> (state: LedgerState, rejected: [UUID]) {
        let limit = now.addingTimeInterval(clockSlack)
        var good: [LedgerRecord] = []
        var rejected: [UUID] = []
        for r in s.records {
            if LedgerValidation.problems(r, now: now).isEmpty { good.append(r) } else { rejected.append(r.id) }
        }
        return (LedgerState(records: good, tombstones: s.tombstones.filter { $0.at <= limit }, kept: s.kept), rejected)
    }

    /// What to send back for a ledger `remote` the other phone sent, given this phone's `local` (before
    /// or after merging it in: merging again changes nothing): the merged ledger when the other phone
    /// would gain something from it that this phone vouches for (what this phone's own screening, by its
    /// own clock, keeps of the merged ledger), nil when it would gain nothing. One `now` for both.
    ///
    /// So two phones may stay different on a row one of them refuses: a version past the keypad's cap
    /// or with a note too long (written before every way in was checked), or a write or deletion dated
    /// more than `clockSlack` ahead of the receiver. The phone that refuses it keeps its own version
    /// and reports the refused row (`screened`'s `rejected`). The refused row is never a reason to
    /// answer (`reply` is nil for it), and the phone that holds it sends that ledger again only at its
    /// heartbeat, until the other says it wrote it, the refused row left out
    /// (`LedgerSyncSession.needsSend`; a build before acknowledgements is sent it once), so the two
    /// never answer each other for ever.
    public static func reply(local: LedgerState, remote: LedgerState, now: Date) -> LedgerState? {
        let clean = screened(remote, now: now).state
        let merged = merge(local, clean)
        return merge(remote, sanitized(merged, now: now)) == remote ? nil : merged
    }

    /// `screened` without the list of what was left out.
    public static func sanitized(_ s: LedgerState, now: Date) -> LedgerState {
        screened(s, now: now).state
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

    /// Rows of the two phones that may be one expense, for the travellers to settle: the same place on
    /// the same day within three hours (the same amount, or another), or no place, the same kind and
    /// amount within half an hour. Pairs already kept apart are left out.
    public static func nearDuplicates(_ s: LedgerState) -> [LedgerPair] {
        var pairs: [LedgerPair] = []
        let kept = Set(s.kept)
        forEachClosePair(s.records) { a, b in
            guard a.origin != b.origin, !kept.contains(pairKey(a.id, b.id)) else { return }
            let gap = abs(a.at.timeIntervalSince(b.at))
            let placed = samePlace(a, b) && sameDay(a, b) && gap <= sameMeal
            let unplaced = !hasPlace(a) && !hasPlace(b) && a.category == b.category && a.yen == b.yen && gap <= sameMoment
            if placed || unplaced {
                let (x, y) = a.id.uuidString < b.id.uuidString ? (a, b) : (b, a)
                pairs.append(LedgerPair(a: x.id, b: y.id, same: isSameExpense(x, y) || unplaced, keep: keeper(x, y)))
            }
        }
        return pairs.sorted { $0.key < $1.key }
    }

    /// Of two rows that are one payment, the one to keep: the one paid in cash or by Suica when the
    /// other was not. A phone's purses count only the rows it logged itself, so dropping the cash row
    /// would leave that phone thinking the money is still in its wallet. Nil when both or neither came
    /// out of a purse: then only the travellers know who paid.
    public static func keeper(_ a: LedgerRecord, _ b: LedgerRecord) -> UUID? {
        let purse: (LedgerRecord) -> Bool = { $0.method == PayMethod.cash.rawValue || $0.method == PayMethod.ic.rawValue }
        switch (purse(a), purse(b)) {
        case (true, false): return a.id
        case (false, true): return b.id
        default: return nil
        }
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

    /// One payment logged on both phones, by every field the two can share.
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

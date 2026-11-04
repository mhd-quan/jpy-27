import Foundation

/// Moving the records of plan items (a stop done, a stop dropped) onto their items' new indexes,
/// in two writes that never put two records of one day on the same index, not even halfway
/// through a write.
///
/// The app keeps each record as a row unique by day and index (`#Unique` in its store). An update
/// that adds an item early in a day moves every later record up by one. Written in one go, the
/// first row to move lands on the index the next one still holds: a store that checks each row as
/// it is written refuses the write, and one that settles a clash by merging folds two records into
/// one. So the records move twice. First, every record that changes index steps aside, to an index
/// no row of its day holds: below 0 and below anything already there. Then each goes to its item's
/// index, which the first write emptied.
///
/// A record whose item is gone stays where it is, unless it sits on another record's new index.
/// Then it steps aside too and stays there; its identity still finds the item if it comes back.
///
/// A new record goes on its item's index only while no row holds it (`slots`).
public enum RecordIndexes {
    /// A row as stored, and where it belongs now.
    public struct Record: Hashable, Sendable {
        public var day: String
        public var index: Int
        /// The index of its item now; nil when the item is gone.
        public var target: Int?
        /// Taken out in the first write (one of two records of one item).
        public var deleted: Bool

        public init(day: String, index: Int, target: Int?, deleted: Bool = false) {
            self.day = day
            self.index = index
            self.target = target
            self.deleted = deleted
        }
    }

    /// The two writes, each as a record's position in the list given → the index it is given.
    public struct Moves: Equatable, Sendable {
        /// First write, with the deletions: records out of the way.
        public var aside: [Int: Int] = [:]
        /// Second write: records onto their items' indexes.
        public var home: [Int: Int] = [:]

        public var isEmpty: Bool { aside.isEmpty && home.isEmpty }
    }

    /// The moves for `records`, as the store holds them. Each day has distinct indexes, and its kept
    /// records have distinct targets: one record per item, the others deleted.
    public static func moves(_ records: [Record]) -> Moves {
        var moves = Moves()
        for rows in Dictionary(grouping: records.indices, by: { records[$0].day }).values {
            // fresh indexes, below every one the day holds, deleted rows' too
            var free = min(0, rows.map { records[$0].index }.min() ?? 0) - 1
            let kept = rows.filter { !records[$0].deleted }
            let targets = Set(kept.compactMap { records[$0].target })
            var moving: [(target: Int, row: Int)] = []
            var blocking: [(index: Int, row: Int)] = []
            for n in kept {
                if let target = records[n].target {
                    if target != records[n].index { moving.append((target, n)) }
                } else if targets.contains(records[n].index) {
                    blocking.append((records[n].index, n))
                }
            }
            for (target, n) in moving.sorted(by: { $0.target < $1.target }) {
                moves.aside[n] = free
                moves.home[n] = target
                free -= 1
            }
            for (_, n) in blocking.sorted(by: { $0.index < $1.index }) {
                moves.aside[n] = free
                free -= 1
            }
        }
        return moves
    }

    /// Where new records of items `targets` are written, in that order, on a day whose rows hold the
    /// indexes `holding`: each on its item's index while no row holds it. A row can: another item's,
    /// whose index a load has still to put right (its write failed), or one whose item is gone, which
    /// keeps its index. Written there, the store's unique day and index would make the insert an update
    /// of that row, one record put in the place of another. So such a record goes where a record set
    /// aside goes, below 0 and below every index the day holds: its identity finds its item from there,
    /// and the next load that writes brings it home (`moves`). No two of `targets` share an index.
    public static func slots(for targets: [Int], holding: [Int]) -> [Int] {
        var held = Set(holding)
        var free = min(0, holding.min() ?? 0) - 1
        return targets.map { target in
            var slot = target
            if held.contains(target) {
                slot = free
                free -= 1
            }
            held.insert(slot)
            return slot
        }
    }

    /// Where a new record of item `target` is written (`slots`).
    public static func slot(for target: Int, holding: [Int]) -> Int {
        slots(for: [target], holding: holding)[0]
    }
}

import Foundation
import Testing
@testable import TripKit

/// The two writes that move marks and skips onto their items' new indexes (`RecordIndexes`), checked
/// the way a store with a unique (day, index) checks them: one row at a time, in any order.
@Suite struct RecordIndexesTests {
    typealias Record = RecordIndexes.Record

    /// Where each row is after both writes (nil: deleted). Each write is applied one row at a time in
    /// the order `order` gives; after every single step no two live rows of a day may share an index.
    func applied(_ records: [Record], _ moves: RecordIndexes.Moves, order: ([Int]) -> [Int] = { $0 },
                 sourceLocation: SourceLocation = #_sourceLocation) -> [Int?] {
        var at: [Int?] = records.map(\.index)
        func check(_ step: String) {
            var seen: [String: Set<Int>] = [:]
            for (n, r) in records.enumerated() {
                guard let i = at[n] else { continue }
                let fresh = seen[r.day, default: []].insert(i).inserted
                #expect(fresh, "two rows of day \(r.day) on \(i) after \(step)", sourceLocation: sourceLocation)
            }
        }
        check("nothing")
        // first write: duplicates deleted, rows moved aside
        let first = (records.indices.filter { records[$0].deleted } + moves.aside.keys).sorted()
        for n in order(first) {
            at[n] = records[n].deleted ? nil : moves.aside[n]
            check("first write, row \(n)")
        }
        for n in order(moves.home.keys.sorted()) {
            at[n] = moves.home[n]
            check("second write, row \(n)")
        }
        return at
    }

    @Test func nothingMovesWhenEveryRecordIsOnItsItem() {
        let records = [Record(day: "1", index: 0, target: 0), Record(day: "1", index: 3, target: 3), Record(day: "2", index: 0, target: 0)]
        #expect(RecordIndexes.moves(records).isEmpty)
        #expect(RecordIndexes.moves([]).isEmpty)
    }

    @Test func twoRecordsSwapThroughIndexesNoRowHolds() {
        let records = [Record(day: "1", index: 0, target: 1), Record(day: "1", index: 1, target: 0)]
        let moves = RecordIndexes.moves(records)
        #expect(moves.aside == [0: -2, 1: -1])
        #expect(moves.home == [0: 1, 1: 0])
        for order in [{ (a: [Int]) in a }, { (a: [Int]) in Array(a.reversed()) }] {
            #expect(applied(records, moves, order: order) == [1, 0])
        }
    }

    /// An item added early in a day moves every later mark up by one: the common case. Written in
    /// one go, 3 → 4 lands on the row still at 4.
    @Test func aChainShiftedByAnAddedItemNeverMeetsItself() {
        let records = (3 ... 6).map { Record(day: "8", index: $0, target: $0 + 1) } + [Record(day: "8", index: 1, target: 1)]
        let moves = RecordIndexes.moves(records)
        #expect(moves.aside.count == 4)
        #expect(moves.aside[4] == nil, "a row already on its item stays")
        #expect(moves.aside.values.allSatisfy { $0 < 0 })
        for order in [{ (a: [Int]) in a }, { (a: [Int]) in Array(a.reversed()) }] {
            #expect(applied(records, moves, order: order) == [4, 5, 6, 7, 1])
        }
    }

    /// A record whose item is gone keeps its index, until another record's item comes to sit there:
    /// then it steps aside and stays aside (its identity still finds the item should it come back).
    @Test func aRecordWhoseItemIsGoneStepsAsideOnlyFromAnotherRecordsIndex() {
        let records = [
            Record(day: "8", index: 5, target: nil),  // item gone, and 6 → 5 is coming
            Record(day: "8", index: 6, target: 5),
            Record(day: "8", index: 9, target: nil),  // item gone, nothing coming
        ]
        let moves = RecordIndexes.moves(records)
        #expect(moves.aside[0] != nil)
        #expect(moves.home[0] == nil, "it has no item to go home to")
        #expect(moves.aside[2] == nil && moves.home[2] == nil)
        let end = applied(records, moves)
        #expect(end[1] == 5)
        #expect(end[0].map { $0 < 0 } == true)
        #expect(end[2] == 9)
    }

    /// Rows already below 0 (stepped aside on an earlier launch, or left there by a second write that
    /// failed) are never met by a new step aside.
    @Test func stepsAsideGoBelowEveryIndexTheDayHolds() {
        let records = [
            Record(day: "3", index: -1, target: nil),
            Record(day: "3", index: -4, target: 2),
            Record(day: "3", index: 0, target: 1),
            Record(day: "3", index: 1, target: 0),
        ]
        let moves = RecordIndexes.moves(records)
        #expect(moves.aside.values.allSatisfy { $0 < -4 })
        #expect(applied(records, moves) == [-1, 2, 1, 0])
        #expect(applied(records, moves, order: { Array($0.reversed()) }) == [-1, 2, 1, 0])
    }

    /// Two records of one item: one is deleted in the first write. Its index is free only after that
    /// write, so the record going there goes aside first; no step aside meets the deleted row.
    @Test func aDeletedDuplicateHoldsItsIndexUntilTheFirstWrite() {
        let records = [
            Record(day: "2", index: 4, target: 3),
            Record(day: "2", index: 3, target: nil, deleted: true),
            Record(day: "2", index: -1, target: nil, deleted: true),
        ]
        let moves = RecordIndexes.moves(records)
        #expect(moves.aside[1] == nil && moves.aside[2] == nil, "deleted rows are not moved")
        #expect(moves.aside[0].map { $0 < -1 } == true)
        #expect(applied(records, moves) == [3, nil, nil])
        #expect(applied(records, moves, order: { Array($0.reversed()) }) == [3, nil, nil])
    }

    @Test func eachDayIsItsOwn() {
        let records = [
            Record(day: "1", index: 0, target: 1), Record(day: "1", index: 1, target: 0),
            Record(day: "2", index: 0, target: 1), Record(day: "2", index: 1, target: 0),
            Record(day: "3", index: 7, target: 7),
        ]
        let moves = RecordIndexes.moves(records)
        #expect(moves.aside[4] == nil && moves.home[4] == nil)
        #expect(applied(records, moves) == [1, 0, 1, 0, 7])
    }

    /// Another day's record coming to an index is no reason to step aside: a record whose item is gone
    /// stays where it is when only another day wants that index.
    @Test func anotherDaysTargetMovesNothing() {
        let records = [Record(day: "1", index: 2, target: nil), Record(day: "2", index: 5, target: 2)]
        let moves = RecordIndexes.moves(records)
        #expect(moves.aside[0] == nil, "day 1's row stepped aside for day 2's target")
        #expect(applied(records, moves) == [2, 2])
    }

    /// Days of up to nine records on indexes -3…11: some on their item, some moving, some whose item
    /// is gone, some deleted. Each write is applied in order, reversed and shuffled; no step may put
    /// two live records of a day on one index, and at the end every record is where it belongs.
    @Test func randomDaysNeverMeetThemselvesInAnyOrder() {
        var rng = SplitMix(seed: 1_4)
        for round in 0 ..< 2_000 {
            var records: [Record] = []
            for day in ["1", "2", "3"].prefix(Int.random(in: 1 ... 3, using: &rng)) {
                let count = Int.random(in: 0 ... 9, using: &rng)
                let stored = Array((-3 ... 11).shuffled(using: &rng).prefix(count))
                var targets = Array((0 ... 9).shuffled(using: &rng))
                for index in stored {
                    switch Int.random(in: 0 ..< 10, using: &rng) {
                    case 0 ..< 2: records.append(Record(day: day, index: index, target: nil))
                    case 2: records.append(Record(day: day, index: index, target: nil, deleted: true))
                    case 3 ..< 5 where (0 ... 9).contains(index) && targets.contains(index):
                        targets.removeAll { $0 == index }
                        records.append(Record(day: day, index: index, target: index))
                    default:
                        records.append(Record(day: day, index: index, target: targets.popLast()))
                    }
                }
            }
            let moves = RecordIndexes.moves(records)
            for (n, r) in records.enumerated() {
                if r.target == r.index { #expect(moves.aside[n] == nil, "round \(round): a needless step aside, row \(n) is on its item") }
                if r.deleted { #expect(moves.aside[n] == nil, "round \(round): a deleted row stepped aside, row \(n)") }
            }
            var shuffled = SplitMix(seed: UInt64(round))
            let orders: [([Int]) -> [Int]] = [{ $0 }, { Array($0.reversed()) }, { $0.shuffled(using: &shuffled) }]
            for order in orders {
                let end = applied(records, moves, order: order)
                for (n, r) in records.enumerated() {
                    if r.deleted {
                        #expect(end[n] == nil)
                    } else if let target = r.target {
                        #expect(end[n] == target, "round \(round): row \(n) belongs at \(target)")
                    } else {
                        let targets = Set(records.filter { $0.day == r.day && !$0.deleted }.compactMap(\.target))
                        #expect(end[n].map { !targets.contains($0) } == true, "round \(round): a gone item's row on a target")
                        #expect(end[n] == r.index || targets.contains(r.index), "round \(round): a gone item's row moved for nothing")
                    }
                }
            }
            for (n, index) in moves.aside {
                let floor = records.filter { $0.day == records[n].day }.map(\.index).min() ?? 0
                #expect(index < min(0, floor), "round \(round): a step aside onto an index in use")
            }
            #expect(Set(moves.home.keys).isSubset(of: Set(moves.aside.keys)), "round \(round): home without stepping aside")
        }
    }
}

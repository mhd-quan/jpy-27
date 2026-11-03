import Foundation
import Testing
@testable import TripKit

@Suite struct LedgerMergeTests {
    let a = "PHONE-A", b = "PHONE-B"
    /// 12:00 in Japan on day 6
    let noon = TripTime.date("2027-10-23", "12:00")!

    func row(_ n: Int, yen: Int = 1200, place: String? = "akafuku", name: String? = nil, category: String = "food",
             method: String = "cash", at minutes: Double = 0, edited: Double? = nil, origin: String, day: String? = "6") -> LedgerRecord {
        LedgerRecord(id: id(n), yen: yen, category: category, method: method, placeID: place, placeName: name, day: day,
                     at: noon.addingTimeInterval(minutes * 60), updatedAt: edited.map { noon.addingTimeInterval($0 * 60) }, origin: origin)
    }

    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    @Test func eachSideGetsWhatTheOtherLogged() {
        let one = LedgerState(records: [row(1, origin: a)])
        let two = LedgerState(records: [row(2, place: "fukusuke", origin: b)])
        let m = LedgerMerge.merge(one, two)
        #expect(m.records.map(\.id) == [id(1), id(2)])
        #expect(m == LedgerMerge.merge(two, one), "the same whichever merges first")
        #expect(LedgerMerge.merge(m, two) == m, "merging again changes nothing")
    }

    @Test func anEditReachesTheOtherPhone() {
        let before = row(1, yen: 1200, origin: a)
        let after = row(1, yen: 1500, edited: 30, origin: a)
        let m = LedgerMerge.merge(LedgerState(records: [before]), LedgerState(records: [after]))
        #expect(m.records.first?.yen == 1500)
        let c = LedgerMerge.changes(from: LedgerState(records: [before]), to: m)
        #expect(c.upserts.map(\.yen) == [1500])
        #expect(c.deletions.isEmpty)
    }

    @Test func aDeletionReachesTheOtherPhoneAndStays() {
        let r = row(1, origin: a)
        let deleted = LedgerState(records: [], tombstones: [LedgerTombstone(id: id(1), at: noon.addingTimeInterval(600))])
        let m = LedgerMerge.merge(LedgerState(records: [r]), deleted)
        #expect(m.records.isEmpty)
        #expect(m.tombstones.map(\.id) == [id(1)])
        #expect(LedgerMerge.changes(from: LedgerState(records: [r]), to: m).deletions == [id(1)])
        // the other phone's old copy, sent again, does not bring it back
        #expect(LedgerMerge.merge(m, LedgerState(records: [r])).records.isEmpty)
    }

    @Test func anEditAfterTheDeletionWins() {
        let deleted = LedgerState(records: [], tombstones: [LedgerTombstone(id: id(1), at: noon.addingTimeInterval(600))])
        let edited = LedgerState(records: [row(1, yen: 900, edited: 20, origin: a)])
        #expect(LedgerMerge.merge(deleted, edited).records.map(\.yen) == [900])
    }

    @Test func twoBowlsAtOneTicketMachineAreBothKept() {
        // Ramen Tsumugi, day 1: each buys a ¥1.200 bowl at the machine and logs it on their own phone
        let mine = LedgerState(records: [row(7, place: "ramen-tsumugi", origin: a, day: "1")])
        let theirs = LedgerState(records: [row(3, place: "ramen-tsumugi", at: 4, origin: b, day: "1")])
        let m = LedgerMerge.merge(mine, theirs)
        #expect(m.records.map(\.id) == [id(3), id(7)], "nothing is dropped without asking")
        #expect(m.records.reduce(0) { $0 + $1.yen } == 2400)
        #expect(m.tombstones.isEmpty)
        #expect(m == LedgerMerge.merge(theirs, mine))
        #expect(LedgerMerge.changes(from: mine, to: m).deletions.isEmpty)
        // and the travellers are asked
        let pairs = LedgerMerge.nearDuplicates(m)
        #expect(pairs.map(\.key) == [LedgerMerge.pairKey(id(3), id(7))])
        #expect(pairs.first?.same == true)
    }

    @Test func oneMealLoggedTwiceKeepsThePurseRow() {
        // one lunch, paid in cash from phone B, also logged on phone A as paid by card
        let s = LedgerMerge.merge(LedgerState(records: [row(1, method: "card", origin: a)]),
                                  LedgerState(records: [row(2, method: "cash", at: 10, origin: b)]))
        #expect(LedgerMerge.nearDuplicates(s).first?.keep == id(2), "B's purse counts its cash row")
        let suica = LedgerMerge.merge(LedgerState(records: [row(1, method: "ic", origin: a)]),
                                      LedgerState(records: [row(2, method: "card", at: 10, origin: b)]))
        #expect(LedgerMerge.nearDuplicates(suica).first?.keep == id(1))
        // both in cash: only the travellers know whose wallet it came from
        let both = LedgerMerge.merge(LedgerState(records: [row(1, origin: a)]), LedgerState(records: [row(2, at: 10, origin: b)]))
        #expect(LedgerMerge.nearDuplicates(both).first?.keep == nil)
    }

    @Test func oneLedgerNeverAsksAboutItsOwnRows() {
        // two bowls at the same counter logged on one phone are two bowls
        let s = LedgerState(records: [row(1, origin: a), row(2, at: 1, origin: a)])
        #expect(LedgerMerge.merge(s, .empty).records.count == 2)
        #expect(LedgerMerge.nearDuplicates(s).isEmpty)
    }

    @Test func otherAmountsOrDaysAreKept() {
        let s = LedgerState(records: [
            row(1, yen: 1200, origin: a),
            row(2, yen: 1500, at: 10, origin: b),
            row(3, yen: 800, place: "fukusuke", at: 0, origin: a, day: "6"),
            row(4, yen: 800, place: "fukusuke", at: 200, origin: b, day: "6"),
        ])
        #expect(LedgerMerge.merge(s, .empty).records.count == 4)
    }

    @Test func nearMatchesAreAskedNotFolded() {
        let s = LedgerState(records: [
            row(1, yen: 1200, origin: a),
            row(2, yen: 1500, at: 10, origin: b),
            // no place, same kind and amount, minutes apart
            row(5, yen: 300, place: nil, category: "extra", at: 60, origin: a),
            row(6, yen: 300, place: nil, category: "extra", at: 75, origin: b),
            // no place, two hours apart: left alone
            row(8, yen: 300, place: nil, category: "extra", at: 200, origin: b),
        ])
        let pairs = LedgerMerge.nearDuplicates(LedgerMerge.merge(s, .empty))
        #expect(pairs.map(\.key) == [LedgerMerge.pairKey(id(1), id(2)), LedgerMerge.pairKey(id(5), id(6))])
        #expect(pairs.map(\.same) == [false, true], "another amount is asked as a near match")
        let kept = LedgerState(records: s.records, kept: [LedgerMerge.pairKey(id(2), id(1))])
        #expect(LedgerMerge.nearDuplicates(kept).count == 1, "a pair kept apart is not asked again")
    }

    @Test func aRowFoldedByAnOlderBuildComesBackOnBothPhones() throws {
        // two people, two bowls at the same price, folded by a build that still did that, then brought back
        let gone = row(2, at: 5, origin: b)
        let m = LedgerState(records: [row(1, origin: a)],
                            tombstones: [LedgerTombstone(id: id(2), at: gone.version, duplicateOf: id(1), record: gone)])
        #expect(LedgerMerge.merge(m, .empty) == m, "merging leaves the old fold as it was")
        let t = try #require(m.tombstones.first { $0.id == id(2) })
        let restored = try #require(LedgerMerge.restore(t, in: m, now: noon.addingTimeInterval(3600)))
        #expect(restored.records.map(\.id) == [id(1), id(2)])
        // the other phone still has the deletion, and gets the restored row and the pair kept apart
        let other = LedgerMerge.merge(m, restored)
        #expect(other.records.map(\.id) == [id(1), id(2)])
        #expect(other == LedgerMerge.merge(restored, m))
    }

    @Test func typedPlaceNamesMatchLoosely() {
        let s = LedgerState(records: [
            row(1, place: nil, name: "Lawson Ōtsu", origin: a),
            row(2, place: nil, name: " lawson otsu", at: 30, origin: b),
        ])
        let merged = LedgerMerge.merge(s, .empty)
        #expect(merged.records.count == 2)
        #expect(LedgerMerge.nearDuplicates(merged).first?.same == true)
    }

    @Test func writesDatedFarAheadAreRefused() {
        let now = noon
        let remote = LedgerState(records: [row(1, origin: b), row(2, edited: 60 * 24 * 365 * 70, origin: b)],
                                 tombstones: [LedgerTombstone(id: id(1), at: TripTime.date("2099-01-01", "00:00")!),
                                              LedgerTombstone(id: id(3), at: now.addingTimeInterval(600))])
        let s = LedgerMerge.sanitized(remote, now: now)
        #expect(s.records.map(\.id) == [id(1)], "a write dated 2097 is left out")
        #expect(s.tombstones.map(\.id) == [id(3)], "a deletion dated 2099 is left out")
        // a phone a few hours ahead, as clocks set by hand are, still syncs
        let ahead = LedgerState(records: [row(4, edited: 60 * 5, origin: b)])
        #expect(LedgerMerge.sanitized(ahead, now: now).records.count == 1)
    }

    @Test func travelsAsJSONUnchanged() throws {
        let m = LedgerMerge.merge(LedgerState(records: [row(1, edited: 3, origin: a)]),
                                  LedgerState(records: [row(2, place: "x", origin: b)], tombstones: [LedgerTombstone(id: id(9), at: noon)], kept: ["k"]))
        let back = try JSONDecoder().decode(LedgerState.self, from: JSONEncoder().encode(m))
        #expect(back == m)
    }
}

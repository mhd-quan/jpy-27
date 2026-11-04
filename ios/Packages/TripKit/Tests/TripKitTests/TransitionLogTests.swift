import Testing
@testable import TripKit

/// The Số đo page's own record of transitions (`Perf` in the app): a tap is paired with the page that
/// answers it, each ends once, and the medians come from the newest samples per name.
@Suite struct TransitionLogTests {
    let t0 = ContinuousClock.now

    func at(_ ms: Int) -> ContinuousClock.Instant { t0 + .milliseconds(ms) }

    @Test func medianOfNothingIsNil() {
        #expect(TransitionLog.median([]) == nil)
    }

    @Test func medianOfOneIsThatOne() {
        #expect(TransitionLog.median([.milliseconds(5)]) == .milliseconds(5))
    }

    @Test func medianOfAnOddCountIsTheMiddleOneSorted() {
        #expect(TransitionLog.median([.milliseconds(30), .milliseconds(10), .milliseconds(20)]) == .milliseconds(20))
    }

    @Test func medianOfAnEvenCountIsTheMeanOfTheMiddleTwo() {
        #expect(TransitionLog.median([.milliseconds(10), .milliseconds(40), .milliseconds(20), .milliseconds(30)]) == .milliseconds(25))
    }

    @Test func aTapClaimedAndSettledIsOneSample() {
        var log = TransitionLog()
        let begun = log.begin(1, slot: "sheet", from: "map.stop.3", to: "place", at: at(0))
        #expect(begun.superseded == nil)
        let claimed = log.claim("sheet", page: nil, at: at(120))
        #expect(claimed == .claimed(1))
        let settled = log.settle(1, at: at(620))
        #expect(settled)
        #expect(log.rows == [TransitionLog.Row(name: "map → place", count: 1, firstFrame: .milliseconds(120), settled: .milliseconds(620))])
    }

    @Test func aTransitionSettlesOnlyOnce() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        _ = log.claim("sheet", page: nil, at: at(100))
        let settled = log.settle(1, at: at(600))
        #expect(settled)
        let settled2 = log.settle(1, at: at(700))
        #expect(!settled2)
        #expect(log.rows.map(\.count) == [1])
    }

    @Test func aPageClaimsOnlyItsOwnSlot() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        let claimed = log.claim("push", page: "day", at: at(100))
        #expect(claimed == .none)
        let claimed2 = log.claim("sheet", page: nil, at: at(110))
        #expect(claimed2 == .claimed(1))
    }

    @Test func aTapOlderThanTheWindowExpiresUnpaired() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "push", from: "today", to: nil, at: at(0))
        let claimed = log.claim("push", page: "day", at: at(3_001))
        #expect(claimed == .expired(1))
        let settled = log.settle(1, at: at(3_500))
        #expect(!settled)
        #expect(log.rows.isEmpty)
    }

    @Test func aTapAtTheWindowsEdgeIsStillClaimed() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "push", from: "today", to: nil, at: at(0))
        let claimed = log.claim("push", page: "day", at: at(3_000))
        #expect(claimed == .claimed(1))
    }

    @Test func aSecondTapBeforeAnyClaimSupersedesTheFirst() {
        var log = TransitionLog()
        let begun = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        #expect(begun.superseded == nil)
        let begun2 = log.begin(2, slot: "sheet", from: nil, to: "ride", at: at(50))
        #expect(begun2.superseded == 1)
        let claimed = log.claim("sheet", page: nil, at: at(150))
        #expect(claimed == .claimed(2))
        let claimed2 = log.claim("sheet", page: nil, at: at(160))
        #expect(claimed2 == .none)
    }

    @Test func aClaimedTransitionIsNotSupersededByTheNextTap() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        _ = log.claim("sheet", page: nil, at: at(100))
        let begun = log.begin(2, slot: "sheet", from: nil, to: "expense", at: at(300))
        #expect(begun.superseded == nil)
        let settled = log.settle(1, at: at(600))
        #expect(settled)
    }

    @Test func aDroppedTransitionRecordsNothingAndEndsOnce() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        _ = log.claim("sheet", page: nil, at: at(100))
        let dropped = log.drop(1)
        #expect(dropped)
        let dropped2 = log.drop(1)
        #expect(!dropped2)
        let settled = log.settle(1, at: at(600))
        #expect(!settled)
        #expect(log.rows.isEmpty)
    }

    @Test func aWaitingTransitionCanBeDropped() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "cover", from: nil, to: "phrase", at: at(0))
        let dropped = log.drop(1)
        #expect(dropped)
        let claimed = log.claim("cover", page: "phrase", at: at(100))
        #expect(claimed == .none)
    }

    @Test func thePageNamesAPushsDestination() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "push", from: "today", to: nil, at: at(0))
        _ = log.claim("push", page: "day", at: at(90))
        _ = log.settle(1, at: at(590))
        _ = log.begin(2, slot: "sheet", from: "map.row.2", to: "place", at: at(1_000))
        _ = log.claim("sheet", page: nil, at: at(1_100))
        _ = log.settle(2, at: at(1_600))
        #expect(log.rows.map(\.name) == ["map → place", "today → day"])
    }

    @Test func labels() {
        #expect(TransitionLog.label(from: "map.stop.3", to: "place") == "map → place")
        #expect(TransitionLog.label(from: nil, to: "phrase") == "phrase")
        #expect(TransitionLog.label(from: "spend.add", to: nil) == "spend")
        #expect(TransitionLog.label(from: "today", to: "day") == "today → day")
    }

    @Test func mediansComeFromTheNewestSamplesOnly() {
        var log = TransitionLog()
        for n in 0..<60 {
            let start = n * 10_000
            // the first ten are slow (a cold cache); the rest take 100 ms to the first frame, 600 to settle
            let first = n < 10 ? 2_500 : 100
            _ = log.begin(n, slot: "push", from: "plan", to: "fuji", at: at(start))
            _ = log.claim("push", page: nil, at: at(start + first))
            _ = log.settle(n, at: at(start + first + 500))
        }
        #expect(log.rows == [TransitionLog.Row(name: "plan → fuji", count: 60, firstFrame: .milliseconds(100), settled: .milliseconds(600))])
    }

    @Test func rowsAndMarksAreSortedByName() {
        var log = TransitionLog()
        for (i, to) in ["place", "expense", "fujiSpot"].enumerated() {
            _ = log.begin(i, slot: "sheet", from: "x", to: to, at: at(i * 1_000))
            _ = log.claim("sheet", page: nil, at: at(i * 1_000 + 50))
            _ = log.settle(i, at: at(i * 1_000 + 550))
        }
        log.count("map.fly")
        log.count("day.check")
        log.count("map.fly")
        #expect(log.rows.map(\.name) == ["x → expense", "x → fujiSpot", "x → place"])
        #expect(log.marks.map(\.name) == ["day.check", "map.fly"])
        #expect(log.marks.map(\.count) == [1, 2])
    }

    @Test func claimedTransitionsNeverEndedAreForgottenPastTheBound() {
        var log = TransitionLog()
        let n = TransitionLog.openKept + 1
        for i in 0..<n {
            _ = log.begin(i, slot: "push", from: "plan", to: "day", at: at(i * 10))
            _ = log.claim("push", page: nil, at: at(i * 10 + 5))
        }
        let settled = log.settle(0, at: at(n * 10))
        #expect(!settled)
        // only the oldest is forgotten: the next one still settles (a bound of openKept, not openKept - 1)
        let settled1 = log.settle(1, at: at(n * 10))
        #expect(settled1)
        let settled2 = log.settle(n - 1, at: at(n * 10))
        #expect(settled2)
    }

    @Test func settledTransitionsDoNotCountTowardTheOpenBound() {
        var log = TransitionLog()
        // one claimed and left open, then openKept more claimed and settled one by one
        _ = log.begin(0, slot: "push", from: "plan", to: "day", at: at(0))
        _ = log.claim("push", page: nil, at: at(5))
        for i in 1...TransitionLog.openKept {
            _ = log.begin(i, slot: "push", from: "plan", to: "day", at: at(i * 10))
            _ = log.claim("push", page: nil, at: at(i * 10 + 5))
            _ = log.settle(i, at: at(i * 10 + 8))
        }
        let settled = log.settle(0, at: at(1_000))
        #expect(settled)
    }

    @Test func theMediansUseExactlyTheNewestSamplesKept() {
        var log = TransitionLog()
        let n = TransitionLog.samplesKept + 1
        // sample k settles (k + 1) × 10 ms after its first frame (100 ms): with the newest 50 (k = 1…50) the
        // middle two are 260 and 270 ms past it; with 49 the middle one would be 270, with all 51, 260
        for k in 0..<n {
            let start = k * 10_000
            _ = log.begin(k, slot: "sheet", from: "map", to: "place", at: at(start))
            _ = log.claim("sheet", page: nil, at: at(start + 100))
            _ = log.settle(k, at: at(start + 100 + (k + 1) * 10))
        }
        #expect(log.rows == [TransitionLog.Row(name: "map → place", count: n, firstFrame: .milliseconds(100), settled: .milliseconds(365))])
    }

    @Test func aTapNoPageAnswersExpiresAtTheNextTapInAnySlot() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "cover", from: nil, to: "phrase", at: at(0))
        _ = log.begin(2, slot: "sheet", from: "map", to: "place", at: at(1_000))
        // past the window for 1, not for 2
        let begun = log.begin(3, slot: "push", from: "plan", to: nil, at: at(3_500))
        #expect(begun == TransitionLog.Begun(superseded: nil, expired: [1]))
        // gone from its slot: nothing to claim, nothing to settle or drop
        let claimed = log.claim("cover", page: "phrase", at: at(3_600))
        #expect(claimed == .none)
        let dropped = log.drop(1)
        #expect(!dropped)
        // the others still wait
        let claimed2 = log.claim("sheet", page: nil, at: at(3_700))
        #expect(claimed2 == .claimed(2))
    }

    @Test func anExpiredTapInTheSameSlotIsExpiredNotSuperseded() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        let begun = log.begin(2, slot: "sheet", from: nil, to: "ride", at: at(3_001))
        #expect(begun == TransitionLog.Begun(superseded: nil, expired: [1]))
    }

    @Test func aTapAtTheWindowsEdgeIsSupersededNotExpired() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        let begun = log.begin(2, slot: "sheet", from: nil, to: "ride", at: at(3_000))
        #expect(begun == TransitionLog.Begun(superseded: 1, expired: []))
    }

    @Test func expiredTapsComeInIDOrder() {
        var log = TransitionLog()
        _ = log.begin(5, slot: "sheet", from: nil, to: "place", at: at(0))
        _ = log.begin(6, slot: "push", from: "plan", to: nil, at: at(10))
        _ = log.begin(7, slot: "cover", from: nil, to: "phrase", at: at(20))
        let begun = log.begin(8, slot: "cover", from: nil, to: "phrase", at: at(5_000))
        #expect(begun == TransitionLog.Begun(superseded: nil, expired: [5, 6, 7]))
    }
}

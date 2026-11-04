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
        let superseded = log.begin(1, slot: "sheet", from: "map.stop.3", to: "place", at: at(0))
        #expect(superseded == nil)
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
        let superseded = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        #expect(superseded == nil)
        let superseded2 = log.begin(2, slot: "sheet", from: nil, to: "ride", at: at(50))
        #expect(superseded2 == 1)
        let claimed = log.claim("sheet", page: nil, at: at(150))
        #expect(claimed == .claimed(2))
        let claimed2 = log.claim("sheet", page: nil, at: at(160))
        #expect(claimed2 == .none)
    }

    @Test func aClaimedTransitionIsNotSupersededByTheNextTap() {
        var log = TransitionLog()
        _ = log.begin(1, slot: "sheet", from: nil, to: "place", at: at(0))
        _ = log.claim("sheet", page: nil, at: at(100))
        let superseded = log.begin(2, slot: "sheet", from: nil, to: "expense", at: at(300))
        #expect(superseded == nil)
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
        let settled2 = log.settle(n - 1, at: at(n * 10))
        #expect(settled2)
    }
}

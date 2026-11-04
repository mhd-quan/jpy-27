import Testing
@testable import TripKit

/// The rules of `transitionSettled` on a page a transition brings in (`settles` in the app): the first
/// appearance claims the tap, a page waits while it is not settled, a finished wait settles it once, a
/// cut-short wait leaves it to the next appearance, and nothing turns it back to false. Tasks 4.1 and
/// 5.3 start their work on it: it must never stay false while the page shows.
@Suite struct SettleGateTests {
    @Test func theFirstAppearanceClaimsTheSecondDoesNot() {
        var gate = SettleGate()
        let first = gate.appeared()
        let second = gate.appeared()
        #expect(first)
        #expect(!second)
        #expect(gate.claimed)
    }

    @Test func aNewPageWaitsAndIsNotSettled() {
        var gate = SettleGate()
        _ = gate.appeared()
        #expect(gate.waits)
        #expect(!gate.settled)
    }

    @Test func aWaitCutShortLeavesItToTheNextAppearance() {
        var gate = SettleGate()
        _ = gate.appeared()
        let cut = gate.waited(finished: false)
        #expect(!cut)
        #expect(!gate.settled)
        // shown again (a tab switch back, a page popped off it): it waits again, and that wait settles it
        let again = gate.appeared()
        #expect(!again)
        #expect(gate.waits)
        let finished = gate.waited(finished: true)
        #expect(finished)
        #expect(gate.settled)
    }

    @Test func onceSettledNothingWaitsAndNothingUnsettles() {
        var gate = SettleGate()
        _ = gate.appeared()
        _ = gate.waited(finished: true)
        _ = gate.appeared()
        #expect(!gate.waits)
        let cut = gate.waited(finished: false)
        #expect(!cut)
        #expect(gate.settled)
    }

    @Test func aFinishedWaitSettlesOnlyOnce() {
        var gate = SettleGate()
        _ = gate.appeared()
        let first = gate.waited(finished: true)
        let second = gate.waited(finished: true)
        #expect(first)
        #expect(!second)
        #expect(gate.settled)
    }
}

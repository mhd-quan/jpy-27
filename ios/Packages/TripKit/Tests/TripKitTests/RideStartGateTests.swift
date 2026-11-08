import Testing
@testable import TripKit

/// The start of a followed ride in two steps (`RideLiveService.select`, then `begin` after the button's first
/// frame): only the ride selected begins, once, and never while its end is under way. One Live Activity at a time
/// rests on it.
@Suite struct RideStartGateTests {
    /// the gate in a box, so a step can sit inside `#expect` (which cannot call a mutating member)
    final class Gate {
        var gate = RideStartGate()
        var selected: String? { gate.selected }
        @discardableResult func select(_ id: String) -> Bool { gate.select(id) }
        func claim(_ id: String) -> Bool { gate.claim(id) }
        func isClosing(_ id: String) -> Bool { gate.isClosing(id) }
        func released(_ id: String) { gate.released(id) }
        func begin(_ id: String) -> Bool { gate.begin(id) }
    }

    @Test func aLaterSelectionTakesTheBeginOfAnEarlierOne() {
        let gate = Gate()
        #expect(gate.select("A"))
        #expect(gate.select("B"))
        #expect(!gate.begin("A"))
        #expect(gate.begin("B"))
        #expect(gate.selected == "B")
    }

    @Test func aSelectionBeginsOnce() {
        let gate = Gate()
        gate.select("A")
        #expect(gate.begin("A"))
        #expect(!gate.begin("A"))
    }

    @Test func nothingBeginsWhileItsEndIsUnderWay() {
        let gate = Gate()
        gate.select("A")
        #expect(gate.claim("A"))
        #expect(gate.isClosing("A"))
        #expect(!gate.begin("A"))
    }

    @Test func nothingBeginsOnceReleased() {
        let gate = Gate()
        gate.select("A")
        gate.released("A")
        #expect(gate.selected == nil)
        #expect(!gate.begin("A"))
    }

    /// the same-ride guard: selecting the ride followed changes nothing, so its begin is not re-armed
    @Test func selectingTheRideFollowedAgainReArmsNothing() {
        let gate = Gate()
        #expect(gate.select("A"))
        #expect(gate.begin("A"))
        #expect(!gate.select("A"))
        #expect(!gate.begin("A"))
    }

    /// `start` (autostart, the station's notification) is select + begin at once; a tap's begin still waiting
    /// for its frame then finds it begun
    @Test func aStartBeforeAWaitingBeginLeavesItNothing() {
        let gate = Gate()
        #expect(gate.select("A"))        // the tap, inside its animation
        #expect(!gate.select("A"))       // autostart's start: the same ride
        #expect(gate.begin("A"))         // …and its begin
        #expect(!gate.begin("A"))        // the tap's, a frame later
    }

    @Test func aRideEndedAndFollowedAgainBeginsAgain() {
        let gate = Gate()
        gate.select("A")
        #expect(gate.begin("A"))
        #expect(gate.claim("A"))
        gate.released("A")
        #expect(gate.select("A"))
        #expect(gate.begin("A"))
        #expect(!gate.begin("A"))
    }

    @Test func oneEndPerRide() {
        let gate = Gate()
        #expect(!gate.claim("A"))        // not followed
        gate.select("A")
        #expect(!gate.claim("B"))        // not the one followed
        #expect(gate.claim("A"))
        #expect(!gate.claim("A"))        // taken
    }

    /// a ride selected while the previous one's end is still letting go: the old release clears only its own
    /// claim and leaves the new ride followed
    @Test func aLateReleaseOfThePreviousRideLeavesTheNewOne() {
        let gate = Gate()
        gate.select("A")
        #expect(gate.claim("A"))
        #expect(gate.select("B"))
        #expect(gate.begin("B"))
        gate.released("A")
        #expect(gate.selected == "B")
        #expect(!gate.isClosing("A"))
        #expect(gate.claim("B"))
        gate.released("B")
        #expect(gate.selected == nil)
        #expect(!gate.isClosing("B"))
    }

    /// select A, select B, begin A, then A selected again: A begins, B's earlier selection is gone
    @Test func backToAnEarlierRide() {
        let gate = Gate()
        gate.select("A")
        gate.select("B")
        #expect(!gate.begin("A"))
        #expect(gate.select("A"))
        #expect(!gate.begin("B"))
        #expect(gate.begin("A"))
    }

    /// the new ride's end taken before the old one's release lands: that release leaves the new claim alone
    @Test func aLateReleaseLeavesTheNewRidesClaim() {
        let gate = Gate()
        gate.select("A")
        #expect(gate.claim("A"))
        gate.select("B")
        #expect(gate.claim("B"))
        gate.released("A")
        #expect(gate.selected == "B")
        #expect(gate.isClosing("B"))
        #expect(!gate.begin("B"))
    }
}

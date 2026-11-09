import Testing
@testable import TripKit

/// A value chosen once for a key and then held: an album page's colour, decided by its first photograph and kept
/// while the page lives (R-357, R-382).
@Suite struct HeldChoiceTests {
    private typealias Choice = HeldChoice<String, Int>

    // MARK: At the start

    @Test func aKnownValueIsDecidedAtOnce() {
        let held = Choice(key: "a", known: 7)
        #expect(held.key == "a" && held.value == 7 && held.decided)
        #expect(!held.wants("a"))
    }

    @Test func anUnknownValueWaitsForItsDecision() {
        let held = Choice(key: "a", known: nil)
        #expect(held.key == "a" && held.value == nil && !held.decided)
        #expect(held.wants("a"))
        #expect(!held.wants("b"))
    }

    @Test func withNoKeyThereIsNothingToHoldOrDecide() {
        let held = Choice(key: nil, known: 7)
        #expect(held.key == nil && held.value == nil && !held.decided)
        #expect(!held.wants("a"))
    }

    // MARK: The decision

    @Test func theDecisionIsTakenOnce() {
        var held = Choice(key: "a", known: nil)
        held.decide(3, for: "a")
        #expect(held.value == 3 && held.decided && !held.wants("a"))
        held.decide(4, for: "a")
        #expect(held.value == 3 && held.decided)
        held.decide(nil, for: "a")
        #expect(held.value == 3 && held.decided)
    }

    @Test func aValueKnownAtTheStartTakesNoDecision() {
        var held = Choice(key: "a", known: 7)
        held.decide(3, for: "a")
        held.decide(nil, for: "a")
        #expect(held.value == 7 && held.decided)
    }

    @Test func aDecisionForAnotherKeyIsIgnored() {
        var held = Choice(key: "a", known: nil)
        held.decide(3, for: "b")
        #expect(held.key == "a" && held.value == nil && !held.decided && held.wants("a"))
        held.decide(nil, for: "b")
        #expect(held.value == nil && !held.decided && held.wants("a"))
        // with no key, every decision is for another
        var none = Choice(key: nil, known: nil)
        none.decide(3, for: "a")
        #expect(none.value == nil && !none.decided)
    }

    @Test func aNilDecisionClosesItForGood() {
        var held = Choice(key: "a", known: nil)
        held.decide(nil, for: "a")
        #expect(held.value == nil && held.decided && !held.wants("a"))
        held.decide(3, for: "a")
        #expect(held.value == nil && held.decided)
        // the same key again does not reopen it, a value known by now included: it waits for the next page
        held.follow("a", known: 3)
        #expect(held.value == nil && held.decided && !held.wants("a"))
    }

    // MARK: Another first key (T2)

    @Test func followingTheSameKeyChangesNothing() {
        var open = Choice(key: "a", known: nil)
        open.follow("a", known: 3)
        #expect(open.value == nil && !open.decided && open.wants("a"))
        var held = Choice(key: "a", known: 7)
        held.follow("a", known: 9)
        #expect(held.value == 7 && held.decided)
    }

    @Test func anotherKeyStartsAgainByTheSameRule() {
        var held = Choice(key: "a", known: 7)
        // the old value is let go, not carried: the new key's own, if known, else nothing until its decision
        held.follow("b", known: nil)
        #expect(held.key == "b" && held.value == nil && !held.decided)
        #expect(held.wants("b") && !held.wants("a"))
        // a decision that was under way for the old key comes too late
        held.decide(5, for: "a")
        #expect(held.value == nil && !held.decided)
        held.decide(4, for: "b")
        #expect(held.value == 4 && held.decided)
        held.follow("c", known: 8)
        #expect(held.key == "c" && held.value == 8 && held.decided)
        // back to an earlier key: its value as known now, not as it was held
        held.follow("a", known: nil)
        #expect(held.key == "a" && held.value == nil && !held.decided)
    }

    @Test func theKnownValueIsLookedUpOnlyForAnotherKey() {
        var held = Choice(key: "a", known: 7)
        var reads = 0
        held.follow("a", known: { reads += 1; return 9 }())
        #expect(reads == 0 && held.value == 7)
        held.follow("b", known: { reads += 1; return 9 }())
        #expect(reads == 1 && held.key == "b" && held.value == 9 && held.decided)
    }

    @Test func choicesCompareByWhatTheyHold() {
        #expect(Choice(key: "a", known: 7) == Choice(key: "a", known: 7))
        #expect(Choice(key: "a", known: 7) != Choice(key: "a", known: nil))
        var closed = Choice(key: "a", known: nil)
        closed.decide(nil, for: "a")
        #expect(closed != Choice(key: "a", known: nil))
    }
}

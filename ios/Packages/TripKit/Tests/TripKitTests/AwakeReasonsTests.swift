import Testing
import TripKit

/// The screen is kept on while any reason holds (the phrase card held up to staff, a ride followed with the
/// switch on), and turning one reason off never turns off another (spec 2.5).
@Suite struct AwakeReasonsTests {
    @Test func emptyKeepsNothingAwake() {
        #expect(AwakeReasons().keepsAwake == false)
    }

    @Test func anyReasonKeepsAwake() {
        var card = AwakeReasons()
        card.set(.showCard, true)
        #expect(card.keepsAwake)
        var ride = AwakeReasons()
        ride.set(.ride, true)
        #expect(ride.keepsAwake)
    }

    @Test func removingOneReasonKeepsTheOther() {
        var r = AwakeReasons()
        r.set(.showCard, true)
        r.set(.ride, true)
        r.set(.ride, false)
        #expect(r.keepsAwake == true)
        r.set(.showCard, false)
        #expect(r.keepsAwake == false)
    }

    @Test func settingTwiceIsOnce() {
        var r = AwakeReasons()
        r.set(.ride, true)
        r.set(.ride, true)
        r.set(.ride, false)
        #expect(r.keepsAwake == false)
    }

    @Test func turningOffAReasonNeverSetIsNothing() {
        var r = AwakeReasons()
        r.set(.ride, false)
        #expect(r == AwakeReasons())
        #expect(r.keepsAwake == false)
    }
}

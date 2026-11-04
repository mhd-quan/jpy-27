import Testing
@testable import TripKit

/// WeatherKit's failures in a row (`ForecastService`): requests that were in flight together fail
/// together for one reason, so they count once.
@Suite struct FailureStreakTests {
    @Test func overlappingFailuresCountOnce() {
        var streak = FailureStreak()
        let a = streak.ticket()
        let b = streak.ticket()
        #expect(streak.failed(a) == 1)
        #expect(streak.failed(b) == 1)
        #expect(streak.count == 1)
    }

    @Test func failuresOneAfterAnotherCountEach() {
        var streak = FailureStreak()
        let a = streak.ticket()
        #expect(streak.failed(a) == 1)
        let b = streak.ticket()
        #expect(streak.failed(b) == 2)
    }

    @Test func aFreshRequestAfterAnOverlapCountsAgain() {
        var streak = FailureStreak()
        let a = streak.ticket()
        let b = streak.ticket()
        streak.failed(a)
        let c = streak.ticket()
        streak.failed(b)
        #expect(streak.failed(c) == 2)
    }

    @Test func aSuccessStartsTheCountAgain() {
        var streak = FailureStreak()
        streak.failed(streak.ticket())
        streak.succeeded()
        #expect(streak.count == 0)
        #expect(streak.failed(streak.ticket()) == 1)
    }
}

import Foundation
import Testing
@testable import TripKit

/// What is ready for no signal: the summary on Settings' main page, the order "Tải tất cả" takes, how fresh a
/// forecast must be, and when "Cần xem" says what is not ready.
@Suite struct ReadinessTests {
    /// every item ready, with `changes` over it
    func states(_ changes: [ReadyItem: ReadyState] = [:]) -> [ReadyItem: ReadyState] {
        var all = Dictionary(uniqueKeysWithValues: ReadyItem.allCases.map { ($0, ReadyState.ready) })
        all.merge(changes) { _, new in new }
        return all
    }

    // MARK: The summary

    @Test func allReadyIsReady() {
        #expect(Readiness.summary(states(), mapsStale: false, downloading: nil) == "Sẵn sàng")
        #expect(Readiness.ready == "Sẵn sàng")
    }

    @Test func unsupportedDoesNotCount() {
        let s = states([.speech: .unsupported("Máy này chưa nghe được tiếng Nhật")])
        #expect(Readiness.summary(s, mapsStale: false, downloading: nil) == "Sẵn sàng")
    }

    @Test func countsWhatIsMissing() {
        let s = states([.photos: .missing(done: 3, total: 9), .translation: .missing(done: nil, total: nil)])
        #expect(Readiness.summary(s, mapsStale: false, downloading: nil) == "Thiếu 2 mục")
    }

    @Test func downloadingWins() {
        let missing = states([.photos: .missing(done: 3, total: 9)])
        #expect(Readiness.summary(missing, mapsStale: false, downloading: 0.424) == "Đang tải 42%")
        #expect(Readiness.summary(missing, mapsStale: true, downloading: 0.424) == "Đang tải 42%")
        #expect(Readiness.summary(states(), mapsStale: false, downloading: 0) == "Đang tải 0%")
    }

    @Test func staleMapsBeforeCount() {
        let s = states([.photos: .missing(done: 3, total: 9), .fuji: .missing(done: 1, total: 70)])
        #expect(Readiness.summary(s, mapsStale: true, downloading: nil) == "Cần tải lại")
        #expect(Readiness.summary(states(), mapsStale: true, downloading: nil) == "Cần tải lại")
    }

    @Test func percentIsFloored() {
        #expect(Readiness.summary(states(), mapsStale: false, downloading: 0.999) == "Đang tải 99%")
        #expect(Readiness.summary(states(), mapsStale: false, downloading: 1) == "Đang tải 100%")
        // 0.57 × 100 is 56.999… in binary floating point
        #expect(Readiness.summary(states(), mapsStale: false, downloading: 0.57) == "Đang tải 57%")
        #expect(Readiness.summary(states(), mapsStale: false, downloading: 0.29) == "Đang tải 29%")
    }

    @Test func percentOutOfRangeIsClamped() {
        #expect(Readiness.summary(states(), mapsStale: false, downloading: .nan) == "Đang tải 0%")
        #expect(Readiness.summary(states(), mapsStale: false, downloading: .infinity) == "Đang tải 0%")
        #expect(Readiness.summary(states(), mapsStale: false, downloading: -0.3) == "Đang tải 0%")
        #expect(Readiness.summary(states(), mapsStale: false, downloading: 1.7) == "Đang tải 100%")
    }

    @Test func needsSetupCountsAsMissing() {
        let s = states([.dayMaps: .needsSetup("Mở trang Hôm nay một lần")])
        #expect(Readiness.summary(s, mapsStale: false, downloading: nil) == "Thiếu 1 mục")
    }

    @Test func everyStateButReadyAndUnsupportedCounts() {
        let s = states([
            .maps: .working(0.5), .dayMaps: .waitingForNetwork, .photos: .failed("Không tải được"),
            .fuji: .needsSetup("Mở trang Fuji một lần"), .forecasts: .missing(done: 2, total: 3),
            .translation: .unsupported("Máy này chưa dịch được Nhật sang Việt"), .speech: .ready,
        ])
        #expect(Readiness.summary(s, mapsStale: false, downloading: nil) == "Thiếu 5 mục")
    }

    @Test func anItemNotReadYetCountsAsMissing() {
        var s = states()
        s[.fuji] = nil
        #expect(Readiness.summary(s, mapsStale: false, downloading: nil) == "Thiếu 1 mục")
        #expect(Readiness.summary([:], mapsStale: false, downloading: nil) == "Thiếu 7 mục")
    }

    // MARK: The order "Tải tất cả" takes

    @Test func planOrder() {
        let missing = Dictionary(uniqueKeysWithValues: ReadyItem.allCases.map { ($0, ReadyState.missing(done: nil, total: nil)) })
        #expect(Readiness.plan(missing) == [.translation, .speech, .photos, .maps, .dayMaps, .fuji, .forecasts])
        #expect(Readiness.plan(states()) == [])
        let some = states([
            .maps: .missing(done: 3, total: 11), .speech: .unsupported("Máy này chưa nghe được tiếng Nhật"),
            .dayMaps: .needsSetup("Mở trang Hôm nay một lần"), .forecasts: .missing(done: 2, total: 3),
        ])
        #expect(Readiness.plan(some) == [.maps, .forecasts])
    }

    @Test func planKeepsWhatIsUnderWayFailedOrWaiting() {
        let s = states([.photos: .working(0.4), .maps: .failed("Lỗi"), .fuji: .waitingForNetwork])
        #expect(Readiness.plan(s) == [.photos, .maps, .fuji])
    }

    @Test func planKeepsAnItemNotReadYet() {
        var s = states()
        s[.translation] = nil
        s[.dayMaps] = nil
        #expect(Readiness.plan(s) == [.translation, .dayMaps])
    }

    // MARK: Forecasts

    @Test func forecastsFreshWithin12Hours() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = [now, now.addingTimeInterval(-3600), now.addingTimeInterval(-43_000)]
        #expect(Readiness.forecasts(fetched: fresh, now: now) == .ready)
        #expect(Readiness.forecasts(fetched: [now, nil, now], now: now) == .missing(done: 2, total: 3))
        #expect(Readiness.forecasts(fetched: [now, now.addingTimeInterval(-43_201), now], now: now) == .missing(done: 2, total: 3))
    }

    @Test func forecastExactlyTwelveHoursOldIsFresh() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Readiness.forecastFresh == 43_200)
        #expect(Readiness.forecasts(fetched: [now.addingTimeInterval(-43_200)], now: now) == .ready)
    }

    @Test func noForecastsIsReady() {
        #expect(Readiness.forecasts(fetched: [], now: Date(timeIntervalSince1970: 1_800_000_000)) == .ready)
    }

    @Test func noForecastFreshCountsNone() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(Readiness.forecasts(fetched: [nil, now.addingTimeInterval(-90_000)], now: now) == .missing(done: 0, total: 2))
    }

    // MARK: A day's map picture (R-640)

    @Test func aDayFollowingTheSystemIsReadyWithEitherScheme() {
        // no photograph, Giao diện on "Tự động": the picture of the scheme it was drawn in before sunset still counts
        #expect(Readiness.dayMapReady(own: false, other: true, followsSystem: true))
        #expect(Readiness.dayMapReady(own: true, other: false, followsSystem: true))
        #expect(Readiness.dayMapReady(own: true, other: true, followsSystem: true))
        #expect(!Readiness.dayMapReady(own: false, other: false, followsSystem: true))
    }

    @Test func aDayWithItsOwnSchemeNeedsThatPicture() {
        // a photograph's colour, or Giao diện on Sáng or Tối: the exact scheme, as before
        #expect(!Readiness.dayMapReady(own: false, other: true, followsSystem: false))
        #expect(Readiness.dayMapReady(own: true, other: false, followsSystem: false))
        #expect(!Readiness.dayMapReady(own: false, other: false, followsSystem: false))
    }

    // MARK: When "Cần xem" speaks

    @Test func watchStartsFourteenDaysBeforeTheTrip() {
        // 2027-10-04 00:00 in Tokyo is 2027-10-03 15:00 UTC
        let start = TripTime.midnight("2027-10-04")!
        #expect(Readiness.watching(now: start, start: "2027-10-18", end: "2027-10-29"))
        #expect(!Readiness.watching(now: start.addingTimeInterval(-1), start: "2027-10-18", end: "2027-10-29"))
        #expect(start == Date(timeIntervalSince1970: 1_822_575_600))
    }

    @Test func watchEndsWithTheLastDay() {
        let next = TripTime.midnight("2027-10-30")!
        #expect(Readiness.watching(now: next.addingTimeInterval(-1), start: "2027-10-18", end: "2027-10-29"))
        #expect(!Readiness.watching(now: next, start: "2027-10-18", end: "2027-10-29"))
        #expect(Readiness.watching(now: TripTime.midnight("2027-10-20")!, start: "2027-10-18", end: "2027-10-29"))
    }

    @Test func watchIsOffWithDatesItCannotRead() {
        let now = TripTime.midnight("2027-10-20")!
        #expect(!Readiness.watching(now: now, start: "soon", end: "2027-10-29"))
        #expect(!Readiness.watching(now: now, start: "2027-10-18", end: ""))
    }
}

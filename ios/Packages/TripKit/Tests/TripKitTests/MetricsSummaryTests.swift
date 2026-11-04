import Foundation
import Testing
@testable import TripKit

/// The median read off a MetricKit histogram (launch time, signpost durations): the midpoint of the
/// bucket that holds the middle observation.
@Suite struct MetricsSummaryTests {
    typealias Bucket = MetricsSummary.Bucket

    @Test func noObservationsHaveNoMedian() {
        #expect(MetricsSummary.median([]) == nil)
        #expect(MetricsSummary.median([Bucket(start: 0, end: 10, count: 0)]) == nil)
    }

    @Test func oneBucketGivesItsMidpoint() {
        #expect(MetricsSummary.median([Bucket(start: 400, end: 410, count: 3)]) == 405)
    }

    @Test func theMiddleObservationsBucket() {
        let buckets = [Bucket(start: 0, end: 10, count: 1), Bucket(start: 10, end: 20, count: 1), Bucket(start: 20, end: 30, count: 5)]
        #expect(MetricsSummary.median(buckets) == 25)
    }

    @Test func anEvenTotalTakesTheLowerMiddle() {
        let buckets = [Bucket(start: 0, end: 10, count: 2), Bucket(start: 10, end: 20, count: 2)]
        #expect(MetricsSummary.median(buckets) == 5)
    }

    @Test func bucketsAreReadInOrderOfStart() {
        let buckets = [Bucket(start: 20, end: 30, count: 5), Bucket(start: 0, end: 10, count: 1), Bucket(start: 10, end: 20, count: 1)]
        #expect(MetricsSummary.median(buckets) == 25)
    }

    @Test func unsortedBucketsAreSortedBeforeCounting() {
        // read as given, the middle observation would fall in (0, 10)
        let buckets = [Bucket(start: 20, end: 30, count: 1), Bucket(start: 0, end: 10, count: 1), Bucket(start: 10, end: 20, count: 1)]
        #expect(MetricsSummary.median(buckets) == 15)
    }

    @Test func aSummaryRoundTrips() throws {
        let s = MetricsSummary(begin: Date(timeIntervalSince1970: 1_793_775_600), end: Date(timeIntervalSince1970: 1_793_862_000), scrollHitch: 2.5, hitch: nil, launch: 412, signposts: [.init(name: "sheet.place", count: 7, median: 455)])
        let back = try JSONDecoder().decode(MetricsSummary.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}

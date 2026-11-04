import Foundation
import Testing
@testable import TripKit

/// `Caches/metrics/`: one MetricKit payload is two files under one stem; the 14 newest payloads stay,
/// and nothing that is not ours is ever deleted.
@Suite struct MetricsFolderTests {
    /// 2026-11-05 07:00:00 UTC
    let day = Date(timeIntervalSince1970: 1_793_862_000)

    func both(_ stem: String) -> [String] { [MetricsFolder.payload(stem), MetricsFolder.summary(stem)] }

    func stems(_ n: Int) -> [String] {
        (0..<n).map { MetricsFolder.stem(end: day.addingTimeInterval(Double($0) * 86_400), index: 0) }
    }

    @Test func aStemIsTheEndInUTCThenTheIndex() {
        #expect(MetricsFolder.stem(end: day, index: 0) == "metrics-20261105T070000Z-0")
        #expect(MetricsFolder.stem(end: day.addingTimeInterval(59), index: 3) == "metrics-20261105T070059Z-3")
        #expect(MetricsFolder.payload("metrics-20261105T070000Z-0") == "metrics-20261105T070000Z-0.json")
        #expect(MetricsFolder.summary("metrics-20261105T070000Z-0") == "metrics-20261105T070000Z-0.summary.json")
    }

    @Test func laterStemsSortAfter() {
        let s = stems(3)
        #expect(s == s.sorted())
    }

    @Test func fifteenPayloadsLoseTheOldestTwoFiles() {
        let s = stems(15)
        let names = s.reversed().flatMap(both)
        #expect(Set(MetricsFolder.stale(names)) == Set(both(s[0])))
    }

    @Test func fourteenOrFewerLoseNothing() {
        #expect(MetricsFolder.stale(stems(14).flatMap(both)).isEmpty)
        #expect(MetricsFolder.stale([]).isEmpty)
    }

    @Test func namesThatAreNotOursAreNeverReturned() {
        let foreign = ["notes.txt", ".DS_Store", "metrics-x.json", "metrics-20261105T070000Z.json", "metrics-20261105T070000Z-1.txt", "Metrics-20261105T070000Z-1.json"]
        let names = stems(20).flatMap(both) + foreign
        let stale = Set(MetricsFolder.stale(names))
        #expect(stale.isDisjoint(with: foreign))
        #expect(stale == Set(stems(6).flatMap(both)))
        #expect(Set(MetricsFolder.stale(foreign, keep: 0)).isEmpty)
    }

    @Test func anOrphanSummaryCountsAsAPayload() {
        let s = stems(15)
        let names = s.dropFirst().flatMap(both) + [MetricsFolder.summary(s[0])]
        #expect(MetricsFolder.stale(names) == [MetricsFolder.summary(s[0])])
    }

    @Test func theIndexBreaksTiesAsANumber() {
        let nine = MetricsFolder.stem(end: day, index: 9)
        let ten = MetricsFolder.stem(end: day, index: 10)
        #expect(Set(MetricsFolder.stale(both(nine) + both(ten), keep: 1)) == Set(both(nine)))
    }

    @Test func keepZeroReturnsEveryFileOfOurs() {
        let names = stems(2).flatMap(both) + ["notes.txt"]
        #expect(Set(MetricsFolder.stale(names, keep: 0)) == Set(stems(2).flatMap(both)))
    }
}

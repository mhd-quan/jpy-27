import Testing
@testable import TripKit

/// What Chẩn đoán › Số đo shows from MetricKit's histograms: the median of a histogram, read as
/// grouped data (the value at the middle count, inside the bucket that holds it).
@Suite struct MetricsMedianTests {
    private func b(_ start: Double, _ end: Double, _ count: Int) -> PerfStats.Bucket {
        PerfStats.Bucket(start: start, end: end, count: count)
    }

    @Test func anEmptyHistogramHasNoMedian() {
        #expect(PerfStats.median([]) == nil)
        #expect(PerfStats.median([b(0, 10, 0), b(10, 20, 0)]) == nil)
    }

    @Test func oneBucketGivesItsMiddle() {
        #expect(PerfStats.median([b(10, 20, 3)]) == 15)
        #expect(PerfStats.median([b(10, 20, 1)]) == 15)
    }

    @Test func anEvenTotalInsideOneBucketIsInterpolated() {
        // 4 values: the middle count is 2, one past the first bucket's 1, so halfway through [10, 20)'s 2
        #expect(PerfStats.median([b(0, 10, 1), b(10, 20, 2), b(20, 30, 1)]) == 15)
        #expect(PerfStats.median([b(0, 10, 1), b(10, 20, 4), b(20, 30, 1)]) == 15)
    }

    @Test func theMiddleOnABucketEdgeIsTheEdge() {
        #expect(PerfStats.median([b(0, 10, 2), b(10, 20, 2)]) == 10)
    }

    @Test func theMiddleOnAGapIsTheGapsMiddle() {
        #expect(PerfStats.median([b(0, 10, 2), b(20, 30, 2)]) == 15)
        // empty buckets in the gap do not close it
        #expect(PerfStats.median([b(0, 10, 2), b(10, 20, 0), b(20, 30, 2)]) == 15)
    }

    @Test func bucketsNeedNotBeSorted() {
        #expect(PerfStats.median([b(20, 30, 2), b(0, 10, 2)]) == 15)
        #expect(PerfStats.median([b(10, 20, 2), b(0, 10, 2)]) == 10)
    }

    @Test func theSameBucketTwiceIsOneBucket() {
        // days merged for the per-name median: [10, 20) twice with 1 each is [10, 20) with 2
        #expect(PerfStats.median([b(10, 20, 1), b(10, 20, 1)]) == 15)
        #expect(PerfStats.median([b(0, 10, 1), b(10, 20, 1), b(0, 10, 1), b(10, 20, 1)]) == 10)
    }
}

/// `Caches/metrics` keeps the 14 newest payloads, each as a raw file and a digest.
@Suite struct MetricsFilesTests {
    private func files(_ stamps: ClosedRange<Int>) -> [String] {
        stamps.flatMap { s in PerfStats.FileKind.allCases.map { PerfStats.fileName(stamp: s, kind: $0) } }
    }

    @Test func namesCarryTheStampAndTheKind() {
        #expect(PerfStats.fileName(stamp: 1_762_560_000, kind: .payload) == "metrics-1762560000.payload.json")
        #expect(PerfStats.fileName(stamp: 1_762_560_000, kind: .digest) == "metrics-1762560000.digest.json")
        #expect(PerfStats.stamp("metrics-1762560000.digest.json") == 1_762_560_000)
    }

    @Test func fifteenPayloadsLoseTheOldest() {
        let names = files(101...115).shuffled()
        #expect(PerfStats.stale(names) == ["metrics-101.digest.json", "metrics-101.payload.json"])
    }

    @Test func fourteenPayloadsLoseNothing() {
        #expect(PerfStats.stale(files(101...114)) == [])
    }

    @Test func newestIsByStampNotByName() {
        // "metrics-99" sorts after "metrics-100" as text, but is older
        let names = files(99...99) + files(100...113)
        #expect(PerfStats.stale(names) == ["metrics-99.digest.json", "metrics-99.payload.json"])
    }

    @Test func aLoneFileCountsAsItsPayload() {
        let names = files(101...114) + [PerfStats.fileName(stamp: 100, kind: .digest)]
        #expect(PerfStats.stale(names) == ["metrics-100.digest.json"])
    }

    @Test func filesNotNamedByTheAppAreNeverDeleted() {
        let foreign = ["notes.txt", "metrics-12.png", "metrics-abc.payload.json", "metrics-12.other.json",
                       "metrics--3.payload.json", "metrics-012.payload.json", "x-metrics-12.payload.json", ".DS_Store"]
        let stale = PerfStats.stale(files(101...130) + foreign)
        #expect(stale == files(101...116).sorted())
        #expect(PerfStats.stale(foreign).isEmpty)
        #expect(foreign.allSatisfy { PerfStats.stamp($0) == nil })
    }
}

/// One transition measured at a time: a new one ends the one still open, and nothing ends twice.
@Suite struct TransitionSlotTests {
    @Test func theFirstBeginReplacesNothing() {
        var slot = TransitionSlot()
        let a = slot.begin()
        #expect(a.replaced == nil)
        #expect(slot.open == a.id)
    }

    @Test func aBeginEndsTheOneStillOpen() {
        var slot = TransitionSlot()
        let a = slot.begin()
        let b = slot.begin()
        #expect(b.replaced == a.id)
        #expect(b.id != a.id)
        #expect(slot.open == b.id)
    }

    @Test func onlyTheOpenOneEnds() {
        var slot = TransitionSlot()
        let a = slot.begin()
        let b = slot.begin()
        // a was ended by b's begin: its destination settling later ends nothing
        let endedA = slot.end(a.id)
        #expect(!endedA)
        #expect(slot.open == b.id)
        let endedB = slot.end(b.id)
        #expect(endedB)
        #expect(slot.open == nil)
    }

    @Test func nothingEndsTwice() {
        var slot = TransitionSlot()
        let a = slot.begin()
        let first = slot.end(a.id)
        let second = slot.end(a.id)
        #expect(first)
        #expect(!second)
        // and a begin after an end replaces nothing
        let next = slot.begin()
        #expect(next.replaced == nil)
    }

    @Test func theFirstFrameCountsOnce() {
        var slot = TransitionSlot()
        let a = slot.begin()
        let once = slot.firstFrame(a.id)
        let twice = slot.firstFrame(a.id)
        #expect(once)
        #expect(!twice)
        let b = slot.begin()
        let replacedFrame = slot.firstFrame(a.id)
        let newFrame = slot.firstFrame(b.id)
        #expect(!replacedFrame)
        #expect(newFrame)
        let ended = slot.end(b.id)
        let afterEnd = slot.firstFrame(b.id)
        #expect(ended)
        #expect(!afterEnd)
    }

    @Test func aFreshMarkGetsItsOwnFirstFrame() {
        var slot = TransitionSlot()
        let a = slot.begin()
        _ = slot.firstFrame(a.id)
        let b = slot.begin()
        let framed = slot.firstFrame(b.id)
        #expect(framed)
    }

    @Test func idsNeverRepeat() {
        var slot = TransitionSlot()
        var seen = Set<Int>()
        for _ in 0..<50 {
            let next = slot.begin()
            #expect(seen.insert(next.id).inserted)
            if next.id % 3 == 0 { _ = slot.end(next.id) }
        }
    }
}

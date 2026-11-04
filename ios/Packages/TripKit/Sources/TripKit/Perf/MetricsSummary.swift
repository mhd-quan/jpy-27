import Foundation

/// What Chẩn đoán › Số đo shows of one MetricKit payload. The app builds it from MetricKit's typed API
/// when the payload arrives (MetricKit's JSON gives values as strings with units, in a form Apple does
/// not document), and keeps it next to the payload's JSON in `Caches/metrics/`.
public struct MetricsSummary: Codable, Sendable, Equatable {
    /// One bar of a MetricKit histogram, in milliseconds.
    public struct Bucket: Sendable, Equatable {
        public let start: Double
        public let end: Double
        public let count: Int
        public init(start: Double, end: Double, count: Int) {
            self.start = start
            self.end = end
            self.count = count
        }
    }

    /// A signpost name MetricKit aggregated over the payload's day: how many, and the median length (ms)
    /// of the intervals (nil for events).
    public struct Signpost: Codable, Sendable, Equatable {
        public let name: String
        public let count: Int
        public let median: Double?
        public init(name: String, count: Int, median: Double?) {
            self.name = name
            self.count = count
            self.median = median
        }
    }

    public let begin: Date
    public let end: Date
    /// time spent hitching while scrolling, ms per s (`MXAnimationMetric.scrollHitchTimeRatio`)
    public let scrollHitch: Double?
    /// time spent hitching in any animation, ms per s (`MXAnimationMetric.hitchTimeRatio`)
    public let hitch: Double?
    /// median time to first draw at launch, ms (`MXAppLaunchMetric.histogrammedTimeToFirstDraw`)
    public let launch: Double?
    public let signposts: [Signpost]

    public init(begin: Date, end: Date, scrollHitch: Double?, hitch: Double?, launch: Double?, signposts: [Signpost]) {
        self.begin = begin
        self.end = end
        self.scrollHitch = scrollHitch
        self.hitch = hitch
        self.launch = launch
        self.signposts = signposts
    }

    /// The midpoint of the bucket that holds the middle observation (the lower middle one for an even
    /// total); nil when the histogram holds none.
    public static func median(_ buckets: [Bucket]) -> Double? {
        let sorted = buckets.filter { $0.count > 0 }.sorted { $0.start < $1.start }
        let total = sorted.reduce(0) { $0 + $1.count }
        guard total > 0 else { return nil }
        let middle = (total + 1) / 2
        var seen = 0
        for b in sorted {
            seen += b.count
            if seen >= middle { return (b.start + b.end) / 2 }
        }
        return nil
    }
}

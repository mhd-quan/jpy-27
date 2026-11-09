/// What the app measures about itself, as plain values: the medians Chẩn đoán › Số đo shows from
/// MetricKit's histograms, which payload files `Caches/metrics` keeps, and the one transition being
/// measured at a time. The app converts MetricKit's types to these; nothing here knows MetricKit.
public enum PerfStats {
    /// One bar of a histogram: `count` values in [start, end), in the app's unit (milliseconds).
    public struct Bucket: Sendable, Hashable, Codable {
        public var start: Double
        public var end: Double
        public var count: Int

        public init(start: Double, end: Double, count: Int) {
            self.start = start
            self.end = end
            self.count = count
        }
    }

    private struct Span: Hashable {
        let start: Double
        let end: Double
    }

    /// The median of a histogram read as grouped data: the value at the middle count (half the
    /// total), interpolated inside the bucket that holds it. Buckets with the same bounds are one
    /// bucket (days merged); empty ones are left out. When the middle count falls exactly at the end
    /// of a bucket and the next one starts later, the median is the middle of the gap. Nil when the
    /// histogram holds nothing.
    public static func median(_ buckets: [Bucket]) -> Double? {
        var counts: [Span: Int] = [:]
        for b in buckets where b.count > 0 {
            counts[Span(start: b.start, end: b.end), default: 0] += b.count
        }
        let sorted = counts.sorted { ($0.key.start, $0.key.end) < ($1.key.start, $1.key.end) }
        let total = sorted.reduce(0) { $0 + $1.value }
        guard total > 0 else { return nil }
        let middle = Double(total) / 2
        var below = 0.0
        for (i, (span, count)) in sorted.enumerated() {
            let c = Double(count)
            if middle <= below + c {
                if middle == below + c, i + 1 < sorted.count, sorted[i + 1].key.start > span.end {
                    return (span.end + sorted[i + 1].key.start) / 2
                }
                return span.start + (span.end - span.start) * (middle - below) / c
            }
            below += c
        }
        return nil
    }

    /// payloads kept in `Caches/metrics`, newest first: two weeks of MetricKit's daily reports
    public static let kept = 14

    /// The two files of one payload: MetricKit's own JSON (shared from Số đo) and the app's digest
    /// of it (what Số đo reads).
    public enum FileKind: String, Sendable, CaseIterable {
        case payload, digest
    }

    private static let prefix = "metrics-"
    private static let suffix = ".json"

    /// "metrics-<stamp>.<kind>.json"; the stamp is the end of the payload's period, in whole seconds
    /// since 1970.
    public static func fileName(stamp: Int, kind: FileKind) -> String {
        "\(prefix)\(stamp).\(kind.rawValue)\(suffix)"
    }

    /// The stamp of a name `fileName` made; nil for any other name.
    public static func stamp(_ name: String) -> Int? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix), name.count > prefix.count + suffix.count else { return nil }
        let core = name.dropFirst(prefix.count).dropLast(suffix.count)
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, FileKind(rawValue: String(parts[1])) != nil,
              let stamp = Int(parts[0]), stamp >= 0, String(stamp) == parts[0] else { return nil }
        return stamp
    }

    /// The names to delete from `names` (the folder's listing): every file of a payload older than
    /// the `keeping` newest, sorted. A name `fileName` did not make is never returned.
    public static func stale(_ names: [String], keeping: Int = kept) -> [String] {
        let newestFirst = Set(names.compactMap(stamp)).sorted(by: >)
        let old = Set(newestFirst.dropFirst(max(0, keeping)))
        return names.filter { stamp($0).map(old.contains) ?? false }.sorted()
    }
}

/// The one transition measured at a time (`Perf.transition`). A new one ends the one still open, an
/// end counts only for the open one (so nothing ends twice), and the first frame counts once.
public struct TransitionSlot: Sendable, Hashable {
    /// the transition being measured, if any
    public private(set) var open: Int?
    private var framed = false
    private var last = 0

    public init() {}

    /// Opens a new transition; `replaced` is the one it ended, which the caller closes.
    public mutating func begin() -> (id: Int, replaced: Int?) {
        let replaced = open
        last += 1
        open = last
        framed = false
        return (last, replaced)
    }

    /// True the first time it is asked for the open transition: its first frame is to be marked.
    public mutating func firstFrame(_ id: Int) -> Bool {
        guard open == id, !framed else { return false }
        framed = true
        return true
    }

    /// True when `id` is the open transition: it ends now, and is to be closed.
    public mutating func end(_ id: Int) -> Bool {
        guard open == id else { return false }
        open = nil
        framed = false
        return true
    }
}

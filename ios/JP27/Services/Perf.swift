import Foundation
import MetricKit
import os
import TripKit

// The app's own numbers: how long a transition takes from the tap to the end of its animation, and
// what MetricKit reports once a day (hitches, launch time, those transitions in the field). Read in
// Instruments (os_signpost) and in Cài đặt › Chẩn đoán › Số đo; docs/perf/2026-11-baseline.md says
// which name is which scenario.

enum Perf {
    /// Instruments' os_signpost: subsystem "tech.delphyra.jp27", category "perf"
    nonisolated static let signposter = OSSignposter(subsystem: "tech.delphyra.jp27", category: "perf")
    /// the same intervals and events for MetricKit, which gathers only signposts on its own log
    nonisolated static let metricsLog = MXMetricManager.makeLogHandle(category: "perf")

    /// a mark nobody settled is ended this long after its begin: never left open
    static let timeoutAfter: Duration = .seconds(3)

    /// How a transition's interval ended (the end message in Instruments): by its destination's
    /// probe, by the probe's 1 s cap, by a newer transition, or by `timeoutAfter`.
    enum End {
        case settled, cap, replaced, timeout
    }

    private struct Open {
        let id: Int
        let name: StaticString
        let state: OSSignpostIntervalState
        let signpost: OSSignpostID
        let metric: OSSignpostID
    }

    private static var slot = TransitionSlot()
    private static var open: Open?
    private static var timeout: Task<Void, Never>?

    /// Begins measuring a transition named `name` (one of a fixed set: `push.<tab>`, `sheet.<kind>`),
    /// ending the one still open. Its destination takes it (`current`) on its first appearance.
    @discardableResult
    static func transition(_ name: StaticString) -> TransitionMark {
        let begun = slot.begin()
        if let replaced = begun.replaced, let previous = open, previous.id == replaced {
            close(previous, .replaced)
        }
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval(name, id: id)
        let metric = OSSignpostID(log: metricsLog)
        mxSignpostAnimationIntervalBegin(log: metricsLog, name: name, signpostID: metric)
        open = Open(id: begun.id, name: name, state: state, signpost: id, metric: metric)
        timeout?.cancel()
        timeout = Task {
            try? await Task.sleep(for: timeoutAfter)
            guard !Task.isCancelled else { return }
            end(begun.id, .timeout)
        }
        return TransitionMark(id: begun.id)
    }

    /// The transition still being measured, for its destination to take.
    static var current: TransitionMark? {
        open.map { TransitionMark(id: $0.id) }
    }

    /// A moment worth seeing on the timeline (5.4: `map.fly`), in Instruments and in MetricKit.
    nonisolated static func mark(_ name: StaticString) {
        signposter.emitEvent(name)
        mxSignpost(.event, log: metricsLog, name: name)
    }

    fileprivate static func firstFrame(_ id: Int) {
        guard slot.firstFrame(id), let o = open, o.id == id else { return }
        signposter.emitEvent("first-frame", id: o.signpost)
    }

    fileprivate static func end(_ id: Int, _ how: End) {
        guard slot.end(id), let o = open, o.id == id else { return }
        open = nil
        timeout?.cancel()
        timeout = nil
        close(o, how)
    }

    private static func close(_ o: Open, _ how: End) {
        switch how {
        case .settled: signposter.endInterval(o.name, o.state, "settled")
        case .cap: signposter.endInterval(o.name, o.state, "cap")
        case .replaced: signposter.endInterval(o.name, o.state, "replaced")
        case .timeout: signposter.endInterval(o.name, o.state, "timeout")
        }
        mxSignpost(.end, log: metricsLog, name: o.name, signpostID: o.metric)
    }
}

/// One transition being measured: a copy ends nothing twice (`TransitionSlot`).
struct TransitionMark: Equatable {
    fileprivate let id: Int

    /// The destination appeared: the `first-frame` event, once.
    func firstFrame() {
        Perf.firstFrame(id)
    }

    /// The transition is over: the interval ends, if this is still the one being measured.
    func settled(_ how: Perf.End = .settled) {
        Perf.end(id, how)
    }
}

// MARK: - MetricKit

/// What Số đo reads of one MetricKit payload, taken from its typed values when it arrives (the
/// payload's JSON has no documented shape to read back). Durations in milliseconds.
nonisolated struct MetricsDigest: Codable, Sendable {
    /// a MetricKit ratio as it came: its value and its unit's symbol (ms per s)
    nonisolated struct Ratio: Codable, Sendable {
        var value: Double
        var unit: String
    }

    nonisolated struct Signpost: Codable, Sendable {
        var name: String
        var count: Int
        var buckets: [PerfStats.Bucket]
        var hitches: Ratio?
    }

    var begin: Date
    var end: Date
    var scrollHitches: Ratio?
    var hitches: Ratio?
    var launch: [PerfStats.Bucket]
    var signposts: [Signpost]
}

/// Takes MetricKit's daily payloads: each kept in `Caches/metrics` as its JSON (shared from Số đo)
/// and a digest (shown there), the `PerfStats.kept` newest only. MetricKit does not say which thread
/// it calls on, so nothing here is on the main actor.
nonisolated final class MetricsInbox: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = MetricsInbox()

    static let folder = URL.cachesDirectory.appending(path: "metrics", directoryHint: .isDirectory)

    func didReceive(_ payloads: [MXMetricPayload]) {
        let files = FileManager.default
        // a cache: a payload not written is a day missing from Số đo, nothing more
        try? files.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        for payload in payloads {
            let stamp = Int(payload.timeStampEnd.timeIntervalSince1970)
            try? payload.jsonRepresentation().write(to: Self.file(stamp, .payload), options: .atomic)
            if let digest = try? encoder.encode(Self.digest(payload)) {
                try? digest.write(to: Self.file(stamp, .digest), options: .atomic)
            }
        }
        Self.trim()
    }

    private static func file(_ stamp: Int, _ kind: PerfStats.FileKind) -> URL {
        folder.appending(path: PerfStats.fileName(stamp: stamp, kind: kind), directoryHint: .notDirectory)
    }

    /// Deletes the payloads older than the newest `PerfStats.kept`, in this folder only.
    private static func trim() {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
        for name in PerfStats.stale(names) {
            try? files.removeItem(at: folder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    private static func digest(_ payload: MXMetricPayload) -> MetricsDigest {
        let animation = payload.animationMetrics
        let signposts = (payload.signpostMetrics ?? []).compactMap { metric -> MetricsDigest.Signpost? in
            guard metric.signpostCategory == "perf", let data = metric.signpostIntervalData else { return nil }
            return MetricsDigest.Signpost(
                name: metric.signpostName,
                count: metric.totalCount,
                buckets: buckets(data.histogrammedSignpostDuration),
                hitches: data.cumulativeHitchTimeRatio.map(ratio)
            )
        }
        return MetricsDigest(
            begin: payload.timeStampBegin,
            end: payload.timeStampEnd,
            scrollHitches: animation.map { ratio($0.scrollHitchTimeRatio) },
            hitches: animation.map { ratio($0.hitchTimeRatio) },
            launch: payload.applicationLaunchMetrics.map { buckets($0.histogrammedTimeToFirstDraw) } ?? [],
            signposts: signposts
        )
    }

    private static func ratio(_ m: Measurement<Unit>) -> MetricsDigest.Ratio {
        MetricsDigest.Ratio(value: m.value, unit: m.unit.symbol)
    }

    private static func buckets(_ histogram: MXHistogram<UnitDuration>) -> [PerfStats.Bucket] {
        var out: [PerfStats.Bucket] = []
        for case let bucket as MXHistogramBucket<UnitDuration> in histogram.bucketEnumerator {
            out.append(PerfStats.Bucket(
                start: bucket.bucketStart.converted(to: .milliseconds).value,
                end: bucket.bucketEnd.converted(to: .milliseconds).value,
                count: bucket.bucketCount
            ))
        }
        return out
    }

    /// What is kept, read off the main actor: the digests newest first, and the payloads' JSON files
    /// to share.
    @concurrent static func stored() async -> (digests: [MetricsDigest], payloads: [URL]) {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return ([], []) }
        let newestFirst = names.compactMap { name in PerfStats.stamp(name).map { (name, $0) } }
            .sorted { $0.1 > $1.1 }
        let decoder = JSONDecoder()
        var digests: [MetricsDigest] = []
        var payloads: [URL] = []
        for (name, _) in newestFirst {
            let url = folder.appending(path: name, directoryHint: .notDirectory)
            if name.hasSuffix(".\(PerfStats.FileKind.payload.rawValue).json") {
                payloads.append(url)
            } else if let data = try? Data(contentsOf: url), let digest = try? decoder.decode(MetricsDigest.self, from: data) {
                digests.append(digest)
            }
        }
        return (digests, payloads)
    }
}

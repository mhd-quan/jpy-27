import Foundation
import MetricKit
import os
import SwiftUI
import TripKit

// Measures, for docs/perf/2026-11-baseline.md and Chẩn đoán › Số đo. Nothing here changes what the app
// does: a tap begins a signpost interval, the page it opens marks its first frame and, once the
// transition has had time to end, closes it; a few moments are marked as events; MetricKit's daily
// reports are kept in Caches/metrics/.
//
// In Instruments (os_signpost, Points of Interest), subsystem tech.delphyra.jp27: one interval
// "transition" per tap, labelled "map → place", "today → day", with an event "first-frame", ending
// "settled", "dismissed" (the page closed, or was covered or left, before it settled), "superseded" or
// "expired". Each transition also has a MetricKit twin under its own name ("sheet.place",
// "push.today", "cover.phrase") for the daily reports; the twins of transitions that did not settle end
// too, so MetricKit's medians per name include them.

/// The app's instrumentation: signposts, its own record of transitions, MetricKit's log.
enum Perf {
    /// Points of Interest, so the intervals show without any setup in Instruments.
    static let signposter = OSSignposter(subsystem: "tech.delphyra.jp27", category: .pointsOfInterest)
    /// The log MetricKit aggregates into each day's `MXSignpostMetric`s.
    static let metrics = MXMetricManager.makeLogHandle(category: "JP27")

    /// Where a page finds the tap that opened it: a tap and its page meet in the same slot.
    enum Slot: String {
        /// `AppModel.present`, the app's sheet stack
        case sheet
        /// a tab's `NavigationPath` grown by a tap
        case push
        /// the phrase card (`phraseCover`)
        case cover
    }

    /// How long a page that came in by a transition waits before it counts as settled
    /// (`transitionSettled`). These are **bounds, not measurements**: SwiftUI reports no end of a push, a
    /// sheet or a zoom (R-212), so the transition is given this long from its first frame. A push slides
    /// in 350 ms; a sheet, the phrase card and the home's zoom into a day spring in longer.
    enum Settle {
        case push
        case modal

        var delay: Duration {
            switch self {
            case .push: .milliseconds(350)
            case .modal: .milliseconds(500)
            }
        }
    }

    /// Transitions since launch and the marks counted, for the Số đo page (memory only).
    private(set) static var log = TransitionLog()
    /// the transition waiting for its page, in each slot
    private static var waiting: [Slot: TransitionMark] = [:]
    private static var lastID = 0

    /// A tap that opens a page: begins its interval and waits in `slot` for the page to claim it.
    /// `name` is the MetricKit twin's name (one of a fixed set); `source` is where the tap was (a
    /// `sheetSource` id, or the tab), `page` what it opens when the tap knows.
    @discardableResult
    static func transition(_ name: StaticString, slot: Slot, from source: String?, to page: String?) -> TransitionMark {
        lastID += 1
        let label = TransitionLog.label(from: source, to: page)
        let signpostID = signposter.makeSignpostID()
        let state = signposter.beginInterval("transition", id: signpostID, "\(label, privacy: .public)")
        let metricID = OSSignpostID(log: metrics)
        mxSignpost(.begin, log: metrics, name: name, signpostID: metricID)
        let mark = TransitionMark(id: lastID, name: name, signpostID: signpostID, state: state, metricID: metricID)
        let begun = log.begin(lastID, slot: slot.rawValue, from: source, to: page, at: .now)
        // taps no page answered: past the window, in any slot, then the one this tap replaces
        for id in begun.expired {
            if let entry = waiting.first(where: { $0.value.id == id }) {
                entry.value.end("expired")
                waiting[entry.key] = nil
            }
        }
        if let replaced = begun.superseded, let old = waiting[slot], old.id == replaced {
            old.end("superseded")
        }
        waiting[slot] = mark
        return mark
    }

    /// A page's first frame: the tap it answers, if one waits in `slot` (one that waited too long is
    /// ended unpaired). `page` names the page when the tap could not (a push).
    static func claim(_ slot: Slot, page: String?) -> TransitionMark? {
        let mark = waiting.removeValue(forKey: slot)
        switch log.claim(slot.rawValue, page: page, at: .now) {
        case .none:
            return nil
        case .claimed(let id):
            return mark?.id == id ? mark : nil
        case .expired(let id):
            if let mark, mark.id == id { mark.end("expired") }
            return nil
        }
    }

    /// One moment: an event in Points of Interest and in MetricKit's log, and a count on the Số đo page.
    /// Only for what happens once per user action (a tap, a photo settled, one camera move asked for),
    /// never once per frame: each call makes a `String` of the name for the count.
    static func mark(_ name: StaticString) {
        signposter.emitEvent(name)
        mxSignpost(.event, log: metrics, name: name)
        log.count(String(describing: name))
    }

    fileprivate static func settle(_ id: Int) -> Bool {
        log.settle(id, at: .now)
    }

    fileprivate static func drop(_ id: Int) -> Bool {
        log.drop(id)
    }
}

/// One transition, from the tap that began it; ended once, by the page that claimed it.
struct TransitionMark {
    let id: Int
    let name: StaticString
    let signpostID: OSSignpostID
    let state: OSSignpostIntervalState
    let metricID: OSSignpostID

    /// The page is about to draw its first frame (its `onAppear`).
    func firstFrame() {
        Perf.signposter.emitEvent("first-frame", id: signpostID)
    }

    /// The transition has had its time (`Perf.Settle`): ends the interval and records it.
    func settled() {
        guard Perf.settle(id) else { return }
        end("settled")
    }

    /// The page went before it settled: closed, or covered or left (a tab switch, a page pushed on top, a
    /// full-screen cover over it). Ends the interval ("dismissed"), records nothing.
    func dismissed() {
        guard Perf.drop(id) else { return }
        end("dismissed")
    }

    /// Ends both intervals. Only through `settled`, `dismissed` or `Perf` itself, so once.
    fileprivate func end(_ how: String) {
        Perf.signposter.endInterval("transition", state, "\(how, privacy: .public)")
        mxSignpost(.end, log: Perf.metrics, name: name, signpostID: metricID)
    }
}

extension AppSheet {
    /// The MetricKit name of its transition, and the page it opens as the Số đo page names it.
    var perf: (name: StaticString, page: String) {
        switch self {
        case .place: ("sheet.place", "place")
        case .ride: ("sheet.ride", "ride")
        case .expense: ("sheet.expense", "expense")
        case .atPlace: ("sheet.atPlace", "atPlace")
        case .menuScan: ("sheet.menuScan", "menuScan")
        case .listen: ("sheet.listen", "listen")
        case .fujiFinder: ("sheet.fujiFinder", "fujiFinder")
        case .fujiSpot: ("sheet.fujiSpot", "fujiSpot")
        case .journal: ("sheet.journal", "journal")
        case .settings: ("sheet.settings", "settings")
        }
    }
}

extension Route {
    /// The page a push of this route opens, as the Số đo page names it.
    var perfPage: String {
        switch self {
        case .day: "day"
        case .place: "place"
        case .ride: "ride"
        case .journal: "journal"
        case .food: "food"
        case .stays: "stays"
        case .stay: "stay"
        case .fuji: "fuji"
        case .trains: "trains"
        case .bookings: "bookings"
        case .handbook: "handbook"
        case .scenario: "scenario"
        case .budget: "budget"
        case .shopping: "shopping"
        case .slot: "slot"
        case .highlight: "highlight"
        }
    }
}

extension FujiPage {
    /// The page a push of this Fuji page opens, as the Số đo page names it.
    var perfPage: String {
        switch self {
        case .map: "fuji.map"
        case .kawaguchiko: "kawaguchiko"
        }
    }
}

// MARK: - MetricKit

/// Receives MetricKit's daily reports and keeps the 14 newest in Caches/metrics/: MetricKit's own JSON
/// (shared from Số đo) and the `MetricsSummary` the page shows.
///
/// Not on the main actor: MetricKit calls `didReceive` on a thread of its own ("safe to process the
/// payload on a separate thread"), and a main-actor conformance would trap there. The files are written
/// on that thread, and nothing of the app's state is touched.
nonisolated final class MetricsInbox: NSObject, MXMetricManagerSubscriber, Sendable {
    static let shared = MetricsInbox()

    private static let log = Logger(subsystem: "tech.delphyra.jp27", category: "metrics")

    static var folder: URL { URL.cachesDirectory.appending(path: "metrics", directoryHint: .isDirectory) }

    func didReceive(_ payloads: [MXMetricPayload]) {
        let folder = Self.folder
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Self.log.error("metrics folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        for (index, payload) in payloads.enumerated() {
            let stem = MetricsFolder.stem(end: payload.timeStampEnd, index: index)
            do {
                try payload.jsonRepresentation().write(to: folder.appending(path: MetricsFolder.payload(stem)), options: .atomic)
                try JSONEncoder().encode(Self.summary(of: payload)).write(to: folder.appending(path: MetricsFolder.summary(stem)), options: .atomic)
            } catch {
                Self.log.error("metrics \(stem, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        Self.prune(folder)
    }

    /// What the Số đo page shows of a payload, read through MetricKit's typed API.
    private static func summary(of payload: MXMetricPayload) -> MetricsSummary {
        let animation = payload.animationMetrics
        return MetricsSummary(
            begin: payload.timeStampBegin,
            end: payload.timeStampEnd,
            scrollHitch: animation?.scrollHitchTimeRatio.value,
            hitch: animation?.hitchTimeRatio.value,
            launch: payload.applicationLaunchMetrics.flatMap { MetricsSummary.median(buckets($0.histogrammedTimeToFirstDraw)) },
            signposts: (payload.signpostMetrics ?? []).map { s in
                MetricsSummary.Signpost(
                    name: s.signpostName,
                    count: s.totalCount,
                    median: s.signpostIntervalData.flatMap { MetricsSummary.median(buckets($0.histogrammedSignpostDuration)) }
                )
            }
        )
    }

    private static func buckets(_ histogram: MXHistogram<UnitDuration>) -> [MetricsSummary.Bucket] {
        histogram.bucketEnumerator.compactMap { $0 as? MXHistogramBucket<UnitDuration> }.map { b in
            MetricsSummary.Bucket(
                start: b.bucketStart.converted(to: .milliseconds).value,
                end: b.bucketEnd.converted(to: .milliseconds).value,
                count: b.bucketCount
            )
        }
    }

    /// Deletes what `MetricsFolder.stale` names, and only that: never a file that is not ours.
    private static func prune(_ folder: URL) {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        } catch {
            log.error("metrics list: \(error.localizedDescription, privacy: .public)")
            return
        }
        for name in MetricsFolder.stale(names) {
            do {
                try FileManager.default.removeItem(at: folder.appending(path: name))
            } catch {
                log.error("metrics delete \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// The reports kept, newest first, and MetricKit's JSON files to share.
    nonisolated struct Stored: Sendable {
        var days: [MetricsSummary] = []
        var files: [URL] = []
    }

    /// Reads Caches/metrics/ off the main thread (a summary that cannot be read is left out).
    @concurrent nonisolated static func stored() async -> Stored {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil) else { return Stored() }
        var stored = Stored()
        for url in urls {
            let name = url.lastPathComponent
            guard name.hasPrefix("metrics-") else { continue }
            if name.hasSuffix(".summary.json") {
                if let data = try? Data(contentsOf: url), let day = try? JSONDecoder().decode(MetricsSummary.self, from: data) {
                    stored.days.append(day)
                }
            } else if name.hasSuffix(".json") {
                stored.files.append(url)
            }
        }
        stored.days.sort { $0.end > $1.end }
        stored.files.sort { $0.lastPathComponent > $1.lastPathComponent }
        return stored
    }
}

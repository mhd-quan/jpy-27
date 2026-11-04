/// The app's own record of its transitions, for Chẩn đoán › Số đo: how long from a tap to the first
/// frame of the page it opens, and to the end of the transition (`Perf` in the app keeps one).
///
/// A tap begins a transition in a slot (`sheet`, `push`, `cover`); the page that appears next in that
/// slot claims it at its first frame and settles it when the transition is over. Pairing goes through
/// here so that a tap no page answers is never paired with a later, unrelated page, and so that each
/// transition ends once: `settle` and `drop` say true only the first time.
public struct TransitionLog: Sendable {
    public typealias Instant = ContinuousClock.Instant

    /// A page claims only a tap this recent; an older one waiting is ended unpaired.
    public static let claimWindow: Duration = .seconds(3)
    /// Medians are taken over the newest this many samples of each name.
    public static let samplesKept = 50
    /// Transitions claimed and never ended are forgotten past this many (a bound on memory only: a page
    /// always ends the one it claimed).
    public static let openKept = 32

    public enum Claim: Sendable, Equatable {
        /// no tap waiting in the slot
        case none
        /// the tap this page answers
        case claimed(Int)
        /// the tap waiting was older than `claimWindow`: end it unpaired
        case expired(Int)
    }

    /// One name on the page: how many settled, and the medians of the newest `samplesKept`.
    public struct Row: Sendable, Equatable {
        public let name: String
        public let count: Int
        public let firstFrame: Duration?
        public let settled: Duration?

        public init(name: String, count: Int, firstFrame: Duration?, settled: Duration?) {
            self.name = name
            self.count = count
            self.firstFrame = firstFrame
            self.settled = settled
        }
    }

    /// A `Perf.mark` name and how many times it was marked.
    public struct Mark: Sendable, Equatable {
        public let name: String
        public let count: Int

        public init(name: String, count: Int) {
            self.name = name
            self.count = count
        }
    }

    private struct Waiting: Sendable {
        let id: Int
        let from: String?
        let to: String?
        let at: Instant
    }

    private struct Open: Sendable {
        let name: String
        let at: Instant
        let firstFrame: Duration
    }

    private struct Sample: Sendable {
        let firstFrame: Duration
        let settled: Duration
    }

    private var waiting: [String: Waiting] = [:]
    private var open: [Int: Open] = [:]
    /// claimed ids, oldest first, for `openKept`
    private var order: [Int] = []
    private var samples: [String: [Sample]] = [:]
    private var totals: [String: Int] = [:]
    private var counts: [String: Int] = [:]

    public init() {}

    /// What a new tap ends unpaired (the caller ends their intervals).
    public struct Begun: Sendable, Equatable {
        /// the transition still waiting in the same slot, which the new one replaces
        public let superseded: Int?
        /// transitions waiting, in any slot, for longer than `claimWindow` (no page answered them), by id
        public let expired: [Int]

        public init(superseded: Int?, expired: [Int]) {
            self.superseded = superseded
            self.expired = expired
        }
    }

    /// A tap began transition `id` toward a page that will claim it in `slot`. A tap no page answered
    /// would otherwise wait for ever: every new tap first ends those waiting past `claimWindow`, in any
    /// slot, then replaces the one still waiting in its own.
    public mutating func begin(_ id: Int, slot: String, from: String?, to: String?, at: Instant) -> Begun {
        let stale = waiting.filter { $0.value.at.duration(to: at) > Self.claimWindow }
        for key in stale.keys { waiting[key] = nil }
        let replaced = waiting[slot]?.id
        waiting[slot] = Waiting(id: id, from: from, to: to, at: at)
        return Begun(superseded: replaced, expired: stale.values.map(\.id).sorted())
    }

    /// A page's first frame, in `slot`: claims the transition waiting there. `page` names the destination
    /// when the tap could not (a push, whose tap knows only the stack it grew).
    public mutating func claim(_ slot: String, page: String?, at: Instant) -> Claim {
        guard let w = waiting.removeValue(forKey: slot) else { return .none }
        let firstFrame = w.at.duration(to: at)
        guard firstFrame <= Self.claimWindow else { return .expired(w.id) }
        open[w.id] = Open(name: Self.label(from: w.from, to: w.to ?? page), at: w.at, firstFrame: firstFrame)
        order.append(w.id)
        while order.count > Self.openKept {
            open[order.removeFirst()] = nil
        }
        return .claimed(w.id)
    }

    /// True once, for a claimed transition still open: records its first frame and its end under its name.
    public mutating func settle(_ id: Int, at: Instant) -> Bool {
        guard let o = open.removeValue(forKey: id) else { return false }
        order.removeAll { $0 == id }
        var kept = samples[o.name, default: []]
        kept.append(Sample(firstFrame: o.firstFrame, settled: o.at.duration(to: at)))
        if kept.count > Self.samplesKept { kept.removeFirst(kept.count - Self.samplesKept) }
        samples[o.name] = kept
        totals[o.name, default: 0] += 1
        return true
    }

    /// Ended without settling (the page went before it settled): true if it was open or waiting; records
    /// nothing.
    public mutating func drop(_ id: Int) -> Bool {
        if open.removeValue(forKey: id) != nil {
            order.removeAll { $0 == id }
            return true
        }
        if let slot = waiting.first(where: { $0.value.id == id })?.key {
            waiting[slot] = nil
            return true
        }
        return false
    }

    /// A `Perf.mark`, counted by name.
    public mutating func count(_ name: String) {
        counts[name, default: 0] += 1
    }

    /// Every name that settled at least once, by name.
    public var rows: [Row] {
        totals.keys.sorted().map { name in
            let kept = samples[name] ?? []
            return Row(name: name, count: totals[name] ?? 0, firstFrame: Self.median(kept.map(\.firstFrame)), settled: Self.median(kept.map(\.settled)))
        }
    }

    /// The marks counted, by name.
    public var marks: [Mark] {
        counts.keys.sorted().map { Mark(name: $0, count: counts[$0] ?? 0) }
    }

    /// "map → place": the first dot-separated part of the source (where the tap was), an arrow, the
    /// destination; either alone when the other is unknown.
    public static func label(from source: String?, to page: String?) -> String {
        let origin = source?.split(separator: ".", maxSplits: 1).first.map(String.init)
        switch (origin, page) {
        case let (o?, p?): return "\(o) → \(p)"
        case let (o?, nil): return o
        case let (nil, p?): return p
        case (nil, nil): return "?"
        }
    }

    /// The middle value; for an even count, the mean of the middle two.
    public static func median(_ values: [Duration]) -> Duration? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}

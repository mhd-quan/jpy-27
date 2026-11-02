import Foundation
import ImageIO
import TripKit
import UIKit
import WidgetKit

// The widget's own plan clock. It reads the slim plan (Shared/schedule.json) and flips by itself at
// each waypoint; when the app has published a fresh snapshot (marks, lateness, advice) that
// snapshot wins for the waypoint it describes. All times in entries are on the real clock, labels
// are Japan time — they differ only while rehearsing with a shifted clock (Shared.clockOffset).

/// One place or departure to announce.
nonisolated struct WidgetStop: Hashable, Sendable {
    var index: Int
    /// stop, departure, reservation
    var kind: String
    var title: String
    var subtitle: String?
    var placeID: String?
    /// line colour for departures
    var color: String?
    var symbol: String
    /// real clock
    var setOff: Date
    var begin: Date
    /// Japan time labels, "12:32"
    var setOffLabel: String
    var beginLabel: String

    var isDeparture: Bool { kind == "departure" }
}

nonisolated struct NextStopEntry: TimelineEntry, Sendable {
    nonisolated enum State: Hashable, Sendable {
        case before(days: Int, title: String, route: String, dateLabel: String)
        case day(n: Int, title: String, color: String, current: WidgetStop?, after: [WidgetStop], late: Int?, advice: String?, stay: String?)
        case after
        case unavailable
    }

    let date: Date
    let state: State
}

/// The plan, decoded once per extension process.
nonisolated enum WidgetPlan {
    static let store: TripStore? = try? TripStore.load(from: .main, slim: true)

    static func entries(at realNow: Date) -> (entries: [NextStopEntry], refresh: Date) {
        let offset = Shared.clockOffset
        let tripNow = realNow.addingTimeInterval(offset)
        let tomorrow = nextMidnight(after: tripNow).addingTimeInterval(-offset)
        guard let store else { return ([NextStopEntry(date: realNow, state: .unavailable)], tomorrow) }
        let itinerary = Itinerary(store: store)
        let days = store.days(choosing: Shared.alternatives)

        switch itinerary.phase(at: tripNow, days: days) {
        case .before(let n, let first):
            // the next booking window that opens at an exact time says more than the route
            let booking = store.trip.bookings.compactMap { b in b.date.map { (b.title, $0) } }.filter { $0.1 > tripNow }.min { $0.1 < $1.1 }
            let line = booking.map { "Đặt chỗ \(Fmt.shortDate(TripTime.isoDate(of: $0.1))): \($0.0)" } ?? first.route
            let state = NextStopEntry.State.before(days: n, title: first.title, route: line, dateLabel: "\(first.dow), \(Fmt.shortDate(first.date))")
            return ([NextStopEntry(date: realNow, state: state)], tomorrow)

        case .after:
            return ([NextStopEntry(date: realNow, state: .after)], realNow.addingTimeInterval(7 * 86400))

        case .during(let day):
            var list = stops(day, store: store, itinerary: itinerary, offset: offset)
            var late: Int?
            var advice: String?
            var lateUntil = Date.distantPast
            if let snap = Shared.snapshot, snap.day == day.key, tripNow.timeIntervalSince(snap.generated) < 1800,
               let k = list.firstIndex(where: { $0.index >= snap.index }) {
                list.removeFirst(k)
                if list.first?.index == snap.index {
                    list[0].setOff = snap.setOff.addingTimeInterval(-offset)
                    list[0].begin = max(list[0].begin, snap.begin.addingTimeInterval(-offset))
                    late = snap.late
                    advice = snap.advice
                    lateUntil = list[0].begin
                }
            }
            let color = store.chapter(of: day)?.color ?? "#8E8E93"
            let stay = store.place(day.stay)?.name
            var times = Set<Date>([realNow])
            for s in list {
                if s.setOff > realNow { times.insert(s.setOff) }
                if s.begin > realNow { times.insert(s.begin) }
            }
            let entries = times.sorted().prefix(48).map { t -> NextStopEntry in
                let ahead = list.filter { $0.begin > t }
                let behind = t < lateUntil
                return NextStopEntry(date: t, state: .day(
                    n: day.n, title: day.title, color: color, current: ahead.first,
                    after: Array(ahead.dropFirst().prefix(3)),
                    late: behind ? late : nil, advice: behind ? advice : nil, stay: stay))
            }
            return (Array(entries), tomorrow)
        }
    }

    static func stops(_ day: Day, store: TripStore, itinerary: Itinerary, offset: TimeInterval) -> [WidgetStop] {
        itinerary.waypoints(day).compactMap { w -> WidgetStop? in
            guard let setOff = TripTime.date(day.date, minutes: w.setOff),
                  let begin = TripTime.date(day.date, minutes: w.begin) else { return nil }
            let place = store.place(w.placeID)
            let beginLabel = w.planned.map { TripTime.clock(Double($0)) } ?? TripTime.clock(w.begin)
            var stop = WidgetStop(
                index: w.index, kind: "stop", title: place?.name ?? w.title, subtitle: nil, placeID: w.placeID,
                color: nil, symbol: place?.kind.symbol ?? "mappin", setOff: setOff.addingTimeInterval(-offset),
                begin: begin.addingTimeInterval(-offset), setOffLabel: TripTime.clock(w.setOff), beginLabel: beginLabel)
            switch w.kind {
            case .departure:
                let leg = day.items.indices.contains(w.index) ? day.items[w.index].move?.leg : nil
                let line = leg.flatMap { store.line($0.line) }
                stop.kind = "departure"
                stop.title = line?.name ?? w.title
                stop.subtitle = place.map { "từ \($0.name)" }
                stop.color = line?.color
                stop.symbol = line?.mode.symbol ?? "tram.fill"
            case .reservation:
                stop.kind = "reservation"
                stop.subtitle = w.title == stop.title ? nil : w.title
                stop.symbol = "checkmark.seal.fill"
            case .stop:
                stop.subtitle = w.title == stop.title ? nil : w.title
            }
            return stop
        }
    }

    /// The next midnight in Japan after an instant.
    static func nextMidnight(after instant: Date) -> Date {
        let start = TripTime.calendar.startOfDay(for: instant)
        return TripTime.calendar.date(byAdding: .day, value: 1, to: start) ?? instant.addingTimeInterval(86400)
    }

    static let sample = NextStopEntry(date: Date(), state: .day(
        n: 2, title: "Yanaka, Asakusa, Nihonbashi", color: "#F39700",
        current: WidgetStop(index: 12, kind: "stop", title: "Owariya Honten", subtitle: "Soba tempura ở Owariya", placeID: "owariya", color: nil, symbol: "fork.knife",
                            setOff: Date().addingTimeInterval(14 * 60), begin: Date().addingTimeInterval(26 * 60), setOffLabel: "12:32", beginLabel: "12:45"),
        after: [
            WidgetStop(index: 14, kind: "stop", title: "Sensō-ji", subtitle: nil, placeID: "sensoji", color: nil, symbol: "binoculars.fill",
                       setOff: Date().addingTimeInterval(80 * 60), begin: Date().addingTimeInterval(86 * 60), setOffLabel: "13:38", beginLabel: "13:45"),
            WidgetStop(index: 19, kind: "departure", title: "Ginza Line", subtitle: "từ Asakusa", placeID: "st-asakusa", color: "#F39700", symbol: "tram.fill.tunnel",
                       setOff: Date().addingTimeInterval(190 * 60), begin: Date().addingTimeInterval(196 * 60), setOffLabel: "16:08", beginLabel: "16:15"),
        ],
        late: nil, advice: nil, stay: "Hotel RESOL Akihabara"))
}

nonisolated struct NextStopProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextStopEntry {
        WidgetPlan.sample
    }

    func getSnapshot(in context: Context, completion: @escaping (NextStopEntry) -> Void) {
        if context.isPreview {
            completion(WidgetPlan.sample)
            return
        }
        completion(WidgetPlan.entries(at: Date()).entries.first ?? WidgetPlan.sample)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextStopEntry>) -> Void) {
        let (entries, refresh) = WidgetPlan.entries(at: Date())
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

/// The downscaled photo the app wrote to the App Group for a place.
nonisolated enum HeroImage {
    static func load(_ placeID: String?, maxPixel: CGFloat = 720) -> UIImage? {
        guard let placeID else { return nil }
        let url = Shared.hero(placeID)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

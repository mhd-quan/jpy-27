import Foundation

/// A notification the plan asks for. The app turns these into UNNotificationRequests; departures
/// and reservations break through Focus as Time Sensitive.
public struct Reminder: Sendable, Hashable, Identifiable {
    public enum Level: String, Sendable { case timeSensitive, active, passive }
    public enum Kind: String, Sendable { case departure, reservation, morning, journal, booking }

    public let id: String
    public let fire: Date
    public let title: String
    public let body: String
    public let level: Level
    public let kind: Kind
    public let day: String?
    public let index: Int?
    public let placeID: String?
}

public struct ReminderPlanner: Sendable {
    public let store: TripStore
    let itinerary: Itinerary

    /// minutes before setting off
    public var lead: Double = 10

    public init(store: TripStore) {
        self.store = store
        itinerary = Itinerary(store: store)
    }

    /// The day's reminders at the plan's times: the same "Rời đi lúc" the Today screen shows for
    /// the next stop. A departure or a reservation that is `settled` (done, dropped, or behind what
    /// was done) is left out: its reminder would only say what already happened.
    public func reminders(for day: Day, settled: (Day, Int) -> Bool = { _, _ in false }) -> [Reminder] {
        var out: [Reminder] = []
        let points = itinerary.waypoints(day)
        if let start = itinerary.engine.simulate(day).first?.begin, let at = TripTime.date(day.date, minutes: start - 30) {
            out.append(Reminder(id: "morning-\(day.key)", fire: at, title: "Ngày \(day.n) · \(day.title)", body: day.route, level: .active, kind: .morning, day: day.key, index: nil, placeID: nil))
        }
        for w in points where w.kind != .stop && !settled(day, w.index) {
            guard let fire = TripTime.date(day.date, minutes: w.setOff - lead), let planned = w.planned else { continue }
            let from = store.place(w.placeID)
            switch w.kind {
            case .departure:
                guard case .move(let m) = day.items[w.index] else { continue }
                let ride = store.ride(startingWith: m.leg.id, on: day)
                let to = store.place(m.leg.to)?.name ?? m.leg.to
                var body = "\(w.title) \(TripTime.clock(Double(planned))) từ \(from?.name ?? m.leg.from) đi \(to)."
                if let seat = ride?.seatVerdict { body += " \(seat)." }
                out.append(Reminder(id: "dep-\(day.key)-\(w.index)", fire: fire, title: "Rời đi lúc \(TripTime.clock(w.setOff))", body: body, level: .timeSensitive, kind: .departure, day: day.key, index: w.index, placeID: m.leg.from))
            case .reservation:
                out.append(Reminder(id: "res-\(day.key)-\(w.index)", fire: fire, title: "Rời đi lúc \(TripTime.clock(w.setOff))", body: "\(w.title) lúc \(TripTime.clock(Double(planned))) — đã đặt chỗ.", level: .timeSensitive, kind: .reservation, day: day.key, index: w.index, placeID: w.placeID))
            case .stop:
                break
            }
        }
        if let at = TripTime.date(day.date, minutes: 21 * 60 + 30) {
            out.append(Reminder(id: "journal-\(day.key)", fire: at, title: "Nhật ký ngày \(day.n)", body: day.title, level: .passive, kind: .journal, day: day.key, index: nil, placeID: nil))
        }
        return out
    }

    /// Booking windows that open at an exact Japan time: the evening before and fifteen minutes before.
    public func bookings() -> [Reminder] {
        (store.guide?.bookings ?? []).enumerated().flatMap { i, b -> [Reminder] in
            guard let at = b.date else { return [] }
            return [
                Reminder(id: "book-\(i)-eve", fire: at.addingTimeInterval(-86400), title: "Ngày mai: \(b.title)", body: "\(b.rule). \(b.text)", level: .active, kind: .booking, day: nil, index: i, placeID: nil),
                Reminder(id: "book-\(i)", fire: at.addingTimeInterval(-15 * 60), title: b.title, body: "Mở lúc \(TripTime.clock(at)) giờ Nhật. \(b.text)", level: .timeSensitive, kind: .booking, day: nil, index: i, placeID: nil),
            ]
        }
    }

    /// What to keep scheduled from now: iOS keeps 64 pending notifications, so only the next days.
    /// Only the days that can have a reminder in that window are worked through: a day's reminders
    /// fire from a little before its midnight (an early start) to its evening.
    public func upcoming(days: [Day], now: Date, horizonDays: Int = 2, settled: (Day, Int) -> Bool = { _, _ in false }) -> [Reminder] {
        let until = now.addingTimeInterval(Double(horizonDays) * 86400)
        let near = days.filter { day in
            guard let midnight = TripTime.midnight(day.date) else { return false }
            return midnight.addingTimeInterval(-6 * 3600) < until && midnight.addingTimeInterval(30 * 3600) > now
        }
        let all = near.flatMap { reminders(for: $0, settled: settled) } + bookings()
        return all.filter { $0.fire > now && $0.fire < until }.sorted { $0.fire < $1.fire }.prefix(60).map { $0 }
    }
}

import Foundation

/// Which rides get an alarm from the timetable before the station to get off at, and when.
///
/// Only long sit-down train rides: 25 minutes or more on a train or the Shinkansen, time enough to
/// doze. Not a boat (you are on deck taking photos), a bus or a ropeway (you watch the road), nor
/// the metro: an alarm rings through silent mode, and on a quiet Japanese train the whole carriage
/// turns round. Only when the timetable knows the arrival to within ten minutes: a ride stated as
/// "55–80" may be a fast train or a slow one, and four minutes before the earliest arrival is half
/// an hour early on the slow one; those get their alarm from the train's real speed once the ride
/// is followed.
public struct WakePlanner: Sendable {
    public struct Wake: Sendable, Hashable {
        public let rideID: String
        public let station: String
        public let at: Date
    }

    public let store: TripStore
    /// minutes before the planned arrival
    public static let lead = 4.0
    public static let minimum = 25
    public static let spread = 10

    public init(store: TripStore) {
        self.store = store
    }

    public func isWorthAnAlarm(_ ride: Ride) -> Bool {
        guard let low = TripTime.statedMinutes(ride.min), low >= Self.minimum,
              let high = TripTime.statedMaxMinutes(ride.min), high - low <= Self.spread,
              ride.at != nil, let day = store.day(ride.day)
        else { return false }
        let modes = day.items.compactMap(\.move).filter { ride.legs.contains($0.leg.id) }.map { store.mode(of: $0.leg) }
        return !modes.isEmpty && modes.allSatisfy { $0 == .train || $0 == .shinkansen || $0 == .walk }
            && modes.contains { $0 != .walk }
    }

    /// When the timetable's alarm for the ride rings: `lead` minutes before its planned arrival, on its
    /// day. Nil for a ride not worth an alarm. A followed ride's alarm never rings later than this
    /// (`RideTracker.alarm`).
    public func alarm(for ride: Ride) -> Date? {
        guard let day = store.day(ride.day) else { return nil }
        return alarm(for: ride, on: day)
    }

    private func alarm(for ride: Ride, on day: Day) -> Date? {
        guard isWorthAnAlarm(ride), let arrive = RideTracker(ride: ride, store: store).plannedArrival else { return nil }
        return TripTime.date(day.date, minutes: arrive - Self.lead)
    }

    /// The alarms wanted from `now` to the end of tomorrow in Japan, for rides not yet ridden.
    public func wakes(days: [Day], now: Date, horizon: TimeInterval = 36 * 3600, ridden: (Day, Int) -> Bool) -> [Wake] {
        var out: [Wake] = []
        for day in days {
            guard let midnight = TripTime.midnight(day.date),
                  midnight < now.addingTimeInterval(horizon), midnight.addingTimeInterval(30 * 3600) > now
            else { continue }
            for ride in store.rides(on: day) {
                guard let at = alarm(for: ride, on: day), at > now else { continue }
                let legs = day.items.indices.filter { i in day.items[i].move.map { ride.legs.contains($0.leg.id) } ?? false }
                if !legs.isEmpty, legs.allSatisfy({ ridden(day, $0) }) { continue }
                out.append(Wake(rideID: ride.id, station: ride.toName, at: at))
            }
        }
        return out
    }
}

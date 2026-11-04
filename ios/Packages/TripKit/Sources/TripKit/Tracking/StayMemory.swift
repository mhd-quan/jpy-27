import Foundation

/// The stays iOS reported lately, without where they were: what makes one stay mark one stop, once,
/// journal or not, and when you left each place, for the walking pace.
///
/// iOS reports a stay twice: on arrival (no departure yet), then on leaving (both times). Only the
/// first report that matches a planned stop marks it; a later report of the same stay only
/// completes it. Without this, the leaving report would match again: a stop unmarked by hand would
/// be marked again, and at a place the day visits twice (the hotel's bag drop, then check-in) the
/// second visit, not yet done, would be marked as you leave the first.
///
/// Only the arrival, the departure and the plan place a stay matched are kept, never a coordinate,
/// and for a day after the stay ended (`keep`); a stay not yet left, for three days (`keepOpen`, two
/// nights at a hotel).
public struct StayMemory: Codable, Sendable, Equatable {
    public struct Stay: Codable, Sendable, Equatable {
        public var arrival: Date
        public var departure: Date?
        /// the plan place the stay matched (`Itinerary.stop`), nil while it matched none
        public var placeID: String?

        public init(arrival: Date, departure: Date?, placeID: String?) {
            self.arrival = arrival
            self.departure = departure
            self.placeID = placeID
        }
    }

    /// What one report of a stay comes to.
    public struct Report: Sendable, Equatable {
        /// the stay as remembered now (its first arrival, the first place it matched)
        public let stay: Stay
        /// the stop matched by this report is to be marked done, at `stay.arrival`
        public let marks: Bool
    }

    /// how long a stay is remembered after it ended
    public static let keep: TimeInterval = 24 * 3600
    /// how long a stay with no departure yet is remembered after it began
    public static let keepOpen: TimeInterval = 3 * 24 * 3600
    /// two reports are one stay when their arrivals are this close (as `VisitRecord.isSameStay`)
    public static let sameArrival: TimeInterval = 120

    public private(set) var stays: [Stay]

    public init(stays: [Stay] = []) {
        self.stays = stays
    }

    /// A report of `visit`, which matched the plan place `placeID` (nil: no planned stop). The first
    /// report of a stay that matches marks; any later report of it only fills in its departure (and
    /// its place, when the stay had matched none: that report then marks).
    public mutating func report(_ visit: VisitRecord, placeID: String?, now: Date) -> Report {
        forget(now: now)
        if let k = stays.firstIndex(where: { abs($0.arrival.timeIntervalSince(visit.arrival)) <= Self.sameArrival }) {
            if stays[k].departure == nil { stays[k].departure = visit.departure }
            let marks = stays[k].placeID == nil && placeID != nil
            if marks { stays[k].placeID = placeID }
            return Report(stay: stays[k], marks: marks)
        }
        let stay = Stay(arrival: visit.arrival, departure: visit.departure, placeID: placeID)
        stays.append(stay)
        return Report(stay: stay, marks: placeID != nil)
    }

    /// When you last left `placeID`, of the stays there that began at `since` or later and were left
    /// by `until`: where a walk from it began.
    public func departure(from placeID: String, since: Date, until: Date) -> Date? {
        stays
            .filter { $0.placeID == placeID && $0.arrival >= since }
            .compactMap(\.departure)
            .filter { $0 <= until }
            .max()
    }

    private mutating func forget(now: Date) {
        stays.removeAll { s in
            if let left = s.departure { return now.timeIntervalSince(left) >= Self.keep }
            return now.timeIntervalSince(s.arrival) >= Self.keepOpen
        }
    }
}

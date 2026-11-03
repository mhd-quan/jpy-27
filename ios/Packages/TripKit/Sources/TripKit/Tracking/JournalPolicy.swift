import Foundation

/// When the location journal may record, and when the phone watches in the background at all.
///
/// The journal (stays and the walked trace) is kept only during the trip, give or take a margin,
/// and only when switched on. Outside a rehearsal the clock that decides is the real one: a
/// rehearsal's shifted clock never opens the real window. A rehearsal records into its own store,
/// thrown away when it ends, so it is judged by its own clock: the journal can be tried before the
/// trip without touching the real records.
public struct JournalPolicy: Sendable {
    /// Midnight in Japan of the first day, minus `margin`, to midnight after the last day, plus
    /// `margin`; nil without days.
    public let window: Range<Date>?
    /// Midnight in Japan of the first day to midnight after the last: when a visit can mark a stop.
    let tripDays: Range<Date>?

    /// How long before the window the background watch starts: the evening before the first day.
    static let watchLead: TimeInterval = 24 * 3600

    public init(days: [Day], margin: TimeInterval = 6 * 3600) {
        let midnights = days.compactMap { TripTime.midnight($0.date) }
        if let first = midnights.min(), let last = midnights.max(),
           let after = TripTime.calendar.date(byAdding: .day, value: 1, to: last) {
            tripDays = first ..< after
            window = first.addingTimeInterval(-margin) ..< after.addingTimeInterval(margin)
        } else {
            tripDays = nil
            window = nil
        }
    }

    /// Whether a stay or a trace point may be written now. While `rehearsing`, by `tripNow` (the
    /// rehearsal's store takes it, and is deleted with it); otherwise by `realNow` only.
    public func mayRecord(realNow: Date, tripNow: Date, rehearsing: Bool, enabled: Bool) -> Bool {
        guard enabled, let window else { return false }
        return window.contains(rehearsing ? tripNow : realNow)
    }

    /// Significant location changes in the background: from a day before the window to its end,
    /// with Always. Whatever the journal's switch: a move re-plans reminders and geofences.
    public func wantsBackgroundWatch(at: Date, journal: Bool, alwaysGranted: Bool) -> Bool {
        guard alwaysGranted, let window else { return false }
        return (window.lowerBound.addingTimeInterval(-Self.watchLead) ..< window.upperBound).contains(at)
    }

    /// Visits (CLVisit) in the background: within the background watch, and only for the journal
    /// or on a trip day, when a visit marks the stop it was at.
    public func wantsVisits(at: Date, journal: Bool, alwaysGranted: Bool) -> Bool {
        guard wantsBackgroundWatch(at: at, journal: journal, alwaysGranted: alwaysGranted) else { return false }
        return journal || tripDays?.contains(at) == true
    }
}

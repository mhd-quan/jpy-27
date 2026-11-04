import Foundation

/// The rehearsal clock's one rule (Settings › Chạy thử): the seconds added to the real clock, as
/// the app and the widget keep and read them. Whether a rehearsal runs is decided here only.
public enum RehearsalClock {
    /// an offset closer to the real clock than this is no rehearsal
    public static let deadBand: TimeInterval = 60

    /// The offset as kept: 0 within a minute of the real clock (or not a number), otherwise the
    /// nearest whole minute. A rehearsal never starts at about now.
    public static func offset(_ raw: TimeInterval) -> TimeInterval {
        guard raw.isFinite, abs(raw) >= deadBand else { return 0 }
        return (raw / 60).rounded() * 60
    }

    /// whether `raw`, read by the rule, shifts the clock
    public static func isRehearsing(_ raw: TimeInterval) -> Bool {
        offset(raw) != 0
    }

    /// What "Chạy thử từ thời điểm này" sets for `picked`, or nil when it would do nothing: no
    /// rehearsal at real time, never the end of one (only "Về giờ thật" ends it), nor the
    /// rehearsal already running. A pick in the trip clock's current minute is "now", however long
    /// the picker stayed open before it was turned back onto it.
    public static func start(at picked: Date, realNow: Date, current: TimeInterval) -> TimeInterval? {
        let tripNow = realNow.addingTimeInterval(offset(current))
        guard minute(of: picked) != minute(of: tripNow) else { return nil }
        let wanted = offset(picked.timeIntervalSince(realNow))
        guard wanted != 0, wanted != offset(current) else { return nil }
        return wanted
    }

    /// the clock minute an instant falls in (minutes since 1/1/2001 UTC, aligned with Japan's)
    private static func minute(of date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate / 60).rounded(.down)
    }
}

/// The clock a followed ride belongs to: the real one, or a rehearsal's (`RideLiveService`). A ride followed in a
/// rehearsal is the real ride of the same train, under the same id and with the same alarm slot, so what its end
/// lets go of is decided by the clock it was followed on and the one it ends on.
public struct RideClock: Sendable, Equatable {
    /// followed while rehearsing
    public let rehearsal: Bool

    public init(rehearsal: Bool) {
        self.rehearsal = rehearsal
    }

    /// Whether the ride's end cancels the ride's alarm: only a ride followed on the real clock and ended on it. A
    /// rehearsal's ride set none (`WakeAlarms` sets nothing while rehearsing), so what the slot holds is the real
    /// ride's timetable alarm; and a real ride ended because a rehearsal starts keeps its own, since no re-plan
    /// runs while rehearsing to bring it back.
    public func endCancelsAlarm(rehearsingNow: Bool) -> Bool {
        !rehearsal && !rehearsingNow
    }

    /// Whether the ride, once ended, is kept from starting again on its own for the rest of the launch: a real
    /// ride only. A rehearsal's would keep the real ride of the same train from starting after "Về giờ thật".
    public var endIsKept: Bool { !rehearsal }
}

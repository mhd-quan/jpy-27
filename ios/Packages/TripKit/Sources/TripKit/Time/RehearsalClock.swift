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
    /// rehearsal already running.
    public static func start(at picked: Date, realNow: Date, current: TimeInterval) -> TimeInterval? {
        let wanted = offset(picked.timeIntervalSince(realNow))
        guard wanted != 0, wanted != offset(current) else { return nil }
        return wanted
    }
}

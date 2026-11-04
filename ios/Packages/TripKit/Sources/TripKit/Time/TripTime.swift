import Foundation

/// Clock arithmetic in Japan time. Plan times are "H:MM" strings on a "YYYY-MM-DD" date.
public enum TripTime {
    public static let zone = TimeZone(identifier: "Asia/Tokyo")!

    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "vi_VN")
        return c
    }()

    /// "7:40" → 460. Returns nil for anything that is not a clock time.
    public static func minutes(_ hm: String?) -> Int? {
        guard let hm else { return nil }
        let parts = hm.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    /// Midnight in Japan of "2027-10-19".
    public static func midnight(_ isoDate: String) -> Date? {
        let p = isoDate.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: p[0], month: p[1], day: p[2]))
    }

    /// A plan time on a plan date as an absolute instant.
    public static func date(_ isoDate: String, minutes: Double) -> Date? {
        midnight(isoDate).map { $0.addingTimeInterval(minutes * 60) }
    }

    public static func date(_ isoDate: String, _ hm: String?) -> Date? {
        minutes(hm).flatMap { date(isoDate, minutes: Double($0)) }
    }

    /// Minutes since midnight (Japan) of the given plan date; may exceed 1440 or go negative.
    public static func minutes(of instant: Date, on isoDate: String) -> Double? {
        midnight(isoDate).map { instant.timeIntervalSince($0) / 60 }
    }

    /// "2027-10-19" of an instant, in Japan.
    public static func isoDate(of instant: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: instant)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    /// "16:05" — no leading zero on the hour, like the plan.
    public static func clock(_ minutes: Double) -> String {
        let m = Int((minutes).rounded())
        let wrapped = ((m % 1440) + 1440) % 1440
        return "\(wrapped / 60):\(String(format: "%02d", wrapped % 60))"
    }

    /// The time said for an item: the plan's time when it has one (a train, a table: late or not,
    /// that time stays), otherwise the begin shown with it, in minutes since the day's midnight.
    public static func beginLabel(planned: Int?, begin: Double) -> String {
        planned.map { clock(Double($0)) } ?? clock(begin)
    }

    public static func clock(_ instant: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: instant)
        return "\(c.hour!):\(String(format: "%02d", c.minute!))"
    }

    /// Stated minutes of a leg, read the way scripts/check-plan.mjs reads them:
    /// "1 giờ 40" → 100, "20–25, đổi…" → 20, "60–90 tính cả chờ" → 60.
    ///
    /// Read by hand, not with a Regex: the plan clock asks for it for every leg of a day on every
    /// pass, and a ride being followed on every fix, and a Swift Regex costs tens of microseconds a
    /// call where this costs well under one. It reads exactly what `/(\d+)\s*giờ\s*(\d+)?/` and then
    /// `/\d+/` would (a digit is `Character.isNumber`, a space `isWhitespace`, as in a Regex); the
    /// tests hold it to those patterns.
    public static func statedMinutes(_ s: String?) -> Int? {
        guard let s else { return nil }
        var first: Substring?
        var i = s.startIndex
        while let run = nextDigits(s, &i) {
            if first == nil { first = run }
            var j = i
            skipSpaces(s, &j)
            guard skipHour(s, &j) else { continue }
            // the first run of digits followed by "giờ" is where the pattern matches
            guard let h = Int(run) else { break }
            skipSpaces(s, &j)
            let m = j < s.endIndex && s[j].isNumber ? nextDigits(s, &j).flatMap { Int($0) } : nil
            return h * 60 + (m ?? 0)
        }
        return first.flatMap { Int($0) }
    }

    /// The longest a stated time can be: 45 for "35–45", 100 for "1 giờ 40", the lower bound
    /// when only one is given.
    public static func statedMaxMinutes(_ s: String?) -> Int? {
        guard let s, let low = statedMinutes(s) else { return nil }
        if s.contains("giờ") { return low }
        // `^\s*\d+\s*[–-]\s*(\d+)`
        var i = s.startIndex
        skipSpaces(s, &i)
        guard i < s.endIndex, s[i].isNumber, nextDigits(s, &i) != nil else { return low }
        skipSpaces(s, &i)
        guard i < s.endIndex, s[i] == "–" || s[i] == "-" else { return low }
        s.formIndex(after: &i)
        skipSpaces(s, &i)
        guard i < s.endIndex, s[i].isNumber, let high = nextDigits(s, &i).flatMap({ Int($0) }) else { return low }
        return max(low, high)
    }

    /// The next run of digits at or after `i`, which is left just past it.
    private static func nextDigits(_ s: String, _ i: inout String.Index) -> Substring? {
        while i < s.endIndex, !s[i].isNumber { s.formIndex(after: &i) }
        guard i < s.endIndex else { return nil }
        let start = i
        while i < s.endIndex, s[i].isNumber { s.formIndex(after: &i) }
        return s[start ..< i]
    }

    private static func skipSpaces(_ s: String, _ i: inout String.Index) {
        while i < s.endIndex, s[i].isWhitespace { s.formIndex(after: &i) }
    }

    private static let hour: [Character] = ["g", "i", "ờ"]

    /// "giờ" at `i`: moves past it and says so; leaves `i` alone otherwise.
    private static func skipHour(_ s: String, _ i: inout String.Index) -> Bool {
        var j = i
        for c in hour {
            guard j < s.endIndex, s[j] == c else { return false }
            s.formIndex(after: &j)
        }
        i = j
        return true
    }
}

/// Vietnamese number and money formatting, the way the site writes it.
public enum Fmt {
    /// What is shown for a number that is not one (NaN, ±∞), or past a whole Int (x ≥ 2^63, x < −2^63)
    public static let missing = "—"
    /// "¥1.500"
    public static func yen(_ n: Int) -> String {
        "¥" + grouped(n)
    }

    /// "1.500"
    public static func grouped(_ n: Int) -> String {
        let s = String(n.magnitude)
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return (n < 0 ? "−" : "") + out
    }

    /// "1,2 km", "850 m"
    public static func km(_ km: Double) -> String {
        guard km.isFinite else { return missing }
        // the unit after rounding: 996 m is a kilometre, not "1000 m"
        if km < 1 {
            // a distance past Int, in tens of metres or once made metres, is not one
            guard let tens = whole((km * 1000 / 10).rounded()) else { return missing }
            let (metres, overflow) = tens.multipliedReportingOverflow(by: 10)
            guard !overflow else { return missing }
            if metres < 1000 { return "\(metres) m" }
        }
        let digits = km < 10 ? 1 : 0
        let shown = decimal(km, digits: digits)
        return shown == missing ? missing : shown + " km"
    }

    /// "1,2" with a decimal comma
    public static func decimal(_ x: Double, digits: Int) -> String {
        guard x.isFinite else { return missing }
        let p = pow(10, Double(digits))
        // after rounding: a finite `x` can round past Int, or `x * p` past the largest Double
        let r = (x * p).rounded() / p
        guard let rounded = whole(r.rounded()) else { return missing }
        if digits == 0 || r == r.rounded() { return grouped(rounded) }
        // the magnitude, and the sign of what is shown: −0,4 keeps it, −0,04 at one digit is "0"
        let m = abs(r)
        let whole = Int(m.rounded(.towardZero))
        let frac = Int(((m - Double(whole)) * p).rounded())
        return (r < 0 ? "−" : "") + "\(grouped(whole)),\(String(format: "%0\(digits)d", frac))"
    }

    /// `x`, a whole number, as an Int; nil where an Int cannot hold it (NaN, ±∞, x ≥ 2^63, x < −2^63), so a
    /// formatter says `missing` instead of trapping
    private static func whole(_ x: Double) -> Int? {
        x >= -0x1p63 && x < 0x1p63 ? Int(x) : nil
    }

    /// "12 phút", "1 giờ 40", "2 giờ"
    public static func duration(_ minutes: Double) -> String {
        guard let m = whole(minutes.rounded()) else { return missing }
        if m < 60 { return "\(m) phút" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h) giờ" : "\(h) giờ \(r)"
    }

    /// "12,3 triệu đồng" for a yen amount at a VND rate
    public static func vndMillions(_ yen: Int, rate: Double) -> String {
        decimal(Double(yen) * rate / 1_000_000, digits: 1) + " triệu"
    }

    /// "19/10"
    public static func shortDate(_ iso: String) -> String {
        let p = iso.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return iso }
        return "\(p[2])/\(p[1])"
    }
}

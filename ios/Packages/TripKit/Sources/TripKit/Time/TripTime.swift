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

    public static func clock(_ instant: Date) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: instant)
        return "\(c.hour!):\(String(format: "%02d", c.minute!))"
    }

    /// Stated minutes of a leg, read the way scripts/check-plan.mjs reads them:
    /// "1 giờ 40" → 100, "20–25, đổi…" → 20, "60–90 tính cả chờ" → 60.
    public static func statedMinutes(_ s: String?) -> Int? {
        guard let s else { return nil }
        if let m = s.firstMatch(of: /(\d+)\s*giờ\s*(\d+)?/), let h = Int(m.1) {
            return h * 60 + (m.2.flatMap { Int($0) } ?? 0)
        }
        if let m = s.firstMatch(of: /\d+/) { return Int(m.0) }
        return nil
    }

    /// The longest a stated time can be: 45 for "35–45", 100 for "1 giờ 40", the lower bound
    /// when only one is given.
    public static func statedMaxMinutes(_ s: String?) -> Int? {
        guard let s, let low = statedMinutes(s) else { return nil }
        if s.contains("giờ") { return low }
        if let m = s.firstMatch(of: /^\s*\d+\s*[–-]\s*(\d+)/), let high = Int(m.1) { return max(low, high) }
        return low
    }
}

/// Vietnamese number and money formatting, the way the site writes it.
public enum Fmt {
    /// "¥1.500"
    public static func yen(_ n: Int) -> String {
        "¥" + grouped(n)
    }

    /// "1.500"
    public static func grouped(_ n: Int) -> String {
        let s = String(abs(n))
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0, (s.count - i) % 3 == 0 { out.append(".") }
            out.append(ch)
        }
        return (n < 0 ? "−" : "") + out
    }

    /// "1,2 km", "850 m"
    public static func km(_ km: Double) -> String {
        if km < 1 { return "\(Int((km * 1000 / 10).rounded()) * 10) m" }
        let digits = km < 10 ? 1 : 0
        return decimal(km, digits: digits) + " km"
    }

    /// "1,2" with a decimal comma
    public static func decimal(_ x: Double, digits: Int) -> String {
        let p = pow(10, Double(digits))
        let r = (x * p).rounded() / p
        if digits == 0 || r == r.rounded() { return grouped(Int(r.rounded())) }
        let whole = Int(r.rounded(.towardZero))
        let frac = Int((abs(r - Double(whole)) * p).rounded())
        return "\(grouped(whole)),\(String(format: "%0\(digits)d", frac))"
    }

    /// "12 phút", "1 giờ 40", "2 giờ"
    public static func duration(_ minutes: Double) -> String {
        let m = Int(minutes.rounded())
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

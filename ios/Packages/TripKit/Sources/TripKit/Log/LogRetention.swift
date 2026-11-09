import Foundation

/// A file of the log folder as the app lists it: its name and its size.
public struct LogFile: Sendable, Equatable {
    public let name: String
    public let bytes: Int

    public init(name: String, bytes: Int) {
        self.name = name
        self.bytes = bytes
    }
}

/// What the log folder keeps and what its files are named: a file a day, named by the phone's own
/// calendar day (`yyyy-MM-dd.jsonl`); today and the 13 days before it; at most 10 MB in all, the oldest
/// day going first and today never; and the crash reports MetricKit hands over, the 20 newest. Every
/// date in a name is Gregorian with ASCII digits, whatever calendar and digits the phone is set to, and
/// no name holds a ":".
public enum LogRetention {
    /// days kept: today and the 13 before it
    public static let maxAgeDays = 14
    /// the day files' total, and the most one day's file grows to
    public static let maxBytes = 10_000_000
    /// MetricKit reports kept in `diagnostics/`
    public static let keptDiagnostics = 20

    // MARK: - Day files

    /// "2027-01-15.jsonl": the day `date` falls on in `timeZone`.
    public static func dayName(_ date: Date, in timeZone: TimeZone) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day], from: date)
        return pad(c.year, 4) + "-" + pad(c.month, 2) + "-" + pad(c.day, 2) + ".jsonl"
    }

    /// The day files of `files` to delete, sorted: those older than today and the 13 days before it,
    /// then, while the day files left are more than `maxBytes` in all, the oldest of them, never
    /// `today`. Only names `dayName` makes count; any other name is neither deleted nor counted. A
    /// name later than today (the zone moved west) is never too old, and is the newest by size.
    /// Nothing is deleted when `today` is not a day name.
    public static func toDelete(_ files: [LogFile], today: String) -> [String] {
        guard let now = day(today) else { return [] }
        let oldest = now - (maxAgeDays - 1)
        var deleted: [String] = []
        var kept: [(name: String, day: Int, bytes: Int)] = []
        for file in files {
            guard let d = day(file.name) else { continue }
            if d < oldest {
                deleted.append(file.name)
            } else {
                kept.append((file.name, d, max(0, file.bytes)))
            }
        }
        var total = kept.reduce(0) { $0 + $1.bytes }
        for file in kept.sorted(by: { $0.day < $1.day }) where file.day != now {
            guard total > maxBytes else { break }
            deleted.append(file.name)
            total -= file.bytes
        }
        return deleted.sorted()
    }

    /// How many lines of `sizes` (bytes each, in order) a day's file of `fileBytes` takes before it
    /// would pass `maxBytes`. The file stops growing there: a line after one that did not fit is not
    /// taken either, so what the file holds stays in order with nothing missing in its middle.
    public static func fitting(_ sizes: [Int], after fileBytes: Int) -> Int {
        var total = fileBytes
        var taken = 0
        for size in sizes {
            guard size <= maxBytes - total else { break }
            total += size
            taken += 1
        }
        return taken
    }

    /// The day number (days since 1970-01-01) of a name `dayName` makes; nil for any other name: exactly
    /// `yyyy-MM-dd.jsonl` with ASCII digits and a real date.
    static func day(_ name: String) -> Int? {
        let b = Array(name.utf8)
        guard b.count == 16, b[4] == UInt8(ascii: "-"), b[7] == UInt8(ascii: "-"), Array(b[10...]) == Array(".jsonl".utf8),
              let y = digits(b, 0..<4), let m = digits(b, 5..<7), let d = digits(b, 8..<10),
              (1...12).contains(m), d >= 1, d <= daysIn(month: m, year: y) else { return nil }
        return daysFromCivil(y, m, d)
    }

    // MARK: - Crash reports

    /// "20270115T080000Z.json": a MetricKit report by the end of its period, in UTC to the second (ISO
    /// 8601's basic form); `index` 1, 2, … for more reports with the same end ("…Z-1.json").
    public static func diagnosticName(_ end: Date, index: Int) -> String {
        let c = calendar(utc).dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        let stamp = pad(c.year, 4) + pad(c.month, 2) + pad(c.day, 2) + "T" + pad(c.hour, 2) + pad(c.minute, 2) + pad(c.second, 2) + "Z"
        return stamp + (index > 0 ? "-\(index)" : "") + ".json"
    }

    /// The name for a report ending at `end` that overwrites none of `taken` (the `diagnostics` folder's listing, and
    /// the names given before in the same delivery): index 0 while no report of that second is there, else one past
    /// the highest index of that second. A name `diagnosticName` did not make is not counted.
    public static func diagnosticName(_ end: Date, after taken: [String]) -> String {
        let stamp = diagnosticOrder(diagnosticName(end, index: 0))?.stamp
        let used = taken.compactMap { name in diagnosticOrder(name).flatMap { $0.stamp == stamp ? $0.index : nil } }
        return diagnosticName(end, index: used.max().map { $0 + 1 } ?? 0)
    }

    /// The reports of `names` (the `diagnostics` folder's listing) to delete: all but the `keeping`
    /// newest, oldest first. A name `diagnosticName` did not make is never returned.
    public static func diagnosticsToDelete(_ names: [String], keeping: Int = LogRetention.keptDiagnostics) -> [String] {
        let ours = names.compactMap { name in diagnosticOrder(name).map { (name: name, order: $0) } }
        let old = ours.sorted { $0.order > $1.order }.dropFirst(max(0, keeping))
        return old.sorted { $0.order < $1.order }.map(\.name)
    }

    /// Where a name `diagnosticName` made sorts: its stamp, then its index; nil for any other name.
    private static func diagnosticOrder(_ name: String) -> (stamp: String, index: Int)? {
        let b = Array(name.utf8)
        guard b.count >= 21, Array(b[(b.count - 5)...]) == Array(".json".utf8),
              digits(b, 0..<8) != nil, b[8] == UInt8(ascii: "T"), digits(b, 9..<15) != nil, b[15] == UInt8(ascii: "Z") else { return nil }
        let stamp = String(decoding: b[0..<16], as: UTF8.self)
        let rest = b[16..<(b.count - 5)]
        if rest.isEmpty { return (stamp, 0) }
        // "-<n>", n from 1 and without a leading zero
        guard rest.first == UInt8(ascii: "-"), rest.count >= 2, rest[rest.startIndex + 1] != UInt8(ascii: "0"),
              let n = digits(b, (rest.startIndex + 1)..<rest.endIndex), n >= 1 else { return nil }
        return (stamp, n)
    }

    // MARK: - The export

    /// "JP27-log-20270115-1700": the export's folder (and, with ".zip", its file), by the time in
    /// `timeZone`.
    public static func exportName(_ date: Date, in timeZone: TimeZone) -> String {
        let c = calendar(timeZone).dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "JP27-log-" + pad(c.year, 4) + pad(c.month, 2) + pad(c.day, 2) + "-" + pad(c.hour, 2) + pad(c.minute, 2)
    }

    // MARK: - Dates

    private static let utc = TimeZone(secondsFromGMT: 0)!

    /// Gregorian whatever the phone's calendar (a Buddhist or Japanese one would give another year)
    private static func calendar(_ zone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    private static func pad(_ n: Int?, _ width: Int) -> String {
        let s = String(n ?? 0)
        return String(repeating: "0", count: max(0, width - s.count)) + s
    }

    /// The number the ASCII digits `b[range]` spell; nil if any is not one.
    private static func digits(_ b: [UInt8], _ range: Range<Int>) -> Int? {
        guard !range.isEmpty, range.count <= 9 else { return nil }
        var n = 0
        for i in range {
            guard b[i] >= UInt8(ascii: "0"), b[i] <= UInt8(ascii: "9") else { return nil }
            n = n * 10 + Int(b[i] - UInt8(ascii: "0"))
        }
        return n
    }

    private static func daysIn(month: Int, year: Int) -> Int {
        let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
        return [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
    }

    /// Days since 1970-01-01 of a Gregorian date (H. Hinnant's `days_from_civil`): integers only, no
    /// zone, no daylight saving.
    private static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}

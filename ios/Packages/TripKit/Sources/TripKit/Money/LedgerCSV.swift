import Foundation

/// A row of a ledger file that was not read, and why.
public struct RowProblem: Sendable, Hashable {
    /// the row as a spreadsheet numbers it: the header is 1
    public let line: Int
    public let reason: Reason

    public enum Reason: Sendable, Hashable {
        /// no id, or not a UUID
        case id
        /// no time it was logged, or not one this file writes
        case date
        /// the amount as written: not a whole number, or outside 1…`Yen.maxEntry`
        case amount(String)
        /// a note or place name longer than `LedgerValidation.maxText`
        case text
    }

    public init(line: Int, reason: Reason) {
        self.line = line
        self.reason = reason
    }
}

/// The ledger as CSV (RFC 4180), in the columns the app has always written: to keep (Numbers,
/// Excel, a backup off the phone), and to merge the other phone's when the two cannot meet.
/// Columns are found by their header name, so a file whose columns were moved still reads.
/// A row is read only if it holds what the keypad could have typed (`LedgerValidation`); the time
/// is checked against the clock by `LedgerMerge.screened`, after reading.
public nonisolated enum LedgerCSV {
    public static let header = ["id", "luc", "ngay", "gio", "yen", "khoan", "ten_khoan", "tra", "place_id", "cho", "ghi_chu", "may", "sua"]

    /// The rows in the order given, under the header, each line ended by CRLF. `placeName` names a
    /// place of the data by its id (the name typed by hand is written otherwise).
    public static func encode(_ rows: [LedgerRecord], placeName: (String?) -> String?) -> String {
        var lines = [header]
        for r in rows {
            lines.append([
                r.id.uuidString, timestamp(r.at), r.day ?? "", TripTime.clock(r.at), String(r.yen),
                r.category, (SpendCategory(rawValue: r.category) ?? .extra).label, r.method, r.placeID ?? "",
                placeName(r.placeID) ?? r.placeName ?? "", r.note, r.origin,
                r.updatedAt.map(timestamp) ?? "",
            ])
        }
        return lines.map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    /// The rows of a file, and the ones left out with why. A byte-order mark is skipped; rows with
    /// nothing in them are passed over in silence (spreadsheets leave them at the end).
    public static func decode(_ text: String) -> (records: [LedgerRecord], rejected: [RowProblem]) {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = parse(text)
        guard let start = rows.firstIndex(where: { !isBlank($0) }) else { return ([], []) }
        let col = Dictionary(rows[start].enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var records: [LedgerRecord] = []
        var rejected: [RowProblem] = []
        for i in rows.indices where i > start && !isBlank(rows[i]) {
            func value(_ name: String) -> String? {
                guard let c = col[name], rows[i].indices.contains(c) else { return nil }
                let v = rows[i][c].trimmingCharacters(in: .whitespaces)
                return v.isEmpty ? nil : v
            }
            let line = i + 1
            guard let id = value("id").flatMap(UUID.init(uuidString:)) else {
                rejected.append(RowProblem(line: line, reason: .id)); continue
            }
            guard let at = value("luc").flatMap(date) else {
                rejected.append(RowProblem(line: line, reason: .date)); continue
            }
            let amount = value("yen") ?? ""
            guard let yen = Int(amount), Yen.isValidEntry(yen) else {
                rejected.append(RowProblem(line: line, reason: .amount(amount))); continue
            }
            let place = value("place_id")
            let r = LedgerRecord(
                id: id, yen: yen,
                category: value("khoan").flatMap(SpendCategory.init(rawValue:))?.rawValue ?? SpendCategory.extra.rawValue,
                method: value("tra").flatMap(PayMethod.init(rawValue:))?.rawValue ?? PayMethod.cash.rawValue,
                placeID: place,
                placeName: place == nil ? value("cho") : nil,
                day: value("ngay"),
                note: value("ghi_chu") ?? "",
                at: at,
                updatedAt: value("sua").flatMap(date),
                origin: value("may") ?? "other")
            guard !LedgerValidation.contentProblems(r).contains(.text) else {
                rejected.append(RowProblem(line: line, reason: .text)); continue
            }
            records.append(r)
        }
        return (records, rejected)
    }

    // MARK: - Times

    private static let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let whole = Date.ISO8601FormatStyle()

    // A time goes into the file cut down to its whole millisecond, and comes back as the earliest
    // instant that cuts down to that same millisecond. So reading and writing again never moves it
    // (ISO8601FormatStyle alone reads "….002Z" as a hair under 2 ms and writes it back as "….001Z"),
    // and a row read from a file is never later than the phone's own copy of it: an export merged
    // back never outranks the row it came from, whose place, coordinates and basket item the file
    // does not carry.

    /// "2027-10-20T03:00:00.250Z": UTC, to the millisecond, cut down (not rounded).
    static func timestamp(_ d: Date) -> String {
        let t = d.timeIntervalSinceReferenceDate
        guard t.isFinite else { return fractional.format(d) }
        let ms = (t * 1000).rounded(.down)
        let seconds = (ms / 1000).rounded(.down)
        let rest = Int(ms - seconds * 1000)
        var text = whole.format(Date(timeIntervalSinceReferenceDate: seconds))
        guard text.last == "Z" else { return fractional.format(d) }
        text.removeLast()
        let digits = String(rest)
        return text + "." + String(repeating: "0", count: max(0, 3 - digits.count)) + digits + "Z"
    }

    /// A time as this file writes it, or as earlier builds read it: with or without the fraction,
    /// in UTC or with an offset.
    static func date(_ s: String) -> Date? {
        guard let d = (try? fractional.parse(s)) ?? (try? whole.parse(s)) else { return nil }
        let t = d.timeIntervalSinceReferenceDate
        guard t.isFinite else { return d }
        // the millisecond written: the nearest one when the text was ours (a hair off from parsing),
        // else the one it falls in
        let near = (t * 1000).rounded()
        let ms = abs(t * 1000 - near) < 0.01 ? near : (t * 1000).rounded(.down)
        var x = ms / 1000
        while (x * 1000).rounded(.down) < ms { x = x.nextUp }
        while (x.nextDown * 1000).rounded(.down) >= ms { x = x.nextDown }
        return Date(timeIntervalSinceReferenceDate: x)
    }

    // MARK: - Fields

    private static func field(_ s: String) -> String {
        // by scalars: "\r\n" is one Character, and in neither ",\"\n\r" set
        s.unicodeScalars.contains { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }
            ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    private static func isBlank(_ row: [String]) -> Bool {
        row.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// RFC 4180: quoted fields may hold commas, quotes (doubled) and line breaks. Every record comes
    /// back, blank ones too, so a row keeps the number a spreadsheet shows for it.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                // "\r\n" is one Character in Swift
                row.append(field); field = ""
                rows.append(row)
                row = []
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

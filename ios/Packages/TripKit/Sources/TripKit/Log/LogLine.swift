import Foundation

// The app's log as plain values: what one line holds and how it is written (one JSON object per line,
// JSON Lines), and the rounding that keeps a position out of it. The app writes the lines to a file
// a day (`LogRetention`), through a queue (`LogQueue`); nothing here touches a file.

/// How much a line matters. Ordered: the log page filters on "this level or above".
public enum LogLevel: String, Codable, Sendable, Comparable, CaseIterable {
    case info, warning, error

    private var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .error: 2
        }
    }

    public static func < (a: LogLevel, b: LogLevel) -> Bool {
        a.rank < b.rank
    }
}

/// What part of the app a line is about: its os.Logger category too, so Console filters the same way.
public enum LogCategory: String, Codable, Sendable, CaseIterable {
    case app, offline, map, alarm, notify, ride, location, sync, records, forecast, talk, settings, check, dev, metrics
}

/// One line of the log. `t` is the real instant it was logged (never the rehearsal clock), written
/// in UTC to the millisecond; `fields` are short values (ids, counts, rounded positions), never text
/// the user typed or the other phone's name.
public struct LogLine: Codable, Sendable, Equatable {
    public let t: Date
    public let level: LogLevel
    public let cat: LogCategory
    public let msg: String
    public let fields: [String: String]?

    public init(t: Date, level: LogLevel, cat: LogCategory, msg: String, fields: [String: String]? = nil) {
        self.t = t
        self.level = level
        self.cat = cat
        self.msg = msg
        self.fields = fields
    }

    /// "2027-01-15T08:00:00.500Z": UTC, the millisecond cut down (not rounded), so lines written in
    /// order keep their order
    private static let time = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    /// a time without its fraction, read as well
    private static let whole = Date.ISO8601FormatStyle()

    /// The line as the file holds it: one JSON object with its keys sorted, and one "\n" at its end
    /// (a "\n" in the text is written "\\n"). Without `fields` when there are none.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Self.time.format(date))
        }
        var data: Data
        do {
            data = try encoder.encode(self)
        } catch {
            // strings, two enums and a date always encode; should they not, still one line, not a crash
            let fallback = #"{"cat":"\#(cat.rawValue)","level":"\#(level.rawValue)","msg":"(không mã hoá được)","t":"\#(Self.time.format(t))"}"#
            data = Data(fallback.utf8)
        }
        data.append(0x0A)
        return data
    }

    /// The line `encoded` wrote (its "\n" or none); nil for anything else: an empty or broken line, a
    /// level or a group this build does not know, a time that is not one.
    public static func decode(_ line: Data) -> LogLine? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = (try? time.parse(text)) ?? (try? whole.parse(text)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a time: \(text)")
            }
            return date
        }
        do {
            return try decoder.decode(LogLine.self, from: line)
        } catch {
            return nil
        }
    }
}

/// Positions in the log: rounded to a hundredth of a degree (about a kilometre), never exact.
public enum LogRedact {
    /// The coordinate rounded to hundredths, half away from zero; never −0.
    public static func round(_ c: Coordinate) -> Coordinate {
        Coordinate(hundredths(c.lat), hundredths(c.lng))
    }

    /// "35.69,139.69": the rounded coordinate with two decimals and a point, whatever the locale.
    public static func text(_ c: Coordinate) -> String {
        "\(fixed(c.lat)),\(fixed(c.lng))"
    }

    private static func hundredths(_ x: Double) -> Double {
        // `+ 0.0` turns the −0 of a small negative value into 0
        (x * 100).rounded() / 100 + 0.0
    }

    private static func fixed(_ x: Double) -> String {
        let h = (x * 100).rounded()
        // nothing a position holds, but never a trap on the way to Int
        guard h.isFinite, abs(h) < 1e15 else { return "\(x)" }
        let n = Int(h)
        let whole = abs(n) / 100
        let cents = abs(n) % 100
        return (n < 0 ? "-" : "") + "\(whole)." + (cents < 10 ? "0" : "") + "\(cents)"
    }
}

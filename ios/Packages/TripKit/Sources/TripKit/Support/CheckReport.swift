import Foundation

// Settings › Hỗ trợ › Kiểm tra (spec 2.3): eight checks, each ok, a warning or an error with one short line. The
// order they are shown and kept in, the levels that are rules rather than one comparison, and the line the main
// page says of a run are here; the app reads the phone and the network and builds the other lines.

/// How a check came out. Ordered: the worst of several is the `max`.
public enum CheckLevel: Int, Codable, Sendable, Comparable {
    case ok, warning, error

    public static func < (a: CheckLevel, b: CheckLevel) -> Bool {
        a.rawValue < b.rawValue
    }
}

/// The checks, in the order the page shows them.
public enum CheckID: String, Codable, Sendable, CaseIterable {
    case permissions, offline, storage, records, reminders, sync, network, clock
}

/// One check's outcome: its level and one short line. The line is the app's own sentence (counts, sizes, codes):
/// it is kept, logged and exported, so it never holds text the user typed nor the other phone's name.
public struct CheckResult: Codable, Sendable, Equatable {
    public let id: CheckID
    public let level: CheckLevel
    public let line: String

    public init(id: CheckID, level: CheckLevel, line: String) {
        self.id = id
        self.level = level
        self.line = line
    }
}

public enum CheckReport {
    /// What a server said to a request: a status (any: it answered), a page of another host (a hotel Wi‑Fi's login
    /// page answers in its place), or nothing (offline, a timeout, a name that does not resolve).
    public enum Answer: Sendable, Equatable {
        case status(Int)
        case elsewhere
        case none
    }

    /// "Ổn" when nothing needs a look; else "1 lỗi · 2 cảnh báo", each part only when there is one.
    public static func summary(_ r: [CheckResult]) -> String {
        let errors = r.filter { $0.level == .error }.count
        let warnings = r.filter { $0.level == .warning }.count
        var parts: [String] = []
        if errors > 0 { parts.append("\(errors) lỗi") }
        if warnings > 0 { parts.append("\(warnings) cảnh báo") }
        return parts.isEmpty ? "Ổn" : parts.joined(separator: " · ")
    }

    /// The results in `CheckID` order, whichever finished first; two of one check keep their order.
    public static func ordered(_ r: [CheckResult]) -> [CheckResult] {
        let rank = Dictionary(uniqueKeysWithValues: CheckID.allCases.enumerated().map { ($1, $0) })
        return r.enumerated().sorted { a, b in
            let (x, y) = (rank[a.element.id] ?? 0, rank[b.element.id] ?? 0)
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
    }

    /// Under 1 GB free (decimal, as `ByteCountFormatter` shows it) is a warning.
    public static func storage(freeBytes: Int64) -> CheckLevel {
        freeBytes < 1_000_000_000 ? .warning : .ok
    }

    /// A rehearsal moves the app's clock: what it says of times is not now.
    public static func clock(rehearsing: Bool) -> CheckResult {
        rehearsing
            ? CheckResult(id: .clock, level: .warning, line: "Đang chạy thử: giờ của app khác giờ thật")
            : CheckResult(id: .clock, level: .ok, line: "Giờ thật")
    }

    /// No network is a warning, whatever was asked (nothing is). With one: a server that did not answer is an error;
    /// one that answered is there, so its status only warns when it says something is wrong — the tile build gone
    /// (404, 410), any other error of the tile server, a server error of the forecast one (its bare URL may answer a
    /// client error), a login page in their place. `tiles` nil: the map's build is not one that can be asked.
    public static func network(online: Bool, tiles: Answer?, forecast: Answer?) -> CheckResult {
        guard online else { return CheckResult(id: .network, level: .warning, line: "Không có mạng") }
        var parts: [(CheckLevel, String)] = []
        let elsewhere = "Wi‑Fi chuyển sang trang khác (cần đăng nhập?)"
        switch tiles {
        case nil:
            parts.append((.warning, "Không biết build bản đồ đang đọc"))
        case .none?:
            parts.append((.error, "Máy chủ bản đồ không trả lời"))
        case .elsewhere?:
            parts.append((.warning, elsewhere))
        case .status(let code)?:
            if code == 404 || code == 410 {
                parts.append((.warning, "Build bản đồ không còn trên máy chủ (\(code))"))
            } else if code >= 400 {
                parts.append((.warning, "Máy chủ bản đồ lỗi (\(code))"))
            }
        }
        switch forecast {
        case nil:
            break
        case .none?:
            parts.append((.error, "Máy chủ dự báo không trả lời"))
        case .elsewhere?:
            if !parts.contains(where: { $0.1 == elsewhere }) { parts.append((.warning, elsewhere)) }
        case .status(let code)?:
            if code >= 500 { parts.append((.warning, "Máy chủ dự báo lỗi (\(code))")) }
        }
        guard let worst = parts.map(\.0).max() else {
            return CheckResult(id: .network, level: .ok, line: "Bản đồ và dự báo trả lời")
        }
        return CheckResult(id: .network, level: worst, line: parts.map(\.1).joined(separator: " · "))
    }

    /// The readiness list's line (`Readiness.summary`): ok when it says ready, an error when an item failed, a
    /// warning for anything else (missing, downloading, stale, not read yet).
    public static func offline(_ states: [ReadyItem: ReadyState], mapsStale: Bool, downloading: Double?) -> CheckResult {
        let line = Readiness.summary(states, mapsStale: mapsStale, downloading: downloading)
        let failed = states.values.contains { if case .failed = $0 { true } else { false } }
        let level: CheckLevel = failed ? .error : (line == Readiness.ready ? .ok : .warning)
        return CheckResult(id: .offline, level: level, line: line)
    }
}

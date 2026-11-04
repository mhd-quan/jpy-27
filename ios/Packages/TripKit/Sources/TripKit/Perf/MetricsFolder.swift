import Foundation

/// The files of `Caches/metrics/`: each MetricKit payload the app received is two files under one stem,
/// MetricKit's own JSON (shared from Chẩn đoán › Số đo) and the `MetricsSummary` the page shows. The 14
/// newest payloads stay; a file whose name is not of this form is never touched.
public enum MetricsFolder {
    /// payloads kept: two weeks of daily reports
    public static let keep = 14

    private static let prefix = "metrics-"
    private static let summaryExtension = ".summary.json"
    private static let payloadExtension = ".json"

    /// "metrics-20261105T070000Z-0": the payload's end in UTC, fixed width so that names sort as time,
    /// then its place in the delivery (MetricKit can hand over several payloads at once).
    public static func stem(end: Date, index: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: end)
        let stamp = String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "\(prefix)\(stamp)-\(index)"
    }

    /// MetricKit's JSON of the payload
    public static func payload(_ stem: String) -> String { stem + payloadExtension }

    /// the `MetricsSummary` of the payload
    public static func summary(_ stem: String) -> String { stem + summaryExtension }

    /// The files to delete so that the `keep` newest payloads stay (a payload's two files go together).
    /// Names that are not ours are never returned.
    public static func stale(_ names: [String], keep: Int = keep) -> [String] {
        let ours = names.compactMap { name in key(of: name).map { (name: name, key: $0) } }
        let newest = Set(Set(ours.map(\.key)).sorted { ($0.stamp, $0.index) > ($1.stamp, $1.index) }.prefix(max(0, keep)))
        return ours.filter { !newest.contains($0.key) }.map(\.name)
    }

    private struct Key: Hashable {
        let stamp: String
        let index: Int
    }

    /// The stem's parts, when `name` is one of ours.
    private static func key(of name: String) -> Key? {
        let stem: Substring
        if name.hasSuffix(summaryExtension) {
            stem = name.dropLast(summaryExtension.count)
        } else if name.hasSuffix(payloadExtension) {
            stem = name.dropLast(payloadExtension.count)
        } else {
            return nil
        }
        guard stem.hasPrefix(prefix) else { return nil }
        let parts = stem.dropFirst(prefix.count).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, isStamp(parts[0]), !parts[1].isEmpty, parts[1].allSatisfy(\.isASCIIDigit), let index = Int(parts[1]) else { return nil }
        return Key(stamp: String(parts[0]), index: index)
    }

    /// "20261105T070000Z"
    private static func isStamp(_ s: Substring) -> Bool {
        let chars = Array(s)
        guard chars.count == 16, chars[8] == "T", chars[15] == "Z" else { return false }
        return (chars[0..<8] + chars[9..<15]).allSatisfy(\.isASCIIDigit)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}

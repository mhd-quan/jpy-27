import SwiftUI
import TripKit

// Small pieces the Plan tab and its guide pages share. Prefixed so they never meet another
// feature's helpers.

/// "Thứ Ba 19/10"
func planDateLabel(_ day: Day) -> String {
    "\(day.dow) \(Fmt.shortDate(day.date))"
}

/// "Ngày 4", or an alternative day's title.
func planDayName(_ key: String, store: TripStore) -> String {
    Int(key) != nil ? "Ngày \(key)" : (store.day(key)?.title ?? key)
}

/// Day-of-week numbers as research writes them (0 = Sunday).
func planWeekdays(_ dows: [Int]) -> String {
    let names = ["CN", "T2", "T3", "T4", "T5", "T6", "T7"]
    return dows.compactMap { names.indices.contains($0) ? names[$0] : nil }.joined(separator: ", ")
}

/// A short tag for a source link: "Tabelog", "Wikipedia", "Instagram"…
func planSourceLabel(_ url: String) -> String {
    let host = URL(string: url)?.host()?.lowercased() ?? ""
    let table: [(String, String)] = [
        ("tabelog", "Tabelog"), ("wikipedia", "Wikipedia"), ("instagram", "Instagram"), ("tiktok", "TikTok"),
        ("youtube", "YouTube"), ("youtu.be", "YouTube"), ("4travel", "4travel"), ("jalan", "Jalan"),
        ("openstreetmap", "OSM"), ("commons.wikimedia", "Commons"), ("google", "Google"), ("x.com", "X"), ("twitter", "X"),
    ]
    return table.first { host.contains($0.0) }?.1 ?? "Web"
}

/// Whether a plan day has started (today or before), in Japan time.
func planHasStarted(_ day: Day, now: Date) -> Bool {
    day.date <= TripTime.isoDate(of: now)
}

/// Link chips: a source opens in Safari.
struct PlanLinkChips: View {
    let links: [(title: String, url: String)]

    var body: some View {
        if !links.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Array(links.enumerated()), id: \.offset) { _, l in
                        if let url = URL(string: l.url) {
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text(l.title)
                                    Image(systemName: "arrow.up.right").imageScale(.small)
                                }
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 12)
                                .frame(minHeight: 32)
                                .background(.fill.tertiary, in: .capsule)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    init(links: [(title: String, url: String)]) {
        self.links = links
    }

    /// Sources named by their site, duplicates dropped.
    init(sources: [String]) {
        var seen = Set<String>()
        links = sources.compactMap { s in seen.insert(s).inserted ? (planSourceLabel(s), s) : nil }
    }
}

/// A labelled fact: icon, what it is, the text.
struct PlanInfoRow: View {
    let symbol: String
    let text: String
    var label: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
                Text(text).font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bullet list of short sentences.
struct PlanBullets: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(.secondary).accessibilityHidden(true)
                    Text(line).font(.subheadline)
                }
            }
        }
    }
}

/// A titled paragraph inside a card: a small heading, the text.
struct PlanParagraph: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rows separated by inset dividers inside a card.
struct PlanRows<Item, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                if i > 0 { Divider() }
                row(item)
            }
        }
    }
}

extension JSONValue {
    /// Text of a loose research field, numbers included.
    var planText: String? {
        switch self {
        case .string(let s): s.isEmpty ? nil : s
        case .number(let n): n == n.rounded() ? Fmt.grouped(Int(n)) : Fmt.decimal(n, digits: 1)
        default: nil
        }
    }
}

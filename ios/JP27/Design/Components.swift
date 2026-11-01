import SwiftUI
import TripKit

// The app's building blocks. Content sits on grouped backgrounds in rounded cards; Liquid Glass is
// kept for controls — the tab bar, toolbars, map controls, action buttons — through the system's
// glass button styles, so glass never sits on glass. How sheets come and go is in Presentation.swift.

enum Metrics {
    /// screen edge inset; Pro Max gets a touch more room
    static let gutter: CGFloat = 20
    static let card: CGFloat = 26
    static let row: CGFloat = 14
    static let stack: CGFloat = 24
}

/// A content card on the grouped background.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Metrics.card, style: .continuous))
    }
}

/// Section title inside a scroll view: no restating, just the name of what follows.
struct SectionTitle: View {
    let title: String
    var trailing: String? = nil

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.semibold))
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
        }
        .padding(.top, 8)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The line a leg runs on, in its operator's colour.
struct LineBadge: View {
    let name: String
    let color: Color
    let mode: Mode
    var compact = false

    init(line: Line, compact: Bool = false) {
        name = line.name
        color = Color(hex: line.color)
        mode = line.mode
        self.compact = compact
    }

    init(name: String, color: Color, mode: Mode, compact: Bool = false) {
        self.name = name
        self.color = color
        self.mode = mode
        self.compact = compact
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: mode.symbol).imageScale(.small)
            if !compact { Text(name).lineLimit(1) }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(mode == .walk ? Color.primary : .white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .background(mode == .walk ? AnyShapeStyle(.fill.secondary) : AnyShapeStyle(color), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }
}

/// Yen with Vietnamese grouping and tabular digits.
struct YenText: View {
    let yen: Int
    var body: some View {
        Text(Fmt.yen(yen)).monospacedDigit()
    }
}

/// A round check, for a stop visited or an item bought.
struct CheckButton: View {
    let isOn: Bool
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isOn ? tint : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isOn) { _, new in new }
        .accessibilityLabel(isOn ? "Đã xong" : "Chưa xong")
        .accessibilityAddTraits(isOn ? [.isSelected, .isButton] : .isButton)
    }
}

/// A small label in a tinted capsule: "Chỉ tiền mặt", "Đã đặt", "Tuỳ chọn".
struct Tag: View {
    let text: String
    var symbol: String? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: .capsule)
        .accessibilityElement(children: .combine)
    }
}

/// A thin bar for spent against planned.
struct Meter: View {
    let value: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                Capsule().fill(value > 1 ? Color.red : tint)
                    .frame(width: max(4, g.size.width * min(1, value)))
            }
        }
        .frame(height: 6)
        .accessibilityValue(Text("\(Int(value * 100))%"))
    }
}

/// Japanese with its reading and meaning, the way every phrase and dish is shown.
struct JapaneseLine: View {
    let ja: String
    var romaji: String?
    var vi: String?
    var size: Font = .title3

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ja).font(size.weight(.semibold)).environment(\.locale, Locale(identifier: "ja_JP"))
            if let romaji { Text(romaji).font(.subheadline).foregroundStyle(.secondary).italic() }
            if let vi { Text(vi).font(.subheadline) }
        }
        .textSelection(.enabled)
    }
}

/// A figure with its unit underneath, for stat rows.
struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Mode icon in a coloured circle, the timeline's left rail.
struct ModeDot: View {
    let mode: Mode
    let color: Color
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: mode.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(mode == .walk ? Color.secondary : .white)
            .frame(width: size, height: size)
            .background(mode == .walk ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(color), in: .circle)
    }
}

extension View {
    /// The grouped background every scrolling screen sits on.
    func screen() -> some View {
        background(Color(.systemGroupedBackground))
    }
}

extension TripPhase {
    var isDuring: Bool {
        if case .during = self { return true }
        return false
    }
}

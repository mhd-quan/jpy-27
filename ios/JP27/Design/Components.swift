import SwiftUI
import TripKit

// The app's building blocks. Content sits on warm paper in white cards; Liquid Glass is kept for
// controls — the tab bar, toolbars, map controls, action buttons — through the system's glass
// button styles, so glass never sits on glass. Colours and marks are in Theme.swift, how sheets
// come and go in Presentation.swift.

enum Metrics {
    /// screen edge inset; Pro Max gets a touch more room
    static let gutter: CGFloat = 20
    static let card: CGFloat = 26
    static let row: CGFloat = 14
    static let stack: CGFloat = 24
}

/// A content card on the grouped background.
struct Card<Content: View>: View {
    @Environment(\.cardSurface) private var surface
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(surface ?? Palette.card, in: .rect(cornerRadius: Metrics.card, style: .continuous))
    }
}

private nonisolated struct CardSurfaceKey: EnvironmentKey {
    static var defaultValue: Color? { nil }
}

extension EnvironmentValues {
    /// What cards are filled with: the card colour on paper, unless a page lays its cards as
    /// translucent tints over a colour of its own (the ambient place page).
    nonisolated var cardSurface: Color? {
        get { self[CardSurfaceKey.self] }
        set { self[CardSurfaceKey.self] = newValue }
    }
}

/// Section title inside a scroll view: no restating, just the name of what follows. An eyebrow
/// (a word in red above, often the Japanese) marks the sections of the home page.
struct SectionTitle: View {
    let title: String
    var trailing: String? = nil
    var eyebrow: String? = nil

    init(_ title: String, trailing: String? = nil, eyebrow: String? = nil) {
        self.title = title
        self.trailing = trailing
        self.eyebrow = eyebrow
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow {
                Text(eyebrow)
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(Palette.sun)
                    .textCase(.uppercase)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.title3.weight(.bold))
                Spacer()
                if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary).monospacedDigit() }
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
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

/// A round check, for a stop visited or an item bought; it lands in red like a hanko stamp.
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
                .symbolEffect(.bounce, value: isOn)
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
    /// indigo while within plan; over plan it turns red, the one colour that means "now"
    var tint: Color = Palette.ai

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.fill.tertiary)
                Capsule().fill(value > 1 ? Palette.sun : tint)
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
    /// The paper every scrolling screen sits on, with the soft edge under its bars.
    func screen() -> some View {
        progressiveEdges().background(Palette.paper)
    }

    /// A grouped list on the same paper; its rows keep the system's card colour.
    func paperList() -> some View {
        scrollContentBackground(.hidden).progressiveEdges().background(Palette.paper)
    }
}

extension TripPhase {
    var isDuring: Bool {
        if case .during = self { return true }
        return false
    }
}

// MARK: - Detail pages

/// The top of a detail page: a photograph filling the page up to its top edge, under the bar and
/// its buttons, with the page's name set on a soft blur at the photograph's foot. There is no bar
/// strip while it is in view; `detailPage` brings the name into the bar once it has scrolled away.
struct DetailHero<Background: View, Foot: View>: View {
    let title: String
    var subtitle: String?
    var height: CGFloat = 440
    @ViewBuilder var background: Background
    /// under the name: tags, page dots, a credit
    @ViewBuilder var foot: Foot

    var body: some View {
        Color.clear
            .frame(height: height)
            .overlay { background }
            .clipped()
            // a little shade under the bar so its glass buttons and the status bar read on a
            // bright sky
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 110)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if let subtitle {
                        Text(subtitle)
                            .font(.mincho(22))
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                            .opacity(0.9)
                    }
                    foot
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 56)
                .padding(.bottom, 18)
                .background { HeroBlur() }
                .environment(\.colorScheme, .dark)
                .accessibilityElement(children: .contain)
            }
    }
}

/// A blur that rises from nothing into a frosted foot, with a shade for white type: the soft,
/// progressive edge, not a band with a hard top.
struct HeroBlur: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.7), location: 0.45), .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
                }
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.42), location: 1)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// A scroll view whose first child is a `DetailHero`: it runs under the bar, the bar shows no
    /// edge and no title over the photograph, and the name comes into the bar (with the system's
    /// soft edge) once the photograph has scrolled away.
    /// `scheme` is the bar's once the photograph has gone: nil follows the system, a page laid on a
    /// colour of its own passes that colour's.
    func detailPage(title: String, heroHeight: CGFloat = 440, scheme: ColorScheme? = nil) -> some View {
        modifier(DetailPage(title: title, heroHeight: heroHeight, scheme: scheme))
    }
}

private struct DetailPage: ViewModifier {
    let title: String
    let heroHeight: CGFloat
    let scheme: ColorScheme?
    @State private var past = false

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(edges: .top)
            .scrollEdgeEffectHidden(!past, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y + geo.contentInsets.top > heroHeight - 130
            } action: { _, now in
                withAnimation(.smooth(duration: 0.25)) { past = now }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .opacity(past ? 1 : 0)
                        .accessibilityHidden(!past)
                }
            }
            // light status bar and bar glyphs over the photograph
            .toolbarColorScheme(past ? scheme : .dark, for: .navigationBar)
    }
}

/// Small page dots for a hero's photographs.
struct HeroDots: View {
    let count: Int
    let current: Int

    var body: some View {
        if count > 1 {
            HStack(spacing: 5) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(i == current ? 1 : 0.4))
                        .frame(width: i == current ? 16 : 6, height: 6)
                }
            }
            .animation(.smooth(duration: 0.3), value: current)
            .accessibilityHidden(true)
        }
    }
}

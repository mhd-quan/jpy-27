import SwiftUI
import TripKit
import UIKit

// The app's taste. White paper and the flag's red, the way the Hinomaru is drawn: red is the one
// loud colour and it marks what matters now (the countdown, the next departure, lateness, a stop
// stamped as visited). Indigo is the second stripe, gold marks the best of something, and the
// operators' own line colours carry everything that moves. Japanese set as ornament is Mincho;
// figures are SF Rounded with tabular digits.

enum Palette {
    /// 紅 — the flag's red (AccentColor), brighter on black
    static let sun = Color.accentColor
    /// 和紙 — warm paper behind every screen
    static let paper = Color("Paper")
    /// the surface cards sit on the paper with
    static let card = Color("Card")
    /// 藍 — indigo, the second stripe: transit, information
    static let ai = Color("Ai")
    /// 金 — signature dishes, ratings, the best of something
    static let kin = Color("Kin")
    /// 抹茶 — booked, on time, saved
    static let matcha = Color("Matcha")
    /// 桜 — the soft tint behind red
    static let sakura = Color("Sakura")
    /// Fuji's violet, from the web's window-side strips
    static let fuji = Color(hex: "#6B4FD8")
}

// MARK: - Appearance

/// Light, dark, or whatever the phone is set to (the default). Every colour is an asset with a dark
/// variant and the map swaps to its dark style, so "automatic" is the system's own switch.
/// Applied to the windows rather than with `preferredColorScheme`: going back to automatic from a
/// forced scheme takes effect at once, and sheets, alerts and the map follow without being told.
nonisolated enum Appearance: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    static let key = "appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Tự động"
        case .light: "Sáng"
        case .dark: "Tối"
        }
    }

    private var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Sets every window's style; a change made from Settings cross-fades instead of snapping.
    @MainActor func apply(animated: Bool) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        for window in windows where window.overrideUserInterfaceStyle != style {
            if animated && !UIAccessibility.isReduceMotionEnabled {
                UIView.transition(with: window, duration: 0.35, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                    window.overrideUserInterfaceStyle = style
                }
            } else {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

// MARK: - Colour and words for the data

extension Place.Kind {
    /// Kind colours from traditional dyes: persimmon food, indigo sights, wisteria stays, peach shops.
    var tint: Color {
        switch self {
        case .food: Color(hex: "#E07A2F")
        case .sight: Palette.ai
        case .stay: Color(hex: "#7A5BB5")
        case .shop: Color(hex: "#C94F7C")
        case .station: Color(.systemGray)
        }
    }
}

extension Chapter {
    /// The city in kanji, set large in Mincho on the chapter line and the day cards.
    var kanji: String {
        ["tokyo": "東京", "hakone": "箱根", "ise": "伊勢", "kyoto": "京都", "osaka": "大阪"][id] ?? name
    }

    var tint: Color { Color(hex: color) }
}

extension Day {
    /// 月火水木金土日 from the Vietnamese weekday, as on a Japanese calendar.
    var dowKanji: String {
        ["Thứ Hai": "月", "Thứ Ba": "火", "Thứ Tư": "水", "Thứ Năm": "木", "Thứ Sáu": "金", "Thứ Bảy": "土", "Chủ Nhật": "日"][dow] ?? ""
    }
}

extension Font {
    /// Hiragino Mincho, for Japanese set as a headline or an ornament.
    static func mincho(_ size: CGFloat, bold: Bool = true, relativeTo style: Font.TextStyle = .title) -> Font {
        .custom(bold ? "HiraMinProN-W6" : "HiraMinProN-W3", size: size, relativeTo: style)
    }

    /// Big figures: countdowns, day numbers, totals.
    static func figure(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Marks

/// The Hinomaru drawn as the web's logo: a white square, an ink edge, the red disc.
struct HinomaruMark: View {
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
        ZStack {
            shape.fill(Color.white)
            shape.strokeBorder(Color.black.opacity(0.82), lineWidth: max(1, size * 0.07))
            Circle()
                .fill(Palette.sun)
                .frame(width: size * 0.52, height: size * 0.52)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// "JP27" set wide and black, as the web's wordmark.
struct Wordmark: View {
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: size * 0.45) {
            HinomaruMark(size: size * 1.3)
            WordmarkText(text: "JP27", size: size)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("JP27")
    }
}

/// A word set the way the wordmark is: black, expanded, tracked a little. Page names that stand
/// in for the wordmark (the Fuji map's) use it.
struct WordmarkText: View {
    let text: String
    var size: CGFloat = 15

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .black).width(.expanded))
            .tracking(0.4)
    }
}

/// Two stripes, red over indigo, the way a livery runs along a train's side.
struct Livery: View {
    var width: CGFloat? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Capsule().fill(Palette.sun).frame(height: 3)
            Capsule().fill(Palette.ai).frame(height: 1.5)
        }
        .frame(width: width)
        .accessibilityHidden(true)
    }
}

// MARK: - Press

/// Cards, tiles and chips that open something: they settle a little under the finger, the way the
/// system's own cards do, and play `press` as they fire. The haptic follows the button's trigger,
/// so a touch that a scroll takes back stays quiet. NavigationLinks and Links have no action of
/// their own to count in, so they get it from here too, in the look they already had.
struct PressableStyle: PrimitiveButtonStyle {
    enum Look {
        /// settles a little under the finger
        case settle
        /// the plain style: drawn as it is; the system dims it while held, unless it reports the press
        /// (`PlainPressStyle`, which draws the label unchanged)
        case plain
        /// text in the tint colour, as a link
        case borderless
        case bordered
        case glass
    }

    var look: Look = .settle
    /// false for a button whose action plays a haptic of its own (a choice that ticks `pick`)
    var felt = true
    /// called as a finger comes down on it (`isPressed` turning true), before it fires: the page it opens starts
    /// loading (`Prefetch`). Only the `.settle` and `.plain` looks report it.
    var onPress: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        PressableButton(configuration: configuration, look: look, felt: felt, onPress: onPress)
    }
}

extension PrimitiveButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }

    /// `press` in another look: `.pressable(.plain)` for a card that keeps the plain style,
    /// `.pressable(.bordered)` for a NavigationLink drawn as a bordered button.
    static func pressable(_ look: PressableStyle.Look, felt: Bool = true, onPress: (() -> Void)? = nil) -> PressableStyle {
        PressableStyle(look: look, felt: felt, onPress: onPress)
    }
}

/// The button a PressableStyle draws: the same label, role and action, felt as it fires. The
/// haptic plays at once rather than through `sensoryFeedback`: many of these close their sheet or
/// open a page over themselves as they fire, and a view on its way out gets no next update.
private struct PressableButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let look: PressableStyle.Look
    let felt: Bool
    let onPress: (() -> Void)?

    var body: some View {
        let button = Button(role: configuration.role) {
            if felt { Haptic.press() }
            configuration.trigger()
        } label: {
            configuration.label
        }
        Group {
            switch look {
            case .settle: button.buttonStyle(SettleStyle(felt: felt, onPress: onPress))
            case .plain:
                if let onPress {
                    button.buttonStyle(PlainPressStyle(onPress: onPress))
                } else {
                    button.buttonStyle(.plain)
                }
            case .borderless: button.buttonStyle(.borderless)
            case .bordered: button.buttonStyle(.bordered)
            case .glass: button.buttonStyle(.glass)
            }
        }
    }
}

private struct SettleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// the button plays `press` as it fires: the finger coming down readies it (`Haptic.prepare`)
    var felt = false
    var onPress: (() -> Void)?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.reduced(Motion.press, reduceMotion), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in
                guard down else { return }
                if felt { Haptic.prepare(.press) }
                onPress?()
            }
    }
}

/// The plain look for a button that says when a finger comes down: the label drawn as it is, with no effect while
/// held. The system's plain style cannot be wrapped for this (it is a primitive style, whose configuration has no
/// `isPressed`), so its dimming under the finger is not there.
private struct PlainPressStyle: ButtonStyle {
    let onPress: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, down in if down { onPress() } }
    }
}

// MARK: - Route spark

/// The day's real path, every leg in its line's colour, drawn small (the web's RouteSpark):
/// solid for rail and road, dashed over water and air, dotted on foot; open circle at the start,
/// filled at the end.
struct RouteSpark: View {
    struct Leg {
        let points: [CGPoint]
        let color: Color
        let mode: Mode
    }

    let legs: [Leg]
    /// extent of the points, in the same units
    let size: CGSize
    let weight: CGFloat

    init(day: Day, store: TripStore, weight: CGFloat = 2.4) {
        self.weight = weight
        var raw: [([Coordinate], Color, Mode)] = []
        for item in day.items {
            guard case .move(let m) = item else { continue }
            let points = store.path(m.leg.id)
            guard points.count > 1 else { continue }
            let line = store.line(m.leg.line)
            raw.append((points, Color(hex: line?.color ?? "#8E8E93"), line?.mode ?? .walk))
        }
        let all = raw.flatMap { $0.0 }
        let minLat = all.map(\.lat).min() ?? 0, maxLat = all.map(\.lat).max() ?? 0
        let minLng = all.map(\.lng).min() ?? 0, maxLng = all.map(\.lng).max() ?? 0
        let k = cos((minLat + maxLat) / 2 * .pi / 180)
        legs = raw.map { pts, color, mode in
            Leg(points: pts.map { CGPoint(x: ($0.lng - minLng) * k, y: maxLat - $0.lat) }, color: color, mode: mode)
        }
        size = CGSize(width: (maxLng - minLng) * k, height: maxLat - minLat)
    }

    var body: some View {
        ZStack {
            ForEach(Array(legs.enumerated()), id: \.offset) { _, leg in
                SparkShape(points: leg.points, extent: size)
                    .stroke(leg.mode == .walk ? Color.secondary : leg.color, style: style(leg.mode))
            }
            if let first = legs.first?.points.first {
                SparkDot(point: first, extent: size, radius: weight * 1.4)
                    .stroke(Color.primary, lineWidth: weight * 0.8)
            }
            if let last = legs.last?.points.last {
                SparkDot(point: last, extent: size, radius: weight * 1.4)
                    .fill(Color.primary)
            }
        }
        .accessibilityHidden(true)
    }

    private func style(_ mode: Mode) -> StrokeStyle {
        switch mode {
        case .walk: StrokeStyle(lineWidth: weight * 0.6, lineCap: .round, lineJoin: .round, dash: [0.1, weight * 1.3])
        case .ferry, .cruise, .ropeway: StrokeStyle(lineWidth: weight, lineCap: .butt, lineJoin: .round, dash: [weight * 1.3, weight])
        default: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
        }
    }
}

/// Fits `extent` into the rect, keeping its shape, with room for the stroke.
private nonisolated func sparkMap(_ extent: CGSize, in rect: CGRect) -> (CGPoint) -> CGPoint {
    let inset: CGFloat = 4
    let w = max(extent.width, 1e-6), h = max(extent.height, 1e-6)
    let s = min((rect.width - 2 * inset) / w, (rect.height - 2 * inset) / h)
    let ox = rect.midX - w * s / 2, oy = rect.midY - h * s / 2
    return { CGPoint(x: ox + $0.x * s, y: oy + $0.y * s) }
}

private nonisolated struct SparkShape: Shape {
    let points: [CGPoint]
    let extent: CGSize

    func path(in rect: CGRect) -> Path {
        let map = sparkMap(extent, in: rect)
        var p = Path()
        p.addLines(points.map(map))
        return p
    }
}

private nonisolated struct SparkDot: Shape {
    let point: CGPoint
    let extent: CGSize
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = sparkMap(extent, in: rect)(point)
        return Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    }
}

// MARK: - Shapes

/// A vertical line through the middle of its frame: the timeline's rail.
nonisolated struct RailLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return p
    }
}

extension Mode {
    /// The web's line grammar: solid on rails and roads, dashed over water and air, dotted on foot.
    func rail(_ width: CGFloat) -> StrokeStyle {
        switch self {
        case .walk: StrokeStyle(lineWidth: width, lineCap: .round, dash: [0.1, width * 2])
        case .ferry, .cruise, .ropeway: StrokeStyle(lineWidth: width, lineCap: .butt, dash: [width * 1.6, width * 1.1])
        default: StrokeStyle(lineWidth: width, lineCap: .butt)
        }
    }
}

/// A ticket: rounded card with a notch top and bottom where the stub tears off.
nonisolated struct TicketShape: Shape {
    /// distance of the perforation from the leading edge
    var stub: CGFloat
    var radius: CGFloat = 22
    var notch: CGFloat = 9

    func path(in rect: CGRect) -> Path {
        let body = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let holes = CGMutablePath()
        let x = rect.minX + stub
        holes.addEllipse(in: CGRect(x: x - notch, y: rect.minY - notch, width: notch * 2, height: notch * 2))
        holes.addEllipse(in: CGRect(x: x - notch, y: rect.maxY - notch, width: notch * 2, height: notch * 2))
        return Path(body.subtracting(holes))
    }
}

/// Fuji above Suruga Bay from Satta Pass (`FujiPhotograph`), pinned to its top edge so the summit
/// stays in a frame wider than the photograph; a clear-sky blue holds its place while it loads.
struct FujiScene: View {
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(hex: "#5B86B8"))
            .overlay(alignment: .top) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .task {
                guard image == nil, let photo = FujiPhotograph.photo else { return }
                let loaded = await PhotoCache.shared.image(photo, maxPixel: 1600)
                withAnimation(Motion.arrive) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}

/// A glyph in white on a tinted rounded square, as Settings draws its rows: used where a list of
/// unlike things needs telling apart at a glance (guides, phrase situations).
struct GlyphTile: View {
    let symbol: String
    var tint: Color = Palette.sun
    var size: CGFloat = 30

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
        // the glyph fitted into half the tile and cut at its edge, as `SettingsIcon` does: drawn at a font
        // size, a wide one spilled out of the tile. Half keeps an ordinary glyph about the size the old
        // 0.48 font gave it; only the wide ones shrink
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: size * 0.5, height: size * 0.5)
            .frame(width: size, height: size)
            .background(tint.gradient, in: shape)
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}

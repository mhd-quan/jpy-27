import SwiftUI
import UIKit
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

// Haptics, named by what happened rather than how hard it taps, so the same moment feels the same
// on every screen. Everything the app draws for the hand to press or swipe answers with one, once
// per change: never while something streams or a finger is still moving, never for a value the app
// set by itself. The system's own controls keep their own feel and get nothing added: toggles,
// pickers, menus, the bars' buttons, a sheet's close and confirm, swipe actions, pull to refresh,
// tabs, alerts, and the rows of a settings-style list. Something that runs on (following a ride,
// the microphone, a download) begins with the system's .start, and what the hand stops ends with
// its .stop.
extension SensoryFeedback {
    /// A light, clear tap: a card, tile, chip or round button that opens something (a page, a
    /// sheet, a card grown large, Maps, a link), a section unfolded, a line read aloud. Folding it
    /// away again is quiet.
    nonisolated static var press: SensoryFeedback { .impact(weight: .light, intensity: 1) }
    /// One of a few chosen, and the choice shows at once: a day, a stop, a chip, a category, a
    /// viewpoint. Letting a choice go again is quiet.
    nonisolated static var pick: SensoryFeedback { .selection }
    /// Held or pulled far enough for something to happen: a long press that reads slowly, a pull
    /// past the end of the day, the map's panel let go at another height, the Fuji marker come
    /// into view.
    nonisolated static var snap: SensoryFeedback { .impact(weight: .medium, intensity: 0.8) }
    /// A carousel or a photo pager the hand swiped, landing on the next card: one for each card,
    /// as a wheel clicks through its rows.
    nonisolated static var page: SensoryFeedback { .impact(weight: .light, intensity: 0.7) }
    /// One key of the app's own number pad that changed the amount.
    nonisolated static var key: SensoryFeedback { .impact(flexibility: .rigid, intensity: 0.75) }
    /// A thing done: a stop marked, a purchase, expense or top-up saved, an address copied, a menu
    /// read. Undoing it is quiet.
    nonisolated static var done: SensoryFeedback { .success }
    /// Done, at a cost worth feeling: stops dropped from today's plan.
    nonisolated static var warn: SensoryFeedback { .warning }
    /// Asked for and it did not happen: the microphone refused, a menu photo with nothing to read.
    nonisolated static var fail: SensoryFeedback { .error }
    /// A count stepped up or down by one, as a stepper moves. Nothing steps a count yet; a stepper
    /// that does uses these.
    nonisolated static var more: SensoryFeedback { .increase }
    nonisolated static var less: SensoryFeedback { .decrease }
    /// A slider meeting a value that means something, never every step on the way to it.
    nonisolated static var notch: SensoryFeedback { .levelChange }
}

/// The same feel as `press`, `snap` and `page`, played the moment an action runs. For a press
/// whose view leaves with it (a button that closes its sheet, a row that opens a page over
/// itself) and for moments that come from a callback rather than a state the view shows:
/// `sensoryFeedback` plays on the view's next update, which a view on its way out never gets,
/// and a state added only to trigger it redraws the view that holds it.
enum Haptic {
    static func press() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 1) }
    static func snap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.8) }
    static func page() { UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.7) }
}

extension View {
    /// `page` each time a carousel the hand swiped moves on to another card, through the
    /// position it is bound to, the way a wheel clicks through its rows. A scroll the code makes
    /// (a cover that turns by itself, cards that follow another control) is quiet. Goes on the
    /// scroll view; `position` is what its scroll position is bound to.
    func feelsPages<Position: Equatable>(_ position: Position) -> some View {
        modifier(SettlePick(position: position))
    }
}

private struct SettlePick<Position: Equatable>: ViewModifier {
    let position: Position
    /// whether the hand is in the scroll: dragging, or the fling it let go of
    @State private var hand = Hand()

    final class Hand {
        var on = false
    }

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                // animating is a scroll the code started; idle is at rest
                hand.on = phase == .tracking || phase == .interacting || phase == .decelerating
            }
            .onChange(of: position) {
                if hand.on { Haptic.page() }
            }
    }
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

private nonisolated struct PageFillKey: EnvironmentKey {
    static var defaultValue: Color? { nil }
}

extension EnvironmentValues {
    /// The solid colour an ambient page is laid on, for a picture that dissolves into it.
    nonisolated var pageFill: Color? {
        get { self[PageFillKey.self] }
        set { self[PageFillKey.self] = newValue }
    }
}

extension View {
    /// Fades a picture out toward its bottom, into the page under it. `stops` are how much of the
    /// picture shows (1 to 0) at each point. On an ambient page the fade is drawn over the picture
    /// in the page's own colour, the same pixels a mask would leave over that colour, without the
    /// offscreen pass a mask costs on every frame it moves (the zoom, a scroll, a swipe).
    func dissolve(_ stops: [(shown: Double, at: CGFloat)]) -> some View {
        modifier(Dissolve(stops: stops))
    }
}

private struct Dissolve: ViewModifier {
    @Environment(\.pageFill) private var fill
    let stops: [(shown: Double, at: CGFloat)]

    func body(content: Content) -> some View {
        if let fill {
            content.overlay {
                LinearGradient(stops: stops.map { .init(color: fill.opacity(1 - $0.shown), location: $0.at) }, startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
        } else {
            content.mask {
                LinearGradient(stops: stops.map { .init(color: .black.opacity($0.shown), location: $0.at) }, startPoint: .top, endPoint: .bottom)
            }
        }
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
    /// A check that marks the moment it is tapped. One whose tap first asks something (an item
    /// bought asks its price) passes false: the tap opens the question with `press`, and `done`
    /// is left to the save.
    var marksOnTap = true
    let action: () -> Void
    // the haptic follows the hand, not isOn: a stop also turns on by itself when you arrive, and
    // from buttons that give their own; taking a mark off stays quiet
    @State private var marked = 0
    @State private var asked = 0

    var body: some View {
        Button {
            if !isOn {
                if marksOnTap { marked += 1 } else { asked += 1 }
            }
            action()
        } label: {
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
        .sensoryFeedback(.done, trigger: marked)
        .sensoryFeedback(.press, trigger: asked)
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

// MARK: - Ambient pages

// Apple Music's album page, for the app's own pages: the photograph fills the top, under the bar,
// and dissolves into one colour taken from its foot; the page is laid on that colour, its cards
// are tints of it and its type takes the colour's side. The place page, the day page and a Fuji
// viewpoint's card are built this way.

/// The photographs, paged, each laid on its own blurred copy and fading out: sharp at the top,
/// soft where the type sits, gone into the page's colour at the bottom. A shade at the very top
/// keeps the status bar and the bar's buttons readable over a white sky.
struct AmbientHero: View {
    let photos: [Photo]
    @Binding var page: Int

    var body: some View {
        TabView(selection: $page) {
            ForEach(photos.indices, id: \.self) { i in
                AmbientPhoto(photo: photos[i]).tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        // only a swipe turns the page
        .sensoryFeedback(.page, trigger: page)
        .dissolve([(1, 0), (1, 0.6), (0.8, 0.74), (0.4, 0.87), (0.12, 0.95), (0, 1)])
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.24), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 100)
                .allowsHitTesting(false)
        }
    }
}

/// One photograph: the sharp image over its pre-blurred copy, the sharp one fading out from the
/// middle down so the blur takes over (no live blur: the copy is small and blurred once).
struct AmbientPhoto: View {
    @Environment(\.accessibilityReduceTransparency) private var plain
    let photo: Photo
    @State private var veil: UIImage?

    init(photo: Photo) {
        self.photo = photo
        _veil = State(initialValue: PhotoCache.cachedVeil(photo))
    }

    var body: some View {
        Color.clear
            .overlay {
                if let veil, !plain {
                    Image(uiImage: veil)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .overlay {
                PlacePhoto(photo: photo, maxPixel: 1800)
                    .mask {
                        LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.48),
                            .init(color: .black.opacity(0.65), location: 0.62),
                            .init(color: .black.opacity(0.2), location: 0.76),
                            .init(color: .clear, location: 0.86),
                        ], startPoint: .top, endPoint: .bottom)
                    }
            }
            .clipped()
            // flattened into one texture, drawn again only when a photo or the veil arrives: the
            // zoom, the page swipe and the scroll then move a finished picture instead of masking
            // the sharp photo over its veil on every frame (the photos are sRGB, which this keeps)
            .drawingGroup()
            .task(id: photo.src) {
                guard !plain else { return }
                if let hit = PhotoCache.cachedVeil(photo) {
                    if veil !== hit { veil = hit }
                    return
                }
                let loaded = await PhotoCache.shared.veil(photo)
                withAnimation(.easeOut(duration: 0.25)) { veil = loaded }
            }
    }
}

/// Page dots in the type colour, for a pager over a photograph that may be light or dark.
struct AmbientDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(Color.primary.opacity(i == current ? 0.85 : 0.28))
                    .frame(width: i == current ? 14 : 5, height: 5)
            }
        }
        .animation(.smooth(duration: 0.3), value: current)
        .accessibilityHidden(true)
    }
}

/// Who took the photograph on screen (CC BY and BY-SA ask for it), opening its Commons page.
struct AmbientCredit: View {
    @Environment(\.openURL) private var openURL
    let photos: [Photo]
    let page: Int

    var body: some View {
        if photos.indices.contains(page), let credit = photos[page].credit {
            let photo = photos[page]
            Button {
                if let link = photo.page, let url = URL(string: link) { openURL(url) }
            } label: {
                Text(((photos.count > 1 ? "Ảnh \(page + 1)/\(photos.count)" : "Ảnh") + " · ") + (["© \(credit)", photo.license].compactMap { $0 }.joined(separator: " · ")))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.pressable(.plain))
            .disabled(photo.page == nil)
            .accessibilityLabel("Ảnh: \(credit)")
        }
    }
}

/// A round secondary button over an ambient page: a tint of the type colour, like the shuffle disc.
struct AmbientDisc: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(width: 50, height: 50)
            .background(Color.primary.opacity(0.1), in: .circle)
            .contentShape(.circle)
    }
}

extension View {
    /// Lays a scroll view whose first child is an `AmbientHero` on the photograph's colour: the
    /// page's fill, cards as lifted tints of it (opaque, so a rail can knock itself out of them),
    /// controls in the type colour, light or dark type throughout. Until the colour is read the
    /// page stays on paper. Includes `detailPage`, so the bar shows the title once the photograph
    /// has gone.
    func ambientPage(_ canvas: AmbientCanvas?, title: String, heroHeight: CGFloat) -> some View {
        modifier(AmbientPageStyle(canvas: canvas, title: title, heroHeight: heroHeight))
    }
}

private struct AmbientPageStyle: ViewModifier {
    @Environment(\.colorScheme) private var system
    let canvas: AmbientCanvas?
    let title: String
    let heroHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .progressiveEdges()
            .background { (canvas?.color ?? Palette.paper).ignoresSafeArea() }
            .environment(\.pageFill, canvas?.color ?? Palette.paper)
            .environment(\.cardSurface, canvas?.surface)
            .tint(canvas == nil ? nil : Color.primary)
            .environment(\.colorScheme, canvas?.scheme ?? system)
            .animation(.easeInOut(duration: 0.45), value: canvas)
            .detailPage(title: title, heroHeight: heroHeight, scheme: canvas?.scheme)
    }
}

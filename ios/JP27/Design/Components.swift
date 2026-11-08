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
    /// what the tap does; false when it could not be saved (`AppModel.persist`): then it fails, and
    /// a mark is not felt as done
    let action: () -> Bool
    // the haptic follows the hand, not isOn: a stop also turns on by itself when you arrive, and
    // from buttons that give their own; taking a mark off stays quiet
    @State private var marked = 0
    @State private var asked = 0
    @State private var failed = 0

    var body: some View {
        Button {
            let marking = !isOn
            if marking, !marksOnTap { asked += 1 }
            if action() {
                if marking, marksOnTap { marked += 1 }
            } else {
                failed += 1
            }
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
        .sensoryFeedback(.fail, trigger: failed)
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
///
/// The blur is not live: it is the photograph's veil (`veil`, the blurred copy `PhotoCache` derives
/// from the decode the page draws), or a blurred picture of the page's own (`backdrop`, which wins
/// when both are given), drawn under the name by `HeroBlur`. A veil already in memory is there from
/// the first frame and stays while the page shows that photograph, even should memory let it go; when
/// the photograph changes (a swipe) the next one's takes its place at once;
/// one that is not is derived from the photograph and fades in (`Motion.arrive`), and until then the
/// foot is the deeper shade alone. In Low Power Mode none is derived (one in memory still shows), and
/// with Reduce Transparency there is none.
struct DetailHero<Background: View, Foot: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var plain
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let title: String
    var subtitle: String?
    var height: CGFloat
    /// the photograph shown, whose veil is under the name
    var veil: Photo?
    /// a blurred picture of its own under the name (Fuji's terrain), in place of a veil
    var backdrop: UIImage?
    let background: Background
    /// under the name: tags, page dots, a credit
    let foot: Foot
    /// the veil that arrived: re-renders the hero, and keeps it on screen should memory let it go
    @State private var held: HeroFoot.Kept<UIImage>?
    /// the last veil shown, with its photograph: under the name still should memory let a veil it found there go
    @State private var lastShown = ShownVeil()

    init(title: String, subtitle: String? = nil, height: CGFloat = 440, veil: Photo? = nil, backdrop: UIImage? = nil,
         @ViewBuilder background: () -> Background, @ViewBuilder foot: () -> Foot) {
        self.title = title
        self.subtitle = subtitle
        self.height = height
        self.veil = veil
        self.backdrop = backdrop
        self.background = background()
        self.foot = foot()
    }

    /// The last veil shown, kept as it is drawn: a box SwiftUI does not observe, so keeping it writes nothing a view
    /// reads.
    private final class ShownVeil {
        var veil: HeroFoot.Kept<UIImage>?
    }

    /// what the task loads: the photograph's veil, and whether it may be derived
    private nonisolated struct VeilLoad: Equatable, Sendable {
        let src: String?
        let making: Bool
    }

    var body: some View {
        let under = shown
        let lowPower = model.lowPower
        let solidOnly = plain
        let making = !lowPower && !solidOnly
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
                .background { HeroBlur(backdrop: under?.image, heroHeight: height, name: under?.name ?? "picture") }
                .environment(\.colorScheme, .dark)
                .accessibilityElement(children: .contain)
            }
            // Low Power Mode in the id: turned off on an open page, the veil is derived then
            .task(id: VeilLoad(src: veil?.src, making: making)) {
                await loadVeil(lowPower: lowPower, reduceTransparency: solidOnly)
            }
    }

    /// What is under the name (`HeroFoot.under`), read from memory as the hero is drawn: a page turned to a
    /// photograph whose veil is held shows it in that same frame, with nothing a view reads written. A veil shown is
    /// kept with its photograph, so memory letting it go while the page is open leaves it there.
    private var shown: (image: UIImage, name: String)? {
        let image = HeroFoot.under(reduceTransparency: plain, backdrop: backdrop, veil: veil?.src, held: held,
                                   cached: veil.flatMap { PhotoCache.cachedVeil($0) }, kept: lastShown.veil)
        guard let image else { return nil }
        guard backdrop == nil, let veil else { return (image, "picture") }
        if lastShown.veil?.image !== image || lastShown.veil?.src != veil.src {
            lastShown.veil = HeroFoot.Kept(src: veil.src, image: image)
        }
        return (image, veil.src)
    }

    /// Only for a veil not in memory (`HeroFoot.derivesVeil`): derived from the photograph (the decode the page
    /// draws, shared with it), and faded in. One in memory is already drawn and writes nothing.
    private func loadVeil(lowPower: Bool, reduceTransparency: Bool) async {
        guard HeroFoot.derivesVeil(lowPower: lowPower, reduceTransparency: reduceTransparency, hasVeil: veil != nil,
                                   hasBackdrop: backdrop != nil, cached: veil.flatMap { PhotoCache.cachedVeil($0) } != nil),
              let veil else { return }
        let src = veil.src
        guard let made = await PhotoCache.shared.veil(veil), !Task.isCancelled else { return }
        withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) { held = HeroFoot.Kept(src: src, image: made) }
    }
}

/// A blur that rises from nothing into a soft foot, with a shade for white type: the progressive
/// edge, not a band with a hard top. The blur is the part of `backdrop` behind the foot, drawn once
/// into a small picture with the rise already in its alpha (`HeroFoot`): one plain image, with no
/// material, no mask and nothing flattened, so the zoom and the scroll move a finished picture. The
/// backdrop fills the whole hero as its photograph does, so the blur is of what is just above it; it
/// is drawn as `cgImage` holds it (upright). Without one, the shade alone, deeper.
struct HeroBlur: View {
    let backdrop: UIImage?
    /// the hero's height: the foot is its bottom part, as wide as it
    let heroHeight: CGFloat
    /// what the backdrop is, for the `hero.foot` event: a photograph's src, or "picture"
    let name: String
    @State private var drawn = FootPicture()

    init(backdrop: UIImage?, heroHeight: CGFloat, name: String = "picture") {
        self.backdrop = backdrop
        self.heroHeight = heroHeight
        self.name = name
    }

    var body: some View {
        GeometryReader { geo in
            let picture = backdrop.flatMap { drawn.picture(of: $0, named: name, foot: geo.size, heroHeight: heroHeight) }
            ZStack {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                }
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .black.opacity(HeroFoot.shade(backdrop: picture != nil)), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The foot's picture, drawn when the backdrop or a size changes and kept for every other render: held
/// by `HeroBlur` in a `@State` box that SwiftUI does not observe, so drawing it writes nothing a view
/// reads. Small and quick: the backdrop's own pixels behind the foot, never more (a 160 px veil gives at
/// most 160 px a side), one draw and one gradient, no decode and no file.
private final class FootPicture {
    private struct Key: Equatable {
        let width: Int
        let height: Int
        let hero: Int
    }

    private var backdrop: UIImage?
    private var key: Key?
    private var made: UIImage?

    func picture(of backdrop: UIImage, named name: String, foot: CGSize, heroHeight: CGFloat) -> UIImage? {
        let key = Key(width: Int(foot.width.rounded()), height: Int(foot.height.rounded()), hero: Int(heroHeight.rounded()))
        if backdrop === self.backdrop, key == self.key { return made }
        self.backdrop = backdrop
        self.key = key
        made = Self.draw(backdrop, foot: foot, heroHeight: heroHeight)
        if made != nil {
            Perf.signposter.emitEvent("hero.foot", "\(name, privacy: .public) \(key.width, privacy: .public)x\(key.height, privacy: .public)")
        }
        return made
    }

    /// The backdrop where `HeroFoot.layout` puts it, its alpha multiplied by `HeroFoot.rise`
    /// (destination-in), in sRGB. Nil, and so the shade alone, when it has no CGImage or a size is empty.
    private static func draw(_ backdrop: UIImage, foot: CGSize, heroHeight: CGFloat) -> UIImage? {
        let stops = HeroFoot.rise
        // black at each stop's strength: only its alpha counts
        let components: [CGFloat] = stops.flatMap { [0, 0, 0, CGFloat($0.shown)] }
        let locations: [CGFloat] = stops.map { CGFloat($0.at) }
        guard let image = backdrop.cgImage,
              let layout = HeroFoot.layout(backdrop: DecodePlan.Size(width: image.width, height: image.height),
                                           heroWidth: Double(foot.width), heroHeight: Double(heroHeight), foot: Double(foot.height)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: layout.canvas.width, height: layout.canvas.height, bitsPerComponent: 8,
                                      bytesPerRow: layout.canvas.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let rise = CGGradient(colorSpace: space, colorComponents: components, locations: locations, count: stops.count) else { return nil }
        context.interpolationQuality = .high
        let r = layout.draw
        context.draw(image, in: CGRect(x: r.x, y: r.y, width: r.width, height: r.height))
        context.setBlendMode(.destinationIn)
        // from the foot's top, which a bitmap context puts at y = height, to its bottom at y = 0
        context.drawLinearGradient(rise, start: CGPoint(x: 0, y: layout.canvas.height), end: .zero,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return context.makeImage().map { UIImage(cgImage: $0) }
    }
}

extension View {
    /// A scroll view whose first child is a `DetailHero`: it runs under the bar, the bar shows no
    /// edge and no title over the photograph, and the name comes into the bar (with the system's
    /// soft edge) once the photograph has scrolled away.
    /// `scheme` is the bar's once the photograph has gone: nil follows the system, a page laid on a
    /// colour of its own passes that colour's. `heroHeight` is the hero's fixed height.
    func detailPage(title: String, heroHeight: CGFloat = 440, scheme: ColorScheme? = nil) -> some View {
        modifier(DetailPage(title: title, hero: .height(heroHeight), scheme: scheme))
    }

    /// The same for a hero that is a share of the page's height (`heroFrame(fraction:)`, an album page):
    /// the same `fraction`.
    func detailPage(title: String, heroFraction: CGFloat, scheme: ColorScheme? = nil) -> some View {
        modifier(DetailPage(title: title, hero: .fraction(heroFraction), scheme: scheme))
    }

    /// A hero `fraction` of its page's height (the page less its safe-area insets), rounded to the point:
    /// `AmbientFrame.heroHeight`, the rule `detailPage(title:heroFraction:)` and a prefetch of its picture
    /// read too.
    func heroFrame(fraction: CGFloat) -> some View {
        containerRelativeFrame(.vertical) { length, _ in
            CGFloat(AmbientFrame.heroHeight(length: Double(length), fraction: Double(fraction)))
        }
    }
}

/// How tall the hero at the top of a detail page is: a fixed height, or a share of the page's.
private nonisolated enum DetailHeroExtent: Sendable {
    case height(CGFloat)
    case fraction(CGFloat)

    /// Read from the scroll view's geometry by the rule the hero was laid out with: for a share, the scroll
    /// view less its insets, as `containerRelativeFrame` measures the container (less its safe area).
    func height(in geo: ScrollGeometry) -> CGFloat {
        switch self {
        case .height(let height):
            height
        case .fraction(let fraction):
            CGFloat(AmbientFrame.heroHeight(length: Double(geo.containerSize.height - geo.contentInsets.top - geo.contentInsets.bottom),
                                            fraction: Double(fraction)))
        }
    }
}

private struct DetailPage: ViewModifier {
    let title: String
    let hero: DetailHeroExtent
    let scheme: ColorScheme?
    @State private var past = false

    func body(content: Content) -> some View {
        content
            .ignoresSafeArea(edges: .top)
            .scrollEdgeEffectHidden(!past, for: .top)
            // The bar takes the title and its edge once the photograph is nearly gone; at the top, never.
            // Read in one go from the scroll: how far the page has moved from its rest, against the hero's
            // height, which is a constant or comes from the same geometry, so it is never a height kept from
            // an earlier reading (a card measured while it was still zooming open kept the bar's title over
            // its photograph until the first scroll). Nothing is written while the page opens.
            .onScrollGeometryChange(for: Bool.self) { geo in
                let y = geo.contentOffset.y + geo.contentInsets.top
                return y > 0 && y > hero.height(in: geo) - 130
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

/// One photograph: the sharp image over its pre-blurred copy (the veil), the sharp one fading out from
/// the middle down so the blur takes over. Drawn as one picture made once (`PhotoCache.ambient`), so the
/// zoom, the page swipe and the scroll move a finished picture: no live blur, no mask, nothing flattened
/// and drawn again on the way. With Reduce Transparency there is no veil: the sharp photo fades into the
/// page under the same stops (`AmbientFrame.fade`).
struct AmbientPhoto: View {
    @Environment(\.accessibilityReduceTransparency) private var plain
    let photo: Photo

    var body: some View {
        if plain {
            PlacePhoto(photo: photo, maxPixel: PhotoCache.albumPixel)
                .mask {
                    LinearGradient(stops: AmbientFrame.fade.map { Gradient.Stop(color: .black.opacity($0.shown), location: CGFloat($0.at)) },
                                   startPoint: .top, endPoint: .bottom)
                }
        } else {
            GeometryReader { geo in
                // the picture is named by the hero's size: none until it has one
                if geo.size.width >= 1, geo.size.height >= 1 {
                    AmbientPicture(photo: photo, size: geo.size)
                }
            }
        }
    }
}

/// `AmbientPhoto` at its size. The picture from memory in the first frame, never faded. Otherwise the
/// decode the page draws, when memory has it, stands in from the first frame (the sharp photo alone,
/// filling the hero; the hero's dissolve covers its foot), and the picture fades in over it once made;
/// with neither, the photo's placeholder until the picture fades in, as a photo arrives anywhere.
/// In Low Power Mode no picture is made: one made before still shows (from memory or the disk), else the
/// decode stays as the stand-in, loaded as `PlacePhoto` loads it; once Low Power Mode is off, the picture
/// is made and fades in over it.
private struct AmbientPicture: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photo: Photo
    let size: CGSize
    /// the picture last shown: held, should memory let it go while it is on screen, and kept on screen while
    /// another size's is made
    @State private var shown: Held?
    /// the photo alone, until the picture has faded in over it
    @State private var standIn: Held?
    /// the photo whose placeholder is under it all, until its picture has faded in: then gone, so a picture
    /// with no veil (its blur failed) leaves its foot to the page's colour, as the masked photo did
    @State private var placeholder: String?

    /// An image and the photo it is of: shown only while that is the photo here.
    private struct Held {
        let src: String
        let image: UIImage
    }

    /// what the task loads: the picture of this size, and whether it may be made
    private nonisolated struct Load: Equatable, Sendable {
        let key: String?
        let making: Bool
    }

    init(photo: Photo, size: CGSize) {
        self.photo = photo
        self.size = size
        let picture = PhotoCache.cachedAmbient(photo, size: size)
        _shown = State(initialValue: picture.map { Held(src: photo.src, image: $0) })
        let decode = picture == nil ? PhotoCache.cached(photo, maxPixel: PhotoCache.albumPixel) : nil
        _standIn = State(initialValue: decode.map { Held(src: photo.src, image: $0) })
        _placeholder = State(initialValue: picture == nil ? photo.src : nil)
    }

    var body: some View {
        let picture = PhotoCache.cachedAmbient(photo, size: size) ?? shown.flatMap { $0.src == photo.src ? $0.image : nil }
        let alone = standIn.flatMap { $0.src == photo.src ? $0.image : nil }
        let making = !model.lowPower
        Color.clear
            .overlay {
                if placeholder == photo.src || (picture == nil && alone == nil) {
                    Rectangle().fill(.fill.tertiary)
                }
            }
            .overlay {
                if let alone {
                    Image(uiImage: alone)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .overlay {
                if let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .accessibilityLabel(photo.caption ?? "")
            // Low Power Mode in the id: turned off on an open page, the picture is made then
            .task(id: Load(key: PhotoCache.ambientKey(photo, size: size), making: making)) {
                await load(making: making)
            }
    }

    private func load(making: Bool) async {
        let src = photo.src
        if let hit = PhotoCache.cachedAmbient(photo, size: size) {
            // never faded: there from the first frame, or another size's swapped for it
            if shown?.image !== hit { shown = Held(src: src, image: hit) }
            if standIn != nil { standIn = nil }
            if placeholder != nil { placeholder = nil }
            return
        }
        if shown != nil, shown?.src != src {
            // another photo here than the one shown: nothing of the last one's stays, so its fade, if it is still
            // under way, finds nothing of this one's to take away when it ends
            shown = nil
        }
        if shown == nil {
            if placeholder != src { placeholder = src }
            // its own decode stands in, if memory has it
            if standIn?.src != src, let decode = PhotoCache.cached(photo, maxPixel: PhotoCache.albumPixel) {
                standIn = Held(src: src, image: decode)
            }
        }
        guard making else {
            // Low Power Mode: a picture made before, else the decode as the stand-in, loaded as a photo is
            if let saved = await PhotoCache.shared.savedAmbient(photo, size: size) {
                guard !Task.isCancelled else { return }
                arrive(saved, of: src)
                return
            }
            guard !Task.isCancelled, shown == nil, standIn?.src != src,
                  let decode = await PhotoCache.shared.image(photo, maxPixel: PhotoCache.albumPixel),
                  !Task.isCancelled else { return }
            withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) { standIn = Held(src: src, image: decode) }
            return
        }
        // cancelled with this task (the view went away, or shows another photo or size): the making stops when
        // nobody else waits for it
        guard let made = await PhotoCache.shared.ambient(photo, size: size), !Task.isCancelled else { return }
        arrive(made, of: src)
    }

    /// The picture fades in; what was under it for the same photo goes once it has, and nothing of another's.
    private func arrive(_ picture: UIImage, of src: String) {
        withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) {
            shown = Held(src: src, image: picture)
        } completion: {
            if standIn?.src == src { standIn = nil }
            if placeholder == src { placeholder = nil }
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
    /// has gone; `heroFraction` is the hero's share of the page (`heroFrame(fraction:)`).
    func ambientPage(_ canvas: AmbientCanvas?, title: String, heroFraction: CGFloat) -> some View {
        modifier(AmbientPageStyle(canvas: canvas, title: title, heroFraction: heroFraction))
    }
}

private struct AmbientPageStyle: ViewModifier {
    @Environment(\.colorScheme) private var system
    let canvas: AmbientCanvas?
    let title: String
    let heroFraction: CGFloat

    func body(content: Content) -> some View {
        content
            .progressiveEdges()
            .background { (canvas?.color ?? Palette.paper).ignoresSafeArea() }
            .environment(\.pageFill, canvas?.color ?? Palette.paper)
            .environment(\.cardSurface, canvas?.surface)
            .tint(canvas == nil ? nil : Color.primary)
            .environment(\.colorScheme, canvas?.scheme ?? system)
            .detailPage(title: title, heroFraction: heroFraction, scheme: canvas?.scheme)
    }
}

/// The colour an album page is laid on, from its first photograph, decided once and then held while the
/// page lives. At its first frame when that photograph's colour was read before (`PhotoCache.knownTone`,
/// read when the page is made); else once the page has come on screen (`decidesTone`), from the photo on
/// the phone, never the network. No body reads the colour anywhere else: one learned later (a remote
/// photo downloaded while its page is open, its veil reading the colour) waits for the page's next
/// opening, instead of turning the page from paper to colour on a later swipe or scroll. The first
/// photograph decides light or dark and the hue for the whole page; the others no longer move it. The rule
/// is TripKit's `HeldChoice`, by the photograph's src.
nonisolated struct PageTone: Equatable, Sendable {
    private var choice: HeldChoice<String, AmbientTone>

    init(_ first: Photo?) {
        choice = HeldChoice(key: first?.src, known: first.flatMap { PhotoCache.knownTone($0) })
    }

    /// the photograph it is for
    var src: String? { choice.key }

    /// Whether the colour for `first` is still to be decided.
    func wants(_ first: Photo) -> Bool {
        choice.wants(first.src)
    }

    /// The colour, once and for good: a decision for another photograph than this one's, or a second one,
    /// changes nothing; a decision of none leaves the page on paper.
    mutating func decide(_ found: AmbientTone?, for first: Photo) {
        choice.decide(found, for: first.src)
    }

    /// `first` is now the page's first photograph: another one starts again, its colour if read before, else
    /// paper until decided; the colour held for the last one is let go.
    mutating func follow(_ first: Photo) {
        choice.follow(first.src, known: PhotoCache.knownTone(first))
    }

    /// The page's colour, `dim` in dark mode; nil: paper.
    func canvas(dim: Bool) -> AmbientCanvas? {
        choice.value.map { $0.canvas(light: $0.prefersLight, dim: dim) }
    }
}

extension View {
    /// Decides an album page's colour (`PageTone`) once the page has come on screen, if its first frame
    /// did not have it. On the page, with its first photograph.
    func decidesTone(_ held: Binding<PageTone>, of first: Photo?) -> some View {
        modifier(DecideTone(held: held, first: first))
    }
}

/// `decidesTone`. It reads `transitionSettled` itself, so the page's own body does not run again when the
/// transition ends.
private struct DecideTone: ViewModifier {
    @Environment(\.transitionSettled) private var settled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var held: PageTone
    let first: Photo?

    /// a new first photograph is decided anew; the settle starts the decision
    private nonisolated struct Ask: Equatable, Sendable {
        let src: String?
        let settled: Bool
    }

    func body(content: Content) -> some View {
        content.task(id: Ask(src: first?.src, settled: settled)) {
            guard settled, let first else { return }
            // another photograph first since the page was made (a day replanned): its colour, by the same rule;
            // written only then
            if held.src != first.src { held.follow(first) }
            guard held.wants(first) else { return }
            // read before, or read now from the photo on the phone (never downloaded for); nil leaves the page
            // on paper for the rest of its life. A decision for a photo no longer first changes nothing.
            let found = await PhotoCache.shared.tone(first)
            if found == nil {
                held.decide(nil, for: first)
            } else {
                withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) { held.decide(found, for: first) }
            }
        }
    }
}

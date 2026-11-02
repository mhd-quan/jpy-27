import SwiftUI
import UIKit
import os

// How things come on screen. A sheet grows out of the control that opened it (a navigation zoom
// transition, as the system does for its own toolbar buttons) and shrinks back into it; a sheet
// opened from a sheet stacks on top instead of replacing it; scrolling content fades out under
// the bars with the progressive blur.

/// A sheet on screen and the control it grew out of.
struct Presented: Identifiable, Hashable {
    let sheet: AppSheet
    var source: String?
    var id: String { sheet.id }
}

private nonisolated struct ZoomSpaceKey: EnvironmentKey {
    static var defaultValue: Namespace.ID? { nil }
}

private nonisolated struct CloseSheetKey: EnvironmentKey {
    static var defaultValue: SheetCloser? { nil }
}

/// Closes the sheet a view is in (and anything stacked on it), from its root or from a page
/// pushed inside it, where `dismiss` would only go back.
struct SheetCloser {
    let close: @MainActor () -> Void
}

extension EnvironmentValues {
    /// The app-wide namespace that sheets and full-screen cards zoom out of.
    nonisolated var zoomSpace: Namespace.ID? {
        get { self[ZoomSpaceKey.self] }
        set { self[ZoomSpaceKey.self] = newValue }
    }

    /// Set inside a sheet; nil on a tab's own pages.
    nonisolated var closeSheet: SheetCloser? {
        get { self[CloseSheetKey.self] }
        set { self[CloseSheetKey.self] = newValue }
    }
}

/// A toolbar button a sheet grows out of. The transition source is the toolbar item itself, so
/// the whole glass button morphs into the sheet and the sheet shrinks back into it, as the
/// system's own toolbar buttons do; a source set on the button inside the item morphs only the
/// glyph and looks stiff.
struct SheetToolbarButton: ToolbarContent {
    @Environment(\.zoomSpace) private var space
    let title: String
    let symbol: String
    let source: String
    var placement: ToolbarItemPlacement = .topBarTrailing
    let action: () -> Void

    var body: some ToolbarContent {
        if let space {
            item.matchedTransitionSource(id: source, in: space)
        } else {
            item
        }
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button(title, systemImage: symbol, action: action)
        }
    }
}

/// The close button of a sheet, always the last item on the trailing side (put it last in the
/// toolbar, after a fixed spacer if the page has its own actions). Absent outside a sheet.
struct CloseButton: ToolbarContent {
    @Environment(\.closeSheet) private var closeSheet

    var body: some ToolbarContent {
        if let closeSheet {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .close) { closeSheet.close() }
            }
        }
    }
}

extension View {
    /// Marks the control a sheet grows out of: pass the same `id` to `AppModel.present(_:from:)`.
    /// Ids name the call site (and the row), so no two controls on screen share one.
    func sheetSource(_ id: String) -> some View {
        modifier(SheetSource(id: id))
    }

    /// The same, for a card: the sheet grows out of the whole rounded card and shrinks back into
    /// it, its corners following the card's.
    func sheetSource(_ id: String, cornerRadius: CGFloat) -> some View {
        modifier(SheetSource(id: id, cornerRadius: cornerRadius))
    }

    /// The other half of `sheetSource`: put on the presented view.
    @ViewBuilder
    func zoomed(from source: String?, in space: Namespace.ID?) -> some View {
        if let source, let space {
            navigationTransition(.zoom(sourceID: source, in: space))
        } else {
            self
        }
    }

    /// Presents `AppModel.sheets[level]`, and inside it the level above.
    func presentsSheets(level: Int = 0) -> some View {
        modifier(SheetLayer(level: level))
    }

    /// The progressive blur under bars: content fades and blurs into the bar instead of stopping at
    /// a hard edge. Built with the iOS 27 SDK the automatic style resolves to `.hard` (a blurred strip
    /// with a rule under it), and there is no app-wide setting: the style has to be set on each
    /// scroll view, which `screen()` and `paperList()` do. On iOS 26, `.soft` is already the default.
    func progressiveEdges() -> some View {
        scrollEdgeEffectStyle(.soft, for: .all)
    }
}

private struct SheetSource: ViewModifier {
    @Environment(\.zoomSpace) private var space
    let id: String
    var cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        if let space, let cornerRadius {
            content.matchedTransitionSource(id: id, in: space) { source in
                source.clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
            }
        } else if let space {
            content.matchedTransitionSource(id: id, in: space)
        } else {
            content
        }
    }
}

/// One level of the sheet stack. Each presented sheet carries the layer above it, so a sheet
/// opened from a sheet (log a dish from the menu scanner, scan from the place card) stacks on top
/// and closing it returns to where you were.
private struct SheetLayer: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.zoomSpace) private var space
    let level: Int

    func body(content: Content) -> some View {
        content.sheet(item: presented) { top in
            SheetHost(sheet: top.sheet)
                .modifier(SheetLayer(level: level + 1))
                .progressiveEdges()
                .environment(model)
                .environment(\.zoomSpace, space)
                .environment(\.closeSheet, SheetCloser { [model, level] in
                    if model.sheets.count > level { model.sheets.removeSubrange(level...) }
                })
                .zoomed(from: top.source, in: space)
        }
    }

    private var presented: Binding<Presented?> {
        Binding(
            get: { model.sheets.indices.contains(level) ? model.sheets[level] : nil },
            set: { value in
                // dismissed by a swipe or a close button: this level and everything on it go
                if value == nil, model.sheets.count > level {
                    model.sheets.removeSubrange(level...)
                }
            }
        )
    }
}

// MARK: - Tab bar on scroll

/// iOS 26 brought a minimized tab bar back on any scroll up; iOS 27 only does so at the very top
/// of the page (`.atScrollEdge` restoration, which only the navigation bar lets an app change).
/// The bar stays `.onScrollDown` throughout, so folding it is the system's own, scroll-driven
/// morph; each page's scroll view reports when it turns upward, and the bar is then asked to open.
///
/// Asking goes straight to UIKit: the bar is set to `.never`, which shows it whole, and handed back
/// to `.onScrollDown` a moment later. UIKit applies that change in a single frame whatever
/// animation is around it (a recording at 60 fps shows the fold over some eight frames and the
/// open in one, with a spring around the change, and with the bar's layer slowed), and no API
/// plays the fold backwards or starts the system's own expand. So the expand is drawn here: the
/// bar opens at once, and before that frame is shown its content is shrunk back onto the folded
/// capsule it came from (`sublayerTransform`, measured from what is on screen before and after),
/// then springs out to the whole bar: leading edge first, the way the fold went in. The transform
/// is on the bar's sublayers, not the bar, since UIKit sets the bar's frame and a frame set under
/// a transform is undefined. Where the capsule cannot be told from the open bar, the bar just opens.
@Observable final class TabBarScroll {
    @ObservationIgnored private weak var tabs: UITabBarController?
    /// hands the bar back to `.onScrollDown` once the expand has settled
    @ObservationIgnored private var handBack: Task<Void, Never>?
    /// the haptics of the bar's tabs, made once the bar is found
    @ObservationIgnored private var feel: TabBarFeel?

    /// The expand's spring: about twice as long as the fold, so it reads as a movement.
    private static let spring = (duration: 0.5, bounce: CGFloat(0.08))

    /// Finds the bar once the window holds it, and gives its tabs their haptics. False while the
    /// window has not laid the `TabView` out yet.
    @discardableResult func attach() -> Bool {
        if tabs != nil, feel != nil { return true }
        guard let found = Self.find() else { return false }
        tabs = found
        feel = TabBarFeel(tabs: found)
        return true
    }

    /// Opens the bar if it is folded; an open bar is left as it is.
    func open() {
        attach()
        guard let tabs, let window = tabs.view.window else { return }
        handBack?.cancel()
        let bar = tabs.tabBar
        let before = Self.platter(of: bar, in: window)
        UIView.performWithoutAnimation {
            tabs.tabBarMinimizeBehavior = .never
            tabs.view.layoutIfNeeded()
            bar.layoutIfNeeded()
        }
        // grown only from a capsule: a bar that was open already is left alone
        if let from = before?.frame, from.width < window.bounds.width / 2 {
            Self.grow(bar, from: from, in: window, tries: 3)
        }
        handBack = Task { [weak tabs] in
            try? await Task.sleep(for: .seconds(Self.spring.duration + 0.05))
            guard !Task.isCancelled else { return }
            tabs?.tabBarMinimizeBehavior = .onScrollDown
        }
    }

    /// Draws the platter shrunk back onto `from`, the capsule it was folded into (in window
    /// coordinates), and springs it out to the open bar: leading edges and middles meet. UIKit has
    /// usually laid the open bar out by now, in this same frame, so nothing of it is seen unshrunk;
    /// if it has not, the next turns of the run loop look again.
    private static func grow(_ bar: UIView, from: CGRect, in window: UIWindow, tries: Int) {
        guard let open = platter(of: bar, in: window), open.frame.width > from.width * 1.5 else {
            if tries > 1 {
                DispatchQueue.main.async { [weak bar, weak window] in
                    guard let bar, let window else { return }
                    Self.grow(bar, from: from, in: window, tries: tries - 1)
                }
            } else {
                log.debug("tab bar did not open from \(String(describing: from), privacy: .public)")
            }
            return
        }
        // the transform goes on the innermost layer that holds the whole platter and no more, and
        // on top of what UIKit has set there (additive), so the bar's own layout is left untouched
        let (to, holder) = (open.frame, open.view)
        let layer = holder.layer
        let anchor = holder.convert(CGPoint(x: holder.bounds.minX + holder.bounds.width * layer.anchorPoint.x,
                                            y: holder.bounds.minY + holder.bounds.height * layer.anchorPoint.y),
                                    to: window)
        let sx = from.width / to.width, sy = from.height / to.height
        let shrunk = CGAffineTransform(a: sx, b: 0, c: 0, d: sy,
                                       tx: from.minX - anchor.x - sx * (to.minX - anchor.x),
                                       ty: from.midY - anchor.y - sy * (to.midY - anchor.y))
        let animation = CASpringAnimation(perceptualDuration: spring.duration, bounce: spring.bounce)
        animation.keyPath = "transform"
        animation.isAdditive = true
        animation.fromValue = NSValue(caTransform3D: CATransform3DMakeAffineTransform(shrunk))
        animation.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        animation.duration = animation.settlingDuration
        layer.add(animation, forKey: "jp27.expand")
        log.debug("tab bar grows \(String(describing: from), privacy: .public) → \(String(describing: to), privacy: .public) on \(String(describing: type(of: holder)), privacy: .public)")
    }

    private static let log = Logger(subsystem: "tech.delphyra.jp27", category: "tab-bar")

    /// What of the bar's platter is drawn on screen, in window coordinates, and the innermost view
    /// holding all of it: a folded bar is its capsule, an open one the whole bar. The platter is
    /// made of the visible pieces that hold a tab's icon (its glass, the selection lens, the icons
    /// themselves), so the accessory, where UIKit draws it inside the bar, is left out; hidden,
    /// transparent and clipped-away parts are left out too. Nil when none is drawn.
    static func platter(of bar: UIView, in window: UIWindow) -> (frame: CGRect, view: UIView)? {
        var pieces: [(view: UIView, frame: CGRect)] = []
        var icons: [CGPoint] = []
        func visit(_ view: UIView, clip: CGRect, hosted: Bool) {
            guard !view.isHidden, view.alpha > 0.01, view.layer.opacity > 0.01 else { return }
            let frame = view.convert(view.bounds, to: window).intersection(clip)
            guard !frame.isNull, frame.width > 1, frame.height > 1 else { return }
            // SwiftUI content (the accessory's) is not a tab's icon, whatever draws it
            let hosted = hosted || String(describing: type(of: view)).contains("Hosting")
            if !hosted, let icon = view as? UIImageView, icon.image != nil {
                icons.append(CGPoint(x: frame.midX, y: frame.midY))
            }
            let shown = view.subviews.filter { !$0.isHidden && $0.alpha > 0.01 }
            // a view draws when it is a leaf, or has a fill, contents or layers of its own (glass)
            let draws = shown.isEmpty || view.layer.contents != nil
                || (view.backgroundColor?.cgColor.alpha ?? 0) > 0.01
                || (view.layer.sublayers?.count ?? 0) > view.subviews.count
            // the platter is a bar's height at most: taller layers are the backdrop around it
            if draws, frame.height <= 96 { pieces.append((view, frame)) }
            let inner = view.clipsToBounds || view.layer.masksToBounds ? frame : clip
            for sub in shown { visit(sub, clip: inner, hosted: hosted) }
        }
        for sub in bar.subviews { visit(sub, clip: window.bounds, hosted: false) }
        let held = icons.isEmpty ? pieces : pieces.filter { piece in icons.contains { piece.frame.contains($0) } }
        guard let first = held.first else { return nil }
        let frame = held.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        var holder = first.view
        while holder !== bar, !held.allSatisfy({ $0.view.isDescendant(of: holder) }), let up = holder.superview {
            holder = up
        }
        return (frame, holder)
    }

    /// The controller behind the root `TabView`: a child of the window's hosting controller, never
    /// one presented over it (a sheet holds no tab bar).
    private static func find() -> UITabBarController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .sorted { $0.isKeyWindow && !$1.isKeyWindow }
        var queue = windows.compactMap(\.rootViewController)
        while !queue.isEmpty {
            let next = queue.removeFirst()
            if let tabs = next as? UITabBarController { return tabs }
            queue += next.children
        }
        return nil
    }
}

/// The haptics of the tab bar, which SwiftUI cannot reach: the bar is UIKit's own. A tap on another
/// tab plays `page`'s tick as the finger lifts; a finger sliding along the bar (the Liquid Glass
/// lens follows it) plays it each time it passes onto another tab, the way a picker's wheel clicks
/// through its rows; a tap on the folded capsule, which opens the bar, plays `press`. The tab under
/// the finger is read from where it is along the platter, which UIKit shares evenly among the
/// tabs. The recognizer only listens: it neither holds a touch back from the bar nor takes one.
private final class TabBarFeel: NSObject, UIGestureRecognizerDelegate {
    private weak var tabs: UITabBarController?
    /// `page`'s tick, kept and woken as a finger lands: a slide plays it in quick succession
    private let tick: UIImpactFeedbackGenerator
    /// the platter as the finger landed (it does not move under the finger); nil off it
    private var platter: CGRect?
    private var folded = false
    /// the selected tab as the finger landed, the tab under it now, and whether it has left the first
    private var selected = 0
    private var under = 0
    private var crossed = false

    /// points past a boundary before the next tab counts, so a finger resting on one does not chatter
    private static let slack: CGFloat = 6

    init(tabs: UITabBarController) {
        self.tabs = tabs
        tick = UIImpactFeedbackGenerator(style: .light, view: tabs.tabBar)
        super.init()
        let listen = UILongPressGestureRecognizer(target: self, action: #selector(follow(_:)))
        listen.minimumPressDuration = 0
        listen.allowableMovement = .greatestFiniteMagnitude
        listen.cancelsTouchesInView = false
        listen.delaysTouchesBegan = false
        listen.delaysTouchesEnded = false
        listen.delegate = self
        tabs.tabBar.addGestureRecognizer(listen)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    @objc private func follow(_ listen: UILongPressGestureRecognizer) {
        guard let tabs, let window = tabs.view.window else { return }
        let x = listen.location(in: window).x
        switch listen.state {
        case .began:
            let point = listen.location(in: window)
            guard let found = TabBarScroll.platter(of: tabs.tabBar, in: window)?.frame,
                  found.insetBy(dx: -8, dy: -8).contains(point) else {
                platter = nil
                return
            }
            platter = found
            folded = found.width < window.bounds.width / 2
            selected = tabs.selectedIndex
            under = index(at: x, on: found)
            crossed = false
            tick.prepare()
        case .changed:
            guard let platter, !folded else { return }
            let next = index(at: x, on: platter)
            guard next != under else { return }
            let width = platter.width / CGFloat(count)
            let past = next > under ? x - (platter.minX + CGFloat(next) * width)
                                    : platter.minX + CGFloat(next + 1) * width - x
            guard past > Self.slack else { return }
            under = next
            crossed = true
            play(listen)
        case .ended:
            guard let platter else { return }
            self.platter = nil
            if folded {
                Haptic.press()
            } else if !crossed, index(at: x, on: platter) != selected {
                play(listen)
            }
        default:
            platter = nil
        }
    }

    private var count: Int {
        max(1, tabs?.tabs.count ?? 0, tabs?.tabBar.items?.count ?? 0)
    }

    private func index(at x: CGFloat, on platter: CGRect) -> Int {
        let at = Int(((x - platter.minX) / (platter.width / CGFloat(count))).rounded(.down))
        return min(max(at, 0), count - 1)
    }

    private func play(_ listen: UIGestureRecognizer) {
        guard let bar = tabs?.tabBar else { return }
        tick.impactOccurred(intensity: 0.7, at: listen.location(in: bar))
        tick.prepare()
    }
}

extension View {
    /// Reports this scroll view's upward turns to the tab bar. `screen()` and `paperList()` add it.
    func tabBarFollowsScroll() -> some View {
        modifier(TabBarFollowsScroll())
    }
}

private struct TabBarFollowsScroll: ViewModifier {
    @Environment(TabBarScroll.self) private var bar: TabBarScroll?
    /// where the scroll last turned, kept out of SwiftUI's sight: it moves every frame
    @State private var track = Track()

    final class Track {
        var turn: CGFloat = 0
        var up = false
    }

    /// points to travel before a turn counts, so a finger resting on the glass does not flicker it
    private static let slack: CGFloat = 24

    func body(content: Content) -> some View {
        // the offset within the page's real range: the rubber band past either end is not a scroll,
        // or springing back from the bottom would read as a turn up and open the bar
        content.onScrollGeometryChange(for: CGFloat.self) { g in
            let top = -g.contentInsets.top
            let bottom = max(top, g.contentSize.height + g.contentInsets.bottom - g.containerSize.height)
            return min(max(g.contentOffset.y, top), bottom) - top
        } action: { _, y in
            let t = track
            if t.up {
                if y < t.turn { t.turn = y } else if y > t.turn + Self.slack { turn(up: false, at: y) }
            } else {
                if y > t.turn { t.turn = y } else if y < t.turn - Self.slack { turn(up: true, at: y) }
            }
        }
    }

    /// A turn down needs nothing: the bar is still `.onScrollDown` and folds by itself.
    private func turn(up: Bool, at y: CGFloat) {
        track.up = up
        track.turn = y
        // on the next turn of the run loop, outside SwiftUI's update, where UIKit lays the bar out
        if up, let bar { Task { bar.open() } }
    }
}


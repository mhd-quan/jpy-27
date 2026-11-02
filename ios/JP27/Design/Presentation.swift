import SwiftUI
import UIKit

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
/// to `.onScrollDown` a moment later. UIKit animates only the fold it drives from a scroll; a change
/// of behaviour it applies at once, so the bar jumped open (first through SwiftUI state, then by
/// re-applying the behaviour back to back). Now the change and the bar's layout run inside a
/// spring, the glass capsule widening back into the bar with the tabs sliding out of it, and the
/// behaviour stays `.never` until that spring has settled, so the expand is not cut short. Only the
/// tab bar's own views are laid out inside the spring: the page under it, mid-scroll, is not.
@Observable final class TabBarScroll {
    @ObservationIgnored private weak var tabs: UITabBarController?
    /// hands the bar back to `.onScrollDown` once the expand has settled
    @ObservationIgnored private var handBack: Task<Void, Never>?

    /// Opens the bar if it is folded; an open bar is left as it is.
    func open() {
        guard let tabs = tabs ?? Self.find() else { return }
        self.tabs = tabs
        handBack?.cancel()
        UIView.animate(springDuration: 0.5, bounce: 0.18, initialSpringVelocity: 0, delay: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            tabs.tabBarMinimizeBehavior = .never
            tabs.tabBar.layoutIfNeeded()
        }
        handBack = Task { [weak tabs] in
            try? await Task.sleep(for: .milliseconds(550))
            guard !Task.isCancelled else { return }
            tabs?.tabBarMinimizeBehavior = .onScrollDown
        }
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
        // on the next turn of the run loop, outside SwiftUI's update, so UIKit animates the change
        if up, let bar { Task { bar.open() } }
    }
}


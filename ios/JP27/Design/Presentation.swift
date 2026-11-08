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

private nonisolated struct TransitionSettledKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

/// Closes the sheet a view is in (and anything stacked on it), from its root or from a page
/// pushed inside it, where `dismiss` would only go back.
nonisolated struct SheetCloser: Equatable {
    /// the stack level it closes down to: the same level closes the same way, so a new closure on
    /// each update of the stack is not a change that redraws every view reading it
    let level: Int
    let close: @MainActor () -> Void

    static func == (a: SheetCloser, b: SheetCloser) -> Bool { a.level == b.level }
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

    /// False while the page is still coming on screen (a sheet's zoom, a push, the phrase card), from
    /// its first appearance until its transition ends (`settlesTransition`); true everywhere else,
    /// the tabs' own pages included. Work that would cost a frame in the animation waits for it:
    /// `.task(id: transitionSettled) { guard transitionSettled else { return } … }`.
    nonisolated var transitionSettled: Bool {
        get { self[TransitionSettledKey.self] }
        set { self[TransitionSettledKey.self] = newValue }
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

    /// Marks a page that comes on screen by a transition (a sheet, a pushed page, the phrase card):
    /// `transitionSettled` is false inside it until the transition has ended, and the transition
    /// being measured (`Perf.current`) gets its first frame and its end here. Put it on the page
    /// itself, inside any `zoomed(from:in:)`, which stays on the presented root.
    func settlesTransition() -> some View {
        modifier(TransitionSettle())
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
                .settlesTransition()
                .modifier(SheetLayer(level: level + 1))
                // a failed write, said on the top sheet (the tabs say it when no sheet is up)
                .saveIssueAlert(level: level + 1)
                .progressiveEdges()
                .environment(model)
                .environment(\.zoomSpace, space)
                .environment(\.closeSheet, SheetCloser(level: level) { [model, level] in
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

/// `settlesTransition()`. The page's first appearance takes the transition being measured and marks
/// its first frame; the end comes from the probe (the end of the hosting controller's appearance
/// transition), or 1 s after the first appearance at the latest, so the page never stays unsettled.
private struct TransitionSettle: ViewModifier {
    @State private var settled = false
    @State private var appeared = false
    @State private var mark: TransitionMark?

    func body(content: Content) -> some View {
        content
            .environment(\.transitionSettled, settled)
            .background {
                TransitionProbe { settle(.settled) }
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .onAppear {
                guard !appeared else { return }
                appeared = true
                mark = Perf.current
                mark?.firstFrame()
                // the probe can report before SwiftUI calls this
                if settled { mark?.settled() }
            }
            // the cap; again on each appearance, a no-op once settled
            .task {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                settle(.cap)
            }
    }

    private func settle(_ how: Perf.End) {
        guard !settled else { return }
        settled = true
        mark?.settled(how)
    }
}

/// A zero-size controller inside the page: UIKit forwards the page's appearance to it, and its
/// `transitionCoordinator` is the one of the push or presentation it is part of (UIKit looks up the
/// parents). Reports once, when that transition completes, or when the page has appeared if
/// there is none.
private struct TransitionProbe: UIViewControllerRepresentable {
    let done: () -> Void

    func makeUIViewController(context: Context) -> ProbeController {
        let controller = ProbeController()
        controller.done = done
        return controller
    }

    func updateUIViewController(_ controller: ProbeController, context: Context) {
        controller.done = done
    }

    final class ProbeController: UIViewController {
        var done: (() -> Void)?
        private var waiting = false
        private var reported = false

        override func loadView() {
            let view = UIView()
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            self.view = view
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard !reported, !waiting, let coordinator = transitionCoordinator else { return }
            waiting = coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                self?.waiting = false
                self?.report()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if !waiting { report() }
        }

        private func report() {
            guard !reported else { return }
            reported = true
            done?()
        }
    }
}

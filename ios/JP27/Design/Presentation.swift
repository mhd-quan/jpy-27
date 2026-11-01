import SwiftUI

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

extension EnvironmentValues {
    /// The app-wide namespace that sheets and full-screen cards zoom out of.
    nonisolated var zoomSpace: Namespace.ID? {
        get { self[ZoomSpaceKey.self] }
        set { self[ZoomSpaceKey.self] = newValue }
    }
}

extension View {
    /// Marks the control a sheet grows out of: pass the same `id` to `AppModel.present(_:from:)`.
    /// Ids name the call site (and the row), so no two controls on screen share one.
    func sheetSource(_ id: String) -> some View {
        modifier(SheetSource(id: id))
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
    /// a hard edge. iOS 27 made the top edge `.hard` by default, a blurred strip with a rule under it.
    /// It is asked for only by the Xcode 27 compiler (Swift 6.4): an app built with the iOS 26 SDK
    /// gets `.soft` over the status bar alone on iOS 27, which reads worse than the system's strip.
    /// On iOS 26, `.soft` is already the default.
    @ViewBuilder
    func progressiveEdges() -> some View {
        #if compiler(>=6.4)
        scrollEdgeEffectStyle(.soft, for: .all)
        #else
        self
        #endif
    }
}

private struct SheetSource: ViewModifier {
    @Environment(\.zoomSpace) private var space
    let id: String

    func body(content: Content) -> some View {
        if let space {
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

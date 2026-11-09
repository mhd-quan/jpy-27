import SwiftUI

// What every Settings page is made of: the coloured tile, the row that opens a page, the page itself, a
// download's ring, and the pages the main page opens.

/// The pages one level down from the main page. The main page links to them by value, so a page stays open
/// when the row that opened it goes away under it (a "Cần xem" row once its problem is solved).
enum SettingsRoute: Hashable {
    case alternatives, pace, rehearsal
    case appearance, map
    case permissions, journal
    case offline, offlineMaps
    case checks, log, metrics, sources, developer
}

/// The coloured tile in front of a settings row, as in the system's Settings. The glyph is fitted into the
/// middle 60% of the tile and cut at its edge: drawn at a font size, a wide one (mountain.2) spilled out of
/// the tile, and its size followed the row's type size.
struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        Image(systemName: symbol)
            .resizable()
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .frame(width: 30, height: 30)
            .background(tint.gradient, in: shape)
            .clipShape(shape)
            .accessibilityHidden(true)
    }
}

/// A row that opens a page: tile, title, and the current value on the trailing side.
struct SettingsLabel: View {
    let title: String
    let symbol: String
    let tint: Color
    var value: String?

    var body: some View {
        LabeledContent {
            if let value {
                Text(value).monospacedDigit().lineLimit(1)
            }
        } label: {
            Label {
                Text(title)
            } icon: {
                SettingsIcon(symbol: symbol, tint: tint)
            }
        }
    }
}

/// A page one level down: its own form, and the close button still at the far right.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .progressiveEdges()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CloseButton() }
    }
}

/// A download's ring: filling while it runs (a square in it: tap to stop), an arrow while paused
/// (tap to go on), a tick when done. As in the App Store and Podcasts.
struct ProgressRing: View {
    enum Mode { case running, paused, done }
    let value: Double
    let mode: Mode

    var body: some View {
        ZStack {
            Circle().stroke(.fill.tertiary, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, value)))
                .stroke(mode == .done ? Color.green : .accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            switch mode {
            case .running:
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 8, height: 8)
            case .paused:
                Image(systemName: "arrow.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.accentColor)
            case .done:
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)
            }
        }
        .frame(width: 26, height: 26)
        // a bigger target than the ring, as a button needs
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
        .animation(Motion.arrive, value: value)
        .accessibilityValue(Text("\(Int(value * 100))%"))
    }
}

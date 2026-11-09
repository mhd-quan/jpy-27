import SwiftUI
import TripKit

// How the app looks: the appearance, and the map's glass and relief.

// MARK: - Appearance

/// Automatic, light or dark, picked from three small screens, as in Display & Brightness.
struct AppearanceSection: View {
    @AppStorage(Appearance.key) private var appearance: Appearance = .system

    var body: some View {
        Section {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Appearance.allCases) { a in
                    Button {
                        guard appearance != a else { return }
                        appearance = a
                        AppLog.info(.settings, "Giao diện", ["value": a.rawValue])
                    } label: {
                        AppearanceChoice(appearance: a, on: appearance == a)
                    }
                    // a row holding several buttons: without a plain style the whole row is one tap
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .sensoryFeedback(.pick, trigger: appearance)
        } footer: {
            Text("Tự động đổi sáng, tối theo iPhone, cả bản đồ.")
        }
    }
}

private struct AppearanceChoice: View {
    let appearance: Appearance
    let on: Bool

    var body: some View {
        VStack(spacing: 10) {
            thumb
                .frame(width: 60, height: 100)
                .shadow(color: .black.opacity(0.14), radius: 4, y: 2)
            Text(appearance.label)
                .font(.subheadline)
            Image(systemName: on ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(on ? AnyShapeStyle(Palette.sun) : AnyShapeStyle(.tertiary))
                .contentTransition(.symbolEffect(.replace))
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(appearance.label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var thumb: some View {
        switch appearance {
        case .light:
            AppearanceThumb().environment(\.colorScheme, .light)
        case .dark:
            AppearanceThumb().environment(\.colorScheme, .dark)
        case .system:
            ZStack {
                AppearanceThumb().environment(\.colorScheme, .light)
                AppearanceThumb().environment(\.colorScheme, .dark)
                    .mask(LowerRightHalf())
            }
        }
    }
}

/// A screen of the app in miniature: paper, the red disc, a title, two cards.
private struct AppearanceThumb: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        shape
            .fill(Palette.paper)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Circle().fill(Palette.sun).frame(width: 12, height: 12)
                    Capsule().fill(.primary.opacity(0.8)).frame(width: 32, height: 4)
                    Capsule().fill(.secondary.opacity(0.6)).frame(width: 22, height: 3)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.card).frame(height: 24)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.card).frame(height: 16)
                }
                .padding(8)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(.separator, lineWidth: 0.5) }
    }
}

private nonisolated struct LowerRightHalf: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Map

/// The glass over the Map tab and the relief under every map: real options, whether or not the frames are
/// being measured (Nhà phát triển › Đo khung hình bản đồ). As before, glass on and relief off.
struct MapOptionsSection: View {
    @AppStorage(MapPacer.glassKey) private var glass = true
    @AppStorage(MapPacer.reliefKey) private var relief = false

    var body: some View {
        Section {
            Toggle(isOn: $glass) {
                Label {
                    Text("Kính trên bản đồ")
                } icon: {
                    SettingsIcon(symbol: "rectangle.on.rectangle", tint: .teal)
                }
            }
            Toggle(isOn: $relief) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Bóng địa hình")
                        Text("Tốn pin hơn").font(.footnote).foregroundStyle(.secondary)
                    }
                } icon: {
                    SettingsIcon(symbol: "mountain.2", tint: .brown)
                }
            }
        } footer: {
            Text("Kính ở các nút của tab Bản đồ; bóng địa hình ở mọi bản đồ và cần mạng.")
        }
        .onChange(of: glass) { _, on in AppLog.info(.settings, "Kính trên bản đồ", ["value": "\(on)"]) }
        .onChange(of: relief) { _, on in AppLog.info(.settings, "Bóng địa hình", ["value": "\(on)"]) }
    }

    /// The main page's value: "Kính", "Kính · bóng núi", "Không kính", "Không kính · bóng núi"
    static func summary(glass: Bool, relief: Bool) -> String {
        (glass ? "Kính" : "Không kính") + (relief ? " · bóng núi" : "")
    }
}

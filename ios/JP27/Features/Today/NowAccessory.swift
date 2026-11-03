import SwiftUI
import TripKit

/// The row above the tab bar, beside it once the bar folds (the system moves it, as it does Music's
/// player): the ride you are on or what is next, when there is one, and Nghe và dịch at the trailing
/// end, where the thumb is, on every tab.
struct NowAccessory: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    /// the ride sheet opened, Today brought forward, or Nghe opened; a tap that changes nothing stays quiet
    @State private var opened = 0

    private var inline: Bool { placement == .inline }
    private var live: Bool { model.live.ride != nil || model.next != nil }

    var body: some View {
        HStack(spacing: 0) {
            if live {
                Button(action: tap) {
                    line
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                // the ride sheet grows out of the accessory, the way Music's player grows out of its own
                .sheetSource("now")
                Divider().frame(height: 20)
                listen(titled: false)
            } else {
                listen(titled: true)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .sensoryFeedback(.press, trigger: opened)
        .animation(.smooth, value: model.live.ride?.id)
        .animation(.smooth, value: live)
    }

    @ViewBuilder
    private var line: some View {
        if let ride = model.live.ride {
            NowRideLine(ride: ride, status: model.live.status, arrival: model.live.arrival, inline: inline)
        } else if let day = model.today, let next = model.next {
            NowNextLine(day: day, next: next, inline: inline)
        }
    }

    /// Nghe và dịch: the glyph alone beside a line, else the name too, the glyph still at the end.
    private func listen(titled: Bool) -> some View {
        Button {
            opened += 1
            model.present(.listen, from: "now.listen")
        } label: {
            HStack(spacing: 8) {
                if titled {
                    Text(inline ? "Dịch" : "Nghe và dịch").fontWeight(.semibold)
                    Spacer(minLength: 4)
                }
                Image(systemName: "translate")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.sun)
            }
            .padding(.leading, titled ? 16 : 12)
            .padding(.trailing, 14)
            .frame(maxWidth: titled ? .infinity : nil, maxHeight: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sheetSource("now.listen")
        .accessibilityLabel("Nghe và dịch")
    }

    private func tap() {
        if let ride = model.live.ride {
            opened += 1
            model.present(.ride(ride.id), from: "now")
        } else if model.tab != .today {
            opened += 1
            model.tab = .today
        }
    }
}

/// "● → Odawara · 3 ga · Fuji →"
private struct NowRideLine: View {
    let ride: Ride
    let status: RideTracker.Status?
    let arrival: Date?
    let inline: Bool

    private var next: String {
        guard let i = status?.nextStop, ride.stations.indices.contains(i) else { return ride.toName }
        return ride.stations[i].en
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: ride.color))
                .frame(width: 10, height: 10)
            if status?.alightSoon == true {
                Text("Chuẩn bị xuống · \(ride.toName)")
                    .fontWeight(.semibold)
                    .foregroundStyle(.red)
            } else {
                Text("→ \(next)").fontWeight(.semibold)
                if let left = status?.stopsLeft, left > 0 {
                    Text("· \(left) ga").foregroundStyle(.secondary).monospacedDigit()
                }
            }
            Spacer(minLength: 4)
            if let side = status?.fujiSide, side == .left || side == .right {
                Label("Fuji", systemImage: side == .left ? "arrow.left" : "arrow.right")
                    .labelStyle(NowFujiLabelStyle(leading: side == .left))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.indigo)
                    .accessibilityLabel("Fuji bên \(side == .left ? "trái" : "phải")")
            } else if !inline, let arrival {
                Text("tới \(TripTime.clock(arrival))").foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NowFujiLabelStyle: LabelStyle {
    let leading: Bool
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            if leading { configuration.icon }
            configuration.title
            if !leading { configuration.icon }
        }
    }
}

/// "🍴 Owariya · còn 18 phút"
private struct NowNextLine: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let next: Waypoint
    let inline: Bool

    private var symbol: String {
        switch next.kind {
        case .departure: "tram.fill"
        case .reservation: "checkmark.seal.fill"
        case .stop: model.store.place(next.placeID)?.kind.symbol ?? "mappin"
        }
    }

    private var title: String {
        next.kind == .departure ? next.title : (model.store.place(next.placeID)?.name ?? next.title)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(model.replan == nil ? Color.accentColor : .red)
            Text(title).fontWeight(.semibold)
            Spacer(minLength: 4)
            if let late = model.replan?.lateBy {
                Text("trễ \(late) phút").foregroundStyle(.red).monospacedDigit()
            } else {
                Countdown(target: model.date(day, minutes: next.setOff), now: model.now)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

import SwiftUI
import TripKit

/// The line above the tab bar, like Music's mini player: the ride you are on, else what is next,
/// else the days to go.
struct NowAccessory: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    /// the ride sheet opened, or Today brought forward; a tap that changes nothing stays quiet
    @State private var opened = 0

    private var inline: Bool { placement == .inline }

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 8) {
                if model.rehearsing { RehearsalBadge(inline: inline) }
                content
            }
            .font(.subheadline)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.press, trigger: opened)
        // the ride sheet grows out of the accessory, the way Music's player grows out of its own
        .sheetSource("now")
        .animation(Motion.arrive, value: model.live.ride?.id)
    }

    @ViewBuilder
    private var content: some View {
        if let ride = model.live.ride {
            NowRideLine(ride: ride, status: model.live.status, arrival: model.live.arrival, inline: inline)
        } else if let day = model.today, let next = model.next {
            NowNextLine(day: day, next: next, inline: inline)
        } else {
            switch model.phase {
            case .before(let days, let first):
                HStack(spacing: 8) {
                    Image(systemName: "airplane.departure")
                        .foregroundStyle(Palette.sun)
                    Text("Còn \(days) ngày").fontWeight(.semibold).monospacedDigit()
                    if !inline {
                        Text("· \(first.title)").foregroundStyle(.secondary)
                    }
                }
            case .during(let day):
                HStack(spacing: 8) {
                    Image(systemName: "moon.stars")
                    Text("Ngày \(day.n) · hết lịch").fontWeight(.semibold)
                }
            case .after:
                HStack(spacing: 8) {
                    Image(systemName: "book.pages")
                    Text("Nhật ký chuyến đi").fontWeight(.semibold)
                }
            }
        }
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

/// "Chạy thử ·" before the line while the trip clock is shifted (`AppModel.rehearsing`): on every
/// tab, so a rehearsal is never forgotten. Folded, the glyph alone.
private struct RehearsalBadge: View {
    let inline: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
            if !inline { Text("Chạy thử ·").fontWeight(.semibold) }
        }
        .foregroundStyle(.purple)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Đang chạy thử")
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

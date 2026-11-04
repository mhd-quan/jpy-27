import ActivityKit
import SwiftUI
import TripKit
import WidgetKit

/// On a ride: the next station, when to get ready, which window Fuji is in, and the walk after.
struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideAttributes.self) { context in
            RideLockView(attributes: context.attributes, state: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(DeepLink.ride(context.attributes.rideID).url)
        } dynamicIsland: { context in
            let a = context.attributes
            let s = context.state
            let tint = Color(hex: a.color)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.alight ? "Chuẩn bị xuống" : "Ga kế")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(s.alight ? .orange : .secondary)
                        Text(s.alight ? a.to : s.next)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Tới nơi").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        RideArrivalText(arrival: s.arrival, arrived: s.arrived)
                            .font(.headline)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 4) {
                        Image(systemName: RideLook.symbol(a.mode))
                        Text(a.line).lineLimit(1)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: min(1, max(0, s.progress)))
                            .tint(tint)
                        HStack(spacing: 8) {
                            if let fuji = s.fuji {
                                RideFujiLabel(side: fuji)
                            } else {
                                Text(s.stopsLeft == 1 ? "Còn 1 ga" : "Còn \(s.stopsLeft) ga")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if let id = a.walkToID, let name = a.walkTo, s.alight || s.arrived {
                                Link(destination: DeepLink.walk(id).url) {
                                    Label("Đi bộ tới \(name)", systemImage: "figure.walk")
                                        .lineLimit(1)
                                }
                            }
                        }
                        .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: RideLook.symbol(a.mode))
                    .foregroundStyle(tint)
                    .accessibilityLabel(a.line)
            } compactTrailing: {
                if s.alight {
                    Text("Xuống")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Chuẩn bị xuống ở \(a.to)")
                } else if let arrival = s.arrival, arrival > .now {
                    Text(timerInterval: Date.now ... arrival, countsDown: true, showsHours: false)
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .frame(width: 44)
                        .foregroundStyle(tint)
                        // a fixed sentence, not the timer: the real time in Japan, as the lock screen shows
                        .accessibilityLabel("Tới \(a.to) lúc \(TripTime.clock(arrival))")
                } else {
                    Text("\(s.stopsLeft)").monospacedDigit().foregroundStyle(tint)
                        .accessibilityLabel(s.stopsLeft == 1 ? "Còn 1 ga" : "Còn \(s.stopsLeft) ga")
                }
            } minimal: {
                RideRing(progress: s.progress, tint: s.alight ? .orange : tint)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(s.alight ? "Chuẩn bị xuống ở \(a.to)" : "\(a.line) tới \(a.to)")
                    .accessibilityValue(Text("Đã đi \(Int((min(1, max(0, s.progress)) * 100).rounded())) phần trăm"))
            }
            .widgetURL(DeepLink.ride(a.rideID).url)
            .keylineTint(tint)
        }
    }
}

// MARK: - Lock screen

private struct RideLockView: View {
    let attributes: RideAttributes
    let state: RideAttributes.ContentState
    let stale: Bool

    private var tint: Color { Color(hex: attributes.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: RideLook.symbol(attributes.mode))
                    Text(attributes.line).lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint, in: .capsule)
                Text("→ \(attributes.to)").font(.caption.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
                RideArrivalText(arrival: state.arrival, arrived: state.arrived)
                    .font(.subheadline.weight(.semibold))
            }

            if state.alight || state.arrived {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.arrived ? "Đã tới \(attributes.to)" : "Chuẩn bị xuống ở \(attributes.to)")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    if let announce = attributes.announce, !state.arrived {
                        Text(announce).font(.subheadline).environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Ga kế").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(state.next).font(.headline).lineLimit(1)
                    Text(state.nextJa).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(state.stopsLeft == 1 ? "còn 1 ga" : "còn \(state.stopsLeft) ga")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: min(1, max(0, state.progress)))
                .tint(state.alight ? .orange : tint)

            HStack(spacing: 10) {
                if let fuji = state.fuji {
                    RideFujiLabel(side: fuji)
                        .font(.caption.weight(.semibold))
                }
                if let view = state.view {
                    Text(view).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
                if let id = attributes.walkToID, let name = attributes.walkTo, state.alight || state.arrived {
                    Link(destination: DeepLink.walk(id).url) {
                        Label("Đi bộ tới \(name)", systemImage: "figure.walk")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .opacity(stale ? 0.7 : 1)
    }
}

// MARK: - Pieces

private enum RideLook {
    static func symbol(_ mode: String) -> String {
        Mode(rawValue: mode)?.symbol ?? "tram.fill"
    }
}

/// "9:22" and, while on the way, the time left.
private struct RideArrivalText: View {
    let arrival: Date?
    let arrived: Bool

    var body: some View {
        if arrived {
            Image(systemName: "checkmark.circle.fill")
        } else if let arrival {
            HStack(spacing: 4) {
                // in Japan's zone whatever the phone's is set to; the real time, also while rehearsing
                // (the app shows the trip's)
                Text(arrival, style: .time)
                    .environment(\.timeZone, TripTime.zone)
                if arrival > .now {
                    Text("·")
                    Text(timerInterval: Date.now ... arrival, countsDown: true, showsHours: false)
                        .frame(maxWidth: 48, alignment: .leading)
                }
            }
            .monospacedDigit()
        } else {
            Text("—")
        }
    }
}

private struct RideFujiLabel: View {
    let side: String

    var body: some View {
        HStack(spacing: 3) {
            if side == "left" { Image(systemName: "arrow.left") }
            Image(systemName: "mountain.2.fill")
            Text(side == "left" ? "Fuji bên trái" : "Fuji bên phải")
            if side != "left" { Image(systemName: "arrow.right") }
        }
        .foregroundStyle(.cyan)
        .accessibilityElement(children: .combine)
    }
}

private struct RideRing: View {
    let progress: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.3), lineWidth: 3)
            Circle()
                .trim(from: 0, to: min(1, max(0.02, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(2)
    }
}

#Preview("Lock screen", as: .content, using: RideAttributes(
    rideID: "r-4-romancecar-st-shinjuku-odakyu", line: "Odakyu Romancecar", color: "#2468B8", mode: "train",
    from: "Shinjuku", to: "Hakone-Yumoto", toJa: "箱根湯本", announce: "まもなく、箱根湯本です。",
    walkTo: nil, walkToID: nil)
) {
    RideLiveActivity()
} contentStates: {
    RideAttributes.ContentState(next: "Odawara", nextJa: "小田原", stopsLeft: 2, progress: 0.62, arrival: Date().addingTimeInterval(1500),
                                fuji: "right", view: "Phải: núi Tanzawa sau cánh đồng", alight: false, arrived: false)
}

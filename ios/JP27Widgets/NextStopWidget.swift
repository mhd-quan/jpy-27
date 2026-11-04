import SwiftUI
import TripKit
import WidgetKit

/// Where to go next and how long before setting off, over a photo of the place.
struct NextStopWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Shared.widgetKind, provider: NextStopProvider()) { entry in
            NextStopView(entry: entry)
        }
        .configurationDisplayName("Điểm tiếp theo")
        .description("Nơi đến tiếp theo và giờ phải rời đi.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline, .accessoryCircular])
    }
}

struct NextStopView: View {
    let entry: NextStopEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .containerBackground(for: .widget) { background }
            .widgetURL(url)
    }

    private var current: WidgetStop? {
        if case .day(_, _, _, let current, _, _, _, _) = entry.state { return current }
        return nil
    }

    private var url: URL {
        guard let current else { return DeepLink.today.url }
        if current.isDeparture { return DeepLink.today.url }
        return current.placeID.map { DeepLink.place($0).url } ?? DeepLink.today.url
    }

    // MARK: Background

    @ViewBuilder private var background: some View {
        switch family {
        case .accessoryCircular:
            AccessoryWidgetBackground()
        case .accessoryRectangular, .accessoryInline:
            Color.clear
        default:
            if renderingMode == .fullColor {
                ZStack {
                    fallbackGradient
                    if let current, !current.isDeparture, let image = HeroImage.load(current.placeID) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.35), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                }
            } else {
                Color.clear
            }
        }
    }

    private var fallbackGradient: some View {
        let hex: String = {
            if let c = current?.color { return c }
            if case .day(_, _, let color, _, _, _, _, _) = entry.state { return color }
            return "#3A3A3C"
        }()
        let base = Color(hex: hex)
        return LinearGradient(colors: [base, base.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var onPhoto: Bool { renderingMode == .fullColor }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch entry.state {
        case .before(let days, let title, let route, let dateLabel):
            BeforeTripView(days: days, title: title, route: route, dateLabel: dateLabel, family: family, onPhoto: onPhoto)
        case .after:
            QuietView(text: "Chuyến đi đã xong", symbol: "checkmark.circle", family: family, onPhoto: onPhoto)
        case .unavailable:
            QuietView(text: "Mở JP27 một lần", symbol: "arrow.clockwise", family: family, onPhoto: onPhoto)
        case .day(let n, let title, _, let current, let after, let late, let advice, let stay):
            if let current {
                DayStopView(date: entry.date, n: n, dayTitle: title, stop: current, after: after, late: late, advice: advice, family: family, onPhoto: onPhoto)
            } else {
                QuietView(text: stay.map { "Về \($0)" } ?? "Hết lịch hôm nay", symbol: "bed.double.fill", family: family, onPhoto: onPhoto)
            }
        }
    }
}

// MARK: - During a day

private struct DayStopView: View {
    let date: Date
    let n: Int
    let dayTitle: String
    let stop: WidgetStop
    let after: [WidgetStop]
    let late: Int?
    let advice: String?
    let family: WidgetFamily
    let onPhoto: Bool

    /// past the time to set off: on the way
    private var leaving: Bool { date >= stop.setOff }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(stop.title) · \(leaving ? stop.beginLabel : stop.setOffLabel)")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemSmall:
            small
        case .systemLarge:
            large
        default:
            medium
        }
    }

    // MARK: Pieces

    private var kindLabel: String {
        switch stop.kind {
        case "departure": "Chuyến tiếp theo"
        case "reservation": "Đã đặt chỗ"
        default: "Tiếp theo"
        }
    }

    private var lateBadge: some View {
        Group {
            if let late, late > 0 {
                Text("Trễ \(late)′")
                    .font(.caption2.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: .capsule)
                    .foregroundStyle(.white)
                    .accessibilityLabel("Trễ \(late) phút")
            }
        }
    }

    private var headline: some View {
        Text(stop.isDeparture ? "\(stop.title) \(stop.beginLabel)" : stop.title)
            .font(.headline)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .widgetAccentable()
    }

    /// "Rời đi 12:32 · 14:05" with a live countdown, or the arrival time once on the way.
    @ViewBuilder private var timing: some View {
        if leaving {
            Text(stop.isDeparture ? "Tàu chạy \(stop.beginLabel)" : "Đang đi · tới \(stop.beginLabel)")
        } else {
            HStack(spacing: 4) {
                Text("Rời đi \(stop.setOffLabel)")
                Text("·")
                countdown
            }
        }
    }

    @ViewBuilder private var countdown: some View {
        if stop.setOff > date {
            Text(timerInterval: date ... stop.setOff, countsDown: true)
                .monospacedDigit()
        } else {
            Text("đi ngay")
        }
    }

    private var symbol: some View {
        Image(systemName: stop.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(onPhoto ? .white : .primary)
            .frame(width: 22, height: 22)
            .background(onPhoto ? AnyShapeStyle(Color(hex: stop.color ?? "#000000").opacity(stop.color == nil ? 0.35 : 1)) : AnyShapeStyle(.fill.tertiary), in: .circle)
    }

    // MARK: Families

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                symbol
                Spacer()
                lateBadge
            }
            Spacer(minLength: 0)
            Text(kindLabel).font(.caption2.weight(.semibold)).opacity(0.85)
            headline
            timing
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(onPhoto ? .white : .primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                symbol
                Text("Ngày \(n) · \(kindLabel)").font(.caption.weight(.semibold)).opacity(0.9)
                Spacer()
                lateBadge
            }
            Spacer(minLength: 0)
            headline.font(.title3.weight(.semibold))
            if let subtitle = stop.subtitle {
                Text(subtitle).font(.subheadline).lineLimit(1).opacity(0.9)
            }
            timing.font(.subheadline.weight(.medium)).lineLimit(1)
            if let advice {
                Text(advice).font(.caption.weight(.medium)).lineLimit(1).foregroundStyle(onPhoto ? .yellow : .orange)
            } else if let next = after.first {
                Text("Sau đó: \(next.title) \(next.beginLabel)").font(.caption).lineLimit(1).opacity(0.85)
            }
        }
        .foregroundStyle(onPhoto ? .white : .primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            medium
                .frame(maxHeight: .infinity)
            if !after.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(after, id: \.index) { s in
                        HStack(spacing: 8) {
                            Text(s.beginLabel)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .frame(width: 40, alignment: .trailing)
                            Image(systemName: s.symbol)
                                .font(.caption2)
                                .frame(width: 16)
                            Text(s.isDeparture ? "\(s.title) \(s.subtitle ?? "")" : s.title)
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                }
                .foregroundStyle(onPhoto ? .white : .primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(onPhoto ? AnyShapeStyle(.black.opacity(0.35)) : AnyShapeStyle(.fill.quaternary), in: .rect(cornerRadius: 14, style: .continuous))
                .padding(.top, 10)
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: stop.symbol)
                Text(kindLabel)
                if let late, late > 0 { Text("· trễ \(late)′").accessibilityLabel("trễ \(late) phút") }
            }
            .font(.caption2.weight(.semibold))
            Text(stop.isDeparture ? "\(stop.title) \(stop.beginLabel)" : stop.title)
                .font(.headline)
                .lineLimit(1)
                .widgetAccentable()
            timing.font(.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var circular: some View {
        if stop.setOff > date, !leaving {
            ProgressView(timerInterval: date ... stop.setOff, countsDown: true) {
                Text("Rời đi")
            } currentValueLabel: {
                Image(systemName: stop.symbol)
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else {
            VStack(spacing: 0) {
                Image(systemName: stop.symbol).font(.title3)
                Text(stop.beginLabel).font(.caption2.weight(.semibold)).monospacedDigit()
            }
            .widgetAccentable()
        }
    }
}

// MARK: - Before and after

private struct BeforeTripView: View {
    let days: Int
    let title: String
    let route: String
    let dateLabel: String
    let family: WidgetFamily
    let onPhoto: Bool

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("JP27 · còn \(days) ngày")
        case .accessoryCircular:
            VStack(spacing: 0) {
                Text("\(days)").font(.title2.weight(.bold)).monospacedDigit().minimumScaleFactor(0.6)
                Text("ngày").font(.caption2)
            }
            .widgetAccentable()
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("JP27").font(.caption2.weight(.semibold))
                Text("Còn \(days) ngày").font(.headline).monospacedDigit().widgetAccentable()
                Text(dateLabel).font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Text("JP27").font(.caption.weight(.bold))
                Spacer(minLength: 0)
                Text("Còn \(days) ngày")
                    .font(family == .systemSmall ? .title2.weight(.bold) : .largeTitle.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                Text("\(dateLabel) · \(title)").font(.subheadline).lineLimit(2)
                if family != .systemSmall {
                    Text(route).font(.caption).lineLimit(1).opacity(0.85)
                }
            }
            .foregroundStyle(onPhoto ? .white : .primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

private struct QuietView: View {
    let text: String
    let symbol: String
    let family: WidgetFamily
    let onPhoto: Bool

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(text)
        case .accessoryCircular:
            Image(systemName: symbol).font(.title2).widgetAccentable()
        case .accessoryRectangular:
            Label(text, systemImage: symbol).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
        default:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol).font(.title2)
                Spacer(minLength: 0)
                Text(text).font(.headline).lineLimit(3).widgetAccentable()
            }
            .foregroundStyle(onPhoto ? .white : .primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

#Preview(as: .systemMedium) {
    NextStopWidget()
} timeline: {
    WidgetPlan.sample
}

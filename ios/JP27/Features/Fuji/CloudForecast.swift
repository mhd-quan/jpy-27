import SwiftUI
import TripKit
import WeatherKit

/// Hour by hour, how likely Fuji's summit is clear from a viewpoint: cloud at the summit and at the
/// viewpoint (WeatherKit), the best hour marked. The last forecast stays readable offline.
struct CloudForecast: View {
    var title: String? = nil
    let key: String
    let coordinate: Coordinate

    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @State private var summit: [ForecastService.Hour] = []
    @State private var here: [ForecastService.Hour] = []
    @State private var loading = true

    private struct Column: Identifiable {
        var id: Date { date }
        let date: Date
        let chance: Double
        let cloud: Double
    }

    private var columns: [Column] {
        let from = model.now.addingTimeInterval(-30 * 60)
        return summit.filter { $0.date >= from }.prefix(18).map { s in
            let h = here.min { abs($0.date.timeIntervalSince(s.date)) < abs($1.date.timeIntervalSince(s.date)) }
            let match = h.flatMap { abs($0.date.timeIntervalSince(s.date)) <= 1800 ? $0 : nil }
            return Column(date: s.date, chance: ForecastService.clearChance(summit: s, here: match) ?? 0, cloud: s.cloud)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label(title, systemImage: "mountain.2.fill").font(.headline)
            }
            let cols = columns
            if cols.isEmpty {
                Text(loading ? "Đang tải dự báo…" : (model.network.online ? "Chưa có dự báo" : "Chưa có dự báo — cần mạng một lần"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                let best = cols.max { $0.chance < $1.chance }
                if let best, best.chance >= 0.35 {
                    Text("Rõ nhất lúc \(TripTime.clock(best.date)) · \(Int((best.chance * 100).rounded()))%")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text("Đỉnh nhiều mây trong 18 giờ tới")
                        .font(.subheadline.weight(.semibold))
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(cols) { c in
                            CloudColumn(date: c.date, chance: c.chance, cloud: c.cloud, isBest: c.id == best?.id && c.chance >= 0.35)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
            footer
        }
        .task(id: key) { await load() }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if let fetched = model.forecasts.series["summit"]?.fetched {
                Text("Cập nhật \(TripTime.clock(fetched))")
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if model.forecasts.source("summit") == .openMeteo {
                SwiftUI.Link("Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
            } else if let a = model.forecasts.attribution {
                AsyncImage(url: scheme == .dark ? a.combinedMarkDarkURL : a.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text("Apple Weather")
                }
                .frame(height: 12)
                SwiftUI.Link("Nguồn", destination: a.legalPageURL)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func load() async {
        loading = true
        let online = model.network.online
        let forecasts = model.forecasts
        summit = await forecasts.hours("summit", at: FujiSight.summit, online: online)
        here = await forecasts.hours(key, at: coordinate, online: online)
        loading = false
    }
}

/// One hour: a bar for the chance the summit shows, the summit's cloud underneath.
private struct CloudColumn: View {
    let date: Date
    let chance: Double
    let cloud: Double
    let isBest: Bool

    private var tint: Color {
        chance >= 0.6 ? .green : chance >= 0.35 ? .yellow : .gray
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Capsule().fill(.fill.tertiary)
                Capsule().fill(tint.gradient)
                    .frame(height: max(4, 64 * chance))
            }
            .frame(width: 14, height: 64)
            Text("\(Int((cloud * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Text("\(TripTime.calendar.component(.hour, from: date))")
                .font(.caption.weight(isBest ? .bold : .regular))
                .monospacedDigit()
        }
        .frame(width: 34)
        .padding(.vertical, 6)
        .background(isBest ? AnyShapeStyle(Color.accentColor.opacity(0.14)) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(TripTime.calendar.component(.hour, from: date)) giờ, khả năng thấy đỉnh \(Int((chance * 100).rounded())) phần trăm, mây \(Int((cloud * 100).rounded())) phần trăm")
    }
}

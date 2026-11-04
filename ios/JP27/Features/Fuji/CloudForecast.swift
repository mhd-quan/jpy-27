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
        // forecast hours are real instants: the real clock, also while rehearsing (still read
        // through `model.now`, which redraws this on the minute)
        let from = model.now.addingTimeInterval(-model.clockOffset - 30 * 60)
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
                    Text("Rõ nhất lúc \(TripTime.clock(best.date)) · \(clearWords(best.chance))")
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
                    .buttonStyle(.pressable(.borderless))
            } else if let a = model.forecasts.attribution {
                AsyncImage(url: scheme == .dark ? a.combinedMarkDarkURL : a.combinedMarkLightURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Text("Apple Weather")
                }
                .frame(height: 12)
                SwiftUI.Link("Nguồn", destination: a.legalPageURL)
                    .buttonStyle(.pressable(.borderless))
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
        .accessibilityLabel("\(TripTime.calendar.component(.hour, from: date)) giờ, \(clearWords(chance)), mây \(Int((cloud * 100).rounded())) phần trăm")
    }
}

/// The clear-view index in words. It multiplies the forecast's clear sky at the summit, clear sky
/// where you stand and visibility over 40 km: a ranking of the hours, not a probability, so it is
/// never shown as a percentage. The cloud figure under each bar is the forecast's own.
private func clearWords(_ index: Double) -> String {
    index >= 0.6 ? "nhiều khả năng thấy" : index >= 0.35 ? "có thể thấy" : "khó thấy"
}

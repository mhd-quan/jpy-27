import SwiftUI
import TripKit
import WeatherKit

// Hỗ trợ: what MetricKit measured on this phone, and the sources and credits.

/// What MetricKit reported about the app on this phone, a day at a time, as kept in
/// `Caches/metrics` (`MetricsInbox`): hitches, launch time, and each measured transition from the tap
/// to its end (`Perf`). The payloads' own JSON can be shared, for a closer look on a computer.
struct MetricsSection: View {
    @State private var stored: (digests: [MetricsDigest], payloads: [URL])?

    var body: some View {
        Group {
            if let stored {
                if stored.digests.isEmpty {
                    Section {
                        Text("Chưa có số đo. iOS gửi số đo của ngày trước mỗi ngày một lần, sau khi app được dùng.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(stored.digests, id: \.end) { day in
                            LabeledContent {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("cuộn \(Self.ratio(day.scrollHitches)) · mọi lúc \(Self.ratio(day.hitches))")
                                    Text("mở app \(Self.ms(PerfStats.median(day.launch)))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .monospacedDigit()
                            } label: {
                                Text(Self.day(day.begin))
                            }
                        }
                    } header: {
                        Text("Theo ngày")
                    } footer: {
                        Text("Giật: ms mỗi giây chuyển động; mở app: trung vị tới khung đầu tiên.")
                    }
                    Section {
                        ForEach(Self.transitions(stored.digests), id: \.name) { t in
                            LabeledContent {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(Self.ms(PerfStats.median(t.buckets)))
                                    Text("\(t.count) lần · giật \(Self.ratio(t.hitches))")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .monospacedDigit()
                            } label: {
                                Text(t.name).font(.subheadline.monospaced())
                            }
                        }
                    } header: {
                        Text("Chuyển cảnh")
                    }
                }
                if !stored.payloads.isEmpty {
                    Section {
                        // what MetricKit sent, as it sent it, for the days kept
                        ShareLink(items: stored.payloads) {
                            Label("Chia sẻ JSON (\(stored.payloads.count) ngày)", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            } else {
                Section {
                    ProgressView()
                }
            }
        }
        .task { stored = await MetricsInbox.stored() }
    }

    /// one transition name over every day kept
    private struct Measured {
        let name: String
        let count: Int
        let buckets: [PerfStats.Bucket]
        let hitches: MetricsDigest.Ratio?
    }

    /// The days merged per name, names in order: the buckets put together (`PerfStats.median` merges
    /// equal ones), the hitch ratio averaged by count.
    private static func transitions(_ digests: [MetricsDigest]) -> [Measured] {
        let byName = Dictionary(grouping: digests.flatMap(\.signposts), by: \.name)
        return byName.keys.sorted().map { name -> Measured in
            let days = byName[name] ?? []
            let rated = days.filter { $0.hitches != nil && $0.count > 0 }
            let weight = rated.reduce(0) { $0 + $1.count }
            let hitches = rated.first.map { first in
                MetricsDigest.Ratio(
                    value: rated.reduce(0.0) { $0 + ($1.hitches?.value ?? 0) * Double($1.count) } / Double(max(weight, 1)),
                    unit: first.hitches?.unit ?? ""
                )
            }
            return Measured(name: name, count: days.reduce(0) { $0 + $1.count }, buckets: days.flatMap(\.buckets), hitches: hitches)
        }
    }

    /// "2,1 ms/s", or "—": MetricKit gives hitch ratios in ms per s, and its unit's symbol is English, so it is not shown
    private static func ratio(_ r: MetricsDigest.Ratio?) -> String {
        guard let r else { return "—" }
        return "\(Fmt.decimal(r.value, digits: 1)) ms/s"
    }

    /// "640 ms", or "—"
    private static func ms(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Fmt.decimal(value, digits: 0)) ms"
    }

    /// "7/11"
    private static func day(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month], from: date)
        return "\(c.day ?? 0)/\(c.month ?? 0)"
    }
}

// MARK: - Sources

struct SourcesSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            LabeledContent("Nghiên cứu", value: model.store.trip.meta.researched)
            source("Bản đồ: OpenFreeMap", "https://openfreemap.org")
            source("© OpenStreetMap", "https://www.openstreetmap.org/copyright")
            source("Ảnh: Wikimedia Commons", "https://commons.wikimedia.org")
            source("Quán ăn: Tabelog", "https://tabelog.com/en/")
            Link(destination: model.forecasts.attribution?.legalPageURL ?? URL(string: "https://developer.apple.com/weatherkit/data-source-attribution/")!) {
                Label("Dự báo:  Weather", systemImage: "cloud.sun")
            }
            // the fallback when the build has no WeatherKit entitlement; CC BY 4.0 asks for the credit
            source("Dự báo: Open-Meteo", "https://open-meteo.com/")
        }
    }

    private func source(_ title: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: "arrow.up.right.square")
        }
    }
}

import SwiftUI
import TripKit

/// Fuji: the odds in October, every viewpoint of the plan with its sight line computed on terrain,
/// the horizon you will actually see, the Kawaguchiko option, and the clouds right now.
struct FujiView: View {
    @Environment(AppModel.self) private var model

    private var fuji: FujiGuide { model.guide.fuji }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.stack) {
                PlanFujiSummit()
                CloudForecast(title: "Đỉnh Fuji", key: "summit", coordinate: FujiSight.summit)
                Button {
                    model.present(.fujiFinder, from: "fuji.finder")
                } label: {
                    Label("Tìm Fuji bằng camera", systemImage: "camera.viewfinder")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .sheetSource("fuji.finder")
                PlanFujiClimate(climate: fuji.research?["climate"])
                ForEach(groups) { group in
                    PlanFujiGroup(title: group.title, spots: group.spots)
                }
                if let k = fuji.kawaguchiko { PlanKawaguchiko(info: k) }
                if let note = fuji.research?["notes"]?.string {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
        .screen()
        .navigationTitle("Fuji")
    }

    private struct SpotGroup: Identifiable {
        let id: String
        let title: String
        let spots: [FujiGuide.Spot]
    }

    private var groups: [SpotGroup] {
        let titles = ["4": "Ngày 4 · Hakone", "5": "Ngày 5 · Tōkaidō", "kawaguchiko": "Kawaguchiko, thay ngày 3"]
        return ["4", "5", "kawaguchiko"].compactMap { key in
            let spots = fuji.spots.filter { planFujiDayKey($0) == key }
            return spots.isEmpty ? nil : SpotGroup(id: key, title: titles[key] ?? key, spots: spots)
        }
    }
}

private struct PlanFujiSummit: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let onshi = model.guide.fuji.spots.first { $0.id == "onshi-hakone-park" }
        HStack(alignment: .top, spacing: 20) {
            Stat(value: "\(Fmt.grouped(Int(model.guide.fuji.summit.h))) m", label: "đỉnh")
            if let onshi {
                Stat(value: Fmt.km(onshi.km), label: "từ Onshi Park")
                Stat(value: Geo.compass(onshi.bearing), label: "hướng nhìn")
            }
            if let p = model.position {
                Stat(value: Fmt.km(FujiSight.from(p).km), label: "từ chỗ bạn")
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.top, 8)
    }
}

private struct PlanFujiClimate: View {
    let climate: JSONValue?

    var body: some View {
        if let climate {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Cơ hội thấy núi")
                Card {
                    PlanRows(items: climate["octoberVisibility"]?.array ?? []) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row["stat"]?.string ?? "").font(.subheadline.weight(.semibold))
                            Text([row["place"]?.string, row["years"]?.string].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let t = climate["timeOfDay"]?.string { Divider(); PlanParagraph(title: "Giờ nào", text: t) }
                    if let t = climate["snowcap"]?.string { Divider(); PlanParagraph(title: "Chóp tuyết", text: t) }
                    if let t = climate["sunrise"]?.string { Divider(); PlanParagraph(title: "Mặt trời", text: t) }
                }
            }
        }
    }
}

private struct PlanFujiGroup: View {
    let title: String
    let spots: [FujiGuide.Spot]

    var body: some View {
        let main = spots.filter { $0.role != "popular" }
        let popular = spots.filter { $0.role == "popular" }
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title)
            ForEach(main) { spot in PlanFujiSpotCard(spot: spot) }
            if !popular.isEmpty {
                Text("Chỗ hay được đăng").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                Card {
                    PlanRows(items: popular) { spot in PlanFujiPopularRow(spot: spot) }
                }
            }
        }
    }
}

/// A viewpoint of the plan: name, what terrain says, research notes, the horizon.
private struct PlanFujiSpotCard: View {
    @Environment(AppModel.self) private var model
    let spot: FujiGuide.Spot

    var body: some View {
        let note = research
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(name).font(.headline)
                Spacer()
                if spot.role == "detour" { Tag(text: "Rẽ thêm") }
                if spot.role == "alt" { Tag(text: "Phương án") }
            }
            PlanFujiSightLine(spot: spot)
            if let pano = model.guide.fuji.panoramas[spot.id] {
                PlanPanorama(pano: pano)
                    .frame(height: 90)
                    .accessibilityLabel("Đường chân trời về phía Fuji")
            }
            if let t = note?["fujiNote"]?.string { Text(t).font(.subheadline) }
            if let t = note?["photoTips"]?.string { PlanInfoRow(symbol: "camera", text: t, label: "Chụp") }
            if let t = note?["bestTime"]?.string { PlanInfoRow(symbol: "clock", text: t, label: "Lúc nên tới") }
            if let t = note?["crowd"]?.string { PlanInfoRow(symbol: "person.3", text: t, label: "Đông hay vắng") }
            if model.store.place(spot.id) != nil {
                NavigationLink(value: Route.place(spot.id)) {
                    Text("Chi tiết").font(.subheadline.weight(.semibold)).frame(minHeight: 32)
                }
            }
        }
    }

    private var name: String {
        spot.name ?? model.store.place(spot.id)?.name ?? research?["name"]?.string ?? spot.id
    }

    private var research: JSONValue? {
        model.guide.fuji.research?["spots"]?.array.first { $0["id"]?.string == spot.id }
    }
}

private struct PlanFujiPopularRow: View {
    @Environment(AppModel.self) private var model
    let spot: FujiGuide.Spot

    var body: some View {
        let place = model.store.place(spot.id)
        let row = HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.name ?? place?.name ?? spot.id).font(.subheadline.weight(.semibold))
                Text("\(Fmt.km(spot.km)) · \(Geo.compass(spot.bearing))" + (spot.visible ? "" : " · bị che"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: spot.visible ? "eye" : "eye.slash").foregroundStyle(spot.visible ? Color.indigo : Color.secondary)
        }
        .contentShape(.rect)
        if place != nil {
            NavigationLink(value: Route.place(spot.id)) { row }.buttonStyle(.plain)
        } else {
            row
        }
    }
}

/// The horizon around Fuji's bearing from a viewpoint, height exaggerated four times.
private struct PlanPanorama: View {
    let pano: FujiGuide.Panorama

    var body: some View {
        Canvas { ctx, size in
            let angles = pano.angles
            guard angles.count > 1, let lo = angles.min(), let hi = angles.max() else { return }
            let span = Double(angles.count - 1) * pano.step
            let base = lo - 0.2
            let range = max(0.5, (hi - base) * 1.15)
            func x(_ az: Double) -> CGFloat { CGFloat((az - pano.from) / span) * size.width }
            func y(_ a: Double) -> CGFloat { size.height - CGFloat((a - base) / range) * size.height }
            var ridge = Path()
            ridge.move(to: CGPoint(x: 0, y: size.height))
            for (i, a) in angles.enumerated() {
                ridge.addLine(to: CGPoint(x: x(pano.from + Double(i) * pano.step), y: y(a)))
            }
            ridge.addLine(to: CGPoint(x: size.width, y: size.height))
            ridge.closeSubpath()
            ctx.fill(ridge, with: .linearGradient(Gradient(colors: [.indigo.opacity(0.55), .indigo.opacity(0.12)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            let sx = x(pano.summitAz)
            var mark = Path()
            mark.move(to: CGPoint(x: sx, y: 0))
            mark.addLine(to: CGPoint(x: sx, y: size.height))
            ctx.stroke(mark, with: .color(.secondary), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            ctx.draw(Text("Fuji").font(.caption2.weight(.semibold)).foregroundStyle(.secondary), at: CGPoint(x: sx, y: 8), anchor: .bottom)
        }
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }
}

/// The Kawaguchiko day: trains and buses there and back, local transport, the timed plan, October notes.
private struct PlanKawaguchiko: View {
    let info: JSONValue

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Đi Kawaguchiko")
            transport(info["trains"]?.array ?? [], symbol: "tram.fill")
            transport(info["buses"]?.array ?? [], symbol: "bus.fill")
            let local = info["local"]?.array ?? []
            if !local.isEmpty {
                Card {
                    PlanRows(items: local) { l in
                        PlanParagraph(title: l["name"]?.string ?? "", text: l["what"]?.string ?? "")
                    }
                }
            }
            let schedule = info["schedule"]?.array ?? []
            if !schedule.isEmpty {
                Text("Lịch mẫu").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                Card {
                    PlanRows(items: schedule) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(s["at"]?.string ?? "").font(.subheadline.weight(.semibold)).monospacedDigit().frame(width: 48, alignment: .leading)
                            Text(s["what"]?.string ?? "").font(.subheadline)
                        }
                    }
                }
            }
            if let october = info["october"]?.planText {
                Card { PlanParagraph(title: "Cuối tháng 10", text: october) }
            }
        }
    }

    @ViewBuilder
    private func transport(_ list: [JSONValue], symbol: String) -> some View {
        if !list.isEmpty {
            Card {
                PlanRows(items: list) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(t["name"]?.string ?? "", systemImage: symbol).font(.subheadline.weight(.semibold))
                        Text([t["from"]?.string, t["to"]?.string].compactMap { $0 }.joined(separator: " → "))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            let departs = (t["depart"]?.array ?? []).compactMap(\.string)
                            if !departs.isEmpty { Tag(text: departs.joined(separator: ", "), symbol: "clock") }
                            if let m = t["min"]?.planText { Tag(text: "\(m) phút") }
                            if let y = t["yen"]?.number { Tag(text: Fmt.yen(Int(y))) }
                        }
                        if let b = t["booking"]?.string { Text(b).font(.caption) }
                    }
                }
            }
        }
    }
}

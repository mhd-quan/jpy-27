import MapKit
import SwiftUI
import TripKit

// Fuji, in the order a traveller asks: where can I see it from (the 3D map and the viewpoints of
// each day), will it be out (clouds now, the odds in October), and the Kawaguchiko option. A
// viewpoint opens its own page: the line of sight on the terrain, what shows of the mountain,
// the horizon, when to go, the clouds there.

struct FujiView: View {
    @Environment(AppModel.self) private var model
    @State private var area: FujiArea = .all
    @State private var exploring = false

    private var fuji: FujiGuide { model.guide.fuji }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FujiHero(area: area, spots: fuji.spots, summit: fuji.summit.coordinate) { exploring = true }
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    VStack(alignment: .leading, spacing: 10) {
                        FujiAreaChips(area: $area)
                        FujiLegend()
                            .padding(.horizontal, Metrics.gutter)
                    }
                    VStack(alignment: .leading, spacing: Metrics.stack) {
                        ForEach(area == .all ? FujiArea.days : [area]) { a in
                            FujiSpotSection(area: a)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Mây lúc này")
                            CloudForecast(title: "Đỉnh Fuji", key: "summit", coordinate: FujiSight.summit)
                        }
                        PlanFujiClimate(climate: fuji.research?["climate"])
                        if fuji.kawaguchiko != nil, area == .all || area == .kawaguchiko {
                            FujiKawaguchikoLink()
                        }
                        if let note = fuji.research?["notes"]?.string {
                            Text(note).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, Metrics.gutter)
                }
                .padding(.top, 16)
            }
            .padding(.bottom, 32)
        }
        .screen()
        .detailPage(title: "Fuji", heroHeight: FujiHero.height)
        .navigationDestination(isPresented: $exploring) {
            FujiExplorer(area: area, spots: fuji.spots, summit: fuji.summit.coordinate)
        }
        .navigationDestination(for: FujiPage.self) { page in
            switch page {
            case .spot(let id): FujiSpotPage(id: id)
            case .kawaguchiko: FujiKawaguchikoPage()
            }
        }
    }
}

// MARK: - Hero

/// The top of the page: the terrain under the bar, the chosen day's viewpoints and their lines of
/// sight, the camera flying to each day as it is chosen; the name, the height and the two ways in
/// (the map to explore, the camera to find the real mountain) at its foot.
private struct FujiHero: View {
    static let height: CGFloat = 480
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let area: FujiArea
    let spots: [FujiGuide.Spot]
    let summit: Coordinate
    let explore: () -> Void
    @State private var position: MapCameraPosition

    init(area: FujiArea, spots: [FujiGuide.Spot], summit: Coordinate, explore: @escaping () -> Void) {
        self.area = area
        self.spots = spots
        self.summit = summit
        self.explore = explore
        _position = State(initialValue: .camera(FujiCamera.area(area, spots: spots.filter { area.contains($0) }, summit: summit)))
    }

    var body: some View {
        let shown = spots.filter { area.contains($0) }
        DetailHero(title: "Fuji", subtitle: "富士山", height: Self.height) {
            ZStack {
                if model.network.online {
                    FujiTerrainMap(spots: shown, position: $position, selection: .constant(nil))
                } else {
                    FujiCompassPlot.backdrop
                    FujiCompassPlot(spots: shown, selection: .constant(nil))
                        .padding(.top, 96)
                        .padding(.bottom, 180)
                }
            }
            .allowsHitTesting(false)
            // a tap on the picture opens the map, as the button does
            .overlay {
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture(perform: explore)
                    .accessibilityHidden(true)
            }
        } foot: {
            VStack(alignment: .leading, spacing: 12) {
                Text(facts(shown))
                    .font(.subheadline.weight(.semibold))
                    .opacity(0.9)
                    .monospacedDigit()
                FujiHeroActions(source: "fuji", explore: explore)
            }
        }
        .onChange(of: area) {
            let camera = FujiCamera.area(area, spots: spots.filter { area.contains($0) }, summit: summit)
            withAnimation(reduceMotion ? nil : .smooth(duration: 1.2)) { position = .camera(camera) }
        }
    }

    /// "3.776 m · 9 chỗ thấy đỉnh · cách bạn 120 km"
    private func facts(_ shown: [FujiGuide.Spot]) -> String {
        var parts = ["\(Fmt.grouped(Int(model.guide.fuji.summit.h))) m", "\(shown.filter(\.visible).count) chỗ thấy đỉnh"]
        if let p = model.position { parts.append("cách bạn \(Fmt.km(FujiSight.from(p).km))") }
        if !model.network.online { parts.append("không có mạng") }
        return parts.joined(separator: " · ")
    }
}

/// The two actions at a hero's foot, in one glass group: open the map, find Fuji with the camera.
private struct FujiHeroActions: View {
    @Environment(AppModel.self) private var model
    let source: String
    let explore: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: explore) {
                    Label("Bản đồ 3D", systemImage: "view.3d")
                }
                .buttonStyle(.glass)
                Button {
                    model.present(.fujiFinder, from: "\(source).finder")
                } label: {
                    Label("Tìm bằng camera", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.glass)
                .sheetSource("\(source).finder")
            }
            .font(.subheadline.weight(.semibold))
            .labelStyle(.titleAndIcon)
            .controlSize(.large)
        }
    }
}

/// How to read the map: the dot's colour, the line's dash.
private struct FujiLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            key(Palette.fuji, "thấy đỉnh")
            key(Color(white: 0.55), "bị núi che")
            HStack(spacing: 5) {
                Capsule().fill(.secondary).frame(width: 6, height: 2)
                Capsule().fill(.secondary).frame(width: 6, height: 2)
                Text("tia nhìn bị chắn")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chấm tím: thấy đỉnh. Chấm xám: bị núi che. Tia nét đứt: tầm nhìn bị chắn.")
    }

    private func key(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
        }
    }
}

// MARK: - Viewpoints

/// A day's viewpoints: the planned ones as rows, the places people post from folded underneath.
private struct FujiSpotSection: View {
    @Environment(AppModel.self) private var model
    let area: FujiArea
    @State private var showsPopular = false

    var body: some View {
        let spots = model.guide.fuji.spots.filter { area.contains($0) }
        let main = FujiWords.ordered(spots.filter { $0.role != "popular" })
        let popular = FujiWords.ordered(spots.filter { $0.role == "popular" })
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(area.heading)
            if let note = area.note {
                Text(note).font(.subheadline).foregroundStyle(.secondary)
            }
            if !main.isEmpty {
                Card(padding: 14) {
                    PlanRows(items: main) { FujiSpotRow(spot: $0) }
                }
            }
            if !popular.isEmpty {
                Card(padding: 14) {
                    DisclosureGroup(isExpanded: $showsPopular.animation(.snappy)) {
                        PlanRows(items: popular) { FujiSpotRow(spot: $0, compact: true) }
                            .padding(.top, 12)
                    } label: {
                        Label("\(popular.count) chỗ hay được đăng", systemImage: "camera.on.rectangle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .frame(minHeight: 32, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// A viewpoint in a list: the way to look, its name, how far, which way, how much shows.
private struct FujiSpotRow: View {
    @Environment(AppModel.self) private var model
    let spot: FujiGuide.Spot
    var compact = false

    var body: some View {
        NavigationLink(value: FujiPage.spot(spot.id)) {
            HStack(spacing: 12) {
                FujiBearingGlyph(spot: spot, size: compact ? 30 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.fujiName(spot))
                        .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("\(Fmt.km(spot.km)) · \(Geo.compass(spot.bearing)) · \(FujiWords.short(spot))")
                        .font(compact ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
                if spot.role != "popular", let role = FujiWords.role(spot) { Tag(text: role) }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The way to the Kawaguchiko option's own page.
private struct FujiKawaguchikoLink: View {
    var body: some View {
        NavigationLink(value: FujiPage.kawaguchiko) {
            HStack(spacing: 12) {
                GlyphTile(symbol: "tram.fill", tint: Palette.fuji, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Đi Kawaguchiko").font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text("Tàu, xe buýt, đi lại ở đó, lịch mẫu").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(minHeight: 44)
            .background(Palette.card, in: .rect(cornerRadius: Metrics.card, style: .continuous))
            .contentShape(.rect(cornerRadius: Metrics.card, style: .continuous))
        }
        .buttonStyle(.pressable)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - A viewpoint's page

/// One viewpoint: the line of sight on the terrain, what shows of the mountain and how big, the
/// numbers, the horizon, the research notes, its photographs, the clouds there.
struct FujiSpotPage: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var exploring = false

    var body: some View {
        if let spot = model.guide.fuji.spots.first(where: { $0.id == id }) {
            content(spot)
        } else {
            ContentUnavailableView("Không có chỗ ngắm này", systemImage: "mountain.2")
        }
    }

    private func content(_ spot: FujiGuide.Spot) -> some View {
        let research = model.fujiResearch(spot.id)
        let name = model.fujiName(spot)
        let place = model.store.place(spot.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FujiSpotHero(spot: spot, name: name, ja: FujiWords.ja(spot, store: model.store, research: research)) { exploring = true }
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    FujiSpotVerdict(spot: spot)
                    FujiSpotNumbers(spot: spot)
                    if let pano = model.guide.fuji.panoramas[spot.id] {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Đường chân trời")
                            Card {
                                PlanPanorama(pano: pano)
                                    .frame(height: 110)
                                    .accessibilityLabel("Đường chân trời nhìn từ \(name) về phía Fuji")
                                Text("Tính từ dữ liệu độ cao, nhìn về phía Fuji trong khoảng ±22°; trục đứng phóng đại để dễ thấy hình núi.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    FujiSpotNotes(research: research)
                    if let place { FujiSpotPhotos(place: place) }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Mây ở đây")
                        CloudForecast(title: name, key: spot.id, coordinate: FujiCamera.point(spot))
                    }
                    if place != nil {
                        NavigationLink(value: Route.place(spot.id)) {
                            Label("Trang địa điểm", systemImage: "mappin.and.ellipse")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 18)
            }
            .padding(.bottom, 32)
        }
        .screen()
        .detailPage(title: name, heroHeight: FujiSpotHero.height)
        .navigationDestination(isPresented: $exploring) {
            FujiExplorer(area: FujiArea.of(spot), focus: spot.id, spots: model.guide.fuji.spots, summit: model.guide.fuji.summit.coordinate)
        }
    }
}

/// The viewpoint's line of sight on the terrain, seen from behind it, or its own photograph (else
/// the plot) without a network; the name, what it is in the plan and the two actions at its foot.
private struct FujiSpotHero: View {
    static let height: CGFloat = 440
    @Environment(AppModel.self) private var model
    let spot: FujiGuide.Spot
    let name: String
    let ja: String?
    let explore: () -> Void
    @State private var position: MapCameraPosition

    init(spot: FujiGuide.Spot, name: String, ja: String?, explore: @escaping () -> Void) {
        self.spot = spot
        self.name = name
        self.ja = ja
        self.explore = explore
        _position = State(initialValue: .camera(FujiCamera.spot(spot, summit: FujiSight.summit)))
    }

    var body: some View {
        DetailHero(title: name, subtitle: ja, height: Self.height) {
            ZStack {
                if model.network.online {
                    FujiTerrainMap(spots: [spot], position: $position, selection: .constant(spot.id))
                } else if let photo = offlinePhoto {
                    PlacePhoto(photo: photo)
                } else {
                    FujiCompassPlot.backdrop
                    FujiCompassPlot(spots: [spot], selection: .constant(spot.id))
                        .padding(.top, 96)
                        .padding(.bottom, 180)
                }
            }
            .allowsHitTesting(false)
        } foot: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Tag(text: spot.visible ? "Thấy đỉnh" : "Bị núi che", symbol: spot.visible ? "eye" : "eye.slash", tint: .white)
                    if let role = FujiWords.role(spot) { Tag(text: role, tint: .white) }
                    if let day = FujiArea.of(spot).day { Tag(text: day.prefix(1).uppercased() + day.dropFirst(), tint: .white) }
                }
                FujiHeroActions(source: "fuji.spot.\(spot.id)", explore: explore)
            }
        }
    }

    /// a bundled view of the place, for when the map cannot load
    private var offlinePhoto: Photo? {
        model.store.place(spot.id)?.images.first { $0.isBundled && ($0.kind == "view" || $0.kind == "exterior") }
    }
}

/// What shows of the mountain, said once and large; then how high it stands and the lens for it.
private struct FujiSpotVerdict: View {
    let spot: FujiGuide.Spot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label {
                Text(FujiWords.shown(spot))
                    .font(.title3.weight(.semibold))
            } icon: {
                Image(systemName: spot.visible ? "eye" : "eye.slash")
                    .foregroundStyle(spot.visible ? Palette.fuji : Color.secondary)
            }
            if spot.visible, let h = spot.heightDeg, h > 0 {
                Text(sentence(h))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "Núi cao 2,4° trên đường chân trời, cỡ ngón cái giơ thẳng tay. Chụp bằng iPhone: ống 3× cho núi chiếm khoảng nửa khung."
    private func sentence(_ h: Double) -> String {
        var s = "Núi cao \(Fmt.decimal(h, digits: 1))° trên đường chân trời, \(FujiWords.size(h))."
        if let w = spot.widthDeg, w > 0 {
            s += " Chụp bằng iPhone: ống \(FujiWords.lens(w)) cho núi chiếm khoảng nửa khung."
        }
        return s
    }
}

/// Distance, bearing and the ground's height, side by side, stacked when the type is large.
private struct FujiSpotNumbers: View {
    let spot: FujiGuide.Spot

    var body: some View {
        Card {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 18) { stats }
                VStack(alignment: .leading, spacing: 12) { stats }
            }
        }
    }

    @ViewBuilder
    private var stats: some View {
        Stat(value: Fmt.km(spot.km), label: "tới đỉnh")
        Stat(value: "\(Geo.compass(spot.bearing)) \(Int(spot.bearing.rounded()))°", label: "hướng nhìn")
        Stat(value: "\(Fmt.grouped(Int(spot.elev))) m", label: "độ cao chỗ đứng")
        if !spot.visible, let b = spot.blockKm, b > 0 {
            Stat(value: Fmt.km(b), label: "tới sườn núi chắn")
        }
    }
}

/// The research on the viewpoint: what to expect, how to frame it, when to come, how busy.
private struct FujiSpotNotes: View {
    struct Note {
        let symbol: String
        let label: String
        let text: String
    }

    let research: JSONValue?

    private var notes: [Note] {
        let fields: [(symbol: String, label: String, key: String)] = [
            ("mountain.2", "Ở đây", "fujiNote"),
            ("camera", "Chụp", "photoTips"),
            ("clock", "Lúc nên tới", "bestTime"),
            ("person.3", "Đông hay vắng", "crowd"),
        ]
        return fields.compactMap { f in
            research?[f.key]?.string.map { Note(symbol: f.symbol, label: f.label, text: $0) }
        }
    }

    var body: some View {
        let rows = notes
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Ghi chú")
                Card {
                    PlanRows(items: rows) { r in
                        PlanInfoRow(symbol: r.symbol, text: r.text, label: r.label)
                    }
                }
            }
        }
    }
}

/// The place's views and front, a few, scrolling sideways, each with its credit.
private struct FujiSpotPhotos: View {
    let place: Place

    var body: some View {
        let photos = Array(place.images.filter { $0.kind == "view" || $0.kind == "exterior" }.prefix(4))
        if !photos.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Ảnh")
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(photos, id: \.src) { photo in
                            VStack(alignment: .leading, spacing: 4) {
                                PlacePhoto(photo: photo)
                                    .frame(width: 250, height: 170)
                                    .clipShape(.rect(cornerRadius: 18, style: .continuous))
                                if let caption = photo.caption {
                                    Text(caption).font(.caption).lineLimit(2)
                                }
                                if let credit = photo.credit {
                                    Text(credit).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .frame(width: 250, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, Metrics.gutter, for: .scrollContent)
                .padding(.horizontal, -Metrics.gutter)
            }
        }
    }
}

// MARK: - Kawaguchiko

private struct FujiKawaguchikoPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                if let info = model.guide.fuji.kawaguchiko { PlanKawaguchiko(info: info) }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
        .screen()
        .navigationTitle("Đi Kawaguchiko")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - The odds

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
            transport("Tàu", info["trains"]?.array ?? [], symbol: "tram.fill")
            transport("Xe buýt", info["buses"]?.array ?? [], symbol: "bus.fill")
            let local = info["local"]?.array ?? []
            if !local.isEmpty {
                SectionTitle("Đi lại ở đó")
                Card {
                    PlanRows(items: local) { l in
                        PlanParagraph(title: l["name"]?.string ?? "", text: l["what"]?.string ?? "")
                    }
                }
            }
            let schedule = info["schedule"]?.array ?? []
            if !schedule.isEmpty {
                SectionTitle("Lịch mẫu")
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
                SectionTitle("Cuối tháng 10")
                Card { Text(october).font(.subheadline) }
            }
        }
    }

    @ViewBuilder
    private func transport(_ title: String, _ list: [JSONValue], symbol: String) -> some View {
        if !list.isEmpty {
            SectionTitle(title)
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

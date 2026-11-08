import MapKit
import SwiftUI
import TripKit

// Fuji, in the order a traveller asks: where can I see it from (the 3D map and the viewpoints of
// each day), will it be out (clouds now, the odds in October), and the Kawaguchiko option. A
// viewpoint opens as a card, as a place does: its photographs dissolving into their colour, what
// shows of the mountain, the horizon, the line of sight on the terrain, when to go, the clouds.

struct FujiView: View {
    @Environment(AppModel.self) private var model
    @State private var area: FujiArea = .all

    private var fuji: FujiGuide { model.guide.fuji }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FujiHero(area: area, spots: fuji.spots, summit: fuji.summit.coordinate)
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
        // the map is pushed as a value, like every page in the stack: a page pushed by a flag
        // (navigationDestination(isPresented:)) cannot push values of its own on top
        .navigationDestination(for: FujiPage.self) { FujiPageHost(page: $0) }
    }
}

/// The pages inside the Fuji page and inside a viewpoint's card.
struct FujiPageHost: View {
    @Environment(AppModel.self) private var model
    let page: FujiPage

    var body: some View {
        Group {
            switch page {
            case .map(let area, let focus):
                FujiExplorer(area: area, focus: focus, spots: model.guide.fuji.spots, summit: model.guide.fuji.summit.coordinate)
            case .kawaguchiko:
                FujiKawaguchikoPage()
            }
        }
        .settlesTransition()
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
    @State private var position: MapCameraPosition

    init(area: FujiArea, spots: [FujiGuide.Spot], summit: Coordinate) {
        self.area = area
        self.spots = spots
        self.summit = summit
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
                NavigationLink(value: FujiPage.map(area, focus: nil)) {
                    Color.clear.contentShape(.rect)
                }
                .buttonStyle(.pressable(.plain))
                .accessibilityHidden(true)
            }
        } foot: {
            VStack(alignment: .leading, spacing: 12) {
                FujiHeroFacts(seen: shown.filter(\.visible).count)
                FujiHeroActions(source: "fuji", map: .map(area, focus: nil))
            }
        }
        .onChange(of: area) {
            let camera = FujiCamera.area(area, spots: spots.filter { area.contains($0) }, summit: summit)
            withAnimation(reduceMotion ? nil : .smooth(duration: 1.2)) { position = .camera(camera) }
        }
    }

}

/// "3.776 m · 9 chỗ thấy đỉnh · cách bạn 120 km". Its own view: it reads where you are, and a step
/// should redraw this line, not the 3D map above it.
private struct FujiHeroFacts: View {
    @Environment(AppModel.self) private var model
    let seen: Int

    var body: some View {
        Text(facts)
            .font(.subheadline.weight(.semibold))
            .opacity(0.9)
            .monospacedDigit()
    }

    private var facts: String {
        var parts = ["\(Fmt.grouped(Int(model.guide.fuji.summit.h))) m", "\(seen) chỗ thấy đỉnh"]
        if let p = model.position { parts.append("cách bạn \(Fmt.km(FujiSight.from(p).km))") }
        if !model.network.online { parts.append("không có mạng") }
        return parts.joined(separator: " · ")
    }
}

/// The two actions at the hero's foot, in one glass group: open the map, find Fuji with the camera.
private struct FujiHeroActions: View {
    @Environment(AppModel.self) private var model
    let source: String
    let map: FujiPage

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink(value: map) {
                    Label("Bản đồ 3D", systemImage: "view.3d")
                }
                .buttonStyle(.pressable(.glass))
                Button {
                    model.present(.fujiFinder, from: "\(source).finder")
                } label: {
                    Label("Tìm bằng camera", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.pressable(.glass))
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
                    // unfolding answers; folding away stays quiet
                    .sensoryFeedback(.press, trigger: showsPopular) { _, shown in shown }
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
        Button {
            model.present(.fujiSpot(spot.id, fromMap: false), from: "fuji.row.\(spot.id)")
        } label: {
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
        .buttonStyle(.pressable(.plain))
        .sheetSource("fuji.row.\(spot.id)")
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

// MARK: - A viewpoint's card

/// One viewpoint, as a card like a place's: its photographs fill the top and dissolve into their
/// own colour, which the card is then laid on (a viewpoint with none shows its line of sight on the
/// terrain, on Fuji's dusk blue); the name and the actions where they dissolve; then what shows of
/// the mountain and how big, the numbers, the horizon, the line of sight, the research notes, the
/// clouds there.
struct FujiSpotPage: View {
    @Environment(AppModel.self) private var model
    let id: String
    /// opened over the 3D map, which the map button then goes back to
    var fromMap = false

    var body: some View {
        if let spot = model.guide.fuji.spots.first(where: { $0.id == id }) {
            FujiSpotCard(spot: spot, photos: photos(spot), fromMap: fromMap)
        } else {
            ContentUnavailableView("Không có chỗ ngắm này", systemImage: "mountain.2")
                .toolbar { CloseButton() }
        }
    }

    /// What the place looks like: the viewpoint's own photographs (a view of Fuji from there when it
    /// shows), then the place's views and outsides. A ryokan's rooms or a restaurant's dishes are
    /// on their own pages; they come here only when there is nothing else.
    private func photos(_ spot: FujiGuide.Spot) -> [Photo] {
        let all = model.store.place(spot.id)?.images ?? []
        let isView: (Photo) -> Bool = { $0.kind == "view" || $0.kind == "exterior" }
        var seen = Set<String>()
        let scenery = (spot.images + all.filter(isView)).filter { seen.insert($0.src).inserted }
        return scenery.isEmpty ? all : scenery
    }
}

/// `FujiSpotPage` for a viewpoint found, with its photographs.
private struct FujiSpotCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var system
    let spot: FujiGuide.Spot
    /// `FujiSpotPage.photos`
    let photos: [Photo]
    let fromMap: Bool
    @State private var page = 0
    /// the card's colour, from its first photograph, held while the card lives
    @State private var held: PageTone

    /// the hero's share of the card's height
    static let heroFraction: CGFloat = 0.56

    init(spot: FujiGuide.Spot, photos: [Photo], fromMap: Bool) {
        self.spot = spot
        self.photos = photos
        self.fromMap = fromMap
        _held = State(initialValue: PageTone(photos.first))
    }

    /// The first photograph decides light or dark and the hue for the whole card; with none, Fuji's dusk.
    private var canvas: AmbientCanvas? {
        photos.isEmpty ? .dusk : held.canvas(dim: system == .dark)
    }

    var body: some View {
        let research = model.fujiResearch(spot.id)
        let name = model.fujiName(spot)
        let place = model.store.place(spot.id)
        let canvas = self.canvas
        ScrollView {
            VStack(spacing: 0) {
                Group {
                    if photos.isEmpty {
                        FujiSightMap(spot: spot, inset: EdgeInsets(top: 96, leading: 24, bottom: 220, trailing: 24))
                            .dissolve([(1, 0), (1, 0.55), (0.7, 0.72), (0.25, 0.88), (0, 1)])
                    } else {
                        AmbientHero(photos: photos, page: $page)
                    }
                }
                .heroFrame(fraction: Self.heroFraction)
                .overlay(alignment: .bottom) {
                    FujiSpotHeadline(spot: spot, name: name, ja: FujiWords.ja(spot, store: model.store, research: research),
                                     count: photos.count, page: page, fill: (canvas ?? .dusk).color, fromMap: fromMap)
                }
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    FujiSpotVerdict(spot: spot)
                    FujiSpotNumbers(spot: spot)
                    if let pano = model.guide.fuji.panoramas[spot.id] {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Đường chân trời")
                            Card {
                                FujiHorizon(pano: pano)
                                    .frame(height: 110)
                                    .accessibilityLabel("Đường chân trời nhìn từ \(name) về phía Fuji")
                                Text("Tính từ dữ liệu độ cao, nhìn về phía Fuji trong khoảng ±22°; trục đứng phóng đại để dễ thấy hình núi.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    // with photographs up top, the line of sight on the terrain gets its own place
                    if !photos.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Tia ngắm")
                            FujiSightMap(spot: spot, inset: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                                .frame(height: 220)
                                .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                        }
                    }
                    FujiSpotNotes(research: research)
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
                        .buttonStyle(.pressable(.bordered))
                        .controlSize(.large)
                    }
                    AmbientCredit(photos: photos, page: page)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 14)
            }
            .padding(.bottom, 32)
        }
        .ambientPage(canvas, title: name, heroFraction: Self.heroFraction)
        .decidesTone($held, of: photos.first)
        .toolbar { CloseButton() }
    }
}

/// Centred where the picture dissolves, as on a place's card: page dots, the name, the Japanese
/// name, what it is; then the 3D map, finding the mountain with the camera (the one filled
/// capsule), and walking there.
private struct FujiSpotHeadline: View {
    @Environment(AppModel.self) private var model
    @Environment(\.closeSheet) private var closeSheet
    let spot: FujiGuide.Spot
    let name: String
    let ja: String?
    let count: Int
    let page: Int
    /// the card's colour, for the type on the filled capsule
    let fill: Color
    let fromMap: Bool

    var body: some View {
        VStack(spacing: 5) {
            if count > 1 {
                AmbientDots(count: count, current: page)
                    .padding(.bottom, 6)
            }
            Text(name)
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let ja {
                Text(ja)
                    .font(.mincho(20, bold: false, relativeTo: .title3))
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(facts)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(2)
            actions
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 10)
    }

    /// "Thấy đỉnh · 36 km tới đỉnh · nhìn về Đông Bắc · Rẽ thêm · ngày 5"
    private var facts: String {
        var parts = [spot.visible ? "Thấy đỉnh" : "Bị núi che", "\(Fmt.km(spot.km)) tới đỉnh", "nhìn về \(Geo.compass(spot.bearing))"]
        if let role = FujiWords.role(spot) { parts.append(role) }
        if let day = FujiArea.of(spot).day { parts.append(day) }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 16) {
            if fromMap {
                // the map is right under this card, already flown to the viewpoint
                Button { closeSheet?.close() } label: { AmbientDisc(symbol: "view.3d") }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Về bản đồ 3D")
            } else {
                NavigationLink(value: FujiPage.map(FujiArea.of(spot), focus: spot.id)) { AmbientDisc(symbol: "view.3d") }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Bản đồ 3D")
            }
            Button {
                model.present(.fujiFinder, from: "fujispot.\(spot.id).finder")
            } label: {
                Label("Tìm Fuji", systemImage: "camera.viewfinder")
                    .font(.headline)
                    .foregroundStyle(fill)
                    .frame(width: 168, height: 50)
                    .background(Color.primary, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
            .sheetSource("fujispot.\(spot.id).finder")
            if model.store.place(spot.id) != nil {
                Button { model.walk(to: spot.id) } label: { AmbientDisc(symbol: "figure.walk") }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Đi bộ tới đây")
            } else {
                // keeps the capsule in the middle
                Color.clear.frame(width: 50, height: 50).accessibilityHidden(true)
            }
        }
        .labelStyle(.titleAndIcon)
    }
}

/// The viewpoint's line of sight on the 3D terrain, seen from behind it; without a network, the
/// plot round the summit. A picture: it does not move under a finger.
private struct FujiSightMap: View {
    @Environment(AppModel.self) private var model
    let spot: FujiGuide.Spot
    /// room the plot leaves round itself (the card's headline sits over the bottom of the hero)
    let inset: EdgeInsets
    @State private var position: MapCameraPosition

    init(spot: FujiGuide.Spot, inset: EdgeInsets) {
        self.spot = spot
        self.inset = inset
        _position = State(initialValue: .camera(FujiCamera.spot(spot, summit: FujiSight.summit)))
    }

    var body: some View {
        ZStack {
            if model.network.online {
                FujiTerrainMap(spots: [spot], position: $position, selection: .constant(spot.id))
            } else {
                FujiCompassPlot.backdrop
                FujiCompassPlot(spots: [spot], selection: .constant(spot.id))
                    .padding(inset)
            }
        }
        .allowsHitTesting(false)
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

/// The horizon around Fuji's bearing from a viewpoint, height exaggerated four times. `compact`
/// (a card over the map) leaves out the name over the summit's mark.
struct FujiHorizon: View {
    let pano: FujiGuide.Panorama
    var compact = false

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
            if !compact {
                ctx.draw(Text("Fuji").font(.caption2.weight(.semibold)).foregroundStyle(.secondary), at: CGPoint(x: sx, y: 8), anchor: .bottom)
            }
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

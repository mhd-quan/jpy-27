import MapKit
import SwiftUI
import TripKit

// The Fuji viewpoints on a map: Apple's 3D terrain (satellite with realistic elevation), the summit,
// each viewpoint coloured by whether the summit shows from there, and its line of sight to the
// summit, solid when clear and dashed when a nearer ridge is in the way, as the web's map draws
// them. MapLibre has no 3D terrain on iOS, so this is MapKit. Without a network MapKit draws
// nothing, so the same viewpoints are then laid out round the summit by bearing and distance.

// MARK: - Areas

/// The trip's Fuji country, by the day it is seen on.
enum FujiArea: String, CaseIterable, Identifiable, Hashable {
    case all
    case hakone = "4"
    case tokaido = "5"
    case kawaguchiko

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Cả vùng"
        case .hakone: "Hakone"
        case .tokaido: "Tōkaidō"
        case .kawaguchiko: "Kawaguchiko"
        }
    }

    /// what the chip says under or after the name
    var day: String? {
        switch self {
        case .all: nil
        case .hakone: "ngày 4"
        case .tokaido: "ngày 5"
        case .kawaguchiko: "thay ngày 3"
        }
    }

    /// The section heading on the page.
    var heading: String {
        switch self {
        case .all: "Mọi chỗ ngắm"
        case .hakone: "Ngày 4 · Hakone"
        case .tokaido: "Ngày 5 · Tōkaidō"
        case .kawaguchiko: "Kawaguchiko, thay ngày 3"
        }
    }

    /// What the terrain does on that day, as the web says it.
    var note: String? {
        switch self {
        case .all: nil
        case .hakone: "Hồ Ashi nằm trong lòng một miệng núi lửa cổ; vành núi phía tây che bớt chân Fuji, nên phần nhìn thấy phụ thuộc nhiều vào chỗ đứng."
        case .tokaido: "Ngồi bên phải tàu từ Mishima tới Fujikawa. Rẽ qua Satta hoặc Miho chỉ khi đổi hẳn bữa trưa."
        case .kawaguchiko: "Thuộc phương án thay ngày 3: Fuji ở ngay phía nam, gần hơn mọi chỗ khác của chuyến."
        }
    }

    /// The days in order, for the page's sections.
    static let days: [FujiArea] = [.hakone, .tokaido, .kawaguchiko]

    func contains(_ spot: FujiGuide.Spot) -> Bool {
        self == .all || planFujiDayKey(spot) == rawValue
    }

    static func of(_ spot: FujiGuide.Spot) -> FujiArea {
        days.first { $0.rawValue == planFujiDayKey(spot) } ?? .all
    }
}

// MARK: - What a viewpoint says

/// Names and the web's sentences for a viewpoint: how much of the mountain shows, how big it looks
/// at arm's length, which iPhone lens fills half the frame with it.
enum FujiWords {
    /// names the data leaves to the web (src/pages/fuji/index.astro)
    private static let names: [String: String] = [
        "lake-ashi-cruise-deck": "Giữa hồ Ashi, trên thuyền",
        "moto-hakone-viewpoint": "Bờ hồ Moto-Hakone",
        "togendai": "Bến Tōgendai",
        "sounzan": "Ga Sōunzan",
    ]

    static func name(_ spot: FujiGuide.Spot, store: TripStore, research: JSONValue?) -> String {
        names[spot.id] ?? spot.name ?? store.place(spot.id)?.name ?? research?["nameEn"]?.string ?? research?["name"]?.string ?? spot.id
    }

    static func ja(_ spot: FujiGuide.Spot, store: TripStore, research: JSONValue?) -> String? {
        spot.ja ?? store.place(spot.id)?.ja ?? research?["nameJa"]?.string
    }

    /// "Thấy nửa trên, khoảng 1.370 m" / "Bị địa hình che, cách 0,6 km"
    static func shown(_ spot: FujiGuide.Spot) -> String {
        guard spot.visible else { return "Bị địa hình che, cách \(Fmt.km(spot.blockKm ?? 0))" }
        let m = Int(spot.shownM ?? 0)
        if m >= 2400 { return "Thấy gần trọn núi, khoảng \(Fmt.grouped(m)) m phần trên" }
        if m >= 1200 { return "Thấy nửa trên, khoảng \(Fmt.grouped(m)) m" }
        return "Thấy phần chóp, khoảng \(Fmt.grouped(m)) m"
    }

    /// "nửa trên" for a row's one line
    static func short(_ spot: FujiGuide.Spot) -> String {
        guard spot.visible else { return "bị núi che" }
        let m = spot.shownM ?? 0
        return m >= 2400 ? "gần trọn núi" : m >= 1200 ? "nửa trên" : "phần chóp"
    }

    /// The mountain's height above the horizon against a hand held at arm's length.
    static func size(_ deg: Double) -> String {
        deg < 1.2 ? "cỡ một ngón út giơ thẳng tay" : deg < 2.5 ? "cỡ ngón cái giơ thẳng tay" : deg < 5.5 ? "cỡ ba ngón tay khép lại" : "cỡ nửa nắm tay"
    }

    /// The iPhone lens that makes the mountain about half the frame wide.
    static func lens(_ widthDeg: Double) -> String {
        let lenses: [(String, Double)] = [("1×", 69), ("2×", 38), ("3×", 26), ("5×", 17)]
        let need = widthDeg / 0.5
        return lenses.reversed().first { $0.1 >= need }?.0 ?? "1×"
    }

    /// Planned viewpoints first (the summit in sight before the hidden ones, nearer first), then
    /// the places people post from.
    static func ordered(_ spots: [FujiGuide.Spot]) -> [FujiGuide.Spot] {
        let main = spots.filter { $0.role != "popular" }.sorted { a, b in
            a.visible != b.visible ? a.visible : a.km < b.km
        }
        let popular = spots.filter { $0.role == "popular" }.sorted { $0.km < $1.km }
        return main + popular
    }

    static func role(_ spot: FujiGuide.Spot) -> String? {
        switch spot.role {
        case "detour": "Rẽ thêm"
        case "alt": "Phương án"
        case "popular": "Hay được đăng"
        default: nil
        }
    }
}

extension AppModel {
    /// A viewpoint's research notes (fujiNote, photoTips, bestTime, crowd).
    func fujiResearch(_ id: String) -> JSONValue? {
        guide.fuji.research?["spots"]?.array.first { $0["id"]?.string == id }
    }

    func fujiName(_ spot: FujiGuide.Spot) -> String {
        FujiWords.name(spot, store: store, research: fujiResearch(spot.id))
    }
}

// MARK: - Camera

/// Where the camera stands: behind the viewpoints, looking over them at the summit, tilted as the
/// web's map is (58°).
enum FujiCamera {
    static let pitch = 58.0

    static func cl(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
    }

    static func point(_ spot: FujiGuide.Spot) -> Coordinate {
        Coordinate(spot.lat, spot.lng)
    }

    private static func lerp(_ a: Coordinate, _ b: Coordinate, _ t: Double) -> Coordinate {
        Coordinate(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t)
    }

    /// An area: for one day, from behind its viewpoints towards the summit; for the whole region,
    /// whose viewpoints ring the mountain, the web's view from the south-east (bearing −52°).
    static func area(_ area: FujiArea, spots: [FujiGuide.Spot], summit: Coordinate) -> MapCamera {
        let points = spots.map(point)
        guard !points.isEmpty else {
            return MapCamera(centerCoordinate: cl(summit), distance: 90_000, heading: 308, pitch: pitch)
        }
        let n = Double(points.count)
        let mid = Coordinate(points.map(\.lat).reduce(0, +) / n, points.map(\.lng).reduce(0, +) / n)
        let center: Coordinate
        let heading: Double
        if area == .all {
            center = lerp(mid, summit, 0.5)
            heading = 308
        } else {
            center = lerp(mid, summit, 0.42)
            heading = Geo.bearing(mid, summit)
        }
        let reach = (points + [summit]).map { Geo.km(center, $0) }.max() ?? 30
        let distance = min(220_000, max(16_000, reach * 2 * 1000 * 1.25))
        return MapCamera(centerCoordinate: cl(center), distance: distance, heading: heading, pitch: pitch)
    }

    /// One viewpoint: standing a little behind it, looking along its line of sight, so the
    /// viewpoint sits in the foreground and the summit ahead.
    static func spot(_ spot: FujiGuide.Spot, summit: Coordinate) -> MapCamera {
        let p = point(spot)
        return MapCamera(centerCoordinate: cl(lerp(p, summit, 0.38)), distance: max(7_000, spot.km * 1000 * 0.8),
                         heading: spot.bearing, pitch: 64)
    }
}

// MARK: - Map

/// The 3D terrain map with the summit, the viewpoints and their lines of sight. Static (no
/// gestures) when it is a page's picture; the explorer makes it interactive and selectable.
struct FujiTerrainMap: View {
    @Environment(AppModel.self) private var model
    let spots: [FujiGuide.Spot]
    @Binding var position: MapCameraPosition
    @Binding var selection: String?
    var interactive = false
    var scope: Namespace.ID? = nil

    var body: some View {
        let summit = model.guide.fuji.summit.coordinate
        Map(position: $position, interactionModes: interactive ? .all : [], selection: $selection, scope: scope) {
            ForEach(spots) { s in
                MapPolyline(coordinates: [FujiCamera.cl(FujiCamera.point(s)), FujiCamera.cl(summit)])
                    .stroke(lineColor(s), style: lineStyle(s))
            }
            Annotation("Fuji", coordinate: FujiCamera.cl(summit), anchor: .bottom) {
                FujiSummitPin(height: Int(model.guide.fuji.summit.h))
            }
            .annotationTitles(.hidden)
            ForEach(spots) { s in
                Annotation(model.fujiName(s), coordinate: FujiCamera.cl(FujiCamera.point(s))) {
                    // a dot to see, a finger's width to tap
                    FujiSpotPin(visible: s.visible, major: s.role != "popular", selected: s.id == selection)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                // names only where they can be read: on the explorer, for the planned viewpoints
                .annotationTitles(interactive && (s.role != "popular" || s.id == selection) ? .automatic : .hidden)
                .tag(s.id)
            }
            if interactive { UserAnnotation() }
        }
        .mapStyle(.hybrid(elevation: .realistic, pointsOfInterest: .excludingAll))
        // no controls inside the map: a picture has none, the explorer sets its own beside it
        .mapControls { EmptyView() }
        .accessibilityLabel("Bản đồ 3D vùng Fuji, với tia ngắm từ từng điểm tới đỉnh")
    }

    private func lineColor(_ s: FujiGuide.Spot) -> Color {
        s.id == selection ? Palette.sun : Color.white.opacity(s.visible ? 0.85 : 0.6)
    }

    private func lineStyle(_ s: FujiGuide.Spot) -> StrokeStyle {
        let width: CGFloat = s.id == selection ? 3 : s.role == "popular" ? 1 : 1.6
        return StrokeStyle(lineWidth: width, lineCap: .round, dash: s.visible ? [] : [5, 5])
    }
}

/// The summit: a white capsule with its height, standing on the mountain top.
struct FujiSummitPin: View {
    let height: Int

    var body: some View {
        Label("\(Fmt.grouped(height)) m", systemImage: "mountain.2.fill")
            .font(.caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(Color(white: 0.1))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white, in: .capsule)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .accessibilityLabel("Đỉnh Fuji, \(Fmt.grouped(height)) mét")
    }
}

/// A viewpoint: violet when the summit shows from it, grey when terrain hides it.
struct FujiSpotPin: View {
    let visible: Bool
    var major = true
    var selected = false

    var body: some View {
        let d: CGFloat = selected ? 22 : major ? 14 : 9
        Circle()
            .fill(visible ? Palette.fuji : Color(white: 0.55))
            .frame(width: d, height: d)
            .overlay { Circle().strokeBorder(.white, lineWidth: selected ? 3 : 2) }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .animation(.snappy, value: selected)
            .accessibilityHidden(true)
    }
}

// MARK: - Without a network

/// The viewpoints round the summit by their true bearing and distance, north up, with rings every
/// 10 km: what the map shows, drawn from the data alone, for when MapKit has nothing to load.
struct FujiCompassPlot: View {
    @Environment(AppModel.self) private var model
    let spots: [FujiGuide.Spot]
    @Binding var selection: String?
    var selectable = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(40, min(size.width, size.height) / 2 - 28)
            let reach = max(10, (spots.map(\.km).max() ?? 40) * 1.08)
            let place = { (s: FujiGuide.Spot) -> CGPoint in
                // from the summit the viewpoint lies opposite to the way it looks
                let a = (s.bearing + 180) * .pi / 180
                let r = CGFloat(s.km / reach) * radius
                return CGPoint(x: center.x + r * CGFloat(sin(a)), y: center.y - r * CGFloat(cos(a)))
            }
            ZStack {
                // rings every 10 km
                ForEach(Array(stride(from: 10.0, through: reach, by: 10)), id: \.self) { km in
                    let r = CGFloat(km / reach) * radius
                    Circle()
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                        .frame(width: r * 2, height: r * 2)
                        .position(center)
                    Text("\(Int(km)) km")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                        .position(x: center.x + 18, y: center.y - r - 7)
                        .accessibilityHidden(true)
                }
                Text("B")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .position(x: center.x, y: max(10, center.y - radius - 14))
                    .accessibilityLabel("Phía bắc")
                // lines of sight
                ForEach(spots) { s in
                    Path { p in
                        p.move(to: place(s))
                        p.addLine(to: center)
                    }
                    .stroke(s.id == selection ? Palette.sun : .white.opacity(s.visible ? 0.7 : 0.45),
                            style: StrokeStyle(lineWidth: s.id == selection ? 2.5 : 1, lineCap: .round, dash: s.visible ? [] : [4, 4]))
                }
                FujiSummitPin(height: Int(model.guide.fuji.summit.h))
                    .position(center)
                ForEach(spots) { s in
                    let pin = FujiSpotPin(visible: s.visible, major: s.role != "popular", selected: s.id == selection)
                    Group {
                        if selectable {
                            Button {
                                selection = s.id
                            } label: {
                                pin.frame(width: 44, height: 44).contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                        } else {
                            pin
                        }
                    }
                    .position(place(s))
                    .accessibilityLabel("\(model.fujiName(s)), \(Fmt.km(s.km)), \(FujiWords.short(s))")
                    .accessibilityAddTraits(s.id == selection ? .isSelected : [])
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// The night-blue ground the plot is drawn on; laid by the caller, under the bars too.
    static var backdrop: some View {
        LinearGradient(colors: [Color(hex: "#1B2140"), Color(hex: "#2E2A5C")], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Explorer

/// The map on its own page: pan, pinch, twist and tilt the terrain; the day's viewpoints run along
/// the bottom as cards, and choosing one (on the map or by swiping the cards) flies the camera
/// behind it, looking along its line of sight.
struct FujiExplorer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.closeSheet) private var closeSheet
    @Namespace private var mapScope
    @State private var area: FujiArea
    @State private var selection: String?
    @State private var position: MapCameraPosition

    init(area: FujiArea, focus: String? = nil, spots: [FujiGuide.Spot], summit: Coordinate) {
        _area = State(initialValue: area)
        _selection = State(initialValue: focus)
        let inArea = spots.filter { area.contains($0) }
        let camera = focus.flatMap { id in spots.first { $0.id == id } }.map { FujiCamera.spot($0, summit: summit) }
            ?? FujiCamera.area(area, spots: inArea, summit: summit)
        _position = State(initialValue: .camera(camera))
    }

    private var spots: [FujiGuide.Spot] {
        FujiWords.ordered(model.guide.fuji.spots.filter { area.contains($0) })
    }

    var body: some View {
        let spots = self.spots
        ZStack {
            if model.network.online {
                FujiTerrainMap(spots: spots, position: $position, selection: $selection, interactive: true, scope: mapScope)
                    .ignoresSafeArea()
                FujiBarEdge()
            } else {
                FujiCompassPlot.backdrop.ignoresSafeArea()
                // inside the safe area: centred between the bar and the days along the bottom
                FujiCompassPlot(spots: spots, selection: $selection, selectable: true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.network.online {
                VStack(spacing: 8) {
                    MapCompass(scope: mapScope)
                    MapPitchToggle(scope: mapScope)
                    MapUserLocationButton(scope: mapScope)
                }
                .buttonBorderShape(.circle)
                .padding(.trailing, 12)
                .padding(.top, 8)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if model.network.online {
                MapScaleView(scope: mapScope)
                    .padding(.leading, 16)
                    .padding(.bottom, 8)
            }
        }
        .mapScope(mapScope)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.network.online {
                Label("Không có mạng: các điểm xếp theo hướng và khoảng cách tới đỉnh", systemImage: "wifi.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, 6)
            }
        }
        // everything the hand reaches for sits at the bottom, over the tab bar: the days, then the
        // viewpoints of the one chosen; the top keeps only the bar and the map's own controls
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                FujiAreaChips(area: $area, onMap: true)
                    // over satellite terrain or the night-blue plot: light type on dark glass
                    .environment(\.colorScheme, .dark)
                FujiSpotCarousel(spots: spots, selection: $selection)
            }
        }
        .navigationTitle("Bản đồ Fuji")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // the name set as the JP27 wordmark is
            ToolbarItem(placement: .principal) {
                WordmarkText(text: "Fuji")
                    .foregroundStyle(.white)
                    .accessibilityLabel("Bản đồ Fuji")
                    .accessibilityAddTraits(.isHeader)
            }
            SheetToolbarButton(title: "Tìm Fuji bằng camera", symbol: "camera.viewfinder", source: "fuji.explorer.finder") {
                model.present(.fujiFinder, from: "fuji.explorer.finder")
            }
            // opened from a viewpoint's card, the map is inside that sheet: close comes last
            if closeSheet != nil {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                CloseButton()
            }
        }
        // a viewpoint chosen flies the camera behind it; letting go (a tap on open ground) leaves
        // the camera where the hands put it
        .onChange(of: selection) { _, id in
            if let spot = id.flatMap({ id in self.spots.first { $0.id == id } }) { fly(to: spot) }
        }
        .onChange(of: area) {
            // a viewpoint of the new day stays chosen; else the camera frames the new day
            if let id = selection, self.spots.contains(where: { $0.id == id }) { return }
            selection = nil
            fly(to: nil)
        }
    }

    private func fly(to spot: FujiGuide.Spot?) {
        let summit = model.guide.fuji.summit.coordinate
        let camera = spot.map { FujiCamera.spot($0, summit: summit) } ?? FujiCamera.area(area, spots: spots, summit: summit)
        withAnimation(reduceMotion ? nil : .smooth(duration: 1.4)) {
            position = .camera(camera)
        }
    }
}

/// The area chips: the whole region or one day. Glass over the map, filled capsules on paper.
struct FujiAreaChips: View {
    @Binding var area: FujiArea
    var onMap = false

    var body: some View {
        ScrollView(.horizontal) {
            Group {
                if onMap {
                    GlassEffectContainer(spacing: 2) { row }
                } else {
                    row
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        // a strip floating over the map draws no edge effect of its own (built with the iOS 27 SDK
        // it would be the hard, ruled one)
        .scrollEdgeEffectHidden(onMap, for: .all)
        .contentMargins(.horizontal, onMap ? 12 : Metrics.gutter, for: .scrollContent)
        .sensoryFeedback(.selection, trigger: area)
    }

    private var row: some View {
        HStack(spacing: 8) {
            ForEach(FujiArea.allCases) { a in chip(a) }
        }
    }

    @ViewBuilder
    private func chip(_ a: FujiArea) -> some View {
        let on = a == area
        let label = HStack(spacing: 5) {
            Text(a.title).fontWeight(.semibold)
            if let day = a.day {
                Text(day).foregroundStyle(on ? Color.white.opacity(0.8) : Color.secondary)
            }
        }
        .font(.subheadline)
        .lineLimit(1)
        .foregroundStyle(on ? Color.white : Color.primary)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(.capsule)

        let button = Button {
            withAnimation(.snappy) { area = a }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .accessibilityLabel([a.title, a.day].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(on ? .isSelected : [])

        if onMap {
            button.glassEffect(on ? .regular.tint(Palette.sun).interactive() : .regular.interactive(), in: .capsule)
        } else {
            button.background(on ? AnyShapeStyle(Palette.sun) : AnyShapeStyle(Palette.card), in: .capsule)
        }
    }
}

/// The day's viewpoints as cards along the bottom of the explorer. Swiping to a card chooses it;
/// choosing a pin brings its card.
private struct FujiSpotCarousel: View {
    @Environment(AppModel.self) private var model
    let spots: [FujiGuide.Spot]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 10) {
                ForEach(spots) { s in
                    FujiSpotCard(spot: s, selected: s.id == selection) {
                        selection = s.id
                    }
                    .containerRelativeFrame(.horizontal) { width, _ in min(360, width - 56) }
                    .id(s.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $selection, anchor: .leading)
        .scrollIndicators(.hidden)
        .scrollEdgeEffectHidden(true, for: .all)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}

/// A viewpoint over the map: its name, how far and which way, what shows of the mountain and the
/// horizon it shows above. Tapping the card flies the camera behind it; Chi tiết opens its card.
private struct FujiSpotCard: View {
    @Environment(AppModel.self) private var model
    let spot: FujiGuide.Spot
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // the face of the card chooses it; the button below is the only other control, so the
            // two never compete for a tap
            Button(action: choose) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        FujiBearingGlyph(spot: spot, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(model.fujiName(spot))
                                .font(.headline)
                                .lineLimit(1)
                            Text("\(Fmt.km(spot.km)) tới đỉnh · nhìn về \(Geo.compass(spot.bearing))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(FujiWords.shown(spot))
                        .font(.subheadline)
                        .lineLimit(1)
                    if let pano = model.guide.fuji.panoramas[spot.id] {
                        FujiHorizon(pano: pano, compact: true)
                            .frame(height: 46)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Bay tới chỗ ngắm này trên bản đồ")
            HStack {
                if let role = FujiWords.role(spot) { Tag(text: role) }
                Spacer(minLength: 0)
                Button {
                    choose()
                    model.present(.fujiSpot(spot.id, fromMap: true), from: "fuji.card.\(spot.id)")
                } label: {
                    Text("Chi tiết").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .sheetSource("fuji.card.\(spot.id)")
            }
        }
        .padding(14)
        .background(Palette.card, in: .rect(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selected ? Palette.sun : .clear, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }
}

/// The soft edge under the bar over the map: the terrain blurs and darkens into the bar, from
/// frosted at the top to nothing, instead of stopping at a ruled strip; the bar's white title and
/// buttons read over bright ground.
private struct FujiBarEdge: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black.opacity(0.7), location: 0.4),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                }
            LinearGradient(colors: [.black.opacity(0.36), .clear], startPoint: .top, endPoint: .bottom)
        }
        .frame(height: 160)
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Which way to look from a viewpoint: an arrow turned to the summit's bearing, violet when the
/// summit shows, grey when terrain hides it.
struct FujiBearingGlyph: View {
    let spot: FujiGuide.Spot
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: spot.visible ? "location.north.fill" : "eye.slash")
            .font(.system(size: size * 0.42, weight: .semibold))
            .rotationEffect(.degrees(spot.visible ? spot.bearing : 0))
            .foregroundStyle(spot.visible ? Color.white : Color.secondary)
            .frame(width: size, height: size)
            .background(spot.visible ? AnyShapeStyle(Palette.fuji.gradient) : AnyShapeStyle(.fill.tertiary), in: .circle)
            .accessibilityHidden(true)
    }
}

/// The pages inside the Fuji page and a viewpoint's card. (A viewpoint itself opens as a card,
/// `AppSheet.fujiSpot`, as a place does.)
enum FujiPage: Hashable {
    /// the 3D map: a day framed, or flown to one viewpoint
    case map(FujiArea, focus: String?)
    case kawaguchiko
}

// MARK: - Photograph

/// Fuji above Suruga Bay from Satta Pass, on the Tōkaidō of day 5: the photograph for the home card
/// (Resources/Cover/fuji-satta.jpg, 1600 px, cut from the Commons original).
enum FujiPhotograph {
    static let file = "fuji-satta.jpg"
    static let credit = "Alpsdake · CC BY-SA 4.0"
    static let page = "https://commons.wikimedia.org/wiki/File:Mount_Fuji_from_Satta_Pass.jpg"

    /// Photo has no public initialiser: built from JSON, the way the trip data and the covers are.
    static let photo: Photo? = {
        let fields = ["kind": "view", "src": file, "caption": "Fuji và vịnh Suruga nhìn từ đèo Satta", "credit": credit,
                      "license": "CC BY-SA 4.0", "page": page]
        guard let json = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
        return try? JSONDecoder().decode(Photo.self, from: json)
    }()
}

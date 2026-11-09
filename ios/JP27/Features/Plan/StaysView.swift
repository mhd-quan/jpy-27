import SwiftUI
import TripKit

/// Chỗ ở: the five places to sleep, what to book them at, and how to hunt the price.
struct StaysView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.stack) {
                ForEach(model.guide.stays) { stay in
                    NavigationLink(value: Route.stay(stay.id)) {
                        PlanStayCard(stay: stay)
                    }
                    .buttonStyle(.pressable(.plain))
                }
                if !model.guide.hunt.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Săn giá mà vẫn giữ chất lượng")
                        Card {
                            PlanRows(items: Array(model.guide.hunt.enumerated())) { pair in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text("\(pair.offset + 1)")
                                        .font(.headline)
                                        .monospacedDigit()
                                        .foregroundStyle(Color.accentColor)
                                        .frame(width: 22)
                                    PlanParagraph(title: pair.element.title, text: pair.element.text)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
        .screen()
        .navigationTitle("Chỗ ở")
    }
}

private struct PlanStayCard: View {
    @Environment(AppModel.self) private var model
    let stay: StayPlan

    var body: some View {
        let place = model.store.place(stay.id)
        VStack(alignment: .leading, spacing: 0) {
            PlacePhoto(photo: place?.hero ?? stay.around?.photos.first, maxPixel: 900)
                .frame(height: 170)
            VStack(alignment: .leading, spacing: 6) {
                Text(place?.name ?? stay.id).font(.headline)
                Text("\(stay.nights) · \(stay.dates)").font(.subheadline).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(Fmt.yen(stay.target) + (stay.id == "mizunoto" ? " / đêm, hai bữa" : " / đêm"))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                    Spacer()
                    Text(stay.range).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Palette.card)
        .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// One hotel: the room and what to know, then the neighbourhood — walks from the door, what is
/// within a few minutes, and for the ryokan, where Fuji can and cannot be seen.
struct StayView: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        if let stay = model.guide.stays.first(where: { $0.id == id }) {
            PlanStayContent(stay: stay, photos: PlanStayContent.photos(of: stay, store: model.store))
        } else {
            ContentUnavailableView("Không có chỗ ở này", systemImage: "bed.double")
        }
    }
}

private let planWalkColors = ["#2F7DE1", "#E9792B", "#1E8A55", "#8A5CD0"]

/// The hotel as an album page: its own photographs and then the neighbourhood's fill the top and
/// dissolve into one colour taken from them, which the page is laid on; the name, the nights and
/// the hotel's actions sit centred where the photograph dissolves.
private struct PlanStayContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var system
    let stay: StayPlan
    /// `photos(of:store:)`
    let photos: [Photo]
    @State private var page = 0
    /// the page's colour, from its first photograph, held while the page lives
    @State private var held: PageTone

    /// the hero's share of the page's height
    static let heroFraction: CGFloat = 0.6

    init(stay: StayPlan, photos: [Photo]) {
        self.stay = stay
        self.photos = photos
        _held = State(initialValue: PageTone(photos.first))
    }

    /// the hotel's own photographs first, then the walks' and the neighbourhood's
    static func photos(of stay: StayPlan, store: TripStore) -> [Photo] {
        var seen = Set<String>()
        let own = store.place(stay.id)?.images ?? []
        return (own + (stay.around?.photos ?? [])).filter { seen.insert($0.src).inserted }
    }

    /// The first photograph decides light or dark and the hue for the whole page.
    private var canvas: AmbientCanvas? {
        held.canvas(dim: system == .dark)
    }

    var body: some View {
        let place = model.store.place(stay.id)
        let title = place?.name ?? "Chỗ ở"
        let scroll = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !photos.isEmpty {
                    AmbientHero(photos: photos, page: $page)
                        .heroFrame(fraction: Self.heroFraction)
                        .overlay(alignment: .bottom) {
                            PlanStayHeadline(stay: stay, place: place, count: photos.count, page: page, canvas: canvas?.color ?? Palette.paper)
                        }
                }
                LazyVStack(alignment: .leading, spacing: Metrics.stack) {
                    VStack(alignment: .leading, spacing: 4) {
                        if photos.isEmpty {
                            Text("\(stay.nights) · \(stay.dates)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text("\(Fmt.yen(stay.target)) · \(stay.range)").font(.title3.weight(.semibold)).monospacedDigit()
                    }
                    Card {
                        PlanParagraph(title: "Phòng", text: stay.room)
                        Divider()
                        PlanParagraph(title: "Điểm tốt", text: stay.good)
                        Divider()
                        PlanParagraph(title: "Cần biết", text: stay.know)
                        Divider()
                        PlanParagraph(title: "Đổi phương án khi", text: stay.switchAt)
                    }
                    if place != nil, photos.isEmpty {
                        NavigationLink(value: Route.place(stay.id)) {
                            Label("Ảnh, địa chỉ, giờ nhận phòng", systemImage: "info.circle")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.pressable(.bordered))
                    }
                    if let around = stay.around {
                        PlanNeighbourhood(stay: stay, around: around, mapScheme: photos.isEmpty ? nil : (canvas?.scheme ?? system))
                    }
                    AmbientCredit(photos: photos, page: page)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, photos.isEmpty ? 8 : 14)
                .padding(.bottom, 32)
            }
        }

        Group {
            if !photos.isEmpty {
                scroll
                    .ambientPage(canvas, title: title, heroFraction: Self.heroFraction)
                    .decidesTone($held, of: photos.first)
            } else {
                scroll
                    .screen()
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .toolbar { CloseButton() }
    }
}

/// Centred where the photograph dissolves: page dots, the hotel's name in both scripts, the nights,
/// then the map, walking there, and the hotel's own card (photographs, address, check-in).
private struct PlanStayHeadline: View {
    @Environment(AppModel.self) private var model
    let stay: StayPlan
    let place: Place?
    let count: Int
    let page: Int
    let canvas: Color

    var body: some View {
        VStack(spacing: 5) {
            if count > 1 {
                AmbientDots(count: count, current: page)
                    .padding(.bottom, 6)
            }
            Text(place?.name ?? "Chỗ ở")
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let ja = place?.ja {
                Text(ja)
                    .font(.mincho(20, bold: false, relativeTo: .title3))
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("\(stay.nights) · \(stay.dates)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let place {
                HStack(spacing: 16) {
                    Button {
                        model.mapFocus = place.id
                        model.dismissSheets()
                        model.tab = .map
                    } label: {
                        AmbientDisc(symbol: "map")
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("Bản đồ")
                    Button {
                        model.walk(to: place.id)
                    } label: {
                        Label("Đi bộ", systemImage: "figure.walk")
                            .font(.headline)
                            .foregroundStyle(canvas)
                            .frame(width: 168, height: 50)
                            .background(Color.primary, in: .capsule)
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.pressable)
                    NavigationLink(value: Route.place(place.id)) { AmbientDisc(symbol: "info") }
                        .buttonStyle(.pressable)
                        .accessibilityLabel("Ảnh, địa chỉ, giờ nhận phòng")
                }
                .labelStyle(.titleAndIcon)
                .padding(.top, 12)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 10)
    }
}

private struct PlanNeighbourhood: View {
    @Environment(AppModel.self) private var model
    let stay: StayPlan
    let around: StayAround
    /// the album page's light or dark, which the map's picture is drawn in; nil without photographs
    var mapScheme: ColorScheme?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Quanh khách sạn")
                StaticTripMap(content: content, insets: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), frameID: stay.id, scheme: mapScheme)
                    .frame(height: 300)
                    .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                if let area = around.area { Text(area).font(.body) }
            }
            if !around.walks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Đi dạo từ cửa")
                    ForEach(Array(around.walks.enumerated()), id: \.element.id) { i, walk in
                        PlanWalkCard(stay: stay.id, walk: walk, color: Color(hex: planWalkColors[i % planWalkColors.count]))
                    }
                }
            }
            if !around.around.isEmpty { PlanAmenities(amenities: around.around) }
            if let fuji = around.fuji { PlanRyokanFuji(fuji: fuji) }
            PlanLinkChips(sources: around.sources)
        }
    }

    /// Walk loops in their colours, what they pass, and the practical places near the door.
    private var content: MapContent {
        var routes: [MapRoute] = []
        var pins: [MapPin] = []
        for (i, w) in around.walks.enumerated() {
            if let p = w.p {
                routes.append(MapRoute(id: w.id, points: Polyline.decode(p), color: planWalkColors[i % planWalkColors.count], width: 4))
            }
            for (k, h) in w.highlights.enumerated() {
                pins.append(MapPin(id: "\(w.id)-h\(k)", coordinate: Coordinate(h.lat, h.lng), kind: .highlight, label: h.name))
            }
        }
        for (k, a) in around.around.enumerated() {
            pins.append(MapPin(id: "\(stay.id)-a\(k)", coordinate: Coordinate(a.lat, a.lng), kind: .along, label: a.name))
        }
        if let hotel = model.store.place(stay.id) {
            pins.append(MapPin(id: hotel.id, coordinate: hotel.coordinate, kind: .stay, label: hotel.name))
        }
        return MapContent(routes: routes, pins: pins)
    }
}

private struct PlanWalkCard: View {
    @Environment(AppModel.self) private var model
    let stay: String
    let walk: StayAround.Walk
    let color: Color

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(walk.title).font(.headline)
            }
            HStack(spacing: 6) {
                if let best = walk.best { Tag(text: best, symbol: "clock") }
                if let minutes = walk.walk.map({ Double($0.min) }) ?? walk.minutes.map(Double.init) {
                    Tag(text: Fmt.duration(minutes), symbol: "figure.walk")
                }
                if let km = walk.walk?.km ?? walk.km { Tag(text: Fmt.km(km)) }
                if let up = walk.walk?.up, up >= 20 { Tag(text: "lên \(Int(up)) m", symbol: "arrow.up.right") }
            }
            Text(walk.text).font(.subheadline)
            // each sight on the way opens its own page: the place's, when the trip already has it
            ForEach(Array(walk.highlights.enumerated()), id: \.offset) { k, h in
                Divider()
                NavigationLink(value: planHighlightRoute(stay: stay, walk: walk, index: k, store: model.store)) {
                    PlanHighlightRow(highlight: h)
                }
                .buttonStyle(.pressable(.plain))
            }
        }
    }
}

private struct PlanHighlightRow: View {
    let highlight: StayAround.Walk.Highlight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let photo = highlight.images.first {
                PlacePhoto(photo: photo, maxPixel: 240)
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(highlight.name).font(.subheadline.weight(.semibold))
                if let ja = highlight.ja { Text(ja).font(.caption).foregroundStyle(.secondary) }
                if let text = highlight.text { Text(text).font(.caption).multilineTextAlignment(.leading) }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.forward")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
                .accessibilityHidden(true)
        }
        .contentShape(.rect)
    }
}

/// A sight on a walk opens the trip's own page for it when there is one (a sight within 30 m:
/// the walks were written round the same places), otherwise a page of its own.
func planHighlightRoute(stay: String, walk: StayAround.Walk, index: Int, store: TripStore) -> Route {
    let h = walk.highlights[index]
    let here = Coordinate(h.lat, h.lng)
    let near = store.places.values
        .filter { $0.kind == .sight }
        .map { (place: $0, m: Geo.km(here, $0.coordinate) * 1000) }
        .filter { $0.m <= 30 }
        .min { $0.m < $1.m }
    if let near { return .place(near.place.id) }
    return .highlight(stay: stay, walk: walk.id, index: index)
}

private struct PlanAmenities: View {
    let amenities: [StayAround.Amenity]

    private static let order = ["konbini", "supermarket", "drugstore", "laundry", "cafe", "bakery", "sento", "sight"]
    private static let names = ["konbini": "Cửa hàng tiện lợi", "supermarket": "Siêu thị", "drugstore": "Hiệu thuốc",
                                "laundry": "Giặt tự động", "cafe": "Cà phê", "bakery": "Tiệm bánh",
                                "sento": "Nhà tắm công cộng", "sight": "Chỗ ngắm"]

    var body: some View {
        let groups = Dictionary(grouping: amenities, by: \.type)
        let types = groups.keys.sorted { (Self.order.firstIndex(of: $0) ?? 99, $0) < (Self.order.firstIndex(of: $1) ?? 99, $1) }
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Gần cửa")
            Card {
                ForEach(Array(types.enumerated()), id: \.element) { i, type in
                    if i > 0 { Divider() }
                    Text(Self.names[type] ?? type.capitalized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(groups[type] ?? [], id: \.self) { a in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(a.name).font(.subheadline.weight(.semibold))
                                if let text = a.text ?? a.note { Text(text).font(.caption).foregroundStyle(.secondary) }
                                if let hours = a.hours { Text(hours).font(.caption).foregroundStyle(.secondary) }
                            }
                            Spacer(minLength: 0)
                            if let m = a.walkMin { Text("\(m) phút").font(.subheadline).monospacedDigit().foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}

/// The ryokan's Fuji research: can it be seen from the property, and where nearby it can.
private struct PlanRyokanFuji: View {
    let fuji: JSONValue

    var body: some View {
        let summary = fuji["fromProperty"]?["summary"]?.string
        let views = fuji["nearbyViews"]?.array ?? []
        let sunrise = fuji["sunrise"]?["text"]?.string
        if summary != nil || !views.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Fuji quanh ryokan")
                Card {
                    if let summary { Text(summary).font(.subheadline) }
                    if let sunrise {
                        Divider()
                        PlanParagraph(title: "Mặt trời mọc", text: sunrise)
                    }
                    ForEach(Array(views.enumerated()), id: \.offset) { _, v in
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(v["name"]?.string ?? "").font(.subheadline.weight(.semibold))
                                if let visible = v["sight"]?["visible"]?.bool {
                                    Tag(text: visible ? "Thấy đỉnh" : "Bị che", symbol: visible ? "eye" : "eye.slash", tint: visible ? .indigo : .secondary)
                                }
                            }
                            if let access = v["access"]?.string {
                                PlanInfoRow(symbol: "figure.hiking", text: access)
                            }
                            if let text = v["text"]?.string { Text(text).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - A sight on a walk

/// A sight on one of a hotel's walks that the trip has no page of its own for: what it is, which
/// walk passes it and how far it is from the door, on the album page when it has photographs.
struct StayHighlightView: View {
    @Environment(AppModel.self) private var model
    let stay: String
    let walk: String
    let index: Int

    var body: some View {
        if let s = model.guide.stays.first(where: { $0.id == stay }),
           let w = s.around?.walks.first(where: { $0.id == walk }),
           w.highlights.indices.contains(index) {
            PlanHighlightContent(stay: s, walk: w, index: index)
        } else {
            ContentUnavailableView("Không có điểm này", systemImage: "mappin.slash")
        }
    }
}

private struct PlanHighlightContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var system
    let stay: StayPlan
    let walk: StayAround.Walk
    let index: Int
    @State private var page = 0
    /// the page's colour, from its first photograph, held while the page lives
    @State private var held: PageTone

    /// the hero's share of the page's height
    static let heroFraction: CGFloat = 0.58

    init(stay: StayPlan, walk: StayAround.Walk, index: Int) {
        self.stay = stay
        self.walk = walk
        self.index = index
        let first = walk.highlights.indices.contains(index) ? walk.highlights[index].images.first : nil
        _held = State(initialValue: PageTone(first))
    }

    private var highlight: StayAround.Walk.Highlight { walk.highlights[index] }

    /// The first photograph decides light or dark and the hue for the whole page.
    private var canvas: AmbientCanvas? {
        held.canvas(dim: system == .dark)
    }

    var body: some View {
        let h = highlight
        let photos = h.images
        let scroll = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !photos.isEmpty {
                    AmbientHero(photos: photos, page: $page)
                        .heroFrame(fraction: Self.heroFraction)
                        .overlay(alignment: .bottom) {
                            PlanHighlightHeadline(highlight: h, walk: walk, count: photos.count, page: page, canvas: canvas?.color ?? Palette.paper)
                        }
                }
                LazyVStack(alignment: .leading, spacing: Metrics.stack) {
                    if photos.isEmpty {
                        PlanHighlightHeadline(highlight: h, walk: walk, count: 0, page: 0, canvas: Palette.paper)
                            .padding(.top, 8)
                    }
                    if let text = h.text {
                        Card { Text(text).font(.body) }
                    }
                    Card {
                        PlanInfoRow(symbol: "figure.walk", text: walk.title, label: "Trên vòng đi bộ")
                        if let best = walk.best { PlanInfoRow(symbol: "clock", text: best, label: "Lúc nên đi") }
                        if let hotel = model.store.place(stay.id) {
                            let km = Geo.km(hotel.coordinate, Coordinate(h.lat, h.lng))
                            PlanInfoRow(symbol: "bed.double", text: "\(Fmt.km(km)) đường chim bay từ \(hotel.name)", label: "Cách khách sạn")
                        }
                    }
                    StaticTripMap(content: content, insets: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), frameID: "\(walk.id)-\(index)",
                                  scheme: photos.isEmpty ? nil : (canvas?.scheme ?? system))
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                    if walk.highlights.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle("Cũng trên đường này")
                            Card {
                                ForEach(Array(walk.highlights.enumerated()).filter { $0.offset != index }, id: \.offset) { k, other in
                                    if k != (index == 0 ? 1 : 0) { Divider() }
                                    NavigationLink(value: planHighlightRoute(stay: stay.id, walk: walk, index: k, store: model.store)) {
                                        PlanHighlightRow(highlight: other)
                                    }
                                    .buttonStyle(.pressable(.plain))
                                }
                            }
                        }
                    }
                    AmbientCredit(photos: photos, page: page)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, photos.isEmpty ? 0 : 14)
                .padding(.bottom, 32)
            }
        }

        Group {
            if !photos.isEmpty {
                scroll
                    .ambientPage(canvas, title: h.name, heroFraction: Self.heroFraction)
                    .decidesTone($held, of: photos.first)
            } else {
                scroll
                    .screen()
                    .navigationTitle(h.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .toolbar { CloseButton() }
    }

    /// The walk's loop in its colour, its sights, this one picked out, and the hotel.
    private var content: MapContent {
        let colorIndex = stay.around?.walks.firstIndex { $0.id == walk.id } ?? 0
        var routes: [MapRoute] = []
        if let p = walk.p {
            routes.append(MapRoute(id: walk.id, points: Polyline.decode(p), color: planWalkColors[colorIndex % planWalkColors.count], width: 4))
        }
        var pins = walk.highlights.enumerated().map { k, h in
            MapPin(id: "\(walk.id)-h\(k)", coordinate: Coordinate(h.lat, h.lng), kind: k == index ? .stop : .highlight, label: h.name)
        }
        if let hotel = model.store.place(stay.id) {
            pins.append(MapPin(id: hotel.id, coordinate: hotel.coordinate, kind: .stay, label: hotel.name))
        }
        return MapContent(routes: routes, pins: pins)
    }
}

/// Centred where the photograph dissolves (or at the top, without one): the sight's name in both
/// scripts, the walk it is on, and walking there.
private struct PlanHighlightHeadline: View {
    @Environment(AppModel.self) private var model
    let highlight: StayAround.Walk.Highlight
    let walk: StayAround.Walk
    let count: Int
    let page: Int
    let canvas: Color

    var body: some View {
        VStack(spacing: 5) {
            if count > 1 {
                AmbientDots(count: count, current: page)
                    .padding(.bottom, 6)
            }
            Text(highlight.name)
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let ja = highlight.ja {
                Text(ja)
                    .font(.mincho(20, bold: false, relativeTo: .title3))
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(walk.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button {
                model.walk(to: Coordinate(highlight.lat, highlight.lng), named: highlight.ja ?? highlight.name)
            } label: {
                Label("Đi bộ", systemImage: "figure.walk")
                    .font(.headline)
                    .foregroundStyle(canvas)
                    .frame(width: 168, height: 50)
                    .background(Color.primary, in: .capsule)
                    .contentShape(.capsule)
            }
            .buttonStyle(.pressable)
            .labelStyle(.titleAndIcon)
            .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 10)
    }
}

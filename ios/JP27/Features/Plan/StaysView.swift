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
                    .buttonStyle(.plain)
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
            PlanStayContent(stay: stay)
        } else {
            ContentUnavailableView("Không có chỗ ở này", systemImage: "bed.double")
        }
    }
}

private let planWalkColors = ["#2F7DE1", "#E9792B", "#1E8A55", "#8A5CD0"]

private struct PlanStayContent: View {
    @Environment(AppModel.self) private var model
    let stay: StayPlan

    var body: some View {
        let place = model.store.place(stay.id)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.stack) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(stay.nights) · \(stay.dates)").font(.subheadline).foregroundStyle(.secondary)
                    Text("\(Fmt.yen(stay.target)) · \(stay.range)").font(.title3.weight(.semibold)).monospacedDigit()
                }
                .padding(.top, 8)
                Card {
                    PlanParagraph(title: "Phòng", text: stay.room)
                    Divider()
                    PlanParagraph(title: "Điểm tốt", text: stay.good)
                    Divider()
                    PlanParagraph(title: "Cần biết", text: stay.know)
                    Divider()
                    PlanParagraph(title: "Đổi phương án khi", text: stay.switchAt)
                }
                if place != nil {
                    NavigationLink(value: Route.place(stay.id)) {
                        Label("Ảnh, địa chỉ, giờ nhận phòng", systemImage: "info.circle")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                if let around = stay.around {
                    PlanNeighbourhood(stay: stay, around: around)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
        .navigationTitle(place?.name ?? "Chỗ ở")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlanNeighbourhood: View {
    @Environment(AppModel.self) private var model
    let stay: StayPlan
    let around: StayAround

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Quanh khách sạn")
                TripMap(content: content, showsUser: false, insets: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), frameID: stay.id)
                    .frame(height: 300)
                    .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                if let area = around.area { Text(area).font(.body) }
            }
            if !around.walks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Đi dạo từ cửa")
                    ForEach(Array(around.walks.enumerated()), id: \.element.id) { i, walk in
                        PlanWalkCard(walk: walk, color: Color(hex: planWalkColors[i % planWalkColors.count]))
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
            ForEach(walk.highlights, id: \.self) { h in
                Divider()
                HStack(alignment: .top, spacing: 12) {
                    if let photo = h.images.first {
                        PlacePhoto(photo: photo, maxPixel: 240)
                            .frame(width: 72, height: 72)
                            .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.name).font(.subheadline.weight(.semibold))
                        if let ja = h.ja { Text(ja).font(.caption).foregroundStyle(.secondary) }
                        if let text = h.text { Text(text).font(.caption) }
                    }
                }
            }
        }
    }
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

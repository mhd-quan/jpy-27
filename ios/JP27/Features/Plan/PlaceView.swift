import SwiftUI
import TripKit
import UIKit

/// A place: photos, what it is, how to get there and talk there, what to order, when it is in the plan.
struct PlaceView: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        if let place = model.store.place(id) {
            PlanPlaceContent(place: place)
        } else {
            ContentUnavailableView("Không có địa điểm này", systemImage: "mappin.slash")
        }
    }
}

private struct PlanPlaceContent: View {
    @Environment(AppModel.self) private var model
    let place: Place

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                if !place.images.isEmpty { PlanPlacePhotos(photos: place.images) }
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    PlanPlaceTitle(place: place)
                    PlanPlaceActions(place: place)
                    PlanPlaceFacts(place: place)
                    if let menu = place.menu { PlanPlaceMenuSection(place: place, menu: menu) }
                    if let snack = place.snack { PlanPlaceSnack(snack: snack) }
                    if let store = place.store { PlanPlaceStore(store: store) }
                    PlanPlaceFuji(place: place)
                    if place.kind == .stay, model.guide.stays.contains(where: { $0.id == place.id }) {
                        NavigationLink(value: Route.stay(place.id)) {
                            Label("Quanh khách sạn", systemImage: "figure.walk.circle")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                    }
                    PlanPlaceUses(place: place)
                    PlanLinkChips(links: sources)
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .padding(.bottom, 32)
        }
        .screen()
        .navigationTitle(place.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.present(.expense(placeID: place.id, yen: nil), from: "place.\(place.id).expense")
                } label: {
                    Label("Ghi chi", systemImage: "yensign")
                }
                .sheetSource("place.\(place.id).expense")
            }
        }
    }

    private var sources: [(title: String, url: String)] {
        var out: [(title: String, url: String)] = []
        if let u = place.official { out.append(("Trang chính thức", u)) }
        if let u = place.tabelog ?? place.snack?.tabelog?.url { out.append(("Tabelog", u)) }
        if let u = place.review { out.append((planSourceLabel(u) == "Web" ? "Đánh giá" : planSourceLabel(u), u)) }
        for s in (place.snack?.social ?? []) + (place.fujiSpot?.social ?? []) {
            out.append((planSourceLabel(s.url), s.url))
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.url).inserted }
    }
}

// MARK: - Photos

private struct PlanPlacePhotos: View {
    let photos: [Photo]
    @State private var page = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TabView(selection: $page) {
                ForEach(Array(photos.enumerated()), id: \.offset) { i, photo in
                    PlacePhoto(photo: photo)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
            .frame(height: 300)
            // the photo carries on, mirrored and blurred, under the bar above it
            .backgroundExtensionEffect()
            if photos.indices.contains(page) {
                let p = photos[page]
                VStack(alignment: .leading, spacing: 2) {
                    if let caption = p.caption { Text(caption).font(.footnote) }
                    if let credit = p.credit {
                        Button {
                            if let page = p.page, let url = URL(string: page) { openURL(url) }
                        } label: {
                            Text(["© \(credit)", p.license].compactMap { $0 }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .disabled(p.page == nil)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
            }
        }
    }
}

// MARK: - Title and actions

private struct PlanPlaceTitle: View {
    @Environment(AppModel.self) private var model
    let place: Place

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(place.name).font(.title.weight(.bold))
            if let ja = place.ja {
                Text(ja)
                    .font(.title2)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .textSelection(.enabled)
            }
            HStack(spacing: 6) {
                Tag(text: kindLabel, symbol: place.kind.symbol)
                Tag(text: areaLabel)
                if model.store.reserved.contains(place.id) { Tag(text: "Đã đặt", symbol: "checkmark.seal.fill", tint: .green) }
            }
            if place.rating != nil || place.snack?.tabelog?.rating != nil || place.snack?.tabelog?.award != nil {
                HStack(spacing: 6) {
                    if let rating = place.rating ?? place.snack?.tabelog?.rating {
                        Tag(text: (place.kind == .food ? "Tabelog " : "") + Fmt.decimal(rating, digits: 2) + (ratingCount.map { " (\(Fmt.grouped($0)))" } ?? ""), symbol: "star.fill", tint: .orange)
                    }
                    if let award = place.snack?.tabelog?.award {
                        Tag(text: award, symbol: "rosette", tint: .orange)
                    }
                }
            }
        }
    }

    private var ratingCount: Int? {
        place.ratingCount ?? place.snack?.tabelog?.count
    }

    private var kindLabel: String {
        switch place.kind {
        case .stay: "Chỗ ở"
        case .food: place.snack != nil ? "Ăn vặt" : "Quán ăn"
        case .sight: "Tham quan"
        case .shop: "Cửa hàng"
        case .station: "Ga"
        }
    }

    private var areaLabel: String {
        let names = ["tokyo": "Tokyo", "hakone": "Hakone", "tokaido": "Tōkaidō", "ise": "Ise", "toba": "Toba", "shima": "Shima",
                     "kyoto": "Kyoto", "nara": "Nara", "osaka": "Osaka", "kawaguchiko": "Kawaguchiko"]
        return names[place.area] ?? place.area.capitalized
    }
}

private struct PlanPlaceActions: View {
    @Environment(AppModel.self) private var model
    let place: Place

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.walk(to: place.id)
                } label: {
                    Label("Đi bộ", systemImage: "figure.walk").frame(maxWidth: .infinity)
                }
                Button {
                    model.mapFocus = place.id
                    model.dismissSheets()
                    model.tab = .map
                } label: {
                    Label("Bản đồ", systemImage: "map").frame(maxWidth: .infinity)
                }
                talk
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder
    private var talk: some View {
        if place.kind == .food || place.kind == .shop {
            Button {
                model.present(.atPlace(place.id), from: "place.\(place.id).talk")
            } label: {
                Label("Nói", systemImage: "character.bubble").frame(maxWidth: .infinity)
            }
            .sheetSource("place.\(place.id).talk")
        } else if let scenario = model.store.scenarios(for: place).first {
            NavigationLink(value: Route.scenario(scenario.id)) {
                Label("Nói", systemImage: "character.bubble").frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Facts

private struct PlanPlaceFacts: View {
    let place: Place
    @State private var copied = false

    var body: some View {
        let rows = facts
        if place.note != nil || place.tips != nil || !rows.isEmpty {
            Card {
                if let note = place.note { Text(note).font(.body) }
                if let tips = place.tips {
                    Label {
                        Text(tips).font(.subheadline)
                    } icon: {
                        Image(systemName: "lightbulb").foregroundStyle(.orange)
                    }
                }
                if !rows.isEmpty, place.note != nil || place.tips != nil { Divider() }
                ForEach(rows, id: \.label) { row in
                    PlanInfoRow(symbol: row.symbol, text: row.text, label: row.label)
                }
                if let address = place.address {
                    Button {
                        UIPasteboard.general.string = address
                        copied = true
                    } label: {
                        PlanInfoRow(symbol: copied ? "checkmark" : "doc.on.doc", text: address, label: copied ? "Đã chép địa chỉ" : "Địa chỉ")
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: copied)
                }
            }
        }
    }

    private var facts: [(symbol: String, label: String, text: String)] {
        var out: [(symbol: String, label: String, text: String)] = []
        if let dish = place.dish { out.append(("fork.knife", "Gọi gì", dish)) }
        if let price = place.price { out.append(("yensign.circle", "Giá mỗi người", price)) }
        if let hours = place.hours { out.append(("clock", "Giờ mở", hours)) }
        if let closed = place.closed { out.append(("calendar.badge.minus", "Nghỉ", closed)) }
        if let fee = place.fee { out.append(("ticket", "Vé", fee)) }
        if let best = place.bestTime { out.append(("sun.max", "Lúc nên tới", best)) }
        if let station = place.station { out.append(("tram", "Ga gần", station)) }
        switch place.payment {
        case .cash: out.append(("banknote", "Thanh toán", "Chỉ tiền mặt"))
        case .card: out.append(("creditcard", "Thanh toán", "Trả thẻ được"))
        case .mixed: out.append(("banknote", "Thanh toán", "Tiền mặt hoặc thẻ, tuỳ món"))
        case nil: break
        }
        return out
    }
}

// MARK: - Menu

private struct PlanPlaceMenuSection: View {
    @Environment(AppModel.self) private var model
    let place: Place
    let menu: PlaceMenu

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Món nên gọi", trailing: Spend.estimate(stop: stop, place: place, people: model.people).map { "Dự kiến \($0.label)" })
            Card {
                let flags = tags
                if !flags.isEmpty { HStack(spacing: 6) { ForEach(flags, id: \.text) { $0 } } }
                if let tip = menu.orderTip {
                    Label {
                        Text(tip).font(.subheadline)
                    } icon: {
                        Image(systemName: "text.bubble").foregroundStyle(.secondary)
                    }
                }
                PlanRows(items: menu.items.sorted { $0.rank < $1.rank }) { item in
                    DishRow(item: item)
                }
            }
            Button {
                model.present(.menuScan(place.id), from: "place.\(place.id).scan")
            } label: {
                Label("Quét thực đơn", systemImage: "text.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .sheetSource("place.\(place.id).scan")
        }
    }

    /// The plan's stop at this place, for its cost.
    private var stop: Stop? {
        for day in model.store.trip.days + model.store.trip.altDays {
            if let s = day.stops.first(where: { $0.stop.place == place.id && $0.stop.cost != nil }) { return s.stop }
        }
        return nil
    }

    private var tags: [Tag] {
        var out: [Tag] = []
        if menu.ticketMachine == true { out.append(Tag(text: "Máy bán phiếu", symbol: "ticket", tint: .blue)) }
        if menu.menuEn == true { out.append(Tag(text: "Có menu tiếng Anh", tint: .secondary)) }
        if menu.menuEn == false { out.append(Tag(text: "Chỉ menu tiếng Nhật", tint: .orange)) }
        return out
    }
}

private struct PlanPlaceSnack: View {
    let snack: Snack

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Nên mua")
            Card {
                PlanRows(items: snack.get) { g in
                    HStack(alignment: .top) {
                        JapaneseLine(ja: g.ja, romaji: g.romaji, vi: g.vi, size: .headline)
                        Spacer(minLength: 0)
                        if let yen = g.yen { YenText(yen: yen).font(.subheadline.weight(.semibold)) }
                    }
                }
                let rows = facts
                if !rows.isEmpty { Divider() }
                ForEach(rows, id: \.label) { row in
                    PlanInfoRow(symbol: row.symbol, text: row.text, label: row.label)
                }
            }
        }
    }

    private var facts: [(symbol: String, label: String, text: String)] {
        var out: [(symbol: String, label: String, text: String)] = []
        if let when = snack.when { out.append(("clock.badge", "Lúc ghé", when)) }
        switch (snack.open, snack.close) {
        case let (o?, c?): out.append(("clock", "Giờ mở", "\(o)–\(c)"))
        case let (o?, nil): out.append(("clock", "Mở từ", o))
        default: break
        }
        if !snack.closedDow.isEmpty || snack.closedNote != nil {
            let text = [snack.closedDow.isEmpty ? nil : planWeekdays(snack.closedDow), snack.closedNote].compactMap { $0 }.joined(separator: " · ")
            out.append(("calendar.badge.minus", "Nghỉ", text))
        }
        if let q = snack.queue { out.append(("person.3", "Xếp hàng", q)) }
        switch snack.pay {
        case .cash: out.append(("banknote", "Thanh toán", "Chỉ tiền mặt"))
        case .card: out.append(("creditcard", "Thanh toán", "Trả thẻ được"))
        case .mixed: out.append(("banknote", "Thanh toán", "Tiền mặt hoặc thẻ"))
        case nil: break
        }
        return out
    }
}

private struct PlanPlaceStore: View {
    @Environment(AppModel.self) private var model
    let store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Cửa hàng")
            Card {
                if let chain = model.guide.shopping.chains.first(where: { $0.id == store.chain }) {
                    PlanParagraph(title: chain.name, text: chain.vi ?? "")
                }
                switch (store.open, store.close) {
                case let (o?, c?): PlanInfoRow(symbol: "clock", text: "\(o)–\(c)", label: "Giờ mở")
                default: EmptyView()
                }
                if !store.closedDow.isEmpty {
                    PlanInfoRow(symbol: "calendar.badge.minus", text: planWeekdays(store.closedDow), label: "Nghỉ")
                }
                if let tf = store.taxFree {
                    PlanInfoRow(symbol: "percent", text: tf ? "Có hoàn thuế" : "Không hoàn thuế", label: "Tax-free")
                }
                if let near = store.near, let p = model.store.place(near) {
                    PlanInfoRow(symbol: "figure.walk", text: "\(p.name)" + (store.walkMin.map { " · \($0) phút đi bộ" } ?? ""), label: "Gần")
                }
            }
        }
    }
}

// MARK: - Fuji

private struct PlanPlaceFuji: View {
    @Environment(AppModel.self) private var model
    let place: Place

    var body: some View {
        let spot = model.guide.fuji.spots.first { $0.id == place.id }
        if place.fujiNote != nil || spot != nil || place.fujiSpot != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Fuji")
                Card {
                    if let spot { PlanFujiSightLine(spot: spot) }
                    if let note = place.fujiNote { Text(note).font(.subheadline) }
                    if let info = place.fujiSpot {
                        if let etiquette = info.etiquette {
                            PlanInfoRow(symbol: "hand.raised", text: etiquette, label: "Lưu ý")
                        }
                        if let status = info.status {
                            PlanInfoRow(symbol: "info.circle", text: status, label: "Tình trạng")
                        }
                        ForEach((info.access ?? [:]).sorted { $0.key < $1.key }, id: \.key) { key, text in
                            PlanInfoRow(symbol: "signpost.right", text: text, label: accessLabel(key))
                        }
                        if let bus = info.busStop {
                            PlanInfoRow(symbol: "bus", text: bus.ja + (bus.walkMin.map { " · \($0) phút đi bộ" } ?? ""), label: "Bến xe")
                        }
                    }
                }
            }
        }
    }

    private func accessLabel(_ key: String) -> String {
        switch key {
        case "day4": "Từ lịch ngày 4"
        case "day5": "Từ lịch ngày 5"
        case "kawaguchiko": "Ngày Kawaguchiko"
        default: key
        }
    }
}

/// "32,7 km · Tây Bắc · thấy đỉnh, núi cao 2,4°" from the terrain computation.
struct PlanFujiSightLine: View {
    let spot: FujiGuide.Spot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Tag(text: spot.visible ? "Thấy đỉnh" : "Bị núi che", symbol: spot.visible ? "eye" : "eye.slash", tint: spot.visible ? .indigo : .secondary)
                Tag(text: "\(Fmt.km(spot.km)) · \(Geo.compass(spot.bearing))", symbol: "location.north.line")
            }
            let parts = facts
            if !parts.isEmpty {
                Text(parts.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var facts: [String] {
        var out: [String] = []
        if spot.visible {
            if let h = spot.heightDeg, h > 0 { out.append("núi cao \(Fmt.decimal(h, digits: 1))° trên chân trời") }
            if let m = spot.shownM, m > 0 { out.append("lộ \(Fmt.grouped(Int(m))) m") }
        } else if let b = spot.blockKm, b > 0 {
            out.append("sườn núi cách \(Fmt.km(b)) chắn tầm nhìn")
        }
        out.append("đứng ở độ cao \(Fmt.grouped(Int(spot.elev))) m")
        return out
    }
}

// MARK: - In the plan

private struct PlanPlaceUses: View {
    @Environment(AppModel.self) private var model
    let place: Place

    var body: some View {
        if !place.uses.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Trong lịch")
                Card {
                    PlanRows(items: place.uses) { use in
                        NavigationLink(value: Route.day(use.day)) {
                            HStack {
                                Text(planDayName(use.day, store: model.store)).font(.body.weight(.semibold))
                                if let day = model.store.day(use.day) {
                                    Text(planDateLabel(day)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let at = use.at { Text(at).monospacedDigit().foregroundStyle(.secondary) }
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

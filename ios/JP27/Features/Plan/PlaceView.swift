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
        Group {
            if planIsAmbient(place, reserved: model.store.reserved.contains(place.id)) {
                PlanAmbientPage(place: place, sources: sources)
            } else if !place.images.isEmpty {
                standard(hero: true).detailPage(title: place.name)
            } else {
                standard(hero: false)
                    .navigationTitle(place.name)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        // the page's own action, then close, always last at the trailing edge
        .toolbar {
            SheetToolbarButton(title: "Ghi chi", symbol: "yensign", source: "place.\(place.id).expense") {
                model.present(.expense(placeID: place.id, yen: nil), from: "place.\(place.id).expense")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            CloseButton()
        }
    }

    /// The page of small stops (and of places without photos): paper, cards, the photo strip on top.
    private func standard(hero: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                if hero { PlanPlaceHero(place: place) }
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    if hero {
                        PlanPlaceBadges(place: place)
                    } else {
                        PlanPlaceTitle(place: place)
                    }
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
                        .buttonStyle(.pressable(.bordered))
                    }
                    PlanPlaceUses(place: place)
                    PlanLinkChips(links: sources)
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .padding(.bottom, 32)
        }
        .screen()
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

/// The place's photographs filling the top of the page, its name and what it is on the soft blur
/// at their foot, the photographer under them.
private struct PlanPlaceHero: View {
    let place: Place
    @State private var page = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        let photos = place.images
        DetailHero(title: place.name, subtitle: place.ja) {
            TabView(selection: $page) {
                ForEach(photos.indices, id: \.self) { i in
                    PlacePhoto(photo: photos[i], maxPixel: 1800)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .sensoryFeedback(.page, trigger: page)
        } foot: {
            HStack(alignment: .center, spacing: 8) {
                Text(placeFacts(place))
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                    .opacity(0.9)
                Spacer(minLength: 8)
                HeroDots(count: photos.count, current: page)
            }
            if photos.indices.contains(page), let credit = photos[page].credit {
                Button {
                    if let link = photos[page].page, let url = URL(string: link) { openURL(url) }
                } label: {
                    Text(["© \(credit)", photos[page].license].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .lineLimit(1)
                        .opacity(0.6)
                }
                .buttonStyle(.pressable(.plain))
                .disabled(photos[page].page == nil)
                .accessibilityLabel("Ảnh: \(credit)")
            }
        }
    }
}

// MARK: - Ambient page

/// The places that are an outing rather than a stop get the album page: every sight, stay and
/// station with photographs, the shops worth the trip, and the meals that are an occasion (booked,
/// from ¥4.000 a head, or Tabelog 3,75 and up). Snack stands, everyday lunches and chain branches
/// keep the plain page.
private func planIsAmbient(_ place: Place, reserved: Bool) -> Bool {
    guard !place.images.isEmpty else { return false }
    if place.kind == .shop {
        // a market, a street, a food hall or a craft shop is a destination; a branch of an everyday
        // chain is one only when it has photographs of its own (a flagship), not of the street
        guard let chain = place.store?.chain, planEverydayChains.contains(chain) else { return true }
        return place.images.count >= 2
    }
    guard place.kind == .food else { return true }
    if place.snack != nil { return false }
    if reserved { return true }
    if let floor = planPriceFloor(place.price), floor >= 4000 { return true }
    return (place.rating ?? 0) >= 3.75
}

/// chains whose branches are much alike (the store card still has their photographs)
private let planEverydayChains: Set<String> = ["uniqlo", "gu", "muji", "donki", "drugstore", "hands", "loft",
                                                "yodobashi", "bic", "daiso", "3coins", "shimamura", "workman"]

/// 4400 from "¥4.400–5.000"
private func planPriceFloor(_ price: String?) -> Int? {
    guard let price, let yen = price.firstIndex(of: "¥") else { return nil }
    let figure = price[price.index(after: yen)...].prefix { $0.isNumber || $0 == "." || $0 == "," }
    return Int(figure.filter(\.isNumber))
}

/// Apple Music's album page, for a place: the page is one colour taken from the photograph's
/// foot; the photograph fills the top, under the bar, and dissolves into that colour, sharp at the
/// top, blurring and fading toward the bottom; the name, what it is and the actions sit centred
/// where it dissolves. Type, cards and controls take the colour's side (dark type on a pale page,
/// white on a deep one), so the system's own styles adapt by themselves.
private struct PlanAmbientPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var system
    let place: Place
    let sources: [(title: String, url: String)]
    @State private var page = 0
    /// photo index → the colour of its foot
    @State private var tones: [Int: AmbientTone] = [:]
    @State private var heroHeight: CGFloat = 520

    /// The first photograph decides light or dark for the whole page; the others only move the hue.
    private var canvas: AmbientCanvas? {
        guard let first = tones[0] else { return nil }
        return (tones[page] ?? first).canvas(light: first.prefersLight, dim: system == .dark)
    }

    var body: some View {
        let canvas = self.canvas
        let scheme = canvas?.scheme ?? system
        let fill = canvas?.color ?? Palette.paper
        ScrollView {
            VStack(spacing: 0) {
                AmbientHero(photos: place.images, page: $page)
                    .containerRelativeFrame(.vertical) { length, _ in (length * 0.6).rounded() }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heroHeight = $0 }
                    .overlay(alignment: .bottom) {
                        PlanAmbientHeadline(place: place, count: place.images.count, page: page, canvas: fill)
                    }
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    if let note = place.note {
                        PlanAmbientNote(text: note, canvas: fill)
                    }
                    PlanPlaceFacts(place: place, showsNote: false)
                    // a hotel's round button is its phrases; the walks round it stay here, as on the plain page
                    if place.kind == .stay, model.guide.stays.contains(where: { $0.id == place.id }) {
                        NavigationLink(value: Route.stay(place.id)) {
                            Label("Quanh khách sạn", systemImage: "figure.walk.circle")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                        .buttonStyle(.pressable(.bordered))
                    }
                    if let menu = place.menu { PlanPlaceMenuSection(place: place, menu: menu) }
                    if let store = place.store { PlanPlaceStore(store: store) }
                    PlanPlaceFuji(place: place)
                    PlanPlaceUses(place: place)
                    VStack(alignment: .leading, spacing: 10) {
                        PlanLinkChips(links: sources)
                        AmbientCredit(photos: place.images, page: page)
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 14)
            }
            .padding(.bottom, 32)
        }
        .progressiveEdges()
        .background { fill.ignoresSafeArea() }
        // cards turn into tints of the page, controls into its type colour
        .environment(\.cardSurface, canvas.map { $0.light ? Color.white.opacity(0.4) : Color.white.opacity(0.09) })
        .tint(canvas == nil ? nil : Color.primary)
        .environment(\.colorScheme, scheme)
        .animation(.easeInOut(duration: 0.45), value: canvas)
        .detailPage(title: place.name, heroHeight: heroHeight, scheme: canvas?.scheme)
        .task(id: place.id) {
            let photos = place.images
            guard let first = photos.first else { return }
            // the first one now, for the page to settle on; the rest in one go after
            if let tone = await PhotoCache.shared.tone(first) { tones[0] = tone }
            var rest: [Int: AmbientTone] = [:]
            for i in photos.indices.dropFirst() {
                if let tone = await PhotoCache.shared.tone(photos[i]) { rest[i] = tone }
            }
            tones.merge(rest) { a, _ in a }
        }
    }
}



/// Centred where the photograph dissolves: page dots, the name, the Japanese name, what it is,
/// and the actions.
private struct PlanAmbientHeadline: View {
    @Environment(AppModel.self) private var model
    let place: Place
    let count: Int
    let page: Int
    let canvas: Color

    var body: some View {
        VStack(spacing: 5) {
            if count > 1 {
                AmbientDots(count: count, current: page)
                    .padding(.bottom, 6)
            }
            Text(place.name)
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            if let ja = place.ja {
                Text(ja)
                    .font(.mincho(20, bold: false, relativeTo: .title3))
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(facts)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            PlanAmbientActions(place: place, canvas: canvas)
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 10)
    }

    /// "Đã đặt · Tham quan · Kyoto · ★ 4,50 (12.000)"
    private var facts: String {
        var parts: [String] = []
        if model.store.reserved.contains(place.id) { parts.append("Đã đặt") }
        parts.append(placeFacts(place))
        if let award = place.snack?.tabelog?.award { parts.append(award) }
        return parts.joined(separator: " · ")
    }
}

/// Map on the left, walking as the one filled capsule, and on the right what else this place is
/// for: talking at the counter, the scenario for a sight, the walks round a hotel, or its day.
private struct PlanAmbientActions: View {
    @Environment(AppModel.self) private var model
    let place: Place
    let canvas: Color

    var body: some View {
        HStack(spacing: 16) {
            round("Bản đồ", symbol: "map") {
                model.mapFocus = place.id
                model.dismissSheets()
                model.tab = .map
            }
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
            trailing
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var trailing: some View {
        if place.kind == .food || place.kind == .shop {
            round("Nói ở quán", symbol: "character.bubble") {
                model.present(.atPlace(place.id), from: "place.\(place.id).talk")
            }
            .sheetSource("place.\(place.id).talk")
        } else if let scenario = model.store.scenarios(for: place).first {
            NavigationLink(value: Route.scenario(scenario.id)) { disc(symbol: "character.bubble") }
                .buttonStyle(.pressable)
                .accessibilityLabel("Câu nói")
        } else if place.kind == .stay, model.guide.stays.contains(where: { $0.id == place.id }) {
            NavigationLink(value: Route.stay(place.id)) { disc(symbol: "figure.walk.circle") }
                .buttonStyle(.pressable)
                .accessibilityLabel("Quanh khách sạn")
        } else if let use = place.uses.first {
            NavigationLink(value: Route.day(use.day)) { disc(symbol: "calendar") }
                .buttonStyle(.pressable)
                .accessibilityLabel("Ngày trong lịch")
        }
    }

    private func round(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { disc(symbol: symbol) }
            .buttonStyle(.pressable)
            .accessibilityLabel(label)
    }

    private func disc(symbol: String) -> some View {
        AmbientDisc(symbol: symbol)
    }
}


/// The description, three lines and a THÊM that opens the rest, as an album's notes.
private struct PlanAmbientNote: View {
    let text: String
    let canvas: Color
    @State private var open = false

    var body: some View {
        let long = text.count > 150
        let hint: String = long ? (open ? "Thu gọn" : "Đọc hết") : ""
        Text(text)
            .font(.subheadline)
            .lineLimit(open || !long ? nil : 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                if long, !open {
                    Text("THÊM")
                        .font(.subheadline.weight(.bold))
                        .padding(.leading, 40)
                        .background {
                            LinearGradient(stops: [.init(color: canvas.opacity(0), location: 0), .init(color: canvas, location: 0.55)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
            .onTapGesture {
                guard long else { return }
                withAnimation(.smooth(duration: 0.3)) { open.toggle() }
            }
            // opening the rest answers; folding it back stays quiet
            .sensoryFeedback(.press, trigger: open) { _, now in now }
            .accessibilityAddTraits(long ? .isButton : [])
            .accessibilityHint(hint)
    }
}


/// "Quán ăn · Tokyo · ★ Tabelog 3,63 (942)"
private func placeFacts(_ place: Place) -> String {
    var parts = [placeKindLabel(place), placeAreaLabel(place)]
    if let rating = place.rating ?? place.snack?.tabelog?.rating {
        let count = (place.ratingCount ?? place.snack?.tabelog?.count).map { " (\(Fmt.grouped($0)))" } ?? ""
        parts.append("★ " + (place.kind == .food ? "Tabelog " : "") + Fmt.decimal(rating, digits: 2) + count)
    }
    return parts.joined(separator: " · ")
}

private func placeKindLabel(_ place: Place) -> String {
    switch place.kind {
    case .stay: "Chỗ ở"
    case .food: place.snack != nil ? "Ăn vặt" : "Quán ăn"
    case .sight: "Tham quan"
    case .shop: "Cửa hàng"
    case .station: "Ga"
    }
}

private func placeAreaLabel(_ place: Place) -> String {
    let names = ["tokyo": "Tokyo", "hakone": "Hakone", "tokaido": "Tōkaidō", "ise": "Ise", "toba": "Toba", "shima": "Shima",
                 "kyoto": "Kyoto", "nara": "Nara", "osaka": "Osaka", "kawaguchiko": "Kawaguchiko"]
    return names[place.area] ?? place.area.capitalized
}

/// Under a hero, only what the foot does not say: booked, an award.
private struct PlanPlaceBadges: View {
    @Environment(AppModel.self) private var model
    let place: Place

    var body: some View {
        let reserved = model.store.reserved.contains(place.id)
        let award = place.snack?.tabelog?.award
        if reserved || award != nil {
            HStack(spacing: 6) {
                if reserved { Tag(text: "Đã đặt", symbol: "checkmark.seal.fill", tint: Palette.matcha) }
                if let award { Tag(text: award, symbol: "rosette", tint: Place.Kind.food.tint) }
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
                Tag(text: placeKindLabel(place), symbol: place.kind.symbol)
                Tag(text: placeAreaLabel(place))
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
            .buttonStyle(.pressable(.glass))
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
    /// the ambient page sets the note as its description, above the cards
    var showsNote = true
    @State private var copied = false

    var body: some View {
        let rows = facts
        let note = showsNote ? place.note : nil
        if note != nil || place.tips != nil || !rows.isEmpty {
            Card {
                if let note { Text(note).font(.body) }
                if let tips = place.tips {
                    Label {
                        Text(tips).font(.subheadline)
                    } icon: {
                        Image(systemName: "lightbulb").foregroundStyle(.orange)
                    }
                }
                if !rows.isEmpty, note != nil || place.tips != nil { Divider() }
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
                    .sensoryFeedback(.done, trigger: copied)
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
            .buttonStyle(.pressable(.bordered))
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
                if !store.buy.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Nên tìm").font(.subheadline.weight(.semibold))
                        PlanBullets(lines: store.buy)
                    }
                }
                if let advice = store.advice {
                    PlanInfoRow(symbol: "lightbulb", text: advice, label: "Mẹo")
                }
                if let plan = store.plan {
                    PlanInfoRow(symbol: "calendar", text: plan, label: "Trong lịch")
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
                        .buttonStyle(.pressable(.plain))
                    }
                }
            }
        }
    }
}

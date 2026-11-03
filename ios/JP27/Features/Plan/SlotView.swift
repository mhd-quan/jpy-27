import SwiftUI
import TripKit

/// A shopping window of the plan: when, where, in which order, which stores, and what they sell
/// from the list.
struct SlotView: View {
    @Environment(AppModel.self) private var model
    let id: String

    var body: some View {
        if let slot = model.guide.shopping.slots.first(where: { $0.id == id }) {
            PlanSlotContent(slot: slot)
        } else {
            ContentUnavailableView("Không có khung mua sắm này", systemImage: "bag")
        }
    }
}

private struct PlanSlotContent: View {
    @Environment(AppModel.self) private var model
    let slot: Shopping.Slot

    private var stores: [Place] { slot.stores.compactMap { model.store.place($0) } }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.stack) {
                PlanSlotHeader(slot: slot)
                StaticTripMap(content: content, insets: UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), frameID: slot.id)
                    .frame(height: 260)
                    .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                if slot.focus != nil || slot.why != nil || slot.skipIf != nil {
                    Card {
                        if let focus = slot.focus { Text(focus).font(.body) }
                        if let why = slot.why { PlanInfoRow(symbol: "info.circle", text: why, label: "Vì sao lúc này") }
                        if let skip = slot.skipIf { PlanInfoRow(symbol: "forward", text: skip, label: "Bỏ khi") }
                    }
                }
                if !stores.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Cửa hàng", trailing: "\(stores.count)")
                        Card {
                            PlanRows(items: Array(stores.enumerated())) { pair in
                                NavigationLink(value: Route.place(pair.element.id)) {
                                    HStack(spacing: 10) {
                                        Text("\(pair.offset + 1)")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 22, height: 22)
                                            .background(Color.accentColor, in: .circle)
                                        PlaceRow(place: pair.element, detail: storeDetail(pair.element))
                                    }
                                }
                                .buttonStyle(.pressable(.plain))
                            }
                        }
                    }
                }
                PlanSlotItems(ids: slot.items)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
        .navigationTitle(slot.area ?? "Mua sắm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func storeDetail(_ p: Place) -> String? {
        var parts: [String] = []
        if let s = p.store {
            if let o = s.open, let c = s.close { parts.append("\(o)–\(c)") }
            if !s.closedDow.isEmpty { parts.append("nghỉ \(planWeekdays(s.closedDow))") }
            if s.taxFree == true { parts.append("tax-free") }
        } else if let hours = p.hours {
            parts.append(hours)
        }
        return parts.isEmpty ? p.ja : parts.joined(separator: " · ")
    }

    /// The walk between stores and the stores in order.
    private var content: MapContent {
        let routes = (slot.route?.p ?? []).enumerated().map { i, p in
            MapRoute(id: "\(slot.id)-\(i)", points: Polyline.decode(p), color: "#8E8E93", width: 3.5, dashed: true)
        }
        let pins = stores.enumerated().map { i, p in
            MapPin(id: p.id, coordinate: p.coordinate, kind: .stop, label: p.name, number: i + 1)
        }
        return MapContent(routes: routes, pins: pins)
    }
}

private struct PlanSlotHeader: View {
    @Environment(AppModel.self) private var model
    let slot: Shopping.Slot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let day = model.store.day(String(slot.day)) {
                Text("\(planDateLabel(day)) · Ngày \(day.n)").font(.subheadline).foregroundStyle(.secondary)
            }
            Text(time).font(.title2.weight(.bold)).monospacedDigit()
            Text([slot.city, slot.area].compactMap { $0 }.joined(separator: " · ")).font(.headline)
            let order = [slot.after.flatMap { model.store.place($0)?.name }.map { "sau \($0)" },
                         slot.before.flatMap { model.store.place($0)?.name }.map { "trước \($0)" }].compactMap { $0 }
            if !order.isEmpty {
                Text(order.joined(separator: ", ").capitalizedFirst).font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                if let r = slot.route {
                    Tag(text: Fmt.km(r.km), symbol: "figure.walk")
                    Tag(text: Fmt.duration(Double(r.min)), symbol: "clock")
                }
            }
        }
        .padding(.top, 8)
    }

    private var time: String {
        switch (slot.start, slot.end) {
        case let (a?, b?): "\(a)–\(b)"
        case let (a?, nil): a
        default: ""
        }
    }
}

/// Items from the list these stores sell.
private struct PlanSlotItems: View {
    @Environment(AppModel.self) private var model
    let ids: [String]

    var body: some View {
        let catalog = Dictionary(model.guide.shopping.categories.flatMap(\.items).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items = ids.compactMap { catalog[$0] }
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Mua được ở đây", trailing: "\(items.count)")
                Card {
                    PlanRows(items: items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline.weight(.semibold))
                                if let ja = item.ja { Text(ja).font(.caption).foregroundStyle(.secondary) }
                                if let note = item.yenNote ?? item.tip { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            }
                            Spacer(minLength: 0)
                            if let yen = item.yen { YenText(yen: yen).font(.subheadline.weight(.semibold)) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }
}

private extension String {
    /// "sau Manseibashi" → "Sau Manseibashi"
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

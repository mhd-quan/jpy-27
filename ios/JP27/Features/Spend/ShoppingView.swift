import SwiftData
import SwiftUI
import TripKit

/// Mua sắm: the basket with what is already bought, the shopping windows the plan leaves day by day,
/// and the researched catalogue. Ticking an item asks what it really cost and logs it.
struct ShoppingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var purchases: [Purchase]
    @State private var buying: SpendBuyItem?
    @Environment(\.zoomSpace) private var space
    @State private var bought = 0

    private var guide: Guide { model.guide }
    private var owned: [String: Purchase] { Dictionary(purchases.map { ($0.itemID, $0) }, uniquingKeysWith: { a, _ in a }) }

    var body: some View {
        let owned = self.owned
        List {
            Section { progress(owned) }
            ForEach(guide.basket.groups) { group in
                let items = guide.basket.items.filter { $0.group == group.id }
                if !items.isEmpty {
                    Section(group.label) {
                        ForEach(items) { item in basketRow(item, purchase: owned[item.id]) }
                    }
                }
            }
            slots
            Section("Mua gì") {
                ForEach(guide.shopping.categories) { c in
                    DisclosureGroup {
                        ForEach(c.items) { item in catalogRow(item, purchase: owned[item.id]) }
                    } label: {
                        HStack {
                            Text(c.vi)
                            Spacer()
                            let n = c.items.filter { owned[$0.id] != nil }.count
                            if n > 0 { Text("\(n)/\(c.items.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit() }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .paperList()
        .navigationTitle("Mua sắm")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $buying) { item in
            SpendBuySheet(item: item) { bought += 1 }
                .zoomed(from: item.source, in: space)
        }
        .sensoryFeedback(.success, trigger: bought)
    }

    // MARK: Basket

    private func progress(_ owned: [String: Purchase]) -> some View {
        let total = guide.basket.total
        let spent = guide.basket.items.reduce(0) { sum, item in sum + (owned[item.id].map { $0.yen ?? item.total } ?? 0) }
        let planned = guide.budget.lines.first { $0.id == "shop" }?.yen ?? total
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.yen(spent)).font(.title2.weight(.bold)).monospacedDigit().contentTransition(.numericText())
                Text("/ \(Fmt.yen(total)) trong giỏ").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Meter(value: total > 0 ? Double(spent) / Double(total) : 0)
            Text("Ngân sách mua sắm \(Fmt.yen(planned)) cho khoảng 10–12 phần quà, gộp theo hộ.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func basketRow(_ item: Basket.Item, purchase: Purchase?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            CheckButton(isOn: purchase != nil) { toggle(id: item.id, name: item.name, yen: item.total, qty: item.qty, purchase: purchase, source: "buy.basket.\(item.id)") }
                .sheetSource("buy.basket.\(item.id)")
                .padding(.top, -8)
                .padding(.leading, -8)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.name) × \(item.qty)").font(.body)
                Text(item.where).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                YenText(yen: purchase?.yen ?? item.total)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(purchase == nil ? .primary : .secondary)
                if let paid = purchase?.yen, paid != item.total {
                    Text("dự trù \(Fmt.grouped(item.total))").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Slots

    @ViewBuilder
    private var slots: some View {
        let byDay = Dictionary(grouping: guide.shopping.slots, by: \.day)
        Section("Theo ngày") {
            ForEach(byDay.keys.sorted(), id: \.self) { n in
                ForEach(byDay[n] ?? []) { slot in
                    NavigationLink(value: Route.slot(slot.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text("Ngày \(slot.day)").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
                                if let start = slot.start {
                                    Text([start, slot.end].compactMap { $0 }.joined(separator: "–")).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                                }
                            }
                            Text(slot.area ?? slot.city ?? "").font(.body.weight(.semibold))
                            if let focus = slot.focus {
                                Text(focus).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Catalogue

    private func catalogRow(_ item: Shopping.CatalogItem, purchase: Purchase?) -> some View {
        let chains = Dictionary(guide.shopping.chains.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        return HStack(alignment: .top, spacing: 8) {
            CheckButton(isOn: purchase != nil) { toggle(id: item.id, name: item.name, yen: item.yen ?? 0, qty: 1, purchase: purchase, source: "buy.catalog.\(item.id)") }
                .sheetSource("buy.catalog.\(item.id)")
                .padding(.top, -8)
                .padding(.leading, -8)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.subheadline.weight(.semibold))
                if let ja = item.ja { Text(ja).font(.caption).foregroundStyle(.secondary).environment(\.locale, Locale(identifier: "ja_JP")) }
                if let why = item.why { Text(why).font(.caption) }
                if let tip = item.tip { Text(tip).font(.caption).foregroundStyle(.secondary) }
                if !item.where.isEmpty {
                    Text(item.where.map { chains[$0] ?? $0 }.joined(separator: " · "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let yen = purchase?.yen ?? item.yen { YenText(yen: yen).font(.subheadline.weight(.semibold)) }
                if let note = item.yenNote {
                    Text(note).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing).lineLimit(3)
                        .frame(maxWidth: 120, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Buying

    private func toggle(id: String, name: String, yen: Int, qty: Int, purchase: Purchase?, source: String) {
        if purchase != nil {
            let linked: String? = id
            try? context.delete(model: Purchase.self, where: #Predicate { $0.itemID == id })
            try? context.delete(model: Expense.self, where: #Predicate { $0.itemID == linked })
            try? context.save()
        } else {
            buying = SpendBuyItem(id: id, name: name, yen: yen, qty: qty, source: source)
        }
    }
}

struct SpendBuyItem: Identifiable {
    let id: String
    let name: String
    let yen: Int
    let qty: Int
    /// the check it was ticked from, which the sheet grows out of
    var source: String?
}

/// "Bought it": the real price and how it was paid; logs the purchase and the expense together.
private struct SpendBuySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: SpendBuyItem
    let done: () -> Void
    @State private var amount = ""
    @State private var method: PayMethod = .card
    @FocusState private var focused: Bool

    private var value: Int { Int(amount.filter(\.isNumber)) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("¥").font(.system(size: 30, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        TextField("0", text: $amount)
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .keyboardType(.numberPad)
                            .focused($focused)
                    }
                    Picker("Trả bằng", selection: $method) {
                        ForEach(PayMethod.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(item.qty > 1 ? "\(item.name) × \(item.qty)" : item.name)
                }
            }
            .progressiveEdges()
            .navigationTitle("Đã mua")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(value <= 0)
                }
            }
            .onAppear {
                if item.yen > 0 { amount = String(item.yen) }
                focused = true
            }
        }
        .presentationDetents([.height(300)])
    }

    private func save() {
        context.insert(Purchase(itemID: item.id, qty: item.qty, yen: value, placeID: nil, at: model.now))
        try? context.save()
        model.logExpense(yen: value, category: .shop, method: method, placeID: nil, note: item.name, itemID: item.id)
        done()
        dismiss()
    }
}

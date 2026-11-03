import SwiftData
import SwiftUI
import TripKit

/// Mua sắm: the basket with what is already bought, the shopping windows the plan leaves day by day,
/// and the researched catalogue. Ticking an item asks what it really cost and logs it.
struct ShoppingView: View {
    @Environment(AppModel.self) private var model
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
        .sensoryFeedback(.done, trigger: bought)
    }

    // MARK: Basket

    private func progress(_ owned: [String: Purchase]) -> some View {
        let total = guide.basket.total
        let spent = Yen.total(guide.basket.items.map { item in owned[item.id].map { $0.yen ?? item.total } ?? 0 })
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
            CheckButton(isOn: purchase != nil, marksOnTap: false) { toggle(id: item.id, name: item.name, yen: item.total, qty: item.qty, purchase: purchase, source: "buy.basket.\(item.id)") }
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
            CheckButton(isOn: purchase != nil, marksOnTap: false) { toggle(id: item.id, name: item.name, yen: item.yen ?? 0, qty: 1, purchase: purchase, source: "buy.catalog.\(item.id)") }
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

    /// Ticked: asks what it cost. Unticked: no longer bought, the expense with it (through the ledger,
    /// so the other phone drops it too); false when that could not be saved.
    private func toggle(id: String, name: String, yen: Int, qty: Int, purchase: Purchase?, source: String) -> Bool {
        guard purchase == nil else { return model.unbuy(id) }
        buying = SpendBuyItem(id: id, name: name, yen: yen, qty: qty, source: source)
        return true
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
/// The price is typed on the sheet's own keypad, so the sheet grows out of its check undisturbed.
private struct SpendBuySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let item: SpendBuyItem
    let done: () -> Void
    @State private var value = 0
    @State private var method: PayMethod = .card
    /// a purchase that could not be saved: the sheet stays, with the price, and says why
    @State private var issue: SaveIssue?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    SpendAmountDisplay(yen: value, size: 52)
                    Text(item.qty > 1 ? "\(item.name) × \(item.qty)" : item.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxHeight: .infinity)
                Picker("Trả bằng", selection: $method) {
                    ForEach(PayMethod.allCases) { m in Text(m.label).tag(m) }
                }
                .pickerStyle(.segmented)
                SpendKeypad(amount: $value)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 12)
            .background(Palette.paper)
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
                if value == 0, item.yen > 0 { value = min(item.yen, Yen.maxEntry) }
            }
            .sensoryFeedback(.fail, trigger: failed)
            .saveIssueAlert($issue) { _ in save() }
        }
        .presentationDetents([.height(540)])
    }

    private func save() {
        // one write for both: bought only with the expense that paid for it
        context.insert(Purchase(itemID: item.id, qty: item.qty, yen: value, placeID: nil, at: model.now))
        guard model.logExpense(yen: value, category: .shop, method: method, placeID: nil, note: item.name, itemID: item.id) != nil else {
            // said here, over the sheet, not behind it
            issue = model.takeSaveIssue()
            failed.toggle()
            return
        }
        done()
        dismiss()
    }
}

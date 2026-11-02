import SwiftData
import SwiftUI
import TripKit

/// Chi tiêu: spent against the budget, cash and Suica on hand with what the next days need in cash,
/// and the ledger. Adding an expense is one floating button away.
struct SpendTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.at, order: .reverse) private var expenses: [Expense]
    @Query private var topups: [Topup]
    @State private var topup: PayMethod?
    @Environment(\.zoomSpace) private var space

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.spendPath) {
            List {
                Section { SpendSummary(expenses: expenses) }
                Section { wallet }
                Section {
                    NavigationLink(value: Route.budget) { Label("Ngân sách", systemImage: "chart.bar.xaxis") }
                    NavigationLink(value: Route.shopping) { Label("Mua sắm", systemImage: "bag") }
                }
                ledger
            }
            .listStyle(.insetGrouped)
            .paperList()
            .navigationTitle("Chi tiêu")
            .navigationDestination(for: Route.self) { RouteHost(route: $0) }
            // a bar, not an overlay: the ledger ends above the button and fades out under it
            .safeAreaBar(edge: .bottom, alignment: .trailing) { addButton }
            .sheet(item: $topup) { method in
                SpendTopupSheet(method: method)
                    .zoomed(from: "spend.topup.\(method.rawValue)", in: space)
            }
        }
    }

    // MARK: Wallet

    private var wallet: some View {
        let w = SpendWallet(expenses: expenses, topups: topups)
        let (plan, label) = cashPlan
        let short = plan.shortfall(onHand: w.cash)
        return Group {
            HStack(spacing: 0) {
                walletFigure("Tiền mặt", yen: w.cash, symbol: "banknote")
                Divider().frame(height: 40)
                walletFigure("Suica", yen: w.ic, symbol: "wave.3.right.circle")
                    .padding(.leading, 16)
            }
            if plan.certain > 0 || plan.possible > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Cần tiền mặt \(label)")
                        Spacer()
                        YenText(yen: plan.certain).fontWeight(.semibold)
                    }
                    if plan.possible > plan.certain {
                        Text("Thêm tới \(Fmt.yen(plan.possible - plan.certain)) ở chỗ nhận cả hai.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if short > 0 {
                        Label("Rút thêm \(Fmt.yen(short)) — ATM 7-Eleven nhận thẻ nước ngoài.", systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.subheadline)
            }
            HStack(spacing: 12) {
                Button { topup = .cash } label: { Label("Rút tiền", systemImage: "plus.circle").frame(maxWidth: .infinity) }
                    .sheetSource("spend.topup.\(PayMethod.cash.rawValue)")
                Button { topup = .ic } label: { Label("Nạp Suica", systemImage: "plus.circle").frame(maxWidth: .infinity) }
                    .sheetSource("spend.topup.\(PayMethod.ic.rawValue)")
            }
            .buttonStyle(.bordered)
        }
    }

    private func walletFigure(_ title: String, yen: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(Fmt.yen(yen))
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(yen < 0 ? .red : .primary)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Cash the next two days ask for; before the trip, the first two days.
    private var cashPlan: (CashPlan, String) {
        if let today = model.today, let i = model.days.firstIndex(where: { $0.key == today.key }) {
            return (CashPlan(store: model.store, days: model.days, from: i, cursor: model.cursor), "hôm nay và mai")
        }
        return (CashPlan(store: model.store, days: model.days, from: 0, cursor: 0), "hai ngày đầu")
    }

    // MARK: Ledger

    @ViewBuilder
    private var ledger: some View {
        if expenses.isEmpty {
            Section {
                Text("Chưa ghi khoản nào.").foregroundStyle(.secondary)
            }
        } else {
            ForEach(groups, id: \.date) { group in
                Section {
                    ForEach(group.items) { e in
                        SpendLedgerRow(expense: e)
                            .swipeActions {
                                Button("Xoá", systemImage: "trash", role: .destructive) { delete(e) }
                            }
                    }
                } header: {
                    HStack {
                        Text(dayTitle(group.date))
                        Spacer()
                        Text(Fmt.yen(group.items.reduce(0) { $0 + $1.yen })).monospacedDigit()
                    }
                }
            }
        }
    }

    private var groups: [SpendDayGroup] {
        let byDate = Dictionary(grouping: expenses) { TripTime.isoDate(of: $0.at) }
        return byDate.keys.sorted(by: >).map { SpendDayGroup(date: $0, items: byDate[$0] ?? []) }
    }

    private func dayTitle(_ iso: String) -> String {
        if let d = model.days.first(where: { $0.date == iso }) { return "Ngày \(d.n) · \(Fmt.shortDate(iso))" }
        return Fmt.shortDate(iso)
    }

    private func delete(_ e: Expense) {
        context.delete(e)
        try? context.save()
    }

    private var addButton: some View {
        Button {
            model.present(.expense(placeID: nil, yen: nil), from: "spend.add")
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .sheetSource("spend.add")
        .accessibilityLabel("Ghi khoản chi")
        .padding(.trailing, Metrics.gutter)
        .padding(.bottom, 16)
    }
}

private struct SpendDayGroup {
    let date: String
    let items: [Expense]
}

/// Total spent against the plan, per category.
struct SpendSummary: View {
    @Environment(AppModel.self) private var model
    let expenses: [Expense]

    private var status: BudgetStatus {
        var spent: [SpendCategory: Int] = [:]
        for e in expenses { spent[e.spendCategory, default: 0] += e.yen }
        return BudgetStatus(budget: model.guide.budget, spent: spent)
    }

    var body: some View {
        let budget = model.guide.budget
        let status = self.status
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.yen(status.spent))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("\(Fmt.vndMillions(status.spent, rate: model.rate)) · trên \(Fmt.yen(status.planned))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Meter(value: status.planned > 0 ? Double(status.spent) / Double(status.planned) : 0)
            ForEach(status.rows.filter { $0.planned > 0 || $0.spent > 0 }) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(row.category.label, systemImage: SpendSymbols.category(row.category))
                            .font(.subheadline)
                        Spacer()
                        Text("\(Fmt.yen(row.spent)) / \(Fmt.grouped(row.planned))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Meter(value: row.share, tint: SpendSymbols.color(row.category, budget: budget))
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 6)
    }
}

/// One expense in the ledger.
private struct SpendLedgerRow: View {
    @Environment(AppModel.self) private var model
    let expense: Expense

    var body: some View {
        let category = expense.spendCategory
        let place = model.store.place(expense.placeID)
        HStack(spacing: 12) {
            Image(systemName: SpendSymbols.category(category))
                .font(.body)
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(SpendSymbols.color(category, budget: model.guide.budget), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(place?.name ?? (expense.note.isEmpty ? category.label : expense.note))
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(TripTime.clock(expense.at)).monospacedDigit()
                    Image(systemName: SpendSymbols.method(expense.payMethod))
                    if place != nil, !expense.note.isEmpty { Text(expense.note).lineLimit(1) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            YenText(yen: expense.yen).font(.body.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

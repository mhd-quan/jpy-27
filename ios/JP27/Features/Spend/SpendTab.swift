import SwiftData
import SwiftUI
import TripKit
import UniformTypeIdentifiers

/// Chi tiêu at a glance. The budget is one dial: each category an arc as long as its share of the
/// plan; before the trip the dial is the plan itself, on the trip the arcs fill as money goes.
/// Under it the two purses, cash and Suica, as cards to tap and fill, with the cash the next days
/// ask for in one line; the budget and the shopping list; then the ledger, day by day.
/// Adding an expense is the toolbar's button, which grows into the editor.
struct SpendTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.zoomSpace) private var space
    @Query(sort: \Expense.at, order: .reverse) private var expenses: [Expense]
    @Query private var topups: [Topup]
    @Query private var purchases: [Purchase]
    @State private var topup: PayMethod?
    @State private var importing = false
    @State private var merged: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.spendPath) {
            List {
                Section {
                    SpendDial(expenses: expenses, today: todaySpent)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Section {
                    let wallet = SpendWallet(expenses: expenses, topups: topups)
                    SpendPurses(wallet: wallet, advice: cashAdvice(onHand: wallet.cash)) { topup = $0 }
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 10, trailing: 0))
                    SpendShortcuts(budget: model.guide.budget.total, owned: ownedCount, items: model.guide.basket.items.count)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                ForEach(groups, id: \.date) { group in
                    Section {
                        ForEach(group.items) { e in
                            SpendLedgerRow(expense: e)
                                .swipeActions {
                                    Button("Xoá", systemImage: "trash", role: .destructive) { delete(e) }
                                }
                        }
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(dayTitle(group.date))
                            Spacer()
                            Text(Fmt.yen(group.items.reduce(0) { $0 + $1.yen })).monospacedDigit()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .paperList()
            .navigationTitle("Chi tiêu")
            .navigationDestination(for: Route.self) { RouteHost(route: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ShareLink(item: SpendLedgerFile(expenses: expenses, store: model.store), preview: SharePreview("Sổ chi JP27")) {
                            Label("Xuất sổ chi (CSV)", systemImage: "square.and.arrow.up")
                        }
                        Button("Gộp sổ từ máy kia", systemImage: "arrow.triangle.merge") { importing = true }
                    } label: {
                        Label("Sổ chi", systemImage: "ellipsis")
                    }
                }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
                SheetToolbarButton(title: "Ghi chi", symbol: "plus", source: "spend.add") {
                    model.present(.expense(placeID: nil, yen: nil), from: "spend.add")
                }
            }
            // the other phone's ledger, sent as its CSV: rows this phone lacks are added, counted in
            // the budget but not in this phone's purses
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                guard case .success(let url) = result else { return }
                do {
                    let n = try SpendLedgerFile.merge(url, into: context)
                    merged = n == 0 ? "Không có khoản nào mới: sổ này đã có đủ." : "Đã gộp \(n) khoản từ máy kia."
                } catch {
                    merged = "Không đọc được file: \(error.localizedDescription)"
                }
            }
            .alert(merged ?? "", isPresented: Binding(get: { merged != nil }, set: { if !$0 { merged = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .sheet(item: $topup) { method in
                SpendTopupSheet(method: method)
                    .zoomed(from: "spend.topup.\(method.rawValue)", in: space)
            }
        }
    }

    // MARK: Figures

    /// Spent today, on a trip day.
    private var todaySpent: Int? {
        guard let today = model.today else { return nil }
        let iso = today.date
        return expenses.filter { e in e.day == today.key || (e.day == nil && TripTime.isoDate(of: e.at) == iso) }
            .reduce(0) { $0 + $1.yen }
    }

    private var ownedCount: Int {
        let ids = Set(model.guide.basket.items.map(\.id))
        return purchases.filter { ids.contains($0.itemID) }.count
    }

    /// "Hai ngày đầu cần ¥8.000 tiền mặt · rút thêm ¥13.000 ở ATM 7-Eleven"
    private func cashAdvice(onHand: Int) -> SpendCashAdvice? {
        let plan: CashPlan
        let when: String
        if let today = model.today, let i = model.days.firstIndex(where: { $0.key == today.key }) {
            plan = CashPlan(store: model.store, days: model.days, from: i, cursor: model.cursor)
            when = "Hôm nay và mai"
        } else {
            plan = CashPlan(store: model.store, days: model.days, from: 0, cursor: 0)
            when = "Hai ngày đầu"
        }
        guard plan.certain > 0 else { return nil }
        return SpendCashAdvice(when: when, need: plan.certain, short: plan.shortfall(onHand: onHand))
    }

    // MARK: Ledger

    private var groups: [SpendDayGroup] {
        // under the day it was counted toward, else the day it was logged
        let dates = Dictionary(model.days.map { ($0.key, $0.date) }, uniquingKeysWith: { a, _ in a })
        let byDate = Dictionary(grouping: expenses) { e in e.day.flatMap { dates[$0] } ?? TripTime.isoDate(of: e.at) }
        return byDate.keys.sorted(by: >).map { SpendDayGroup(date: $0, items: byDate[$0] ?? []) }
    }

    private func dayTitle(_ iso: String) -> String {
        if let today = model.today, today.date == iso { return "Hôm nay" }
        if let d = model.days.first(where: { $0.date == iso }) { return "Ngày \(d.n) · \(Fmt.shortDate(iso))" }
        return Fmt.shortDate(iso)
    }

    private func delete(_ e: Expense) {
        context.delete(e)
        try? context.save()
    }
}

private struct SpendDayGroup {
    let date: String
    let items: [Expense]
}

private struct SpendCashAdvice {
    let when: String
    let need: Int
    let short: Int
}

// MARK: - The dial

/// One arc of the dial: a line of the budget, where it sits on the circle and how far it is spent.
private struct SpendArc: Identifiable {
    let id: String
    let label: String
    let symbol: String
    let color: Color
    let planned: Int
    let spent: Int
    let start: Double
    let end: Double

    var share: Double { planned > 0 ? Double(spent) / Double(planned) : 0 }
    var left: Int { planned - spent }
}

/// An arc of the dial from `start` to `end` (fractions of the circle, from twelve o'clock,
/// clockwise), drawn only as far as `sweep` has gone round: animating `sweep` from 0 to 1 draws
/// the whole dial in one stroke, arc after arc; animating `end` grows a fill.
private nonisolated struct SpendArcShape: Shape {
    let start: Double
    var end: Double
    var sweep: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(end, sweep) }
        set {
            end = newValue.first
            sweep = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let to = min(end, sweep)
        var path = Path()
        guard to > start else { return path }
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: .radians(2 * .pi * start - .pi / 2),
            endAngle: .radians(2 * .pi * to - .pi / 2),
            clockwise: false
        )
        return path
    }
}

/// The budget as one dial (Screen Time's and Storage's segmented ring): every line of the plan an
/// arc as long as its share. Before anything is spent the arcs are drawn in full: the plan. Once
/// money goes, they turn to faint tracks that fill from their start. Choosing a category below
/// reads it in the middle of the dial; choosing it again, or the middle, goes back to the total.
private struct SpendDial: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let expenses: [Expense]
    let today: Int?
    @State private var selected: String?
    @State private var drawn = false

    private static let size: CGFloat = 228
    private static let width: CGFloat = 20

    private var arcs: [SpendArc] {
        var spent: [String: Int] = [:]
        for e in expenses { spent[e.spendCategory.rawValue, default: 0] += e.yen }
        let lines = model.guide.budget.lines.filter { $0.yen > 0 }
        let total = Double(max(1, lines.reduce(0) { $0 + $1.yen }))
        // a hairline gap between arcs, the same few points whatever the arc's length
        let gap = 3.0 / (Double.pi * Double(Self.size - Self.width))
        var at = 0.0
        return lines.map { line in
            let length = Double(line.yen) / total
            defer { at += length }
            let category = SpendCategory(rawValue: line.id)
            return SpendArc(
                id: line.id,
                label: category?.label ?? line.label,
                symbol: category.map(SpendSymbols.category) ?? "shield.lefthalf.filled",
                color: Color(hex: line.color),
                planned: line.yen,
                spent: spent[line.id] ?? 0,
                start: at + gap / 2,
                end: max(at + gap / 2, at + length - gap / 2)
            )
        }
    }

    var body: some View {
        let arcs = self.arcs
        let planned = arcs.reduce(0) { $0 + $1.planned }
        let spent = arcs.reduce(0) { $0 + $1.spent }
        let planning = spent == 0
        let chosen = arcs.first { $0.id == selected }
        VStack(spacing: 22) {
            ZStack {
                ring(arcs, planning: planning)
                    .frame(width: Self.size, height: Self.size)
                centre(chosen, planned: planned, spent: spent, planning: planning)
                    .frame(width: Self.size - Self.width * 2 - 20)
                    .contentShape(.circle)
                    .onTapGesture { withAnimation(.snappy) { selected = nil } }
            }
            .padding(.top, 8)
            .accessibilityElement(children: .combine)

            legend(arcs, planning: planning)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .sensoryFeedback(.selection, trigger: selected)
        .onAppear {
            guard !drawn else { return }
            if reduceMotion { drawn = true } else { withAnimation(.smooth(duration: 1.1).delay(0.1)) { drawn = true } }
        }
    }

    private func ring(_ arcs: [SpendArc], planning: Bool) -> some View {
        let stroke = StrokeStyle(lineWidth: Self.width, lineCap: .butt)
        let sweep = drawn ? 1.0 : 0.0
        return ZStack {
            ForEach(arcs) { a in
                let lit = selected == nil || selected == a.id
                // the track: the plan in full before the trip, a faint groove once spending starts
                SpendArcShape(start: a.start, end: a.end, sweep: sweep)
                    .stroke(a.color.opacity(planning ? (lit ? 1 : 0.25) : (lit ? 0.2 : 0.08)), style: stroke)
                if !planning {
                    SpendArcShape(start: a.start, end: a.start + (a.end - a.start) * min(1, a.share), sweep: sweep)
                        .stroke(a.color.opacity(lit ? 1 : 0.3), style: stroke)
                }
            }
        }
        .padding(Self.width / 2)
        .animation(.smooth(duration: 0.3), value: selected)
        .animation(.smooth(duration: 0.6), value: arcs.reduce(0) { $0 + $1.spent })
    }

    private func centre(_ arc: SpendArc?, planned: Int, spent: Int, planning: Bool) -> some View {
        VStack(spacing: 3) {
            if let arc {
                Image(systemName: arc.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(arc.color)
                Text(arc.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                figure(planning ? arc.planned : arc.spent)
                Text(arcCaption(arc, planned: planned, planning: planning))
                    .font(.caption)
                    .foregroundStyle(arc.left < 0 && !planning ? Palette.sun : Color.secondary)
                    .monospacedDigit()
            } else if planning {
                Text("Dự tính")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                figure(planned)
                Text(Fmt.vndMillions(planned, rate: model.rate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            } else {
                Text("Đã chi")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                figure(spent)
                Text("trên \(Fmt.yen(planned))")
                    .font(.caption)
                    .foregroundStyle(spent > planned ? Palette.sun : Color.secondary)
                    .monospacedDigit()
                if let today, today > 0 {
                    Text("hôm nay \(Fmt.yen(today))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .multilineTextAlignment(.center)
        .animation(.snappy, value: arc?.id)
    }

    /// Under a chosen category's figure: its share of the plan before the trip, what is left on it.
    private func arcCaption(_ arc: SpendArc, planned: Int, planning: Bool) -> String {
        if planning {
            let percent = Int((Double(arc.planned) / Double(max(1, planned)) * 100).rounded())
            return "\(percent)% ngân sách"
        }
        return arc.left >= 0 ? "còn \(Fmt.yen(arc.left))" : "vượt \(Fmt.yen(-arc.left))"
    }

    private func figure(_ yen: Int) -> some View {
        Text(Fmt.yen(yen))
            .font(.figure(32))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText(value: Double(yen)))
    }

    /// The lines of the plan as chips, two by two: the plan's figure before the trip, what is
    /// left of each on it.
    private func legend(_ arcs: [SpendArc], planning: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            ForEach(arcs) { a in
                let on = selected == a.id
                Button {
                    withAnimation(.snappy) { selected = on ? nil : a.id }
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(a.color)
                            .frame(width: 9, height: 9)
                        Text(a.label)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(chipFigure(a, planning: planning))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(!planning && a.left < 0 ? Palette.sun : Color.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Palette.card, in: .capsule)
                    .overlay {
                        Capsule().strokeBorder(a.color, lineWidth: on ? 1.5 : 0)
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("\(a.label), \(chipFigure(a, planning: planning))")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private func chipFigure(_ a: SpendArc, planning: Bool) -> String {
        if planning { return Fmt.grouped(a.planned) }
        return a.left >= 0 ? Fmt.grouped(a.left) : "−\(Fmt.grouped(-a.left))"
    }
}

// MARK: - Purses

/// Cash and Suica as two cards, each with what is in it; tapping one fills it (ATM, top-up).
/// Under them, in one line, the cash the next days ask for and what to withdraw.
private struct SpendPurses: View {
    let wallet: SpendWallet
    let advice: SpendCashAdvice?
    let fill: (PayMethod) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                purse(.cash, title: "Tiền mặt", yen: wallet.cash, kanji: "円", top: SpendPurseTint.of(.cash), bottom: Color(hex: "#16325C"))
                purse(.ic, title: "Suica", yen: wallet.ic, symbol: "wave.3.right", top: SpendPurseTint.of(.ic), bottom: Color(hex: "#1B6E3B"))
            }
            if let advice {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "banknote")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    if advice.short > 0 {
                        Text("\(advice.when) cần \(Fmt.yen(advice.need)) tiền mặt · rút thêm \(Text(Fmt.yen(advice.short)).fontWeight(.semibold).foregroundStyle(.primary)) ở ATM 7-Eleven")
                    } else {
                        Text("\(advice.when) cần \(Fmt.yen(advice.need)) tiền mặt · đã đủ")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.horizontal, 4)
            }
        }
    }

    private func purse(_ method: PayMethod, title: String, yen: Int, kanji: String? = nil, symbol: String? = nil, top: Color, bottom: Color) -> some View {
        Button {
            fill(method)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.9)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.caption.weight(.bold))
                        .frame(width: 24, height: 24)
                        .background(.white.opacity(0.2), in: .circle)
                }
                Spacer(minLength: 0)
                Text(yen < 0 ? "−\(Fmt.yen(-yen))" : Fmt.yen(yen))
                    .font(.figure(26))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: Double(yen)))
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .background(alignment: .bottomTrailing) {
                // the purse's mark, large and faint, like the emboss on a card
                Group {
                    if let kanji {
                        Text(kanji).font(.mincho(64))
                    } else if let symbol {
                        Image(systemName: symbol).font(.system(size: 54, weight: .semibold))
                    }
                }
                .foregroundStyle(.white.opacity(0.1))
                .offset(x: 6, y: 14)
                .accessibilityHidden(true)
            }
            .background(LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(.rect(cornerRadius: 22, style: .continuous))
            .contentShape(.rect(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.pressable)
        .sheetSource("spend.topup.\(method.rawValue)")
        .accessibilityLabel("\(title): \(Fmt.yen(yen))")
        .accessibilityHint(method == .cash ? "Ghi tiền rút ra" : "Ghi tiền nạp Suica")
    }
}

// MARK: - Budget and shopping

private struct SpendShortcuts: View {
    let budget: Int
    let owned: Int
    let items: Int

    var body: some View {
        HStack(spacing: 12) {
            tile(.budget, symbol: "chart.pie.fill", tint: Palette.matcha, title: "Ngân sách", detail: Fmt.yen(budget))
            tile(.shopping, symbol: "bag.fill", tint: Place.Kind.shop.tint, title: "Mua sắm", detail: items > 0 ? "\(owned)/\(items) món" : "Danh sách")
        }
    }

    private func tile(_ route: Route, symbol: String, tint: Color, title: String, detail: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                GlyphTile(symbol: symbol, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Palette.card, in: .rect(cornerRadius: 20, style: .continuous))
            .contentShape(.rect(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Ledger

/// One expense: its category, where (a place from the data, else the name typed in), when and
/// how it was paid, the amount.
private struct SpendLedgerRow: View {
    @Environment(AppModel.self) private var model
    let expense: Expense

    var body: some View {
        let category = expense.spendCategory
        let place = model.store.place(expense.placeID)
        let named = place?.name ?? expense.placeName
        HStack(spacing: 12) {
            GlyphTile(symbol: SpendSymbols.category(category), tint: SpendSymbols.color(category, budget: model.guide.budget), size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(named ?? (expense.note.isEmpty ? category.label : expense.note))
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(TripTime.clock(expense.at)).monospacedDigit()
                    Image(systemName: SpendSymbols.method(expense.payMethod))
                        .accessibilityLabel(expense.payMethod.label)
                    if named != nil, !expense.note.isEmpty {
                        Text(expense.note).lineLimit(1)
                    }
                    if expense.device != nil {
                        Text("· máy kia")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            YenText(yen: expense.yen)
                .font(.body.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }
}

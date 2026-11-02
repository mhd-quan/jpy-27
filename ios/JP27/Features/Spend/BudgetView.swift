import Charts
import SwiftData
import SwiftUI
import TripKit

/// Ngân sách: the plan's money by line, food by day, transport fares, and what a different rate or
/// a few savings do to the total in đồng.
struct BudgetView: View {
    @Environment(AppModel.self) private var model
    @Query private var expenses: [Expense]
    @State private var rate: Double = 0
    @State private var saving: Set<String> = []

    private var budget: Budget { model.guide.budget }
    private var total: Int { budget.total - budget.savings.filter { saving.contains($0.id) }.reduce(0) { $0 + $1.yen } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                totalCard
                lines
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Đã chi")
                    Card { SpendSummary(expenses: expenses) }
                }
                food
                transport
                scenarios
                Text("Hai người, theo yên, giá gồm thuế. Chỉ tiền chi tại Nhật — chưa gồm vé máy bay, visa, bảo hiểm và phí hành lý của hãng bay.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
        .navigationTitle("Ngân sách")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { if rate == 0 { rate = model.rate } }
    }

    // MARK: Total at a rate

    private var totalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.yen(total))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("≈ \(Fmt.vndMillions(total, rate: rate)) đồng ở \(Int(rate)) đ/¥")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .animation(.snappy, value: total)
            .animation(.snappy, value: rate)
            Slider(value: $rate, in: 160 ... 200, step: 1) {
                Text("Tỷ giá")
            } minimumValueLabel: {
                Text("160").font(.caption).monospacedDigit()
            } maximumValueLabel: {
                Text("200").font(.caption).monospacedDigit()
            }
            .sensoryFeedback(.selection, trigger: Int(rate))
            if !budget.savings.isEmpty {
                Divider()
                ForEach(budget.savings) { s in
                    Toggle(isOn: Binding(
                        get: { saving.contains(s.id) },
                        set: { on in if on { saving.insert(s.id) } else { saving.remove(s.id) } }
                    )) {
                        HStack {
                            Text(s.label).font(.subheadline)
                            Spacer()
                            Text("−\(Fmt.yen(s.yen))").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: Lines

    private var lines: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Chia theo khoản", trailing: Fmt.yen(budget.total))
            Card {
                Chart(budget.lines) { line in
                    BarMark(x: .value("Yên", line.yen), y: .value("Tổng", "Tổng"))
                        .foregroundStyle(Color(hex: line.color))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 28)
                .clipShape(.capsule)
                .accessibilityHidden(true)
                ForEach(budget.lines) { line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle().fill(Color(hex: line.color)).frame(width: 10, height: 10).padding(.top, 5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.label).font(.subheadline.weight(.semibold))
                            Text(line.note).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 2) {
                            YenText(yen: line.yen).font(.subheadline.weight(.semibold))
                            Text(Fmt.vndMillions(line.yen, rate: rate)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Food per day

    private var food: some View {
        let days = model.days
        let sum = days.reduce(0) { $0 + $1.meals.total }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Tiền ăn từng ngày", trailing: Fmt.yen(sum))
            Card {
                Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 8) {
                    GridRow {
                        Text("Ngày").gridColumnAlignment(.leading)
                        Text("Sáng")
                        Text("Trưa")
                        Text("Tối")
                        Text("Vặt")
                        Text("Cộng")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(days) { d in
                        GridRow {
                            Text("\(d.n) · \(Fmt.shortDate(d.date))").gridColumnAlignment(.leading)
                            cell(d.meals.b)
                            cell(d.meals.l)
                            cell(d.meals.d)
                            cell(d.meals.s)
                            Text(Fmt.grouped(d.meals.total)).fontWeight(.semibold)
                        }
                        .font(.caption)
                        .monospacedDigit()
                    }
                }
            }
        }
    }

    private func cell(_ yen: Int) -> some View {
        Text(yen == 0 ? "–" : Fmt.grouped(yen)).foregroundStyle(yen == 0 ? .tertiary : .primary)
    }

    // MARK: Transport

    private var transport: some View {
        let sum = budget.transport.reduce(0) { $0 + $1.yen }
        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Di chuyển", trailing: Fmt.yen(sum))
            Card {
                ForEach(Array(budget.transport.enumerated()), id: \.offset) { i, fare in
                    if i > 0 { Divider() }
                    HStack {
                        Text(fare.label).font(.subheadline)
                        Spacer()
                        YenText(yen: fare.yen).font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: Rates

    private var scenarios: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Khi tỷ giá đổi")
            Card {
                ForEach(Array(budget.scenarios.enumerated()), id: \.offset) { i, s in
                    if i > 0 { Divider() }
                    Button { withAnimation(.snappy) { rate = s.rate } } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(Int(s.rate))")
                                .font(.headline)
                                .monospacedDigit()
                                .frame(width: 40, alignment: .leading)
                                .foregroundStyle(Int(s.rate) == Int(rate) ? Color.accentColor : .primary)
                            Text(s.note).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                            Text(Fmt.vndMillions(budget.total, rate: s.rate)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Dùng tỷ giá này")
                }
            }
        }
    }
}

/// Total spent against the plan, per category.
private struct SpendSummary: View {
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

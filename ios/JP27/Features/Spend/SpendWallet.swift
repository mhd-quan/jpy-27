import SwiftData
import SwiftUI
import TripKit

/// Cash and Suica on hand: what went in (ATM, top-ups) minus what was paid that way.
struct SpendWallet {
    let cash: Int
    let ic: Int

    init(expenses: [Expense], topups: [Topup]) {
        func inflow(_ m: PayMethod) -> Int { topups.filter { $0.method == m.rawValue }.reduce(0) { $0 + $1.yen } }
        func outflow(_ m: PayMethod) -> Int { expenses.filter { $0.method == m.rawValue }.reduce(0) { $0 + $1.yen } }
        cash = inflow(.cash) - outflow(.cash)
        ic = inflow(.ic) - outflow(.ic)
    }
}

enum SpendSymbols {
    static func category(_ c: SpendCategory) -> String {
        switch c {
        case .food: "fork.knife"
        case .shop: "bag.fill"
        case .move: "tram.fill"
        case .ticket: "ticket.fill"
        case .hotel: "bed.double.fill"
        case .ryokan: "bathtub.fill"
        case .extra: "ellipsis.circle.fill"
        }
    }

    static func method(_ m: PayMethod) -> String {
        switch m {
        case .cash: "banknote"
        case .card: "creditcard"
        case .ic: "wave.3.right.circle"
        }
    }

    /// Category colours follow the budget's own line colours.
    static func color(_ c: SpendCategory, budget: Budget) -> Color {
        budget.lines.first { $0.id == c.rawValue }.map { Color(hex: $0.color) } ?? .gray
    }
}

/// Money in: an ATM withdrawal or a Suica top-up.
struct SpendTopupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let method: PayMethod
    @State private var amount = ""
    @FocusState private var focused: Bool

    private var yen: Int? { Int(amount.filter(\.isNumber)) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("¥").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                    TextField("0", text: $amount)
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .keyboardType(.numberPad)
                        .focused($focused)
                }
                .padding(.horizontal, Metrics.gutter)
                HStack(spacing: 8) {
                    ForEach(method == .cash ? [10_000, 20_000, 30_000] : [2_000, 3_000, 5_000], id: \.self) { v in
                        Button(Fmt.yen(v)) { amount = String(v) }
                            .buttonStyle(.bordered)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .navigationTitle(method == .cash ? "Rút tiền" : "Nạp Suica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if let yen, yen > 0 { model.topUp(yen: yen, method: method) }
                        dismiss()
                    }
                    .disabled((yen ?? 0) <= 0)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(280)])
    }
}

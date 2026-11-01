import SwiftUI
import TripKit

/// Log what was really spent, in a few taps: the amount first, everything else guessed from where
/// you are and the plan.
struct ExpenseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let placeID: String?
    let yen: Int?

    @State private var amount = ""
    @State private var category: SpendCategory = .food
    @State private var method: PayMethod = .cash
    @State private var place: String?
    @State private var note = ""
    @State private var ready = false
    @State private var saved = false
    @FocusState private var focused: Bool

    private var value: Int { Int(amount.filter(\.isNumber)) ?? 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("¥").font(.system(size: 34, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        TextField("0", text: $amount)
                            .font(.system(size: 48, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .keyboardType(.numberPad)
                            .focused($focused)
                            .accessibilityLabel("Số tiền, yên")
                    }
                    if value > 0 {
                        Text(Fmt.vndMillions(value, rate: model.rate) + " đồng")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Section {
                    Picker("Trả bằng", selection: $method) {
                        ForEach(PayMethod.allCases) { m in Text(m.label).tag(m) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Khoản", selection: $category) {
                        ForEach(SpendCategory.allCases) { c in
                            Label(c.label, systemImage: SpendSymbols.category(c)).tag(c)
                        }
                    }
                    Picker("Ở đâu", selection: $place) {
                        Text("Không gắn chỗ").tag(String?.none)
                        ForEach(candidates) { p in Text(p.name).tag(Optional(p.id)) }
                    }
                    TextField("Ghi chú", text: $note)
                }
            }
            .navigationTitle("Ghi chi")
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
            .sensoryFeedback(.success, trigger: saved)
            .onAppear(perform: setUp)
            .onChange(of: place) { _, id in
                guard ready, let p = model.store.place(id) else { return }
                category = SpendCategory.of(p)
                method = Self.method(for: p)
            }
        }
    }

    /// The places worth offering: the given one, then today's (or the next trip day's) stops.
    private var candidates: [Place] {
        var ids: [String] = []
        if let placeID { ids.append(placeID) }
        for (_, s) in model.focusDay.stops {
            if let id = s.place, !ids.contains(id), let p = model.store.place(id), p.kind != .station { ids.append(id) }
        }
        return ids.compactMap { model.store.place($0) }
    }

    private func setUp() {
        guard !ready else { return }
        if let yen, yen > 0 { amount = String(yen) }
        place = placeID ?? nearestPlanned()
        let p = model.store.place(place)
        category = p.map { SpendCategory.of($0) } ?? .food
        method = p.map { Self.method(for: $0) } ?? .cash
        ready = true
        focused = true
    }

    /// Today's planned place within 150 m of where you stand.
    private func nearestPlanned() -> String? {
        guard let here = model.position, let day = model.today else { return nil }
        let near = day.stops.compactMap { model.store.place($0.stop.place) }
            .filter { $0.kind != .station }
            .map { ($0, Geo.km($0.coordinate, here)) }
            .min { $0.1 < $1.1 }
        return near.flatMap { $0.1 <= 0.15 ? $0.0.id : nil }
    }

    private static func method(for place: Place) -> PayMethod {
        switch place.payment {
        case .card: .card
        default: .cash
        }
    }

    private func save() {
        guard value > 0 else { return }
        model.logExpense(yen: value, category: category, method: method, placeID: place, note: note.trimmingCharacters(in: .whitespaces))
        saved.toggle()
        dismiss()
    }
}

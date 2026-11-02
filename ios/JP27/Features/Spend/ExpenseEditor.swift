import SwiftUI
import TripKit

/// Log what was really spent, in a few taps: the amount first, everything else guessed from where
/// you are and the plan. The day it counts toward can be changed (a bill logged the next morning),
/// and the place can be anything: a stop of that day, a side trip near one, a place around you,
/// any place in the data, or one the data never had, named by hand.
struct ExpenseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let placeID: String?
    let yen: Int?

    @State private var amount = ""
    @State private var category: SpendCategory = .food
    @State private var method: PayMethod = .cash
    @State private var dayKey: String?
    @State private var place: String?
    @State private var placeName = ""
    @State private var note = ""
    @State private var ready = false
    @State private var saved = false
    @FocusState private var focused: Bool

    private var value: Int { Int(amount.filter(\.isNumber)) ?? 0 }
    private var day: Day? { dayKey.flatMap { key in model.days.first { $0.key == key } ?? model.store.day(key) } }

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
                    Picker("Ngày", selection: $dayKey) {
                        ForEach(model.days) { d in
                            Text("Ngày \(d.n) · \(Fmt.shortDate(d.date))").tag(Optional(d.key))
                        }
                        Text("Không theo ngày").tag(String?.none)
                    }
                    NavigationLink {
                        ExpensePlacePicker(day: day, place: $place, placeName: $placeName)
                    } label: {
                        LabeledContent("Ở đâu") {
                            Text(placeLabel)
                                .lineLimit(1)
                                .foregroundStyle(place == nil && placeName.isEmpty ? .secondary : .primary)
                        }
                    }
                    TextField("Ghi chú", text: $note)
                }
            }
            .progressiveEdges()
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

    private var placeLabel: String {
        if let p = model.store.place(place) { return p.name }
        if !placeName.isEmpty { return placeName }
        return "Không gắn chỗ"
    }

    private func setUp() {
        guard !ready else { return }
        if let yen, yen > 0 { amount = String(yen) }
        place = placeID ?? nearestPlanned()
        let p = model.store.place(place)
        // the day it counts toward: today on the trip; else the day the place is planned for
        dayKey = model.today?.key ?? p?.uses.first { use in model.days.contains { $0.key == use.day } }?.day
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
        let name = placeName.trimmingCharacters(in: .whitespaces)
        model.logExpense(yen: value, category: category, method: method, placeID: place,
                         placeName: place == nil && !name.isEmpty ? name : nil, day: dayKey,
                         note: note.trimmingCharacters(in: .whitespaces))
        saved.toggle()
        dismiss()
    }
}

/// Where the money went, for one day: around you, that day's stops, the side trips beside them;
/// a search over every place in the data; or a name typed in for a place the data does not have.
private struct ExpensePlacePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let day: Day?
    @Binding var place: String?
    @Binding var placeName: String
    @State private var query = ""
    @State private var draft = ""

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        List {
            if q.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(.secondary)
                        TextField("Chỗ khác, gõ tên", text: $draft)
                            .submitLabel(.done)
                            .onSubmit(useDraft)
                        if !draft.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Dùng", action: useDraft)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                        }
                    }
                    choice(nil, title: "Không gắn chỗ", symbol: "minus.circle", tint: .secondary)
                }
                let near = around
                if !near.isEmpty {
                    Section("Quanh bạn") {
                        ForEach(near) { n in
                            choice(n.place, detail: Fmt.km(n.km))
                        }
                    }
                }
                if let day {
                    let stops = planned(day)
                    if !stops.isEmpty {
                        Section("Ngày \(day.n) · trong lịch") {
                            ForEach(stops, id: \.id) { p in choice(p) }
                        }
                    }
                    let sides = detours(day)
                    if !sides.isEmpty {
                        Section("Ngày \(day.n) · rẽ ngang") {
                            ForEach(sides, id: \.id) { s in
                                choice(s.place, detail: "rẽ \(s.minutes) phút")
                            }
                        }
                    }
                }
            } else {
                let results = search(q)
                if results.isEmpty {
                    Section {
                        Button {
                            draft = q
                            useDraft()
                        } label: {
                            Label("Dùng “\(q)” làm tên chỗ", systemImage: "square.and.pencil")
                        }
                    }
                } else {
                    Section {
                        ForEach(results, id: \.id) { p in
                            choice(p, detail: plannedDay(p))
                        }
                    }
                }
            }
        }
        .paperList()
        .navigationTitle("Ở đâu")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Tìm trong mọi chỗ đã lưu")
        .onAppear {
            if place == nil { draft = placeName }
        }
    }

    // MARK: Rows

    private func choice(_ p: Place?, title: String? = nil, symbol: String? = nil, tint: Color? = nil, detail: String? = nil) -> some View {
        let on = p.map { $0.id == place } ?? (place == nil && placeName.isEmpty)
        return Button {
            place = p?.id
            placeName = ""
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol ?? (p?.snack != nil ? "takeoutbag.and.cup.and.straw.fill" : p?.kind.symbol ?? "mappin"))
                    .font(.subheadline)
                    .foregroundStyle(tint ?? p?.kind.tint ?? .secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title ?? p?.name ?? "")
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
                if on {
                    Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Palette.sun)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func useDraft() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        place = nil
        placeName = name
        dismiss()
    }

    // MARK: Lists

    /// Places in the data within 300 m of you (empty when you are not near any).
    private var around: [ExpenseNear] {
        guard let here = model.position else { return [] }
        return model.store.trip.places
            .filter { $0.kind != .station }
            .map { ExpenseNear(place: $0, km: Geo.km(here, $0.coordinate)) }
            .filter { $0.km <= 0.3 }
            .sorted { $0.km < $1.km }
            .prefix(6)
            .map { $0 }
    }

    /// "Ngày 4" for a place the plan visits
    private func plannedDay(_ p: Place) -> String? {
        guard let use = p.uses.first, let d = model.days.first(where: { $0.key == use.day }) else { return nil }
        return "Ngày \(d.n)"
    }

    private func planned(_ day: Day) -> [Place] {
        var seen = Set<String>()
        return day.stops.compactMap { _, s in
            guard let p = model.store.place(s.place), p.kind != .station, seen.insert(p.id).inserted else { return nil }
            return p
        }
    }

    /// The day's side trips in the order of the stops they sit beside.
    private func detours(_ day: Day) -> [MapSide] {
        let sides = MapGuide.sides(for: day, store: model.store, pace: model.pace.factor)
        var seen = Set<String>()
        return day.stops.flatMap { sides[$0.index] ?? [] }.filter { seen.insert($0.id).inserted }
    }

    private func search(_ q: String) -> [Place] {
        model.store.trip.places
            .filter { p in
                p.kind != .station && (p.name.localizedStandardContains(q) || (p.ja?.contains(q) ?? false) || (p.dish?.localizedStandardContains(q) ?? false))
            }
            .sorted { ($0.uses.isEmpty ? 1 : 0, $0.name) < ($1.uses.isEmpty ? 1 : 0, $1.name) }
            .prefix(40)
            .map { $0 }
    }
}

private struct ExpenseNear: Identifiable {
    let place: Place
    let km: Double
    var id: String { place.id }
}

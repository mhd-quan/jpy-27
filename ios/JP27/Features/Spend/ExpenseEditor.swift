import SwiftUI
import TripKit

/// Log what was really spent, in a few taps: the amount first, on the sheet's own keypad, so the
/// sheet grows out of its button with nothing rising into the zoom; everything else guessed from
/// where you are and the plan. The day it counts toward can be changed (a bill logged the next
/// morning), and the place can be anything: a stop of that day, a side trip near one, a place
/// around you, any place in the data, or one the data never had, named by hand.
struct ExpenseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let placeID: String?
    let yen: Int?
    /// an expense already logged, to change (on either phone: the later edit wins when they sync)
    var editing: Expense? = nil

    @State private var value = 0
    @State private var category: SpendCategory = .food
    @State private var method: PayMethod = .cash
    @State private var dayKey: String?
    @State private var place: String?
    @State private var placeName = ""
    @State private var note = ""
    @State private var ready = false
    @State private var saved = false
    @FocusState private var writing: Bool

    private var day: Day? { dayKey.flatMap { key in model.days.first { $0.key == key } ?? model.store.day(key) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 22) {
                        amount
                        categories
                        Picker("Trả bằng", selection: $method) {
                            ForEach(PayMethod.allCases) { m in Text(m.label).tag(m) }
                        }
                        .pickerStyle(.segmented)
                        details
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
                // the pad steps aside while the note is being typed
                if !writing {
                    SpendKeypad(amount: $value)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: writing)
            .background(Palette.paper)
            .progressiveEdges()
            .navigationTitle(editing == nil ? "Ghi chi" : "Sửa khoản chi")
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
                // a new expense takes the kind and the way to pay from its place; an edit keeps its own
                guard ready, editing == nil, let p = model.store.place(id) else { return }
                withAnimation(.snappy) {
                    category = SpendCategory.of(p)
                    method = Self.method(for: p)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Parts

    /// The amount, large, with what it is in đồng under it.
    private var amount: some View {
        VStack(spacing: 2) {
            SpendAmountDisplay(yen: value, size: 60)
            Text("≈ \(Fmt.vndMillions(value, rate: model.rate)) đồng")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .opacity(value > 0 ? 1 : 0)
        }
        .padding(.top, 12)
        .contentShape(.rect)
        .onTapGesture { writing = false }
    }

    /// The seven kinds of spending as a row of coloured glyphs; the chosen one filled, its name under
    /// the row.
    private var categories: some View {
        let budget = model.guide.budget
        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(SpendCategory.allCases) { c in
                    let on = c == category
                    let tint = SpendSymbols.color(c, budget: budget)
                    Button {
                        withAnimation(.snappy) { category = c }
                    } label: {
                        Image(systemName: SpendSymbols.category(c))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(on ? Color.white : tint)
                            .frame(width: 42, height: 42)
                            .background(on ? tint : tint.opacity(0.14), in: .circle)
                            .overlay {
                                Circle()
                                    .strokeBorder(tint.opacity(on ? 0.35 : 0), lineWidth: 3)
                                    .padding(-4)
                            }
                            .frame(maxWidth: .infinity)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel(c.label)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(category.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SpendSymbols.color(category, budget: budget))
                .contentTransition(.interpolate)
                .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection, trigger: category)
    }

    /// Where, which day it counts toward, and a note, as one card.
    private var details: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ExpensePlacePicker(day: day, place: $place, placeName: $placeName)
            } label: {
                row(symbol: "mappin.and.ellipse", title: "Ở đâu") {
                    HStack(spacing: 6) {
                        Text(placeLabel)
                            .lineLimit(1)
                            .foregroundStyle(place == nil && placeName.isEmpty ? .secondary : .primary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
            Divider().padding(.leading, 48)
            row(symbol: "calendar", title: "Tính vào") {
                Picker("Tính vào", selection: $dayKey) {
                    ForEach(model.days) { d in
                        Text("Ngày \(d.n) · \(Fmt.shortDate(d.date))").tag(Optional(d.key))
                    }
                    Text("Không theo ngày").tag(String?.none)
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            Divider().padding(.leading, 48)
            HStack(spacing: 12) {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                TextField("Ghi chú", text: $note)
                    .focused($writing)
                    .submitLabel(.done)
                    .onSubmit { writing = false }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
        }
        .background(Palette.card, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func row<Value: View>(symbol: String, title: String, @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
            Spacer(minLength: 12)
            value()
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 50)
        .contentShape(.rect)
    }

    private var placeLabel: String {
        if let p = model.store.place(place) { return p.name }
        if !placeName.isEmpty { return placeName }
        return "Không gắn chỗ"
    }

    // MARK: Guesses

    private func setUp() {
        guard !ready else { return }
        if let e = editing {
            value = e.yen
            category = e.spendCategory
            method = e.payMethod
            dayKey = e.day
            place = e.placeID
            placeName = e.placeName ?? ""
            note = e.note
            ready = true
            return
        }
        if let yen, yen > 0 { value = min(yen, 9_999_999) }
        place = placeID ?? nearestPlanned()
        let p = model.store.place(place)
        // the day it counts toward: today on the trip; else the day the place is planned for
        dayKey = model.today?.key ?? p?.uses.first { use in model.days.contains { $0.key == use.day } }?.day
        category = p.map { SpendCategory.of($0) } ?? .food
        method = p.map { Self.method(for: $0) } ?? .cash
        ready = true
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
        if let e = editing {
            e.yen = value
            e.category = category.rawValue
            e.method = method.rawValue
            e.placeID = place
            e.placeName = place == nil && !name.isEmpty ? name : nil
            e.day = dayKey
            e.note = note.trimmingCharacters(in: .whitespaces)
            e.touch()
            try? model.context.save()
            saved.toggle()
            dismiss()
            return
        }
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

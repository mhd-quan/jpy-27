import Combine
import SwiftUI
import TripKit
import UIKit

/// Log what was really spent, in a few taps: the amount first, on the sheet's own keypad, so the
/// sheet grows out of its button with nothing rising into the zoom; everything else guessed from
/// where you are and the plan. The day it counts toward can be changed (a bill logged the next
/// morning), and the place can be anything: a stop of that day, a side trip near one, a place
/// around you, any place in the data, or one the data never had, named by hand.
struct ExpenseEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// an expense already logged, to change (on either phone: the later edit wins when they sync)
    let editing: Expense?

    /// what the sheet shows, filled in before its first frame (`ExpenseDraft.make`)
    @State private var draft: ExpenseDraft
    @State private var saved = false
    /// a save that failed: the editor stays, with what was typed, and says why
    @State private var issue: SaveIssue?
    @State private var failed = false
    /// kinds tapped; the kind also changes by itself, set up from the place and on picking a place
    @State private var chosen = 0
    /// places chosen in the list under "Ở đâu"; the place set up on opening stays quiet
    @State private var placePicks = 0
    @FocusState private var writing: Bool
    /// the pad, out of the way while the system keyboard is up: it leaves and comes back with the keyboard,
    /// on the keyboard's own timing (`keyboard(_:shows:)`)
    @State private var padShown = true
    /// the sheet is being closed by its own buttons: the keyboard going down with it brings no pad back
    @State private var leaving = Leaving()

    /// not observed: set on the way out, read only by the keyboard's notifications
    final class Leaving {
        var on = false
    }

    /// `model` is the app's one model, the one the sheet also reads from its environment.
    init(placeID: String?, yen: Int?, editing: Expense? = nil, model: AppModel = .shared) {
        self.editing = editing
        _draft = State(initialValue: ExpenseDraft.make(placeID: placeID, yen: yen, editing: editing, model: model))
    }

    private var day: Day? { draft.dayKey.flatMap { key in model.days.first { $0.key == key } ?? model.store.day(key) } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 22) {
                        amount
                        categories
                        Picker("Trả bằng", selection: $draft.method) {
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
                // the pad steps aside while the system keyboard is up (the note being typed)
                if padShown {
                    SpendKeypad(amount: $draft.value)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { keyboard($0, shows: true) }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { keyboard($0, shows: false) }
            .background(Palette.paper)
            .progressiveEdges()
            .navigationTitle(editing == nil ? "Ghi chi" : "Sửa khoản chi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", role: .cancel) { leave() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(!Yen.isValidEntry(draft.value))
                }
            }
            .sensoryFeedback(.done, trigger: saved)
            .sensoryFeedback(.fail, trigger: failed)
            .saveIssueAlert($issue) { _ in save() }
            // here, not in the list: the list closes as the place is chosen
            .sensoryFeedback(.pick, trigger: placePicks)
            // only a place chosen in the list: the one the sheet opened on was there before its first frame
            .onChange(of: draft.place) { _, id in
                // a new expense takes the kind and the way to pay from its place; an edit keeps its own
                guard editing == nil, let p = model.store.place(id) else { return }
                withAnimation(Motion.reduced(Motion.pick, reduceMotion)) {
                    draft.category = SpendCategory.of(p)
                    draft.method = ExpenseDraft.method(for: p)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: Parts

    /// The amount, large, with what it is in đồng under it.
    private var amount: some View {
        VStack(spacing: 2) {
            SpendAmountDisplay(yen: draft.value, size: 60)
            Text("≈ \(Fmt.vndMillions(draft.value, rate: model.rate)) đồng")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .contentTransition(.numericText())
                .opacity(draft.value > 0 ? 1 : 0)
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
                    let on = c == draft.category
                    let tint = SpendSymbols.color(c, budget: budget)
                    Button {
                        if c != draft.category { chosen += 1 }
                        withAnimation(Motion.reduced(Motion.pick, reduceMotion)) { draft.category = c }
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
                    // the kind chosen ticks `pick` below, not the press
                    .buttonStyle(.pressable(.settle, felt: false))
                    .accessibilityLabel(c.label)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(draft.category.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SpendSymbols.color(draft.category, budget: budget))
                .contentTransition(.interpolate)
                .accessibilityHidden(true)
        }
        .sensoryFeedback(.pick, trigger: chosen)
    }

    /// Where, which day it counts toward, and a note, as one card.
    private var details: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ExpensePlacePicker(day: day, place: $draft.place, placeName: $draft.placeName, picks: $placePicks)
            } label: {
                row(symbol: "mappin.and.ellipse", title: "Ở đâu") {
                    HStack(spacing: 6) {
                        Text(placeLabel)
                            .lineLimit(1)
                            .foregroundStyle(draft.place == nil && draft.placeName.isEmpty ? .secondary : .primary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.pressable(.plain))
            Divider().padding(.leading, 48)
            row(symbol: "calendar", title: "Tính vào") {
                Picker("Tính vào", selection: $draft.dayKey) {
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
                TextField("Ghi chú", text: $draft.note)
                    .focused($writing)
                    .onChange(of: draft.note) { _, text in
                        if text.count > LedgerValidation.maxText { draft.note = String(text.prefix(LedgerValidation.maxText)) }
                    }
                    .submitLabel(.done)
                    .onSubmit { writing = false }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 50)
            if draft.longNote {
                Text("Ghi chú dài hơn 500 ký tự; khi lưu chỉ giữ 500 ký tự đầu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
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
        if let p = model.store.place(draft.place) { return p.name }
        if !draft.placeName.isEmpty { return draft.placeName }
        return "Không gắn chỗ"
    }

    private func save() {
        guard Yen.isValidEntry(draft.value) else { return }
        // held to what the other phone and a file are held to (`LedgerValidation`)
        let name = String(draft.placeName.trimmingCharacters(in: .whitespaces).prefix(LedgerValidation.maxText))
        let text = String(draft.note.trimmingCharacters(in: .whitespaces).prefix(LedgerValidation.maxText))
        if let e = editing {
            e.yen = draft.value
            e.category = draft.category.rawValue
            e.method = draft.method.rawValue
            e.placeID = draft.place
            e.placeName = draft.place == nil && !name.isEmpty ? name : nil
            e.day = draft.dayKey
            e.note = text
            e.touch()
            // a failed write takes the edit back on the row; what was typed stays here
            if model.persist("Khoản chi") { saved.toggle(); leave() } else { fail() }
            return
        }
        if model.logExpense(yen: draft.value, category: draft.category, method: draft.method, placeID: draft.place,
                            placeName: draft.place == nil && !name.isEmpty ? name : nil, day: draft.dayKey,
                            note: text) != nil {
            saved.toggle()
            leave()
        } else {
            fail()
        }
    }

    /// Closes the sheet from its own buttons, the keyboard perhaps still up: the pad stays out while the sheet goes.
    private func leave() {
        leaving.on = true
        dismiss()
    }

    /// The system keyboard rising or going down: the pad goes the other way, in the same motion. A keyboard of
    /// another app (on iPad) moves nothing here; one going down as the sheet closes brings no pad back.
    private func keyboard(_ note: Notification, shows: Bool) {
        if let local = note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool, !local { return }
        let pad = !shows
        guard pad != padShown, !(pad && leaving.on) else { return }
        let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0
        // the system keyboard's own curve and duration, not a Motion token: the pad moves with the keyboard
        let curve: Animation? = duration > 0 ? .spring(duration: duration, bounce: 0) : nil
        withAnimation(curve) { padShown = pad }
    }

    /// Not saved: said here, over the editor, not behind it.
    private func fail() {
        issue = model.takeSaveIssue()
        failed.toggle()
    }
}

/// What the editor shows and saves. Filled in when the sheet is made, so its first frame is the last:
/// an edit starts from the expense, a new one from where you are and the plan.
nonisolated struct ExpenseDraft: Equatable {
    var value: Int
    var category: SpendCategory
    var method: PayMethod
    var dayKey: String?
    var place: String?
    var placeName: String
    var note: String
    /// the note loaded was longer than `LedgerValidation.maxText`: saving keeps only its start
    var longNote: Bool
}

extension ExpenseDraft {
    @MainActor static func make(placeID: String?, yen: Int?, editing: Expense?, model: AppModel) -> ExpenseDraft {
        if let e = editing {
            // an amount the keypad could not have typed starts again from nothing; a note too long
            // shows (and saves) its start, and says so
            let note = LedgerValidation.seed(note: e.note)
            return ExpenseDraft(value: Yen.seed(editing: e.yen), category: e.spendCategory, method: e.payMethod,
                                dayKey: e.day, place: e.placeID, placeName: e.placeName ?? "",
                                note: note.text, longNote: note.long)
        }
        // the place: the one it was opened from, else today's planned place within 150 m of you
        let place = placeID ?? model.position.flatMap { here in
            model.today.flatMap { Nearby.plannedStop(near: here, day: $0, store: model.store) }
        }
        let p = model.store.place(place)
        // the day it counts toward: today on the trip; else the day the place is planned for
        let dayKey = model.today?.key ?? p?.uses.first { use in model.days.contains { $0.key == use.day } }?.day
        return ExpenseDraft(value: Yen.seed(asked: yen),
                            category: p.map { SpendCategory.of($0) } ?? .food,
                            method: p.map { method(for: $0) } ?? .cash,
                            dayKey: dayKey, place: place, placeName: "", note: "", longNote: false)
    }

    /// Card where the place says card; cash otherwise ("mixed" included).
    static func method(for place: Place) -> PayMethod {
        switch place.payment {
        case .card: .card
        default: .cash
        }
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
    /// counts a place or a typed name chosen in place of the one before; "Không gắn chỗ" is a letting go and stays quiet
    @Binding var picks: Int
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
                            .onChange(of: draft) { _, text in
                                if text.count > LedgerValidation.maxText { draft = String(text.prefix(LedgerValidation.maxText)) }
                            }
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
            if let p, p.id != place { picks += 1 }
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
        if place != nil || name != placeName { picks += 1 }
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

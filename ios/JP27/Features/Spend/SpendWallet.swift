import SwiftData
import SwiftUI
import TripKit
import UniformTypeIdentifiers

extension Expense {
    /// Whether it counts toward any total: an amount the keypad could have typed. A row saved before
    /// every way in was held to that (a file, the other phone) may hold anything; such a row is
    /// listed under "Khoản cần sửa" to be fixed or deleted, never counted, never deleted by itself.
    var isCountable: Bool { Yen.isValidEntry(yen) }
}

/// Cash and Suica on hand: what went in (ATM, top-ups) minus what was paid that way. Only what was
/// paid from this phone's purses: expenses merged from the other phone count in the budget, not here.
struct SpendWallet {
    let cash: Int
    let ic: Int

    init(expenses: [Expense], topups: [Topup]) {
        func inflow(_ m: PayMethod) -> Int { Yen.total(topups.filter { $0.method == m.rawValue }.map(\.yen)) }
        func outflow(_ m: PayMethod) -> Int {
            Yen.total(expenses.filter { $0.isCountable && $0.device == nil && $0.method == m.rawValue }.map(\.yen))
        }
        cash = Yen.difference(inflow(.cash), outflow(.cash))
        ic = Yen.difference(inflow(.ic), outflow(.ic))
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

/// Money in: an ATM withdrawal or a Suica top-up. The amount is typed on the sheet's own keypad,
/// or picked from the usual few, so the sheet grows out of its purse without a keyboard rising
/// into the zoom.
struct SpendTopupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let method: PayMethod
    @State private var yen = 0
    @State private var picked = 0
    @State private var saved = false
    /// a top-up that could not be saved: the sheet stays, with the amount, and says why
    @State private var issue: SaveIssue?
    @State private var failed = false

    private var quick: [Int] { method == .cash ? [10_000, 20_000, 30_000] : [2_000, 3_000, 5_000] }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                VStack(spacing: 4) {
                    SpendAmountDisplay(yen: yen, size: 52)
                    Text(method == .cash ? "Rút ở ATM, vào ví tiền mặt" : "Nạp vào Suica")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
                HStack(spacing: 8) {
                    ForEach(quick, id: \.self) { v in
                        let on = yen == v
                        Button {
                            if yen != v { picked += 1 }
                            withAnimation(.snappy) { yen = v }
                        } label: {
                            Text(Fmt.yen(v))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(on ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(on ? AnyShapeStyle(SpendPurseTint.of(method)) : AnyShapeStyle(Color.primary.opacity(0.06)), in: .capsule)
                                .contentShape(.capsule)
                        }
                        // the amount chosen ticks `pick` below; the same amount again stays quiet
                        .buttonStyle(.pressable(.settle, felt: false))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .sensoryFeedback(.pick, trigger: picked)
                SpendKeypad(amount: $yen)
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 12)
            .background(Palette.paper)
            .navigationTitle(method == .cash ? "Rút tiền" : "Nạp Suica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(yen <= 0)
                }
            }
            .sensoryFeedback(.done, trigger: saved)
            .sensoryFeedback(.fail, trigger: failed)
            .saveIssueAlert($issue) { _ in save() }
        }
        .presentationDetents([.height(540)])
    }

    private func save() {
        guard yen > 0 else {
            dismiss()
            return
        }
        guard model.topUp(yen: yen, method: method) else {
            // said here, over the sheet, not behind it
            issue = model.takeSaveIssue()
            failed.toggle()
            return
        }
        saved.toggle()
        dismiss()
    }
}

/// The purses' own colours: indigo for cash, Suica's green.
enum SpendPurseTint {
    static let suica = Color(hex: "#2E9E4F")

    static func of(_ method: PayMethod) -> Color {
        switch method {
        case .cash: Palette.ai
        case .card: Palette.fuji
        case .ic: suica
        }
    }
}

// MARK: - Amount and keypad

/// The amount being typed, large: "¥" small and grey before it, grey "0" until a digit comes; each
/// digit rolls in.
struct SpendAmountDisplay: View {
    let yen: Int
    var size: CGFloat = 56

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("¥")
                .font(.figure(size * 0.6, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Fmt.grouped(yen))
                .font(.figure(size, weight: .semibold))
                .foregroundStyle(yen > 0 ? HierarchicalShapeStyle.primary : .tertiary)
                .contentTransition(.numericText(value: Double(yen)))
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Số tiền")
        .accessibilityValue(Fmt.yen(yen))
    }
}

/// A number pad drawn in the sheet itself (1–9, 000, 0, delete), so a sheet that grows out of a
/// button stays still while it grows: no system keyboard sliding in over the zoom. Each key that
/// changes the amount taps lightly (`key`); a key that changes nothing (0 on an empty amount,
/// delete on nothing, a digit past the cap) stays still, so the finger feels which ones counted.
/// The amount is capped below ten million yen (`Yen.maxEntry`); delete always takes a digit off, so
/// an amount above the cap can still be brought down.
struct SpendKeypad: View {
    @Binding var amount: Int
    var limit = Yen.maxEntry
    @State private var keys = 0

    private static let rows: [[Yen.Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.thousand, .digit(0), .delete],
    ]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(Self.rows, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { key in
                        Button {
                            press(key)
                        } label: {
                            label(key)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .contentShape(.rect)
                        }
                        .buttonStyle(SpendKeyStyle())
                        .accessibilityLabel(accessibility(key))
                    }
                }
            }
        }
        .sensoryFeedback(.key, trigger: keys)
    }

    @ViewBuilder
    private func label(_ key: Yen.Key) -> some View {
        switch key {
        case .digit(let n):
            Text("\(n)").font(.figure(28, weight: .medium))
        case .thousand:
            Text("000").font(.figure(22, weight: .medium))
        case .delete:
            Image(systemName: "delete.left").font(.title2)
        }
    }

    private func accessibility(_ key: Yen.Key) -> String {
        switch key {
        case .digit(let n): "\(n)"
        case .thousand: "Ba số không"
        case .delete: "Xoá"
        }
    }

    private func press(_ key: Yen.Key) {
        guard let next = Yen.keyed(amount, key, limit: limit) else { return }
        keys += 1
        withAnimation(.snappy(duration: 0.25)) { amount = next }
    }
}

/// A key of the pad: a quiet tile that lights the moment it is touched and fades as it is let go.
private struct SpendKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.primary)
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.16 : 0.06),
                in: .rect(cornerRadius: 16, style: .continuous)
            )
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.25), value: configuration.isPressed)
    }
}

// MARK: - The ledger as a file

/// The ledger as CSV: to keep (Numbers, Excel, a backup off the phone), and to merge the other
/// phone's when the two cannot meet (`LedgerSync` does it by itself when they can). Merging follows
/// `LedgerMerge`: rows are keyed by the expense's id, so merging twice never counts one twice; an edit
/// newer than this phone's copy replaces it; a meal logged on both phones is kept twice and asked
/// about in the Spend tab. A file carries no deletions: a row deleted on the other phone stays here
/// until the phones meet.
///
/// The file is written only when it is shared: the Spend tab's menu builds its ShareLink with the
/// tab (a Menu makes its content up front), and the tab redraws with every change to the ledger.
nonisolated struct SpendLedgerFile: Transferable, Sendable {
    /// the records the ledger is read from when the file is asked for (the rehearsal's while one runs)
    let container: ModelContainer
    let store: TripStore

    static var transferRepresentation: some TransferRepresentation {
        // a byte-order mark, so spreadsheet apps read the Vietnamese right
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            let csv = await file.csv()
            return Data(("\u{FEFF}" + csv).utf8)
        }
        .suggestedFileName("JP27-so-chi.csv")
    }

    /// This install, so a file merged back is recognised as this phone's own rows.
    @MainActor static var installID: String {
        if let id = Shared.defaults.string(forKey: "installID") { return id }
        let id = UUID().uuidString
        Shared.defaults.set(id, forKey: "installID")
        return id
    }

    init(container: ModelContainer, store: TripStore) {
        self.container = container
        self.store = store
    }

    /// The ledger as it is now, oldest first (`LedgerCSV`).
    @MainActor func csv() -> String {
        let me = Self.installID
        let store = self.store
        let expenses = (try? container.mainContext.fetch(FetchDescriptor<Expense>(sortBy: [SortDescriptor(\.at)]))) ?? []
        return LedgerCSV.encode(expenses.map { $0.record(me: me) }, placeName: { store.place($0)?.name })
    }

    /// What merging a file did.
    struct Outcome {
        var added = 0
        var updated = 0
        /// rows of the file not merged: not what the keypad could have typed, or dated far ahead
        var skipped = 0
        /// the rows not read, as a spreadsheet numbers them (rows left out for their date have none)
        var lines: [Int] = []

        /// "Đã thêm 1 khoản, bỏ qua 1 dòng không hợp lệ (dòng 2)."
        var summary: String { LedgerCSV.summary(added: added, updated: updated, skipped: skipped, lines: lines) }
    }

    /// Merges a ledger file into this phone's ledger: read and checked off the main actor, then
    /// held to what the other phone is held to (`LedgerMerge.screened`) and merged. Throws
    /// `SaveFailure`, with nothing of the file kept, when the merge could not be written or this
    /// phone's ledger could not be read.
    @MainActor static func merge(_ url: URL, into context: ModelContext) async throws -> Outcome {
        let file = try await read(url)
        // a file is trusted no more than the other phone: rows the keypad could not have typed, and
        // rows dated far ahead, are left out
        let (clean, screenedOut) = LedgerMerge.screened(LedgerState(records: file.records), now: Date())
        let before = try Set(Ledger.state(context).records.map(\.id))
        let (_, changes) = try Ledger.merge(clean, into: context)
        var outcome = Outcome(skipped: file.rejected.count + screenedOut.count, lines: file.rejected.map(\.line))
        for r in changes.upserts {
            if before.contains(r.id) { outcome.updated += 1 } else { outcome.added += 1 }
        }
        return outcome
    }

    /// The file's rows, and the ones that could not be read. The file is held open (security scope)
    /// for the whole read.
    @concurrent private nonisolated static func read(_ url: URL) async throws -> (records: [LedgerRecord], rejected: [RowProblem]) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let text = try String(contentsOf: url, encoding: .utf8)
        return LedgerCSV.decode(text)
    }
}

import SwiftData
import SwiftUI
import TripKit
import UniformTypeIdentifiers

/// Cash and Suica on hand: what went in (ATM, top-ups) minus what was paid that way. Only what was
/// paid from this phone's purses: expenses merged from the other phone count in the budget, not here.
struct SpendWallet {
    let cash: Int
    let ic: Int

    init(expenses: [Expense], topups: [Topup]) {
        func inflow(_ m: PayMethod) -> Int { topups.filter { $0.method == m.rawValue }.reduce(0) { $0 + $1.yen } }
        func outflow(_ m: PayMethod) -> Int { expenses.filter { $0.device == nil && $0.method == m.rawValue }.reduce(0) { $0 + $1.yen } }
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
                        .buttonStyle(.pressable(.settle, feedback: nil))
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
                    Button(role: .confirm) {
                        if yen > 0 {
                            model.topUp(yen: yen, method: method)
                            saved.toggle()
                        }
                        dismiss()
                    }
                    .disabled(yen <= 0)
                }
            }
            .sensoryFeedback(.done, trigger: saved)
        }
        .presentationDetents([.height(540)])
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
/// The amount is capped below ten million yen.
struct SpendKeypad: View {
    @Binding var amount: Int
    var limit = 9_999_999
    @State private var keys = 0

    private static let rows: [[SpendKey]] = [
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
    private func label(_ key: SpendKey) -> some View {
        switch key {
        case .digit(let n):
            Text("\(n)").font(.figure(28, weight: .medium))
        case .thousand:
            Text("000").font(.figure(22, weight: .medium))
        case .delete:
            Image(systemName: "delete.left").font(.title2)
        }
    }

    private func accessibility(_ key: SpendKey) -> String {
        switch key {
        case .digit(let n): "\(n)"
        case .thousand: "Ba số không"
        case .delete: "Xoá"
        }
    }

    private func press(_ key: SpendKey) {
        let next: Int
        switch key {
        case .digit(let n): next = amount * 10 + n
        case .thousand: next = amount * 1000
        case .delete: next = amount / 10
        }
        guard next != amount, next <= limit else { return }
        keys += 1
        withAnimation(.snappy(duration: 0.25)) { amount = next }
    }
}

private nonisolated enum SpendKey: Hashable {
    case digit(Int)
    case thousand
    case delete
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
nonisolated struct SpendLedgerFile: Transferable, Sendable {
    let csv: String

    static var transferRepresentation: some TransferRepresentation {
        // a byte-order mark, so spreadsheet apps read the Vietnamese right
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in Data(("\u{FEFF}" + file.csv).utf8) }
            .suggestedFileName("JP27-so-chi.csv")
    }

    static let header = ["id", "luc", "ngay", "gio", "yen", "khoan", "ten_khoan", "tra", "place_id", "cho", "ghi_chu", "may", "sua"]

    /// This install, so a file merged back is recognised as this phone's own rows.
    @MainActor static var installID: String {
        if let id = Shared.defaults.string(forKey: "installID") { return id }
        let id = UUID().uuidString
        Shared.defaults.set(id, forKey: "installID")
        return id
    }

    @MainActor init(expenses: [Expense], store: TripStore) {
        let iso = Self.iso
        let me = Self.installID
        var rows = [Self.header]
        for e in expenses.sorted(by: { $0.at < $1.at }) {
            rows.append([
                e.id.uuidString, iso.string(from: e.at), e.day ?? "", TripTime.clock(e.at), String(e.yen),
                e.category, e.spendCategory.label, e.method, e.placeID ?? "",
                store.place(e.placeID)?.name ?? e.placeName ?? "", e.note, e.device ?? me,
                e.updatedAt.map(iso.string(from:)) ?? "",
            ])
        }
        csv = rows.map { $0.map(Self.field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func field(_ s: String) -> String {
        s.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : s
    }

    /// What merging a file did.
    struct Outcome {
        var added = 0
        var updated = 0

        var summary: String {
            var parts: [String] = []
            if added > 0 { parts.append("thêm \(added) khoản") }
            if updated > 0 { parts.append("cập nhật \(updated) khoản") }
            return parts.isEmpty ? "Sổ đã có đủ các khoản trong file." : "Đã " + parts.joined(separator: ", ") + "."
        }
    }

    /// Times to the millisecond, so an edit made a moment after another still reads as later.
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return iso.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    /// Merges a ledger file into this phone's ledger.
    @MainActor static func merge(_ url: URL, into context: ModelContext) throws -> Outcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var text = try String(contentsOf: url, encoding: .utf8)
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let rows = parse(text)
        guard let head = rows.first else { return Outcome() }
        let col = Dictionary(head.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func value(_ row: [String], _ name: String) -> String? {
            guard let i = col[name], row.indices.contains(i) else { return nil }
            let v = row[i].trimmingCharacters(in: .whitespaces)
            return v.isEmpty ? nil : v
        }
        var records: [LedgerRecord] = []
        for row in rows.dropFirst() {
            guard let idText = value(row, "id"), let id = UUID(uuidString: idText),
                  let at = date(value(row, "luc")),
                  let yen = value(row, "yen").flatMap(Int.init), yen > 0
            else { continue }
            let place = value(row, "place_id")
            records.append(LedgerRecord(
                id: id, yen: yen,
                category: value(row, "khoan").flatMap(SpendCategory.init(rawValue:))?.rawValue ?? SpendCategory.extra.rawValue,
                method: value(row, "tra").flatMap(PayMethod.init(rawValue:))?.rawValue ?? PayMethod.cash.rawValue,
                placeID: place,
                placeName: place == nil ? value(row, "cho") : nil,
                day: value(row, "ngay"),
                note: value(row, "ghi_chu") ?? "",
                at: at,
                updatedAt: date(value(row, "sua")),
                origin: value(row, "may") ?? "other"))
        }
        let before = Set(Ledger.state(context).records.map(\.id))
        // a file is trusted no more than the other phone: rows dated far ahead are left out
        let (_, changes) = Ledger.merge(LedgerMerge.sanitized(LedgerState(records: records), now: Date()), into: context)
        var outcome = Outcome()
        for r in changes.upserts {
            if before.contains(r.id) { outcome.updated += 1 } else { outcome.added += 1 }
        }
        return outcome
    }

    /// RFC 4180: quoted fields may hold commas, quotes (doubled) and line breaks.
    private static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            if quoted {
                if c == "\"" {
                    if chars.first == "\"" { field.append("\""); chars.removeFirst() } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == "," {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r" || c == "\r\n" {
                // "\r\n" is one Character in Swift
                row.append(field); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

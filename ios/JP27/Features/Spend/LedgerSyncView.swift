import SwiftData
import SwiftUI
import TripKit

// The Spend tab's side of `LedgerSync`: one quiet line for where the sync stands, a card when a
// phone near by asks to share, the pairs that may be one expense logged twice, and the sheet that
// turns it on and explains it.

/// "Đã đồng bộ với Lan lúc 21:04", under the purses; opens the sync sheet.
struct SpendSyncLine: View {
    @Environment(AppModel.self) private var model
    let open: () -> Void

    var body: some View {
        let sync = model.ledgerSync
        Button(action: open) {
            HStack(spacing: 8) {
                Image(systemName: sync.nearby != nil ? "arrow.triangle.2.circlepath" : "iphone.radiowaves.left.and.right")
                    .foregroundStyle(sync.nearby != nil ? AnyShapeStyle(SpendPurseTint.suica) : AnyShapeStyle(.secondary))
                Text(sync.status)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minHeight: 34)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable(.plain))
        .accessibilityHint("Mở đồng bộ với máy kia")
    }
}

/// A phone near by with the app open, asking to share the ledger.
struct SpendPairCard: View {
    @Environment(AppModel.self) private var model
    let name: String
    /// told when "Dùng chung" is pressed, so the haptic can play where the card is shown: the card
    /// itself goes away as the yes lands
    var accepted: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                GlyphTile(symbol: "iphone.radiowaves.left.and.right", tint: Palette.ai, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ghép với \(name)?")
                        .font(.subheadline.weight(.semibold))
                    Text("\(name) đang mở JP27 ở gần. Hai máy sẽ dùng chung một sổ chi và tự đồng bộ mỗi khi ở gần nhau. Chỉ đồng ý khi máy kia hiện cùng mã này; chạm đầu hai máy vào nhau cũng là đồng ý.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let code = model.ledgerSync.askingCode {
                SyncPairCode(code: code)
            }
            // explicit styles: two buttons in one list row, each its own
            HStack(spacing: 10) {
                Button("Để sau") { model.ledgerSync.decline() }
                    .buttonStyle(.bordered)
                Button("Dùng chung") {
                    model.ledgerSync.accept()
                    accepted()
                }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Palette.card, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// The six digits both phones show while pairing, large enough to compare across a table.
struct SyncPairCode: View {
    let code: String

    var body: some View {
        HStack(spacing: 10) {
            Text("Mã ghép")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(code)
                .font(.title2.weight(.semibold).monospacedDigit())
                .tracking(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mã ghép \(code)")
    }
}

/// Two rows of the two phones that may be one expense.
struct SpendDuplicatePair: Identifiable {
    let a: Expense
    let b: Expense
    /// same place, kind, amount and day: one payment logged on both phones, or each paying their own
    var same = false
    /// the row to keep if it is one payment: the one paid from a purse, when only one was
    var keep: Expense?
    var id: String { LedgerMerge.pairKey(a.id, b.id) }
}

/// The two rows side by side. Nothing is merged without asking: two people buying the same ¥1.200
/// bowl at one ticket machine is as common as one bowl logged twice. "Giữ khoản này" keeps one and
/// deletes the other (for both phones); "Hai khoản riêng" keeps both, not asked again on either
/// phone. The row paid in cash or by Suica is the one suggested, because only the phone that logged
/// it counts it in its purse: dropping it would leave that phone thinking the money is still there.
struct SpendDuplicateCard: View {
    @Environment(AppModel.self) private var model
    let pair: SpendDuplicatePair
    /// the row to drop, or nil to keep both
    let resolve: (Expense?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            line(pair.a, other: pair.b)
            Divider()
            line(pair.b, other: pair.a)
            Button("Hai khoản riêng") { resolve(nil) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var question: String {
        let place = model.store.place(pair.a.placeID)?.name ?? pair.a.placeName
        let at = place.map { " ở \($0)" } ?? ""
        if pair.same { return "Hai máy cùng ghi \(Fmt.yen(pair.a.yen))\(at). Một lần trả ghi hai lần, hay mỗi người trả một phần?" }
        return "Hai máy cùng ghi một khoản\(at) trong cùng buổi, số tiền khác nhau. Có phải cùng một lần trả?"
    }

    private func line(_ e: Expense, other: Expense) -> some View {
        let who = SpendOrigin.name(of: e, sync: model.ledgerSync)
        let suggested = pair.keep?.id == e.id
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(who.prefix(1).uppercased() + who.dropFirst())
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(TripTime.clock(e.at)) · \(e.payMethod.label)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            YenText(yen: e.yen)
                .font(.subheadline.weight(.semibold))
            keep(e, other: other, suggested: suggested)
                .controlSize(.small)
                .accessibilityLabel("Giữ khoản của \(who), bỏ khoản kia")
                .accessibilityHint(suggested ? "Gợi ý: khoản này trả bằng \(e.payMethod.label.lowercased()), được tính vào ví của \(who)" : "")
        }
    }

    @ViewBuilder
    private func keep(_ e: Expense, other: Expense, suggested: Bool) -> some View {
        if suggested {
            Button("Giữ khoản này") { resolve(other) }
                .buttonStyle(.borderedProminent)
        } else {
            Button("Giữ khoản này") { resolve(other) }
                .buttonStyle(.bordered)
        }
    }
}

enum SpendOrigin {
    /// "máy này", the paired phone's name, or "máy kia"
    @MainActor static func name(of e: Expense, sync: LedgerSync) -> String {
        guard let device = e.device else { return "máy này" }
        return sync.paired.first { $0.install == device }?.name ?? "máy kia"
    }
}

/// Turning the sync on, naming this phone, the phones paired, the rows folded as copies.
struct LedgerSyncSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var folded: [LedgerTombstone] = []
    // felt from the list: the rows pressed leave with the press
    @State private var paired = 0
    @State private var restored = 0
    /// a row brought back that could not be saved: said here, over the sheet, with "Thử lại"
    @State private var issue: SaveIssue?
    @State private var unsaved: LedgerTombstone?
    @State private var failed = false

    var body: some View {
        let sync = model.ledgerSync
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .font(.system(size: 44))
                            .foregroundStyle(Palette.ai)
                            .symbolEffect(.variableColor.iterative, isActive: sync.enabled && sync.nearby == nil)
                            .accessibilityHidden(true)
                        Text("Dùng chung sổ chi")
                            .font(.title3.weight(.bold))
                        Text("Hai máy cùng mở JP27 ở gần nhau thì sổ chi tự gộp qua Wi‑Fi trực tiếp giữa hai máy, không cần mạng: khoản mới, khoản sửa, khoản xoá. Hai khoản trông như một bữa được cả hai máy cùng ghi thì app hỏi lại, không tự gộp.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .listRowBackground(Color.clear)

                Section {
                    Toggle("Tự đồng bộ khi ở gần", isOn: Binding(get: { sync.enabled }, set: { sync.setEnabled($0) }))
                    LabeledContent("Tên máy này") {
                        TextField("Tên", text: $name)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { sync.rename(name) }
                    }
                } footer: {
                    Text("Ghép lần đầu: mở trang này trên cả hai máy. Máy kia thấy tên này khi ghép; máy lạ ở gần chỉ thấy “JP27”. Lần đầu bật, iPhone hỏi quyền tìm thiết bị trong mạng cục bộ và quyền đo khoảng cách tới thiết bị ở gần.")
                }

                if sync.enabled {
                    Section("Bây giờ") {
                        Label(sync.status, systemImage: sync.nearby != nil ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right")
                        if let asking = sync.asking {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(asking.name) ở gần và muốn dùng chung sổ chi. Chỉ đồng ý khi máy kia hiện cùng mã này.")
                                if let code = sync.askingCode {
                                    SyncPairCode(code: code)
                                }
                                HStack(spacing: 10) {
                                    Button("Để sau") { sync.decline() }
                                        .buttonStyle(.bordered)
                                    Button("Dùng chung") {
                                        sync.accept()
                                        paired += 1
                                    }
                                        .buttonStyle(.borderedProminent)
                                }
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.vertical, 4)
                        }
                        touch(sync)
                    }
                }

                if !sync.paired.isEmpty {
                    Section {
                        ForEach(sync.paired) { p in
                            Label(p.name, systemImage: "iphone")
                                .swipeActions {
                                    Button("Bỏ ghép", role: .destructive) { sync.unpair(p) }
                                }
                        }
                    } header: {
                        Text("Máy đã ghép")
                    } footer: {
                        Text("Vuốt để bỏ ghép. Những khoản đã đồng bộ vẫn ở lại máy này.")
                    }
                }

                if !folded.isEmpty {
                    Section {
                        ForEach(folded) { t in
                            if let r = t.record {
                                HStack(spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(model.store.place(r.placeID)?.name ?? r.placeName ?? (r.note.isEmpty ? "Khoản chi" : r.note))
                                            .lineLimit(1)
                                        Text("\(TripTime.clock(r.at)) · \(Fmt.yen(r.yen))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                    Spacer(minLength: 8)
                                    Button("Không phải trùng") { restore(t) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    } header: {
                        Text("Đã gộp vì ghi trùng")
                    } footer: {
                        Text("Bản trước của app tự gộp những khoản này khi hai máy cùng ghi một chỗ, cùng số tiền, cùng buổi. Nếu thật ra là hai lần trả, chọn Không phải trùng.")
                    }
                }

                Section {
                } footer: {
                    Text("Khi hai máy không gặp được nhau: xuất sổ chi ra file CSV ở menu ··· của tab Chi tiêu, gửi cho máy kia, rồi gộp file ở máy đó. File không mang theo các khoản đã xoá.")
                }
            }
            .paperList()
            .sensoryFeedback(.done, trigger: paired)
            .sensoryFeedback(.done, trigger: restored)
            .sensoryFeedback(.fail, trigger: failed)
            .saveIssueAlert($issue) { _ in
                if let unsaved { restore(unsaved) }
            }
            .navigationTitle("Đồng bộ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) {
                        sync.rename(name)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = sync.name
                folded = Ledger.folded(context)
                // while this page is open, a phone not paired yet may connect to be asked about
                sync.setPairing(true)
            }
            .onDisappear { sync.setPairing(false) }
        }
        .presentationDetents([.large])
    }

    /// A row wrongly taken for a copy, brought back; when that cannot be saved, nothing is.
    private func restore(_ t: LedgerTombstone) {
        do {
            try Ledger.restore(t, in: context)
        } catch {
            unsaved = t
            issue = SaveIssue(what: "Khoản bị gộp nhầm", error: error.localizedDescription)
            failed.toggle()
            return
        }
        unsaved = nil
        folded = Ledger.folded(context)
        restored += 1
    }

    @ViewBuilder
    private func touch(_ sync: LedgerSync) -> some View {
        if !sync.supportsTouch {
            Text("Máy này không có chip UWB: hai máy vẫn tự đồng bộ khi ở gần, chỉ không có cử chỉ chạm.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let d = sync.distance, sync.nearby != nil {
            Label("Cách \(Fmt.decimal(Double(d), digits: 1)) m · chạm đầu hai máy vào nhau để đồng bộ ngay", systemImage: "wave.3.right")
                .contentTransition(.numericText())
        } else {
            Text("Chạm đầu hai máy vào nhau để ghép và đồng bộ ngay. Cả hai máy cần chip UWB (iPhone 11 trở lên).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

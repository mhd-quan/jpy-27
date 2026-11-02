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
        .buttonStyle(.plain)
        .accessibilityHint("Mở đồng bộ với máy kia")
    }
}

/// A phone near by with the app open, asking to share the ledger.
struct SpendPairCard: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                GlyphTile(symbol: "iphone.radiowaves.left.and.right", tint: Palette.ai, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ghép với \(name)?")
                        .font(.subheadline.weight(.semibold))
                    Text("\(name) đang mở JP27 ở gần. Hai máy sẽ dùng chung một sổ chi và tự đồng bộ mỗi khi ở gần nhau. Chạm đầu hai máy vào nhau cũng là đồng ý.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            // explicit styles: two buttons in one list row, each its own
            HStack(spacing: 10) {
                Button("Để sau") { model.ledgerSync.decline() }
                    .buttonStyle(.bordered)
                Button("Dùng chung") { model.ledgerSync.accept() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(Palette.card, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// Two rows of the two phones that may be one expense.
struct SpendDuplicatePair: Identifiable {
    let a: Expense
    let b: Expense
    var id: String { LedgerMerge.pairKey(a.id, b.id) }
}

/// The two rows side by side: drop one, or keep both (not asked again, on either phone).
struct SpendDuplicateCard: View {
    @Environment(AppModel.self) private var model
    let pair: SpendDuplicatePair
    /// the row to drop, or nil to keep both
    let resolve: (Expense?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            line(pair.a)
            Divider()
            line(pair.b)
            Button("Giữ cả hai") { resolve(nil) }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func line(_ e: Expense) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.store.place(e.placeID)?.name ?? e.placeName ?? (e.note.isEmpty ? e.spendCategory.label : e.note))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("\(TripTime.clock(e.at)) · \(SpendOrigin.name(of: e, sync: model.ledgerSync))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            YenText(yen: e.yen)
                .font(.subheadline.weight(.semibold))
            Button("Bỏ", role: .destructive) { resolve(e) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Bỏ khoản của \(SpendOrigin.name(of: e, sync: model.ledgerSync))")
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
                        Text("Hai máy cùng mở JP27 ở gần nhau thì sổ chi tự gộp qua Wi‑Fi trực tiếp giữa hai máy, không cần mạng: khoản mới, khoản sửa, khoản xoá. Một bữa cả hai máy cùng ghi thì chỉ tính một lần.")
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
                    Text("Máy kia thấy tên này khi ghép. Lần đầu bật, iPhone hỏi quyền tìm thiết bị trong mạng cục bộ và quyền đo khoảng cách tới thiết bị ở gần.")
                }

                if sync.enabled {
                    Section("Bây giờ") {
                        Label(sync.status, systemImage: sync.nearby != nil ? "arrow.triangle.2.circlepath" : "antenna.radiowaves.left.and.right")
                        if let asking = sync.asking {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("\(asking.name) ở gần và muốn dùng chung sổ chi.")
                                HStack(spacing: 10) {
                                    Button("Để sau") { sync.decline() }
                                        .buttonStyle(.bordered)
                                    Button("Dùng chung") { sync.accept() }
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
                                    Button("Không phải trùng") {
                                        Ledger.restore(t, in: context)
                                        folded = Ledger.folded(context)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    } header: {
                        Text("Đã gộp vì ghi trùng")
                    } footer: {
                        Text("Hai máy cùng ghi một khoản ở cùng chỗ, cùng số tiền, cùng buổi thì chỉ giữ một. Nếu thật ra là hai lần trả, chọn Không phải trùng.")
                    }
                }

                Section {
                } footer: {
                    Text("Khi hai máy không gặp được nhau: xuất sổ chi ra file CSV ở menu ··· của tab Chi tiêu, gửi cho máy kia, rồi gộp file ở máy đó. File không mang theo các khoản đã xoá.")
                }
            }
            .paperList()
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
            }
        }
        .presentationDetents([.large])
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

import SwiftData
import SwiftUI
import TripKit

/// At the door of a restaurant, snack stand or shop (opened from the arrival notification): what to
/// order, how to say it, how to pay, what it should cost, then log what it really cost.
struct AtPlaceView: View {
    @Environment(AppModel.self) private var model
    let id: String

    @Query private var expenses: [Expense]
    @Query private var topups: [Topup]
    @State private var shown: TalkShowItem?
    /// the scanner or a new expense opened from the buttons at the foot
    @State private var opened = 0

    var body: some View {
        Group {
            if let place = model.store.place(id) {
                if place.hero != nil {
                    content(place).detailPage(title: place.name, heroHeight: 360)
                } else {
                    content(place)
                        .navigationTitle(place.name)
                        .navigationBarTitleDisplayMode(.inline)
                }
            } else {
                ContentUnavailableView("Không có địa điểm này", systemImage: "mappin.slash")
            }
        }
        .phraseCover($shown)
    }

    private func content(_ place: Place) -> some View {
        let stop = model.today?.stops.first { $0.stop.place == place.id }?.stop
        let estimate = Spend.estimate(stop: stop, place: place, people: model.people)
        let wallet = SpendWallet(expenses: expenses, topups: topups)
        return ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                if let photo = place.hero {
                    DetailHero(title: place.name, height: 360) {
                        PlacePhoto(photo: photo, maxPixel: 1800)
                    } foot: {
                        EmptyView()
                    }
                }
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    header(place)
                    order(place)
                    say(place)
                    money(place, estimate: estimate, wallet: wallet)
                    actions(place, estimate: estimate)
                }
                .padding(.horizontal, Metrics.gutter)
            }
            .padding(.bottom, 32)
        }
        .screen()
    }

    private func header(_ place: Place) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if place.hero == nil {
                Text(place.name).font(.title.weight(.bold))
            }
            if let ja = place.ja {
                let item = TalkShowItem(id: "name-\(place.id)", ja: ja, romaji: place.name)
                Button { shown = item } label: {
                    Text(ja).font(.title2.weight(.semibold)).environment(\.locale, Locale(identifier: "ja_JP"))
                }
                .buttonStyle(.pressable(.plain))
                .sheetSource(item.source)
                .accessibilityHint("Hiện tên quán chữ lớn")
            }
            if let tip = place.menu?.orderTip {
                Label(tip, systemImage: "lightbulb").font(.subheadline).foregroundStyle(.secondary)
            }
            if place.menu?.ticketMachine == true {
                Tag(text: "Gọi món ở máy bán vé", symbol: "ticket")
            }
        }
    }

    @ViewBuilder
    private func order(_ place: Place) -> some View {
        let dishes = (place.menu?.items ?? []).sorted { $0.rank < $1.rank }.prefix(3)
        let snacks = place.snack?.get ?? []
        if !dishes.isEmpty || !snacks.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Nên gọi")
                Card {
                    if !dishes.isEmpty {
                        ForEach(Array(dishes.enumerated()), id: \.offset) { i, item in
                            if i > 0 { Divider() }
                            let show = TalkShowItem(id: "dish-\(item.ja)", ja: item.ja, romaji: item.romaji, vi: item.vi)
                            Button { shown = show } label: {
                                DishRow(item: item).contentShape(.rect)
                            }
                            .buttonStyle(.pressable(.plain))
                            .sheetSource(show.source)
                        }
                    } else {
                        ForEach(Array(snacks.prefix(3).enumerated()), id: \.offset) { i, g in
                            if i > 0 { Divider() }
                            let show = TalkShowItem(id: "get-\(g.ja)", ja: g.ja, romaji: g.romaji, vi: g.vi)
                            Button { shown = show } label: {
                                HStack(alignment: .top) {
                                    JapaneseLine(ja: g.ja, romaji: g.romaji, vi: g.vi, size: .headline)
                                    Spacer(minLength: 0)
                                    if let yen = g.yen { YenText(yen: yen).font(.subheadline.weight(.semibold)) }
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.pressable(.plain))
                            .sheetSource(show.source)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func say(_ place: Place) -> some View {
        let phrases = Array(model.store.scenarios(for: place).flatMap(\.phrases).prefix(6))
        if !phrases.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Nói")
                Card {
                    ForEach(Array(phrases.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Divider() }
                        TalkPhraseRow(item: TalkShowItem(p), show: { shown = $0 })
                    }
                }
            }
        }
    }

    private func money(_ place: Place, estimate: Estimate?, wallet: SpendWallet) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Label(payLabel(place.payment), systemImage: place.payment == .cash ? "banknote" : "creditcard")
                    .font(.body.weight(.semibold))
                Spacer()
                if let estimate {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(estimate.label).font(.title3.weight(.semibold)).monospacedDigit()
                        Text("dự kiến cho \(model.people) người").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if place.payment != .card {
                HStack {
                    Text("Tiền mặt đang có").foregroundStyle(.secondary)
                    Spacer()
                    YenText(yen: wallet.cash)
                }
                .font(.subheadline)
                if let estimate, wallet.cash < estimate.high {
                    Label("Có thể không đủ tiền mặt — rút thêm ở 7-Eleven gần đó.", systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func payLabel(_ pay: Payment?) -> String {
        switch pay {
        case .cash: "Chỉ tiền mặt"
        case .card: "Trả thẻ được"
        case .mixed: "Tiền mặt hoặc thẻ"
        case nil: "Chưa rõ cách trả"
        }
    }

    private func actions(_ place: Place, estimate: Estimate?) -> some View {
        HStack(spacing: 12) {
            if place.menu != nil || place.kind == .food {
                Button {
                    opened += 1
                    model.present(.menuScan(place.id), from: "at.\(place.id).scan")
                } label: {
                    Label("Quét menu", systemImage: "text.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .sheetSource("at.\(place.id).scan")
            }
            Button {
                opened += 1
                model.present(.expense(placeID: place.id, yen: estimate?.mid), from: "at.\(place.id).expense")
            } label: {
                Label("Ghi chi thật", systemImage: "yensign").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .sheetSource("at.\(place.id).expense")
        }
        .controlSize(.large)
        .sensoryFeedback(.press, trigger: opened)
    }
}

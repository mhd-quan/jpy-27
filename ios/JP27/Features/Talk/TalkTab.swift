import SwiftUI
import TripKit

/// Sổ tay: listen and scan up top, then the phrasebook by situation, the trip's own sentences,
/// station names to recognise, and the handbook one level down.
struct TalkTab: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var shown: TalkShowItem?

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.talkPath) {
            ScrollView {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    content
                } else {
                    TalkSearchResults(query: query, show: { shown = $0 })
                }
            }
            .screen()
            .navigationTitle("Sổ tay")
            .searchable(text: $query, prompt: "Tìm câu tiếng Nhật hoặc tiếng Việt")
            .navigationDestination(for: Route.self) { RouteHost(route: $0) }
            .phraseCover($shown)
        }
    }

    private var guide: Guide { model.guide }

    private var content: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            actions
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle(group.title)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(group.list) { s in
                            NavigationLink(value: Route.scenario(s.id)) { TalkScenarioTile(scenario: s) }
                                .buttonStyle(.pressable)
                        }
                    }
                }
            }
            if !guide.phrases.trip.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Câu riêng cho chuyến này")
                    Card {
                        ForEach(Array(guide.phrases.trip.enumerated()), id: \.offset) { i, p in
                            if i > 0 { Divider() }
                            TalkPhraseRow(item: TalkShowItem(id: "trip-\(i)", ja: p.ja, romaji: p.romaji, vi: p.vi), label: p.use, show: { shown = $0 })
                        }
                    }
                }
            }
            if !guide.phrases.stations.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionTitle("Tên ga nên nhớ")
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 10)], spacing: 10) {
                        ForEach(guide.phrases.stations, id: \.ja) { st in
                            let item = TalkShowItem(id: "st-\(st.ja)", ja: st.ja, romaji: st.romaji)
                            Button { shown = item } label: {
                                VStack(spacing: 2) {
                                    Text(st.ja).font(.title2.weight(.bold)).environment(\.locale, Locale(identifier: "ja_JP"))
                                    Text(st.romaji).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .background(Palette.card, in: .rect(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .sheetSource(item.source)
                            .accessibilityLabel("\(st.romaji), \(st.ja)")
                        }
                    }
                }
            }
            NavigationLink(value: Route.handbook) {
                Card {
                    HStack {
                        Label {
                            Text("Cẩm nang").font(.body.weight(.semibold))
                        } icon: {
                            GlyphTile(symbol: "book.closed.fill", tint: Palette.ai, size: 28)
                        }
                        Spacer()
                        Text("Vé, hành lý, onsen").font(.subheadline).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.bottom, 32)
    }

    /// Listen and scan: the two things done with the phone held out, on glass tiles.
    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                TalkActionTile(title: "Nghe", symbol: "translate") { model.present(.listen, from: "talk.listen") }
                    .sheetSource("talk.listen")
                TalkActionTile(title: "Quét menu", symbol: "text.viewfinder") { model.present(.menuScan(TalkNearby.foodPlace(model)), from: "talk.scan") }
                    .sheetSource("talk.scan")
            }
        }
        .padding(.top, 8)
    }

    private var groups: [TalkGroup] {
        let byID = Dictionary(guide.phrases.scenarios.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var out = guide.phrases.groups.map { g in TalkGroup(title: g.title, list: g.ids.compactMap { byID[$0] }) }
        let grouped = Set(guide.phrases.groups.flatMap(\.ids))
        let others = guide.phrases.scenarios.filter { !grouped.contains($0.id) }
        if !others.isEmpty { out.append(TalkGroup(title: "Khác", list: others)) }
        return out.filter { !$0.list.isEmpty }
    }
}

private struct TalkGroup: Identifiable {
    let title: String
    let list: [Scenario]
    var id: String { title }
}

private struct TalkActionTile: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 30, weight: .semibold))
                Text(title).font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 96)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: 24))
    }
}

private struct TalkScenarioTile: View {
    let scenario: Scenario

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlyphTile(symbol: TalkSymbols.scenario(scenario.id), tint: TalkSymbols.tint(scenario.id), size: 34)
            Text(scenario.vi)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.leading)
                .lineLimit(2, reservesSpace: true)
            Text("\(scenario.phrases.count) câu")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.card, in: .rect(cornerRadius: 20, style: .continuous))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Phrases matching a search, across every scenario and the trip's own sentences.
private struct TalkSearchResults: View {
    @Environment(AppModel.self) private var model
    let query: String
    let show: (TalkShowItem) -> Void

    var body: some View {
        let hits = results
        VStack(alignment: .leading, spacing: 12) {
            if hits.isEmpty {
                ContentUnavailableView.search(text: query)
                    .padding(.top, 40)
            } else {
                Card {
                    ForEach(Array(hits.enumerated()), id: \.offset) { i, hit in
                        if i > 0 { Divider() }
                        TalkPhraseRow(item: hit.item, label: hit.scenario, note: nil, show: show)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 12)
    }

    private var results: [TalkHit] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let folded = JapaneseText.fold(q)
        func hit(_ ja: String, _ romaji: String, _ vi: String) -> Bool {
            ja.contains(q) || romaji.localizedStandardContains(q) || vi.localizedStandardContains(q)
                || (!folded.isEmpty && JapaneseText.fold(ja).contains(folded))
        }
        let phrases = model.guide.phrases
        var out: [TalkHit] = []
        for (i, p) in phrases.trip.enumerated() where hit(p.ja, p.romaji, p.vi) {
            out.append(TalkHit(item: TalkShowItem(id: "trip-\(i)", ja: p.ja, romaji: p.romaji, vi: p.vi), scenario: p.use))
        }
        for s in phrases.scenarios {
            for p in s.phrases where hit(p.ja, p.romaji, p.vi) {
                out.append(TalkHit(item: TalkShowItem(p), scenario: s.vi))
            }
        }
        return Array(out.prefix(60))
    }
}

private struct TalkHit {
    let item: TalkShowItem
    let scenario: String
}

/// The food place a menu scan most likely concerns: the one you are at, else today's next meal.
enum TalkNearby {
    static func foodPlace(_ model: AppModel) -> String? {
        guard let day = model.today else { return nil }
        let foods = day.stops.compactMap { entry -> (index: Int, place: Place)? in
            guard let p = model.store.place(entry.stop.place), p.kind == .food || p.menu != nil else { return nil }
            return (entry.index, p)
        }
        if let here = model.position,
           let near = foods.min(by: { Geo.km($0.place.coordinate, here) < Geo.km($1.place.coordinate, here) }),
           Geo.km(near.place.coordinate, here) < 0.3 {
            return near.place.id
        }
        return foods.first { $0.index >= model.cursor }?.place.id
    }
}

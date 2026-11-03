import SwiftUI
import TripKit

/// One situation of the phrasebook: what to say, and what you are likely to hear back.
struct ScenarioView: View {
    @Environment(AppModel.self) private var model
    let id: String
    @State private var shown: TalkShowItem?

    var body: some View {
        Group {
            if let scenario = model.store.scenario(id) {
                content(scenario)
                    .navigationTitle(scenario.vi)
            } else {
                ContentUnavailableView("Không có tình huống này", systemImage: "text.bubble")
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .phraseCover($shown)
    }

    private func content(_ s: Scenario) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                if let hint = s.hint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Card {
                    ForEach(Array(s.phrases.enumerated()), id: \.element.id) { i, p in
                        if i > 0 { Divider() }
                        TalkPhraseRow(item: TalkShowItem(p), note: p.note, show: { shown = $0 })
                    }
                }
                if !s.hear.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Bạn có thể nghe")
                        Card {
                            ForEach(Array(s.hear.enumerated()), id: \.offset) { i, h in
                                if i > 0 { Divider() }
                                ScenarioHeardRow(heard: h, show: { shown = $0 })
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
    }
}

/// A line staff may say, and the reply to give.
private struct ScenarioHeardRow: View {
    let heard: Heard
    let show: (TalkShowItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                JapaneseLine(ja: heard.ja, romaji: heard.romaji, vi: heard.vi, size: .body)
                Spacer(minLength: 0)
                TalkSpeakButton(ja: heard.ja)
            }
            if let reply = heard.reply {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 4)
                        .accessibilityLabel("Đáp")
                    let item = TalkShowItem(id: "reply-\(heard.ja)", ja: reply.ja, romaji: reply.romaji)
                    Button {
                        show(item)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reply.ja).font(.headline).environment(\.locale, Locale(identifier: "ja_JP"))
                            Text(reply.romaji).font(.caption).italic().foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable(.plain))
                    .sheetSource(item.source)
                    TalkSpeakButton(ja: reply.ja)
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

/// Cẩm nang: passes worth buying, luggage and tax refunds, onsen manners, weather, shopping rules.
struct HandbookView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let guide = model.guide
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.stack) {
                if !guide.passes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Vé và thẻ")
                        Card {
                            ForEach(Array(guide.passes.enumerated()), id: \.offset) { i, pass in
                                if i > 0 { Divider() }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Tag(text: pass.verdict, symbol: pass.recommended ? "checkmark" : "xmark", tint: pass.recommended ? .green : .secondary)
                                        Text(pass.name).font(.body.weight(.semibold))
                                    }
                                    Text(pass.text).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                ForEach(guide.notes) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        // a group's passes sit under the same heading; its notes follow without a second title
                        if group.id != "ve" || guide.passes.isEmpty { SectionTitle(group.title) }
                        Card {
                            ForEach(Array(group.notes.enumerated()), id: \.element.id) { i, note in
                                if i > 0 { Divider() }
                                VStack(alignment: .leading, spacing: 4) {
                                    if note.title != group.title {
                                        Text(note.title).font(.headline)
                                    }
                                    Text(note.text).font(.subheadline)
                                }
                            }
                        }
                    }
                }
                if let tax = guide.shopping.taxFree {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Hoàn thuế khi mua sắm")
                        Card { Text(tax).font(.subheadline) }
                    }
                }
                if !guide.shopping.rules.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Nguyên tắc mua sắm")
                        Card {
                            ForEach(Array(guide.shopping.rules.enumerated()), id: \.offset) { i, rule in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(i + 1)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(.secondary)
                                    Text(rule).font(.subheadline)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
        .navigationTitle("Cẩm nang")
        .navigationBarTitleDisplayMode(.large)
    }
}

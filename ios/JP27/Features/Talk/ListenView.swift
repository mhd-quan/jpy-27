import SwiftUI
import TripKit

/// Hold the phone toward the speaker: Japanese appears as it is said, each finished sentence is
/// translated to Vietnamese on the phone, and a sentence the phrasebook knows comes with its reply.
struct ListenView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model
    @State private var listener: TalkListener?
    @State private var translator = TalkTranslator()
    @State private var shown: TalkShowItem?

    var body: some View {
        NavigationStack {
            Group {
                if let listener {
                    transcript(listener)
                } else {
                    ProgressView()
                }
            }
            .screen()
            .navigationTitle("Nghe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                CloseButton()
                // leave the item out (ToolbarContent.hidden is not on iOS), so the bar morphs
                // instead of keeping an empty slot
                if let listener, !listener.sentences.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Xoá", systemImage: "trash") { listener.clear() }
                    }
                }
            }
            // a bar, not an inset: the transcript scrolls under the button and fades out there
            .safeAreaBar(edge: .bottom) {
                if let listener { recordButton(listener) }
            }
        }
        .talkTranslation(translator)
        .phraseCover($shown)
        .task {
            if listener == nil { listener = TalkListener(scenarios: model.guide.phrases.scenarios) }
        }
        .onDisappear {
            if let listener { Task { await listener.stop() } }
        }
    }

    private func transcript(_ listener: TalkListener) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    TalkTranslationPackRow(translator: translator)
                        .padding(.bottom, 4)
                    if case .unavailable(let message) = listener.state {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ListenHint(listener: listener)
                    ForEach(listener.sentences) { s in
                        ListenBubble(sentence: s, vi: translator.translation(s.id.uuidString), failed: translator.failed.contains(s.id.uuidString), show: { shown = $0 })
                            .id(s.id)
                            .onAppear { translator.enqueue(id: s.id.uuidString, text: s.ja) }
                    }
                    ListenPartial(listener: listener, proxy: proxy)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, 12)
            }
            .onChange(of: listener.sentences.count) {
                if let last = listener.sentences.last?.id {
                    withAnimation(Motion.reduced(Motion.settle, reduceMotion)) { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    private func recordButton(_ listener: TalkListener) -> some View {
        let on = listener.isListening
        return Button {
            Task { await listener.toggle() }
        } label: {
            Group {
                if listener.state == .preparing {
                    ProgressView()
                } else {
                    Image(systemName: on ? "stop.fill" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.pulse, isActive: on)
                }
            }
            .frame(width: 84, height: 84)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(on ? .red : .accentColor)
        .disabled(listener.state == .preparing)
        .sensoryFeedback(.start, trigger: on) { _, new in new }
        .sensoryFeedback(.stop, trigger: on) { old, _ in old }
        // the mic asked for and refused, or it would not start; only a tap gets it this far
        .sensoryFeedback(.fail, trigger: listener.state) { _, new in
            if case .unavailable = new { return true }
            return false
        }
        .accessibilityLabel(on ? "Dừng nghe" : "Bắt đầu nghe")
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }
}

/// A heard sentence, its translation, and the phrasebook's reply when it recognises the line.
private struct ListenBubble: View {
    let sentence: TalkSentence
    let vi: String?
    let failed: Bool
    let show: (TalkShowItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(sentence.ja)
                .font(.title3.weight(.semibold))
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .textSelection(.enabled)
            if let vi {
                Text(vi).font(.body)
            } else if failed {
                Text("Chưa dịch được — cần gói dịch trên máy.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
            if let hit = sentence.hit {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Label(hit.heard.vi, systemImage: "book.closed")
                        .font(.subheadline.weight(.medium))
                    if let reply = hit.heard.reply {
                        HStack(alignment: .top) {
                            let item = TalkShowItem(id: "reply-\(sentence.id)", ja: reply.ja, romaji: reply.romaji)
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
                    }
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.card, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

// The words still being heard change several times a second. Each piece that reads them is its
// own view, so they redraw that line and not the whole screen (bar, transcript, button).

/// What to do, until something is heard.
private struct ListenHint: View {
    let listener: TalkListener

    var body: some View {
        if listener.sentences.isEmpty, listener.partial.isEmpty, listener.state != .listening {
            ContentUnavailableView("Chạm micro rồi đưa máy về phía người nói", systemImage: "waveform")
                .padding(.top, 60)
        }
    }
}

/// The sentence still being said, kept in view as it grows.
private struct ListenPartial: View {
    let listener: TalkListener
    let proxy: ScrollViewProxy

    var body: some View {
        if !listener.partial.isEmpty {
            Text(listener.partial)
                .font(.title3)
                .foregroundStyle(.secondary)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .id("partial")
                .onAppear { proxy.scrollTo("partial", anchor: .bottom) }
                .onChange(of: listener.partial) { proxy.scrollTo("partial", anchor: .bottom) }
        }
    }
}

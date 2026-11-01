import Observation
import SwiftUI
import Translation
import TripKit
import UIKit

// Pieces the phrasebook, the listener, the menu scanner and the at-the-door card share.

/// A sentence to hold up to staff.
struct TalkShowItem: Identifiable, Hashable {
    let id: String
    let ja: String
    var romaji: String?
    var vi: String?

    init(id: String, ja: String, romaji: String? = nil, vi: String? = nil) {
        self.id = id
        self.ja = ja
        self.romaji = romaji
        self.vi = vi
    }

    init(_ p: Phrase) {
        self.init(id: p.id, ja: p.filledJa, romaji: p.filledRomaji, vi: p.vi)
    }

    /// The `sheetSource` of the line the card grows out of.
    var source: String { "show.\(id)" }
}

extension View {
    /// The full-screen card for `item`, grown out of the line that was tapped (marked with
    /// `sheetSource(item.source)`) and shrunk back into it on close.
    func phraseCover(_ item: Binding<TalkShowItem?>) -> some View {
        modifier(TalkPhraseCover(item: item))
    }
}

private struct TalkPhraseCover: ViewModifier {
    @Binding var item: TalkShowItem?
    @Environment(\.zoomSpace) private var space

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $item) { shown in
            TalkShowCard(item: shown)
                .zoomed(from: shown.source, in: space)
        }
    }
}

/// Full screen, black on white, Japanese as large as fits: for the person across the counter.
/// The rotate button turns the text sideways for a wider line without turning the app.
struct TalkShowCard: View {
    let item: TalkShowItem
    @Environment(\.dismiss) private var dismiss
    @State private var sideways = false

    var body: some View {
        GeometryReader { geo in
            let box = sideways ? CGSize(width: geo.size.height, height: geo.size.width) : geo.size
            VStack(spacing: 20) {
                Text(item.ja)
                    .font(.system(size: 160, weight: .bold))
                    .minimumScaleFactor(0.08)
                    .lineLimit(6)
                    .multilineTextAlignment(.center)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                if let r = item.romaji {
                    Text(r)
                        .font(.title2)
                        .italic()
                        .minimumScaleFactor(0.5)
                        .lineLimit(2)
                        .foregroundStyle(.black.opacity(0.6))
                }
                if let vi = item.vi {
                    Text(vi)
                        .font(.body)
                        .lineLimit(3)
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 28)
            .padding(.vertical, sideways ? 28 : 110)
            .frame(width: box.width, height: box.height)
            .rotationEffect(.degrees(sideways ? 90 : 0))
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.smooth(duration: 0.35), value: sideways)
        }
        .foregroundStyle(.black)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .overlay(alignment: .top) { controls }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .accessibilityElement(children: .contain)
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.title3.weight(.semibold)).frame(width: 48, height: 48)
                }
                .accessibilityLabel("Đóng")
                Spacer()
                Button { sideways.toggle() } label: {
                    Image(systemName: "rotate.right").font(.title3.weight(.semibold)).frame(width: 48, height: 48)
                }
                .accessibilityLabel(sideways ? "Dựng thẳng" : "Xoay ngang")
                Button { Speaker.shared.say(item.ja) } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title3.weight(.semibold)).frame(width: 48, height: 48)
                }
                .accessibilityLabel("Phát âm")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}

/// Plays Japanese aloud; hold for a slower reading.
struct TalkSpeakButton: View {
    let ja: String
    var size: CGFloat = 44

    var body: some View {
        let active = Speaker.shared.speaking == ja
        Image(systemName: active ? "speaker.wave.3.fill" : "speaker.wave.2")
            .font(.body.weight(.semibold))
            .symbolEffect(.variableColor.iterative, isActive: active)
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .contentShape(.rect)
            .onLongPressGesture(minimumDuration: 0.4) { Speaker.shared.say(ja, slow: true) }
            .onTapGesture { Speaker.shared.say(ja) }
            .accessibilityElement()
            .accessibilityLabel("Phát âm")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Speaker.shared.say(ja) }
            .accessibilityAction(named: "Đọc chậm") { Speaker.shared.say(ja, slow: true) }
    }
}

/// A phrase: Japanese, reading, meaning, a note, and a speaker. Tapping opens the full-screen card.
struct TalkPhraseRow: View {
    let item: TalkShowItem
    var label: String?
    var note: String?
    let show: (TalkShowItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { show(item) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    if let label {
                        Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text(item.ja)
                        .font(.title3.weight(.semibold))
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    if let r = item.romaji { Text(r).font(.subheadline).italic().foregroundStyle(.secondary) }
                    if let vi = item.vi { Text(vi).font(.subheadline) }
                    if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .sheetSource(item.source)
            .accessibilityHint("Hiện chữ lớn cho nhân viên")
            TalkSpeakButton(ja: item.ja)
        }
    }
}

/// SF Symbol for a phrasebook scenario.
enum TalkSymbols {
    static func scenario(_ id: String) -> String {
        switch id {
        case "greet": "hand.wave"
        case "table": "person.2"
        case "order": "list.bullet.rectangle"
        case "shokken": "ticket"
        case "ask-food": "questionmark.bubble"
        case "diet": "leaf"
        case "izakaya": "wineglass"
        case "cafe": "cup.and.saucer"
        case "pay": "creditcard"
        case "reserve": "calendar.badge.clock"
        case "takeout": "takeoutbag.and.cup.and.straw"
        case "ticket": "ticket.fill"
        case "platform": "tram"
        case "bus": "bus"
        case "lost": "questionmark.circle"
        case "locker": "lock"
        case "taxi": "car"
        case "checkin": "key"
        case "forward": "shippingbox"
        case "ryokan": "bed.double"
        case "onsen": "drop"
        case "room-problem": "wrench.and.screwdriver"
        case "checkout": "door.left.hand.open"
        case "temple": "building.columns"
        case "directions": "signpost.right"
        case "shop": "bag"
        case "souvenir": "gift"
        case "kimono": "tshirt"
        case "ferry": "ferry"
        case "health": "cross.case"
        case "pharmacy": "pills"
        case "emergency": "exclamationmark.triangle"
        default: "text.bubble"
        }
    }
}

// MARK: - Offline translation

/// Japanese → Vietnamese with Apple's Translation framework, on device once the language pack is
/// installed. Views queue texts and attach `.talkTranslation(translator)`; the session runs there.
@Observable final class TalkTranslator {
    static let source = Locale.Language(identifier: "ja")
    static let target = Locale.Language(identifier: "vi")

    private(set) var results: [String: String] = [:]
    private(set) var failed: Set<String> = []
    private(set) var status: LanguageAvailability.Status?
    var configuration: TranslationSession.Configuration?
    private var queue: [(id: String, text: String)] = []
    private var wantsDownload = false

    var needsDownload: Bool { status == .supported }
    var unsupported: Bool { status == .unsupported }

    func translation(_ id: String) -> String? { results[id] }

    func enqueue(id: String, text: String) {
        guard results[id] == nil, !queue.contains(where: { $0.id == id }) else { return }
        queue.append((id, text))
        trigger()
    }

    /// Ask the system to fetch the Japanese–Vietnamese pack, for use without signal.
    func download() {
        wantsDownload = true
        trigger()
    }

    private func trigger() {
        if configuration == nil {
            configuration = TranslationSession.Configuration(source: Self.source, target: Self.target)
        } else {
            configuration?.invalidate()
        }
    }

    func refreshStatus() async {
        status = await LanguageAvailability().status(from: Self.source, to: Self.target)
    }

    /// Runs inside `.translationTask`, on the main actor.
    func run(_ session: TranslationSession) async {
        if wantsDownload {
            wantsDownload = false
            try? await session.prepareTranslation()
        }
        let jobs = queue
        queue = []
        if !jobs.isEmpty {
            let requests = jobs.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id) }
            do {
                for response in try await session.translations(from: requests) {
                    if let id = response.clientIdentifier { results[id] = response.targetText }
                }
            } catch {
                failed.formUnion(jobs.map { $0.id })
            }
        }
        await refreshStatus()
    }
}

extension View {
    func talkTranslation(_ translator: TalkTranslator) -> some View {
        translationTask(translator.configuration) { session in
            await translator.run(session)
        }
        .task { await translator.refreshStatus() }
    }
}

/// "Tải gói Nhật–Việt" when the pack is not on the phone yet.
struct TalkTranslationPackRow: View {
    let translator: TalkTranslator

    var body: some View {
        if translator.needsDownload {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(Color.accentColor)
                Text("Gói dịch Nhật–Việt chưa có trên máy, nên tải trước khi mất sóng.")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Button("Tải") { translator.download() }
                    .buttonStyle(.bordered)
            }
        } else if translator.unsupported {
            Label("Máy này chưa dịch được Nhật sang Việt.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

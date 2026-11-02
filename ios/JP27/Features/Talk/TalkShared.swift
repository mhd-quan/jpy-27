import Observation
import SwiftUI
// TranslationSession and its Request are not Sendable, yet its methods are @concurrent, so in
// Swift 6 mode a session handed to a main-actor closure by `.translationTask` cannot be used at all
// (Apple's own sample fails the same way). TalkTranslator.run uses its session one awaited call at
// a time and nothing else holds it, so the module's missing annotations are accepted here.
@preconcurrency import Translation
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
    /// read aloud, or turned sideways for the person across; standing it back up and closing stay quiet
    @State private var pressed = 0

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
                Button {
                    if !sideways { pressed += 1 }
                    sideways.toggle()
                } label: {
                    Image(systemName: "rotate.right").font(.title3.weight(.semibold)).frame(width: 48, height: 48)
                }
                .accessibilityLabel(sideways ? "Dựng thẳng" : "Xoay ngang")
                Button {
                    pressed += 1
                    Speaker.shared.say(item.ja)
                } label: {
                    Image(systemName: "speaker.wave.2.fill").font(.title3.weight(.semibold)).frame(width: 48, height: 48)
                }
                .accessibilityLabel("Phát âm")
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .sensoryFeedback(.press, trigger: pressed)
    }
}

/// Plays Japanese aloud; hold for a slower reading.
struct TalkSpeakButton: View {
    let ja: String
    var size: CGFloat = 44
    // a long press is felt the moment it takes, as the system's own are; a plain tap answers lightly
    @State private var slowed = 0
    @State private var spoken = 0

    var body: some View {
        let active = Speaker.shared.speaking == ja
        Image(systemName: active ? "speaker.wave.3.fill" : "speaker.wave.2")
            .font(.body.weight(.semibold))
            .symbolEffect(.variableColor.iterative, isActive: active)
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .contentShape(.rect)
            .onLongPressGesture(minimumDuration: 0.4) {
                slowed += 1
                Speaker.shared.say(ja, slow: true)
            }
            .onTapGesture {
                spoken += 1
                Speaker.shared.say(ja)
            }
            .accessibilityElement()
            .accessibilityLabel("Phát âm")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { Speaker.shared.say(ja) }
            .accessibilityAction(named: "Đọc chậm") { Speaker.shared.say(ja, slow: true) }
            .sensoryFeedback(.snap, trigger: slowed)
            .sensoryFeedback(.press, trigger: spoken)
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
            .buttonStyle(.pressable(.plain))
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
        case "greet": "hand.wave.fill"
        case "table": "person.2.fill"
        case "order": "menucard.fill"
        case "shokken": "rectangle.and.hand.point.up.left.fill"
        case "ask-food": "questionmark.bubble.fill"
        case "diet": "leaf.fill"
        case "izakaya": "mug.fill"
        case "cafe": "cup.and.saucer.fill"
        case "pay": "yensign.circle.fill"
        case "reserve": "calendar.badge.clock"
        case "takeout": "takeoutbag.and.cup.and.straw.fill"
        case "ticket": "ticket.fill"
        case "platform": "tram.fill"
        case "bus": "bus.fill"
        case "lost": "questionmark.circle.fill"
        case "locker": "lock.fill"
        case "taxi": "car.fill"
        case "checkin": "key.fill"
        case "forward": "shippingbox.fill"
        case "ryokan": "bed.double.fill"
        case "onsen": "bathtub.fill"
        case "room-problem": "wrench.and.screwdriver.fill"
        case "checkout": "door.left.hand.open"
        case "temple": "building.columns.fill"
        case "directions": "signpost.right.fill"
        case "shop": "bag.fill"
        case "souvenir": "gift.fill"
        case "kimono": "tshirt.fill"
        case "ferry": "ferry.fill"
        case "health": "cross.case.fill"
        case "pharmacy": "pills.fill"
        case "emergency": "exclamationmark.triangle.fill"
        default: "text.bubble.fill"
        }
    }

    /// Situations take the colour of what they are about, in Japan's traditional dye colours
    /// (日本の伝統色), each deep enough for a white glyph in light and dark: vermilion of torii and
    /// lacquer for food, indigo of noren and work cloth for getting around, Edo purple for the inn,
    /// pine green for temples and streets, tea gold for shopping, crimson for anything urgent.
    static func tint(_ id: String) -> Color {
        switch id {
        case "greet", "table", "order", "shokken", "ask-food", "diet", "izakaya", "cafe", "pay", "reserve", "takeout":
            Iro.shu
        case "ticket", "platform", "bus", "lost", "locker", "taxi", "ferry":
            Iro.ai
        case "checkin", "forward", "ryokan", "onsen", "room-problem", "checkout":
            Iro.edoMurasaki
        case "health", "pharmacy", "emergency":
            Iro.kurenai
        case "shop", "souvenir":
            Iro.kincha
        default:
            Iro.tokiwa
        }
    }
}

/// 日本の伝統色, the phrasebook's colours.
enum Iro {
    /// 朱 shu: torii, lacquer
    static let shu = Color(hex: "#D3501C")
    /// 藍 ai: indigo dye
    static let ai = Color(hex: "#165E83")
    /// 江戸紫 Edo murasaki
    static let edoMurasaki = Color(hex: "#745399")
    /// 常磐 tokiwa: evergreen pine
    static let tokiwa = Color(hex: "#1E7B4F")
    /// 金茶 kincha: tea gold
    static let kincha = Color(hex: "#B26E1E")
    /// 紅 kurenai: crimson
    static let kurenai = Color(hex: "#C1123A")
    /// 紺青 konjō: Prussian blue, Hokusai's wave
    static let konjo = Color(hex: "#1F3A6E")
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

    /// Runs inside `.translationTask`, on the main actor. The session is only touched here, one
    /// awaited call after another, never from two places at once.
    func run(_ session: TranslationSession) async {
        if wantsDownload {
            wantsDownload = false
            try? await session.prepareTranslation()
        }
        let jobs = queue
        queue = []
        if !jobs.isEmpty {
            do {
                results.merge(try await TalkBatch.translate(jobs, with: session)) { _, new in new }
            } catch {
                failed.formUnion(jobs.map { $0.id })
            }
        }
        await refreshStatus()
    }
}

/// The batch call itself, off the main actor: the requests are made here and never belong to it,
/// and only plain strings come back.
private nonisolated enum TalkBatch {
    @concurrent static func translate(_ jobs: [(id: String, text: String)], with session: TranslationSession) async throws -> [String: String] {
        let requests = jobs.map { TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id) }
        var out: [String: String] = [:]
        for response in try await session.translations(from: requests) {
            if let id = response.clientIdentifier { out[id] = response.targetText }
        }
        return out
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
    @State private var started = 0

    var body: some View {
        if translator.needsDownload {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle").font(.title3).foregroundStyle(Color.accentColor)
                Text("Gói dịch Nhật–Việt chưa có trên máy, nên tải trước khi mất sóng.")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Button("Tải") {
                    started += 1
                    translator.download()
                }
                .buttonStyle(.bordered)
                .sensoryFeedback(.start, trigger: started)
            }
        } else if translator.unsupported {
            Label("Máy này chưa dịch được Nhật sang Việt.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

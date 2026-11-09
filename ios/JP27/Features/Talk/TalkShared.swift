import CoreText
import Observation
import os
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
                .settlesTransition()
                .zoomed(from: shown.source, in: space)
        }
    }
}

/// Full screen, black on white, Japanese as large as fits: for the person across the counter.
/// The rotate button turns the text sideways for a wider line without turning the app.
///
/// Each orientation is its own copy (`TalkShowLayout`), laid out once in its own fixed box, its Japanese size
/// measured once (`TalkShowFit`). Turning swaps the copies (`.id(sideways)`) through `TalkTurn`, which rotates and
/// fades them and never lays them out again: the text has its final line breaks from the first frame. The card used
/// to animate one box and its padding, and the text jumped to its new breaks in that first frame while the box and
/// the rotation were still on their way.
struct TalkShowCard: View {
    let item: TalkShowItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.legibilityWeight) private var weight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sideways = false
    /// read aloud, or turned sideways for the person across; standing it back up and closing stay quiet
    @State private var pressed = 0

    var body: some View {
        GeometryReader { geo in
            // both orientations on every pass (memo hits after the first), so the one not shown is measured before the tap
            let upright = TalkShowLayout(item: item, box: geo.size, sideways: false, typeSize: typeSize, weight: weight)
            let turned = TalkShowLayout(item: item, box: CGSize(width: geo.size.height, height: geo.size.width),
                                        sideways: true, typeSize: typeSize, weight: weight)
            ZStack {
                (sideways ? turned : upright)
                    .rotationEffect(.degrees(sideways ? 90 : 0))
                    // framed to the screen before the transition: while both copies are on screen each reports the
                    // screen's size, so the stack never grows to the turned copy's box and pushes the other aside
                    .frame(width: geo.size.width, height: geo.size.height)
                    .transition(TalkTurn(degrees: reduceMotion ? 0 : (sideways ? -90 : 90)))
                    .id(sideways)
            }
        }
        .foregroundStyle(.black)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        .overlay(alignment: .top) { controls }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        // the screen stays on while the card is up, whatever else keeps it on or lets it go (`KeepAwake`)
        .onAppear { KeepAwake.set(.showCard, true) }
        .onDisappear { KeepAwake.set(.showCard, false) }
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
                    // a card coming to rest in its new orientation
                    withAnimation(Motion.reduced(Motion.settle, reduceMotion)) { sideways.toggle() }
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

/// One orientation of the card: the Japanese at the size measured for this box, its reading and its meaning
/// below, in a box that never changes. `box` is the screen for the upright copy, the screen turned for the
/// sideways one (which the card then rotates as a whole).
private struct TalkShowLayout: View {
    let item: TalkShowItem
    let box: CGSize
    let sideways: Bool
    /// the Japanese line's point size, measured for this box (remembered by `TalkShowFit`)
    let jaSize: Int

    init(item: TalkShowItem, box: CGSize, sideways: Bool, typeSize: DynamicTypeSize, weight: LegibilityWeight?) {
        self.item = item
        self.box = box
        self.sideways = sideways
        jaSize = TalkShowFit.size(of: item, box: box, sideways: sideways, typeSize: typeSize, weight: weight)
    }

    var body: some View {
        VStack(spacing: TalkShowFit.spacing) {
            Text(item.ja)
                .font(.system(size: CGFloat(jaSize), weight: .bold))
                // a safety net only, for where SwiftUI's text and UIKit's measurement disagree: the box is fixed
                // and this copy is laid out once, so it never re-fits during the turn
                .minimumScaleFactor(0.5)
                .lineLimit(TalkShowFit.jaLines)
                .multilineTextAlignment(.center)
                .environment(\.locale, Locale(identifier: "ja_JP"))
            if let r = item.romaji {
                Text(r)
                    .font(.title2)
                    .italic()
                    .minimumScaleFactor(0.5)
                    .lineLimit(TalkShowFit.romajiLines)
                    .foregroundStyle(.black.opacity(0.6))
            }
            if let vi = item.vi {
                Text(vi)
                    .font(.body)
                    .lineLimit(TalkShowFit.viLines)
                    .foregroundStyle(.black.opacity(0.45))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, TalkShowFit.across)
        .padding(.vertical, TalkShowFit.down(sideways: sideways))
        .frame(width: box.width, height: box.height)
    }
}

/// A copy of the card turning in or out: a rotation and a fade, nothing that lays it out again. `degrees` is
/// where the other orientation stands from this copy: +90 for the upright copy (it comes from sideways and goes
/// back there), −90 for the sideways one. Both copies are at the same angle at every instant, so one card turns
/// while its two fixed layouts cross-fade. Under Reduce Motion the card passes 0 and the copies only fade, the
/// sideways one already sideways; `properties` keeps its default (`hasMotion`), with which the system too replaces
/// a transition by a fade under Reduce Motion.
private struct TalkTurn: Transition {
    let degrees: Double

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .rotationEffect(.degrees(phase.isIdentity ? 0 : degrees))
            .opacity(phase.isIdentity ? 1 : 0)
    }
}

/// How large the card's Japanese is in one orientation: the largest whole point size in `sizes` at which UIKit's
/// text system (`NSString.boundingRect`) lays it out within its room in at most `jaLines` lines (`LargestFit`,
/// at most 8 measurements). The room is the box less the padding, and less the reading and the meaning at the
/// Dynamic Type size, which is why that size is in the key: the Japanese itself is a fixed size. Remembered per
/// phrase (its three texts, not its id: a filled template or a heard line can share an id), orientation, box,
/// Dynamic Type size and Bold Text, up to `bound` entries, then forgotten all at once.
private enum TalkShowFit {
    static let sizes = 12...160
    static let jaLines = 6
    static let romajiLines = 2
    static let viLines = 3
    static let spacing: CGFloat = 20
    static let across: CGFloat = 28
    static func down(sideways: Bool) -> CGFloat { sideways ? 28 : 110 }
    static let bound = 64

    private struct Key: Hashable {
        let ja: String
        let romaji: String?
        let vi: String?
        let sideways: Bool
        let typeSize: DynamicTypeSize
        let bold: Bool
        let width: Int
        let height: Int
    }

    private static var memo: [Key: Int] = [:]

    private static let paragraph: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.alignment = .center
        p.lineBreakMode = .byWordWrapping
        // what UILabel uses; that SwiftUI's Text breaks lines the same way is unverified
        p.lineBreakStrategy = .standard
        return p
    }()

    static func size(of item: TalkShowItem, box: CGSize, sideways: Bool, typeSize: DynamicTypeSize,
                     weight: LegibilityWeight?) -> Int {
        let bold = weight == .bold
        let key = Key(ja: item.ja, romaji: item.romaji, vi: item.vi, sideways: sideways, typeSize: typeSize, bold: bold,
                      width: Int(box.width.rounded()), height: Int(box.height.rounded()))
        if let known = memo[key] { return known }
        // the reading and the meaning as SwiftUI draws them: at this Dynamic Type size, bold under Bold Text
        let traits = UITraitCollection(mutations: { t in
            t.preferredContentSizeCategory = UIContentSizeCategory(typeSize)
            t.legibilityWeight = UILegibilityWeight(weight)
        })
        let width = box.width - 2 * across
        var height = box.height - 2 * down(sideways: sideways)
        if let r = item.romaji {
            let title2 = UIFont.preferredFont(forTextStyle: .title2, compatibleWith: traits)
            height -= spacing + measure(r, font: italic(title2), width: width, lines: romajiLines)
        }
        if let vi = item.vi {
            height -= spacing + measure(vi, font: .preferredFont(forTextStyle: .body, compatibleWith: traits),
                                        width: width, lines: viLines)
        }
        // no room left for the Japanese: a first pass before the screen has its size, or a real box that the reading
        // and the meaning fill (a small phone sideways at an accessibility size). The smallest size, not remembered,
        // so measured again on every pass and with no `phrase.fit`; there the reading and the meaning can still be cut
        guard width >= 1, height >= 1 else { return sizes.lowerBound }
        // SwiftUI draws `.bold` heavier under Bold Text. That it is exactly one step heavier (`.heavy`) is
        // unverified: no documentation says so (device check § 5.6 row 5)
        let face: UIFont.Weight = bold ? .heavy : .bold
        let found = LargestFit.size(in: sizes) { n in
            fits(item.ja, font: .systemFont(ofSize: CGFloat(n), weight: face), width: width, height: height)
        }
        if memo.count >= bound { memo.removeAll() }
        memo[key] = found
        let turn = sideways ? "sideways" : "upright"
        Perf.signposter.emitEvent("phrase.fit", "\(turn, privacy: .public) \(key.width, privacy: .public)x\(key.height, privacy: .public)")
        return found
    }

    /// The Japanese at `font` within `width` × `height`, in at most `jaLines` lines. The text is marked Japanese,
    /// as the card shows it under a ja_JP locale, so that it is measured with the glyph fallback and line breaking
    /// it is drawn with. That `NSString` drawing uses the language attribute to pick the fallback font is unverified:
    /// its documentation names localized glyphs and line breaking only. Lines are counted by the height of one line
    /// of the same text under the same attributes, not by `font.lineHeight`: kana and kanji are drawn in a fallback
    /// font, whose lines are not the system font's height.
    private static func fits(_ ja: String, font: UIFont, width: CGFloat, height: CGFloat) -> Bool {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            NSAttributedString.Key(kCTLanguageAttributeName as String): "ja",
        ]
        let r = (ja as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                              options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        // fractional, and the width can pass the one asked for (spaces may overhang): rounded up, as Apple says
        let w = r.width.rounded(.up)
        let h = r.height.rounded(.up)
        guard w <= width, h <= height else { return false }
        // the same glyphs on one unbroken line: its height is one line's, in whatever font they fall back to
        let unbroken = ja.components(separatedBy: .newlines).joined(separator: " ") as NSString
        let one = unbroken.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                        options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        return (h / max(one.height, 1)).rounded() <= CGFloat(jaLines)
    }

    /// The height of a line under the Japanese, at most `lines` lines of `font`.
    private static func measure(_ text: String, font: UIFont, width: CGFloat, lines: Int) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .paragraphStyle: paragraph]
        let r = (text as NSString).boundingRect(with: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude),
                                                options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        return min(r.height.rounded(.up), (CGFloat(lines) * font.lineHeight).rounded(.up))
    }

    /// `font` in italic, keeping its other traits (bold under Bold Text): SwiftUI's `.italic()` on `.title2`
    private static func italic(_ font: UIFont) -> UIFont {
        let d = font.fontDescriptor
        guard let slanted = d.withSymbolicTraits(d.symbolicTraits.union(.traitItalic)) else { return font }
        return UIFont(descriptor: slanted, size: font.pointSize)
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
        // each page has its own translator, asked at every appearance: the log hears of a change only
        if let status, Self.logged != status {
            Self.logged = status
            AppLog.info(.talk, "Gói dịch Nhật–Việt", ["status": "\(status)"])
        }
    }

    /// the pack's status as last logged, this launch
    private static var logged: LanguageAvailability.Status?

    /// An error of the Translation framework in the log: its domain and code, no text of its own (whether
    /// that text quotes what was being translated is not documented).
    private static func code(_ error: any Error) -> String {
        let ns = error as NSError
        return "\(ns.domain):\(ns.code)"
    }

    /// Runs inside `.translationTask`, on the main actor. The session is only touched here, one
    /// awaited call after another, never from two places at once.
    func run(_ session: TranslationSession) async {
        if wantsDownload {
            wantsDownload = false
            // a refusal is only logged, as `try?` left it before
            do {
                try await session.prepareTranslation()
                AppLog.info(.talk, "Tải gói dịch xong")
            } catch {
                AppLog.error(.talk, "Không tải được gói dịch", ["error": Self.code(error)])
            }
        }
        let jobs = queue
        queue = []
        if !jobs.isEmpty {
            do {
                results.merge(try await TalkBatch.translate(jobs, with: session)) { _, new in new }
            } catch {
                failed.formUnion(jobs.map { $0.id })
                // how many, never which: an id of a scanned menu stands for its line of text
                AppLog.warning(.talk, "Không dịch được", ["count": "\(jobs.count)", "error": Self.code(error)])
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

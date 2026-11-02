import Foundation
#if canImport(Darwin)
import CoreFoundation
#endif

/// How Japanese text sounds, in romaji: the same dish is written 天ぷら蕎麦, 天ぷらそば and
/// 天麩羅そば, and only its reading, "tenpura soba", is the same in all three.
public struct Reading: Sendable {
    let read: @Sendable (String) -> String

    public init(_ read: @escaping @Sendable (String) -> String) {
        self.read = read
    }

    /// The system's dictionary (CFStringTokenizer's Latin transcription), on Apple platforms.
    /// Elsewhere there is none, and text reads as itself.
    public static let system = Reading { JapaneseText.romaji($0) }
}

/// Japanese text folded so a scanned menu line and a researched dish name compare by what they say:
/// full-width forms to ASCII, katakana to hiragana, long-vowel marks, punctuation, prices and
/// spaces removed. No language model involved — only string comparison.
public enum JapaneseText {
    public static func fold(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            var v = u.value
            // full-width ASCII → ASCII
            if (0xFF01 ... 0xFF5E).contains(v) { v -= 0xFEE0 }
            // katakana → hiragana (ァ..ヶ)
            if (0x30A1 ... 0x30F6).contains(v) { v -= 0x60 }
            guard let scalar = UnicodeScalar(v) else { continue }
            // drop separators, punctuation, symbols and the long-vowel mark
            if scalar.properties.isWhitespace { continue }
            if v == 0x30FC || v == 0x30FB { continue }
            switch scalar.properties.generalCategory {
            case .connectorPunctuation, .dashPunctuation, .openPunctuation, .closePunctuation,
                 .initialPunctuation, .finalPunctuation, .otherPunctuation, .mathSymbol,
                 .currencySymbol, .modifierSymbol, .otherSymbol:
                continue
            default:
                break
            }
            out.append(scalar)
        }
        var folded = String(out).lowercased()
        // prices and counts are not part of a dish's name
        folded = folded.replacingOccurrences(of: "[0-9]+(円|えん|yen)?", with: "", options: .regularExpression)
        folded = folded.replacingOccurrences(of: "(税込|税別|税抜|込)", with: "", options: .regularExpression)
        return folded
    }

    /// Yen amount written on a menu line: "1,800円", "¥1800", "1800yen".
    public static func price(in line: String) -> Int? {
        let ascii = String(String.UnicodeScalarView(line.unicodeScalars.map { u in
            (0xFF01 ... 0xFF5E).contains(u.value) ? UnicodeScalar(u.value - 0xFEE0)! : u
        }))
        let patterns = ["¥\\s*([0-9][0-9,]*)", "([0-9][0-9,]*)\\s*円", "([0-9][0-9,]*)\\s*yen"]
        for pattern in patterns {
            guard let r = ascii.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            let digits = ascii[r].filter(\.isNumber)
            if let n = Int(digits), n >= 50, n < 1_000_000 { return n }
        }
        return nil
    }

    static func bigrams(_ s: String) -> [String: Int] {
        let chars = Array(s)
        guard chars.count > 1 else { return chars.isEmpty ? [:] : [String(chars): 1] }
        var out: [String: Int] = [:]
        for i in 0 ..< chars.count - 1 { out[String(chars[i ... i + 1]), default: 0] += 1 }
        return out
    }

    /// 0…1 on the written form.
    public static func similarity(_ a: String, _ b: String) -> Double {
        score(fold(a), fold(b))
    }

    /// 0…1 on the written form or, when it says more, on the reading: 天ぷら蕎麦 and 天ぷらそば share
    /// half their characters but all of "tenpurasoba".
    public static func similarity(_ a: String, _ b: String, reading: Reading) -> Double {
        let x = fold(a), y = fold(b)
        let written = score(x, y)
        guard written < 1 else { return 1 }
        return max(written, score(romanized(x, reading), romanized(y, reading)))
    }

    /// Words that turn a dish into another thing to buy: 持ち帰り 牛丼弁当 contains 牛丼, but it is a
    /// takeaway box, not the bowl on the table. Written and read forms both.
    static let otherProduct = ["弁当", "べんとう", "持ち帰り", "持帰り", "もちかえり", "ていくあうと",
                               "bento", "mochikaeri", "teikuauto"]

    /// 0…1 on two folded strings (written or read): Dice on character bigrams; when one contains
    /// the other, lifted in proportion to how much of the longer it is (天ぷらそば in 名物天ぷらそば
    /// is the dish; 牛丼 in a seven-character line is likely something else), and lowered when the
    /// rest makes it another product.
    static func score(_ x: String, _ y: String) -> Double {
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 1 }
        let bx = bigrams(x), by = bigrams(y)
        let shared = bx.reduce(0) { $0 + min($1.value, by[$1.key] ?? 0) }
        let dice = 2 * Double(shared) / Double(bx.values.reduce(0, +) + by.values.reduce(0, +))
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        guard short.count >= 2, let r = long.range(of: short) else { return dice }
        let rest = String(long[..<r.lowerBound]) + String(long[r.upperBound...])
        var lifted = 0.35 + 0.65 * Double(short.count) / Double(long.count)
        if otherProduct.contains(where: { rest.contains($0) && !short.contains($0) }) { lifted *= 0.6 }
        return max(dice, lifted)
    }

    /// The reading, normalised so spellings of one sound meet: no macrons or spaces, long vowels
    /// single (gyūdon, gyuudon → gyudon), m before b/p/m as n (tempura → tenpura), nn → n.
    /// Characters the reader leaves as they are stay, so an unknown word never vanishes.
    static func romanized(_ folded: String, _ reading: Reading) -> String {
        var t = reading.read(folded)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
        t = String(t.filter { $0.isLetter })
        for (pattern, with) in [("m(?=[bpm])", "n"), ("ou", "o"), ("oo", "o"), ("uu", "u"), ("aa", "a"), ("ii", "i"), ("ee", "e"), ("nn", "n")] {
            t = t.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        return t
    }

    /// Romaji for Japanese text, word by word, from the system's dictionary; a word it has no
    /// reading for stays as written.
    public static func romaji(_ s: String) -> String {
        #if canImport(Darwin)
        let cf = s as CFString
        let length = CFStringGetLength(cf)
        guard length > 0 else { return s }
        let tokenizer = CFStringTokenizerCreate(kCFAllocatorDefault, cf, CFRange(location: 0, length: length),
                                                kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale)
        var out = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                out += latin
            } else if let word = CFStringCreateWithSubstring(kCFAllocatorDefault, cf, range) {
                out += word as String
            }
        }
        return out.isEmpty ? s : out
        #else
        return s
        #endif
    }
}

/// Matches recognised menu lines to the dishes researched for a place (research/menus-*.json).
public struct MenuMatcher: Sendable {
    public struct Candidate: Sendable {
        public let placeID: String
        public let item: MenuItem
    }

    public struct Match: Sendable {
        /// the recognised line it came from
        public let line: Int
        public let text: String
        public let candidate: Candidate
        public let score: Double
        /// price printed on the line, if any
        public let printedYen: Int?
    }

    public let candidates: [Candidate]
    public let threshold: Double
    let reading: Reading?
    /// each candidate's name folded, and read, once
    private let written: [String]
    private let read: [String]

    public init(candidates: [Candidate], threshold: Double = 0.55, reading: Reading? = .system) {
        self.candidates = candidates
        self.threshold = threshold
        self.reading = reading
        let folded = candidates.map { JapaneseText.fold($0.item.ja) }
        written = folded
        read = reading.map { r in folded.map { JapaneseText.romanized($0, r) } } ?? []
    }

    /// Dishes of one place, or of every place with a menu when the place is unknown.
    public init(store: TripStore, placeID: String?, threshold: Double = 0.55, reading: Reading? = .system) {
        let places = placeID.flatMap { store.place($0) }.map { [$0] } ?? store.trip.places.filter { $0.menu != nil }
        let cands = places.flatMap { p in (p.menu?.items ?? []).map { Candidate(placeID: p.id, item: $0) } }
            + places.flatMap { p in (p.snack?.get ?? []).map { g in
                Candidate(placeID: p.id, item: MenuItem(ja: g.ja, romaji: g.romaji, vi: g.vi, yen: g.yen, yenNote: nil, pick: .popular, note: nil))
            } }
        self.init(candidates: cands, threshold: threshold, reading: reading)
    }

    /// Best dish for each line that clears the threshold; a dish keeps only its best line.
    public func match(lines: [String]) -> [Match] {
        var best: [String: Match] = [:]
        for (i, text) in lines.enumerated() {
            let folded = JapaneseText.fold(text)
            guard folded.count >= 2 else { continue }
            let sound = reading.map { JapaneseText.romanized(folded, $0) }
            var top: (Candidate, Double)?
            for (k, c) in candidates.enumerated() {
                var s = JapaneseText.score(folded, written[k])
                // the same dish written in other characters: compare how both are read
                if s < 1, let sound, sound.count >= 3, read[k].count >= 3 {
                    s = max(s, JapaneseText.score(sound, read[k]))
                }
                if s > (top?.1 ?? 0) { top = (c, s) }
            }
            guard let (c, s) = top, s >= threshold else { continue }
            let key = c.placeID + "|" + c.item.ja
            if (best[key]?.score ?? 0) < s {
                best[key] = Match(line: i, text: text, candidate: c, score: s, printedYen: JapaneseText.price(in: text))
            }
        }
        return best.values.sorted { $0.line < $1.line }
    }
}

extension MenuItem {
    /// Short Vietnamese name for compact lists: "Kem đậu phụ, nhẹ…" → "Kem đậu phụ".
    public var shortVi: String {
        let cut = vi.firstIndex { ".;,(（".contains($0) } ?? vi.endIndex
        let head = vi[..<cut].components(separatedBy: " — ").first ?? String(vi[..<cut])
        return head.trimmingCharacters(in: .whitespaces)
    }

    /// Order of what to order: the house dish first, drinks last.
    public var rank: Int {
        switch pick {
        case .signature: 0
        case .popular: 1
        case .value: 2
        case .light: 3
        case .side: 4
        case .dessert: 5
        case .drink: 6
        }
    }
}

/// What a heard sentence most likely was, among the phrasebook's "you may hear" lines.
public struct HeardMatcher: Sendable {
    public struct Hit: Sendable {
        public let scenario: String
        public let heard: Heard
        public let score: Double
    }

    let entries: [(String, Heard)]

    public init(scenarios: [Scenario]) {
        entries = scenarios.flatMap { s in s.hear.map { (s.id, $0) } }
    }

    public func best(for transcript: String, threshold: Double = 0.45) -> Hit? {
        var top: Hit?
        for (sid, h) in entries {
            let s = JapaneseText.similarity(transcript, h.ja)
            if s >= threshold, s > (top?.score ?? 0) { top = Hit(scenario: sid, heard: h, score: s) }
        }
        return top
    }
}

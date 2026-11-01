import Foundation

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

    /// 0…1: Dice on character bigrams, lifted when one name contains the other.
    public static func similarity(_ a: String, _ b: String) -> Double {
        let x = fold(a), y = fold(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 1 }
        let bx = bigrams(x), by = bigrams(y)
        let shared = bx.reduce(0) { $0 + min($1.value, by[$1.key] ?? 0) }
        let dice = 2 * Double(shared) / Double(bx.values.reduce(0, +) + by.values.reduce(0, +))
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        if short.count >= 2, long.contains(short) {
            return max(dice, 0.6 + 0.4 * Double(short.count) / Double(long.count))
        }
        return dice
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

    public init(candidates: [Candidate], threshold: Double = 0.55) {
        self.candidates = candidates
        self.threshold = threshold
    }

    /// Dishes of one place, or of every place with a menu when the place is unknown.
    public init(store: TripStore, placeID: String?, threshold: Double = 0.55) {
        let places = placeID.flatMap { store.place($0) }.map { [$0] } ?? store.trip.places.filter { $0.menu != nil }
        let cands = places.flatMap { p in (p.menu?.items ?? []).map { Candidate(placeID: p.id, item: $0) } }
            + places.flatMap { p in (p.snack?.get ?? []).map { g in
                Candidate(placeID: p.id, item: MenuItem(ja: g.ja, romaji: g.romaji, vi: g.vi, yen: g.yen, yenNote: nil, pick: .popular, note: nil))
            } }
        self.init(candidates: cands, threshold: threshold)
    }

    /// Best dish for each line that clears the threshold; a dish keeps only its best line.
    public func match(lines: [String]) -> [Match] {
        var best: [String: Match] = [:]
        for (i, text) in lines.enumerated() {
            let folded = JapaneseText.fold(text)
            guard folded.count >= 2 else { continue }
            var top: (Candidate, Double)?
            for c in candidates {
                let s = JapaneseText.similarity(text, c.item.ja)
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

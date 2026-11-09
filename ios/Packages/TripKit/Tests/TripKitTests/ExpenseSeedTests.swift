import Foundation
import Testing
@testable import TripKit

/// What the expense editor starts with: the amount of an expense being changed, the amount it was
/// opened with, and the note of an expense being changed. The editor saves what it shows.
@Suite struct ExpenseSeedTests {
    @Test func anEditedAmountTheKeypadCouldTypeIsKept() {
        #expect(Yen.seed(editing: 1) == 1)
        #expect(Yen.seed(editing: 1_200) == 1_200)
        #expect(Yen.seed(editing: Yen.maxEntry) == Yen.maxEntry)
    }

    @Test func anEditedAmountTheKeypadCouldNotTypeStartsFromNothing() {
        #expect(Yen.seed(editing: 0) == 0)
        #expect(Yen.seed(editing: -500) == 0)
        #expect(Yen.seed(editing: Yen.maxEntry + 1) == 0)
        #expect(Yen.seed(editing: Int.max) == 0)
    }

    @Test func theAmountAskedForIsHeldToTheKeypad() {
        #expect(Yen.seed(asked: nil) == 0)
        #expect(Yen.seed(asked: 0) == 0)
        #expect(Yen.seed(asked: -1) == 0)
        #expect(Yen.seed(asked: 1) == 1)
        #expect(Yen.seed(asked: Yen.maxEntry) == Yen.maxEntry)
        #expect(Yen.seed(asked: Yen.maxEntry + 1) == Yen.maxEntry)
        #expect(Yen.seed(asked: Int.max) == Yen.maxEntry)
    }

    @Test func aNoteThatFitsIsWholeAndNotLong() {
        let fits = String(repeating: "a", count: LedgerValidation.maxText)
        let seeded = LedgerValidation.seed(note: fits)
        #expect(seeded.text == fits)
        #expect(!seeded.long)
        #expect(LedgerValidation.seed(note: "") == (text: "", long: false))
    }

    @Test func aNoteOneOverIsCutAndLong() {
        let fits = String(repeating: "a", count: LedgerValidation.maxText)
        let seeded = LedgerValidation.seed(note: fits + "b")
        #expect(seeded.text == fits)
        #expect(seeded.long)
    }

    /// The cut counts what a person sees as one character: a flag or an accented letter at the
    /// cut is kept whole or left out whole, never split into its scalars.
    @Test func theCutCountsCharactersNotScalars() {
        let flags = String(repeating: "🇯🇵", count: LedgerValidation.maxText + 1)
        let seededFlags = LedgerValidation.seed(note: flags)
        #expect(seededFlags.long)
        #expect(seededFlags.text == String(repeating: "🇯🇵", count: LedgerValidation.maxText))
        #expect(seededFlags.text.unicodeScalars.count == 2 * LedgerValidation.maxText)

        let accents = String(repeating: "a", count: LedgerValidation.maxText - 1) + "e\u{301}" + "z"
        let seededAccents = LedgerValidation.seed(note: accents)
        #expect(seededAccents.long)
        #expect(seededAccents.text == String(repeating: "a", count: LedgerValidation.maxText - 1) + "e\u{301}")
        #expect(seededAccents.text.count == LedgerValidation.maxText)

        // a combined character that brings the count to exactly the limit is not long
        let exact = String(repeating: "a", count: LedgerValidation.maxText - 1) + "e\u{301}"
        #expect(LedgerValidation.seed(note: exact) == (text: exact, long: false))
    }
}

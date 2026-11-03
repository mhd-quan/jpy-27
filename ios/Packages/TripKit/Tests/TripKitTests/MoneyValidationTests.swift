import Foundation
import Testing
@testable import TripKit

@Suite struct MoneyValidationTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    /// A date's whole milliseconds, as the file keeps it.
    func ms(_ d: Date?) -> Int64? { d.map { Int64(($0.timeIntervalSinceReferenceDate * 1000).rounded(.down)) } }

    func csv(_ rows: [String]) -> String {
        ([LedgerCSV.header.joined(separator: ",")] + rows).joined(separator: "\r\n") + "\r\n"
    }

    // MARK: Yen

    @Test func totalSaturatesInsteadOfTrapping() {
        #expect(Yen.total([Int.max, 1]) == Int.max)
        #expect(Yen.total([1_200, 800]) == 2_000)
        #expect(Yen.total([Int.min, -1]) == Int.min)
        #expect(Yen.total([Int]()) == 0)
    }

    @Test func differenceSaturatesInsteadOfTrapping() {
        #expect(Yen.difference(Int.min, 1) == Int.min)
        #expect(Yen.difference(Int.max, -1) == Int.max)
        #expect(Yen.difference(20_000, 1_200) == 18_800)
        #expect(Yen.difference(0, Yen.total([Int.max, 5])) == -Int.max)
    }

    @Test func capItselfIsAccepted() {
        #expect(Yen.isValidEntry(9_999_999))
        #expect(!Yen.isValidEntry(10_000_000))
        #expect(!Yen.isValidEntry(0))
        #expect(Yen.isValidEntry(1))
        #expect(!Yen.isValidEntry(-1))
        #expect(Yen.maxEntry == 9_999_999)
    }

    @Test func amountsFormatAtTheEndsOfInt() {
        #expect(Fmt.grouped(Int.min) == "−9.223.372.036.854.775.808")
        #expect(Fmt.grouped(Int.max) == "9.223.372.036.854.775.807")
        #expect(Fmt.yen(-1_500) == "¥−1.500")
    }

    @Test func budgetWithAnAbsurdCategoryDoesNotTrap() throws {
        let budget = try #require(Bundle_.store.guide?.budget)
        let status = BudgetStatus(budget: budget, spent: [.food: Int.max, .shop: 1])
        #expect(status.spent == Int.max)
        #expect(status.planned == budget.total)
        #expect(status.rows.first { $0.category == .food }?.left == 172_000 - Int.max)
        let ok = BudgetStatus(budget: budget, spent: [.food: 12_000, .shop: 3_000])
        #expect(ok.spent == 15_000)
        #expect(ok.rows.first { $0.category == .food }?.left == 160_000)
    }

    // MARK: One validation

    @Test func otherPhonesRowsAreScreenedTheSameWay() {
        let bad = LedgerRecord(id: UUID(), yen: Int.max, category: "food", method: "cash", at: now, origin: "b")
        let ok = LedgerRecord(id: UUID(), yen: 900, category: "food", method: "cash", at: now, origin: "b")
        let (state, rejected) = LedgerMerge.screened(LedgerState(records: [bad, ok]), now: now)
        #expect(state.records.map(\.id) == [ok.id])
        #expect(rejected == [bad.id])
    }

    @Test func overlongNoteIsRejected() {
        let long = String(repeating: "a", count: LedgerValidation.maxText + 1)
        let fits = String(repeating: "あ", count: LedgerValidation.maxText)
        let noted = LedgerRecord(id: id(1), yen: 900, category: "food", method: "cash", note: long, at: now, origin: "b")
        let named = LedgerRecord(id: id(2), yen: 900, category: "food", method: "cash", placeName: long, at: now, origin: "b")
        let fine = LedgerRecord(id: id(3), yen: 900, category: "food", method: "cash", placeName: fits, note: fits, at: now, origin: "b")
        #expect(LedgerValidation.maxText == 500)
        #expect(LedgerValidation.problems(noted, now: now) == [.text])
        #expect(LedgerValidation.problems(named, now: now) == [.text])
        #expect(LedgerValidation.problems(fine, now: now).isEmpty)
        let (state, rejected) = LedgerMerge.screened(LedgerState(records: [noted, named, fine]), now: now)
        #expect(state.records.map(\.id) == [id(3)])
        #expect(rejected == [id(1), id(2)])
        // and in a file
        let (records, problems) = LedgerCSV.decode(csv(["\(id(4)),2027-10-20T03:00:00.000Z,d3,12:00,900,food,,cash,,,\(long),other,"]))
        #expect(records.isEmpty)
        #expect(problems == [RowProblem(line: 2, reason: .text)])
    }

    @Test func aDateFarAheadIsTheOldRule() {
        func row(at: Date, edited: Date? = nil) -> LedgerRecord {
            LedgerRecord(id: id(1), yen: 900, category: "food", method: "cash", at: at, updatedAt: edited, origin: "b")
        }
        let slack = LedgerMerge.clockSlack
        #expect(LedgerValidation.problems(row(at: now.addingTimeInterval(slack)), now: now).isEmpty)
        #expect(LedgerValidation.problems(row(at: now.addingTimeInterval(slack + 1)), now: now) == [.futureDate])
        #expect(LedgerValidation.problems(row(at: now, edited: now.addingTimeInterval(slack + 1)), now: now) == [.futureDate])
        #expect(LedgerValidation.problems(row(at: now.addingTimeInterval(5 * 3600)), now: now).isEmpty)
        // logged far ahead, edited since by a clock set right: still from a phone that cannot be believed
        #expect(LedgerValidation.problems(row(at: now.addingTimeInterval(slack + 1), edited: now), now: now) == [.futureDate])
        let both = LedgerRecord(id: id(2), yen: 0, category: "food", method: "cash", at: now.addingTimeInterval(2 * slack), origin: "b")
        #expect(LedgerValidation.problems(both, now: now) == [.amount, .futureDate])
    }

    @Test func sanitizedIsWhatScreeningKeeps() {
        let far = now.addingTimeInterval(LedgerMerge.clockSlack + 60)
        let s = LedgerState(records: [LedgerRecord(id: id(1), yen: 900, category: "food", method: "cash", at: now, origin: "b"),
                                      LedgerRecord(id: id(2), yen: 0, category: "food", method: "cash", at: now, origin: "b"),
                                      LedgerRecord(id: id(3), yen: 900, category: "food", method: "cash", at: far, origin: "b")],
                            tombstones: [LedgerTombstone(id: id(4), at: far), LedgerTombstone(id: id(5), at: now)],
                            kept: ["k"])
        let (state, rejected) = LedgerMerge.screened(s, now: now)
        #expect(LedgerMerge.sanitized(s, now: now) == state)
        #expect(state.records.map(\.id) == [id(1)])
        #expect(rejected == [id(2), id(3)])
        #expect(state.tombstones.map(\.id) == [id(5)], "a deletion dated far ahead is still left out")
        #expect(state.kept == ["k"])
    }

    // MARK: The file

    @Test func headerIsTheThirteenColumns() {
        #expect(LedgerCSV.header.joined(separator: ",") == "id,luc,ngay,gio,yen,khoan,ten_khoan,tra,place_id,cho,ghi_chu,may,sua")
    }

    @Test func csvRowAboveTheKeypadCapIsRejected() {
        let csv = LedgerCSV.header.joined(separator: ",") + "\r\n"
            + "\(UUID()),2027-10-20T03:00:00.000Z,d3,12:00,9223372036854775807,food,,cash,,,,other,\r\n"
            + "\(UUID()),2027-10-20T03:01:00.000Z,d3,12:01,1,food,,cash,,,,other,\r\n"
        let (records, rejected) = LedgerCSV.decode(csv)
        #expect(records.map(\.yen) == [1])
        #expect(rejected == [RowProblem(line: 2, reason: .amount("9223372036854775807"))])
    }

    /// The file the device check imports (docs/superpowers/fixtures/overflow.csv).
    @Test func theDeviceChecksFileReadsAsTheTestSays() throws {
        let url = Bundle_.resources.deletingLastPathComponent().appendingPathComponent("docs/superpowers/fixtures/overflow.csv")
        let (records, rejected) = LedgerCSV.decode(try String(contentsOf: url, encoding: .utf8))
        #expect(records.map(\.yen) == [1])
        #expect(rejected == [RowProblem(line: 2, reason: .amount("9223372036854775807"))])
        // dated before the check, so the clock does not leave it out
        let (state, screened) = LedgerMerge.screened(LedgerState(records: records), now: TripTime.date("2026-11-03", "12:00")!)
        #expect(state.records.count == 1 && screened.isEmpty)
    }

    @Test func eachBadRowSaysWhy() {
        let (records, rejected) = LedgerCSV.decode(csv([
            "not-a-uuid,2027-10-20T03:00:00.000Z,d3,12:00,900,food,,cash,,,,other,",
            "\(id(1)),20/10/2027 12:00,d3,12:00,900,food,,cash,,,,other,",
            "\(id(2)),2027-10-20T03:00:00.000Z,d3,12:00,,food,,cash,,,,other,",
            "\(id(3)),2027-10-20T03:00:00.000Z,d3,12:00,1.200,food,,cash,,,,other,",
            "\(id(4)),2027-10-20T03:00:00.000Z,d3,12:00,-5,food,,cash,,,,other,",
            "\(id(5)),2027-10-20T03:00:00.000Z,d3,12:00,99999999999999999999,food,,cash,,,,other,",
            "\(id(6)),2027-10-20T03:00:00.000Z,d3,12:00,10000000,food,,cash,,,,other,",
            "\(id(7)),2027-10-20T03:00:00.000Z,d3,12:00, 9999999 ,food,,cash,,,,other,",
        ]))
        #expect(records.map(\.id) == [id(7)])
        #expect(records.map(\.yen) == [9_999_999])
        #expect(rejected == [
            RowProblem(line: 2, reason: .id),
            RowProblem(line: 3, reason: .date),
            RowProblem(line: 4, reason: .amount("")),
            RowProblem(line: 5, reason: .amount("1.200")),
            RowProblem(line: 6, reason: .amount("-5")),
            RowProblem(line: 7, reason: .amount("99999999999999999999")),
            RowProblem(line: 8, reason: .amount("10000000")),
        ])
    }

    /// The number a spreadsheet shows: the header is 1, every record after it one more, blank ones
    /// too; a line break inside quotes stays in its record.
    @Test func rowNumbersAreTheSpreadsheetsRows() {
        let text = LedgerCSV.header.joined(separator: ",") + "\r\n"
            + "\r\n"
            + "\(id(1)),2027-10-20T03:00:00.000Z,d3,12:00,900,food,,cash,,,\"two\r\nlines\nand three\",other,\r\n"
            + ",,,,,,,,,,,,\r\n"
            + "\(id(2)),2027-10-20T03:00:00.000Z,d3,12:00,0,food,,cash,,,,other,\r\n"
            + "\n"
            + "\(id(3)),never,d3,12:00,900,food,,cash,,,,other,"
        let (records, rejected) = LedgerCSV.decode(text)
        #expect(records.map(\.id) == [id(1)])
        #expect(records.first?.note == "two\r\nlines\nand three")
        #expect(rejected == [RowProblem(line: 5, reason: .amount("0")), RowProblem(line: 7, reason: .date)])
    }

    @Test func aByteOrderMarkIsNotPartOfTheHeader() {
        let (records, rejected) = LedgerCSV.decode("\u{FEFF}" + csv(["\(id(1)),2027-10-20T03:00:00.000Z,d3,12:00,900,food,,cash,,,,other,"]))
        #expect(records.map(\.id) == [id(1)])
        #expect(rejected.isEmpty)
    }

    @Test func csvRoundTripsWhatItWrites() {
        let rows = [
            LedgerRecord(id: id(1), yen: 1_200, category: "food", method: "cash", placeID: "akafuku", day: "6", note: "tô lớn",
                         at: Date(timeIntervalSince1970: 1_824_000_000.123), updatedAt: Date(timeIntervalSince1970: 1_824_000_100.9996), origin: "PHONE-A"),
            LedgerRecord(id: id(2), yen: 9_999_999, category: "ryokan", method: "card", placeName: "Nhà trọ, bên sông",
                         at: Date(timeIntervalSince1970: 1_824_100_000.0005), origin: "PHONE-B"),
            LedgerRecord(id: id(3), yen: 1, category: "extra", method: "ic", note: "a, \"b\"\nc", at: Date(timeIntervalSince1970: 1_824_200_000), origin: "other"),
        ]
        let text = LedgerCSV.encode(rows, placeName: { $0 == "akafuku" ? "Akafuku" : nil })
        let (back, rejected) = LedgerCSV.decode(text)
        #expect(rejected.isEmpty)
        #expect(back.map(\.id) == rows.map(\.id))
        #expect(back.map(\.yen) == rows.map(\.yen))
        #expect(back.map(\.category) == rows.map(\.category))
        #expect(back.map(\.method) == rows.map(\.method))
        #expect(back.map(\.placeID) == rows.map(\.placeID))
        #expect(back.map(\.placeName) == rows.map(\.placeName))
        #expect(back.map(\.day) == rows.map(\.day))
        #expect(back.map(\.note) == rows.map(\.note))
        #expect(back.map(\.origin) == rows.map(\.origin))
        #expect(back.map { ms($0.at) } == rows.map { ms($0.at) })
        #expect(back.map { ms($0.updatedAt) } == rows.map { ms($0.updatedAt) })
        // read back is never later than written, so a file never outranks the phone's own row
        for (b, r) in zip(back, rows) {
            #expect(b.at <= r.at)
            #expect(b.version <= r.version)
        }
        // and written again, the same file
        #expect(LedgerCSV.encode(back, placeName: { $0 == "akafuku" ? "Akafuku" : nil }) == text)
    }

    @Test func csvKeepsQuotedCommasAndLineBreaks() {
        let notes = ["a, \"b\"\nc", "one\r\ntwo", "cr\ronly", "\"", ","]
        let rows = notes.enumerated().map { i, note in
            LedgerRecord(id: id(i + 1), yen: 500, category: "food", method: "cash", note: note, at: now, origin: "b")
        }
        let text = LedgerCSV.encode(rows, placeName: { _ in nil })
        #expect(text.contains("\"a, \"\"b\"\"\nc\""))
        #expect(text.contains("\"one\r\ntwo\""), "a CRLF inside a note is quoted")
        let (back, rejected) = LedgerCSV.decode(text)
        #expect(rejected.isEmpty)
        #expect(back.map(\.note) == notes)
    }

    /// A row exactly as the build before this one wrote it reads back field for field.
    @Test func anOldExportReadsBackFieldForField() throws {
        let text = "\u{FEFF}id,luc,ngay,gio,yen,khoan,ten_khoan,tra,place_id,cho,ghi_chu,may,sua\r\n"
            + "00000000-0000-0000-0000-000000000001,2027-10-23T03:00:00.250Z,6,12:00,1200,food,Ăn uống,ic,akafuku,Akafuku,\"tô, lớn\",PHONE-A,2027-10-23T04:30:00.001Z\r\n"
            + "00000000-0000-0000-0000-000000000002,2027-10-23T05:00:00.000Z,,14:00,800,xyz,Phụ phí,zzz,,Quán ven đường,,,\r\n"
        let (records, rejected) = LedgerCSV.decode(text)
        #expect(rejected.isEmpty)
        try #require(records.count == 2)
        let a = records[0], b = records[1]
        #expect(a.id == id(1))
        #expect(LedgerCSV.timestamp(a.at) == "2027-10-23T03:00:00.250Z")
        #expect(a.day == "6")
        #expect(a.yen == 1_200)
        #expect(a.category == "food")
        #expect(a.method == "ic")
        #expect(a.placeID == "akafuku")
        #expect(a.placeName == nil, "a place from the data keeps its id, not its name")
        #expect(a.note == "tô, lớn")
        #expect(a.origin == "PHONE-A")
        #expect(a.updatedAt.map(LedgerCSV.timestamp) == "2027-10-23T04:30:00.001Z")
        #expect(a.lat == nil && a.lng == nil && a.itemID == nil)
        #expect(b.id == id(2))
        #expect(b.day == nil)
        #expect(b.category == "extra", "an unknown kind reads as extra")
        #expect(b.method == "cash", "an unknown way to pay reads as cash")
        #expect(b.placeID == nil)
        #expect(b.placeName == "Quán ven đường")
        #expect(b.note == "")
        #expect(b.origin == "other")
        #expect(b.updatedAt == nil)
        // and this build writes the same row the same way
        let again = LedgerCSV.encode([a], placeName: { $0 == "akafuku" ? "Akafuku" : nil })
        #expect(again == "id,luc,ngay,gio,yen,khoan,ten_khoan,tra,place_id,cho,ghi_chu,may,sua\r\n"
            + "00000000-0000-0000-0000-000000000001,2027-10-23T03:00:00.250Z,6,12:00,1200,food,Ăn uống,ic,akafuku,Akafuku,\"tô, lớn\",PHONE-A,2027-10-23T04:30:00.001Z\r\n")
    }

    @Test func datesInTheShapesReadBefore() {
        let shapes = [
            ("2027-10-20T03:00:00.000Z", "2027-10-20T03:00:00.000Z"),
            ("2027-10-20T03:00:00Z", "2027-10-20T03:00:00.000Z"),
            ("2027-10-20T12:00:00.123+09:00", "2027-10-20T03:00:00.123Z"),
            ("2027-10-20T12:00:00+09:00", "2027-10-20T03:00:00.000Z"),
            ("2027-10-20T03:00:00.5Z", "2027-10-20T03:00:00.500Z"),
            ("2027-10-20T03:00:00.999Z", "2027-10-20T03:00:00.999Z"),
        ]
        for (given, read) in shapes {
            #expect(LedgerCSV.date(given).map(LedgerCSV.timestamp) == read, "\(given)")
        }
        #expect(LedgerCSV.date("2027-10-20 03:00:00") == nil)
        #expect(LedgerCSV.date("") == nil)
    }

    /// Written, read and written again, a time stays to the millisecond, and what is read is never
    /// later than what was written (a plain ISO8601FormatStyle loses a millisecond about half the time).
    @Test func timesDoNotDrift() {
        var g = SplitMix64(seed: 27)
        for _ in 0..<100_000 {
            // 2001 to 2039, any fraction of a second
            let original = Date(timeIntervalSinceReferenceDate: Double(g.next() % 1_200_000_000_000_000) / 1_000_000)
            let text = LedgerCSV.timestamp(original)
            guard let back = LedgerCSV.date(text) else { Issue.record("unread \(text)"); return }
            if LedgerCSV.timestamp(back) != text || back > original || ms(back) != ms(original) {
                Issue.record("\(original.timeIntervalSinceReferenceDate) → \(text) → \(back.timeIntervalSinceReferenceDate)")
                return
            }
        }
        // the earliest instant of a millisecond, where the double nearest to it is a hair later:
        // what is read back must not be that hair later
        for bits: UInt64 in [4_740_377_403_820_460_736, 4_740_377_403_821_081_493, 4_740_377_403_821_509_312] {
            let edge = Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
            let back = LedgerCSV.date(LedgerCSV.timestamp(edge))
            #expect(back == edge, "\(LedgerCSV.timestamp(edge))")
        }
        #expect(LedgerCSV.timestamp(Date(timeIntervalSinceReferenceDate: 0)) == "2001-01-01T00:00:00.000Z")
        #expect(LedgerCSV.timestamp(Date(timeIntervalSinceReferenceDate: -0.0004)) == "2000-12-31T23:59:59.999Z")
    }
}

/// A fixed sequence of numbers, the same on every run.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

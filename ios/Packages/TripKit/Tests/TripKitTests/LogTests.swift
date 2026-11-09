import Foundation
import Testing
@testable import TripKit

/// The app's log: one JSON object per line, times to the millisecond in UTC, coordinates rounded to
/// about a kilometre, a file per day of the phone's own calendar, 14 days and 10 MB kept, and a queue
/// that never grows past its cap. Instants here are exact to the millisecond in binary (R-601), so a
/// line read back compares equal to the line written.
@Suite struct LogTests {
    private static let instant = Date(timeIntervalSince1970: 1_800_000_000.5) // 2027-01-15T08:00:00.500Z
    private static let tokyo = TimeZone(identifier: "Asia/Tokyo")!
    private static let saigon = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
    private static let utc = TimeZone(identifier: "UTC")!

    private func line(_ msg: String, level: LogLevel = .info, fields: [String: String]? = nil) -> LogLine {
        LogLine(t: Self.instant, level: level, cat: .app, msg: msg, fields: fields)
    }

    private func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private func files(_ sizes: [(String, Int)]) -> [LogFile] {
        sizes.map { LogFile(name: $0.0, bytes: $0.1) }
    }

    // MARK: - Lines

    @Test func lineEncodesOneJSONObjectPerLine() {
        let written = LogLine(t: Self.instant, level: .warning, cat: .offline, msg: "a\nb", fields: ["area": "nara"])
        let data = written.encoded()
        #expect(data.last == 0x0A)
        #expect(data.filter { $0 == 0x0A }.count == 1)
        #expect(LogLine.decode(data) == written)
    }

    @Test func lineTimeIsTheGivenInstant() throws {
        let encoded = text(line("Mở app").encoded())
        #expect(encoded.contains(#""t":"2027-01-15T08:00:00.500Z""#))
        let cat = try #require(encoded.range(of: #""cat""#))
        let level = try #require(encoded.range(of: #""level""#))
        #expect(cat.lowerBound < level.lowerBound)
        // the whole line: keys sorted, nothing else in it
        #expect(encoded == #"{"cat":"app","level":"info","msg":"Mở app","t":"2027-01-15T08:00:00.500Z"}"# + "\n")
    }

    @Test func fieldsOmittedWhenNil() {
        let bare = line("Vào app")
        #expect(!text(bare.encoded()).contains("fields"))
        #expect(LogLine.decode(bare.encoded())?.fields == nil)
    }

    @Test func fieldsAreWrittenSortedAndSlashesKept() {
        let encoded = text(line("Nạp style", fields: ["url": "https://a.b/c", "build": "x"]).encoded())
        #expect(encoded.contains(#""fields":{"build":"x","url":"https://a.b/c"}"#))
    }

    @Test func decodeRejectsWhatIsNotALine() {
        #expect(LogLine.decode(Data()) == nil)
        #expect(LogLine.decode(Data("not json\n".utf8)) == nil)
        #expect(LogLine.decode(Data(#"{"cat":"app","level":"info","msg":"x","t":"2027-01-15T08:00:00.500Z""#.utf8)) == nil)
        // a level or a group a later build added, a time that is not one, a key missing
        #expect(LogLine.decode(Data(#"{"cat":"app","level":"debug","msg":"x","t":"2027-01-15T08:00:00.500Z"}"#.utf8)) == nil)
        #expect(LogLine.decode(Data(#"{"cat":"weather","level":"info","msg":"x","t":"2027-01-15T08:00:00.500Z"}"#.utf8)) == nil)
        #expect(LogLine.decode(Data(#"{"cat":"app","level":"info","msg":"x","t":"yesterday"}"#.utf8)) == nil)
        #expect(LogLine.decode(Data(#"{"cat":"app","level":"info","t":"2027-01-15T08:00:00.500Z"}"#.utf8)) == nil)
    }

    @Test func decodeReadsAWholeSecondTime() {
        let read = LogLine.decode(Data(#"{"cat":"app","level":"error","msg":"x","t":"2027-01-15T08:00:00Z"}"#.utf8))
        #expect(read == LogLine(t: Date(timeIntervalSince1970: 1_800_000_000), level: .error, cat: .app, msg: "x", fields: nil))
    }

    @Test func levelsOrderInfoWarningError() {
        #expect(LogLevel.info < .warning)
        #expect(LogLevel.warning < .error)
        #expect(LogLevel.info < .error)
        #expect(!(LogLevel.error < .error))
        #expect(!(LogLevel.error < .info))
        #expect(LogLevel.allCases.filter { $0 >= .warning } == [.warning, .error])
        #expect(LogLevel.allCases.map(\.rawValue) == ["info", "warning", "error"])
    }

    @Test func categoriesAreTheGroupsTheFilesUse() {
        #expect(LogCategory.allCases.map(\.rawValue) == [
            "app", "offline", "map", "alarm", "notify", "ride", "location", "sync", "records", "forecast",
            "talk", "settings", "check", "dev", "metrics",
        ])
    }

    // MARK: - Coordinates

    @Test func roundsCoordinatesToHundredths() {
        #expect(LogRedact.round(Coordinate(35.6895, 139.6917)) == Coordinate(35.69, 139.69))
        #expect(LogRedact.text(Coordinate(35.6895, 139.6917)) == "35.69,139.69")
        // half a hundredth goes away from zero
        #expect(LogRedact.round(Coordinate(-0.005, 0.004)) == Coordinate(-0.01, 0.0))
        #expect(LogRedact.round(Coordinate(0.005, -0.015)) == Coordinate(0.01, -0.02))
    }

    @Test func roundNeverGivesNegativeZero() {
        let r = LogRedact.round(Coordinate(-0.004, -0.0))
        #expect(r.lat.sign == .plus)
        #expect(r.lng.sign == .plus)
        #expect(LogRedact.text(Coordinate(-0.004, -0.0)) == "0.00,0.00")
    }

    @Test func textAlwaysHasTwoDecimals() {
        #expect(LogRedact.text(Coordinate(-0.005, 0.004)) == "-0.01,0.00")
        #expect(LogRedact.text(Coordinate(35.7, 139.0)) == "35.70,139.00")
        #expect(LogRedact.text(Coordinate(-33.8688, 151.2093)) == "-33.87,151.21")
        #expect(LogRedact.text(Coordinate(35.0049, 135.7681)) == "35.00,135.77")
    }

    // MARK: - Day files

    @Test func dayNameUsesTheGivenZone() {
        let morning = Date(timeIntervalSince1970: 1_800_000_000) // 08:00 UTC, 17:00 in Tokyo
        #expect(LogRetention.dayName(morning, in: Self.tokyo) == "2027-01-15.jsonl")
        let evening = morning.addingTimeInterval(12 * 3600) // 20:00 UTC, 05:00 the next day in Tokyo
        #expect(LogRetention.dayName(evening, in: Self.tokyo) == "2027-01-16.jsonl")
        #expect(LogRetention.dayName(evening, in: Self.utc) == "2027-01-15.jsonl")
    }

    @Test func dayNamePadsMonthAndDay() {
        let early = Date(timeIntervalSince1970: 1_804_174_200) // 2027-03-05 00:30 in Tokyo, 03-04 15:30 UTC
        #expect(LogRetention.dayName(early, in: Self.tokyo) == "2027-03-05.jsonl")
        #expect(LogRetention.dayName(early, in: Self.utc) == "2027-03-04.jsonl")
    }

    // MARK: - Retention

    @Test func retentionDropsOlderThan14Days() {
        let kept = files([("2026-10-26.jsonl", 1000), ("2026-10-27.jsonl", 1000), ("2026-11-09.jsonl", 1000)])
        #expect(LogRetention.toDelete(kept, today: "2026-11-09.jsonl") == ["2026-10-26.jsonl"])
    }

    @Test func retentionCountsAcrossMonthsYearsAndLeapDays() {
        let newYear = files([("2026-12-22.jsonl", 1), ("2026-12-23.jsonl", 1), ("2027-01-05.jsonl", 1)])
        #expect(LogRetention.toDelete(newYear, today: "2027-01-05.jsonl") == ["2026-12-22.jsonl"])
        // 2028 has a 29 February, 2027 does not
        let leap = files([("2028-02-20.jsonl", 1), ("2028-02-21.jsonl", 1), ("2028-03-05.jsonl", 1)])
        #expect(LogRetention.toDelete(leap, today: "2028-03-05.jsonl") == ["2028-02-20.jsonl"])
        let common = files([("2027-02-19.jsonl", 1), ("2027-02-20.jsonl", 1), ("2027-03-05.jsonl", 1)])
        #expect(LogRetention.toDelete(common, today: "2027-03-05.jsonl") == ["2027-02-19.jsonl"])
    }

    @Test func retentionTrimsOldestUntilUnderCap() {
        let full = files([("2026-11-07.jsonl", 4_000_000), ("2026-11-08.jsonl", 4_000_000), ("2026-11-09.jsonl", 4_000_000)])
        #expect(LogRetention.toDelete(full, today: "2026-11-09.jsonl") == ["2026-11-07.jsonl"])
    }

    @Test func retentionKeepsExactlyTheCap() {
        let atCap = files([("2026-11-08.jsonl", 5_000_000), ("2026-11-09.jsonl", 5_000_000)])
        #expect(LogRetention.toDelete(atCap, today: "2026-11-09.jsonl") == [])
        let oneOver = files([("2026-11-07.jsonl", 1), ("2026-11-08.jsonl", 5_000_000), ("2026-11-09.jsonl", 5_000_000)])
        #expect(LogRetention.toDelete(oneOver, today: "2026-11-09.jsonl") == ["2026-11-07.jsonl"])
    }

    @Test func retentionDeletesSeveralOldestFirst() {
        // 15 MB in five days, listed in no order: the two oldest go, and the result is sorted
        let five = files([("2026-11-08.jsonl", 3_000_000), ("2026-11-05.jsonl", 3_000_000), ("2026-11-09.jsonl", 3_000_000),
                          ("2026-11-06.jsonl", 3_000_000), ("2026-11-07.jsonl", 3_000_000)])
        #expect(LogRetention.toDelete(five, today: "2026-11-09.jsonl") == ["2026-11-05.jsonl", "2026-11-06.jsonl"])
    }

    @Test func retentionDoesNotCountWhatAgeAlreadyDeletes() {
        let mixed = files([("2026-10-01.jsonl", 9_000_000), ("2026-11-08.jsonl", 4_000_000), ("2026-11-09.jsonl", 4_000_000)])
        #expect(LogRetention.toDelete(mixed, today: "2026-11-09.jsonl") == ["2026-10-01.jsonl"])
    }

    @Test func retentionNeverDeletesToday() {
        #expect(LogRetention.toDelete(files([("2026-11-09.jsonl", 12_000_000)]), today: "2026-11-09.jsonl") == [])
        let withYesterday = files([("2026-11-08.jsonl", 1_000_000), ("2026-11-09.jsonl", 12_000_000)])
        #expect(LogRetention.toDelete(withYesterday, today: "2026-11-09.jsonl") == ["2026-11-08.jsonl"])
    }

    @Test func retentionIgnoresOtherNames() {
        // neither deleted nor counted: a big file of another name never costs a day of log
        let others = files([("notes.txt", 50_000_000), ("diagnostics", 50_000_000), ("2026-11-08.jsonl", 1000), ("2026-11-09.jsonl", 1000)])
        #expect(LogRetention.toDelete(others, today: "2026-11-09.jsonl") == [])
        let old = files([("notes.txt", 50_000_000), ("diagnostics", 50_000_000), ("2026-10-01.jsonl", 1000), ("2026-11-09.jsonl", 12_000_000)])
        #expect(LogRetention.toDelete(old, today: "2026-11-09.jsonl") == ["2026-10-01.jsonl"])
    }

    @Test func retentionNeedsTheExactName() {
        let lookalikes = ["2026-10-01.json", "2026-10-1.jsonl", "2026-10-01.jsonl.tmp", "x2026-10-01.jsonl", "2026-13-01.jsonl",
                          "2026-02-30.jsonl", "2026-00-10.jsonl", "2026-10-00.jsonl", "２０２６-10-01.jsonl", "٢٠٢٦-10-01.jsonl",
                          "2026-10-01.JSONL", "../2026-10-01.jsonl"]
        let all = files(lookalikes.map { ($0, 5_000_000) } + [("2026-10-01.jsonl", 1), ("2026-11-09.jsonl", 1)])
        #expect(LogRetention.toDelete(all, today: "2026-11-09.jsonl") == ["2026-10-01.jsonl"])
    }

    @Test func retentionKeepsLaterNamesByAge() {
        // a day ahead of the phone's (the zone moved west): never too old, the newest by size
        let ahead = files([("2026-10-20.jsonl", 1000), ("2026-11-10.jsonl", 1000), ("2026-11-09.jsonl", 1000)])
        #expect(LogRetention.toDelete(ahead, today: "2026-11-09.jsonl") == ["2026-10-20.jsonl"])
        let heavy = files([("2026-11-08.jsonl", 6_000_000), ("2026-11-09.jsonl", 3_000_000), ("2026-11-10.jsonl", 3_000_000)])
        #expect(LogRetention.toDelete(heavy, today: "2026-11-09.jsonl") == ["2026-11-08.jsonl"])
    }

    @Test func retentionRejectsALongerExtensionWithTheSameLength() {
        // ".jsonx" is as long as ".jsonl" and starts the same: not a day file, so neither deleted nor counted
        let all = files([("2026-10-01.jsonx", 1), ("2026-10-01.jsonl", 1), ("2026-11-09.jsonl", 1)])
        #expect(LogRetention.toDelete(all, today: "2026-11-09.jsonl") == ["2026-10-01.jsonl"])
    }

    @Test func retentionKnowsACenturyYearIsNotLeap() {
        // 2100 is divisible by 100 and not by 400: it has no 29 February; 2000 does
        let all = files([("2100-02-29.jsonl", 1), ("2100-03-30.jsonl", 1)])
        #expect(LogRetention.toDelete(all, today: "2100-03-30.jsonl") == [])
        let leap = files([("2000-02-29.jsonl", 1), ("2000-03-30.jsonl", 1)])
        #expect(LogRetention.toDelete(leap, today: "2000-03-30.jsonl") == ["2000-02-29.jsonl"])
    }

    @Test func retentionTreatsANegativeSizeAsZero() {
        // a size read as negative takes nothing off the total: 10_001_000 bytes still over the cap
        let all = files([("2026-11-07.jsonl", 1000), ("2026-11-08.jsonl", -5_000_000), ("2026-11-09.jsonl", 10_000_000)])
        #expect(LogRetention.toDelete(all, today: "2026-11-09.jsonl") == ["2026-11-07.jsonl"])
    }

    @Test func retentionResultIsSortedWhateverTheListingOrder() {
        // deleted by age, listed in no order: the result is still by name
        let all = files([("2026-10-03.jsonl", 1), ("2026-10-01.jsonl", 1), ("2026-10-02.jsonl", 1), ("2026-11-09.jsonl", 1)])
        #expect(LogRetention.toDelete(all, today: "2026-11-09.jsonl") == ["2026-10-01.jsonl", "2026-10-02.jsonl", "2026-10-03.jsonl"])
    }

    @Test func retentionWithoutAValidTodayDeletesNothing() {
        let old = files([("2026-01-01.jsonl", 20_000_000), ("2026-11-09.jsonl", 1)])
        #expect(LogRetention.toDelete(old, today: "notes.txt") == [])
        #expect(LogRetention.toDelete(old, today: "2026-11-31.jsonl") == [])
    }

    @Test func aDayFileStopsAtTheCap() {
        let cap = LogRetention.maxBytes
        #expect(LogRetention.fitting([100, 100], after: 0) == 2)
        #expect(LogRetention.fitting([100, 100], after: cap - 200) == 2)
        #expect(LogRetention.fitting([100, 100], after: cap - 150) == 1)
        #expect(LogRetention.fitting([100, 100], after: cap) == 0)
        #expect(LogRetention.fitting([cap], after: 0) == 1)
        #expect(LogRetention.fitting([cap + 1], after: 0) == 0)
        // the file stops growing: a smaller line after one that did not fit is not taken either
        #expect(LogRetention.fitting([200, 10], after: cap - 150) == 0)
        #expect(LogRetention.fitting([], after: 0) == 0)
    }

    @Test func limitsAreTheSpecs() {
        #expect(LogRetention.maxAgeDays == 14)
        #expect(LogRetention.maxBytes == 10_000_000)
        #expect(LogRetention.keptDiagnostics == 20)
    }

    // MARK: - Crash reports and the export

    @Test func diagnosticNameIsISOWithoutColons() {
        let end = Date(timeIntervalSince1970: 1_800_000_000.75)
        #expect(LogRetention.diagnosticName(end, index: 0) == "20270115T080000Z.json")
        #expect(LogRetention.diagnosticName(end, index: 1) == "20270115T080000Z-1.json")
        #expect(LogRetention.diagnosticName(end, index: 12) == "20270115T080000Z-12.json")
        #expect(!LogRetention.diagnosticName(end, index: 3).contains(":"))
    }

    @Test func diagnosticsToDeleteKeepsTheNewest() {
        let stamps = (0..<23).map { LogRetention.diagnosticName(Date(timeIntervalSince1970: 1_800_000_000 + Double($0) * 86_400), index: 0) }
        let listed = stamps.reversed() + ["notes.txt", "20270115T080000Z.json.tmp", "2027-01-15T08:00:00Z.json", "20270115T080000Z-01.json", "20270115T080000Z-0.json"]
        #expect(LogRetention.diagnosticsToDelete(Array(listed)) == Array(stamps.prefix(3)))
        #expect(LogRetention.diagnosticsToDelete(Array(listed), keeping: 22) == [stamps[0]])
        #expect(LogRetention.diagnosticsToDelete(Array(listed), keeping: 0) == stamps)
        #expect(LogRetention.diagnosticsToDelete(Array(listed), keeping: 30) == [])
    }

    @Test func diagnosticsOfOneSecondKeepTheirOrder() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let names = [2, 0, 10, 1].map { LogRetention.diagnosticName(end, index: $0) }
        let later = LogRetention.diagnosticName(end.addingTimeInterval(1), index: 0)
        // newest kept: the later second, then index 10, 2 and 1; index 0 is the oldest
        #expect(LogRetention.diagnosticsToDelete(names + [later], keeping: 4) == ["20270115T080000Z.json"])
        #expect(LogRetention.diagnosticsToDelete(names + [later], keeping: 2) == ["20270115T080000Z.json", "20270115T080000Z-1.json", "20270115T080000Z-2.json"])
    }

    @Test func aReportOfASecondAlreadyOnDiskTakesTheNextIndex() {
        let end = Date(timeIntervalSince1970: 1_800_000_000.75)
        #expect(LogRetention.diagnosticName(end, after: []) == "20270115T080000Z.json")
        // index 0 is "…Z.json": a report of that second on disk from an earlier delivery makes the next "…Z-1.json"
        #expect(LogRetention.diagnosticName(end, after: ["20270115T080000Z.json"]) == "20270115T080000Z-1.json")
        #expect(LogRetention.diagnosticName(end, after: ["20270115T080000Z-1.json", "20270115T080000Z.json"]) == "20270115T080000Z-2.json")
        // after the highest, never into a gap below it
        #expect(LogRetention.diagnosticName(end, after: ["20270115T080000Z-3.json"]) == "20270115T080000Z-4.json")
    }

    @Test func otherSecondsAndOtherNamesLeaveTheIndexAlone() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let listed = ["20270115T080001Z.json", "20270115T075959Z-4.json", "notes.txt", "20270115T080000Z-01.json",
                      "20270115T080000Z-0.json", "20270115T080000Z.json.tmp"]
        #expect(LogRetention.diagnosticName(end, after: listed) == "20270115T080000Z.json")
    }

    @Test func exportNameUsesTheGivenZone() {
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(LogRetention.exportName(morning, in: Self.tokyo) == "JP27-log-20270115-1700")
        #expect(LogRetention.exportName(morning, in: Self.saigon) == "JP27-log-20270115-1500")
        // 2027-03-05 09:07 in Tokyo
        #expect(LogRetention.exportName(Date(timeIntervalSince1970: 1_804_205_220), in: Self.tokyo) == "JP27-log-20270305-0907")
        #expect(!LogRetention.exportName(morning, in: Self.tokyo).contains(":"))
    }

    // MARK: - The queue

    @Test func queueDropsOldestPastCap() {
        var queue = LogQueue(cap: 3)
        for i in 0..<5 { queue.append(line("\(i)")) }
        #expect(queue.count == 3)
        #expect(queue.dropped == 2)
        #expect(queue.drain().map(\.msg) == ["2", "3", "4"])
        #expect(queue.dropped == 2)
        #expect(queue.count == 0)
        #expect(queue.drain().isEmpty)
    }

    @Test func queueKeepsWorkingAfterADrain() {
        var queue = LogQueue(cap: 3)
        for i in 0..<4 { queue.append(line("\(i)")) }
        #expect(queue.drain().map(\.msg) == ["1", "2", "3"])
        queue.append(line("a"))
        queue.append(line("b"))
        #expect(queue.count == 2)
        #expect(queue.drain().map(\.msg) == ["a", "b"])
        // dropped counts every line lost since the queue was made
        for i in 0..<7 { queue.append(line("\(i)")) }
        #expect(queue.drain().map(\.msg) == ["4", "5", "6"])
        #expect(queue.dropped == 5)
    }

    @Test func queueOfOneAndTheDefaultCap() {
        var one = LogQueue(cap: 1)
        one.append(line("a"))
        one.append(line("b"))
        #expect(one.drain().map(\.msg) == ["b"])
        #expect(one.dropped == 1)
        // a cap below one is one: the newest line is always kept
        var none = LogQueue(cap: 0)
        none.append(line("a"))
        #expect(none.drain().map(\.msg) == ["a"])
        var standard = LogQueue()
        for i in 0...2000 { standard.append(line("\(i)")) }
        #expect(standard.count == 2000)
        #expect(standard.dropped == 1)
        #expect(standard.drain().first?.msg == "1")
    }
}

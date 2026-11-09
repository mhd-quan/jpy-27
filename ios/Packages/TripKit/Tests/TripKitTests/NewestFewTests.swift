import Testing
@testable import TripKit

/// The prefetch rule (`Prefetch` in the app): at most three day or place pages load ahead at once, the newest
/// ask winning; a page already loading is not loaded twice; a finished one frees its place, and a cancelled one
/// that finishes late frees nothing that is not its own.
@Suite struct NewestFewTests {
    typealias Few = NewestFew<String>

    /// starts `key`, expecting a start; its ticket and what it cancelled
    private func start(_ few: inout Few, _ key: String) -> (ticket: Few.Ticket, cancelled: Few.Ticket?)? {
        guard case .start(let t, let cancelled) = few.admit(key) else { return nil }
        return (t, cancelled)
    }

    @Test func threeStartWithoutCancellingAny() throws {
        var few = Few(limit: 3)
        for key in ["a", "b", "c"] {
            let s = try #require(start(&few, key))
            #expect(s.ticket.key == key)
            #expect(s.cancelled == nil)
        }
        #expect(few.running == ["a", "b", "c"])
    }

    @Test func aFourthCancelsTheOldest() throws {
        var few = Few(limit: 3)
        let a = try #require(start(&few, "a"))
        _ = start(&few, "b")
        _ = start(&few, "c")
        let d = try #require(start(&few, "d"))
        #expect(d.cancelled == a.ticket)
        #expect(few.running == ["b", "c", "d"])
    }

    @Test func aKeyRunningIsNotStartedTwice() throws {
        var few = Few(limit: 3)
        _ = start(&few, "a")
        let b = try #require(start(&few, "b"))
        _ = start(&few, "c")
        #expect(few.admit("b") == .running(b.ticket))
        #expect(few.running.count == 3)
        #expect(Set(few.running) == ["a", "b", "c"])
    }

    @Test func aKeyAskedAgainBecomesTheNewest() throws {
        var few = Few(limit: 3)
        let a = try #require(start(&few, "a"))
        let b = try #require(start(&few, "b"))
        _ = start(&few, "c")
        #expect(few.admit("a") == .running(a.ticket))
        #expect(few.running == ["b", "c", "a"])
        // the refreshed key outlives an older one: b goes first, then c, and a only after them
        let d = try #require(start(&few, "d"))
        #expect(d.cancelled == b.ticket)
        let e = try #require(start(&few, "e"))
        #expect(e.cancelled?.key == "c")
        let f = try #require(start(&few, "f"))
        #expect(f.cancelled == a.ticket)
    }

    @Test func aFinishedKeyFreesItsSlot() throws {
        var few = Few(limit: 3)
        let a = try #require(start(&few, "a"))
        _ = start(&few, "b")
        _ = start(&few, "c")
        few.finished(a.ticket)
        #expect(few.running == ["b", "c"])
        let d = try #require(start(&few, "d"))
        #expect(d.cancelled == nil)
        #expect(few.running == ["b", "c", "d"])
    }

    @Test func aFinishedKeyStartsAgainUnderANewTicket() throws {
        var few = Few(limit: 3)
        let a = try #require(start(&few, "a"))
        few.finished(a.ticket)
        let again = try #require(start(&few, "a"))
        #expect(again.ticket != a.ticket)
        #expect(again.cancelled == nil)
        #expect(few.running == ["a"])
    }

    @Test func aLateFinishOfACancelledRunFreesNothingOfTheNewOne() throws {
        var few = Few(limit: 3)
        let a = try #require(start(&few, "a"))
        let b = try #require(start(&few, "b"))
        _ = start(&few, "c")
        let d = try #require(start(&few, "d"))
        #expect(d.cancelled == a.ticket)
        // a is asked for again: it starts anew, making room by cancelling b
        let a2 = try #require(start(&few, "a"))
        #expect(a2.cancelled == b.ticket)
        // the first run of a, cancelled, finishes now
        few.finished(a.ticket)
        #expect(few.running == ["c", "d", "a"])
        #expect(few.admit("a") == .running(a2.ticket))
    }

    @Test func finishingWhatDoesNotRunChangesNothing() throws {
        var few = Few(limit: 3)
        var other = Few(limit: 3)
        let stranger = try #require(start(&other, "x"))
        let a = try #require(start(&few, "a"))
        _ = start(&few, "b")
        few.finished(stranger.ticket)
        #expect(few.running == ["a", "b"])
        few.finished(a.ticket)
        few.finished(a.ticket)
        #expect(few.running == ["b"])
    }

    @Test func removeAllHandsBackEveryTicketOldestFirst() throws {
        var few = Few(limit: 3)
        let a = try #require(start(&few, "a"))
        let b = try #require(start(&few, "b"))
        let c = try #require(start(&few, "c"))
        #expect(few.removeAll() == [a.ticket, b.ticket, c.ticket])
        #expect(few.running.isEmpty)
        #expect(few.removeAll().isEmpty)
        let d = try #require(start(&few, "d"))
        #expect(d.cancelled == nil)
    }

    @Test func withRoomForOneEachNewKeyCancelsTheLast() throws {
        var few = Few(limit: 1)
        let a = try #require(start(&few, "a"))
        let b = try #require(start(&few, "b"))
        #expect(b.cancelled == a.ticket)
        let c = try #require(start(&few, "c"))
        #expect(c.cancelled == b.ticket)
        #expect(few.running == ["c"])
    }
}

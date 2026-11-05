import Testing
@testable import TripKit

/// Who holds the audio session, the Speaker or Nghe, and the calls each change of hands takes
/// (`AudioSessionOwners`). The rows named are those of the sequence table in the Task 4.2 pre-mortem.
@Suite struct AudioSessionOwnersTests {
    /// the Speaker's setup: `.playback / .spokenAudio / [.duckOthers]`
    static let speaker = AudioSetup(category: "playback", mode: "spokenAudio", options: 2)
    /// Nghe's setup: `.playAndRecord / .measurement / [.duckOthers, .defaultToSpeaker]`
    static let listener = AudioSetup(category: "playAndRecord", mode: "measurement", options: 10)
    /// what a session has before the app sets anything (`.soloAmbient`)
    static let fresh = AudioSetup(category: "soloAmbient", mode: "default", options: 0)

    private func owners() -> AudioSessionOwners {
        AudioSessionOwners(speaker: Self.speaker, listener: Self.listener)
    }

    // MARK: The Speaker

    /// Row 1: the Speaker sets its own category, then activates.
    @Test func aLineTakesTheSessionInTheSpeakersSetup() {
        var o = owners()
        #expect(o.say(found: Self.fresh) == [.setCategory(Self.speaker), .activate])
        #expect(o.holder == .speaker)
        #expect(o.reading)
        #expect(o.release == nil)
    }

    /// The category is set only when the session does not have it already.
    @Test func aCategoryAlreadySetIsNotSetAgain() {
        var o = owners()
        #expect(o.say(found: Self.speaker) == [.activate])
    }

    /// Row 4 then row 5: once nothing is left to say, a release is due; it deactivates.
    @Test func theReleaseDeactivatesOnceNothingIsLeftToSay() throws {
        var o = owners()
        _ = o.say(found: Self.fresh)
        let ticketDue = o.ended()
        let ticket = try #require(ticketDue)
        #expect(!o.reading)
        #expect(o.release == ticket)
        #expect(o.holder == .speaker)
        #expect(o.releaseDue(ticket) == [.deactivate])
        #expect(o.holder == .nobody)
        #expect(o.release == nil)
        // fired twice: nothing more
        #expect(o.releaseDue(ticket) == [])
    }

    /// Row 2 then 5b: a line within the release's delay voids it, and the session stays active for it.
    @Test func aLineBeforeTheReleaseVoidsIt() throws {
        var o = owners()
        _ = o.say(found: Self.fresh)
        let ticketDue = o.ended()
        let ticket = try #require(ticketDue)
        #expect(o.say(found: Self.speaker) == [.activate])
        #expect(o.release == nil)
        #expect(o.releaseDue(ticket) == [])
        #expect(o.holder == .speaker)
        #expect(o.reading)
    }

    /// Only the latest release counts: one voided by a line stays void after the next line ends.
    @Test func anOlderReleaseStaysVoid() throws {
        var o = owners()
        _ = o.say(found: Self.fresh)
        let firstDue = o.ended()
        let first = try #require(firstDue)
        _ = o.say(found: Self.speaker)
        let secondDue = o.ended()
        let second = try #require(secondDue)
        #expect(first != second)
        #expect(o.releaseDue(first) == [])
        #expect(o.holder == .speaker)
        #expect(o.releaseDue(second) == [.deactivate])
    }

    /// Row 4c: a second `ended` (a cancel and a finish, a late callback) neither re-arms nor voids.
    @Test func aSecondEndKeepsTheReleaseDue() throws {
        var o = owners()
        _ = o.say(found: Self.fresh)
        let ticketDue = o.ended()
        let ticket = try #require(ticketDue)
        #expect(o.ended() == nil)
        #expect(o.release == ticket)
        #expect(o.releaseDue(ticket) == [.deactivate])
    }

    /// Nothing said: nothing to release.
    @Test func anEndWithNothingSaidReleasesNothing() {
        var o = owners()
        #expect(o.ended() == nil)
        #expect(o.holder == .nobody)
    }

    // MARK: Nghe and the Speaker

    /// Row 6: Nghe sets its own category, activates, and remembers the setup it found.
    @Test func listeningTakesTheSessionAndRemembersWhatItFound() {
        var o = owners()
        #expect(o.listen(1, found: Self.fresh) == [.setCategory(Self.listener), .activate])
        #expect(o.holder == .listener(1))
        #expect(o.prior == Self.fresh)
        var again = owners()
        #expect(again.listen(1, found: Self.listener) == [.activate])
    }

    /// Row 3: while Nghe listens, a line is spoken through its session; the category is left alone
    /// (changing it would stop the microphone).
    @Test func aLineWhileListeningLeavesTheSessionAlone() {
        var o = owners()
        _ = o.listen(1, found: Self.fresh)
        #expect(o.say(found: Self.listener) == [])
        #expect(o.holder == .listener(1))
        #expect(o.reading)
    }

    /// Row 4b: a line ending while Nghe listens releases nothing: the session is Nghe's to end.
    @Test func aLineEndingWhileListeningReleasesNothing() {
        var o = owners()
        _ = o.listen(1, found: Self.fresh)
        _ = o.say(found: Self.listener)
        #expect(o.ended() == nil)
        #expect(!o.reading)
        #expect(o.release == nil)
    }

    /// Row 6 over row 4: Nghe starting voids the Speaker's release, which would otherwise end Nghe's
    /// session (and its microphone) half a second later. What Nghe found is the Speaker's setup.
    @Test func listeningVoidsTheSpeakersRelease() throws {
        var o = owners()
        _ = o.say(found: Self.fresh)
        let ticketDue = o.ended()
        let ticket = try #require(ticketDue)
        #expect(o.listen(1, found: Self.speaker) == [.setCategory(Self.listener), .activate])
        #expect(o.release == nil)
        #expect(o.releaseDue(ticket) == [])
        #expect(o.holder == .listener(1))
        #expect(o.prior == Self.speaker)
    }

    /// Row 8: stopping with nothing being read deactivates first (what another app plays comes back
    /// up), then puts back what Nghe found, on the inactive session.
    @Test func stoppingIdleDeactivatesThenPutsTheSetupBack() {
        var o = owners()
        _ = o.listen(1, found: Self.fresh)
        #expect(o.listenEnded(1, found: Self.listener) == [.deactivate, .setCategory(Self.fresh)])
        #expect(o.holder == .nobody)
        #expect(o.prior == nil)
    }

    /// Row 8, with the setup found still in place: nothing to put back.
    @Test func stoppingIdleWithTheSetupInPlaceOnlyDeactivates() {
        var o = owners()
        _ = o.listen(1, found: Self.listener)
        #expect(o.listenEnded(1, found: Self.listener) == [.deactivate])
    }

    /// Row 7: stopping mid-line hands the active session to the Speaker, in its own setup; the setup
    /// from before is dropped, and the Speaker's release ends the session after the line.
    @Test func stoppingMidLineHandsTheSessionToTheSpeaker() throws {
        var o = owners()
        _ = o.listen(1, found: Self.fresh)
        _ = o.say(found: Self.listener)
        #expect(o.listenEnded(1, found: Self.listener) == [.setCategory(Self.speaker)])
        #expect(o.holder == .speaker)
        #expect(o.prior == nil)
        #expect(o.reading)
        let ticketDue = o.ended()
        let ticket = try #require(ticketDue)
        #expect(o.releaseDue(ticket) == [.deactivate])
        #expect(o.holder == .nobody)
    }

    /// Row 7, then a new listen: the setup it finds is the one remembered, not the dropped one.
    @Test func aDroppedSetupIsNotPutBackLater() {
        var o = owners()
        _ = o.listen(1, found: Self.fresh)
        _ = o.say(found: Self.listener)
        _ = o.listenEnded(1, found: Self.listener)
        _ = o.listen(2, found: Self.speaker)
        _ = o.ended()
        #expect(o.listenEnded(2, found: Self.listener) == [.deactivate, .setCategory(Self.speaker)])
    }

    /// Rows 9 and 10: a stop from a listen that does not hold the session (stopped already, or an
    /// older listener whose stop or deinit comes late) changes nothing.
    @Test func aStopFromAListenNotHoldingTheSessionIsIgnored() {
        var o = owners()
        _ = o.listen(1, found: Self.fresh)
        _ = o.listen(2, found: Self.listener)
        #expect(o.listenEnded(1, found: Self.listener) == [])
        #expect(o.holder == .listener(2))
        // the setup from before the first listen is the one put back
        #expect(o.listenEnded(2, found: Self.listener) == [.deactivate, .setCategory(Self.fresh)])
        #expect(o.listenEnded(2, found: Self.fresh) == [])
        #expect(o.listenEnded(3, found: Self.fresh) == [])
        #expect(o.holder == .nobody)
    }

    /// Nghe starting during a line, the line ending, then Nghe stopping: it puts back the Speaker's
    /// setup it found.
    @Test func listeningDuringALineThenStoppingIdlePutsTheSpeakersSetupBack() {
        var o = owners()
        _ = o.say(found: Self.fresh)
        _ = o.listen(1, found: Self.speaker)
        #expect(o.ended() == nil)
        #expect(o.listenEnded(1, found: Self.listener) == [.deactivate, .setCategory(Self.speaker)])
        #expect(o.holder == .nobody)
    }
}

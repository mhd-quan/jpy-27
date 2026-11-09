import Testing
@testable import TripKit

private typealias Plan = AudioSessionPlan

private let setSpeaker = Plan.Command.session(.setCategory(.speaker))
private let setListener = Plan.Command.session(.setCategory(.listener))
private let capture = Plan.Command.session(.capturePrior)
private let restore = Plan.Command.session(.restorePrior)
private let activate = Plan.Command.session(.activate)
private let deactivate = Plan.Command.session(.deactivate)

private func busy(_ step: Plan.Step) -> Plan.Failure { Plan.Failure(step: step, busy: true) }
private func broken(_ step: Plan.Step) -> Plan.Failure { Plan.Failure(step: step, busy: false) }

/// The app's one audio session between the Speaker and Nghe: who holds it, when the Speaker's release comes, what a
/// failure does. Each test reads the whole list of commands an event gives, in order.
@Suite struct AudioSessionPlanTests {
    // MARK: The Speaker

    @Test func aLineTakesTheSessionInTheSpeakersSetup() {
        var plan = Plan()
        #expect(plan.handle(.speakerWillSpeak) == [setSpeaker])
        #expect(plan.holder == .speaker)
    }

    @Test func theSpeakersSetupIsSetOnlyWhenItDiffers() {
        var plan = Plan()
        #expect(plan.handle(.speakerWillSpeak) == [setSpeaker])
        #expect(plan.handle(.speakerWillSpeak) == [])
        #expect(plan.holder == .speaker)
    }

    @Test func aLineWhileNgheListensSpeaksThroughTheRecording() {
        var plan = Plan()
        _ = plan.handle(.listenerStarting)
        let ticket = plan.generation
        // the recording session as it is: changing the category would stop the microphone
        #expect(plan.handle(.speakerWillSpeak) == [])
        #expect(plan.holder == .listener(active: true))
        #expect(plan.generation == ticket)
        // the line ends while Nghe still listens: the session is Nghe's to end
        #expect(plan.handle(.speakerDone) == [])
        #expect(plan.handle(.listenerStopped(ticket: ticket, lineBeingRead: false)) == [deactivate, restore])
    }

    @Test func anEndedLineReleasesHalfASecondLater() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        #expect(Plan.releaseAfter == 500)
        #expect(plan.handle(.speakerDone) == [.release(afterMilliseconds: 500, generation: plan.generation)])
        // still the Speaker's until the release comes due
        #expect(plan.holder == .speaker)
    }

    @Test func theReleaseDeactivatesWhenItComesDue() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let g = plan.generation
        #expect(plan.handle(.releaseDue(generation: g)) == [deactivate])
        #expect(plan.holder == .nobody)
        // once: a second wake of the same release finds nothing pending
        #expect(plan.handle(.releaseDue(generation: g)) == [])
    }

    @Test func aLineBeforeTheReleaseCancelsIt() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let first = plan.generation
        // the category is the Speaker's already: only the release goes
        #expect(plan.handle(.speakerWillSpeak) == [.cancelRelease])
        #expect(plan.handle(.releaseDue(generation: first)) == [])
        #expect(plan.holder == .speaker)
        // the second line's end has a release of its own
        let second = plan.generation
        #expect(second != first)
        #expect(plan.handle(.speakerDone) == [.release(afterMilliseconds: 500, generation: second)])
        #expect(plan.handle(.releaseDue(generation: second)) == [deactivate])
    }

    @Test func anOlderReleaseComingDueDoesNothing() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let first = plan.generation
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let second = plan.generation
        // the first line's wait, not cancelled in time, wakes while the second's release is pending: the token,
        // not the pending flag, tells them apart
        #expect(plan.handle(.releaseDue(generation: first)) == [])
        #expect(plan.holder == .speaker)
        #expect(plan.handle(.releaseDue(generation: second)) == [deactivate])
    }

    @Test func oneReleaseForTwoEnds() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        #expect(plan.handle(.speakerDone) == [.release(afterMilliseconds: 500, generation: plan.generation)])
        #expect(plan.handle(.speakerDone) == [])
    }

    // MARK: Nghe

    @Test func aListenCapturesThePriorSetsItsSetupAndActivates() {
        var plan = Plan()
        #expect(plan.handle(.listenerStarting) == [capture, setListener, activate])
        #expect(plan.holder == .listener(active: true))
    }

    @Test func aListenCancelsAPendingRelease() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let release = plan.generation
        #expect(plan.handle(.listenerStarting) == [.cancelRelease, capture, setListener, activate])
        // Nghe holds the session now and ends it
        #expect(plan.handle(.releaseDue(generation: release)) == [])
        #expect(plan.holder == .listener(active: true))
    }

    @Test func ngheStoppingWithNothingReadDeactivatesThenRestores() {
        var plan = Plan()
        _ = plan.handle(.listenerStarting)
        let ticket = plan.generation
        // deactivated first (what another app plays comes back up), then the category from before
        #expect(plan.handle(.listenerStopped(ticket: ticket, lineBeingRead: false)) == [deactivate, restore])
        #expect(plan.holder == .nobody)
        // the prior's setup is not known here: the next listen and the next line set theirs again
        #expect(plan.handle(.listenerStarting) == [capture, setListener, activate])
        _ = plan.handle(.listenerStopped(ticket: plan.generation, lineBeingRead: false))
        #expect(plan.handle(.speakerWillSpeak) == [setSpeaker])
    }

    @Test func ngheStoppingMidLineHandsTheSessionToTheSpeaker() {
        var plan = Plan()
        _ = plan.handle(.listenerStarting)
        let ticket = plan.generation
        #expect(plan.handle(.speakerWillSpeak) == [])
        // the session stays active, in the Speaker's setup; the prior is dropped
        #expect(plan.handle(.listenerStopped(ticket: ticket, lineBeingRead: true)) == [setSpeaker])
        #expect(plan.holder == .speaker)
        // the Speaker's release ends it after the line, with nothing to restore
        #expect(plan.handle(.speakerDone) == [.release(afterMilliseconds: 500, generation: plan.generation)])
        #expect(plan.handle(.releaseDue(generation: plan.generation)) == [deactivate])
        // the next listen captures afresh
        #expect(plan.handle(.listenerStarting) == [capture, setListener, activate])
    }

    @Test func thePriorIsCapturedOnce() {
        var plan = Plan()
        _ = plan.handle(.listenerStarting)
        let a = plan.generation
        // a second listen before the first gave the session back: the setup from before both is kept
        #expect(plan.handle(.listenerStarting) == [activate])
        let b = plan.generation
        #expect(b != a)
        #expect(plan.handle(.listenerStopped(ticket: a, lineBeingRead: false)) == [])
        #expect(plan.handle(.listenerStopped(ticket: b, lineBeingRead: false)) == [deactivate, restore])
        // given back: the next listen captures again
        #expect(plan.handle(.listenerStarting) == [capture, setListener, activate])
    }

    @Test func aStopFromAnEarlierListenDoesNothing() {
        var plan = Plan()
        _ = plan.handle(.listenerStarting)
        let old = plan.generation
        _ = plan.handle(.listenerStopped(ticket: old, lineBeingRead: false))
        _ = plan.handle(.listenerStarting)
        // the sheet closed and opened again: the old listener's deinit lands during the new listen
        #expect(plan.handle(.listenerStopped(ticket: old, lineBeingRead: false)) == [])
        #expect(plan.holder == .listener(active: true))
        #expect(plan.handle(.listenerStopped(ticket: plan.generation, lineBeingRead: false)) == [deactivate, restore])
    }

    @Test func aStopWithNobodyListeningDoesNothing() {
        var plan = Plan()
        #expect(plan.handle(.listenerStopped(ticket: plan.generation, lineBeingRead: false)) == [])
        _ = plan.handle(.speakerWillSpeak)
        #expect(plan.handle(.listenerStopped(ticket: plan.generation, lineBeingRead: true)) == [])
        #expect(plan.holder == .speaker)
    }

    @Test func aListenWhoseActivationFailedGivesBackOnlyTheCategory() {
        var plan = Plan()
        _ = plan.handle(.listenerStarting)
        let ticket = plan.generation
        #expect(plan.handle(.failed(broken(.activate), generation: ticket)) == [])
        #expect(plan.holder == .listener(active: false))
        // never activated: nothing to deactivate, and no hand-over to the Speaker either
        #expect(plan.handle(.listenerStopped(ticket: ticket, lineBeingRead: true)) == [restore])
        #expect(plan.holder == .nobody)

        // the category failing stops the batch before the activation: the same
        _ = plan.handle(.listenerStarting)
        let second = plan.generation
        #expect(plan.handle(.failed(broken(.setCategory(.listener)), generation: second)) == [])
        #expect(plan.handle(.listenerStopped(ticket: second, lineBeingRead: false)) == [restore])

        // an older listen's failure does not touch a newer listen
        _ = plan.handle(.listenerStarting)
        let third = plan.generation
        #expect(plan.handle(.failed(broken(.activate), generation: second)) == [])
        #expect(plan.holder == .listener(active: true))
        #expect(plan.handle(.listenerStopped(ticket: third, lineBeingRead: false)) == [deactivate, restore])
    }

    // MARK: Failures

    @Test func aBusyDeactivationIsRetriedOnceAfter150ms() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let g = plan.generation
        _ = plan.handle(.releaseDue(generation: g))
        #expect(Plan.busyRetryAfter == 150)
        #expect(plan.handle(.failed(busy(.deactivate), generation: g)) == [.retry(afterMilliseconds: 150, generation: g)])
        #expect(plan.handle(.retryDue(generation: g)) == [deactivate])
        // the one retry runs once, however often its wait wakes
        #expect(plan.handle(.retryDue(generation: g)) == [])
        // busy again: not retried a second time (the app logs it)
        #expect(plan.handle(.failed(busy(.deactivate), generation: g)) == [])
        #expect(plan.handle(.retryDue(generation: g)) == [])
        #expect(plan.holder == .nobody)
    }

    /// The app never sends this sequence: the queue stops a batch at its first failure, and a retry's batch is
    /// queued only by `retryDue`, so no second failure can come while the retry waits. The plan still gives at most
    /// one retry, and the second failure ends the deactivation.
    @Test func aSecondBusyFailureWhileTheRetryWaitsIsNeverASecondRetry() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let g = plan.generation
        #expect(plan.handle(.releaseDue(generation: g)) == [deactivate])
        #expect(plan.handle(.failed(busy(.deactivate), generation: g)) == [.retry(afterMilliseconds: 150, generation: g)])
        #expect(plan.handle(.failed(busy(.deactivate), generation: g)) == [])
        #expect(plan.handle(.retryDue(generation: g)) == [])
        #expect(plan.holder == .nobody)
    }

    @Test func ngheRetriesItsRestoreWithTheDeactivation() {
        var plan = Plan()
        _ = plan.handle(.listenerStarting)
        let g = plan.generation
        _ = plan.handle(.listenerStopped(ticket: g, lineBeingRead: false))
        // the batch stopped at the deactivation: the category from before was not set on a session still active
        #expect(plan.handle(.failed(busy(.deactivate), generation: g)) == [.retry(afterMilliseconds: 150, generation: g)])
        #expect(plan.handle(.retryDue(generation: g)) == [deactivate, restore])
    }

    @Test func anotherDeactivationFailureIsNotRetried() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let g = plan.generation
        #expect(plan.handle(.releaseDue(generation: g)) == [deactivate])
        #expect(plan.handle(.failed(broken(.deactivate), generation: g)) == [])
        #expect(plan.handle(.retryDue(generation: g)) == [])
        #expect(plan.holder == .nobody)
    }

    @Test func aRetryAfterANewLineOrListenDoesNothing() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let g = plan.generation
        _ = plan.handle(.releaseDue(generation: g))
        #expect(plan.handle(.failed(busy(.deactivate), generation: g)) == [.retry(afterMilliseconds: 150, generation: g)])
        // a line starts during the 150 ms: the retry would cut it
        #expect(plan.handle(.speakerWillSpeak) == [])
        #expect(plan.handle(.retryDue(generation: g)) == [])
        #expect(plan.holder == .speaker)

        // a busy failure that comes back after a listen started is not retried either
        _ = plan.handle(.speakerDone)
        let h = plan.generation
        _ = plan.handle(.releaseDue(generation: h))
        _ = plan.handle(.listenerStarting)
        #expect(plan.handle(.failed(busy(.deactivate), generation: h)) == [])
        #expect(plan.handle(.retryDue(generation: h)) == [])
        #expect(plan.holder == .listener(active: true))
    }

    @Test func aFailedCategoryIsSetAgainNextTime() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        #expect(plan.handle(.failed(broken(.setCategory(.speaker)), generation: plan.generation)) == [])
        // the line is still read, and still the Speaker's to release
        #expect(plan.holder == .speaker)
        #expect(plan.handle(.speakerDone) == [.release(afterMilliseconds: 500, generation: plan.generation)])
        #expect(plan.handle(.speakerWillSpeak) == [.cancelRelease, setSpeaker])
    }

    @Test func anOlderLinesFailedCategoryIsSetAgainToo() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        let first = plan.generation
        // a second line takes the session before the first one's set has run: the category is the one set last
        #expect(plan.handle(.speakerWillSpeak) == [])
        #expect(plan.generation != first)
        // the first line's set then fails: the category is unknown, though that line's generation is gone
        #expect(plan.handle(.failed(broken(.setCategory(.speaker)), generation: first)) == [])
        #expect(plan.lastSet == nil)
        #expect(plan.holder == .speaker)
        // the next line sets it again instead of taking it as already set
        #expect(plan.handle(.speakerWillSpeak) == [setSpeaker])
    }

    @Test func aMediaServicesResetMakesTheCategoryUnknown() {
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        let before = plan
        #expect(plan.handle(.mediaServicesReset) == [])
        // nothing else changes
        #expect(plan.holder == before.holder)
        #expect(plan.generation == before.generation)
        #expect(plan.releasing == before.releasing)
        #expect(plan.priorCaptured == before.priorCaptured)
        #expect(plan.lastSet == nil)
        #expect(plan.handle(.speakerWillSpeak) == [setSpeaker])
    }

    @Test func aMediaServicesResetLeavesAPendingReleaseAndACapturedPrior() {
        // a release pending across the reset still comes due
        var plan = Plan()
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.speakerDone)
        let g = plan.generation
        #expect(plan.handle(.mediaServicesReset) == [])
        #expect(plan.handle(.releaseDue(generation: g)) == [deactivate])

        // a prior captured before the reset is still given back
        var listening = Plan()
        _ = listening.handle(.listenerStarting)
        let ticket = listening.generation
        #expect(listening.handle(.mediaServicesReset) == [])
        #expect(listening.handle(.listenerStopped(ticket: ticket, lineBeingRead: false)) == [deactivate, restore])
    }

    @Test func everyTakeIsANewGeneration() {
        var plan = Plan()
        #expect(plan.generation == 0)
        _ = plan.handle(.speakerWillSpeak)
        #expect(plan.generation == 1)
        _ = plan.handle(.speakerWillSpeak)
        #expect(plan.generation == 2)
        _ = plan.handle(.listenerStarting)
        #expect(plan.generation == 3)
        // speaking through Nghe's session and the hand-over take nothing new
        _ = plan.handle(.speakerWillSpeak)
        _ = plan.handle(.listenerStopped(ticket: 3, lineBeingRead: true))
        #expect(plan.generation == 3)
        #expect(plan.holder == .speaker)
    }

    /// Checklist step 7 (Q5) from end to end: music plays, Nghe listens, a slow line is read, Nghe is stopped halfway,
    /// the line ends, the release comes due.
    @Test func stoppingNgheMidLineFromStartToEnd() {
        var plan = Plan()
        var trail: [Plan.Command] = []
        trail += plan.handle(.listenerStarting)
        let ticket = plan.generation
        trail += plan.handle(.speakerWillSpeak)
        trail += plan.handle(.listenerStopped(ticket: ticket, lineBeingRead: true))
        trail += plan.handle(.speakerDone)
        trail += plan.handle(.releaseDue(generation: plan.generation))
        #expect(trail == [capture, setListener, activate,
                          setSpeaker,
                          .release(afterMilliseconds: 500, generation: ticket),
                          deactivate])
        #expect(plan.holder == .nobody)
        #expect(!plan.priorCaptured)
    }
}

import Foundation
import Testing
@testable import TripKit

/// The extras of a download (day maps, Fuji, forecasts) as the app runs them: one part at a time in the list's order,
/// busy from the moment they are asked for, a pause that holds, and each part's count as it ended.
@Suite struct ExtrasRunTests {
    typealias Count = ExtrasRun.Count

    /// `begin`, its answer out of the expectation (a mutation cannot be expected)
    func began(_ run: inout ExtrasRun, _ extra: OfflineExtra) -> Bool { run.begin(extra) }

    @Test func anExtraAskedForIsBusyBeforeItStarts() {
        var run = ExtrasRun()
        #expect(!run.busy([.dayMaps])); #expect(run.next == nil)
        run.request([.dayMaps, .fuji])
        // busy at once: a job whose maps and photos are already there does not end before its first picture
        #expect(run.busy([.dayMaps])); #expect(run.busy([.fuji])); #expect(run.busy([.dayMaps, .forecasts]))
        #expect(!run.busy([.forecasts])); #expect(!run.busy([]))
        #expect(run.phases == [.dayMaps: .pending, .fuji: .pending])
        #expect(run.state(.dayMaps) == nil); #expect(run.progress(.dayMaps) == nil)
        #expect(run.paused.isEmpty)
    }

    @Test func partsRunOneAtATimeInTheListsOrder() {
        var run = ExtrasRun()
        run.request([.forecasts, .fuji, .dayMaps])
        var order: [OfflineExtra] = []
        while let next = run.next {
            #expect(began(&run, next))
            // one loop: a second start of the same part is refused
            #expect(!began(&run, next))
            #expect(run.phases[next] == .running(nil)); #expect(run.busy([next]))
            order.append(next)
            run.end(next, Count(done: 5, total: 5))
            #expect(run.phases[next] == .finished(Count(done: 5, total: 5))); #expect(!run.busy([next]))
        }
        #expect(order == [.dayMaps, .fuji, .forecasts])
        #expect(!run.busy(Set(OfflineExtra.allCases)))
        #expect(run.states(Set(OfflineExtra.allCases)) == [
            .dayMaps: ExtraState(done: 5, total: 5, paused: false),
            .fuji: ExtraState(done: 5, total: 5, paused: false),
            .forecasts: ExtraState(done: 5, total: 5, paused: false),
        ])
        // a part never asked for never starts
        var other = ExtrasRun()
        other.request([.fuji])
        #expect(!began(&other, .dayMaps)); #expect(other.phases[.dayMaps] == nil)
        // the next is taken from the start of the list each time: day maps asked for during Fuji go before the forecasts
        var mid = ExtrasRun()
        mid.request([.fuji, .forecasts])
        #expect(mid.next == .fuji); #expect(began(&mid, .fuji))
        #expect(mid.next == .forecasts)
        mid.request([.dayMaps])
        mid.end(.fuji, Count(done: 69, total: 69))
        #expect(mid.next == .dayMaps)
    }

    @Test func aRequestForThePartRunningIsOnceMoreAfterThisPass() {
        var run = ExtrasRun()
        run.request([.fuji])
        #expect(began(&run, .fuji))
        run.counted(.fuji, done: 10, total: 69)
        run.request([.fuji])
        // the pass under way goes on, its count kept
        #expect(run.phases[.fuji] == .running(Count(done: 10, total: 69))); #expect(run.again == [.fuji])
        run.end(.fuji, Count(done: 60, total: 69))
        #expect(run.phases[.fuji] == .pending); #expect(run.again.isEmpty); #expect(run.busy([.fuji]))
        #expect(run.state(.fuji) == nil); #expect(run.next == .fuji)
        #expect(began(&run, .fuji))
        run.end(.fuji, Count(done: 69, total: 69))
        #expect(run.phases[.fuji] == .finished(Count(done: 69, total: 69))); #expect(run.next == nil)
        // once more only once: two taps during a pass are one more pass
        run.request([.fuji]); _ = run.begin(.fuji); run.request([.fuji]); run.request([.fuji])
        run.end(.fuji, nil)
        _ = run.begin(.fuji)
        run.end(.fuji, Count(done: 69, total: 69))
        #expect(run.next == nil); #expect(!run.busy([.fuji]))
    }

    @Test func aPartAskedForAgainAfterItEndedRunsAgain() {
        var run = ExtrasRun()
        run.request([.forecasts])
        _ = run.begin(.forecasts)
        run.end(.forecasts, Count(done: 30, total: 32))
        #expect(run.state(.forecasts) == ExtraState(done: 30, total: 32, paused: false))
        run.request([.forecasts])
        #expect(run.phases[.forecasts] == .pending); #expect(run.state(.forecasts) == nil); #expect(run.busy([.forecasts]))
        #expect(run.again.isEmpty)
    }

    @Test func aPartThatCannotBeCountedEndsWithNoState() {
        // Fuji waiting for a page to be opened, no page measured for the day maps: over, and not done
        var run = ExtrasRun()
        run.request([.fuji])
        _ = run.begin(.fuji)
        run.end(.fuji, nil)
        #expect(run.phases[.fuji] == .finished(nil))
        #expect(!run.busy([.fuji])); #expect(run.state(.fuji) == nil); #expect(run.states([.fuji]).isEmpty)
        #expect(run.next == nil)
    }

    @Test func aPauseStopsWhatWaitsAndWhatRuns() {
        var run = ExtrasRun()
        run.request(Set(OfflineExtra.allCases))
        _ = run.begin(.dayMaps)
        run.counted(.dayMaps, done: 3, total: 13)
        run.request([.dayMaps])
        run.pause()
        #expect(!run.busy(Set(OfflineExtra.allCases))); #expect(run.next == nil); #expect(run.again.isEmpty)
        #expect(run.paused == Set(OfflineExtra.allCases))
        #expect(run.state(.dayMaps) == ExtraState(done: 3, total: 13, paused: true))
        // never counted: a pause all the same
        #expect(run.state(.fuji) == ExtraState(done: 0, total: 0, paused: true))
        #expect(!began(&run, .fuji))
        // the picture in flight lands on a part that stays paused, with its count
        run.end(.dayMaps, Count(done: 4, total: 13))
        #expect(run.phases[.dayMaps] == .paused(Count(done: 4, total: 13))); #expect(run.next == nil)
        run.counted(.dayMaps, done: 5, total: 13)
        #expect(run.state(.dayMaps) == ExtraState(done: 5, total: 13, paused: true))
        // a part that had ended is not paused by it
        var ended = ExtrasRun()
        ended.request([.forecasts, .fuji])
        _ = ended.begin(.fuji)
        ended.end(.fuji, Count(done: 69, total: 69))
        ended.pause()
        #expect(ended.phases[.fuji] == .finished(Count(done: 69, total: 69))); #expect(ended.paused == [.forecasts])
        #expect(ended.states([.fuji, .forecasts]) == [.fuji: ExtraState(done: 69, total: 69, paused: false),
                                                      .forecasts: ExtraState(done: 0, total: 0, paused: true)])
    }

    @Test func aRequestAfterAPauseGoesOnFromWhatIsMissing() {
        var run = ExtrasRun()
        run.request([.dayMaps, .fuji])
        _ = run.begin(.dayMaps)
        run.pause()
        run.request([.dayMaps, .fuji])
        #expect(run.paused.isEmpty); #expect(run.phases == [.dayMaps: .pending, .fuji: .pending])
        // the pass stopped by the pause ends after the new tap: the part waits for its new pass
        run.end(.dayMaps, Count(done: 4, total: 13))
        #expect(run.phases[.dayMaps] == .pending); #expect(run.next == .dayMaps)
    }

    @Test func aStopKeptAcrossALaunchComesBackPaused() {
        var run = ExtrasRun()
        run.restore([.dayMaps, .fuji, .forecasts], held: [.fuji, .forecasts])
        #expect(run.state(.fuji) == ExtraState(done: 0, total: 0, paused: true))
        #expect(!run.busy([.fuji, .forecasts])); #expect(run.busy([.dayMaps, .fuji]))
        #expect(run.paused == [.fuji, .forecasts]); #expect(run.next == .dayMaps)
        #expect(run.held == [.fuji, .forecasts])
        // what was kept for a part no longer in the job is let go
        var other = ExtrasRun()
        other.restore([.dayMaps], held: [.fuji])
        #expect(other.phases == [.dayMaps: .pending]); #expect(other.held.isEmpty)
        // nothing kept: every part waits its turn
        var fresh = ExtrasRun()
        fresh.restore([.fuji, .forecasts], held: [])
        #expect(fresh.phases == [.fuji: .pending, .forecasts: .pending]); #expect(fresh.held.isEmpty)
    }

    @Test func aStopHoldsEveryPartAcrossAKillTheOnesOverWithThem() {
        // day maps drawn in front, then Fuji waiting for the app when the Live Activity's stop comes
        var run = ExtrasRun()
        let members: Set<OfflineExtra> = [.dayMaps, .fuji, .forecasts]
        run.request(members)
        _ = run.begin(.dayMaps)
        run.end(.dayMaps, Count(done: 13, total: 13))
        _ = run.begin(.fuji)
        run.pause()
        #expect(run.held == members)
        // the app is ended before the job is judged; at the next launch the job comes back with what was kept
        var back = ExtrasRun()
        back.restore(members, held: run.held)
        #expect(back.next == nil); #expect(!back.busy(members))
        #expect(back.phases == [.dayMaps: .paused(nil), .fuji: .paused(nil), .forecasts: .paused(nil)])
        #expect(back.states(members).values.allSatisfy { $0.paused })
        // a stop with nothing under way holds what was there all the same
        var over = ExtrasRun()
        over.request([.forecasts])
        _ = over.begin(.forecasts)
        over.end(.forecasts, Count(done: 32, total: 32))
        over.pause()
        #expect(over.held == [.forecasts]); #expect(over.phases[.forecasts] == .finished(Count(done: 32, total: 32)))
    }

    @Test func aRequestLetsGoOfTheStopOnlyForWhatItAsks() {
        // a row's own Tải after a stop: that part goes on, the others stay stopped, across a launch too
        var run = ExtrasRun()
        run.request(Set(OfflineExtra.allCases))
        _ = run.begin(.dayMaps)
        run.counted(.dayMaps, done: 4, total: 13)
        run.pause()
        run.request([.fuji])
        #expect(run.held == [.dayMaps, .forecasts])
        #expect(run.phases == [.dayMaps: .paused(Count(done: 4, total: 13)), .fuji: .pending, .forecasts: .paused(nil)])
        #expect(run.next == .fuji); #expect(run.busy([.fuji])); #expect(!run.busy([.dayMaps, .forecasts]))
        #expect(run.paused == [.dayMaps, .forecasts])
        var back = ExtrasRun()
        back.restore(Set(OfflineExtra.allCases), held: run.held)
        #expect(back.next == .fuji); #expect(back.paused == [.dayMaps, .forecasts])
        // and the rest asked for: nothing is held
        run.request([.dayMaps, .forecasts])
        #expect(run.held.isEmpty); #expect(run.paused.isEmpty)
    }

    @Test func anEndOnAPartOverChangesNothing() {
        var run = ExtrasRun()
        run.request([.fuji])
        _ = run.begin(.fuji)
        run.end(.fuji, Count(done: 60, total: 69))
        run.end(.fuji, Count(done: 69, total: 69))
        run.end(.fuji, nil)
        #expect(run.phases[.fuji] == .finished(Count(done: 60, total: 69)))
        #expect(run.state(.fuji) == ExtraState(done: 60, total: 69, paused: false))
        #expect(run.next == nil)
    }

    @Test func aPartWaitingItsTurnAgainKeepsItsCount() {
        // stepping aside for the forecasts, or asked for again: its count stays on the line while it waits
        var run = ExtrasRun()
        run.request([.fuji, .forecasts])
        _ = run.begin(.fuji)
        run.counted(.fuji, done: 12, total: 69)
        run.request([.fuji])
        run.end(.fuji, Count(done: 12, total: 69))
        #expect(run.phases[.fuji] == .pending)
        #expect(run.progress(.fuji) == Count(done: 12, total: 69)); #expect(run.fraction(.fuji) == 12.0 / 69)
        // its next pass shows it until it counts again
        _ = run.begin(.fuji)
        #expect(run.phases[.fuji] == .running(nil)); #expect(run.progress(.fuji) == Count(done: 12, total: 69))
        run.counted(.fuji, done: 13, total: 69)
        #expect(run.progress(.fuji) == Count(done: 13, total: 69))
        run.pause()
        #expect(run.progress(.fuji) == Count(done: 13, total: 69)); #expect(run.state(.fuji) == ExtraState(done: 13, total: 69, paused: true))
        // never counted: no count
        #expect(run.progress(.forecasts) == nil); #expect(run.fraction(.forecasts) == 0)
        // a part asked for again once over keeps its last count while it waits
        var again = ExtrasRun()
        again.request([.dayMaps])
        _ = again.begin(.dayMaps)
        again.end(.dayMaps, Count(done: 13, total: 13))
        again.request([.dayMaps])
        #expect(again.progress(.dayMaps) == Count(done: 13, total: 13)); #expect(again.state(.dayMaps) == nil)
        // an end with no count keeps the last one known
        _ = again.begin(.dayMaps)
        again.end(.dayMaps, nil)
        #expect(again.phases[.dayMaps] == .finished(nil)); #expect(again.progress(.dayMaps) == Count(done: 13, total: 13))
        #expect(again.state(.dayMaps) == nil)
    }

    @Test func aCountIsKeptOnlyWhereThePartIsUnderWayOrPaused() {
        var run = ExtrasRun()
        run.counted(.fuji, done: 1, total: 2)
        #expect(run.phases[.fuji] == nil)
        run.request([.fuji])
        run.counted(.fuji, done: 1, total: 2)
        #expect(run.phases[.fuji] == .pending); #expect(run.progress(.fuji) == nil)
        _ = run.begin(.fuji)
        run.counted(.fuji, done: 1, total: 2)
        #expect(run.progress(.fuji) == Count(done: 1, total: 2))
        run.end(.fuji, Count(done: 2, total: 2))
        run.counted(.fuji, done: 0, total: 2)
        #expect(run.progress(.fuji) == Count(done: 2, total: 2)); #expect(run.state(.fuji) == ExtraState(done: 2, total: 2, paused: false))
        // an end with no part under way changes nothing
        var idle = ExtrasRun()
        idle.end(.dayMaps, Count(done: 1, total: 1))
        #expect(idle.phases.isEmpty)
        idle.request([.dayMaps])
        idle.end(.dayMaps, Count(done: 1, total: 1))
        #expect(idle.phases[.dayMaps] == .pending)
    }

    @Test func eachPartsShareOfTheBar() {
        var run = ExtrasRun()
        #expect(run.fraction(.fuji) == 0)
        run.request(Set(OfflineExtra.allCases))
        #expect(run.fraction(.fuji) == 0)
        _ = run.begin(.dayMaps)
        #expect(run.fraction(.dayMaps) == 0)
        run.counted(.dayMaps, done: 3, total: 12)
        #expect(run.fraction(.dayMaps) == 0.25)
        run.counted(.dayMaps, done: 0, total: 0)
        #expect(run.fraction(.dayMaps) == 0)
        run.counted(.dayMaps, done: 15, total: 12)
        #expect(run.fraction(.dayMaps) == 1)
        run.counted(.dayMaps, done: -1, total: 12)
        #expect(run.fraction(.dayMaps) == 0)
        run.end(.dayMaps, Count(done: 12, total: 13))
        #expect(run.fraction(.dayMaps) == 12.0 / 13)
        _ = run.begin(.fuji)
        run.end(.fuji, nil)
        // over with nothing to count, or nothing to draw: all of its share
        #expect(run.fraction(.fuji) == 1)
        _ = run.begin(.forecasts)
        run.end(.forecasts, Count(done: 0, total: 0))
        #expect(run.fraction(.forecasts) == 1)
        var paused = ExtrasRun()
        paused.request([.fuji, .dayMaps])
        _ = paused.begin(.dayMaps)
        paused.counted(.dayMaps, done: 6, total: 12)
        paused.pause()
        #expect(paused.fraction(.dayMaps) == 0.5); #expect(paused.fraction(.fuji) == 0)
    }
}

/// The Live Activity's bar only moves forward; when the job grows, what is done from then on fills what is left of it.
@Suite struct JobBarTests {
    @Test func aJobThatNeverGrewShowsItsFraction() {
        let bar = JobBar()
        #expect(JobBar.units == 1000)
        #expect(bar.units(for: 0) == 0); #expect(bar.units(for: 0.4256) == 425); #expect(bar.units(for: 1) == 1000)
        #expect(bar.units(for: -1) == 0); #expect(bar.units(for: 2) == 1000); #expect(bar.units(for: .nan) == 0)
    }

    @Test func aJobThatGrewFillsWhatIsLeft() {
        // the maps at 90 %, then Tải tất cả: the job, the extras with it, is now at 60 %
        var bar = JobBar()
        bar.grew(fraction: 0.6, bar: 900)
        #expect(bar.units(for: 0.6) == 900)
        #expect(bar.units(for: 0.8) == 950)
        #expect(bar.units(for: 1) == 1000)
        // less than when it grew (more photos counted): the bar stays where it was
        #expect(bar.units(for: 0.5) == 900)
        #expect(bar.units(for: .nan) == 900); #expect(bar.units(for: 3) == 1000)
        // and again
        bar.grew(fraction: 0.9, bar: 950)
        #expect(bar.units(for: 0.95) == 975)
        // grown again and again with nothing done between (taps in a row): the bar stays, then fills what is left
        var taps = JobBar()
        taps.grew(fraction: 0.6, bar: 900)
        taps.grew(fraction: 0.5, bar: taps.units(for: 0.5))
        taps.grew(fraction: 0.4, bar: taps.units(for: 0.4))
        #expect(taps.units(for: 0.4) == 900); #expect(taps.units(for: 0.7) == 950); #expect(taps.units(for: 1) == 1000)
        // grown with nothing left: full once done
        var full = JobBar()
        full.grew(fraction: 1, bar: 400)
        #expect(full.units(for: 1) == 1000); #expect(full.units(for: 0.5) == 400)
        // what the system shows is held to the bar
        var over = JobBar()
        over.grew(fraction: 0.2, bar: 1200)
        #expect(over.units(for: 0.2) == 1000)
        var under = JobBar()
        under.grew(fraction: .nan, bar: -5)
        #expect(under.units(for: 0.5) == 500)
    }
}

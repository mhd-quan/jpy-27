import Foundation
import Testing
@testable import TripKit

/// AlarmKit as the tests see it: what it was asked, in order, and the alarms it holds.
@MainActor final class FakeScheduler: AlarmScheduling {
    enum Call: Equatable {
        case schedule(UUID)
        case cancel(UUID)
    }

    struct Failure: Error {}

    var log: [Call] = []
    var scheduledRequests: [WakeRequest] = []
    var cancelled: Set<UUID> = []
    /// the alarms the system holds for the app, each as AlarmKit reports it
    var system: [UUID: SystemAlarmState] = [:]
    /// the next schedule throws
    var failNext = false
    /// every cancel throws
    var failCancel = false
    /// reading the system's alarms throws
    var failList = false
    var listReads = 0
    /// asking for permission throws
    var failAuthorization = false
    var authorized = true
    /// the answer to the permission prompt
    var grant = true
    var prompts = 0
    /// set, the permission prompt stays up until the test opens it
    var authorizationGate: OneAtATimeTests.Gate?
    /// set, scheduling an alarm waits until the test opens it
    var scheduleGate: OneAtATimeTests.Gate?

    var isAuthorized: Bool { authorized }

    var scheduledIDs: [UUID] {
        log.compactMap { if case .schedule(let id) = $0 { id } else { nil } }
    }

    func requestAuthorization() async throws -> Bool {
        if authorized { return true }
        prompts += 1
        if let authorizationGate { await authorizationGate.wait() }
        if failAuthorization { throw Failure() }
        authorized = grant
        return grant
    }

    func schedule(id: UUID, request: WakeRequest) async throws {
        log.append(.schedule(id))
        scheduledRequests.append(request)
        // the system may hold the alarm before the call returns
        system[id] = .scheduled
        if let scheduleGate { await scheduleGate.wait() }
        if failNext {
            failNext = false
            system[id] = nil
            throw Failure()
        }
    }

    func cancel(id: UUID) throws {
        log.append(.cancel(id))
        if failCancel { throw Failure() }
        cancelled.insert(id)
        system[id] = nil
    }

    func systemAlarms() throws -> [UUID: SystemAlarmState] {
        listReads += 1
        if failList { throw Failure() }
        return system
    }

    /// An alarm the system already holds: waiting to ring, unless told otherwise.
    func seed(_ state: SystemAlarmState = .scheduled) -> UUID {
        let id = UUID()
        system[id] = state
        return id
    }
}

/// The alighting alarm (`WakeAlarms`): a wanted alarm is kept however close it is, a new one is set
/// only with time enough, and the one set is replaced only once its replacement is.
@Suite @MainActor struct WakeAlarmsTests {
    /// What `onChange` was handed, each time, and what had been cancelled by then.
    @MainActor final class SavedLog {
        var slots: [[String: AlarmSlot]] = []
        var cancelledThen: [Set<UUID>] = []
    }

    /// A clock the test moves on.
    @MainActor final class FakeClock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func keepsWantedAlarmDueIn45Seconds() async {
        let s = FakeScheduler()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: s.seed(), at: now + 45, source: .timetable)], now: { now }) { _ in }
        await a.planWake([WakeRequest(rideID: "r1", station: "Odawara", at: now + 45, source: .timetable)], isOn: { _ in true })
        #expect(a.scheduled["r1"] != nil)
        #expect(s.cancelled.isEmpty)
    }

    @Test func doesNotPlaceNewAlarmInsideLead() async {
        let s = FakeScheduler()
        let a = WakeAlarms(scheduler: s, saved: [:], now: { now }) { _ in }
        await a.planWake([WakeRequest(rideID: "r1", station: "X", at: now + 45, source: .timetable)], isOn: { _ in true })
        #expect(s.scheduledRequests.isEmpty)
    }

    @Test func cancelsAlarmNoLongerWantedOrSwitchedOff() async {
        let s = FakeScheduler()
        let gone = s.seed(), off = s.seed(), kept = s.seed(), followed = s.seed()
        let a = WakeAlarms(scheduler: s, saved: [
            "r1": AlarmSlot(id: gone, at: now + 600, source: .timetable),
            "r2": AlarmSlot(id: off, at: now + 700, source: .timetable),
            "r3": AlarmSlot(id: kept, at: now + 800, source: .timetable),
            // a followed ride the timetable never wants (a boat, off by default): the GPS's alarm is not
            // the timetable's to take back, whatever the switch reads (turning it off cancels it directly)
            "r4": AlarmSlot(id: followed, at: now + 900, source: .ride),
        ], now: { now }) { _ in }
        await a.planWake([
            WakeRequest(rideID: "r2", station: "X", at: now + 700, source: .timetable),
            WakeRequest(rideID: "r3", station: "X", at: now + 800, source: .timetable),
        ], isOn: { $0 != "r2" && $0 != "r4" })
        // r1 left the plan, r2's switch is off: both cancelled, and r2 is not set again
        #expect(s.cancelled == [gone, off])
        #expect(Set(a.scheduled.keys) == ["r3", "r4"])
        #expect(s.scheduledRequests.isEmpty)
    }

    @Test func failedScheduleKeepsOldAlarm() async {
        let s = FakeScheduler(); s.failNext = true
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 900, source: .ride))
        #expect(a.scheduled["r1"]?.id == old)
        #expect(!s.cancelled.contains(old))
        #expect(a.lastError != nil)
    }

    @Test func deniedPermissionKeepsOldAlarm() async {
        let s = FakeScheduler(); s.authorized = false; s.grant = false
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 900, source: .ride))
        #expect(s.prompts == 1)
        #expect(a.scheduled["r1"]?.id == old)
        #expect(s.log.isEmpty)
    }

    @Test func replacementTooLateKeepsOldAlarm() async {
        let s = FakeScheduler()
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 300, source: .timetable)], now: { now }) { _ in }
        // the GPS says the train is early: 20 s is too late for a new alarm, and the old one still rings
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 20, source: .ride))
        #expect(a.scheduled["r1"] == AlarmSlot(id: old, at: now + 300, source: .timetable))
        #expect(s.log.isEmpty)
    }

    @Test func oldIsCancelledOnlyAfterNewIsConfirmed() async {
        let s = FakeScheduler()
        let old = s.seed()
        let saves = SavedLog()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { slots in
            saves.slots.append(slots)
            saves.cancelledThen.append(s.cancelled)
        }
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .ride))
        #expect(s.log == [.schedule(a.scheduled["r1"]!.id), .cancel(old)])
        // the new alarm is saved before the old one is cancelled: killed in between, the app still knows the new one
        let new = a.scheduled["r1"]!.id
        let first = saves.slots.firstIndex { $0["r1"]?.id == new }
        #expect(first.map { saves.cancelledThen[$0].contains(old) } == false)
    }

    @Test func timetableNeverReplacesRide() async {
        let s = FakeScheduler()
        let followed = AlarmSlot(id: s.seed(), at: now + 600, source: .ride)
        let a = WakeAlarms(scheduler: s, saved: ["r1": followed], now: { now }) { _ in }
        await a.planWake([WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .timetable)], isOn: { _ in true })
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .timetable))
        #expect(a.scheduled["r1"] == followed)
        #expect(s.log.isEmpty)
    }

    @Test func aCloseGPSTimeTakesOverTheTimetableAlarm() async {
        let s = FakeScheduler()
        let old = s.seed()
        let saves = SavedLog()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .timetable)], now: { now }) { saves.slots.append($0) }
        // a minute off is not worth a new alarm, but the ride is the GPS's now: the timetable leaves it alone
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 660, source: .ride))
        // the same alarm, at its own time (the one AlarmKit rings), saved as the GPS's
        #expect(a.scheduled["r1"] == AlarmSlot(id: old, at: now + 600, source: .ride))
        #expect(saves.slots.last == ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)])
        #expect(s.log.isEmpty)
    }

    @Test func cancelWhileAwaitingPermissionDropsTheNewAlarm() async {
        let s = FakeScheduler(); s.authorized = false; s.grant = true
        let gate = OneAtATimeTests.Gate()
        s.authorizationGate = gate
        let a = WakeAlarms(scheduler: s, saved: [:], now: { now }) { _ in }
        let asking = Task { await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 600, source: .ride)) }
        await gate.reached()
        // the ride ends, or its alarm is turned off, while the prompt is up
        a.cancel("r1")
        gate.open()
        await asking.value
        #expect(s.scheduledRequests.isEmpty)
        #expect(a.scheduled["r1"] == nil)
    }

    @Test func cancelWhileSchedulingTakesBackTheNewAlarm() async throws {
        let s = FakeScheduler()
        let gate = OneAtATimeTests.Gate()
        s.scheduleGate = gate
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        let setting = Task { await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .ride)) }
        await gate.reached()
        a.cancel("r1")
        gate.open()
        await setting.value
        let new = try #require(s.scheduledIDs.first)
        // the GPS's alarm is cancelled directly, and the one that landed afterwards is taken back
        #expect(s.log == [.schedule(new), .cancel(old), .cancel(new)])
        #expect(a.scheduled["r1"] == nil)
        #expect(s.system.isEmpty)
    }

    @Test func reconcileCancelsSystemAlarmsTheAppForgot() async {
        let s = FakeScheduler()
        let orphan = s.seed()
        // ringing, counting down, paused, or in a state AlarmKit adds later: the traveller's to stop
        let busy: [UUID] = [s.seed(.alerting), s.seed(.countdown), s.seed(.paused), s.seed(.unknown)]
        let a = WakeAlarms(scheduler: s, saved: [:], now: { now }) { _ in }
        a.reconcile()
        #expect(s.cancelled == [orphan])
        #expect(busy.allSatisfy { s.system[$0] != nil })
    }

    @Test func reconcileForgetsAlarmsTheSystemNoLongerHas() {
        let s = FakeScheduler()
        let saves = SavedLog()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: UUID(), at: now + 600, source: .timetable)], now: { now }) { saves.slots.append($0) }
        a.reconcile()
        #expect(a.scheduled.isEmpty)
        #expect(saves.slots == [[:]])
        #expect(s.log.isEmpty)
    }

    // MARK: - The traps around the rules

    @Test func anAlarmPastItsTimeIsForgottenNotCancelled() async throws {
        // ringing: the planner no longer wants a wake whose time has passed
        let s = FakeScheduler()
        let ringing = s.seed(.alerting), followed = s.seed()
        let saves = SavedLog()
        let a = WakeAlarms(scheduler: s, saved: [
            "r1": AlarmSlot(id: ringing, at: now - 10, source: .timetable),
            // a GPS alarm that has rung is forgotten too, though the timetable never takes one back
            "r2": AlarmSlot(id: followed, at: now - 5, source: .ride),
        ], now: { now }) { saves.slots.append($0) }
        await a.planWake([], isOn: { _ in true })
        #expect(a.scheduled.isEmpty)
        #expect(saves.slots.last == [:])
        #expect(s.log.isEmpty)
        // nor when the GPS moves it on: the new one is set, the one that rang is left alone
        let t = FakeScheduler()
        let rang = t.seed()
        let b = WakeAlarms(scheduler: t, saved: ["r1": AlarmSlot(id: rang, at: now - 10, source: .timetable)], now: { now }) { _ in }
        await b.alight(WakeRequest(rideID: "r1", station: "X", at: now + 300, source: .ride))
        let new = try #require(t.scheduledIDs.first)
        #expect(b.scheduled["r1"] == AlarmSlot(id: new, at: now + 300, source: .ride))
        #expect(t.log == [.schedule(new)])
    }

    @Test func leadRunsOutWhileThePromptIsUp() async {
        let s = FakeScheduler(); s.authorized = false; s.grant = true
        let gate = OneAtATimeTests.Gate()
        s.authorizationGate = gate
        let clock = FakeClock(now)
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .timetable)], now: { clock.now }) { _ in }
        let asking = Task { await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 40, source: .ride)) }
        await gate.reached()
        // answered 15 s later: 25 s is too late for a new alarm
        clock.now = now + 15
        gate.open()
        await asking.value
        #expect(s.scheduledRequests.isEmpty)
        #expect(a.scheduled["r1"]?.id == old)
    }

    @Test func reconcileLeavesAnAlarmBeingSetAlone() async throws {
        let s = FakeScheduler()
        let gate = OneAtATimeTests.Gate()
        s.scheduleGate = gate
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        let setting = Task { await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .ride)) }
        await gate.reached()
        // back to the app while the new alarm is being set: the system holds it, the app does not know it yet
        a.reconcile()
        #expect(s.cancelled.isEmpty)
        gate.open()
        await setting.value
        let new = try #require(s.scheduledIDs.first)
        #expect(a.scheduled["r1"]?.id == new)
        #expect(Set(s.system.keys) == [new])
    }

    @Test func aFailedCancelIsRetriedByReconcile() async throws {
        let s = FakeScheduler()
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        s.failCancel = true
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .ride))
        let new = try #require(s.scheduledIDs.first)
        #expect(a.scheduled["r1"]?.id == new)
        #expect(s.system[old] != nil)
        #expect(a.lastError != nil)
        // with no list to read, nothing is cancelled (the old one may be ringing by now) and nothing forgotten
        s.failCancel = false
        s.failList = true
        a.reconcile()
        #expect(s.cancelled.isEmpty)
        #expect(a.scheduled["r1"]?.id == new)
        // the list says it is still waiting: taken back
        s.failList = false
        a.reconcile()
        #expect(s.cancelled == [old])
        #expect(a.scheduled["r1"]?.id == new)
    }

    @Test func timetableNeverAsksForPermission() async {
        let s = FakeScheduler(); s.authorized = false
        let a = WakeAlarms(scheduler: s, saved: [:], now: { now }) { _ in }
        await a.planWake([WakeRequest(rideID: "r1", station: "X", at: now + 600, source: .timetable)], isOn: { _ in true })
        #expect(s.prompts == 0)
        #expect(s.scheduledRequests.isEmpty)
    }

    @Test func decodesSlotsSavedByEarlierBuilds() throws {
        // `alarms.scheduled` as earlier builds wrote it: the first ones had no source, those were the timetable's
        let json = """
        {"r1":{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","at":800000000},
         "r2":{"id":"0E984725-C51C-4BF4-9960-E1C80E27ABA0","at":800000600,"source":"ride"}}
        """
        let slots = try JSONDecoder().decode([String: AlarmSlot].self, from: Data(json.utf8))
        #expect(slots["r1"] == AlarmSlot(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!, at: Date(timeIntervalSinceReferenceDate: 800_000_000), source: .timetable))
        #expect(slots["r2"]?.source == .ride)
        #expect(try JSONDecoder().decode([String: AlarmSlot].self, from: JSONEncoder().encode(slots)) == slots)
    }

    @Test func reconcileAtLaunchKeepsARingingAlarm() {
        // saved before the app was closed, ringing now as it opens: the app still knows it
        let s = FakeScheduler()
        let ringing = s.seed(.alerting)
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: ringing, at: now - 20, source: .timetable)], now: { now }) { _ in }
        a.reconcile()
        #expect(s.log.isEmpty)
        #expect(a.scheduled["r1"]?.id == ringing)
    }

    // MARK: - Fix round 1: what reconcile may touch, the rehearsal, permission, the store

    @Test func aRingingAlarmThePlanForgotIsNotCancelledByReconcile() async {
        let s = FakeScheduler()
        let ringing = s.seed(.alerting)
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: ringing, at: now - 10, source: .timetable)], now: { now }) { _ in }
        await a.planWake([], isOn: { _ in true })
        // unknown to the app now, but ringing: the traveller stops it, not the app
        a.reconcile()
        #expect(a.scheduled.isEmpty)
        #expect(!s.cancelled.contains(ringing))
        #expect(s.log.isEmpty)
    }

    @Test func aRingingAlarmTheGPSReplacedIsNotCancelledByReconcile() async throws {
        let s = FakeScheduler()
        let ringing = s.seed(.alerting)
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: ringing, at: now - 10, source: .timetable)], now: { now }) { _ in }
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 300, source: .ride))
        a.reconcile()
        let new = try #require(s.scheduledIDs.first)
        #expect(a.scheduled["r1"]?.id == new)
        #expect(!s.cancelled.contains(ringing))
        #expect(s.log == [.schedule(new)])
    }

    @Test func aRehearsalSetsNoAlarm() async {
        let s = FakeScheduler(); s.authorized = false; s.grant = true
        let old = AlarmSlot(id: s.seed(), at: now + 600, source: .timetable)
        let saves = SavedLog()
        let a = WakeAlarms(scheduler: s, saved: ["r1": old], now: { now }, rehearsing: { true }) { saves.slots.append($0) }
        // a replacement (asking for permission first), a relabel, and a new timetable alarm: none happens
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .ride))
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 660, source: .ride))
        s.authorized = true
        await a.alight(WakeRequest(rideID: "r2", station: "X", at: now + 900, source: .timetable))
        #expect(s.prompts == 0)
        #expect(s.log.isEmpty)
        #expect(a.scheduled == ["r1": old])
        #expect(saves.slots.isEmpty)
    }

    @Test func anUnreadableStoreNeverCancelsWhatItDoesNotKnow() async throws {
        let s = FakeScheduler()
        // set by an earlier run, whose record of it could not be read
        let unknown = s.seed()
        let a = WakeAlarms(scheduler: s, saved: nil, now: { now }) { _ in }
        // one this run set, replaced, and could not cancel is still this run's to take back
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 600, source: .ride))
        let first = try #require(s.scheduledIDs.first)
        s.failCancel = true
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 1200, source: .ride))
        s.failCancel = false
        a.reconcile()
        #expect(s.cancelled == [first])
        #expect(s.system[unknown] != nil)
        #expect(a.scheduled["r1"]?.at == now + 1200)
    }

    @Test func reconcileDoesNothingWithoutPermission() {
        // without permission AlarmKit may list nothing, though the alarms are still set
        let s = FakeScheduler(); s.authorized = false
        let slot = AlarmSlot(id: UUID(), at: now + 600, source: .ride)
        let a = WakeAlarms(scheduler: s, saved: ["r1": slot], now: { now }) { _ in }
        a.reconcile()
        #expect(a.scheduled == ["r1": slot])
        #expect(s.log.isEmpty)
        #expect(s.listReads == 0)
    }

    @Test func aPermissionErrorKeepsTheOldAlarm() async {
        let s = FakeScheduler(); s.authorized = false; s.failAuthorization = true
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 600, source: .ride)], now: { now }) { _ in }
        await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 900, source: .ride))
        #expect(a.scheduled["r1"]?.id == old)
        #expect(s.log.isEmpty)
        #expect(a.lastError != nil)
    }

    @Test func anOldAlarmThatComesDueWhileTheNewIsSetIsForgotten() async throws {
        let s = FakeScheduler()
        let gate = OneAtATimeTests.Gate()
        s.scheduleGate = gate
        let clock = FakeClock(now)
        let old = s.seed()
        let a = WakeAlarms(scheduler: s, saved: ["r1": AlarmSlot(id: old, at: now + 100, source: .timetable)], now: { clock.now }) { _ in }
        let setting = Task { await a.alight(WakeRequest(rideID: "r1", station: "X", at: now + 400, source: .ride)) }
        await gate.reached()
        // the old alarm's time comes while AlarmKit sets the new one: it is ringing
        clock.now = now + 100
        gate.open()
        await setting.value
        let new = try #require(s.scheduledIDs.first)
        #expect(a.scheduled["r1"]?.id == new)
        #expect(s.log == [.schedule(new)])
    }

    @Test func aListThatCannotBeReadIsRecorded() {
        let s = FakeScheduler(); s.failList = true
        let a = WakeAlarms(scheduler: s, saved: [:], now: { now }) { _ in }
        a.reconcile()
        #expect(a.lastError != nil)
    }

    @Test func anAlarmDueExactlyNowIsForgottenNotCancelled() async {
        let s = FakeScheduler()
        let wanted = s.seed(), unwanted = s.seed()
        let a = WakeAlarms(scheduler: s, saved: [
            "r1": AlarmSlot(id: wanted, at: now, source: .timetable),
            "r2": AlarmSlot(id: unwanted, at: now, source: .timetable),
        ], now: { now }) { _ in }
        await a.planWake([WakeRequest(rideID: "r1", station: "X", at: now, source: .timetable)], isOn: { _ in true })
        #expect(a.scheduled.isEmpty)
        #expect(s.log.isEmpty)
    }

    @Test func aNewAlarmNeedsMoreThanItsLead() {
        func placement(in seconds: TimeInterval, _ source: AlarmSource) -> WakeReconciler.Placement {
            WakeReconciler.placement(current: nil, request: WakeRequest(rideID: "r1", station: "X", at: now + seconds, source: source), now: now)
        }
        #expect(placement(in: 60, .timetable) == .skip)
        #expect(placement(in: 60.001, .timetable) == .replace)
        #expect(placement(in: 30, .ride) == .skip)
        #expect(placement(in: 30.001, .ride) == .replace)
    }

    @Test func aMoveOfLessThanTheSlackIsNotWorthANewAlarm() {
        let current = AlarmSlot(id: UUID(), at: now + 600, source: .timetable)
        func placement(at seconds: TimeInterval) -> WakeReconciler.Placement {
            WakeReconciler.placement(current: current, request: WakeRequest(rideID: "r1", station: "X", at: now + seconds, source: .ride), now: now)
        }
        #expect(placement(at: 600 + 120) == .replace)
        #expect(placement(at: 600 + 119.999) == .relabel(.ride))
        #expect(placement(at: 600 - 120) == .replace)
        #expect(placement(at: 600 - 119.999) == .relabel(.ride))
    }

    /// A followed ride's alarm is the timetable's at the latest (`RideTracker.alarm`). On a train
    /// running twenty minutes late, the timetable's 9:18 has rung: every later fix asks for nothing.
    /// The capped time itself (`min(at, planned)`, past) handed to `WakeAlarms` would set, cancel and
    /// report nothing either; it only takes the rung alarm as the GPS's, once.
    @Test func aLateTrainRingsOnceAtTheTimetablesTime() async throws {
        let store = Bundle_.store
        let ride = try #require(store.trip.rides.first { $0.id == "r-4-romancecar-st-shinjuku-odakyu" })
        let planned = try #require(WakePlanner(store: store).alarm(for: ride))
        let s = FakeScheduler()
        let rung = AlarmSlot(id: s.seed(.alerting), at: planned, source: .timetable)
        let clock = FakeClock(planned)
        let saves = SavedLog()
        let a = WakeAlarms(scheduler: s, saved: [ride.id: rung], now: { clock.now }) { saves.slots.append($0) }
        var tracker = RideTracker(ride: ride, store: store)
        // from 9:18 to 9:38, a fix a minute, short of Iriuda (86.6 km) at 50 km/h
        for minute in 0 ... 20 {
            let fix = planned + Double(minute * 60)
            clock.now = fix
            #expect(tracker.alarm(km: 70 + Double(minute) * 0.8, speedKmh: 50, at: fix, notAfter: planned, scheduled: a.scheduled[ride.id]?.at, now: fix) == nil)
            await a.alight(WakeRequest(rideID: ride.id, station: ride.toName, at: planned, source: .ride))
        }
        #expect(s.log.isEmpty)
        #expect(s.prompts == 0)
        #expect(a.lastError == nil)
        #expect(saves.slots == [[ride.id: AlarmSlot(id: rung.id, at: planned, source: .ride)]])
        // a ride first followed after 9:18, with no alarm set: nothing, the same way
        let none = FakeScheduler()
        let b = WakeAlarms(scheduler: none, saved: [:], now: { clock.now }) { _ in }
        var late = RideTracker(ride: ride, store: store)
        #expect(late.alarm(km: 80, at: clock.now, notAfter: planned, scheduled: nil, now: clock.now) == nil)
        await b.alight(WakeRequest(rideID: ride.id, station: ride.toName, at: planned, source: .ride))
        #expect(none.log.isEmpty)
        #expect(b.scheduled.isEmpty)
        #expect(b.lastError == nil)
    }
}

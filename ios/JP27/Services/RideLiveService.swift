// Activity is not marked Sendable, yet update(_:) and end(_:dismissalPolicy:) run off the main
// actor, so Swift 6 rejects every call from it (Apple's own Live Activity code makes the same
// calls). ActivityKit serialises updates to an activity itself; accept its missing annotations.
@preconcurrency import ActivityKit
import Foundation
import Observation
import TripKit

/// Follows one ride: projects the position onto the track, keeps the Live Activity current,
/// and keeps the alighting alarm a few minutes before the stop before yours, never later than the
/// timetable's alarm for the ride (or says so in a notification when the stop is too close for one).
///
/// While it is followed a ride holds its Live Activity, the navigation-grade positions and their
/// background session (`LocationService.startLive`), its GPS alarm, the projection's ride
/// (`Itinerary.project(riding:)`) and the hold on background re-plans (`holdsReschedule`), and it keeps
/// `AppModel.autoStartRide` from starting another. It lets go of all of it once (`release`), however it
/// ends: the button, its arrival, its fixes far from the line, the clock long past it
/// (`RideTracker.ending`), the trip's clock moved (`clockMoved`).
@Observable final class RideLiveService {
    private(set) var ride: Ride?
    private(set) var status: RideTracker.Status?
    private(set) var arrival: Date?
    /// The ride's one tracker: it keeps the train's last minutes of fixes (`RideTracker.record`), so
    /// it is changed where it lives, never through a copy. Made new for each ride.
    @ObservationIgnored private var tracker: RideTracker?
    /// when the timetable's alarm for the ride rings, on the trip's clock (`WakePlanner.alarm(for:)`),
    /// for the rides that have one
    @ObservationIgnored private var timetableAlarm: Date?
    /// when the ride was followed, on the trip's clock (`RideTracker.deadline`)
    @ObservationIgnored private var followedAt: Date?
    /// when it reached its end, on the real clock: closed `RideTracker.closeAfterArrival` later
    @ObservationIgnored private var arrivedAt: Date?
    /// the arrival on the real clock, to the second, for the Live Activity, whose count-down runs on
    /// the phone's clock (`arrival` is the trip's, for the app)
    @ObservationIgnored private var liveArrival: Date?
    /// the ride whose end is under way: it is ended once, whichever path gets there first
    @ObservationIgnored private var closing: String?
    /// the rides ended since launch, by any path, one set per clock (`EndedRides`): none starts again
    /// on its own on the clock it ended on (`wasEnded`)
    @ObservationIgnored private var ends = EndedRides()
    /// the clock the ride was followed on: a rehearsal's ride is the real ride of the same train, and its
    /// end lets go of nothing of the real one's (`RideClock`)
    @ObservationIgnored private var clock = RideClock(rehearsal: false)
    private var activity: Activity<RideAttributes>?
    private var lastState: RideAttributes.ContentState?
    private var lastPush = Date.distantPast
    private var ending = false

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// How long an arrived ride's Live Activity stays on the lock screen once ended.
    private static let arrivedLinger: TimeInterval = 15 * 60

    /// The ride being followed has reached its end and is only waiting to be closed: the next ride
    /// may start at once (a change of trains), it replaces this one.
    var hasArrived: Bool { ending }

    func start(_ ride: Ride, model: AppModel) {
        if self.ride?.id == ride.id { return }
        // one ride at a time: close the previous one without waiting for it
        if let old = activity, let last = lastState {
            Task { await old.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: .immediate) }
        }
        // its alarm, when it is its own (`RideClock`): a rehearsal's ride set none
        if let old = self.ride, clock.endCancelsAlarm(rehearsingNow: model.rehearsing) { model.alarms.cancel(old.id) }
        clock = RideClock(rehearsal: model.rehearsing)
        ending = false
        status = nil
        arrival = nil
        liveArrival = nil
        arrivedAt = nil
        followedAt = Shared.now
        lastPush = .distantPast
        self.ride = ride
        tracker = RideTracker(ride: ride, store: model.store)
        timetableAlarm = WakePlanner(store: model.store).alarm(for: ride)
        model.location.startLive(background: true)
        let after = walkAfter(ride, store: model.store)
        let line = model.store.day(ride.day)?.items.compactMap(\.move).first { $0.leg.id == ride.legs.first }?.leg.line
        let attributes = RideAttributes(
            rideID: ride.id, line: ride.title, color: ride.color,
            mode: line.flatMap { model.store.line($0)?.mode.rawValue } ?? Mode.train.rawValue,
            from: ride.fromName, to: ride.toName, toJa: ride.stations.last?.ja ?? ride.toName,
            announce: ride.alight?.announce, walkTo: after?.name, walkToID: after?.id)
        let state = makeState(tracker!.status(km: 0), model: model)
        if isAvailable {
            activity = try? Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil, relevanceScore: 100), pushType: nil)
        }
        lastState = state
        update(model: model)
    }

    /// Called on every position change, with every projection of the day, and on a significant
    /// change in the background: each is a moment the app runs, and the ride's end is checked at each
    /// (no timer runs while the app is suspended).
    func update(model: AppModel) {
        guard let ride, closing != ride.id else { return }
        // the fix's own time: the pace counts from when the train was there, and a call with no new
        // fix (a projection, the GPS lost in a tunnel) adds nothing and moves nothing. With no fix
        // time at all, nothing is recorded: the call's own time would read as the train standing still
        let fixedAt = model.location.fixedAt
        let found = model.position.flatMap { tracker?.status(at: $0) }
        // how far off the line each fix lies, before the check below drops the far ones: fixes far
        // from it for ten minutes say the ride was left (`RideTracker.note`)
        if let found, let fixedAt { tracker?.note(offTrackKm: found.offTrackKm, at: fixedAt) }
        if let followedAt, let why = tracker?.ending(arrivedAt: arrivedAt, followedAt: followedAt, tripNow: Shared.now, now: Date()) {
            // an arrival stays on the lock screen a while; a ride left or long past, its content wrong
            close(ride, model: model, policy: why == .arrived ? .after(Date().addingTimeInterval(Self.arrivedLinger)) : .immediate, byClockMove: false)
            return
        }
        // a position far off the track says nothing about this ride (still on the platform, or a wrong train)
        guard let s = found, s.offTrackKm < RideTracker.offTrack else { return }
        if status != s { status = s }
        if let fixedAt { tracker?.record(km: s.km, at: fixedAt) }
        let fix = fixedAt ?? Date()
        let speed = model.location.speedKmh
        let left = tracker?.minutesLeft(km: s.km, speedKmh: speed)
        // from the fix: on the trip's clock for the app, shown as hours and minutes and kept to the
        // minute, so it changes once a minute at most instead of with every fix (the accessory over
        // the tab bar redraws when it does); on the real clock, to the second, for the Live Activity
        let eta = left.map { RideTracker.arrival(minutesLeft: $0, fixedAt: fix, clockOffset: model.clockOffset) }
        if arrival != eta?.shown { arrival = eta?.shown }
        liveArrival = eta?.live
        let state = makeState(s, model: model)
        // ring as the train leaves the stop before yours, never later than the timetable's alarm (real
        // time, as alarms are), nothing once that has had its time, and once an alarm for the ride
        // has rung only the timetable's (`RideTracker.alarm`, told what is set); a time within two
        // minutes of the one set is not worth a call (AlarmService would keep the alarm it has anyway).
        // A stop less than a minute away, or passed, is said in a notification instead, once per ride
        // (`RideTracker.wake`, `AlarmService.firstNotice`)
        if !s.arrived, model.wakeAlarmIsOn(ride) {
            let current = model.alarms.time(of: ride.id)
            // a notice only where it can be seen: else the alarm, however close (`RideTracker.wake`)
            let canNotify = model.notifications.alertsAuthorized
            switch tracker?.wake(km: s.km, speedKmh: speed, at: fix, notAfter: timetableAlarm?.addingTimeInterval(-model.clockOffset), scheduled: current, now: Date(), canNotify: canNotify) {
            case .alarm(let at)? where current.map({ abs($0.timeIntervalSince(at)) >= 120 }) ?? true:
                Task { await model.alarms.alight(rideID: ride.id, station: ride.toName, at: at) }
            case .notice?:
                if model.alarms.firstNotice(for: ride.id) {
                    // woken by a fix under the lock screen: iOS waits for the notification to be posted
                    BackgroundWork.run(name: "Báo sắp tới ga xuống") { await model.notifications.alightSoon(ride) }
                }
            default:
                break
            }
        }
        let changed = state.next != lastState?.next || state.alight != lastState?.alight || state.fuji != lastState?.fuji || state.arrived != lastState?.arrived
        if changed || Date().timeIntervalSince(lastPush) > 30 {
            lastState = state
            lastPush = Date()
            Task { await activity?.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(600), relevanceScore: state.alight ? 100 : 60)) }
        }
        if s.arrived, !ending {
            ending = true
            arrivedAt = Date()
            model.rideArrived(ride)
            // closes this ride only: one started meanwhile (a change of trains within the 90
            // seconds) keeps its Live Activity, its alarm and its background positions
            let id = ride.id
            Task {
                try? await Task.sleep(for: .seconds(RideTracker.closeAfterArrival))
                await self.end(model: model, immediately: false, only: id)
            }
        }
    }

    /// Stops following the ride; with `only`, only if that is still the ride followed.
    func end(model: AppModel, immediately: Bool, only rideID: String? = nil) async {
        guard let ride, rideID == nil || ride.id == rideID, let claimed = claim(ride, model: model, byClockMove: false) else { return }
        await release(ride, claimed, model: model, policy: immediately ? .immediate : .after(Date().addingTimeInterval(Self.arrivedLinger)))
    }

    /// The trip's clock moved (a rehearsal starting, moving or ending), from a call that cannot wait:
    /// the followed ride ends at once, its times belonging to the clock it was followed on, and is not
    /// kept from starting again (`byClockMove`, decided in `RideClock.endIsKept`); the rehearsal's ended
    /// rides are forgotten, the real ones stay (`EndedRides`). Neither depends on the other's order.
    func clockMoved(model: AppModel) {
        if let ride { close(ride, model: model, policy: .immediate, byClockMove: true) }
        ends.offsetChanged()
    }

    /// A ride `RideTracker.ending` says is over, ended from a call that cannot wait for it: often a
    /// fix or a move that woke the app under the lock screen, so iOS waits for the end to be done.
    private func close(_ ride: Ride, model: AppModel, policy: ActivityUIDismissalPolicy, byClockMove: Bool) {
        guard let claimed = claim(ride, model: model, byClockMove: byClockMove) else { return }
        BackgroundWork.run(name: "Kết thúc chuyến") { await self.release(ride, claimed, model: model, policy: policy) }
    }

    /// What an end that has taken its ride lets go of besides the ride itself.
    private struct Claimed {
        /// the ride's alarm is its own to cancel (`RideClock.endCancelsAlarm`)
        let cancelsAlarm: Bool
    }

    /// The first of the paths ending a ride takes it; the others find it taken (nil). Set before
    /// anything waits, so two ends of one ride never both run, and decided on the clock of this
    /// moment: a rehearsal starting or ending moves the clock and ends the ride in one step.
    private func claim(_ ride: Ride, model: AppModel, byClockMove: Bool) -> Claimed? {
        guard self.ride?.id == ride.id, closing != ride.id else { return nil }
        closing = ride.id
        // a ride ended by any path is not started again on its own on the clock it was followed on
        // (the button on the platform, a taxi after getting off read as a train); one ended because the
        // clock changed is not kept (`RideClock.endIsKept`)
        ends.insert(ride.id, clock: clock, rehearsingNow: model.rehearsing, byClockMove: byClockMove)
        return Claimed(cancelsAlarm: clock.endCancelsAlarm(rehearsingNow: model.rehearsing))
    }

    /// Everything the ride holds, let go of once.
    private func release(_ ride: Ride, _ claimed: Claimed, model: AppModel, policy: ActivityUIDismissalPolicy) async {
        // its alarm, when it is its own: the timetable's comes back with the re-plan below while it is
        // still ahead. A rehearsal's ride set none, and the slot of its id holds the real ride's
        // timetable alarm; a real ride ended as a rehearsal starts keeps its own, which no re-plan
        // would bring back while rehearsing (`RideClock`)
        if claimed.cancelsAlarm { model.alarms.cancel(ride.id) }
        if let activity, let last = lastState {
            await activity.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: policy)
        }
        // the activity's end above suspends: a ride started meanwhile is not this one's to clear, but
        // the claim is: this ride, followed again later, can be ended again
        guard self.ride?.id == ride.id else {
            if closing == ride.id { closing = nil }
            return
        }
        activity = nil
        self.ride = nil
        tracker = nil
        timetableAlarm = nil
        followedAt = nil
        arrivedAt = nil
        liveArrival = nil
        status = nil
        arrival = nil
        lastState = nil
        ending = false
        closing = nil
        clock = RideClock(rehearsal: false)
        // back to what the moment calls for: the ordinary stream on screen, nothing behind the lock
        // (the navigation stream and its background session end)
        model.location.follow(model)
        // the projection without it, and the re-plan its hold kept back
        model.rideEnded()
    }

    /// The ride was ended since launch on the clock running now (a rehearsal's: since its offset was
    /// set): `AppModel.autoStartRide` does not start it again. Starting it by hand, or from the
    /// station's notification, still does.
    func wasEnded(_ rideID: String, model: AppModel) -> Bool {
        ends.contains(rideID, rehearsingNow: model.rehearsing)
    }

    /// Back on screen (`AppModel.activate`): a Live Activity this run does not hold (a run killed
    /// mid-ride left it; a second one of the same ride) is ended at once. Only that: the ride's alarm
    /// and everything else stay as they are, nothing is followed after a relaunch, and the alarm may
    /// be all that still watches for the stop. One that has ended and waits out its time on the lock
    /// screen is left to it.
    func endOrphans() {
        let held = activity?.id
        for orphan in Activity<RideAttributes>.activities where orphan.id != held {
            switch orphan.activityState {
            case .active, .stale, .pending:
                Task { await orphan.end(nil, dismissalPolicy: .immediate) }
            default:
                break
            }
        }
    }

    #if DEBUG
    /// When the followed ride ends on its own, by the clock (`RideTracker.deadline`), on the trip's
    /// clock, for the device checks.
    var deadline: Date? { followedAt.flatMap { tracker?.deadline(followedAt: $0) } }
    #endif

    private func makeState(_ s: RideTracker.Status, model: AppModel) -> RideAttributes.ContentState {
        guard let ride else { return .init(next: "", nextJa: "", stopsLeft: 0, progress: 0, arrival: nil, fuji: nil, view: nil, alight: false, arrived: false) }
        guard let next = s.nextStop.map({ ride.stations[$0] }) ?? ride.stations.last else {
            return .init(next: ride.toName, nextJa: ride.toName, stopsLeft: 0, progress: s.progress, arrival: liveArrival, fuji: nil, view: nil, alight: s.alightSoon, arrived: s.arrived)
        }
        let view = s.events.map { ride.events[$0] }.first { $0.side == .left || $0.side == .right }
        let viewText = view.map { e in "\(e.side == .left ? "Trái" : "Phải"): \(e.what.prefix(60))" }
        return .init(next: next.en, nextJa: next.ja, stopsLeft: s.stopsLeft, progress: s.progress, arrival: liveArrival,
                     fuji: s.fujiSide?.rawValue, view: viewText, alight: s.alightSoon, arrived: s.arrived)
    }

    /// The first stop the plan walks to after this ride.
    private func walkAfter(_ ride: Ride, store: TripStore) -> Place? {
        guard let day = store.day(ride.day), let last = ride.legs.last,
              let i = day.items.firstIndex(where: { $0.move?.leg.id == last }) else { return nil }
        for item in day.items[(i + 1)...] {
            if case .move(let m) = item, store.mode(of: m.leg) != .walk { return nil }
            if case .stop(let s) = item, let p = store.place(s.place), p.kind != .station { return p }
        }
        return nil
    }
}

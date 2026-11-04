// Activity is not marked Sendable, yet update(_:) and end(_:dismissalPolicy:) run off the main
// actor, so Swift 6 rejects every call from it (Apple's own Live Activity code makes the same
// calls). ActivityKit serialises updates to an activity itself; accept its missing annotations.
@preconcurrency import ActivityKit
import Foundation
import Observation
import TripKit

/// Follows one ride: projects the position onto the track, keeps the Live Activity current,
/// and keeps the alighting alarm a few minutes before the stop before yours.
@Observable final class RideLiveService {
    private(set) var ride: Ride?
    private(set) var status: RideTracker.Status?
    private(set) var arrival: Date?
    private var tracker: RideTracker?
    private var activity: Activity<RideAttributes>?
    private var lastState: RideAttributes.ContentState?
    private var lastPush = Date.distantPast
    private var ending = false

    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// The ride being followed has reached its end and is only waiting to be closed: the next ride
    /// may start at once (a change of trains), it replaces this one.
    var hasArrived: Bool { ending }

    func start(_ ride: Ride, model: AppModel) {
        if self.ride?.id == ride.id { return }
        // one ride at a time: close the previous one without waiting for it
        if let old = activity, let last = lastState {
            Task { await old.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: .immediate) }
        }
        if let old = self.ride { model.alarms.cancel(old.id) }
        ending = false
        status = nil
        arrival = nil
        lastPush = .distantPast
        self.ride = ride
        tracker = RideTracker(ride: ride, store: model.store)
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

    /// Called on every position change.
    func update(model: AppModel) {
        guard let ride, let tracker else { return }
        guard let p = model.position, let s = tracker.status(at: p) else { return }
        // a position far off the track says nothing about this ride (still on the platform, or a wrong train)
        guard s.offTrackKm < RideTracker.offTrack else { return }
        if status != s { status = s }
        let left = tracker.minutesLeft(km: s.km, speedKmh: model.location.speedKmh)
        // shown as hours and minutes: kept to the minute, so it changes once a minute at most
        // instead of with every fix (the accessory over the tab bar redraws when it does)
        let eta = left.map { Date(timeIntervalSinceReferenceDate: (model.now.addingTimeInterval($0 * 60).timeIntervalSinceReferenceDate / 60).rounded(.down) * 60) }
        if arrival != eta { arrival = eta }
        let state = makeState(s, model: model)
        if !s.arrived, let prompt = tracker.minutesToAlightPrompt(km: s.km, speedKmh: model.location.speedKmh), model.wakeAlarmIsOn(ride) {
            // ring as the train leaves the stop before yours; a time within two minutes of the one
            // set is not worth a call (AlarmService would keep the alarm it has anyway)
            let at = Date().addingTimeInterval(max(0, prompt) * 60)
            if model.alarms.time(of: ride.id).map({ abs($0.timeIntervalSince(at)) >= 120 }) ?? true {
                Task { await model.alarms.alight(rideID: ride.id, station: ride.toName, at: at) }
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
            model.rideArrived(ride)
            // closes this ride only: one started meanwhile (a change of trains within the 90
            // seconds) keeps its Live Activity, its alarm and its background positions
            let id = ride.id
            Task {
                try? await Task.sleep(for: .seconds(90))
                await self.end(model: model, immediately: false, only: id)
            }
        }
    }

    /// Stops following the ride; with `only`, only if that is still the ride followed.
    func end(model: AppModel, immediately: Bool, only rideID: String? = nil) async {
        guard let ride, rideID == nil || ride.id == rideID else { return }
        model.alarms.cancel(ride.id)
        if let activity, let last = lastState {
            await activity.end(ActivityContent(state: last, staleDate: nil), dismissalPolicy: immediately ? .immediate : .after(Date().addingTimeInterval(15 * 60)))
        }
        // the activity's end above suspends: a ride started meanwhile is not this one's to clear
        guard self.ride?.id == ride.id else { return }
        activity = nil
        self.ride = nil
        tracker = nil
        status = nil
        arrival = nil
        lastState = nil
        ending = false
        // back to what the moment calls for: the ordinary stream on screen, nothing behind the lock
        model.location.follow(model)
    }

    private func makeState(_ s: RideTracker.Status, model: AppModel) -> RideAttributes.ContentState {
        guard let ride else { return .init(next: "", nextJa: "", stopsLeft: 0, progress: 0, arrival: nil, fuji: nil, view: nil, alight: false, arrived: false) }
        guard let next = s.nextStop.map({ ride.stations[$0] }) ?? ride.stations.last else {
            return .init(next: ride.toName, nextJa: ride.toName, stopsLeft: 0, progress: s.progress, arrival: arrival, fuji: nil, view: nil, alight: s.alightSoon, arrived: s.arrived)
        }
        let view = s.events.map { ride.events[$0] }.first { $0.side == .left || $0.side == .right }
        let viewText = view.map { e in "\(e.side == .left ? "Trái" : "Phải"): \(e.what.prefix(60))" }
        return .init(next: next.en, nextJa: next.ja, stopsLeft: s.stopsLeft, progress: s.progress, arrival: arrival,
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

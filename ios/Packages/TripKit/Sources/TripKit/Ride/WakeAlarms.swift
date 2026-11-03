import Foundation

/// Where an alarm's time came from: the timetable, set in advance for the long train rides
/// (`WakePlanner`), or the train's real progress once the ride is followed (the GPS).
public enum AlarmSource: String, Codable, Sendable {
    case timetable, ride
}

/// An alarm set for a ride: the system's id for it, when it rings, and where that time came from.
public struct AlarmSlot: Codable, Sendable, Hashable {
    public let id: UUID
    public let at: Date
    public let source: AlarmSource

    public init(id: UUID, at: Date, source: AlarmSource) {
        self.id = id
        self.at = at
        self.source = source
    }

    /// What the first builds saved has no `source`: those were the timetable's alarms.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        at = try c.decode(Date.self, forKey: .at)
        source = try c.decodeIfPresent(AlarmSource.self, forKey: .source) ?? .timetable
    }
}

/// One alarm wanted for a ride.
public struct WakeRequest: Sendable, Hashable {
    public let rideID: String
    /// the station to get off at, which the alarm names
    public let station: String
    public let at: Date
    public let source: AlarmSource

    public init(rideID: String, station: String, at: Date, source: AlarmSource) {
        self.rideID = rideID
        self.station = station
        self.at = at
        self.source = source
    }
}

/// What to do with a ride's alarm, given the one set and the one wanted.
///
/// - **Keep** a timetable alarm already set while its ride is still in `wanted` (by `rideID`, *not*
///   filtered by time) and the ride's switch is on. An alarm past its time (`at <= now`) counts as
///   having rung: it leaves `scheduled`, and cancel is not called.
/// - **Place a new one** only when `request.at > now + lead` (`timetableLead` for `.timetable`,
///   `rideLead` for `.ride`).
/// - `placement`: none set → `.replace` if there is lead enough, else `.skip`; the one set is `.ride`
///   and the request `.timetable` → `.skip`; off by less than `moveSlack` → `.relabel(.ride)` if the
///   request is `.ride` from the other source, else `.skip`; a request without lead enough →
///   `.skip` (**the one set stays as it is**); otherwise `.replace`.
/// - **Replacing:** schedule the new one (a new UUID) → check the `ticket` is still current → write
///   `scheduled[rideID]` and call `onChange` (saved) → *only then* `cancel(old.id)`. A failed cancel
///   of the old one puts its id in `orphans`, tried again by `reconcile()`.
/// - Permission refused, schedule throwing, or the lead run out after waiting on the prompt
///   (`placement` asked again after every `await`) → `return`, the one set stays as it is.
/// - `reconcile()`: an id in `systemAlarmIDs()` that is not in `scheduled` → cancel; an entry in
///   `scheduled` the system no longer has → dropped (rung, or turned off).
///
/// Two more: the GPS's alarm (`.ride`) is not the timetable's to keep or cancel, only past its time
/// is it dropped (a followed boat ride is never in `wanted`); and an old alarm replaced after its
/// time is forgotten, not cancelled, like any alarm that has rung (it may be ringing still).
public enum WakeReconciler {
    /// a new alarm from the timetable is set at least this long before it rings
    public static let timetableLead: TimeInterval = 60
    /// a new alarm from the GPS is set at least this long before it rings
    public static let rideLead: TimeInterval = 30
    /// moving an alarm by less than this is not worth a new one
    public static let moveSlack: TimeInterval = 120

    public enum Placement: Equatable, Sendable {
        /// leave the one set (or none) as it is
        case skip
        /// keep the alarm set, now owned by this source
        case relabel(AlarmSource)
        /// set a new alarm, then take back the one set
        case replace
    }

    /// The alarm stays in `scheduled`. One that does not and is still to ring is cancelled; one
    /// past its time is only forgotten.
    public static func keeps(_ slot: AlarmSlot, rideID: String, wanted: Set<String>, isOn: Bool, now: Date) -> Bool {
        guard slot.at > now else { return false }
        guard slot.source == .timetable else { return true }
        return wanted.contains(rideID) && isOn
    }

    public static func placement(current: AlarmSlot?, request: WakeRequest, now: Date) -> Placement {
        let lead = request.source == .timetable ? timetableLead : rideLead
        let inTime = request.at > now.addingTimeInterval(lead)
        guard let current else { return inTime ? .replace : .skip }
        if current.source == .ride, request.source == .timetable { return .skip }
        if abs(current.at.timeIntervalSince(request.at)) < moveSlack {
            return request.source == .ride && current.source != request.source ? .relabel(.ride) : .skip
        }
        return inTime ? .replace : .skip
    }
}

/// The system's alarms, as `WakeAlarms` uses them (AlarmKit in the app).
@MainActor public protocol AlarmScheduling: AnyObject {
    var isAuthorized: Bool { get }
    /// Asks, if it was never asked; true when alarms may be set.
    func requestAuthorization() async -> Bool
    /// Sets an alarm with this id; once it returns, the alarm is set.
    func schedule(id: UUID, request: WakeRequest) async throws
    func cancel(id: UUID) throws
    /// The alarms the system holds for the app, ringing ones included.
    func systemAlarmIDs() throws -> Set<UUID>
}

/// One alarm per ride before the station to get off at, by `WakeReconciler`'s rules: what is still
/// wanted is kept however close it is, a new alarm is set only with time enough, and the one set is
/// cancelled only once its replacement is set and saved. A traveller asleep on the train is never
/// left without the alarm they had because a new one could not be set.
///
/// One alarm is being set per ride at a time (asking for permission, scheduling): a call made
/// meanwhile waits, only the latest is kept, and a cancel takes back an alarm being set as it lands.
/// What the system holds and the app does not know (it was killed between setting an alarm and
/// saving it) is taken back by `reconcile()`.
@MainActor public final class WakeAlarms {
    /// what is set, per ride; every change is handed to `onChange` (saved, shown)
    public private(set) var scheduled: [String: AlarmSlot] {
        didSet { onChange(scheduled) }
    }

    /// the latest thing the system refused (setting, cancelling, listing), for Settings › Chẩn đoán;
    /// what was set before it is left as it was
    public private(set) var lastError: String?

    private let scheduler: any AlarmScheduling
    private let now: () -> Date
    private let onChange: ([String: AlarmSlot]) -> Void
    private let serial = OneAtATime<WakeRequest>()
    /// alarms the system would not cancel, tried again by `reconcile()`
    private var orphans: Set<UUID> = []
    /// alarms being set right now: the system may hold them before the app does
    private var placing: Set<UUID> = []

    /// `saved` as it was saved, alarms past their time included: one may be ringing as the app
    /// opens, and `reconcile()` would cancel it if it were not known.
    public init(scheduler: any AlarmScheduling, saved: [String: AlarmSlot], now: @escaping () -> Date = Date.init,
                onChange: @escaping ([String: AlarmSlot]) -> Void) {
        self.scheduler = scheduler
        self.scheduled = saved
        self.now = now
        self.onChange = onChange
    }

    /// The timetable's alarms, made to match `wanted`: those no longer wanted, or switched off, are
    /// cancelled; the missing ones are set, moved ones moved. A ride's GPS alarm is left as it is.
    /// Never asks for permission (this runs in the background too): without it, nothing new is set.
    public func planWake(_ wanted: [WakeRequest], isOn: (String) -> Bool) async {
        let rides = Set(wanted.map(\.rideID))
        let t = now()
        for (rideID, slot) in scheduled where !WakeReconciler.keeps(slot, rideID: rideID, wanted: rides, isOn: isOn(rideID), now: t) {
            // rung, or ringing right now: the planner no longer wants a wake past its time, and
            // cancelling it would silence it (nor is a GPS alarm being set for the ride stopped)
            if slot.at > t { cancel(rideID) } else { scheduled[rideID] = nil }
        }
        for r in wanted where r.source == .timetable && scheduled[r.rideID]?.source != .ride && isOn(r.rideID) {
            await alight(r)
        }
    }

    /// Ring at `request.at` for the ride. One call per ride runs at a time; one made meanwhile is
    /// done after it, the latest only. The GPS knows better than the timetable: a timetable time
    /// never replaces a followed ride's.
    public func alight(_ request: WakeRequest) async {
        await serial.run(request.rideID, request, overrides: { running, waiting in
            request.source == .ride || (running.source != .ride && waiting?.source != .ride)
        }) { r, ticket in
            await self.place(r, ticket: ticket)
        }
    }

    private func place(_ r: WakeRequest, ticket: OneAtATime<WakeRequest>.Ticket) async {
        guard settle(r) else { return }
        // the timetable never asks: permission is asked for when a ride is followed
        let allowed = r.source == .timetable ? scheduler.isAuthorized : await scheduler.requestAuthorization()
        // cancelled while the prompt was up, or answered too late for a new alarm
        guard allowed, serial.isCurrent(ticket), settle(r) else { return }
        let id = UUID()
        placing.insert(id)
        do {
            try await scheduler.schedule(id: id, request: r)
        } catch {
            placing.remove(id)
            lastError = "Đặt báo thức: \(error)"
            return
        }
        placing.remove(id)
        guard serial.isCurrent(ticket) else {
            takeBack(id)
            return
        }
        // read after the wait: an alarm dropped meanwhile is not this one's to cancel
        let old = scheduled[r.rideID]
        scheduled[r.rideID] = AlarmSlot(id: id, at: r.at, source: r.source)
        if let old, old.at > now() { takeBack(old.id) }
    }

    /// `placement` applied as far as it goes without a new alarm; true when one is needed.
    private func settle(_ r: WakeRequest) -> Bool {
        let current = scheduled[r.rideID]
        switch WakeReconciler.placement(current: current, request: r, now: now()) {
        case .skip:
            return false
        case .relabel(let source):
            if let current { scheduled[r.rideID] = AlarmSlot(id: current.id, at: current.at, source: source) }
            return false
        case .replace:
            return true
        }
    }

    /// No alarm for the ride, from either source, including one being set right now.
    public func cancel(_ rideID: String) {
        serial.cancel(rideID)
        guard let slot = scheduled[rideID] else { return }
        scheduled[rideID] = nil
        takeBack(slot.id)
    }

    /// After a time away, `scheduled` made to match what the system holds: an alarm it holds that the
    /// app does not know is cancelled, one the app knows that it no longer holds is forgotten (it
    /// rang, or was turned off). An alarm being set is left alone; with no list to read, only the
    /// alarms that would not cancel before are tried again, and nothing is forgotten.
    public func reconcile() {
        let system: Set<UUID>
        do {
            system = try scheduler.systemAlarmIDs()
        } catch {
            lastError = "Đọc báo thức: \(error)"
            for id in orphans { takeBack(id) }
            return
        }
        // an orphan the system no longer holds has rung
        orphans.formIntersection(system)
        let known = Set(scheduled.values.map(\.id))
        for id in system where !known.contains(id) && !placing.contains(id) {
            takeBack(id)
        }
        for (rideID, slot) in scheduled where !system.contains(slot.id) {
            scheduled[rideID] = nil
        }
    }

    private func takeBack(_ id: UUID) {
        do {
            try scheduler.cancel(id: id)
            orphans.remove(id)
        } catch {
            orphans.insert(id)
            lastError = "Huỷ báo thức: \(error)"
        }
    }
}

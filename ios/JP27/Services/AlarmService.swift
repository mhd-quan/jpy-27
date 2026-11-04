import AlarmKit
import Foundation
import Observation
import SwiftUI
import TripKit

nonisolated struct AlightAlarm: AlarmMetadata {
    var rideID: String
    var station: String
}

/// AlarmKit as `WakeAlarms` asks for it: the alarm itself (it rings through silent mode and Focus,
/// named after the station), the permission, and the alarms the system holds for the app.
final class AlarmKitScheduler: AlarmScheduling {
    var isAuthorized: Bool { AlarmManager.shared.authorizationState == .authorized }

    func requestAuthorization() async throws -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return try await AlarmManager.shared.requestAuthorization() == .authorized
        }
    }

    func schedule(id: UUID, request: WakeRequest) async throws {
        let alert = AlarmPresentation.Alert(
            title: "Sắp tới \(request.station)",
            stopButton: AlarmButton(text: "Đã thức", textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<AlightAlarm>(
            presentation: AlarmPresentation(alert: alert),
            metadata: AlightAlarm(rideID: request.rideID, station: request.station),
            tintColor: .accentColor
        )
        let configuration = AlarmManager.AlarmConfiguration<AlightAlarm>(schedule: .fixed(request.at), attributes: attributes)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    func cancel(id: UUID) throws {
        try AlarmManager.shared.cancel(id: id)
    }

    func systemAlarms() throws -> [UUID: SystemAlarmState] {
        var states: [UUID: SystemAlarmState] = [:]
        for alarm in try AlarmManager.shared.alarms {
            states[alarm.id] = Self.state(of: alarm)
        }
        return states
    }

    private static func state(of alarm: Alarm) -> SystemAlarmState {
        switch alarm.state {
        case .scheduled: return .scheduled
        case .countdown: return .countdown
        case .paused: return .paused
        case .alerting: return .alerting
        // a state added later is not "waiting": reconcile leaves it alone
        @unknown default: return .unknown
        }
    }
}

/// A real alarm (AlarmKit) before the station to get off at: it rings through silent mode and
/// Focus, unlike a notification, which a dozing passenger can sleep through.
///
/// Two sources, one alarm per ride: the timetable sets it in advance for the long train rides of
/// today and tomorrow (`planWake`, rides chosen by `WakePlanner`), so it rings even if the ride is
/// never followed; following the ride moves it to what the GPS says. What to keep, set and replace
/// is `WakeAlarms` (TripKit): an alarm still wanted is kept however close it is, and one is
/// replaced only once its replacement is set. This holds the switches, keeps what is set on disk
/// (AlarmKit keeps alarms across launches) and shows it.
@Observable final class AlarmService {
    /// what is set, per ride: `WakeAlarms`'s, mirrored here so the views that read it redraw
    private(set) var scheduled: [String: AlarmSlot] = [:]

    /// the switch, for rides where it was moved by hand; otherwise a ride follows its default
    /// (on for the long train rides `WakePlanner` picks, off for boats, buses and the metro)
    private(set) var choices: [String: Bool] = [:] {
        didSet { Shared.defaults.set(choices, forKey: Self.choicesKey) }
    }

    private let scheduler = AlarmKitScheduler()
    /// set once at the end of `init`, whose `self` its `onChange` needs
    @ObservationIgnored private var core: WakeAlarms!
    /// what is set could not be read from disk, or written to it
    @ObservationIgnored private var storeProblem: String?

    /// the rides told "Sắp tới …" in a notification (`firstNotice`), and when
    @ObservationIgnored private var noticed: [String: Date] = [:]
    /// the same during a rehearsal: kept in memory only, so a rehearsal never uses up a real ride's
    @ObservationIgnored private var noticedRehearsing: Set<String> = []

    private static let key = "alarms.scheduled"
    private static let choicesKey = "alarms.choices"
    private static let noticedKey = "alarms.noticed"

    init() {
        // nil: there is a record and it could not be read, so no alarm AlarmKit holds is taken for a stray
        var saved: [String: AlarmSlot]? = [:]
        if let data = Shared.defaults.data(forKey: Self.key) {
            // what earlier builds saved reads too: an entry with no source was the timetable's
            do {
                saved = try JSONDecoder().decode([String: AlarmSlot].self, from: data)
            } catch {
                saved = nil
                storeProblem = "Đọc báo thức đã lưu: \(error)"
            }
        }
        scheduled = saved ?? [:]
        choices = Shared.defaults.dictionary(forKey: Self.choicesKey) as? [String: Bool] ?? [:]
        noticed = Shared.defaults.dictionary(forKey: Self.noticedKey) as? [String: Date] ?? [:]
        // a rehearsal sets no real alarm: its times are not real ones
        core = WakeAlarms(scheduler: scheduler, saved: saved, rehearsing: { Shared.rehearsing }, onChange: { [weak self] slots in
            self?.scheduled = slots
            self?.save(slots)
        })
    }

    private func save(_ slots: [String: AlarmSlot]) {
        do {
            let data = try JSONEncoder().encode(slots)
            Shared.defaults.set(data, forKey: Self.key)
        } catch {
            storeProblem = "Lưu báo thức: \(error)"
        }
    }

    /// What the disk could not do with the alarms, else the latest thing the system refused
    /// (permission, setting, cancelling, listing alarms); read when shown, not observed. What was set
    /// before it is left as it was.
    var lastError: String? { storeProblem ?? core.lastError }

    func isOn(_ rideID: String, default on: Bool) -> Bool { choices[rideID] ?? on }

    /// Turning it off cancels what is set, from either source; turning it on lets the next
    /// reconciliation, or the next position of a followed ride, set it again.
    func setOn(_ on: Bool, rideID: String) {
        choices[rideID] = on
        if !on { cancel(rideID) }
    }

    /// The timetable's alarms, made to match `wanted` (`WakeAlarms.planWake`): those no longer
    /// wanted or switched off are cancelled, the missing ones set, moved ones moved. A ride being
    /// followed keeps its GPS alarm. Never asks for permission (this runs in the background too):
    /// without it, nothing new is set.
    func planWake(_ wanted: [WakePlanner.Wake]) async {
        let requests = wanted.map { WakeRequest(rideID: $0.rideID, station: $0.station, at: $0.at, source: .timetable) }
        await core.planWake(requests, isOn: { self.isOn($0, default: true) })
    }

    var authorized: Bool { scheduler.isAuthorized }

    /// An error is shown in Settings › Chẩn đoán and counts as a no.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await core.requestAuthorization()
    }

    func isSet(_ rideID: String) -> Bool { scheduled[rideID] != nil }

    /// When the ride's alarm rings, if one is set.
    func time(of rideID: String) -> Date? { scheduled[rideID]?.at }

    /// Ring at `date` for the ride (`WakeAlarms.alight`): moving it by less than two minutes is not
    /// worth a new alarm, and the GPS's time always takes the place of the timetable's. Nothing while
    /// rehearsing (`WakeAlarms` asks `Shared.rehearsing`).
    func alight(rideID: String, station: String, at date: Date, source: AlarmSource = .ride) async {
        await core.alight(WakeRequest(rideID: rideID, station: station, at: date, source: source))
    }

    /// True the first time it is asked for a ride, then never again: a followed ride whose stop before
    /// yours is too close for an alarm is told so in one notification (`RideTracker.wake`), not at
    /// every fix, nor again after a relaunch. Kept two days. During a rehearsal kept in memory only,
    /// so the evening's rehearsal of tomorrow's ride leaves the real one its notice.
    func firstNotice(for rideID: String) -> Bool {
        if Shared.rehearsing { return noticedRehearsing.insert(rideID).inserted }
        guard noticed[rideID] == nil else { return false }
        let now = Date()
        noticed = noticed.filter { now.timeIntervalSince($0.value) < 2 * 86_400 }
        noticed[rideID] = now
        Shared.defaults.set(noticed, forKey: Self.noticedKey)
        return true
    }

    /// No alarm for the ride, from either source, including one being set right now.
    func cancel(_ rideID: String) {
        core.cancel(rideID)
    }

    /// Back in the app: an alarm the system holds, still waiting, that the app does not know (it was
    /// killed between setting one and saving it) is cancelled, and one that rang is forgotten. Never
    /// one ringing; nothing without permission (`WakeAlarms.reconcile`).
    func reconcile() {
        core.reconcile()
    }

    #if DEBUG
    /// What AlarmKit holds for the app right now, by state ("đang reo 1 · đang chờ 2"), for the
    /// device checks.
    func systemAlarmsSummary() -> String {
        do {
            let states = try Array(scheduler.systemAlarms().values)
            guard !states.isEmpty else { return "Không có" }
            let names: [(SystemAlarmState, String)] = [
                (.alerting, "đang reo"), (.scheduled, "đang chờ"), (.countdown, "đếm ngược"), (.paused, "tạm dừng"), (.unknown, "khác"),
            ]
            return names.compactMap { state, name in
                let count = states.filter { $0 == state }.count
                return count > 0 ? "\(name) \(count)" : nil
            }.joined(separator: " · ")
        } catch {
            return "Không đọc được: \(error)"
        }
    }
    #endif
}

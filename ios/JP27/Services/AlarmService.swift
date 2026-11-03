import AlarmKit
import Foundation
import Observation
import SwiftUI

nonisolated struct AlightAlarm: AlarmMetadata {
    var rideID: String
    var station: String
}

/// A real alarm (AlarmKit) before the station to get off at: it rings through silent mode and
/// Focus, unlike a notification, which a dozing passenger can sleep through.
///
/// Two sources, one alarm per ride: the timetable sets it in advance for the long train rides of
/// today and tomorrow (`planWake`, rides chosen by `WakePlanner`), so it rings even if the ride is
/// never followed; following the ride moves it to what the GPS says. Each time the plan changes the
/// timetable's alarms are reconciled: one no longer wanted (ride taken, day swapped for its
/// alternative, alarm turned off) is cancelled. What is set, and the rides turned off, are kept on
/// disk, since AlarmKit keeps alarms across launches.
@Observable final class AlarmService {
    nonisolated enum Source: String, Codable {
        case timetable, ride
    }

    struct Scheduled {
        let id: UUID
        let at: Date
        let source: Source
    }

    private(set) var scheduled: [String: Scheduled] = [:] {
        didSet { save() }
    }

    /// the switch, for rides where it was moved by hand; otherwise a ride follows its default
    /// (on for the long train rides `WakePlanner` picks, off for boats, buses and the metro)
    private(set) var choices: [String: Bool] = [:] {
        didSet { Shared.defaults.set(choices, forKey: Self.choicesKey) }
    }

    private nonisolated struct Saved: Codable {
        let id: UUID
        let at: Date
        /// absent in what earlier builds saved: those were timetable alarms
        let source: Source?
    }

    private static let key = "alarms.scheduled"
    private static let choicesKey = "alarms.choices"

    init() {
        if let data = Shared.defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: Saved].self, from: data) {
            // an alarm whose time has passed has rung or been stopped
            scheduled = saved.filter { $0.value.at > Date() }.mapValues { Scheduled(id: $0.id, at: $0.at, source: $0.source ?? .timetable) }
        }
        choices = Shared.defaults.dictionary(forKey: Self.choicesKey) as? [String: Bool] ?? [:]
    }

    private func save() {
        let saved = scheduled.mapValues { Saved(id: $0.id, at: $0.at, source: $0.source) }
        if let data = try? JSONEncoder().encode(saved) { Shared.defaults.set(data, forKey: Self.key) }
    }

    func isOn(_ rideID: String, default on: Bool) -> Bool { choices[rideID] ?? on }

    /// Turning it off cancels what is set, from either source; turning it on lets the next
    /// reconciliation, or the next position of a followed ride, set it again.
    func setOn(_ on: Bool, rideID: String) {
        choices[rideID] = on
        if !on { cancel(rideID) }
    }

    /// The timetable's alarms, made to match `wanted`: those no longer wanted are cancelled, the
    /// missing ones set, moved ones moved. A ride being followed keeps its GPS alarm. Never asks
    /// for permission (this runs in the background too): without it, nothing is set.
    func planWake(_ wanted: [(rideID: String, station: String, at: Date)]) async {
        let keep = wanted.filter { isOn($0.rideID, default: true) && $0.at > Date().addingTimeInterval(60) }
        let ids = Set(keep.map(\.rideID))
        for (rideID, s) in scheduled where s.source == .timetable && !ids.contains(rideID) {
            cancel(rideID)
        }
        guard authorized else { return }
        for r in keep where scheduled[r.rideID]?.source != .ride {
            await alight(rideID: r.rideID, station: r.station, at: r.at, source: .timetable)
        }
    }

    var authorized: Bool { AlarmManager.shared.authorizationState == .authorized }

    @discardableResult
    func requestAuthorization() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized: return true
        case .denied: return false
        default: return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        }
    }

    func isSet(_ rideID: String) -> Bool { scheduled[rideID] != nil }

    /// Ring at `date` for the ride; moving it by less than two minutes is not worth a new alarm.
    func alight(rideID: String, station: String, at date: Date, source: Source = .ride) async {
        if let current = scheduled[rideID], abs(current.at.timeIntervalSince(date)) < 120 {
            if current.source != source, source == .ride { scheduled[rideID] = Scheduled(id: current.id, at: current.at, source: .ride) }
            return
        }
        cancel(rideID)
        // the timetable never asks: permission is asked for when a ride is followed
        guard date > Date().addingTimeInterval(30), source == .timetable ? authorized : await requestAuthorization() else { return }
        let alert = AlarmPresentation.Alert(
            title: "Sắp tới \(station)",
            stopButton: AlarmButton(text: "Đã thức", textColor: .white, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<AlightAlarm>(
            presentation: AlarmPresentation(alert: alert),
            metadata: AlightAlarm(rideID: rideID, station: station),
            tintColor: .accentColor
        )
        let id = UUID()
        let configuration = AlarmManager.AlarmConfiguration<AlightAlarm>(schedule: .fixed(date), attributes: attributes)
        do {
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            scheduled[rideID] = Scheduled(id: id, at: date, source: source)
        } catch {}
    }

    func cancel(_ rideID: String) {
        guard let current = scheduled.removeValue(forKey: rideID) else { return }
        try? AlarmManager.shared.cancel(id: current.id)
    }
}

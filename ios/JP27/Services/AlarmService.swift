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
/// Two sources, one alarm per ride: the timetable sets it in advance for the day's long rides
/// (`planWake`), so it rings even if the ride is never followed; following the ride moves it to
/// what the GPS says. What is set is kept on disk, since AlarmKit keeps alarms across launches.
@Observable final class AlarmService {
    private(set) var scheduled: [String: (id: UUID, at: Date)] = [:] {
        didSet { save() }
    }

    private nonisolated struct Saved: Codable {
        let id: UUID
        let at: Date
    }

    private static let key = "alarms.scheduled"

    init() {
        if let data = Shared.defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: Saved].self, from: data) {
            // an alarm whose time has passed has rung or been stopped
            scheduled = saved.filter { $0.value.at > Date() }.mapValues { ($0.id, $0.at) }
        }
    }

    private func save() {
        let saved = scheduled.mapValues { Saved(id: $0.id, at: $0.at) }
        if let data = try? JSONEncoder().encode(saved) { Shared.defaults.set(data, forKey: Self.key) }
    }

    /// Timetable alarms for rides not set yet; never asks for permission (this runs in the
    /// background too): without it, nothing is set.
    func planWake(_ rides: [(rideID: String, station: String, at: Date)]) async {
        guard authorized else { return }
        for r in rides where scheduled[r.rideID] == nil && r.at > Date().addingTimeInterval(60) {
            await alight(rideID: r.rideID, station: r.station, at: r.at)
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
    func alight(rideID: String, station: String, at date: Date) async {
        if let current = scheduled[rideID], abs(current.at.timeIntervalSince(date)) < 120 { return }
        cancel(rideID)
        guard date > Date().addingTimeInterval(30), await requestAuthorization() else { return }
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
            scheduled[rideID] = (id, date)
        } catch {}
    }

    func cancel(_ rideID: String) {
        guard let current = scheduled.removeValue(forKey: rideID) else { return }
        try? AlarmManager.shared.cancel(id: current.id)
    }
}

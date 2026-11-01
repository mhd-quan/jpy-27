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
@Observable final class AlarmService {
    private(set) var scheduled: [String: (id: UUID, at: Date)] = [:]

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

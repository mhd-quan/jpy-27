import CoreMotion
import Foundation
import Network
import Observation

/// Walking pace from the pedometer, and whether you are walking or riding, from motion activity.
@Observable final class MotionService {
    private let pedometer = CMPedometer()
    private let activity = CMMotionActivityManager()
    private(set) var walking = false
    private(set) var riding = false
    private(set) var running = false

    /// km/h while walking, and minutes it covers
    var onPace: ((Double, Double) -> Void)?

    private var pending: (kmh: Double, minutes: Double) = (0, 0)
    private var lastSample: Date?

    func start() {
        guard !running else { return }
        running = true
        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: .main) { [weak self] a in
                guard let self, let a else { return }
                MainActor.assumeIsolated {
                    self.walking = a.walking && a.confidence != .low
                    self.riding = a.automotive && a.confidence != .low
                }
            }
        }
        guard CMPedometer.isPaceAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data, let pace = data.currentPace?.doubleValue, pace > 0 else { return }
            let kmh = 3.6 / pace
            Task { @MainActor in self?.sample(kmh: kmh) }
        }
    }

    func stop() {
        pedometer.stopUpdates()
        activity.stopActivityUpdates()
        running = false
    }

    /// Fold instantaneous pace into three-minute samples of real walking.
    private func sample(kmh: Double) {
        let now = Date()
        defer { lastSample = now }
        guard walking, let last = lastSample else { return }
        let minutes = min(2, now.timeIntervalSince(last) / 60)
        pending.kmh = (pending.kmh * pending.minutes + kmh * minutes) / max(0.01, pending.minutes + minutes)
        pending.minutes += minutes
        if pending.minutes >= 3 {
            onPace?(pending.kmh, pending.minutes)
            pending = (0, 0)
        }
    }

    /// Steps and distance between two instants (the journal's day total).
    func walked(from: Date, to: Date) async -> (steps: Int, km: Double)? {
        guard CMPedometer.isStepCountingAvailable() else { return nil }
        return await withCheckedContinuation { cont in
            pedometer.queryPedometerData(from: from, to: to) { data, _ in
                let result = data.map { (Int(truncating: $0.numberOfSteps), ($0.distance?.doubleValue ?? 0) / 1000) }
                cont.resume(returning: result)
            }
        }
    }
}

/// Online or not, for the offline badge and for skipping network work.
@Observable final class NetworkStatus {
    private(set) var online = true
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in self?.online = ok }
        }
        monitor.start(queue: DispatchQueue(label: "jp27.network"))
    }
}

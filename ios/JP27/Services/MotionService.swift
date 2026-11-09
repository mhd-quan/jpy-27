import CoreMotion
import Foundation
import Network
import Observation
import TripKit

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
                    // one already queued on the main queue as `stop()` ran is from before it
                    guard self.running else { return }
                    self.set(walking: a.walking && a.confidence != .low, riding: a.automotive && a.confidence != .low)
                }
            }
        }
        guard CMPedometer.isPaceAvailable() else { return }
        // CoreMotion calls this on its own queue. Written inside a main-actor method, the block
        // would be main-actor isolated and Swift 6's runtime check would trap on entry: it is
        // @Sendable (nonisolated) and hops to the main actor itself.
        pedometer.startUpdates(from: Date()) { @Sendable [weak self] data, _ in
            guard let data, let pace = data.currentPace?.doubleValue, pace > 0 else { return }
            let kmh = 3.6 / pace
            Task { @MainActor in self?.sample(kmh: kmh) }
        }
    }

    /// The app left the screen (`AppModel.deactivate`): nothing here is worth waking for.
    func stop() {
        guard running else { return }
        pedometer.stopUpdates()
        activity.stopActivityUpdates()
        running = false
        // the gap until the next start is not walking
        lastSample = nil
        // nor what was true when it left: back on screen `AppModel.autoStartRide` reads these at
        // once, before the first update (which reports the motion of that moment) arrives, and the
        // bus of an hour ago would start the train you stand far from
        set(walking: false, riding: false)
    }

    /// Written only when they change: views redraw with every write.
    private func set(walking: Bool, riding: Bool) {
        if self.walking != walking { self.walking = walking }
        if self.riding != riding { self.riding = riding }
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
            pedometer.queryPedometerData(from: from, to: to) { @Sendable data, _ in
                let result = data.map { (Int(truncating: $0.numberOfSteps), ($0.distance?.doubleValue ?? 0) / 1000) }
                cont.resume(returning: result)
            }
        }
    }
}

/// Online or not, two ways. `raw` is the path as it is this instant: for network work and for what is
/// written to disk (a fetch, a picture kept). `online` is what is drawn (a live map or its offline plot, "không
/// có mạng"): the first report at once, then a change only once it has held 2 s, and only when it differs.
/// A flaky signal no longer tears a page's live map down and builds it again (`SteadyValue`).
/// One exception, drawn yet on `raw` (R-312): the state of a download in progress (Settings › Dùng khi mất sóng: "Đang
/// tải" or "Chờ mạng", a failure shown, the photos button enabled), so a flaky signal flips its line. That is accepted:
/// the download itself follows `raw`.
@Observable final class NetworkStatus {
    /// the path as it is now
    private(set) var raw = true
    /// `raw` once it has held 2 s
    private(set) var online = true
    /// the path costs money (cellular, a Personal Hotspot): Tải tất cả asks first
    private(set) var expensive = false
    private let monitor = NWPathMonitor()
    @ObservationIgnored private var steady: SteadyValue<Bool>?

    init() {
        steady = SteadyValue(delay: .seconds(2)) { [weak self] ok in
            guard let self, online != ok else { return }
            online = ok
        }
        // runs on the monitor's queue, at start and on every change: nonisolated, see MotionService
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let ok = path.status == .satisfied
            let expensive = path.isExpensive
            Task { @MainActor in self?.took(ok, expensive: expensive) }
        }
        monitor.start(queue: DispatchQueue(label: "jp27.network"))
    }

    /// Written only when it changes: views redraw with every write. The path says the same again when only its
    /// interface changes.
    private func took(_ ok: Bool, expensive: Bool) {
        if raw != ok { raw = ok }
        if self.expensive != expensive { self.expensive = expensive }
        steady?.report(ok)
    }
}

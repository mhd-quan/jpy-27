import CoreLocation
import Foundation
import Observation
import TripKit

/// Where you are, kept as cheap as the moment allows:
/// - foreground: a live stream of positions;
/// - on a ride or racing a departure: the same stream kept alive under the lock screen;
/// - otherwise: only visits (CLVisit) and up to 20 geofences (CLMonitor), which wake the app.
@Observable final class LocationService: NSObject {
    private let manager = CLLocationManager()

    private(set) var position: Coordinate?
    private(set) var altitude: Double?
    private(set) var horizontalAccuracy: Double?
    /// km/h over ground, when moving
    private(set) var speedKmh: Double?
    /// true heading, degrees
    private(set) var heading: Double?
    private(set) var authorization: CLAuthorizationStatus

    var onUpdate: ((Coordinate) -> Void)?
    var onVisit: ((VisitRecord) -> Void)?
    var onFence: ((Fence, Bool) -> Void)?

    private var liveTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var monitor: CLMonitor?
    private var monitorTask: Task<Void, Never>?
    private var lastTrace: (at: Date, at2: Coordinate)?

    var isAlways: Bool { authorization == .authorizedAlways }
    var isAllowed: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.headingFilter = 3
        if manager.authorizationStatus == .authorizedAlways {
            manager.startMonitoringVisits()
            manager.startMonitoringSignificantLocationChanges()
        }
        monitorTask = Task { [weak self] in await self?.watchFences() }
    }

    // MARK: Permission

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    /// Asked for only when a feature needs it (geofences, journal, rides under the lock screen).
    func requestAlways() {
        manager.requestAlwaysAuthorization()
    }

    // MARK: Live positions

    func resume(for model: AppModel) {
        if authorization == .notDetermined { requestWhenInUse() }
        guard isAllowed else { return }
        startLive(background: model.activeRide != nil)
        manager.startUpdatingHeading()
    }

    /// Stream positions; with `background`, keep streaming after the screen locks (a ride, a race to a train).
    func startLive(background: Bool) {
        if liveTask == nil {
            liveTask = Task { [weak self] in
                do {
                    for try await update in CLLocationUpdate.liveUpdates(.otherNavigation) {
                        guard let self else { return }
                        if let loc = update.location { self.accept(loc) }
                    }
                } catch {}
            }
        }
        if background, backgroundSession == nil {
            backgroundSession = CLBackgroundActivitySession()
        } else if !background {
            backgroundSession?.invalidate()
            backgroundSession = nil
        }
    }

    func stopLive() {
        liveTask?.cancel()
        liveTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        manager.stopUpdatingHeading()
    }

    private func accept(_ loc: CLLocation) {
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 200 else { return }
        let p = Coordinate(loc.coordinate.latitude, loc.coordinate.longitude)
        position = p
        altitude = loc.verticalAccuracy >= 0 ? loc.altitude : altitude
        horizontalAccuracy = loc.horizontalAccuracy
        speedKmh = loc.speed >= 0 ? loc.speed * 3.6 : nil
        onUpdate?(p)
    }

    /// One sample per ~80 m or five minutes for the journal's heatmap.
    func shouldTrace(_ p: Coordinate) -> Bool {
        let now = Date()
        if let last = lastTrace, Geo.km(last.at2, p) < 0.08, now.timeIntervalSince(last.at) < 300 { return false }
        lastTrace = (now, p)
        return true
    }

    // MARK: Geofences

    private static let fenceKey = "fences"

    /// Rotate the watched circles to what is next. Called when the day, cursor or plan changes.
    func updateFences(model: AppModel) {
        let wanted: [Fence]
        if let today = model.today, isAlways {
            wanted = FencePlanner(store: model.store).fences(today: today, cursor: model.cursor, tomorrow: model.tomorrow)
        } else {
            wanted = []
        }
        // remember what each circle means, for a relaunch straight into a fence event
        let info = Dictionary(uniqueKeysWithValues: wanted.map { ($0.id, "\($0.kind.rawValue)|\($0.placeID)|\($0.day)|\($0.index.map(String.init) ?? "")|\($0.center.lat)|\($0.center.lng)|\($0.radius)") })
        Shared.defaults.set(info, forKey: Self.fenceKey)
        Task { await apply(wanted) }
    }

    private func apply(_ wanted: [Fence]) async {
        guard let monitor else { return }
        let ids = Set(wanted.map(\.id))
        let current = await monitor.identifiers
        for id in current where !ids.contains(id) {
            await monitor.remove(id)
        }
        for f in wanted where !current.contains(f.id) {
            let condition = CLMonitor.CircularGeographicCondition(center: CLLocationCoordinate2D(latitude: f.center.lat, longitude: f.center.lng), radius: f.radius)
            await monitor.add(condition, identifier: f.id, assuming: .unsatisfied)
        }
    }

    private func watchFences() async {
        let m = await CLMonitor("jp27.fences")
        monitor = m
        do {
            for try await event in await m.events {
                guard let fence = Self.fence(event.identifier) else { continue }
                switch event.state {
                case .satisfied: onFence?(fence, true)
                case .unsatisfied: onFence?(fence, false)
                default: break
                }
            }
        } catch {}
    }

    private static func fence(_ id: String) -> Fence? {
        guard let s = (Shared.defaults.dictionary(forKey: fenceKey) as? [String: String])?[id] else { return nil }
        let f = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 7, let kind = Fence.Kind(rawValue: f[0]), let lat = Double(f[4]), let lng = Double(f[5]), let r = Double(f[6]) else { return nil }
        return Fence(placeID: f[1], kind: kind, center: Coordinate(lat, lng), radius: r, day: f[2], index: Int(f[3]))
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedAlways {
                self.manager.startMonitoringVisits()
                self.manager.startMonitoringSignificantLocationChanges()
                AppModel.shared.rescheduleAll()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let arrival = visit.arrivalDate == .distantPast ? Date() : visit.arrivalDate
        let departure = visit.departureDate == .distantFuture ? nil : visit.departureDate
        let record = VisitRecord(arrival: arrival, departure: departure, coordinate: Coordinate(visit.coordinate.latitude, visit.coordinate.longitude))
        Task { @MainActor in self.onVisit?(record) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // significant changes while in the background: refresh reminders and fences
        guard let last = locations.last else { return }
        let c = Coordinate(last.coordinate.latitude, last.coordinate.longitude)
        Task { @MainActor in
            self.position = c
            self.onUpdate?(c)
            AppModel.shared.rescheduleAll()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = h }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

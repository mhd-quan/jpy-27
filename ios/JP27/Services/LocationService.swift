import CoreLocation
import Foundation
import Observation
import TripKit

/// Where you are, kept as cheap as the moment allows:
/// - foreground: a live stream of positions;
/// - on a ride or racing a departure: the same stream kept alive under the lock screen;
/// - otherwise: only visits (CLVisit) and up to 20 geofences (region monitoring), which wake the app.
@Observable final class LocationService: NSObject {
    /// Made in `start()`, from application(_:didFinishLaunchingWithOptions:). AppModel is built with
    /// the App struct, before UIApplicationMain has registered the app with the system, and
    /// CoreLocation started that early misbehaves: CLMonitor asserted in its init on every relaunch.
    @ObservationIgnored private var manager: CLLocationManager?

    private(set) var position: Coordinate?
    private(set) var altitude: Double?
    private(set) var horizontalAccuracy: Double?
    /// km/h over ground, when moving
    private(set) var speedKmh: Double?
    /// true heading, degrees
    private(set) var heading: Double?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    var onUpdate: ((Coordinate) -> Void)?
    var onVisit: ((VisitRecord) -> Void)?
    var onFence: ((Fence, Bool) -> Void)?
    /// the permission changed: re-plan what depends on it (fences only exist with Always)
    var onAuthorizationChange: (() -> Void)?
    /// a significant move in the background: worth re-planning reminders and fences
    var onMoved: (() -> Void)?

    private var liveTask: Task<Void, Never>?
    private var backgroundSession: CLBackgroundActivitySession?
    private var lastTrace: (at: Date, at2: Coordinate)?
    /// where and when the last background move re-planned, to keep that cheap
    private var lastMoved: (at: Date, position: Coordinate)?

    var isAlways: Bool { authorization == .authorizedAlways }
    var isAllowed: Bool { authorization == .authorizedAlways || authorization == .authorizedWhenInUse }

    /// Once, at launch (foreground or a background relaunch for a visit or a fence): the manager
    /// and its delegate must exist then for the event that woke the app to be delivered.
    func start() {
        guard manager == nil else { return }
        let m = CLLocationManager()
        manager = m
        m.delegate = self
        m.headingFilter = 3
        authorization = m.authorizationStatus
        if authorization == .authorizedAlways { startBackgroundWatch() }
    }

    /// Visits and significant changes: both wake a suspended or terminated app, at little cost.
    /// Idempotent; called at launch and when Always is granted.
    private func startBackgroundWatch() {
        manager?.startMonitoringVisits()
        manager?.startMonitoringSignificantLocationChanges()
    }

    // MARK: Permission

    func requestWhenInUse() {
        manager?.requestWhenInUseAuthorization()
    }

    /// Asked for only when a feature needs it (geofences, journal, rides under the lock screen).
    func requestAlways() {
        manager?.requestAlwaysAuthorization()
    }

    // MARK: Live positions

    func resume(for model: AppModel) {
        if authorization == .notDetermined { requestWhenInUse() }
        guard isAllowed else { return }
        startLive(background: model.activeRide != nil)
        manager?.startUpdatingHeading()
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
        manager?.stopUpdatingHeading()
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
    private static let enteredKey = "fences.entered"
    /// an entry into the same circle within this long is the same arrival (GPS jitter at the edge)
    private static let reentry: TimeInterval = 20 * 60

    /// Rotate the watched circles to what is next. Called when the day, cursor or plan changes.
    ///
    /// Region monitoring on the app's one location manager, not `CLMonitor`: it is synchronous, so
    /// two updates in a row cannot interleave and leave more than 20 circles registered, it needs
    /// no second object made at launch (the monitor's init was what failed every relaunch once
    /// Always was on), and iOS relaunches the app into `didEnterRegion` the same way.
    func updateFences(model: AppModel) {
        guard let manager else { return }
        let wanted: [Fence]
        if let today = model.today, isAlways {
            wanted = FencePlanner(store: model.store).fences(today: today, cursor: model.cursor, tomorrow: model.tomorrow)
        } else {
            wanted = []
        }
        // remember what each circle means, for a relaunch straight into a fence event
        var info: [String: String] = [:]
        for f in wanted {
            info[f.id] = "\(f.kind.rawValue)|\(f.placeID)|\(f.day)|\(f.index.map(String.init) ?? "")|\(f.center.lat)|\(f.center.lng)|\(f.radius)"
        }
        Shared.defaults.set(info, forKey: Self.fenceKey)

        let ids = Set(wanted.map(\.id))
        let current = manager.monitoredRegions
        for region in current where !ids.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        let have = Set(current.map(\.identifier))
        guard isAlways, CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }
        for f in wanted where !have.contains(f.id) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: f.center.lat, longitude: f.center.lng),
                radius: min(f.radius, manager.maximumRegionMonitoringDistance),
                identifier: f.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
    }

    /// An entry iOS reported, at most once per circle within `reentry`: walking along the edge of a
    /// circle makes iOS report the same arrival again and again.
    fileprivate func entered(_ id: String) {
        guard let fence = Self.fence(id) else { return }
        let now = Date()
        var last = Shared.defaults.dictionary(forKey: Self.enteredKey) as? [String: Double] ?? [:]
        if let t = last[id], now.timeIntervalSince1970 - t < Self.reentry { return }
        last[id] = now.timeIntervalSince1970
        // forget arrivals older than a day, so the record stays small
        last = last.filter { now.timeIntervalSince1970 - $0.value < 86400 }
        Shared.defaults.set(last, forKey: Self.enteredKey)
        onFence?(fence, true)
    }

    private static func fence(_ id: String) -> Fence? {
        guard let s = (Shared.defaults.dictionary(forKey: fenceKey) as? [String: String])?[id] else { return nil }
        let f = s.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 7, let kind = Fence.Kind(rawValue: f[0]), let lat = Double(f[4]), let lng = Double(f[5]), let r = Double(f[6]) else { return nil }
        return Fence(placeID: f[1], kind: kind, center: Coordinate(lat, lng), radius: r, day: f[2], index: Int(f[3]))
    }

    /// A significant change in the background re-plans reminders and fences, but only after a real
    /// move (500 m) or ten minutes: iOS can deliver these in bursts.
    fileprivate func moved(to c: Coordinate) {
        let now = Date()
        if let last = lastMoved, Geo.km(last.position, c) < 0.5, now.timeIntervalSince(last.at) < 600 { return }
        lastMoved = (now, c)
        onMoved?()
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // called once at launch with the status already known: act on a change only
            guard status != self.authorization else { return }
            self.authorization = status
            if status == .authorizedAlways { self.startBackgroundWatch() }
            self.onAuthorizationChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.entered(id) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: any Error) {}

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
            self.moved(to: c)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in self.heading = h }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

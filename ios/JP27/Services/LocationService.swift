import CoreLocation
import Foundation
import Observation
import TripKit

/// Where you are, kept as cheap as the moment allows (`follow`):
/// - on a ride: a navigation-grade stream, kept alive under the lock screen;
/// - on a trip day, on screen: an ordinary stream;
/// - before or after the trip, on screen: one position each time the app opens, for the distances
///   the screens show (the map draws its own dot);
/// - otherwise: only visits (CLVisit), significant changes and up to 20 geofences (region
///   monitoring), which wake the app; visits and significant changes only near the trip
///   (`BackgroundWatch`).
@Observable final class LocationService: NSObject {
    /// Made in `start()`, from application(_:didFinishLaunchingWithOptions:). AppModel is built with
    /// the App struct, before UIApplicationMain has registered the app with the system, and
    /// CoreLocation started that early misbehaves: CLMonitor asserted in its init on every relaunch.
    @ObservationIgnored private var manager: CLLocationManager?

    /// Where you are, for what the screens show. It moves once you have moved 8 m: GPS wanders a
    /// few metres a second while you stand still, and every view that shows a distance would redraw
    /// with it. Each fix still goes to `onUpdate`, and the map draws its own dot.
    private(set) var position: Coordinate?
    /// whole metres, for the same reason
    private(set) var altitude: Double?
    /// read, not drawn: no view redraws when they change
    @ObservationIgnored private(set) var horizontalAccuracy: Double?
    /// km/h over ground, when moving
    @ObservationIgnored private(set) var speedKmh: Double?
    /// when the latest fix was taken (its own time, not when it was handled): a followed ride measures
    /// the train's pace with it (`RideLiveService`)
    @ObservationIgnored private(set) var fixedAt: Date?
    /// true heading, degrees; streamed only while a compass is on screen (`watchHeading`)
    private(set) var heading: Double?
    @ObservationIgnored private var compasses = 0
    private(set) var authorization: CLAuthorizationStatus = .notDetermined

    var onUpdate: ((Coordinate) -> Void)?
    var onVisit: ((VisitRecord) -> Void)?
    var onFence: ((Fence, Bool) -> Void)?
    /// the permission changed: re-plan what depends on it (fences only exist with Always)
    var onAuthorizationChange: (() -> Void)?
    /// a significant move while the app is in the background, only: worth re-planning reminders and
    /// fences. Never the position `requestLocation` finds on opening the app, whose return to the app
    /// has re-planned already
    var onMoved: (() -> Void)?
    /// what is to be watched in the background now (`AppModel.backgroundWatch`), asked each time
    /// the watch is applied
    var backgroundWatch: (() -> BackgroundWatch)?

    private var liveTask: Task<Void, Never>?
    /// the stream running is the navigation-grade one (a ride)
    private var liveNavigation = false
    /// the app is on screen (between `resume` and `pause`)
    private var foreground = false
    private var backgroundSession: CLBackgroundActivitySession?
    private var lastTrace: (at: Date, at2: Coordinate)?
    /// where and when the last background move re-planned, to keep that cheap
    private var lastMoved: (at: Date, position: Coordinate)?
    /// what this launch has started or stopped; nil until the first `applyBackgroundWatch`
    @ObservationIgnored private var watching: BackgroundWatch?

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
        applyBackgroundWatch()
    }

    /// Visits and significant changes, started or stopped as `backgroundWatch` says: both wake a
    /// suspended or terminated app, and both are left running by iOS from one launch to the next,
    /// so the first call of a launch starts or stops each of them, whatever an earlier build left
    /// on. After that only a change reaches Core Location. Called at launch, when the permission
    /// changes, and with every `AppModel.refresh` (the watch's edges are not the trip's days).
    func applyBackgroundWatch() {
        guard let manager else { return }
        let wanted = isAlways ? backgroundWatch?() ?? BackgroundWatch.off : BackgroundWatch.off
        let was = watching
        if was?.visits != wanted.visits {
            if wanted.visits { manager.startMonitoringVisits() } else { manager.stopMonitoringVisits() }
        }
        if was?.significantChanges != wanted.significantChanges {
            if wanted.significantChanges {
                manager.startMonitoringSignificantLocationChanges()
            } else {
                manager.stopMonitoringSignificantLocationChanges()
            }
        }
        watching = wanted
    }

    // MARK: Permission

    func requestWhenInUse() {
        manager?.requestWhenInUseAuthorization()
    }

    /// Asked for only when a feature needs it (geofences, marking stops, the journal, rides under the
    /// lock screen).
    func requestAlways() {
        manager?.requestAlwaysAuthorization()
    }

    // MARK: Live positions

    /// The app came on screen.
    func resume(for model: AppModel) {
        foreground = true
        if authorization == .notDetermined { requestWhenInUse() }
        guard isAllowed else { return }
        follow(model)
        if compasses > 0 { manager?.startUpdatingHeading() }
    }

    /// The app left the screen: nothing streams on, unless a ride is followed (its background
    /// session keeps the stream going under the lock screen).
    func pause(riding: Bool) {
        foreground = false
        if !riding { stopLive() }
        manager?.stopUpdatingHeading()
    }

    /// The stream the moment calls for. Called on resume, when a ride starts or ends, when a trip
    /// day begins or ends, and when the permission changes.
    func follow(_ model: AppModel) {
        guard isAllowed else { return }
        if model.activeRide != nil {
            startLive(background: true)
        } else if !foreground {
            stopLive()
        } else if model.today != nil {
            startLive(background: false)
        } else {
            // months before the trip: GPS kept on would only drain the battery
            stopLive()
            manager?.requestLocation()
        }
    }

    /// A compass came on screen or left it. The heading is streamed only while one is: it changes
    /// with every turn of the hand, and nothing else draws it.
    func watchHeading(_ on: Bool) {
        compasses = max(0, compasses + (on ? 1 : -1))
        if compasses > 0, isAllowed {
            manager?.startUpdatingHeading()
        } else if compasses == 0 {
            manager?.stopUpdatingHeading()
        }
    }

    /// Stream positions; with `background`, at navigation grade and kept streaming after the screen
    /// locks (a ride). Without, the ordinary stream: navigation grade keeps every sensor the phone
    /// has on, which a walk between stops has no use for.
    func startLive(background: Bool) {
        if liveTask == nil || liveNavigation != background {
            liveTask?.cancel()
            liveNavigation = background
            let configuration: CLLocationUpdate.LiveConfiguration = background ? .otherNavigation : .default
            liveTask = Task { [weak self] in
                do {
                    for try await update in CLLocationUpdate.liveUpdates(configuration) {
                        guard let self, !Task.isCancelled else { return }
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
    }

    private func accept(_ loc: CLLocation) {
        // one rule for every fix (`Presence.takes`): precise enough, and not older than the newest used
        // unless the phone's clock went back since (real clock, as fix times are)
        guard Presence.takes(accuracy: loc.horizontalAccuracy, at: loc.timestamp, newest: fixedAt, now: Date()) else { return }
        let p = Coordinate(loc.coordinate.latitude, loc.coordinate.longitude)
        fixedAt = loc.timestamp
        publish(p)
        if loc.verticalAccuracy >= 0, altitude != loc.altitude.rounded() { altitude = loc.altitude.rounded() }
        horizontalAccuracy = loc.horizontalAccuracy
        speedKmh = loc.speed >= 0 ? loc.speed * 3.6 : nil
        onUpdate?(p)
    }

    private func publish(_ p: Coordinate) {
        if let shown = position, Geo.km(shown, p) < 0.008 { return }
        position = p
    }

    /// One sample per ~80 m or five minutes for the journal's heatmap.
    func shouldTrace(_ p: Coordinate) -> Bool {
        let now = Date()
        if let last = lastTrace, Geo.km(last.at2, p) < 0.08, now.timeIntervalSince(last.at) < 300 { return false }
        lastTrace = (now, p)
        return true
    }

    // MARK: Geofences

    /// what each registered circle means (`Fence.archive`), for a relaunch straight into a crossing
    private static let fenceKey = "fences.v2"
    /// the same, as builds before item ids kept it (a string per circle, with an item index): removed
    private static let oldFenceKey = "fences"
    private static let enteredKey = "fences.entered"
    /// an entry into the same circle within this long is the same arrival (GPS jitter at the edge)
    private static let reentry: TimeInterval = 20 * 60

    /// Rotate the watched circles to what is next. Called when the cursor moves (`AppModel.refresh`)
    /// and with every reschedule: the day, a mark or a skip, the plan, the permission.
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
        // remember what each circle means, for a relaunch straight into a fence event (none kept when
        // it cannot be written: a circle then means nothing, rather than what it meant before)
        Shared.defaults.set(try? Fence.archive(wanted), forKey: Self.fenceKey)
        Shared.defaults.removeObject(forKey: Self.oldFenceKey)

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

    /// What the circle `id` means, as `updateFences` kept it; nil for a circle it does not know (one
    /// registered by a build before item ids, until the first `updateFences` replaces what it kept).
    private static func fence(_ id: String) -> Fence? {
        Shared.defaults.data(forKey: fenceKey).flatMap { Fence.unarchive($0)[id] }
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
            self.applyBackgroundWatch()
            self.onAuthorizationChange?()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier
        Task { @MainActor in self.entered(id) }
    }

    /// A circle registered: ask at once whether the phone is already in it. iOS reports only
    /// crossings, so a circle registered while standing inside it (the fences move on as the day
    /// does, often while already at the next stop) would never say so on its own.
    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        manager.requestState(for: region)
    }

    /// The answer to `requestState`, and also sent on every crossing next to `didEnterRegion`:
    /// `entered` takes each arrival once (`reentry`).
    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state == .inside else { return }
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

    /// Significant changes, and the one position `requestLocation` asks for on opening the app.
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let c = Coordinate(last.coordinate.latitude, last.coordinate.longitude)
        let at = last.timestamp
        let accuracy = last.horizontalAccuracy
        Task { @MainActor in
            // where you are only by the live stream's rule (`accept`): a significant change from the cell
            // towers, kilometres wide, or a fix delivered after a newer one, would put a followed ride's
            // pace, the projection and the journal at the wrong place or time
            if Presence.takes(accuracy: accuracy, at: at, newest: self.fixedAt, now: Date()) {
                self.fixedAt = at
                self.publish(c)
                self.onUpdate?(c)
            }
            // in the background only: refresh reminders and fences, a coarse fix included (the phone
            // moved, which is what a significant change says). On screen, the return to the app has just
            // done that, and this is usually `requestLocation`'s answer to it
            if !self.foreground { self.moved(to: c) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let h = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        Task { @MainActor in if self.heading != h { self.heading = h } }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {}
}

/// What the phone watches in the background (`LocationService.applyBackgroundWatch`), decided by
/// `JournalPolicy`.
nonisolated struct BackgroundWatch: Equatable, Sendable {
    /// visits (CLVisit): a stay marks its stop, and the journal keeps it
    var visits: Bool
    /// significant location changes: a move re-plans reminders and geofences
    var significantChanges: Bool

    static let off = BackgroundWatch(visits: false, significantChanges: false)
}

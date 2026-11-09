import Foundation
import Observation
import TripKit
import UIKit

/// What a download makes on the phone besides the map areas and the photos (`OfflineExtra`): each day's map picture,
/// the Fuji terrain pictures and the cloud forecasts, for use with no signal. Owned by `Downloads`, which judges the job
/// they belong to; the rules of the run are TripKit's (`ExtrasRun`).
///
/// - One part at a time, in the readiness list's order, each once no map area and no photo download is under way (the
///   photos first: a day's map follows its photograph's colour, read once the photograph is on the phone), and only
///   with the signal: without it, the part waits and goes on when it is back.
/// - The pictures are drawn only while the app is in front: MapKit answers only there, and a MapLibre picture drawn
///   while the app went away may come back blank. A drawing the app left, or the signal dropped during, is drawn
///   again. The forecasts go on away from the app, ahead of a picture waiting for it.
/// - Each picture is waited for on disk before the next is drawn (`drawForKeeping`); nothing is kept in memory. Each
///   part ends with a count of what is on disk then, which the job's end reads (`state`), and the names it drew are
///   kept from the launch trim (`offlineKeep`).
/// - A part asked for again while it runs (`ExtrasRun.again`) stops its pass at the next item and starts it again,
///   from what is missing, so a change the pass may have missed is seen.
/// - A stop (`pause`) holds every part of the run, those already over with it, until each is asked for again, and is
///   kept across a launch: the app ended before the job comes back with them stopped, none run against the stop.
@Observable final class OfflineExtras {
    private let maps: OfflineMaps
    private let photos: OfflinePhotos
    private let readiness: OfflineReadiness

    /// each part's phase and count
    private(set) var run = ExtrasRun()
    /// a part waits for the signal
    private(set) var waitingForNetwork = false
    /// a part waits for the app to be in front, to draw
    private(set) var waitingForApp = false
    /// the one loop that runs the parts
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// how many times the app went to the background: a picture drawn across one is drawn again
    @ObservationIgnored private var departures = 0
    /// the parts whose start the log has heard of and not their end: a pass started again says nothing new
    @ObservationIgnored private var started: Set<OfflineExtra> = []
    /// the parts stopped, kept across a launch
    private static let stoppedKey = "downloads.extrasPaused"
    /// a picture whose drawing the app left, or the signal dropped during, is drawn this many times at most in a pass
    private static let tries = 5

    /// Made inside `Downloads`, itself made inside `AppModel.shared`: nothing here reads `AppModel.shared` until later.
    init(maps: OfflineMaps, photos: OfflinePhotos, readiness: OfflineReadiness) {
        self.maps = maps
        self.photos = photos
        self.readiness = readiness
    }

    // MARK: What the job asks

    /// At launch, the extras of the job picked up again: waiting their turn, or stopped where the travellers stopped
    /// them before the app was ended, the ones that were over with them (`ExtrasRun.restore`). Nothing runs yet: `back`
    /// starts them, once the app is made.
    func restore(_ members: Set<OfflineExtra>) {
        run.restore(members, held: Self.stoppedBefore)
        Self.keepStopped(run.held)
    }

    /// A tap: these parts run (again), from what is missing; a stop kept for them is let go, for them only.
    func request(_ extras: Set<OfflineExtra>) {
        guard !extras.isEmpty else { return }
        run.request(extras)
        Self.keepStopped(run.held)
        go()
    }

    /// The system stopped the job away from the app, or the travellers did from its Live Activity: what waits and what
    /// runs stops where it is (a picture in flight ends first), and every part of the run, the ones over with it, stays
    /// stopped across a launch until it is asked for again.
    func pause() {
        let stopping = run.busy(Set(OfflineExtra.allCases))
        run.pause()
        Self.keepStopped(run.held)
        if stopping { AppLog.info(.offline, "Dừng phần tải", ["parts": Self.names(run.paused)]) }
    }

    /// The job is over: its parts are let go, and with them the stop kept.
    func forget() {
        run = ExtrasRun()
        started = []
        Self.keepStopped([])
    }

    /// The app went to the background.
    func left() {
        departures += 1
    }

    /// Back in the app, or at launch: the parts waiting their turn run.
    func back() {
        go()
    }

    /// What the job's end reads of a part (`ExtrasRun.state`).
    func state(_ extra: OfflineExtra) -> ExtraState? {
        run.state(extra)
    }

    func states(_ members: Set<OfflineExtra>) -> [OfflineExtra: ExtraState] {
        run.states(members)
    }

    /// Any of `members` waiting its turn or under way.
    func busy(_ members: Set<OfflineExtra>) -> Bool {
        run.busy(members)
    }

    func fraction(_ extra: OfflineExtra) -> Double {
        run.fraction(extra)
    }

    /// A part as the offline page's row shows it while it waits or runs (the page is open, so the app is in front):
    /// nil when it does neither, and the row says what the last look found. Waiting its turn again, it shows how far
    /// it had come.
    func live(_ extra: OfflineExtra) -> ReadyState? {
        switch run.phases[extra] {
        case .pending?:
            return .working(run.fraction(extra))
        case .running?:
            return waitingForNetwork ? .waitingForNetwork : .working(run.fraction(extra))
        case .finished?, .paused?, nil:
            return nil
        }
    }

    // MARK: The loop

    /// Starts the loop unless it runs, or nothing waits.
    private func go() {
        guard loop == nil, run.next != nil else { return }
        loop = Task { await self.work() }
    }

    /// The parts in turn until none waits. Nothing is awaited between the last look for a part and the loop's end, so
    /// a request in between finds no loop and starts one.
    private func work() async {
        while let extra = nextPart {
            guard run.begin(extra) else { break }
            let count = await pass(extra)
            run.end(extra, count)
            log(extra, count)
            // the rows and Settings' line follow
            await readiness.refresh()
        }
        loop = nil
    }

    /// The first part waiting its turn; away from the app, the forecasts first (they need neither the screen nor
    /// MapKit, and a Live Activity that does not move may be ended by the system).
    private var nextPart: OfflineExtra? {
        if UIApplication.shared.applicationState == .background, run.phases[.forecasts] == .pending { return .forecasts }
        return run.next
    }

    /// One line as a part starts, once its pass knows how many it has (nil: it cannot be counted). A pass started again
    /// (asked for again, or after stepping aside for the forecasts) is the same part going on: said once until its end.
    private func starting(_ extra: OfflineExtra, total: Int?) {
        guard started.insert(extra).inserted else { return }
        var fields = ["part": extra.rawValue]
        if let total { fields["total"] = "\(total)" }
        AppLog.info(.offline, "Bắt đầu phần tải", fields)
    }

    /// One line as a part that started ends, over or stopped; one stopped before its start was said is in the stop's.
    private func log(_ extra: OfflineExtra, _ count: ExtrasRun.Count?) {
        switch run.phases[extra] {
        case .finished?, .paused?:
            guard started.remove(extra) != nil else { return }
            var fields = ["part": extra.rawValue, "paused": "\(run.paused.contains(extra))"]
            if let count {
                fields["done"] = "\(count.done)"
                fields["total"] = "\(count.total)"
            }
            AppLog.info(.offline, "Xong phần tải", fields)
        case .pending?, .running?, nil:
            // its turn again (asked for during the pass, or stepping aside for the forecasts)
            break
        }
    }

    /// One pass of a part, once the maps and the photos are done: what is missing of it made, then what is on disk
    /// counted. Nil: it cannot be counted (a page to open first).
    private func pass(_ extra: OfflineExtra) async -> ExtrasRun.Count? {
        guard await turn(extra) else { return nil }
        switch extra {
        case .dayMaps: return await dayMaps()
        case .fuji: return await fuji()
        case .forecasts: return await forecasts()
        }
    }

    /// The part runs on: not stopped, nor asked for again (its next pass starts from what is missing).
    private func goingOn(_ extra: OfflineExtra) -> Bool {
        guard case .running? = run.phases[extra] else { return false }
        return !run.again.contains(extra)
    }

    /// Waits for the map areas and the photos: they go first (at a launch, once the packs are read, so an area picked
    /// up again is seen). False when the part was stopped meanwhile.
    private func turn(_ extra: OfflineExtra) async -> Bool {
        while goingOn(extra) {
            let mapsDone = (maps.ready || maps.requests.isEmpty) && !maps.phases.values.contains(where: \.isUnderWay)
            if mapsDone, !photos.running { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    /// Waits for the signal and, to draw, for the app in front; one line in the log for each wait. False when the part
    /// was stopped meanwhile, or steps aside for the forecasts away from the app (its next pass goes on after them).
    private func ready(_ extra: OfflineExtra, draws: Bool) async -> Bool {
        var said = (network: false, app: false)
        defer { waiting(network: false, app: false) }
        while goingOn(extra) {
            let online = AppModel.shared.network.raw
            let front = !draws || UIApplication.shared.applicationState != .background
            if online && front { return true }
            if online, !front, run.phases[.forecasts] == .pending {
                run.request([extra])
                return false
            }
            if !online, !said.network {
                said.network = true
                AppLog.info(.offline, "Chờ mạng để tải tiếp", ["part": extra.rawValue])
            }
            if online, !front, !said.app {
                said.app = true
                AppLog.info(.offline, "Chờ mở app để vẽ tiếp", ["part": extra.rawValue])
            }
            waiting(network: !online, app: online && !front)
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }

    /// Written only when it changes: the page redraws with every write.
    private func waiting(network: Bool, app: Bool) {
        if waitingForNetwork != network { waitingForNetwork = network }
        if waitingForApp != app { waitingForApp = app }
    }

    /// One picture drawn for keeps (`make`, given what must still hold once it is drawn). Drawn again when the app went
    /// away or the signal dropped during it, which is no fault of the picture's; one that fails with the app in front
    /// and the signal there all along is not tried again in this pass. False when it is not on disk.
    private func draw(_ extra: OfflineExtra, _ make: (_ keep: () -> Bool) async -> Bool) async -> Bool {
        for _ in 0 ..< Self.tries {
            guard await ready(extra, draws: true) else { return false }
            let left = departures
            let made = await make {
                departures == left && AppModel.shared.network.raw && UIApplication.shared.applicationState != .background
            }
            if made { return true }
            if departures == left, AppModel.shared.network.raw { return false }
        }
        return false
    }

    // MARK: The parts

    /// Every day, the alternative ones with them, its map's picture on disk at the page size the home measured last:
    /// the same days, and the same pictures, the readiness list counts.
    private func dayMaps() async -> ExtrasRun.Count? {
        guard let page = Prefetch.lastPage else {
            starting(.dayMaps, total: nil)
            AppLog.info(.offline, "Không đếm được phần tải", ["part": OfflineExtra.dayMaps.rawValue, "reason": "Mở trang Hôm nay một lần"])
            return nil
        }
        let model = AppModel.shared
        let requests = await dayRequests(model, page: page)
        MapSnapshots.offlineKeep = Set(requests.wanted.map(\.key.stem))
        starting(.dayMaps, total: requests.days)
        if run.progress(.dayMaps) == nil { run.counted(.dayMaps, done: 0, total: requests.days) }
        var done = 0
        for request in requests.wanted {
            guard goingOn(.dayMaps) else { break }
            if await MapSnapshots.shared.isOnDisk(request) {
                done += 1
            } else if await draw(.dayMaps, { keep in await MapSnapshots.shared.drawForKeeping(request, keep: keep) }) {
                done += 1
            }
            run.counted(.dayMaps, done: done, total: requests.days)
        }
        // counted again from the disk: a new page size or tile build renames them, a page drawing the same frame at
        // another size prunes one
        let now = await dayRequests(model, page: Prefetch.lastPage ?? page)
        MapSnapshots.offlineKeep = Set(now.wanted.map(\.key.stem))
        var onDisk = 0
        for request in now.wanted {
            if await MapSnapshots.shared.isOnDisk(request) { onDisk += 1 }
        }
        return ExtrasRun.Count(done: onDisk, total: now.days)
    }

    /// The day maps' pictures and how many days there are. A day whose photograph's colour is not known yet has it
    /// read from the phone first (nothing is downloaded for it); one still unknown has no picture to draw, and counts
    /// as missing.
    private func dayRequests(_ model: AppModel, page: Prefetch.Page) async -> (wanted: [MapSnapshots.Request], days: Int) {
        let store = model.store
        var seen = Set<String>()
        let days = (store.trip.days + store.trip.altDays).filter { seen.insert($0.key).inserted }
        var wanted: [MapSnapshots.Request] = []
        for day in days {
            let photo = HomePicks.photo(for: day, store: store)
            if let photo, PhotoCache.knownTone(photo) == nil { _ = await PhotoCache.shared.tone(photo) }
            if let request = await Prefetch.dayMapRequest(day, photo: photo, model: model, page: page) { wanted.append(request) }
        }
        return (wanted, days.count)
    }

    /// Every area hero and viewpoint card, in the schemes each is shown in, at the sizes kept (`wanted`).
    private func fuji() async -> ExtrasRun.Count? {
        let model = AppModel.shared
        let requests: [FujiTerrainPictures.Request]
        switch FujiTerrainPictures.wanted(guide: model.guide.fuji, store: model.store) {
        case .needs(let slot):
            starting(.fuji, total: nil)
            AppLog.info(.offline, "Không đếm được phần tải", ["part": OfflineExtra.fuji.rawValue, "reason": slot.setup])
            return nil
        case .pictures(let wanted):
            requests = wanted
        }
        FujiTerrainPictures.offlineKeep = Set(requests.map(\.stem))
        starting(.fuji, total: requests.count)
        if run.progress(.fuji) == nil { run.counted(.fuji, done: 0, total: requests.count) }
        var done = 0
        for request in requests {
            guard goingOn(.fuji) else { break }
            if await FujiTerrainPictures.shared.isOnDisk(request) {
                done += 1
            } else if await draw(.fuji, { keep in await FujiTerrainPictures.shared.drawForKeeping(request, keep: keep) }) {
                done += 1
            }
            run.counted(.fuji, done: done, total: requests.count)
        }
        // counted again from the disk, against the pictures wanted now: a size kept during the pass renames them
        guard case .pictures(let now) = FujiTerrainPictures.wanted(guide: model.guide.fuji, store: model.store) else { return nil }
        FujiTerrainPictures.offlineKeep = Set(now.map(\.stem))
        var onDisk = 0
        for request in now {
            if await FujiTerrainPictures.shared.isOnDisk(request) { onDisk += 1 }
        }
        return ExtrasRun.Count(done: onDisk, total: now.count)
    }

    /// The summit's forecast and every viewpoint's, under the keys and at the places the views ask them, each refreshed
    /// by the service's own rule (older than an hour); then how many are fresh by the real clock (`Readiness`), never
    /// the rehearsal's.
    private func forecasts() async -> ExtrasRun.Count? {
        let model = AppModel.shared
        let keys: [(key: String, at: Coordinate)] = [("summit", FujiSight.summit)] + model.guide.fuji.spots.map { ($0.id, Coordinate($0.lat, $0.lng)) }
        starting(.forecasts, total: keys.count)
        for (i, place) in keys.enumerated() {
            guard await ready(.forecasts, draws: false) else { break }
            _ = await model.forecasts.hours(place.key, at: place.at, online: model.network.raw)
            run.counted(.forecasts, done: i + 1, total: keys.count)
        }
        var fetched: [Date?] = []
        for place in keys { fetched.append(await model.forecasts.fetched(place.key)) }
        let fresh: Int
        switch Readiness.forecasts(fetched: fetched, now: Date()) {
        case .missing(let done?, _): fresh = done
        case .ready: fresh = keys.count
        case .missing, .working, .waitingForNetwork, .failed, .unsupported, .needsSetup: fresh = 0
        }
        return ExtrasRun.Count(done: fresh, total: keys.count)
    }

    // MARK: The stop kept

    private static var stoppedBefore: Set<OfflineExtra> {
        Set((Shared.defaults.stringArray(forKey: stoppedKey) ?? []).compactMap(OfflineExtra.init(rawValue:)))
    }

    private static func keepStopped(_ extras: Set<OfflineExtra>) {
        if extras.isEmpty {
            Shared.defaults.removeObject(forKey: stoppedKey)
        } else {
            Shared.defaults.set(extras.map(\.rawValue).sorted(), forKey: stoppedKey)
        }
    }

    /// raw names in the list's order, for the log
    static func names(_ extras: Set<OfflineExtra>) -> String {
        OfflineExtra.allCases.filter(extras.contains).map(\.rawValue).joined(separator: ",")
    }
}

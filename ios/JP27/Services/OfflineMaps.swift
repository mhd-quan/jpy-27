import BackgroundTasks
import Foundation
import MapLibre
import Observation
import QuartzCore
import TripKit
import UIKit

/// The basemap and its offline packs. The style is the site's own (src/lib/mapStyle.ts, exported to
/// public/map/), on OpenFreeMap vector tiles; packs cover each area of the trip so the map works
/// with no signal. Tiles are shared between styles, so the dark style reads the same packs.
///
/// A pack holds the tiles of one build: each is tagged with the tile URLs it was downloaded for.
/// When the map moves to another build (`usesCurrentTiles`), the packs of the old one no longer
/// match what the map asks for; they are `stale`, no longer counted as downloaded, and the app
/// says so once (`needsReload`) so they are downloaded again while there is still Wi-Fi.
@Observable final class OfflineMaps: NSObject {
    nonisolated struct Area: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let sw: Coordinate
        let ne: Coordinate
    }

    /// Bundled copy, used by the map view: no network needed to read the style itself. If the tile
    /// build it pins has gone, the same style on OpenFreeMap's current build instead.
    static func style(dark: Bool) -> URL {
        let bundled = Bundle.main.url(forResource: dark ? "jp27-dark" : "jp27-light", withExtension: "json", subdirectory: "map")
            ?? remoteStyle(dark: dark)
        guard usesCurrentTiles, let current = currentTilesStyle(from: bundled, dark: dark) else { return bundled }
        return current
    }

    // MARK: Pinned tiles

    /// The tiles the map reads now: the pinned build's URL template, or "current".
    static var tilesNow: String {
        usesCurrentTiles ? "current" : pinned
    }

    /// The bundled style's tile template, read once (every pack report asks).
    private static let pinned: String =
        Bundle.main.url(forResource: "jp27-light", withExtension: "json", subdirectory: "map").flatMap(pinnedTiles(in:)) ?? "pinned"

    /// The style pins one OpenFreeMap build, so the offline packs keep matching its tile URLs.
    /// OpenFreeMap answers any build path today, but nothing promises it still will in October
    /// 2027: once per launch, when online, the pinned build is asked for its first tile, and if it
    /// answers 404 the maps read OpenFreeMap's current build (its TileJSON) until it answers again.
    /// Offline nothing is asked and nothing changes, so the packs keep working.
    static let tilesChanged = Notification.Name("JP27.tilesChanged")
    private static let currentTilesKey = "map.currentTiles"
    private static let currentTileJSON = "https://tiles.openfreemap.org/planet"

    static var usesCurrentTiles: Bool { Shared.defaults.bool(forKey: currentTilesKey) }

    static func checkPinnedTiles() async {
        guard let bundled = Bundle.main.url(forResource: "jp27-light", withExtension: "json", subdirectory: "map"),
              let template = pinnedTiles(in: bundled),
              let url = URL(string: template.replacingOccurrences(of: "{z}/{x}/{y}", with: "0/0/0"))
        else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        // no answer (offline, a timeout) says nothing about the build
        guard let (_, response) = try? await URLSession.shared.data(for: request), let http = response as? HTTPURLResponse else { return }
        let gone = http.statusCode == 404 || http.statusCode == 410
        guard gone != usesCurrentTiles, gone || http.statusCode == 200 else { return }
        Shared.defaults.set(gone, forKey: currentTilesKey)
        NotificationCenter.default.post(name: tilesChanged, object: nil)
    }

    /// Reads a file and parses it: needs no actor. Left on the main actor (the module's default),
    /// it could not be handed as a function to `flatMap` in `pinned`'s initializer, which runs on none.
    private nonisolated static func pinnedTiles(in style: URL) -> String? {
        guard let data = try? Data(contentsOf: style),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let omt = (json["sources"] as? [String: Any])?["omt"] as? [String: Any]
        else { return nil }
        return (omt["tiles"] as? [String])?.first
    }

    /// The bundled style with its tile source pointed at the TileJSON that always names the current
    /// build, written next to the caches.
    private static func currentTilesStyle(from bundled: URL, dark: Bool) -> URL? {
        guard bundled.isFileURL, let data = try? Data(contentsOf: bundled),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var sources = json["sources"] as? [String: Any],
              var omt = sources["omt"] as? [String: Any]
        else { return nil }
        omt["tiles"] = nil
        omt["minzoom"] = nil
        omt["maxzoom"] = nil
        omt["url"] = currentTileJSON
        sources["omt"] = omt
        json["sources"] = sources
        let out = URL.cachesDirectory.appending(path: "jp27-\(dark ? "dark" : "light")-current.json")
        guard let rewritten = try? JSONSerialization.data(withJSONObject: json),
              (try? rewritten.write(to: out, options: .atomic)) != nil
        else { return nil }
        return out
    }

    /// Served by the site, used for the packs (a pack downloads its style by URL): pinned to the
    /// bundled build, or on OpenFreeMap's current one.
    static func remoteStyle(dark: Bool, current: Bool = false) -> URL {
        URL(string: "https://jpy27.delphyra.tech/map/jp27-\(dark ? "dark" : "light")\(current ? "-current" : "").json")!
    }

    private(set) var areas: [Area] = []
    /// MapLibre has read its packs: until then nothing is known about any area, and nothing is downloaded twice
    private(set) var ready = false
    /// areas whose pack has not said yet how far it is (packs read from storage start unknown)
    private(set) var checking: Set<String> = []
    private(set) var progress: [String: Double] = [:]
    private(set) var bytes: [String: UInt64] = [:]
    private(set) var complete: Set<String> = []
    /// downloading now
    private(set) var running: Set<String> = []
    /// asked for and not finished, kept across launches: picked up again when the app opens
    private(set) var wanted: Set<String> = Set(Shared.defaults.stringArray(forKey: OfflineMaps.wantedKey) ?? [])
    /// the last error of a download under way, until it moves again (MapLibre tries again by itself)
    private(set) var problems: [String: String] = [:]
    /// areas downloaded for another tile build than the map reads now: useless offline until downloaded again
    private(set) var stale: Set<String> = []
    /// the packs just went stale: say so once, for the travellers to download again
    var needsReload = false

    var totalBytes: UInt64 { bytes.values.reduce(0, +) }
    /// asked for and not finished
    var pending: Set<String> { wanted.subtracting(complete) }

    /// How far these areas are, together (a finished one counts whole).
    func fraction(of ids: Set<String>) -> Double {
        guard !ids.isEmpty else { return 0 }
        return ids.reduce(0.0) { $0 + (complete.contains($1) ? 1 : progress[$1] ?? 0) } / Double(ids.count)
    }

    private static let wantedKey = "map.wanted"
    /// What a pack was made for, kept as its context.
    private nonisolated struct Tag: Codable, Equatable {
        let area: String
        /// the tile URL template of the build, or "current"
        let tiles: String
    }

    /// read once per pack: MapLibre reports progress for every tile, so nothing per report reads JSON
    @ObservationIgnored private var tags: [ObjectIdentifier: (context: Data, tag: Tag)] = [:]
    /// when each area last showed its progress: a few times a second is what a page can show
    @ObservationIgnored private var shown: [String: CFTimeInterval] = [:]
    /// packs being made, not in MapLibre's list yet
    @ObservationIgnored private var adding: Set<String> = []
    @ObservationIgnored private var watch: NSKeyValueObservation?
    /// `tilesNow`, read on `refresh` (the tile build changes rarely; packs report all the time).
    /// Empty until the packs are read, and no pack reports before that.
    @ObservationIgnored private var tilesNow = ""

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(packProgress(_:)), name: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(packError(_:)), name: NSNotification.Name.MLNOfflinePackError, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tilesMoved(_:)), name: Self.tilesChanged, object: nil)
    }

    /// One area per region of the plan, framed on its places with a margin.
    func configure(store: TripStore) {
        if areas.isEmpty {
            let names = ["tokyo": "Tokyo", "hakone": "Hakone", "kawaguchiko": "Kawaguchiko", "tokaido": "Shizuoka", "ise": "Ise", "toba": "Toba, Tōshijima", "shima": "Shima", "kyoto": "Kyoto, Uji", "nara": "Nara", "osaka": "Osaka, KIX"]
            let grouped = Dictionary(grouping: store.trip.places.filter { $0.role != "alt" || $0.area == "kawaguchiko" }, by: \.area)
            areas = names.compactMap { id, name in
                guard let pts = grouped[id]?.map(\.coordinate), let b = Geo.bounds(pts) else { return nil }
                let pad = 0.012
                return Area(id: id, name: name, sw: Coordinate(b.sw.lat - pad, b.sw.lng - pad), ne: Coordinate(b.ne.lat + pad, b.ne.lng + pad))
            }.sorted { $0.name < $1.name }
        }
        guard watch == nil else { return }
        // `packs` is nil until MapLibre has read its database, a moment after it is first asked;
        // it changes again whenever a pack is added or removed. The handler is @Sendable (on no
        // actor), and KVO calls it synchronously inside MapLibre's own add and remove, which this
        // object calls from `download`: so `refresh` runs on the next turn of the main actor, never
        // in the middle of a download it would start again.
        watch = MLNOfflineStorage.shared.observe(\.packs, options: [.initial]) { @Sendable [weak self] _, _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    func refresh() {
        guard let packs = MLNOfflineStorage.shared.packs else { return }
        ready = true
        tilesNow = Self.tilesNow
        let hadStale = !stale.isEmpty
        var found = Set<String>()
        var staleNow = Set<String>()
        var known: [ObjectIdentifier: (context: Data, tag: Tag)] = [:]
        for pack in packs where pack.state != .invalid {
            guard let tag = tag(of: pack) else { continue }
            known[ObjectIdentifier(pack)] = tags[ObjectIdentifier(pack)]
            if tag.tiles != tilesNow { staleNow.insert(tag.area); continue }
            found.insert(tag.area)
            if pack.state == .unknown {
                // a pack read from storage knows nothing of itself until asked
                checking.insert(tag.area)
                pack.requestProgress()
            }
            record(pack, tag: tag, force: true)
        }
        tags = known
        staleNow.subtract(found)
        if staleNow != stale { stale = staleNow }
        // areas whose pack went (removed, or replaced while stale)
        for id in Set(progress.keys).union(complete).union(running).union(checking).subtracting(found).subtracting(adding) {
            forget(id)
        }
        if !hadStale, !stale.isEmpty { needsReload = true }
        if stale.isEmpty { needsReload = false }
        // asked for before a relaunch and with no pack for the tiles the map reads now: made again
        for area in areas where wanted.contains(area.id) && !found.contains(area.id) && !adding.contains(area.id) {
            download(area)
        }
    }

    /// Downloads an area for the tiles the map reads now; a pack of the area made for other tiles goes.
    func download(_ area: Area) {
        want(area.id)
        problems[area.id] = nil
        // not read yet: picked up by `refresh` once MapLibre has its list, so no pack is made twice
        guard let all = MLNOfflineStorage.shared.packs else { return }
        let packs = all.filter { $0.state != .invalid && tag(of: $0)?.area == area.id }
        let now = Self.tilesNow
        if let existing = packs.first(where: { tag(of: $0)?.tiles == now }) {
            existing.resume()
            running.insert(area.id)
            return
        }
        for old in packs { MLNOfflineStorage.shared.removePack(old) { _ in } }
        stale.remove(area.id)
        let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: area.sw.lat, longitude: area.sw.lng),
                                         ne: CLLocationCoordinate2D(latitude: area.ne.lat, longitude: area.ne.lng))
        let style = Self.remoteStyle(dark: false, current: now == "current")
        let region = MLNTilePyramidOfflineRegion(styleURL: style, bounds: bounds, fromZoomLevel: 9, toZoomLevel: 16)
        let context = (try? JSONEncoder().encode(Tag(area: area.id, tiles: now))) ?? Data(area.id.utf8)
        adding.insert(area.id)
        let id = area.id
        // Swift imports an Objective-C completion handler as @Sendable, so this closure is on no
        // actor. MapLibre calls it on the main queue (MLNOfflineStorage.mm dispatches it there),
        // which `assumeIsolated` states and checks, as for the other MapLibre callbacks. Only plain
        // facts cross into the main actor: the pack (not Sendable) stays where MapLibre handed it,
        // and the main actor reads it from `packs` like every other pack, so `record` alone decides
        // to start it (as it does after a relaunch), and one paused or removed meanwhile waits.
        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { [weak self] pack, error in
            guard let self else { return }
            let made = pack != nil
            let failure = error?.localizedDescription
            MainActor.assumeIsolated {
                self.adding.remove(id)
                if made {
                    self.refresh()
                } else {
                    self.problems[id] = "Không tạo được vùng tải" + (failure.map { ": \($0)" } ?? "")
                    self.unwant(id)
                    self.running.remove(id)
                }
            }
        }
        progress[area.id] = 0
        bytes[area.id] = nil
        complete.remove(area.id)
        running.insert(area.id)
    }

    /// Every area not downloaded yet. Returns their ids.
    @discardableResult func downloadAll() -> Set<String> {
        let missing = areas.filter { !complete.contains($0.id) }
        for a in missing { download(a) }
        needsReload = false
        return Set(missing.map(\.id))
    }

    /// Stops an area where it is; "Tiếp tục" picks it up from there.
    func pause(_ id: String) {
        unwant(id)
        for pack in MLNOfflineStorage.shared.packs ?? [] where pack.state == .active && tag(of: pack)?.area == id {
            pack.suspend()
        }
        running.remove(id)
    }

    func pauseAll() {
        for id in pending { pause(id) }
    }

    func remove(_ area: Area) {
        unwant(area.id)
        for pack in MLNOfflineStorage.shared.packs ?? [] where pack.state != .invalid && tag(of: pack)?.area == area.id {
            MLNOfflineStorage.shared.removePack(pack) { _ in }
        }
        forget(area.id)
        stale.remove(area.id)
    }

    private func want(_ id: String) {
        guard !wanted.contains(id) else { return }
        wanted.insert(id)
        Shared.defaults.set(wanted.sorted(), forKey: Self.wantedKey)
    }

    private func unwant(_ id: String) {
        guard wanted.contains(id) else { return }
        wanted.remove(id)
        Shared.defaults.set(wanted.sorted(), forKey: Self.wantedKey)
    }

    private func forget(_ id: String) {
        progress[id] = nil
        bytes[id] = nil
        problems[id] = nil
        if complete.contains(id) { complete.remove(id) }
        if running.contains(id) { running.remove(id) }
        if checking.contains(id) { checking.remove(id) }
        shown[id] = nil
    }

    /// MapLibre posts pack progress on the main queue (MLNOfflinePack hops there before posting),
    /// so this stays on the main actor and the notification never crosses to it.
    @objc private func packProgress(_ note: Notification) {
        guard let pack = note.object as? MLNOfflinePack, pack.state != .invalid, let tag = tag(of: pack),
              tag.tiles == tilesNow else { return }
        record(pack, tag: tag)
    }

    /// A tile or the style failed (posted on the main queue too). MapLibre keeps trying; the area
    /// says why it is not moving until it moves again. A missing tile is ordinary (sea, no data).
    @objc private func packError(_ note: Notification) {
        guard let pack = note.object as? MLNOfflinePack, pack.state != .invalid, let tag = tag(of: pack),
              tag.tiles == tilesNow else { return }
        let error = note.userInfo?[MLNOfflinePackUserInfoKey.error.rawValue] as? NSError
        let text: String
        switch error?.code {
        case MLNErrorCode.notFound.rawValue: return
        case MLNErrorCode.connectionFailed.rawValue: text = "Không kết nối được, đang thử lại"
        case MLNErrorCode.badServerResponse.rawValue: text = "Máy chủ bản đồ đang lỗi, đang thử lại"
        default: text = "Lỗi tải, đang thử lại"
        }
        if problems[tag.area] != text { problems[tag.area] = text }
    }

    /// The map moved to another tile build (posted on the main queue by `checkPinnedTiles`).
    @objc private func tilesMoved(_ note: Notification) {
        refresh()
    }

    private func record(_ pack: MLNOfflinePack, tag: Tag, force: Bool = false) {
        let id = tag.area
        let state = pack.state
        // not known yet: `requestProgress` answers with a report
        guard state != .unknown else { return }
        let p = pack.progress
        let expected = p.countOfResourcesExpected
        let done = state == .complete
            || (expected > 0 && p.countOfResourcesCompleted >= expected && p.maximumResourcesExpected == expected)
        let active = state == .active && !done
        let changed = checking.contains(id) || done != complete.contains(id) || active != running.contains(id)
        // every tile reports; the page is told a few times a second, and at once when the state changes
        let now = CACurrentMediaTime()
        guard force || changed || now - (shown[id] ?? 0) >= 0.25 else { return }
        shown[id] = now
        if checking.contains(id) { checking.remove(id) }
        let fraction = done ? 1 : expected > 0 ? min(1, Double(p.countOfResourcesCompleted) / Double(expected)) : 0
        if fraction > (progress[id] ?? 0), problems[id] != nil { problems[id] = nil }
        if progress[id] != fraction { progress[id] = fraction }
        if bytes[id] != p.countOfBytesCompleted { bytes[id] = p.countOfBytesCompleted }
        if done {
            if !complete.contains(id) { complete.insert(id) }
            if running.contains(id) { running.remove(id) }
            if problems[id] != nil { problems[id] = nil }
            unwant(id)
        } else {
            if complete.contains(id) { complete.remove(id) }
            if state == .inactive, wanted.contains(id) {
                // asked for and not running: a pack just made (MapLibre hands it over inactive),
                // or one stopped by a relaunch (packs come back inactive). On.
                pack.resume()
                if !running.contains(id) { running.insert(id) }
            } else if active != running.contains(id) {
                if active { running.insert(id) } else { running.remove(id) }
            }
        }
    }

    /// The area and tile build a pack was made for. Packs from before they were tagged were made
    /// from the site's style, pinned to the bundled build.
    private func tag(of pack: MLNOfflinePack) -> Tag? {
        let key = ObjectIdentifier(pack)
        let context = pack.context
        if let hit = tags[key], hit.context == context { return hit.tag }
        let tag = (try? JSONDecoder().decode(Tag.self, from: context))
            ?? String(data: context, encoding: .utf8).map { Tag(area: $0, tiles: Self.pinned) }
        if let tag { tags[key] = (context, tag) }
        return tag
    }
}

// MARK: - Downloads that outlast the page

/// The trip's downloads (map areas, photos) belong to the app, not to the page that starts them:
/// they go on while the travellers use the rest of the app, the page shows where they are whenever
/// it is opened again, and what was asked for and not finished is picked up at the next launch.
///
/// Leaving the app: a download started by a tap runs as a continued processing task (iOS 26), which
/// the system shows as a Live Activity with its progress and a stop button, and lets run in the
/// background until it is done. The system grants one only for an explicit action, so a download
/// picked up at launch gets the usual half minute (`beginBackgroundTask`) instead.
@Observable final class Downloads {
    let maps = OfflineMaps()
    let photos = OfflinePhotos()

    /// the areas of the download under way, finished ones included, for one progress over all of it
    @ObservationIgnored private var job: Set<String> = []
    @ObservationIgnored private var photosInJob = false
    @ObservationIgnored private var task: BGContinuedProcessingTask?
    /// submitted, not started yet
    @ObservationIgnored private var asked = false
    @ObservationIgnored private var grace: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var shown = ""

    /// Something asked for is still downloading.
    var busy: Bool { !maps.pending.isEmpty || photos.running }

    /// How far the download under way is, 0…1: each area weighs one, the photos one more.
    var fraction: Double {
        let areas = job.union(maps.pending)
        var sum = maps.fraction(of: areas) * Double(areas.count)
        var weight = Double(areas.count)
        if photosInJob || photos.running {
            sum += photos.fraction
            weight += 1
        }
        return weight > 0 ? sum / weight : 0
    }

    // MARK: Taps

    func download(_ area: OfflineMaps.Area) {
        maps.download(area)
        job.insert(area.id)
        keep()
    }

    func downloadAllMaps() {
        job.formUnion(maps.downloadAll())
        keep()
    }

    func downloadPhotos() {
        photos.download()
        photosInJob = true
        keep()
    }

    // MARK: The app comes and goes

    /// Back in the app: what was picked up at launch is followed like the rest.
    func back() {
        endGrace()
        if busy { tick() }
    }

    /// Leaving the app: without a continued task, what still downloads gets the usual half minute.
    func leaving() {
        guard busy, task == nil, grace == .invalid else { return }
        grace = UIApplication.shared.beginBackgroundTask(withName: "Tải dữ liệu offline") {
            // called on the main thread, the time is up: MapLibre picks up where it was next time
            AppModel.shared.downloads.endGrace()
        }
        tick()
    }

    private func endGrace() {
        guard grace != .invalid else { return }
        UIApplication.shared.endBackgroundTask(grace)
        grace = .invalid
    }

    // MARK: The continued task

    /// After a tap: follow the download, and ask the system to let it finish in the background.
    private func keep() {
        tick()
        guard task == nil, !asked, let id = Self.identifier, Self.register(id) else { return }
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: Self.title, subtitle: subtitle)
        do {
            try BGTaskScheduler.shared.submit(request)
            asked = true
        } catch {
            // not granted now: the downloads still run while the app is open, and for half a minute after
        }
    }

    /// `<bundle id>.downloads`, listed in Info.plist (BGTaskSchedulerPermittedIdentifiers).
    private static var identifier: String? { Bundle.main.bundleIdentifier.map { $0 + ".downloads" } }
    private static let title = "Tải dữ liệu offline cho chuyến đi"
    private static var registered: Bool?

    /// Once per launch: the system ends an app that registers the same identifier twice. False when
    /// the identifier is not in Info.plist (a build made before it was added).
    private static func register(_ id: String) -> Bool {
        if let registered { return registered }
        let ok = listen(id)
        registered = ok
        return ok
    }

    /// The handler runs on a queue of the scheduler's, so it is built off the main actor and hops to it.
    private nonisolated static func listen(_ id: String) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: id, using: nil) { task in
            let handed = Handed(task: task)
            Task { @MainActor in AppModel.shared.downloads.run(handed.task) }
        }
    }

    private nonisolated struct Handed: @unchecked Sendable { let task: BGTask }

    private func run(_ started: BGTask) {
        asked = false
        guard let started = started as? BGContinuedProcessingTask else {
            started.setTaskCompleted(success: false)
            return
        }
        task = started
        started.progress.totalUnitCount = 1000
        // the system's queue again, the moment the task has to stop
        started.expirationHandler = { @Sendable in
            Task { @MainActor in AppModel.shared.downloads.expired() }
        }
        shown = ""
        tick()
        _ = report()
    }

    /// The system stopped the task, or the travellers did from its Live Activity. Away from the app
    /// the downloads pause where they are and say so ("Tiếp tục" picks them up); in it, they go on.
    private func expired() {
        guard let task else { return }
        if UIApplication.shared.applicationState == .background {
            maps.pauseAll()
            photos.pause()
        }
        task.setTaskCompleted(success: false)
        self.task = nil
    }

    /// About once a second while something downloads: the Live Activity's progress, and the end.
    private func tick() {
        guard ticking == nil else { return }
        ticking = Task {
            while report() {
                try? await Task.sleep(for: .seconds(1))
            }
            ticking = nil
        }
    }

    /// Returns whether to go on.
    private func report() -> Bool {
        guard busy else {
            finish()
            return false
        }
        if let task {
            let units = Int64(fraction * 1000)
            // the system reads a stuck bar as a stuck task: it only moves forward
            if units > task.progress.completedUnitCount { task.progress.completedUnitCount = units }
            let line = subtitle
            if line != shown {
                task.updateTitle(Self.title, subtitle: line)
                shown = line
            }
        }
        return true
    }

    private func finish() {
        if let task {
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.updateTitle(Self.title, subtitle: photos.failed > 0 ? "Xong, \(photos.failed) ảnh chưa tải được" : "Xong")
            task.setTaskCompleted(success: photos.failed == 0)
            self.task = nil
        } else if asked, let id = Self.identifier {
            // nothing left for a task still waiting its turn
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
            asked = false
        }
        endGrace()
        job = []
        photosInJob = false
    }

    /// "Bản đồ 3/10 vùng · Ảnh 120/180 · 42%"
    private var subtitle: String {
        var parts: [String] = []
        let areas = job.union(maps.pending)
        if !areas.isEmpty { parts.append("Bản đồ \(areas.filter(maps.complete.contains).count)/\(areas.count) vùng") }
        if photosInJob || photos.running { parts.append("Ảnh \(photos.saved)/\(photos.total)") }
        parts.append("\(Int(fraction * 100))%")
        return parts.joined(separator: " · ")
    }
}

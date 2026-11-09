import BackgroundTasks
import Foundation
import MapLibre
import Observation
import QuartzCore
import TripKit
import UIKit

/// The basemap and its offline packs. The style is the site's own (src/lib/mapStyle.ts, exported to
/// public/map/ and bundled), on OpenFreeMap vector tiles; packs cover each area of the trip, and the whole
/// route zoomed out, so the map works with no signal. Tiles are shared between styles, so the dark style
/// reads the same packs. A pack's style is the bundled one, which the app stores in MapLibre's database
/// under the URL the pack names (`PackStyle`): no site has to serve it.
///
/// A pack holds the tiles of one build, and is tagged with the build its style really held when it was
/// made (`PackTag`). Where each area is (`phases`) is decided in TripKit, from what MapLibre says of its
/// pack (`OfflineArea.phase`) and of its packs together (`OfflineArea.settle`). When the map moves to
/// another build (`mapBuild`), the packs of the old one no longer match what the map asks for: they are
/// stale, no longer counted as downloaded, and the app asks once per build (`needsReload`) for them to be
/// downloaded again while there is still Wi-Fi.
@Observable final class OfflineMaps: NSObject {
    nonisolated struct Area: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let sw: Coordinate
        let ne: Coordinate
        /// the zoom levels its pack holds: 9–16 for an area, 5–10 for the whole route
        let zoom: ClosedRange<Double>
    }

    /// Bundled copy, used by the map view: no network needed to read the style itself. If the tile
    /// build it pins has gone, the same style on OpenFreeMap's current build instead.
    static func style(dark: Bool) -> URL {
        let bundled = Bundle.main.url(forResource: dark ? "jp27-dark" : "jp27-light", withExtension: "json", subdirectory: "map")
            ?? remoteStyle(dark: dark)
        guard let template = currentTemplate, let current = currentTilesStyle(from: bundled, dark: dark, template: template) else { return bundled }
        return current
    }

    // MARK: The tile build

    /// The tile build the map reads: OpenFreeMap's current one while the pinned build is gone, else the
    /// one the bundled style pins.
    static var mapBuild: TileBuild {
        if let currentTemplate { return TileBuild(template: currentTemplate) }
        return pinned ?? TileBuild(template: "pinned")
    }

    /// The bundled style's tile build, and its name (`metadata["jp27:build"]`), which a pack of the pinned
    /// build names its style by (`PackStyle`). Read once, for both (every pack report asks).
    private nonisolated static let bundled: (build: TileBuild?, name: String?) = {
        let style = bundledStyle()
        return (style.flatMap { StyleInfo.build(style: $0) }, style.flatMap { StyleInfo.styleBuild(style: $0) })
    }()
    private static var pinned: TileBuild? { bundled.build }

    /// Reads a file: needs no actor. Left on the main actor (the module's default), it could not be
    /// called from `bundled`'s initializer, which runs on none.
    private nonisolated static func bundledStyle() -> Data? {
        Bundle.main.url(forResource: "jp27-light", withExtension: "json", subdirectory: "map").flatMap { try? Data(contentsOf: $0) }
    }

    /// The style pins one OpenFreeMap build, so the offline packs keep matching its tile URLs.
    /// OpenFreeMap answers any build path today, but nothing promises it still will in October
    /// 2027: once per launch, when online, the pinned build is asked for its first tile, and if it
    /// answers 404 the maps read the build OpenFreeMap's TileJSON names, asked again at each launch
    /// while the pinned one is gone, until it answers again. Offline nothing is asked and nothing
    /// changes, so the packs keep working.
    static let tilesChanged = Notification.Name("JP27.tilesChanged")
    private static let currentKey = "map.currentTemplate"
    private static let currentTileJSON = URL(string: "https://tiles.openfreemap.org/planet")!

    /// Set while the pinned build is gone: the tile template OpenFreeMap's TileJSON named at the last
    /// online launch. (Earlier builds kept a Bool, `map.currentTiles`, and let MapLibre read the TileJSON
    /// itself, so nothing knew the build; it is not read any more.)
    static var currentTemplate: String? { Shared.defaults.string(forKey: currentKey) }

    /// True once the server answered (whatever it said): the launch need not ask again. False with no
    /// answer (offline, a timeout), so the next return to the app asks.
    @discardableResult
    static func checkPinnedTiles() async -> Bool {
        guard let template = pinned?.template,
              let url = URL(string: template.replacingOccurrences(of: "{z}/{x}/{y}", with: "0/0/0"))
        else { return true }
        // no answer (offline, a timeout) says nothing about the build
        guard let status = await fetch(url, timeout: 10)?.status else { return false }
        guard status == 404 || status == 410 else {
            // there: the map reads it (another answer says nothing either way)
            if status == 200, currentTemplate != nil { move(to: nil) }
            return true
        }
        // gone: the build OpenFreeMap names now
        guard let answer = await fetch(currentTileJSON, timeout: 10), answer.status == 200,
              let current = StyleInfo.build(tileJSON: answer.data)
        else { return false }
        if current.template != currentTemplate { move(to: current.template) }
        return true
    }

    /// The map reads another build: the map views load their style again (`tilesChanged`), and the packs
    /// are looked at anew (`refresh`).
    private static func move(to template: String?) {
        if let template {
            Shared.defaults.set(template, forKey: currentKey)
        } else {
            Shared.defaults.removeObject(forKey: currentKey)
        }
        NotificationCenter.default.post(name: tilesChanged, object: nil)
    }

    /// A small file as it is served now (not from a cache: what the server says today). Nil with no answer.
    private static func fetch(_ url: URL, timeout: TimeInterval) async -> (status: Int, data: Data)? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse
        else { return nil }
        return (http.statusCode, data)
    }

    /// The bundled style on the current build (`StyleInfo.pointing`: its tiles, none of its `jp27:`
    /// metadata), written next to the caches.
    private static func currentTilesStyle(from bundled: URL, dark: Bool, template: String) -> URL? {
        guard bundled.isFileURL, let data = try? Data(contentsOf: bundled),
              let rewritten = StyleInfo.pointing(style: data, at: template)
        else { return nil }
        let out = URL.cachesDirectory.appending(path: "jp27-\(dark ? "dark" : "light")-current.json")
        guard (try? rewritten.write(to: out, options: .atomic)) != nil else { return nil }
        return out
    }

    /// Served by the site: a theme's style, pinned to the bundled build. Only for a bundle without its style
    /// (`style(dark:)`); the packs never ask the site.
    static func remoteStyle(dark: Bool) -> URL {
        URL(string: "https://jpy27.delphyra.tech/map/jp27-\(dark ? "dark" : "light").json")!
    }

    // MARK: The packs' style

    /// Kept until then and never asked again (`mustRevalidate: false`): nothing answers its URL.
    private static let packStyleExpiry = Date(timeIntervalSince1970: 1_893_456_000) // 2030-01-01 00:00 UTC
    private static let unstored = "Không nạp được style của bản đồ"

    /// The style a pack is made from, for the pinned build (`currentTemplate` nil) or OpenFreeMap's current
    /// one. Reads a file and parses JSON: off the main actor.
    @concurrent private nonisolated static func preparedStyle(currentTemplate: String?) async -> PackStyle.Prepared? {
        guard let data = bundledStyle() else { return nil }
        return PackStyle.prepare(bundled: data, pinnedName: bundled.name, currentTemplate: currentTemplate)
    }

    // MARK: The areas

    private(set) var areas: [Area] = []
    /// MapLibre has read its packs: until then nothing is known about any area, and nothing is downloaded twice
    private(set) var ready = false
    /// Where each area is; none: never asked for and no pack. An area asked for before this launch is
    /// `.requested` until its packs are read.
    private(set) var phases: [String: AreaPhase] = [:]
    /// how far each area got, 0…1, as last reported: a paused or waiting area shows where it stopped
    private(set) var progress: [String: Double] = [:]
    private(set) var bytes: [String: UInt64] = [:]
    /// the last error MapLibre reported for an area downloading, said beside `.waitingForNetwork` until a
    /// resource arrives again (MapLibre tries again by itself)
    private(set) var problems: [String: String] = [:]
    /// Asked for and not complete, kept across launches: made or resumed when the app opens. An area whose
    /// pack could not be made stays, so the next launch tries it again; a pause or a removal takes it out.
    private(set) var requests: Set<String> = Set(Shared.defaults.stringArray(forKey: OfflineMaps.requestsKey) ?? [])
    /// `OfflineMaps.mapBuild`, read on `refresh` (the build changes rarely; packs report all the time)
    private(set) var mapBuild = OfflineMaps.mapBuild
    /// Some packs are stale: asked once per tile build for them to be downloaded again. Answered (the
    /// alert's buttons, "Tải tất cả"), or with nothing stale left, it is not asked again for this build.
    var needsReload = false {
        didSet {
            if oldValue, !needsReload { Shared.defaults.set(mapBuild.template, forKey: Self.reloadAskedKey) }
        }
    }

    /// complete for the build the map reads
    var complete: Set<String> { ids { if case .complete = $0 { true } else { false } } }
    /// made for another build or by an older version: useless offline until downloaded again
    var stale: Set<String> { ids { if case .stale = $0 { true } else { false } } }
    var totalBytes: UInt64 { bytes.values.reduce(0, +) }

    /// Not complete and not under way: what "Tải tất cả" downloads.
    var missing: [Area] {
        areas.filter { area in
            guard let phase = phases[area.id] else { return true }
            if case .complete = phase { return false }
            return !phase.isUnderWay
        }
    }

    /// How far these areas are, together (a complete one counts whole).
    func fraction(of ids: Set<String>) -> Double {
        guard !ids.isEmpty else { return 0 }
        let sum = ids.reduce(0.0) { sum, id in
            if case .complete? = phases[id] { return sum + 1 }
            return sum + (progress[id] ?? 0)
        }
        return sum / Double(ids.count)
    }

    private func ids(where test: (AreaPhase) -> Bool) -> Set<String> {
        Set(phases.filter { test($0.value) }.keys)
    }

    /// the key of the list since the first builds, when it was called `wanted` (same list, same shape)
    private static let requestsKey = "map.wanted"
    /// the tile template the reload was last asked for
    private static let reloadAskedKey = "map.reloadAskedFor"

    /// What a pack was made for: its area (packs of every version name it) and its tag (this version's only).
    private struct Label {
        let area: String
        let tag: PackTag?
    }

    /// Read once per context: MapLibre reports progress for every tile, so nothing per report reads JSON.
    /// Kept by context, not by pack object: `reloadPacks` hands out new objects for the same packs.
    @ObservationIgnored private var labels: [Data: Label] = [:]
    /// when each area last showed its progress: a few times a second is what a page can show
    @ObservationIgnored private var shown: [String: CFTimeInterval] = [:]
    /// the resources each area's pack had at its last report: one more is the network working again
    @ObservationIgnored private var counted: [String: UInt64] = [:]
    @ObservationIgnored private var watch: NSKeyValueObservation?
    /// `watch` is being set up: its style stored first (`configure`), so a second call waits for that one
    @ObservationIgnored private var preparing = false
    /// The last style stored (`preloadStyle`): put back under a pack's own URL just before the pack resumes
    /// (`record`). MapLibre links the style to a pack only once the pack is complete (or has found 200
    /// resources already stored); until then it is a row of the ambient cache, which browsing the map can
    /// push out, and a pack resumed without it would ask the network for it.
    @ObservationIgnored private var lastStyle: PackStyle.Prepared?
    /// Each area whose pack is being made, and the number of the make that makes it: from `download` until the
    /// pack is added, or the area fails or is removed. A make that finds another number there (Xoá, then Tải,
    /// during "Đang chuẩn bị…") or none leaves the area alone, so no area gets two packs of one build.
    @ObservationIgnored private var making: [String: Int] = [:]
    @ObservationIgnored private var makes = 0

    override init() {
        super.init()
        // asked for before this launch: nothing is known of them until their packs are read
        phases = Dictionary(uniqueKeysWithValues: requests.map { ($0, AreaPhase.requested) })
        NotificationCenter.default.addObserver(self, selector: #selector(packProgress(_:)), name: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(packError(_:)), name: NSNotification.Name.MLNOfflinePackError, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tilesMoved(_:)), name: Self.tilesChanged, object: nil)
    }

    /// One area per region of the plan, framed on its places with a margin, and first the whole route
    /// zoomed out ("Toàn tuyến"), so the map zoomed out and the picture of a day across areas draw with no
    /// signal. Set at once: the caller reads them next (`Downloads.back`). The packs are read once the style
    /// they are made from is stored; each later call (every return to the app) stores it again.
    func configure(store: TripStore) {
        if areas.isEmpty {
            let names = ["tokyo": "Tokyo", "hakone": "Hakone", "kawaguchiko": "Kawaguchiko", "tokaido": "Shizuoka", "ise": "Ise", "toba": "Toba, Tōshijima", "shima": "Shima", "kyoto": "Kyoto, Uji", "nara": "Nara", "osaka": "Osaka, KIX"]
            let grouped = Dictionary(grouping: store.trip.places.filter { $0.role != "alt" || $0.area == "kawaguchiko" }, by: \.area)
            var all: [Area] = names.compactMap { id, name in
                guard let pts = grouped[id]?.map(\.coordinate), let b = Geo.bounds(pts) else { return nil }
                let pad = 0.012
                return Area(id: id, name: name, sw: Coordinate(b.sw.lat - pad, b.sw.lng - pad), ne: Coordinate(b.ne.lat + pad, b.ne.lng + pad),
                            zoom: 9...16)
            }.sorted { $0.name < $1.name }
            if let whole = OfflineArea.overview(of: all.map { (sw: $0.sw, ne: $0.ne) }) {
                all.insert(Area(id: OfflineArea.overviewID, name: "Toàn tuyến", sw: whole.sw, ne: whole.ne, zoom: 5...10), at: 0)
            }
            areas = all
            // asked for by an earlier build, of an area this one does not have: it could never be made, and
            // would keep a download under way for ever
            let known = Set(areas.map(\.id))
            let unknown = requests.subtracting(known)
            if !unknown.isEmpty {
                requests.subtract(unknown)
                saveRequests()
            }
            for id in Set(phases.keys).subtracting(known) { phases[id] = nil }
        }
        guard watch == nil else {
            // back in the app: stored again, in case the cache let it go meanwhile (nobody waits for it)
            Task { _ = await preloadStyle(currentTemplate: Self.currentTemplate) }
            return
        }
        guard !preparing else { return }
        preparing = true
        Task {
            // Stored before the packs are read, so a pack resumed at launch (`record`) never asks the
            // network for its style. Not stored (no bundled style), the packs are still read: an area made
            // later says why it fails.
            _ = await preloadStyle(currentTemplate: Self.currentTemplate)
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
    }

    /// Stores the style a pack of this build is made from (`currentTemplate` nil: the pinned build) in
    /// MapLibre's database, under the URL the pack will name, and returns it once MapLibre says it is there:
    /// a pack made or resumed after this reads it from the database. Nil when the app has no style to store,
    /// or MapLibre said it could not store it.
    private func preloadStyle(currentTemplate: String?) async -> PackStyle.Prepared? {
        guard let prepared = await Self.preparedStyle(currentTemplate: currentTemplate), let url = URL(string: prepared.url) else { return nil }
        // The handler is @Sendable (on no actor) and MapLibre calls it on the main queue
        // (MLNOfflineStorage.h): it only hands the answer over. MapLibre 7.0.0 always calls it, once.
        let stored = await withCheckedContinuation { (answer: CheckedContinuation<Bool, Never>) in
            MLNOfflineStorage.shared.preload(prepared.style, for: url, modificationDate: nil, expirationDate: Self.packStyleExpiry,
                                             eTag: nil, mustRevalidate: false) { _, error in
                answer.resume(returning: error == nil)
            }
        }
        guard stored else { return nil }
        lastStyle = prepared
        return prepared
    }

    /// Puts the last style stored back under the URL this pack names, when it holds the pack's build: the
    /// pack resumed next finds it. No completion to wait for: MapLibre stores it and resumes the pack on one
    /// queue, in that order. No style stored yet (a resume in the first moments of a launch): nothing put
    /// back, and the store already asked for is ahead of the resume in that queue.
    private func restoreStyle(for tag: PackTag) {
        guard let last = lastStyle, last.build == tag.build, let url = URL(string: tag.styleURL) else { return }
        MLNOfflineStorage.shared.preload(last.style, for: url, modifiedOn: nil, expiresOn: Self.packStyleExpiry, eTag: nil, mustRevalidate: false)
    }

    /// Looks at every pack: where each area is (`OfflineArea.settle`), the older packs of an area complete
    /// again let go, the areas asked for with no pack for the map's build made, the reload asked for.
    func refresh() {
        guard let packs = MLNOfflineStorage.shared.packs else { return }
        ready = true
        mapBuild = Self.mapBuild
        // each area's pack for the map's build, and its packs of another build or an older version
        var current: [String: (pack: MLNOfflinePack, tag: PackTag)] = [:]
        var older: [String: (phase: AreaPhase, packs: [MLNOfflinePack])] = [:]
        for pack in packs {
            // the state first: any other message to a removed pack raises
            guard pack.state != .invalid, let label = label(of: pack) else { continue }
            if let tag = label.tag, tag.build == mapBuild {
                if Self.keeps(pack, over: current[label.area]?.pack) { current[label.area] = (pack, tag) }
            } else {
                older[label.area, default: (phase: .stale(label.tag?.build), packs: [])].packs.append(pack)
            }
        }
        var make: [Area] = []
        for area in areas {
            let id = area.id
            var now: AreaPhase?
            if let (pack, tag) = current[id] {
                // a pack read from storage knows nothing of itself until asked
                if pack.state == .unknown { pack.requestProgress() }
                now = record(pack, tag: tag, force: true).phase
            } else {
                drop(id)
            }
            let settled = OfflineArea.settle(current: now, older: older[id]?.phase, previous: phases[id], requested: requests.contains(id),
                                             making: making[id] != nil)
            set(id, settled.phase)
            if settled.dropOld {
                // its pack for the map's build is complete: the older ones go (until now they were what it had)
                for old in older[id]?.packs ?? [] { MLNOfflineStorage.shared.removePack(old) { _ in } }
            }
            if settled.make { make.append(area) }
        }
        let anyStale = !stale.isEmpty
        if anyStale, !needsReload, Shared.defaults.string(forKey: Self.reloadAskedKey) != mapBuild.template { needsReload = true }
        if !anyStale, needsReload { needsReload = false }
        // asked for, and no pack for the build the map reads: made (again)
        if !make.isEmpty { download(make) }
    }

    /// Asks for these areas. Each is under way at once: its pack for the map's build goes on from where it
    /// is, or it is `.creating` while its pack is made (`make`), so a download that follows the phases
    /// never sees it idle in between. Asked for until complete, paused or removed; a failure keeps it.
    func download(_ asked: [Area]) {
        let packs = MLNOfflineStorage.shared.packs
        var toMake: [(area: Area, number: Int)] = []
        for area in asked {
            let id = area.id
            request(id)
            if problems[id] != nil { problems[id] = nil }
            // its pack is being made already (paused meanwhile: under way again, and started once added)
            if making[id] != nil {
                set(id, .creating)
                continue
            }
            // not read yet: made by `refresh` once MapLibre has its list, so no pack is made twice
            guard let packs else {
                set(id, .requested)
                continue
            }
            if let (pack, tag) = currentPack(of: id, in: packs) {
                if pack.state == .unknown { pack.requestProgress() }
                set(id, record(pack, tag: tag, force: true).phase)
                continue
            }
            set(id, .creating)
            if progress[id] != 0 { progress[id] = 0 }
            if bytes[id] != nil { bytes[id] = nil }
            makes += 1
            making[id] = makes
            toMake.append((area, makes))
        }
        guard !toMake.isEmpty else { return }
        // nobody waits for it: a download follows the phases, which `make` moves on
        Task { await make(toMake) }
    }

    /// Every area not complete and not under way. Returns their ids.
    @discardableResult func downloadAll() -> Set<String> {
        let missing = missing
        download(missing)
        needsReload = false
        return Set(missing.map(\.id))
    }

    /// Makes the areas' packs (each under its number in `making`), after storing the style they are made
    /// from, for the build the map read when asked (`preloadStyle`): the pack then reads it from MapLibre's
    /// database, never from the network. It must hold the build the map reads, or the pack would hold tiles
    /// the map never asks for; the map moving to another build during the store stores the style of that
    /// one (`OfflineArea.step`).
    private func make(_ asked: [(area: Area, number: Int)]) async {
        var left = asked
        var again = false
        while true {
            let askedOn = mapBuild
            let prepared = await preloadStyle(currentTemplate: askedOn == Self.pinned ? nil : askedOn.template)
            let served: ServedStyle = prepared.map { .files(style: $0.style, tileJSON: nil) } ?? .refused(Self.unstored)
            // after the wait: removed or made again by a later tap meanwhile, nothing to make here
            left = left.filter { still($0.area.id, $0.number) }
            guard !left.isEmpty else { return }
            // `mapBuild` read after the wait: the map may have moved to another build meanwhile (`refresh`)
            switch OfflineArea.step(served, mapBuild: mapBuild, askedOn: askedOn, again: again) {
            case .add(let build):
                // a build comes only from a style stored: one URL for the region, its tag and the stored style
                guard let prepared, let style = URL(string: prepared.url) else {
                    abandon(left, because: Self.unstored)
                    return
                }
                for (area, number) in left {
                    add(area, tag: PackTag(area: area.id, build: build, styleURL: prepared.url), style: style, number: number)
                }
                return
            case .again:
                again = true
            case .fail(let reason):
                abandon(left, because: reason)
                return
            }
        }
    }

    /// The make is over for these areas, and they fail. One paused meanwhile stays paused, not failed (and,
    /// asked for no more, is not tried again).
    private func abandon(_ left: [(area: Area, number: Int)], because reason: String) {
        for (area, _) in left {
            making[area.id] = nil
            if phases[area.id] == .creating { set(area.id, .failed(reason)) }
        }
    }

    /// Whether make `number` still makes the area's pack: the area still under it (not removed, not made
    /// again by a later tap), with no pack for the map's build (the map moved back to a build it has one of:
    /// that pack says where it is, `refresh`), and `.creating`, or `.paused` by a tap meanwhile (still made,
    /// then left inactive: `record`).
    private func still(_ id: String, _ number: Int) -> Bool {
        guard making[id] == number else { return false }
        if let packs = MLNOfflineStorage.shared.packs, currentPack(of: id, in: packs) != nil {
            making[id] = nil
            return false
        }
        guard phases[id] == .creating || phases[id] == .paused else {
            making[id] = nil
            return false
        }
        return true
    }

    private func add(_ area: Area, tag: PackTag, style: URL, number: Int) {
        let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: area.sw.lat, longitude: area.sw.lng),
                                         ne: CLLocationCoordinate2D(latitude: area.ne.lat, longitude: area.ne.lng))
        let region = MLNTilePyramidOfflineRegion(styleURL: style, bounds: bounds, fromZoomLevel: area.zoom.lowerBound, toZoomLevel: area.zoom.upperBound)
        let id = area.id
        // Swift imports an Objective-C completion handler as @Sendable, so this closure is on no
        // actor. MapLibre calls it on the main queue (MLNOfflineStorage.mm dispatches it there),
        // which `assumeIsolated` states and checks, as for the other MapLibre callbacks. Only plain
        // facts cross into the main actor: the pack (not Sendable) stays where MapLibre handed it,
        // and the main actor reads it from `packs` like every other pack, so `record` alone decides
        // to start it (as it does after a relaunch), and one paused or removed meanwhile waits.
        MLNOfflineStorage.shared.addPack(for: region, withContext: tag.context) { [weak self] pack, error in
            guard let self else { return }
            let made = pack != nil
            let failure = error?.localizedDescription
            MainActor.assumeIsolated {
                // the make is over (another number: Xoá, then Tải, made the area again meanwhile, and that
                // make goes on). Added, the pack says where the area is; one of a build the map left during
                // the add is filed as older, and the area, made by nothing now, is made again (`settle`).
                let ours = self.making[id] == number
                if ours { self.making[id] = nil }
                if made {
                    self.refresh()
                } else if ours, self.phases[id] == .creating {
                    // still asked for: a tap, or the next launch, tries again
                    self.set(id, .failed("Không tạo được vùng tải" + (failure.map { ": \($0)" } ?? "")))
                }
            }
        }
    }

    /// Stops an area where it is; "Tiếp tục" picks it up from there. Not asked for any more, so not
    /// picked up at the next launch either.
    func pause(_ id: String) {
        unrequest(id)
        for pack in MLNOfflineStorage.shared.packs ?? [] where pack.state == .active && label(of: pack)?.area == id {
            pack.suspend()
        }
        // a suspended pack reports nothing more (MLNOfflinePack.h), so the area says it here. One whose
        // pack is being made says so at once too: still made, then left inactive (`record`); if it cannot
        // be made, it stays paused (`make`).
        switch phases[id] {
        case .requested?, .creating?, .downloading?, .waitingForNetwork?: set(id, .paused)
        case .paused?, .complete?, .stale?, .failed?, nil: break
        }
    }

    func pauseAll() {
        for (id, phase) in phases where phase.isUnderWay { pause(id) }
    }

    /// The area's packs go, of every build and version, and the area is asked for no more.
    func remove(_ area: Area) {
        let id = area.id
        unrequest(id)
        // a make under way leaves it alone now (`still`)
        making[id] = nil
        for pack in MLNOfflineStorage.shared.packs ?? [] where pack.state != .invalid && label(of: pack)?.area == id {
            MLNOfflineStorage.shared.removePack(pack) { _ in }
        }
        set(id, nil)
        drop(id)
    }

    private func request(_ id: String) {
        guard !requests.contains(id) else { return }
        requests.insert(id)
        saveRequests()
    }

    private func unrequest(_ id: String) {
        guard requests.contains(id) else { return }
        requests.remove(id)
        saveRequests()
    }

    private func saveRequests() {
        Shared.defaults.set(requests.sorted(), forKey: Self.requestsKey)
    }

    private func set(_ id: String, _ phase: AreaPhase?) {
        if phases[id] != phase { phases[id] = phase }
    }

    /// No pack for the map's build: nothing downloaded for the area, nothing reporting.
    private func drop(_ id: String) {
        if progress[id] != nil { progress[id] = nil }
        if bytes[id] != nil { bytes[id] = nil }
        if problems[id] != nil { problems[id] = nil }
        shown[id] = nil
        counted[id] = nil
    }

    /// MapLibre posts pack progress on the main queue (MLNOfflinePack hops there before posting),
    /// so this stays on the main actor and the notification never crosses to it.
    @objc private func packProgress(_ note: Notification) {
        // the state first: any other message to a removed pack raises
        guard let pack = note.object as? MLNOfflinePack, pack.state != .invalid, let tag = label(of: pack)?.tag,
              tag.build == mapBuild, areas.contains(where: { $0.id == tag.area }) else { return }
        let was = phases[tag.area]
        let (phase, show) = record(pack, tag: tag)
        guard show else { return }
        set(tag.area, phase)
        // complete just now: its older packs can go (`refresh`)
        if case .complete = phase, was != phase { refresh() }
    }

    /// A tile or the style failed (posted on the main queue too). MapLibre keeps trying; the area
    /// waits for the network and says why until a resource arrives again. A missing tile is ordinary
    /// (sea, no data).
    @objc private func packError(_ note: Notification) {
        guard let pack = note.object as? MLNOfflinePack, pack.state != .invalid, let tag = label(of: pack)?.tag,
              tag.build == mapBuild, areas.contains(where: { $0.id == tag.area }) else { return }
        let error = note.userInfo?[MLNOfflinePackUserInfoKey.error.rawValue] as? NSError
        let text: String
        switch error?.code {
        case MLNErrorCode.notFound.rawValue: return
        case MLNErrorCode.connectionFailed.rawValue: text = "Không kết nối được, đang thử lại"
        case MLNErrorCode.badServerResponse.rawValue: text = "Máy chủ bản đồ đang lỗi, đang thử lại"
        default: text = "Lỗi tải, đang thử lại"
        }
        if problems[tag.area] != text { problems[tag.area] = text }
        set(tag.area, record(pack, tag: tag, force: true).phase)
    }

    /// The map moved to another tile build (posted on the main queue by `checkPinnedTiles`): the style of
    /// that build stored first, so the packs looked at anew (`refresh`) and resumed have it.
    @objc private func tilesMoved(_ note: Notification) {
        Task {
            _ = await preloadStyle(currentTemplate: Self.currentTemplate)
            refresh()
        }
    }

    /// Where an area is, from its pack for the map's build (`OfflineArea.phase`). Starts the pack when the
    /// area is asked for and it is not running; lets go of the request once the area is complete. `show`:
    /// worth telling the page now (every resource reports; a few times a second is what a page can show,
    /// and at once when the phase changes).
    private func record(_ pack: MLNOfflinePack, tag: PackTag, force: Bool = false) -> (phase: AreaPhase, show: Bool) {
        let id = tag.area
        let requested = requests.contains(id)
        let previous = phases[id]
        var state = PackState(rawValue: pack.state.rawValue) ?? .unknown
        if state == .inactive, requested {
            // asked for and not running: a pack just made (MapLibre hands it over inactive), or one
            // stopped by a relaunch (packs come back inactive). On, its style put back first.
            restoreStyle(for: tag)
            pack.resume()
            state = .active
        } else if state == .active, !requested {
            // paused: MapLibre may still finish what it had asked for, but the area is not under way
            state = .inactive
        }
        guard state != .unknown else {
            // not known yet: `requestProgress` answers with a report
            let phase = OfflineArea.phase(state: .unknown, completed: 0, expected: 0, maximum: 0, tag: tag,
                                          mapBuild: mapBuild, error: nil, previous: previous)
            return (phase, force || phase != previous)
        }
        let p = pack.progress
        // a resource arrived: the network works again
        if p.countOfResourcesCompleted > (counted[id] ?? p.countOfResourcesCompleted), problems[id] != nil { problems[id] = nil }
        counted[id] = p.countOfResourcesCompleted
        let phase = OfflineArea.phase(state: state, completed: p.countOfResourcesCompleted, expected: p.countOfResourcesExpected,
                                      maximum: p.maximumResourcesExpected, tag: tag, mapBuild: mapBuild, error: problems[id],
                                      previous: previous)
        let complete = if case .complete = phase { true } else { false }
        if complete {
            unrequest(id)
            if problems[id] != nil { problems[id] = nil }
        }
        let counting = if case .downloading? = previous, case .downloading = phase { true } else { false }
        let now = CACurrentMediaTime()
        guard force || (phase != previous && !counting) || now - (shown[id] ?? 0) >= 0.25 else { return (phase, false) }
        shown[id] = now
        let expected = p.countOfResourcesExpected
        let fraction = complete ? 1 : expected > 0 ? min(1, Double(p.countOfResourcesCompleted) / Double(expected)) : 0
        if progress[id] != fraction { progress[id] = fraction }
        if bytes[id] != p.countOfBytesCompleted { bytes[id] = p.countOfBytesCompleted }
        return (phase, true)
    }

    /// The area's pack for the map's build, if any.
    private func currentPack(of id: String, in packs: [MLNOfflinePack]) -> (pack: MLNOfflinePack, tag: PackTag)? {
        var found: (pack: MLNOfflinePack, tag: PackTag)?
        for pack in packs where pack.state != .invalid {
            guard let tag = label(of: pack)?.tag, tag.area == id, tag.build == mapBuild else { continue }
            if Self.keeps(pack, over: found?.pack) { found = (pack, tag) }
        }
        return found
    }

    /// An area's pack for the map's build made twice (it should not be): the complete one is kept, else the
    /// first. Its state must have been read first, and not be `.invalid`.
    private static func keeps(_ pack: MLNOfflinePack, over found: MLNOfflinePack?) -> Bool {
        found == nil || pack.state == .complete
    }

    /// What a pack was made for. Its state must have been read first, and not be `.invalid`: the context
    /// is a message to the pack.
    private func label(of pack: MLNOfflinePack) -> Label? {
        let context = pack.context
        if let known = labels[context] { return known }
        guard let area = PackTag.area(of: context) else { return nil }
        let label = Label(area: area, tag: PackTag.read(context))
        labels[context] = label
        return label
    }
}

// MARK: - Downloads that outlast the page

/// The trip's downloads (map areas, photos) belong to the app, not to the page that starts them:
/// they go on while the travellers use the rest of the app, the page shows where they are whenever
/// it is opened again, and what was asked for and not finished is picked up at the next launch.
///
/// A tap starts a job (`OfflineJob`), or adds to the one under way: its areas, and whether it takes the
/// photos. It is saved, so a relaunch follows it again. It is over when nothing of it is under way, and
/// only then said done or not (`OfflineJob.result`): "Xong" only when every area is complete for the
/// build the map reads and every photo is on disk.
///
/// Leaving the app: a download started by a tap runs as a continued processing task (iOS 26), which
/// the system shows as a Live Activity with its progress and a stop button, and lets run in the
/// background until it is done. The system grants one only for an explicit action, so a download
/// picked up at launch gets the usual half minute (`beginBackgroundTask`) instead.
@Observable final class Downloads {
    let maps = OfflineMaps()
    let photos = OfflinePhotos()

    /// the download under way: every tap since the last one ended
    private var job: OfflineJob? = nil
    /// how the last one ended, for the page, until the next tap
    private(set) var ended: JobResult? = nil
    @ObservationIgnored private var task: BGContinuedProcessingTask?
    /// submitted, not started yet
    @ObservationIgnored private var asked = false
    @ObservationIgnored private var grace: UIBackgroundTaskIdentifier = .invalid
    @ObservationIgnored private var ticking: Task<Void, Never>?
    @ObservationIgnored private var shown = ""
    private static let jobKey = "downloads.job"

    init() {
        // followed again where it was: its areas are made or resumed once the packs are read (the areas
        // asked for, `OfflineMaps.requests`, among them), the photos by their own flag
        let saved = Shared.defaults.data(forKey: Self.jobKey).flatMap { try? JSONDecoder().decode(OfflineJob.self, from: $0) }
        let areas = (saved?.areas ?? []).union(maps.requests)
        let withPhotos = saved?.photos ?? false
        if !areas.isEmpty || withPhotos { job = OfflineJob(areas: areas, photos: withPhotos) }
    }

    /// Something is still going: an area of the download under way (or one asked for, made again at a
    /// launch), or the photos.
    var busy: Bool {
        if photos.running { return true }
        return (job?.areas ?? []).union(maps.requests).contains { maps.phases[$0]?.isUnderWay == true }
    }

    /// How far the download under way is, 0…1: each area weighs one, the photos one more.
    var fraction: Double {
        let areas = job?.areas ?? []
        var sum = maps.fraction(of: areas) * Double(areas.count)
        var weight = Double(areas.count)
        if job?.photos == true || photos.running {
            sum += photos.fraction
            weight += 1
        }
        return weight > 0 ? sum / weight : 0
    }

    /// "Bản đồ 3/10 vùng · Ảnh 120/180 · 42%": the download while it runs. How it ended is `ended`.
    var progressLine: String {
        var parts: [String] = []
        let areas = job?.areas ?? []
        if !areas.isEmpty { parts.append("Bản đồ \(areas.filter(maps.complete.contains).count)/\(areas.count) vùng") }
        if job?.photos == true || photos.running { parts.append("Ảnh \(photos.saved)/\(photos.total)") }
        parts.append("\(Int(fraction * 100))%")
        return parts.joined(separator: " · ")
    }

    // MARK: Taps

    func download(_ area: OfflineMaps.Area) {
        maps.download([area])
        start(areas: [area.id], photos: false)
    }

    func downloadAllMaps() {
        start(areas: maps.downloadAll(), photos: false)
    }

    func downloadPhotos() {
        photos.download()
        start(areas: [], photos: photos.running)
    }

    /// A tap: the download under way takes these too (one Live Activity for all of it), or a new one
    /// starts. Saved, so a relaunch follows it; followed now, and the system asked to let it finish.
    private func start(areas: Set<String>, photos withPhotos: Bool) {
        guard !areas.isEmpty || withPhotos else { return }
        job = OfflineJob(areas: (job?.areas ?? []).union(areas), photos: (job?.photos ?? false) || withPhotos)
        ended = nil
        saveJob()
        keep()
    }

    private func saveJob() {
        if let job, let data = try? JSONEncoder().encode(job) {
            Shared.defaults.set(data, forKey: Self.jobKey)
        } else {
            Shared.defaults.removeObject(forKey: Self.jobKey)
        }
    }

    // MARK: The app comes and goes

    /// Back in the app: what was picked up at launch is followed like the rest.
    func back() {
        endGrace()
        forgetUnknownAreas()
        if busy || job != nil { tick() }
    }

    /// A job saved by an earlier build may name an area this one does not have (`OfflineMaps.configure`
    /// drops it from the requests): never complete, it would keep the job from ending.
    private func forgetUnknownAreas() {
        guard let job, !maps.areas.isEmpty else { return }
        let known = Set(maps.areas.map(\.id))
        guard !job.areas.isSubset(of: known) else { return }
        let areas = job.areas.intersection(known)
        self.job = areas.isEmpty && !job.photos ? nil : OfflineJob(areas: areas, photos: job.photos)
        saveJob()
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
        let request = BGContinuedProcessingTaskRequest(identifier: id, title: Self.title, subtitle: progressLine)
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

    /// Returns whether to go on: while something is under way, and until the job can be judged.
    private func report() -> Bool {
        guard busy || !judgeable else {
            finish()
            return false
        }
        if let task {
            let units = Int64(fraction * 1000)
            // the system reads a stuck bar as a stuck task: it only moves forward
            if units > task.progress.completedUnitCount { task.progress.completedUnitCount = units }
            let line = progressLine
            if line != shown {
                task.updateTitle(Self.title, subtitle: line)
                shown = line
            }
        }
        return true
    }

    /// Whether how the job stands can be told: its areas' packs read (until then none has a phase worth
    /// judging) and, when it takes the photos, the photos on disk counted.
    private var judgeable: Bool {
        guard let job else { return true }
        return (job.areas.isEmpty || maps.ready) && (!job.photos || photos.counted)
    }

    /// The job is over: said done only when it is. The Live Activity's last line says how it ended; its
    /// bar is full only on success.
    private func finish() {
        let result = job?.result(phases: maps.phases, photos: photoState, mapBuild: maps.mapBuild)
        if let task {
            if let result {
                if result.success { task.progress.completedUnitCount = task.progress.totalUnitCount }
                task.updateTitle(Self.title, subtitle: result.subtitle)
            }
            task.setTaskCompleted(success: result?.success ?? false)
            self.task = nil
        } else if asked, let id = Self.identifier {
            // nothing left for a task still waiting its turn
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: id)
            asked = false
        }
        endGrace()
        if let result { ended = result }
        job = nil
        saveJob()
    }

    /// The photos as the job's end reads them.
    private var photoState: PhotoState {
        PhotoState(failed: photos.failed, left: max(0, photos.total - photos.saved), paused: photos.paused)
    }
}

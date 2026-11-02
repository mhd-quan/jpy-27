import Foundation
import MapLibre
import Observation
import TripKit

/// The basemap and its offline packs. The style is the site's own (src/lib/mapStyle.ts, exported to
/// public/map/), on OpenFreeMap vector tiles; packs cover each area of the trip so the map works
/// with no signal. Tiles are shared between styles, so the dark style reads the same packs.
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

    private static func pinnedTiles(in style: URL) -> String? {
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

    /// Served by the site, used for the packs (a pack downloads its style by URL).
    static func remoteStyle(dark: Bool) -> URL {
        URL(string: "https://jpy27.delphyra.tech/map/jp27-\(dark ? "dark" : "light").json")!
    }

    private(set) var areas: [Area] = []
    private(set) var progress: [String: Double] = [:]
    private(set) var bytes: [String: UInt64] = [:]
    private(set) var complete: Set<String> = []

    var totalBytes: UInt64 { bytes.values.reduce(0, +) }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(packProgress(_:)), name: NSNotification.Name.MLNOfflinePackProgressChanged, object: nil)
    }

    /// One area per region of the plan, framed on its places with a margin.
    func configure(store: TripStore) {
        let names = ["tokyo": "Tokyo", "hakone": "Hakone", "kawaguchiko": "Kawaguchiko", "tokaido": "Shizuoka", "ise": "Ise", "toba": "Toba, Tōshijima", "shima": "Shima", "kyoto": "Kyoto, Uji", "nara": "Nara", "osaka": "Osaka, KIX"]
        let grouped = Dictionary(grouping: store.trip.places.filter { $0.role != "alt" || $0.area == "kawaguchiko" }, by: \.area)
        areas = names.compactMap { id, name in
            guard let pts = grouped[id]?.map(\.coordinate), let b = Geo.bounds(pts) else { return nil }
            let pad = 0.012
            return Area(id: id, name: name, sw: Coordinate(b.sw.lat - pad, b.sw.lng - pad), ne: Coordinate(b.ne.lat + pad, b.ne.lng + pad))
        }.sorted { $0.name < $1.name }
        refresh()
    }

    func refresh() {
        for pack in MLNOfflineStorage.shared.packs ?? [] {
            guard let id = Self.areaID(pack) else { continue }
            record(pack, id: id)
        }
    }

    func download(_ area: Area) {
        if let existing = (MLNOfflineStorage.shared.packs ?? []).first(where: { Self.areaID($0) == area.id }) {
            existing.resume()
            return
        }
        let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: area.sw.lat, longitude: area.sw.lng),
                                         ne: CLLocationCoordinate2D(latitude: area.ne.lat, longitude: area.ne.lng))
        let region = MLNTilePyramidOfflineRegion(styleURL: Self.remoteStyle(dark: false), bounds: bounds, fromZoomLevel: 9, toZoomLevel: 16)
        let context = Data(area.id.utf8)
        MLNOfflineStorage.shared.addPack(for: region, withContext: context) { pack, _ in
            pack?.resume()
        }
        progress[area.id] = 0
    }

    func downloadAll() {
        for a in areas where !complete.contains(a.id) { download(a) }
    }

    func remove(_ area: Area) {
        for pack in MLNOfflineStorage.shared.packs ?? [] where Self.areaID(pack) == area.id {
            MLNOfflineStorage.shared.removePack(pack) { _ in }
        }
        progress[area.id] = nil
        bytes[area.id] = nil
        complete.remove(area.id)
    }

    /// MapLibre posts pack progress on the main queue (MLNOfflinePack hops there before posting),
    /// so this stays on the main actor and the notification never crosses to it.
    @objc private func packProgress(_ note: Notification) {
        guard let pack = note.object as? MLNOfflinePack, let id = Self.areaID(pack) else { return }
        record(pack, id: id)
    }

    private func record(_ pack: MLNOfflinePack, id: String) {
        let p = pack.progress
        progress[id] = p.countOfResourcesExpected > 0 ? Double(p.countOfResourcesCompleted) / Double(p.countOfResourcesExpected) : 0
        bytes[id] = p.countOfBytesCompleted
        if pack.state == .complete { complete.insert(id) }
    }

    private static func areaID(_ pack: MLNOfflinePack) -> String? {
        String(data: pack.context, encoding: .utf8)
    }
}

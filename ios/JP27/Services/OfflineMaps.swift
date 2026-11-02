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

    /// Bundled copy, used by the map view: no network needed to read the style itself.
    static func style(dark: Bool) -> URL {
        Bundle.main.url(forResource: dark ? "jp27-dark" : "jp27-light", withExtension: "json", subdirectory: "map")
            ?? remoteStyle(dark: dark)
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

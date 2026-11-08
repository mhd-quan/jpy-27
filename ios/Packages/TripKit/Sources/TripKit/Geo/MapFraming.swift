import Foundation

/// What a map of some points is framed on: one place (or a few metres) centred at street level, else
/// everything, at least ~600 m across, with the map's insets kept clear around it. The app's live map
/// (`TripMap.Coordinator.fit`) and its picture (`MapSnapshots.frame`) frame by this one rule, so the live
/// map that replaces a picture shows the same view (Settings › Chẩn đoán › So khung bản đồ, in Debug).
public enum MapFraming: Hashable, Sendable {
    case point(Coordinate)
    case area(sw: Coordinate, ne: Coordinate)

    /// the zoom a lone place is shown at
    public static let pointZoom = 15.5

    public static func of(_ pts: [Coordinate]) -> MapFraming? {
        guard let b = Geo.bounds(pts) else { return nil }
        let mid = Coordinate((b.sw.lat + b.ne.lat) / 2, (b.sw.lng + b.ne.lng) / 2)
        if pts.count == 1 || (b.ne.lat - b.sw.lat < 0.002 && b.ne.lng - b.sw.lng < 0.002) {
            return .point(mid)
        }
        // a short walk is not blown up to street level: at least ~600 m across
        let half = (lat: max((b.ne.lat - b.sw.lat) / 2, 0.0028), lng: max((b.ne.lng - b.sw.lng) / 2, 0.0034))
        return .area(sw: Coordinate(mid.lat - half.lat, mid.lng - half.lng), ne: Coordinate(mid.lat + half.lat, mid.lng + half.lng))
    }
}

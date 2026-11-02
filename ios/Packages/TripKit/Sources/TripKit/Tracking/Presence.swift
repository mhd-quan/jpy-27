import Foundation

/// Being at a place: one definition for everything that asks. Which stop a visit marks, where the
/// day stands, which stays the journal counts, how wide a geofence is. GPS between city buildings
/// is off by 50–100 m, so a counter's circle is 150 m; temple grounds and parks spread wider, and a
/// station's exits spread over a block.
public enum Presence {
    /// How far from the pin still counts as being there, km.
    public static func radius(of place: Place) -> Double {
        switch place.kind {
        case .sight: 0.25
        case .station: 0.22
        case .food, .shop, .stay: 0.15
        }
    }

    public static func isAt(_ position: Coordinate, _ place: Place) -> Bool {
        Geo.km(position, place.coordinate) <= radius(of: place)
    }

    /// Of the candidates, the one `position` is at: the nearest whose circle holds it, the first on
    /// a tie. Neighbours a few metres apart (Fukusuke and Okage Yokochō, 24 m) are told apart by
    /// distance, never by their order in the plan.
    public static func nearest<T>(_ position: Coordinate, among candidates: [(T, Place)]) -> T? {
        var best: (item: T, km: Double)?
        for (item, place) in candidates {
            let km = Geo.km(position, place.coordinate)
            guard km <= radius(of: place) else { continue }
            if best.map({ km < $0.km }) ?? true { best = (item, km) }
        }
        return best?.item
    }
}

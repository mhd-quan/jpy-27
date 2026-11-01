import Foundation

/// The decoded plan with the lookups every screen needs. Immutable; share it freely.
public final class TripStore: Sendable {
    public let trip: Trip
    public let guide: Guide?
    public let places: [String: Place]
    public let reserved: Set<String>
    private let paths: [String: [Coordinate]]
    private let ridesByDay: [String: [Ride]]
    private let scenarios: [String: Scenario]

    public init(trip: Trip, guide: Guide? = nil) {
        self.trip = trip
        self.guide = guide
        places = Dictionary(trip.places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        reserved = Set(trip.reserved)
        paths = trip.paths.mapValues { Polyline.decode($0.p) }
        ridesByDay = Dictionary(grouping: trip.rides + trip.altRides, by: \.day)
        scenarios = Dictionary((guide?.phrases.scenarios ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    public convenience init(tripJSON: Data, guideJSON: Data? = nil) throws {
        let decoder = JSONDecoder()
        let trip = try decoder.decode(Trip.self, from: tripJSON)
        let guide = try guideJSON.map { try decoder.decode(Guide.self, from: $0) }
        self.init(trip: trip, guide: guide)
    }

    /// trip.json and guide.json from a bundle (the app), or schedule.json alone (the widget).
    public static func load(from bundle: Bundle, slim: Bool = false) throws -> TripStore {
        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
            }
            return try Data(contentsOf: url, options: .mappedIfSafe)
        }
        if slim { return try TripStore(tripJSON: data("schedule")) }
        return try TripStore(tripJSON: data("trip"), guideJSON: data("guide"))
    }

    // MARK: Lookups

    public func place(_ id: String?) -> Place? {
        id.flatMap { places[$0] }
    }

    public func line(_ key: String) -> Line? {
        trip.lines[key]
    }

    public func mode(of leg: Leg) -> Mode {
        trip.lines[leg.line]?.mode ?? .walk
    }

    /// Geometry of a leg, decoded once.
    public func path(_ legID: String) -> [Coordinate] {
        paths[legID] ?? []
    }

    public func rides(on day: Day) -> [Ride] {
        ridesByDay[day.key] ?? []
    }

    public func scenario(_ id: String) -> Scenario? {
        scenarios[id]
    }

    public func chapter(of day: Day) -> Chapter? {
        trip.chapters.first { $0.days.contains(day.n) }
    }

    /// The days as the travellers will live them: an alternative replaces its day when chosen.
    public func days(choosing alternatives: Set<String> = []) -> [Day] {
        trip.days.map { day in
            trip.altDays.first { $0.replaces == day.n && alternatives.contains($0.key) } ?? day
        }
    }

    public func alternatives(for day: Day) -> [Day] {
        trip.altDays.filter { $0.replaces == day.n }
    }

    public func day(_ key: String) -> Day? {
        trip.days.first { $0.key == key } ?? trip.altDays.first { $0.key == key }
    }

    /// The ride a move starts, if the trains research grouped it into one.
    public func ride(startingWith legID: String, on day: Day) -> Ride? {
        rides(on: day).first { $0.legs.first == legID }
    }

    public func ride(containing legID: String, on day: Day) -> Ride? {
        rides(on: day).first { $0.legs.contains(legID) }
    }

    /// The ride's track, legs end to end.
    public func track(of ride: Ride) -> [Coordinate] {
        ride.legs.flatMap { path($0) }
    }

    /// Every coordinate a day touches, for framing a map.
    public func outline(of day: Day) -> [Coordinate] {
        var pts: [Coordinate] = []
        for item in day.items {
            switch item {
            case .move(let m): pts += path(m.leg.id)
            case .stop(let s): if let p = place(s.place) { pts.append(p.coordinate) }
            }
        }
        return pts
    }

    /// Scenarios that fit a place: its kind first, then extras the site attached by id.
    public func scenarios(for place: Place) -> [Scenario] {
        let extra: [String: [String]] = ["mizunoto": ["ryokan", "onsen"], "wargo-gion": ["kimono"], "st-toba": ["locker"], "kix": ["checkout"]]
        var tags: [String] = []
        switch place.kind {
        case .food: tags = ["table", "order", "ask-food", "pay"] + (place.menu?.ticketMachine == true ? ["shokken"] : [])
        case .station:
            tags = (place.name + (place.ja ?? "")).range(of: "Bến|Marine|港", options: .regularExpression) != nil ? ["ferry"] : ["ticket", "platform"]
        case .stay: tags = ["checkin", "checkout", "forward"]
        case .shop: tags = ["shop", "souvenir", "pay"]
        case .sight: tags = place.category == "temple" || place.name.contains("Jing") || place.name.contains("ji") ? ["temple"] : ["directions"]
        }
        tags += extra[place.id] ?? []
        var seen = Set<String>()
        return tags.compactMap { id in seen.insert(id).inserted ? scenario(id) : nil }
    }
}

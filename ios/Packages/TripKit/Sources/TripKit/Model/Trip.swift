import Foundation

/// The plan as exported by scripts/export-ios.mjs (trip.json, or the slim schedule.json).
public struct Trip: Codable, Sendable {
    public let version: Int
    public let meta: Meta
    public let modes: [String: String]
    public let lines: [String: Line]
    @Many public var chapters: [Chapter]
    @Many public var places: [Place]
    @Many public var days: [Day]
    @Many public var altDays: [Day]
    public let paths: [String: PathGeo]
    @Many public var rides: [Ride]
    @Many public var altRides: [Ride]
    @Many public var reserved: [String]
    public let rules: PlanRules
    /// booking windows, carried in the slim schedule for the widget's before-trip view
    @Many public var bookings: [Booking]
    /// Ids an update changed while the visit stayed the same one, by day key: old id → the id the day
    /// has now (src/data/id-renames.ts). One step: the data maps every old id straight to today's. The
    /// slim schedule has none.
    @ManyByKey public var idRenames: [String: [String: String]]
}

/// What the plan clock assumes (scripts/plan-rules.mjs).
public struct PlanRules: Codable, Sendable {
    /// minimum minutes at a place, by place id
    public let dwell: [String: Int]
    /// minutes waited for a departure without a fixed time, by mode
    public let wait: [String: Int]
    /// minutes a planned time may be behind the clock and still count as kept
    public let grace: Grace
    /// a stop reached with fewer minutes to spare than this is tight
    public let tight: Int

    public struct Grace: Codable, Sendable, Hashable {
        /// for a departure: the train does not wait
        public let move: Int
        public let stop: Int
    }

    private enum CodingKeys: String, CodingKey { case dwell, wait, grace, tight }

    /// `grace` and `tight` came later: a plan exported without them gets the values it was checked with.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dwell = try c.decode([String: Int].self, forKey: .dwell)
        wait = try c.decode([String: Int].self, forKey: .wait)
        grace = try c.decodeIfPresent(Grace.self, forKey: .grace) ?? Grace(move: 1, stop: 2)
        tight = try c.decodeIfPresent(Int.self, forKey: .tight) ?? 3
    }
}

public struct Meta: Codable, Sendable {
    public let title: String
    public let start: String
    public let end: String
    public let nights: Int
    public let people: Int
    public let researched: String
    /// VND per yen, the planning assumption
    public let rate: Double
    public let tz: String
}

public enum Mode: String, Codable, Sendable, CaseIterable {
    case walk, train, subway, shinkansen, bus, shuttle, ferry, cruise, ropeway, cable

    public var isRail: Bool { [.train, .subway, .shinkansen, .cable].contains(self) }
    /// Rides worth a Live Activity: you sit, stations pass, there is something to look at.
    public var isRide: Bool { self != .walk }
}

public struct Line: Codable, Sendable {
    public let name: String
    /// "#RRGGBB"
    public let color: String
    public let mode: Mode
    /// minutes between daytime departures, for lines that run often (src/data/lines.ts)
    public let every: Int?

    /// Missing one only means waiting for the next: a planned time on it is a suggestion, not a
    /// departure the day is held to. Reserved seats and sparse lines are not. Up to 20 minutes:
    /// JR Tōkaidō's local trains and the Shinkansen without a booked seat come that often.
    public static let frequentEvery = 20
    public var isFrequent: Bool { (every ?? .max) <= Self.frequentEvery }
}

public struct Chapter: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let nights: Int
    public let days: [Int]
    public let stay: String
    public let short: String
    public let color: String
}

public struct PathGeo: Codable, Sendable {
    /// Google encoded polyline, [lat, lng] at 1e-5
    public let p: String
    public let km: Double
}

// MARK: - Places

public struct Place: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case stay, food, sight, shop, station
    }

    public let id: String
    public let name: String
    public let ja: String?
    public let kind: Kind
    public let area: String
    public let lat: Double
    public let lng: Double
    /// plan, along, detour, alt
    public let role: String?
    public let dish: String?
    /// per person, "¥1.400–1.700"
    public let price: String?
    public let note: String?
    public let tips: String?
    public let closed: String?
    public let pay: Payment?
    public let tabelog: String?
    public let official: String?
    public let review: String?
    public let address: String?
    public let hours: String?
    public let rating: Double?
    public let ratingCount: Int?
    public let fee: String?
    public let bestTime: String?
    public let station: String?
    public let fujiView: String?
    public let fujiNote: String?
    @Many public var images: [Photo]
    public let menu: PlaceMenu?
    public let snack: Snack?
    public let store: Store?
    public let fujiSpot: FujiSpotInfo?
    /// the day research tied this place to (day number or an alternative day's key)
    public let day: String?
    public let category: String?
    /// the plan place a snack stop sits beside
    public let near: String?
    public let detourMin: Int?
    @Many public var uses: [Use]

    public var coordinate: Coordinate { Coordinate(lat, lng) }
    public var hero: Photo? { images.first }

    /// How this place is paid for, from the plan or the snack research.
    public var payment: Payment? { pay ?? snack?.pay }
}

public enum Payment: String, Codable, Sendable, CaseIterable {
    case cash, card, mixed
}

public struct Use: Codable, Sendable, Hashable {
    public let day: String
    public let at: String?
}

public struct Photo: Codable, Sendable, Hashable {
    public let kind: String?
    /// "commons/abc.webp" ships in the app bundle; otherwise an https URL
    public let src: String
    public let full: String?
    public let caption: String?
    public let credit: String?
    public let license: String?
    public let page: String?

    public var isBundled: Bool { !src.hasPrefix("http") }
}

/// Dishes researched for a restaurant (research/menus-*.json).
public struct PlaceMenu: Codable, Sendable {
    @Many public var items: [MenuItem]
    public let orderTip: String?
    public let ticketMachine: Bool?
    public let menuEn: Bool?
    @Many public var sources: [String]
}

public struct MenuItem: Codable, Sendable, Hashable {
    public enum Pick: String, Codable, Sendable {
        case signature, popular, value, light, side, dessert, drink
    }

    public let ja: String
    public let romaji: String?
    public let vi: String
    public let yen: Int?
    public let yenNote: String?
    public let pick: Pick
    public let note: String?
}

public struct Snack: Codable, Sendable {
    public struct Get: Codable, Sendable, Hashable {
        public let ja: String
        public let romaji: String?
        public let vi: String
        public let yen: Int?
    }

    public struct Rating: Codable, Sendable {
        public let url: String
        public let rating: Double?
        public let count: Int?
        public let award: String?
    }

    public let type: String
    @Many public var get: [Get]
    public let when: String?
    public let open: String?
    public let close: String?
    @Many public var closedDow: [Int]
    public let closedNote: String?
    public let queue: String?
    public let pay: Payment?
    public let tabelog: Rating?
    @Many public var social: [Social]
}

public struct Social: Codable, Sendable, Hashable {
    public let platform: String
    public let url: String
    public let note: String?
}

public struct Store: Codable, Sendable {
    public let chain: String
    public let city: String?
    public let open: String?
    public let close: String?
    @Many public var closedDow: [Int]
    public let taxFree: Bool?
    public let near: String?
    public let walkMin: Int?
    /// how the store fits the day's plan (the place's note is what the store is)
    public let plan: String?
    /// what to look for there
    @Many public var buy: [String]
    /// tax-free counter, payment, the floor to head for, the quiet hours
    public let advice: String?
}

public struct FujiSpotInfo: Codable, Sendable {
    public struct BusStop: Codable, Sendable {
        public let ja: String
        public let lat: Double
        public let lng: Double
        public let walkMin: Int?
    }

    public let area: String?
    public let type: String?
    public let fit: String?
    public let status: String?
    public let etiquette: String?
    public let access: [String: String]?
    public let busStop: BusStop?
    @Many public var social: [Social]
}

// MARK: - Days

public struct Day: Codable, Sendable, Identifiable {
    public var id: String { key }
    /// "1"…"12", or an alternative day's slug ("kawaguchiko")
    public let key: String
    public let n: Int
    /// set on an alternative day: the day it can replace
    public let replaces: Int?
    /// "2027-10-19", Japan date
    public let date: String
    public let dow: String
    public let title: String
    public let route: String
    public let stay: String?
    public let lead: String?
    public let walk: String?
    public let meals: Meals
    @Many public var trims: [String]
    public let alt: AltPlan?
    public let chapter: String?
    public let km: DayKm?
    public let items: [DayItem]
    @Many public var along: [Along]
    @Many public var slots: [String]

    public var isAlternative: Bool { replaces != nil }

    public var stops: [(index: Int, stop: Stop)] {
        items.enumerated().compactMap { i, it in
            if case .stop(let s) = it { return (i, s) }
            return nil
        }
    }
}

public struct Meals: Codable, Sendable {
    public let b: Int
    public let l: Int
    public let d: Int
    public let s: Int
    public var total: Int { b + l + d + s }
}

public struct DayKm: Codable, Sendable {
    public let rail: Double
    public let walk: Double
    public let road: Double
    public let water: Double
    public let air: Double
}

public struct AltPlan: Codable, Sendable {
    public let title: String
    public let text: String
    @Many public var places: [String]
}

public enum DayItem: Codable, Sendable {
    case stop(Stop)
    case move(Move)

    private enum CodingKeys: String, CodingKey { case type }

    public init(from decoder: any Decoder) throws {
        let type = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .type)
        switch type {
        case "stop": self = .stop(try Stop(from: decoder))
        default: self = .move(try Move(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .stop(let s):
            try c.encode("stop", forKey: .type)
            try s.encode(to: encoder)
        case .move(let m):
            try c.encode("move", forKey: .type)
            try m.encode(to: encoder)
        }
    }

    public var at: String? {
        switch self {
        case .stop(let s): s.at
        case .move(let m): m.at
        }
    }

    public var stop: Stop? {
        if case .stop(let s) = self { return s }
        return nil
    }

    public var move: Move? {
        if case .move(let m) = self { return m }
        return nil
    }

    /// The visit's id, written in the data: what records, reminders and fences hold on to.
    public var id: String {
        switch self {
        case .stop(let s): s.id
        case .move(let m): m.id
        }
    }
}

public struct Stop: Codable, Sendable {
    /// "s:<place>", or "s:<place>:<key>" when the day comes back to the place, "s::<key>" without a
    /// place; unique within the day, kept when the time or the order changes
    public let id: String
    public let at: String?
    public let place: String?
    public let title: String
    public let text: String?
    /// yen for two people
    public let cost: Int?
    public let optional: Bool?
    /// the number drawn on the map for this place
    public let n: Int?

    public var isOptional: Bool { optional ?? false }

    /// Leaving the bags or checking in: an errand with a time, never worth dropping or warning about.
    public var isErrand: Bool { title.hasPrefix("Gửi") || title.hasPrefix("Nhận phòng") }
}

public struct Move: Codable, Sendable {
    /// "m:<from>><to>", or with ":<key>" when the day repeats the pair; unique within the day. Not the
    /// leg's id: paths, rides and the records kept before item ids go by `leg.id`, which changes with
    /// the way walked.
    public let id: String
    public let at: String?
    public let leg: Leg
}

public struct Leg: Codable, Sendable, Identifiable {
    public let id: String
    public let line: String
    public let from: String
    public let to: String
    @Many public var via: [String]
    /// stated minutes, free text: "15–20", "1 giờ 40", "3–4 giờ, tính cả dừng"
    public let min: String?
    public let note: String?
    public let km: Double?
    /// slope-aware walking time (scripts/build-walk.mjs), walks only
    public let walk: WalkStats?
}

public struct WalkStats: Codable, Sendable {
    public let km: Double
    public let up: Double
    public let down: Double
    /// minutes on foot at the model pace, before overheads
    public let walkMin: Double
    /// walking plus a minute to get one's bearings plus platform-to-street time
    public let min: Int

    public init(km: Double, up: Double, down: Double, walkMin: Double, min: Int) {
        self.km = km
        self.up = up
        self.down = down
        self.walkMin = walkMin
        self.min = min
    }

    /// Minutes with the walking part scaled to a personal pace (1 = the model's 3.9 km/h).
    public func minutes(pace: Double) -> Double {
        if pace == 1 { return Double(min) }
        let overhead = max(0, Double(min) - walkMin)
        return overhead + walkMin / max(0.5, pace)
    }
}

public struct Along: Codable, Sendable {
    public struct Origin: Codable, Sendable {
        public let label: String
        public let lat: Double
        public let lng: Double
        public let onWalk: Bool
    }

    public struct Detour: Codable, Sendable {
        /// encoded polyline; absent when the place sits right on the way
        public let p: String?
        public let km: Double
        public let min: Int
        /// walk or car
        public let mode: String
        public let up: Double?
    }

    public let place: String
    /// straight line from the origin; absent when the day has no walk to start from
    public let km: Double?
    public let from: Origin?
    public let detour: Detour?
}

// MARK: - Rides

public struct Ride: Codable, Sendable, Identifiable {
    public enum Side: String, Codable, Sendable {
        case left, right, both, front, down
    }

    public struct Station: Codable, Sendable, Hashable {
        public let ja: String
        public let en: String
        /// along the ride, from where you board
        public let km: Double
        /// the train stops here
        public let stop: Bool
        /// board, alight, transfer, prev (the stop before yours)
        @Many public var marks: [String]

        public static func == (a: Station, b: Station) -> Bool { a.ja == b.ja && a.km == b.km }
        public func hash(into h: inout Hasher) {
            h.combine(ja)
            h.combine(km)
        }
    }

    public struct Event: Codable, Sendable {
        public let side: Side
        /// station indices
        public let from: Int
        public let to: Int
        public let what: String
        public let tip: String?
        public let fuji: Bool
        public let computed: Bool?
        public let src: String?
    }

    public struct Transfer: Codable, Sendable {
        public let at: String
        public let text: String
        public let idx: Int
    }

    public struct Alight: Codable, Sendable {
        public let prevSt: String
        public let announce: String?
        public let announceRomaji: String?
        public let text: String?
        public let idx: Int
    }

    public let id: String
    public let day: String
    public let at: String?
    public let legs: [String]
    public let color: String
    public let lineName: String
    public let fromName: String
    public let toName: String
    public let km: Double
    public let min: String?
    public let title: String
    public let train: String?
    public let seat: String?
    public let seatVerdict: String?
    public let stations: [Station]
    public let hidden: Int
    @Many public var events: [Event]
    @Many public var transfers: [Transfer]
    public let alight: Alight?
    public let onboard: String?
    public let board: String?
    public let pay: String?
    @Many public var sources: [String]
    public let researched: Bool
}

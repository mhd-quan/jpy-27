import Foundation

/// Everything around the plan (guide.json): phrasebook, money, shopping, stays, Fuji, bookings.
public struct Guide: Codable, Sendable {
    public let version: Int
    public let phrases: Phrasebook
    public let budget: Budget
    public let basket: Basket
    public let shopping: Shopping
    @Many public var stays: [StayPlan]
    @Many public var hunt: [Step]
    public let fuji: FujiGuide
    @Many public var passes: [Pass]
    @Many public var bookings: [Booking]
    @Many public var checks: [Check]
    @Many public var notes: [NoteGroup]

    public struct Step: Codable, Sendable, Hashable {
        public let title: String
        public let text: String
    }
}

// MARK: - Phrases

public struct Phrasebook: Codable, Sendable {
    @Many public var scenarios: [Scenario]
    @Many public var groups: [ScenarioGroup]
    @Many public var trip: [TripPhrase]
    @Many public var stations: [StationName]
}

public struct Scenario: Codable, Sendable, Identifiable {
    public let id: String
    public let vi: String
    public let hint: String?
    /// place kinds and tags this scenario fits: food, station, stay, order…
    @Many public var `for`: [String]
    @Many public var phrases: [Phrase]
    /// what staff are likely to say, with a reply
    @Many public var hear: [Heard]
}

public struct Phrase: Codable, Sendable, Identifiable, Hashable {
    public struct Example: Codable, Sendable, Hashable {
        public let ja: String
        public let romaji: String
    }

    public let id: String
    public let ja: String
    public let romaji: String
    public let vi: String
    public let note: String?
    /// a "{n}" placeholder in ja and romaji
    public let slot: String?
    public let example: Example?

    public init(id: String, ja: String, romaji: String, vi: String, note: String? = nil, slot: String? = nil, example: Example? = nil) {
        self.id = id
        self.ja = ja
        self.romaji = romaji
        self.vi = vi
        self.note = note
        self.slot = slot
        self.example = example
    }

    /// The sentence with its slot filled by the example, ready to show or speak.
    public var filledJa: String {
        guard let slot, let example else { return ja }
        return ja.replacingOccurrences(of: "{\(slot)}", with: example.ja)
    }

    public var filledRomaji: String {
        guard let slot, let example else { return romaji }
        return romaji.replacingOccurrences(of: "{\(slot)}", with: example.romaji)
    }
}

public struct Heard: Codable, Sendable, Hashable {
    public struct Reply: Codable, Sendable, Hashable {
        public let ja: String
        public let romaji: String
    }

    public let ja: String
    public let romaji: String
    public let vi: String
    public let reply: Reply?
}

public struct ScenarioGroup: Codable, Sendable, Hashable {
    public let title: String
    public let ids: [String]
}

public struct TripPhrase: Codable, Sendable, Hashable {
    public let use: String
    public let ja: String
    public let romaji: String
    public let vi: String
}

public struct StationName: Codable, Sendable, Hashable {
    public let romaji: String
    public let ja: String
}

// MARK: - Money

public struct Budget: Codable, Sendable {
    public struct Line: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let label: String
        public let yen: Int
        public let note: String
        public let color: String
    }

    public struct RateScenario: Codable, Sendable, Hashable {
        public let rate: Double
        public let note: String
    }

    public struct Saving: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let label: String
        public let yen: Int
    }

    public struct Fare: Codable, Sendable, Hashable {
        public let label: String
        public let yen: Int
    }

    @Many public var lines: [Line]
    @Many public var scenarios: [RateScenario]
    @Many public var savings: [Saving]
    @Many public var transport: [Fare]

    public var total: Int { lines.reduce(0) { $0 + $1.yen } }
}

public struct Basket: Codable, Sendable {
    public struct Item: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String
        public let qty: Int
        public let unit: Int
        public let `where`: String
        public let group: String
        public var total: Int { qty * unit }
    }

    public struct Group: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let label: String
    }

    @Many public var items: [Item]
    @Many public var groups: [Group]

    public var total: Int { items.reduce(0) { $0 + $1.total } }
}

// MARK: - Shopping

public struct Shopping: Codable, Sendable {
    public struct Slot: Codable, Sendable, Identifiable {
        public struct Route: Codable, Sendable {
            /// encoded polylines, one per stretch between stores
            public let p: [String]
            public let km: Double
            public let min: Int
        }

        public let id: String
        public let day: Int
        public let start: String?
        public let end: String?
        public let city: String?
        public let area: String?
        public let after: String?
        public let before: String?
        @Many public var stores: [String]
        public let focus: String?
        public let why: String?
        public let skipIf: String?
        public let route: Route?
        /// catalogue items these stores sell
        @Many public var items: [String]
    }

    public struct Category: Codable, Sendable, Identifiable {
        public let id: String
        public let vi: String
        @Many public var items: [CatalogItem]
    }

    public struct CatalogItem: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let name: String
        public let ja: String?
        public let brand: String?
        public let yen: Int?
        public let yenNote: String?
        public let why: String?
        public let tip: String?
        @Many public var `where`: [String]
        public let weightG: Int?
        public let src: String?

        public static func == (a: CatalogItem, b: CatalogItem) -> Bool { a.id == b.id }
        public func hash(into h: inout Hasher) { h.combine(id) }
    }

    public struct Chain: Codable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let vi: String?
        public let taxFreeMinYen: Int?
        public let src: String?
    }

    @Many public var slots: [Slot]
    @Many public var categories: [Category]
    @Many public var chains: [Chain]
    public let taxFree: String?
    @Many public var rules: [String]
}

// MARK: - Stays

public struct StayPlan: Codable, Sendable, Identifiable {
    public let id: String
    public let nights: String
    public let dates: String
    /// yen per night (the ryokan: per stay, two meals)
    public let target: Int
    public let range: String
    public let room: String
    public let good: String
    public let know: String
    public let switchAt: String
    public let around: StayAround?
}

public struct StayAround: Codable, Sendable {
    public struct Walk: Codable, Sendable, Identifiable {
        public struct Highlight: Codable, Sendable, Hashable {
            public let name: String
            public let ja: String?
            public let lat: Double
            public let lng: Double
            public let text: String?
            @Many public var images: [Photo]

            public static func == (a: Highlight, b: Highlight) -> Bool { a.name == b.name && a.lat == b.lat }
            public func hash(into h: inout Hasher) {
                h.combine(name)
                h.combine(lat)
            }
        }

        public let id: String
        public let title: String
        public let best: String?
        public let text: String
        public let minutes: Int?
        public let km: Double?
        /// encoded polyline of the loop
        public let p: String?
        public let walk: WalkStats?
        @Many public var highlights: [Highlight]
        /// where along the walk Fuji's summit is in line of sight (ryokan only)
        public let fuji: JSONValue?
    }

    public struct Amenity: Codable, Sendable, Hashable {
        public let name: String
        public let ja: String?
        /// konbini, supermarket, drugstore, laundry, cafe, bakery, sento, sight
        public let type: String
        public let lat: Double
        public let lng: Double
        public let text: String?
        public let hours: String?
        public let walkMin: Int?
        public let distanceM: Int?
        public let note: String?
    }

    public let area: String?
    @Many public var walks: [Walk]
    @Many public var around: [Amenity]
    @Many public var photos: [Photo]
    @Many public var sources: [String]
    public let fuji: JSONValue?
}

// MARK: - Fuji

public struct FujiGuide: Codable, Sendable {
    public struct Summit: Codable, Sendable {
        public let lat: Double
        public let lng: Double
        /// metres
        public let h: Double
        public var coordinate: Coordinate { Coordinate(lat, lng) }
    }

    /// A viewpoint with its sight line computed on terrain (scripts/build-fuji.mjs).
    public struct Spot: Codable, Sendable, Identifiable {
        public let id: String
        public let name: String?
        public let ja: String?
        public let lat: Double
        public let lng: Double
        public let day: String?
        public let role: String?
        public let km: Double
        public let bearing: Double
        /// ground elevation at the viewpoint, metres
        public let elev: Double
        public let visible: Bool
        /// metres of the mountain above the nearer horizon
        public let shownM: Double?
        public let heightDeg: Double?
        public let widthDeg: Double?
        /// distance to the ridge that hides the summit, when it is hidden
        public let blockKm: Double?
    }

    /// The horizon around the summit's bearing, for drawing the expected silhouette.
    public struct Panorama: Codable, Sendable {
        public let from: Double
        public let step: Double
        public let angles: [Double]
        public let summitAz: Double
    }

    public let summit: Summit
    @Many public var spots: [Spot]
    public let panoramas: [String: Panorama]
    public let research: JSONValue?
    public let kawaguchiko: JSONValue?
}

// MARK: - Before the trip

public struct Pass: Codable, Sendable, Hashable {
    public let name: String
    /// "Mua" or "Bỏ"
    public let verdict: String
    public let text: String
    public var recommended: Bool { verdict == "Mua" }
}

public struct Booking: Codable, Sendable, Hashable {
    /// ISO 8601 with +09:00, only when the rule pins an exact opening time
    public let at: String?
    public let title: String
    public let text: String
    public let rule: String

    public var date: Date? {
        guard let at else { return nil }
        return ISO8601DateFormatter().date(from: at)
    }
}

public struct Check: Codable, Sendable, Hashable {
    public let when: String
    public let text: String
}

public struct NoteGroup: Codable, Sendable, Identifiable {
    public struct Note: Codable, Sendable, Identifiable, Hashable {
        public let id: String
        public let title: String
        public let text: String
    }

    public let id: String
    public let title: String
    @Many public var notes: [Note]
}

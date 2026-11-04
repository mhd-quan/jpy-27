import Foundation
import SwiftUI
import TripKit

/// What the app and its widgets share through the App Group.
nonisolated enum Shared {
    /// From Info.plist (`JP27AppGroup`, the `JP27_APP_GROUP` build setting), so a build signed with
    /// someone else's provisioning profile uses the group that profile grants.
    static let appGroup = Bundle.main.object(forInfoDictionaryKey: "JP27AppGroup") as? String ?? "group.tech.delphyra.jp27"
    static let scheme = "jp27"
    static let widgetKind = "NextStop"

    /// The App Group's defaults: what the widget, the extension or work in the background reads
    /// (the clock offset, the snapshot, the pace, alarms, fences, downloads wanted). One instance,
    /// made once: it was made anew on every read, the clock's among them.
    ///
    /// A view's own preferences (appearance, the diagnostics switches, a flag a screen keeps) stay
    /// in `@AppStorage`, the app's standard defaults: nothing outside the app reads them. No key is
    /// in both; one moved across would lose what is already stored under it.
    nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: appGroup) ?? .standard

    static var container: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    /// Downscaled photos of each place, written by the app for the widgets (which cannot decode
    /// the full set within their memory budget).
    static var heroes: URL { container.appendingPathComponent("Heroes", isDirectory: true) }

    static func hero(_ placeID: String) -> URL { heroes.appendingPathComponent("\(placeID).jpg") }

    enum Key {
        /// alternative day keys the travellers chose ("kawaguchiko")
        static let alternatives = "alternatives"
        /// seconds added to the real clock, to rehearse a trip day before October 2027
        static let clockOffset = "clockOffset"
        static let snapshot = "snapshot"
        static let pace = "pace"
        /// 2 once the real records name every item by its id (`AppModel.loadRecords`)
        static let recordIDs = "records.ids"
        /// the location journal's switch (`journalEnabled`)
        static let journal = "journal.enabled"
        /// set once the location history from outside the trip was deleted (`AppModel.activate`)
        static let journalPurged = "journal.purged.v1"
        /// the stays iOS reported lately, without their coordinates (`StayMemory`)
        static let stays = "visits.seen"
    }

    static var alternatives: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.alternatives) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.alternatives) }
    }

    /// Read and written by the rehearsal clock's rule (`RehearsalClock.offset`): whole minutes, and
    /// 0 within a minute of the real clock. A value an older build stored (−0.3 s from a picker left
    /// at now, seconds on a rehearsal) reads by the same rule, in the app and in the widget.
    static var clockOffset: TimeInterval {
        get { RehearsalClock.offset(storedClockOffset) }
        set { defaults.set(RehearsalClock.offset(newValue), forKey: Key.clockOffset) }
    }

    /// The offset as it is stored, unread by the rule: only `AppModel.init` looks, for an offset
    /// of about 0 an older build left behind.
    static var storedClockOffset: TimeInterval { defaults.double(forKey: Key.clockOffset) }

    /// A rehearsal is running (`RehearsalClock`): what code without the model asks.
    static var rehearsing: Bool { RehearsalClock.isRehearsing(storedClockOffset) }

    /// Whether the location journal records stays and the walked trace (only during the trip,
    /// `JournalPolicy`). Off until switched on.
    static var journalEnabled: Bool {
        get { defaults.bool(forKey: Key.journal) }
        set { defaults.set(newValue, forKey: Key.journal) }
    }

    /// The trip's clock: real time, shifted when rehearsing.
    static var now: Date { Date().addingTimeInterval(clockOffset) }

    static var snapshot: Snapshot? {
        get { defaults.data(forKey: Key.snapshot).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } }
        set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.snapshot) }
    }

    static var pace: Double {
        let v = defaults.double(forKey: Key.pace)
        return v > 0 ? v : 1
    }
}

/// The app's live view of "what is next", handed to the widget: it knows what was marked done and
/// how late you run, which the widget's own plan clock cannot.
nonisolated struct Snapshot: Codable, Hashable, Sendable {
    var day: String
    /// the item (`DayItem.id`), which the widget finds on its own plan
    var itemID: String
    var title: String
    var placeID: String?
    var setOff: Date
    var begin: Date
    /// stop, departure, reservation
    var kind: String
    /// minutes behind the next fixed time, when behind
    var late: Int?
    var advice: String?
    var generated: Date
}

/// Deep links: jp27://place/owariya, jp27://walk/owariya, jp27://ride/<id>, jp27://day/4,
/// jp27://spend?place=owariya, jp27://journal/4
nonisolated enum DeepLink: Hashable, Sendable {
    case today
    case place(String)
    case walk(String)
    case ride(String)
    case day(String)
    case spend(place: String?)
    case journal(String)
    case menu(String)

    var url: URL {
        let s = Shared.scheme
        switch self {
        case .today: return URL(string: "\(s)://today")!
        case .place(let id): return URL(string: "\(s)://place/\(id)")!
        case .walk(let id): return URL(string: "\(s)://walk/\(id)")!
        case .ride(let id): return URL(string: "\(s)://ride/\(id)")!
        case .day(let key): return URL(string: "\(s)://day/\(key)")!
        case .spend(let place): return URL(string: "\(s)://spend" + (place.map { "?place=\($0)" } ?? ""))!
        case .journal(let key): return URL(string: "\(s)://journal/\(key)")!
        case .menu(let id): return URL(string: "\(s)://menu/\(id)")!
        }
    }

    init?(_ url: URL) {
        guard url.scheme == Shared.scheme, let host = url.host() else { return nil }
        let arg = url.pathComponents.dropFirst().first
        switch host {
        case "today": self = .today
        case "place": guard let arg else { return nil }; self = .place(arg)
        case "walk": guard let arg else { return nil }; self = .walk(arg)
        case "ride": guard let arg else { return nil }; self = .ride(arg)
        case "day": guard let arg else { return nil }; self = .day(arg)
        case "journal": guard let arg else { return nil }; self = .journal(arg)
        case "menu": guard let arg else { return nil }; self = .menu(arg)
        case "spend":
            let place = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "place" }?.value
            self = .spend(place: place)
        default: return nil
        }
    }
}

// MARK: - Colour

extension Color {
    /// "#RRGGBB" from the data (line colours, budget colours).
    nonisolated init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x8E8E93
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension Mode {
    /// SF Symbol for a way of moving: the bullet nose for the Shinkansen, a sailing ship for the
    /// Ashi pirate ship, a tunnel for the metro.
    nonisolated var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .train: "tram.fill"
        case .subway: "tram.fill.tunnel"
        case .shinkansen: "train.side.front.car"
        case .bus, .shuttle: "bus.fill"
        case .ferry: "ferry.fill"
        case .cruise: "sailboat.fill"
        case .ropeway: "cablecar.fill"
        case .cable: "cablecar"
        }
    }
}

extension Place.Kind {
    nonisolated var symbol: String {
        switch self {
        case .stay: "bed.double.fill"
        case .food: "fork.knife"
        case .sight: "binoculars.fill"
        case .shop: "bag.fill"
        case .station: "tram.fill"
        }
    }
}

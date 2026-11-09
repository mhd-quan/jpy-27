import Foundation

/// What the app needs to be usable with no signal, in the order the offline page lists it.
public enum ReadyItem: String, CaseIterable, Codable, Sendable {
    /// every map area, "Toàn tuyến" with them, complete for the build the map reads
    case maps
    /// each day's map picture on disk, at the page size measured last
    case dayMaps
    /// the restaurants' and hotels' photos on disk
    case photos
    /// the Fuji terrain pictures, light and dark, of every viewpoint card and area hero
    case fuji
    /// the cloud forecasts of the summit and every viewpoint, fetched in the last 12 hours
    case forecasts
    /// the Japanese–Vietnamese translation pack
    case translation
    /// the Japanese speech pack
    case speech
}

/// Where one item stands.
public enum ReadyState: Sendable, Equatable {
    case ready
    /// not all there: how many of how many, when they can be counted
    case missing(done: Int?, total: Int?)
    /// downloading, 0…1
    case working(Double)
    case waitingForNetwork
    /// why
    case failed(String)
    /// this phone cannot have it: why. It never counts as missing.
    case unsupported(String)
    /// it cannot be counted, nor fetched, until a page has been opened once: which
    case needsSetup(String)
}

/// The rules of the readiness list: the one line Settings' main page says of it, the order "Tải tất cả" takes, how
/// fresh a forecast must be, and the weeks "Cần xem" speaks of it.
public enum Readiness {
    /// a forecast fetched this long ago or less is fresh
    public static let forecastFresh: TimeInterval = 43_200

    /// the summary when everything is there
    public static let ready = "Sẵn sàng"

    /// "Đang tải 42%" while a download runs; else "Cần tải lại" when downloaded maps are of an old build; else
    /// "Thiếu N mục", counting every item that is neither ready nor unsupported (one still to be read counts:
    /// an unread state never says ready); else "Sẵn sàng".
    public static func summary(_ s: [ReadyItem: ReadyState], mapsStale: Bool, downloading: Double?) -> String {
        if let downloading { return "Đang tải \(percent(downloading))%" }
        if mapsStale { return "Cần tải lại" }
        let missing = ReadyItem.allCases.filter { !settled(s[$0]) }.count
        return missing == 0 ? ready : "Thiếu \(missing) mục"
    }

    /// What "Tải tất cả" fetches, in its order: the language packs first (asked while the page is open, so the
    /// system's prompt can show), then the photos, the maps, the day maps, Fuji and the forecasts. An item ready
    /// or unsupported is left out, and so is one that needs a page opened first (nothing to fetch it at); one not
    /// read yet is kept.
    public static func plan(_ s: [ReadyItem: ReadyState]) -> [ReadyItem] {
        let order: [ReadyItem] = [.translation, .speech, .photos, .maps, .dayMaps, .fuji, .forecasts]
        return order.filter { item in
            switch s[item] {
            case .ready?, .unsupported?, .needsSetup?: false
            case nil, .missing?, .working?, .waitingForNetwork?, .failed?: true
            }
        }
    }

    /// Ready when every forecast was fetched `forecastFresh` ago or less (by the real clock); else how many are.
    public static func forecasts(fetched: [Date?], now: Date) -> ReadyState {
        let fresh = fetched.filter { date in
            guard let date else { return false }
            return now.timeIntervalSince(date) <= forecastFresh
        }.count
        return fresh == fetched.count ? .ready : .missing(done: fresh, total: fetched.count)
    }

    /// From midnight in Japan 14 days before the trip's first day to the end of its last day: when "Cần xem" says
    /// what is not ready. `now` is the real clock, never the rehearsal's.
    public static func watching(now: Date, start: String, end: String) -> Bool {
        guard let first = TripTime.midnight(start), let last = TripTime.midnight(end),
              let from = TripTime.calendar.date(byAdding: .day, value: -14, to: first),
              let until = TripTime.calendar.date(byAdding: .day, value: 1, to: last) else { return false }
        return from <= now && now < until
    }

    /// Whether a day's map picture counts the day ready, from what is on disk (R-640): the picture in the scheme its
    /// page is in now (`own`), or the same picture in the other scheme (`other`). A day whose page sets its own scheme
    /// (a photograph's colour, or Giao diện on Sáng or Tối) needs `own`. A day whose page follows the system's light and
    /// dark (no photograph, Giao diện on "Tự động") turns with sunrise and sunset, and either scheme counts for it: the
    /// day page draws it live from the packs with no signal, so Tải tất cả draws nothing for it while one is there.
    public static func dayMapReady(own: Bool, other: Bool, followsSystem: Bool) -> Bool {
        own || (followsSystem && other)
    }

    /// ready, or never to be: what does not count as missing (here, and at the end of Tải tất cả: `OfflineJob.result`)
    static func settled(_ state: ReadyState?) -> Bool {
        switch state {
        case .ready?, .unsupported?: true
        case nil, .missing?, .working?, .waitingForNetwork?, .failed?, .needsSetup?: false
        }
    }

    /// 0…100, floored (99 until it is all there); a value out of range or not a number is held to the range. The
    /// millionth added keeps 0.57 at 57 (× 100 it is 56.999… in binary), far below a step a download could show.
    private static func percent(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int((min(1, max(0, fraction)) * 100 + 1e-6).rounded(.down))
    }
}

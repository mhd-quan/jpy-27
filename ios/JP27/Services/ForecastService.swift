import CoreLocation
import Foundation
import Observation
import TripKit
import WeatherKit

/// Hourly cloud cover from WeatherKit, at Fuji's summit and at the places you will look from.
/// Each forecast is kept on disk so the last one still shows without signal.
@Observable final class ForecastService {
    nonisolated struct Hour: Codable, Hashable, Identifiable, Sendable {
        var id: Date { date }
        let date: Date
        /// 0…1
        let cloud: Double
        let visibilityKm: Double
        let symbol: String
        let rain: Double
    }

    nonisolated struct Series: Codable, Sendable {
        let fetched: Date
        let hours: [Hour]
    }

    private(set) var series: [String: Series] = [:]
    private(set) var attribution: WeatherAttribution?
    private(set) var failed = false

    private var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Forecast", isDirectory: true)
    }

    /// Hours for a key ("summit", or a place id), refreshed when older than an hour and online.
    func hours(_ key: String, at c: Coordinate, online: Bool) async -> [Hour] {
        if series[key] == nil, let disk = load(key) { series[key] = disk }
        if let s = series[key], Date().timeIntervalSince(s.fetched) < 3600 || !online { return s.hours }
        do {
            let forecast = try await WeatherService.shared.weather(for: CLLocation(latitude: c.lat, longitude: c.lng), including: .hourly)
            let hours = forecast.forecast.prefix(72).map { h in
                Hour(date: h.date, cloud: h.cloudCover, visibilityKm: h.visibility.converted(to: .kilometers).value, symbol: h.symbolName, rain: h.precipitationChance)
            }
            let s = Series(fetched: Date(), hours: Array(hours))
            series[key] = s
            save(key, s)
            failed = false
            if attribution == nil { attribution = try? await WeatherService.shared.attribution }
            return s.hours
        } catch {
            failed = true
            return series[key]?.hours ?? []
        }
    }

    /// Is the summit likely clear: low cloud at the summit and at the viewpoint, good visibility.
    static func clearChance(summit: Hour?, here: Hour?) -> Double? {
        guard let summit else { return nil }
        let a = 1 - summit.cloud
        let b = here.map { 1 - $0.cloud * 0.6 } ?? 1
        let v = here.map { min(1, $0.visibilityKm / 40) } ?? 1
        return max(0, min(1, a * b * v))
    }

    private func load(_ key: String) -> Series? {
        (try? Data(contentsOf: folder.appendingPathComponent("\(key).json"))).flatMap { try? JSONDecoder().decode(Series.self, from: $0) }
    }

    private func save(_ key: String, _ s: Series) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(s).write(to: folder.appendingPathComponent("\(key).json"))
    }
}

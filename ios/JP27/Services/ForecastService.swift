import CoreLocation
import Foundation
import Observation
import TripKit
import WeatherKit

/// Hourly cloud cover at Fuji's summit and at the places you will look from. WeatherKit when the
/// build carries its entitlement; Open-Meteo otherwise, or when WeatherKit refuses (a profile without
/// WeatherKit signs fine but every request fails). Each forecast is kept on disk so the last one still
/// shows without signal, with the source it came from for the attribution.
///
/// Only a refusal sets WeatherKit aside for the session. A dropped connection or a timeout says
/// nothing about WeatherKit: that request goes to Open-Meteo, and WeatherKit is tried again after a
/// few minutes.
@Observable final class ForecastService {
    nonisolated enum Source: String, Codable, Sendable {
        case weatherKit, openMeteo
    }

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
        /// nil in forecasts cached before there was a second source: those came from WeatherKit
        var source: Source?
    }

    private(set) var series: [String: Series] = [:]
    private(set) var attribution: WeatherAttribution?
    private(set) var failed = false
    /// Off when the build was signed without the WeatherKit entitlement (Info.plist `JP27WeatherKit`),
    /// or once WeatherKit has refused this session (`failedWeatherKit`).
    private var weatherKit = (Bundle.main.object(forInfoDictionaryKey: "JP27WeatherKit") as? String) != "NO"
    /// WeatherKit rests until then after a failure, so a bad connection is not asked again and again
    private var weatherKitRests = Date.distantPast
    /// failures in a row that were not the network's
    private var refusals = 0

    private var folder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Forecast", isDirectory: true)
    }

    /// Hours for a key ("summit", or a place id), refreshed when older than an hour and online.
    func hours(_ key: String, at c: Coordinate, online: Bool) async -> [Hour] {
        if series[key] == nil, let disk = load(key) { series[key] = disk }
        if let s = series[key], Date().timeIntervalSince(s.fetched) < 3600 || !online { return s.hours }
        if weatherKit, Date() >= weatherKitRests {
            do {
                let s = Series(fetched: Date(), hours: try await Self.fromWeatherKit(c), source: .weatherKit)
                refusals = 0
                if attribution == nil { attribution = try? await WeatherService.shared.attribution }
                return keep(s, as: key)
            } catch {
                failedWeatherKit(error)
            }
        }
        do {
            return keep(Series(fetched: Date(), hours: try await Self.fromOpenMeteo(c), source: .openMeteo), as: key)
        } catch {
            failed = true
            return series[key]?.hours ?? []
        }
    }

    /// After a WeatherKit failure: rest a few minutes whatever it was; set WeatherKit aside for the
    /// session when it said no (permission denied, which a build without the entitlement gets every
    /// time), or failed twice in a row for a reason that was not the network.
    private func failedWeatherKit(_ error: any Error) {
        weatherKitRests = Date().addingTimeInterval(5 * 60)
        if let e = error as? WeatherError, case .permissionDenied = e {
            weatherKit = false
            return
        }
        guard !Self.isNetwork(error) else { return }
        refusals += 1
        if refusals >= 2 { weatherKit = false }
    }

    /// A failure of the connection, not of the service: offline, a timeout, a cancelled request.
    nonisolated static func isNetwork(_ error: any Error) -> Bool {
        if error is URLError || error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain { return true }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError, under.domain == NSURLErrorDomain { return true }
        return false
    }

    /// The source of what is on screen for `key`.
    func source(_ key: String) -> Source? {
        series[key].map { $0.source ?? .weatherKit }
    }

    private func keep(_ s: Series, as key: String) -> [Hour] {
        series[key] = s
        save(key, s)
        failed = false
        return s.hours
    }

    private static func fromWeatherKit(_ c: Coordinate) async throws -> [Hour] {
        let forecast = try await WeatherService.shared.weather(for: CLLocation(latitude: c.lat, longitude: c.lng), including: .hourly)
        return forecast.forecast.prefix(72).map { h in
            Hour(date: h.date, cloud: h.cloudCover, visibilityKm: h.visibility.converted(to: .kilometers).value, symbol: h.symbolName, rain: h.precipitationChance)
        }
    }

    /// Open-Meteo's hourly forecast (free, no key, CC BY 4.0): cloud cover, visibility, rain chance
    /// and the WMO weather code, for the next three days.
    private static func fromOpenMeteo(_ c: Coordinate) async throws -> [Hour] {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(c.lat)),
            URLQueryItem(name: "longitude", value: String(c.lng)),
            URLQueryItem(name: "hourly", value: "cloud_cover,visibility,precipitation_probability,weather_code"),
            URLQueryItem(name: "forecast_days", value: "3"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
        ]
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let h = try JSONDecoder().decode(OpenMeteo.self, from: data).hourly
        return h.time.indices.compactMap { i in
            guard let cloud = h.cloud_cover[safe: i] ?? nil else { return nil }
            return Hour(
                date: Date(timeIntervalSince1970: h.time[i]),
                cloud: cloud / 100,
                visibilityKm: ((h.visibility[safe: i] ?? nil) ?? 20_000) / 1000,
                symbol: OpenMeteo.symbol((h.weather_code[safe: i] ?? nil) ?? 0),
                rain: ((h.precipitation_probability[safe: i] ?? nil) ?? 0) / 100
            )
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

    private nonisolated struct OpenMeteo: Decodable {
        struct Hourly: Decodable {
            let time: [TimeInterval]
            let cloud_cover: [Double?]
            let visibility: [Double?]
            let precipitation_probability: [Double?]
            let weather_code: [Int?]
        }

        let hourly: Hourly

        /// WMO weather code → SF Symbol, close to what WeatherKit's `symbolName` gives.
        static func symbol(_ code: Int) -> String {
            switch code {
            case 0: "sun.max"
            case 1, 2: "cloud.sun"
            case 3: "cloud"
            case 45, 48: "cloud.fog"
            case 51...57: "cloud.drizzle"
            case 61...67: "cloud.rain"
            case 71...77, 85, 86: "cloud.snow"
            case 80...82: "cloud.heavyrain"
            case 95...99: "cloud.bolt.rain"
            default: "cloud"
            }
        }
    }

    private func load(_ key: String) -> Series? {
        (try? Data(contentsOf: folder.appendingPathComponent("\(key).json"))).flatMap { try? JSONDecoder().decode(Series.self, from: $0) }
    }

    private func save(_ key: String, _ s: Series) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(s).write(to: folder.appendingPathComponent("\(key).json"))
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

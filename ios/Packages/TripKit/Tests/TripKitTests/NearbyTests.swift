import Foundation
import Testing
@testable import TripKit

/// The day's planned place a new expense starts on: the nearest of the day's stops within 150 m of
/// you, never a station (the expense editor's guess).
@Suite struct PlannedStopTests {
    let store = Bundle_.store

    /// The day's stops that are not stations, as places.
    private func places(_ day: Day) -> [Place] {
        day.stops.compactMap { store.place($0.stop.place) }.filter { $0.kind != .station }
    }

    /// The non-station stops of `day` within `km` of `point`, other than `except`.
    private func others(near point: Coordinate, on day: Day, within km: Double, except: String? = nil) -> [Place] {
        places(day).filter { $0.id != except && Geo.km($0.coordinate, point) <= km }
    }

    /// A day and one of its non-station stops with no other stop within `clear` km of `probe(place)`.
    private func lone(clear: Double, probe: (Place) -> Coordinate = { $0.coordinate }) -> (Day, Place)? {
        for day in store.trip.days {
            for p in places(day) where others(near: probe(p), on: day, within: clear, except: p.id).isEmpty {
                return (day, p)
            }
        }
        return nil
    }

    @Test func theDistanceIsAHundredAndFiftyMetres() {
        #expect(Nearby.plannedStopKm == 0.15)
    }

    @Test func standingOnAStopNamesIt() throws {
        let (day, p) = try #require(lone(clear: 0.3))
        #expect(Nearby.plannedStop(near: p.coordinate, day: day, store: store) == p.id)
    }

    @Test func aHundredMetresOffStillNamesIt() throws {
        let off: (Place) -> Coordinate = { Coordinate($0.coordinate.lat + 0.0009, $0.coordinate.lng) }
        let (day, p) = try #require(lone(clear: 0.3, probe: off))
        let probe = off(p)
        #expect(Geo.km(probe, p.coordinate) > 0.09 && Geo.km(probe, p.coordinate) < 0.11)
        #expect(Nearby.plannedStop(near: probe, day: day, store: store) == p.id)
    }

    @Test func twoHundredMetresOffNamesNothing() throws {
        let off: (Place) -> Coordinate = { Coordinate($0.coordinate.lat + 0.0018, $0.coordinate.lng) }
        let (day, p) = try #require(lone(clear: 0.3, probe: off))
        let probe = off(p)
        #expect(Geo.km(probe, p.coordinate) > 0.19 && Geo.km(probe, p.coordinate) < 0.21)
        // nothing else of the day is in range either: nil is the distance's doing
        try #require(others(near: probe, on: day, within: 0.15).isEmpty)
        #expect(Nearby.plannedStop(near: probe, day: day, store: store) == nil)
    }

    @Test func aStationIsNeverNamed() throws {
        var found: (Day, Place)?
        for day in store.trip.days where found == nil {
            for s in day.stops.compactMap({ store.place($0.stop.place) }) where s.kind == .station {
                if others(near: s.coordinate, on: day, within: 0.15).isEmpty { found = (day, s); break }
            }
        }
        let (day, station) = try #require(found)
        #expect(Nearby.plannedStop(near: station.coordinate, day: day, store: store) == nil)
    }

    @Test func theNearerOfTwoIsNamed() throws {
        // two stops of one day under 210 m apart; standing a third of the way from one toward the other,
        // so both are within 150 m
        var found: (Day, Place, Place)?
        for day in store.trip.days where found == nil {
            let ps = places(day)
            for a in ps {
                if let b = ps.first(where: { $0.id != a.id && Geo.km(a.coordinate, $0.coordinate) < 0.21 && Geo.km(a.coordinate, $0.coordinate) > 0.05 }) {
                    found = (day, a, b)
                    break
                }
            }
        }
        let (day, a, b) = try #require(found)
        let probe = Coordinate(a.coordinate.lat + (b.coordinate.lat - a.coordinate.lat) / 3,
                               a.coordinate.lng + (b.coordinate.lng - a.coordinate.lng) / 3)
        // b is within range too, so the nearer one has to be chosen, not the only one
        #expect(Geo.km(probe, b.coordinate) <= Nearby.plannedStopKm)
        let nearest = try #require(places(day).min { Geo.km($0.coordinate, probe) < Geo.km($1.coordinate, probe) })
        #expect(nearest.id == a.id)
        #expect(Nearby.plannedStop(near: probe, day: day, store: store) == a.id)
        let flipped = Coordinate(b.coordinate.lat + (a.coordinate.lat - b.coordinate.lat) / 3,
                                 b.coordinate.lng + (a.coordinate.lng - b.coordinate.lng) / 3)
        #expect(Nearby.plannedStop(near: flipped, day: day, store: store) == b.id)
    }
}

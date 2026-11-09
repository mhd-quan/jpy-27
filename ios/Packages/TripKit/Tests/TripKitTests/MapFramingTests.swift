import Foundation
import Testing
@testable import TripKit

/// How the app frames a map of some points, the live map and its picture alike. The coordinates are
/// chosen so every sum, half and difference below is exact in binary: the expectations are exact values.
@Suite struct MapFramingTests {
    /// 2⁻¹¹, 2⁻¹⁰, 2⁻⁹ degrees: about 54 m, 109 m and 217 m of latitude
    private let tiny = 0.000_488_281_25
    private let small = 0.000_976_562_5
    private let short = 0.001_953_125

    @Test func nothingIsNotFramed() {
        #expect(MapFraming.of([]) == nil)
    }

    @Test func onePlaceIsCentred() {
        let ueno = Coordinate(35.7141, 139.7774)
        #expect(MapFraming.of([ueno]) == .point(ueno))
    }

    @Test func placesAFewMetresApartAreOnePlace() {
        // less than 0.002° apart both ways: centred on the middle of them
        let pts = [Coordinate(35.5 - tiny, 139.5 - tiny), Coordinate(35.5 + tiny, 139.5 + tiny), Coordinate(35.5, 139.5 + tiny)]
        #expect(MapFraming.of(pts) == .point(Coordinate(35.5, 139.5)))
    }

    @Test func twoThousandthsOfADegreeIsAnArea() {
        // exactly 0.002° apart one way (at 0°, where the difference is exactly 0.002): not "less than",
        // so an area, grown to the least span around the middle
        let mid = 0.002 / 2
        #expect(MapFraming.of([Coordinate(0, 0), Coordinate(0.002, 0)])
            == .area(sw: Coordinate(mid - 0.0028, -0.0034), ne: Coordinate(mid + 0.0028, 0.0034)))
        #expect(MapFraming.of([Coordinate(0, 0), Coordinate(0, 0.002)])
            == .area(sw: Coordinate(-0.0028, mid - 0.0034), ne: Coordinate(0.0028, mid + 0.0034)))
        // and just under it, both ways: one place
        #expect(MapFraming.of([Coordinate(0, 0), Coordinate(0.0019, 0.0019)]) == .point(Coordinate(0.0019 / 2, 0.0019 / 2)))
    }

    @Test func aWideSpreadIsFramedWhole() {
        let pts = [Coordinate(35, 139), Coordinate(35.25, 139.75), Coordinate(36, 140)]
        #expect(MapFraming.of(pts) == .area(sw: Coordinate(35, 139), ne: Coordinate(36, 140)))
    }

    @Test func aShortWalkIsAtLeastSixHundredMetresAcross() {
        // 0.00195° tall (under 0.002) and 0.0039° wide (over): an area, each half-span grown to the least,
        // 0.0028° of latitude and 0.0034° of longitude, around the middle
        let pts = [Coordinate(35.5 - small, 139.5 - short), Coordinate(35.5 + small, 139.5 + short)]
        #expect(MapFraming.of(pts) == .area(sw: Coordinate(35.5 - 0.0028, 139.5 - 0.0034), ne: Coordinate(35.5 + 0.0028, 139.5 + 0.0034)))
    }

    @Test func aLonePlaceIsAtStreetLevel() {
        #expect(MapFraming.pointZoom == 15.5)
    }
}

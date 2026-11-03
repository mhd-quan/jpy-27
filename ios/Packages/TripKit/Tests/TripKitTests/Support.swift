import Foundation
@testable import TripKit

/// The JSON the app ships, read straight from the repository.
enum Bundle_ {
    static let resources: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TripKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TripKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // ios

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: resources.appendingPathComponent(path))
    }

    static let store: TripStore = {
        try! TripStore(tripJSON: data("JP27/Resources/Trip/trip.json"), guideJSON: data("JP27/Resources/Trip/guide.json"))
    }()

    static func fixture(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }
}

extension TripStore {
    /// The shipped plan with `edit` applied to its JSON first: a plan the data does not have, for a
    /// test that needs one (a stop moved, a time changed).
    static func patched(_ edit: (inout [String: Any]) throws -> Void) throws -> TripStore {
        let raw = try JSONSerialization.jsonObject(with: Bundle_.data("JP27/Resources/Trip/trip.json"))
        guard var trip = raw as? [String: Any] else { throw CocoaError(.coderReadCorrupt) }
        try edit(&trip)
        return try TripStore(tripJSON: JSONSerialization.data(withJSONObject: trip), guideJSON: Bundle_.data("JP27/Resources/Trip/guide.json"))
    }
}

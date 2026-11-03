import ActivityKit
import Foundation

/// The Live Activity shown while riding: the next station, when to get ready to alight, which window
/// Fuji is in, and where the walk goes after.
nonisolated struct RideAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// next station the train calls at
        var next: String
        var nextJa: String
        var stopsLeft: Int
        var progress: Double
        /// expected arrival at the end of the ride
        var arrival: Date?
        /// "left" or "right" while Fuji is in line of sight
        var fuji: String?
        /// what is outside now, short
        var view: String?
        /// the stop before yours has been passed
        var alight: Bool
        var arrived: Bool
    }

    var rideID: String
    var line: String
    /// "#RRGGBB"
    var color: String
    var mode: String
    var from: String
    var to: String
    var toJa: String
    /// "まもなく、箱根湯本です。" — what the train will announce
    var announce: String?
    /// the place the plan walks to after this ride
    var walkTo: String?
    var walkToID: String?
}

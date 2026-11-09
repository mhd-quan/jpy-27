import TripKit
import UIKit

/// The one place the screen is kept from locking itself (the application's idle timer, set below), for
/// every reason at once (`AwakeReasons`): the phrase card held up to staff, a ride followed with Settings › Giữ
/// màn hình sáng khi đi tàu on. Turning one reason off leaves the others.
enum KeepAwake {
    /// Settings › Trải nghiệm › Giữ màn hình sáng khi đi tàu (`AppModel.keepAwakeOnRide`), off by default
    nonisolated static let rideKey = "ride.keepAwake"

    private static var reasons = AwakeReasons()

    static func set(_ r: AwakeReasons.Reason, _ on: Bool) {
        reasons.set(r, on)
        UIApplication.shared.isIdleTimerDisabled = reasons.keepsAwake
    }
}

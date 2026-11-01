// swift-tools-version: 6.0
// The trip's logic with no UI and no Apple-only frameworks: models for the bundled JSON, the plan
// clock (a port of scripts/check-plan.mjs), the late-schedule replanner, ride tracking, menu
// matching and money. It builds and tests on Linux as well as in the app.
import PackageDescription

let package = Package(
    name: "TripKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "TripKit", targets: ["TripKit"]),
    ],
    targets: [
        .target(name: "TripKit"),
        .testTarget(name: "TripKitTests", dependencies: ["TripKit"], resources: [.copy("Fixtures")]),
    ]
)

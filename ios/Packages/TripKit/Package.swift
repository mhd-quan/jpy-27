// swift-tools-version: 6.2
// The trip's logic with no UI and no Apple-only frameworks: models for the bundled JSON, the plan
// clock (a port of scripts/check-plan.mjs), the late-schedule replanner, ride tracking, menu
// matching and money. It builds and tests on Linux as well as in the app.
import PackageDescription

// The app's concurrency rules (approachable concurrency in project.yml), so the same code means the
// same thing on both sides: a `nonisolated async` function runs on its caller's actor, and only
// `@concurrent` sends work off it. No default MainActor isolation, unlike the app: TripKit is value
// types that the widget and the app's `nonisolated` code call synchronously; the few classes that
// hold state between calls say `@MainActor` themselves.
let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "TripKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "TripKit", targets: ["TripKit"]),
    ],
    targets: [
        .target(name: "TripKit", swiftSettings: concurrency),
        .testTarget(name: "TripKitTests", dependencies: ["TripKit"], resources: [.copy("Fixtures")], swiftSettings: concurrency),
    ]
)

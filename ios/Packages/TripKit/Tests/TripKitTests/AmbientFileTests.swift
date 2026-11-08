import Testing
@testable import TripKit

/// The names of the album pictures in `Caches/Ambient` (the app's `PhotoCache.ambient`): found again on every
/// launch of one build, never read by another build (Caches outlive an update; ruling R-255).
@Suite struct AmbientFileTests {
    let key = "commons/kinkakuji.jpg@amb@402x524"

    @Test func sameBuildFindsItAgain() {
        #expect(AmbientFile.name(key: key, build: "41") == AmbientFile.name(key: key, build: "41"))
    }

    @Test func newBuildNewName() {
        #expect(AmbientFile.name(key: key, build: "41") != AmbientFile.name(key: key, build: "42"))
        #expect(AmbientFile.name(key: key, build: "41") != AmbientFile.name(key: key, build: ""))
    }

    @Test func otherBoxOtherName() {
        #expect(AmbientFile.name(key: key, build: "41") != AmbientFile.name(key: "commons/kinkakuji.jpg@amb@402x525", build: "41"))
    }

    /// The key and the build are closed off from each other: "ab" then "c" is not "a" then "bc".
    @Test func partsAreClosedOff() {
        #expect(AmbientFile.name(key: "x@amb@1x1", build: "2") != AmbientFile.name(key: "x@amb@1x", build: "12"))
    }

    @Test func shape() {
        let name = AmbientFile.name(key: key, build: "41")
        #expect(name.hasPrefix("a1-"))
        #expect(name.hasSuffix(".heic"))
        let middle = name.dropFirst(3).dropLast(5)
        #expect(!middle.isEmpty)
        #expect(middle.allSatisfy { ("0"..."9").contains($0) || ("a"..."z").contains($0) })
    }
}

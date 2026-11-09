import Foundation
import Testing
@testable import TripKit

/// The Fuji terrain's picture (`FujiTerrainSnapshot` in the app): its name in `Application Support/Fuji`, the
/// fingerprint kept beside it that tells a stale one from the right one, the launch trim, and when the live map goes
/// under the picture and the picture comes off it.
@Suite struct TerrainPictureTests {
    private let summit = Coordinate(35.36064, 138.72743)
    private let camera = TerrainPicture.Camera(center: Coordinate(35.25, 138.95), distance: 52_000, heading: 308, pitch: 58)
    private let spots = [
        TerrainPicture.Spot(id: "owakudani", coordinate: Coordinate(35.2425, 139.0198)),
        TerrainPicture.Spot(id: "sounzan", coordinate: Coordinate(35.2489, 139.0269)),
    ]

    // MARK: Names

    @Test func stemIsTheKindTheIdTheSizeTheScaleAndTheScheme() {
        #expect(TerrainPicture.stem(kind: .area, id: "4", width: 402, height: 480, scale: 3, dark: true) == "area-4-402x480@3-dark")
        #expect(TerrainPicture.stem(kind: .spot, id: "satta-pass", width: 361, height: 220, scale: 2, dark: false)
            == "spot-satta-pass-361x220@2-light")
        #expect(TerrainPicture.stem(kind: .area, id: "kawaguchiko", width: 402, height: 480, scale: 3, dark: false)
            == "area-kawaguchiko-402x480@3-light")
    }

    @Test func stemRoundsTheSizeToThePointAndWritesAPartScale() {
        #expect(TerrainPicture.stem(kind: .area, id: "all", width: 402.4, height: 479.6, scale: 3, dark: false) == "area-all-402x480@3-light")
        #expect(TerrainPicture.stem(kind: .area, id: "all", width: 402.5, height: 480, scale: 2.5, dark: false) == "area-all-403x480@2.5-light")
        #expect(TerrainPicture.stem(kind: .area, id: "all", width: 402, height: 480, scale: 2.625, dark: false) == "area-all-402x480@2.63-light")
        #expect(TerrainPicture.stem(kind: .area, id: "all", width: 402, height: 480, scale: 1.05, dark: false) == "area-all-402x480@1.05-light")
    }

    @Test func stemIsNilForAnEmptySizeOrScale() {
        #expect(TerrainPicture.stem(kind: .area, id: "4", width: 0.4, height: 480, scale: 3, dark: false) == nil)
        #expect(TerrainPicture.stem(kind: .area, id: "4", width: 402, height: .infinity, scale: 3, dark: false) == nil)
        #expect(TerrainPicture.stem(kind: .area, id: "4", width: 402, height: 480, scale: 0, dark: false) == nil)
        #expect(TerrainPicture.stem(kind: .area, id: "4", width: .nan, height: 480, scale: 3, dark: false) == nil)
    }

    @Test func anIdIsMadeSafeAndKindsNeverMeet() {
        // an area and a viewpoint of the same id are two names; an id's odd bytes never make a "/" or a "."
        #expect(TerrainPicture.stem(kind: .area, id: "kawaguchiko", width: 10, height: 10, scale: 1, dark: false)
            != TerrainPicture.stem(kind: .spot, id: "kawaguchiko", width: 10, height: 10, scale: 1, dark: false))
        #expect(TerrainPicture.stem(kind: .spot, id: "a/b.c", width: 10, height: 10, scale: 1, dark: false) == "spot-a_2Fb_2Ec-10x10@1-light")
        #expect(TerrainPicture.name(kind: .spot, id: "a/b.c") == "spot-a_2Fb_2Ec")
        #expect(TerrainPicture.name(kind: .area, id: "4") == "area-4")
    }

    @Test func parseReadsOnlyTheNamesThisCacheMakes() {
        #expect(TerrainPicture.parse("area-4-402x480@3-dark.heic") == TerrainPicture.FileName(stem: "area-4-402x480@3-dark", ext: "heic"))
        #expect(TerrainPicture.parse("spot-satta-pass-361x220@2.5-light.json") == TerrainPicture.FileName(stem: "spot-satta-pass-361x220@2.5-light", ext: "json"))
        #expect(TerrainPicture.parse("spot-fs-oishi-park-361x220@3-light.jpg") == TerrainPicture.FileName(stem: "spot-fs-oishi-park-361x220@3-light", ext: "jpg"))
        // every name `stem` makes reads back
        let made = TerrainPicture.stem(kind: .spot, id: "a/b.c", width: 361, height: 220, scale: 2.63, dark: true)!
        #expect(TerrainPicture.parse(made + ".heic")?.stem == made)
        for name in [
            "area-4-402x480@3-dark.png", // another kind of file
            "area-4-402x480@3-dusk.heic", // not a scheme
            "trail-4-402x480@3-dark.heic", // not a kind
            "area--402x480@3-dark.heic", // no id
            "area-4-402x@3-dark.heic", "area-4-402x480@-dark.heic", "area-4-402x480-dark.heic", "area-4-40a2x480@3-dark.heic",
            "area-4-402x480@3.-dark.heic", "area-4-402x480@.5-dark.heic",
            ".dat.nosync1a2b.XyZ", // a write still under way
            "area-4-402x480@3-dark", "notes.txt", "",
        ] {
            #expect(TerrainPicture.parse(name) == nil, "\(name)")
        }
    }

    // MARK: Fingerprint

    @Test func fingerprintIsTheSameForTheSameInputWhateverTheSpotsOrder() {
        let a = TerrainPicture.fingerprint(camera: camera, summit: summit, spots: spots)
        #expect(a == TerrainPicture.fingerprint(camera: camera, summit: summit, spots: spots.reversed()))
        #expect(!a.isEmpty)
        #expect(a.allSatisfy { ("0"..."9").contains($0) || ("a"..."z").contains($0) })
    }

    @Test func fingerprintMovesWithEveryInput() {
        func fp(_ c: TerrainPicture.Camera? = nil, summit s: Coordinate? = nil, spots sp: [TerrainPicture.Spot]? = nil, recipe: Int = TerrainPicture.recipe) -> String {
            TerrainPicture.fingerprint(camera: c ?? camera, summit: s ?? summit, spots: sp ?? spots, recipe: recipe)
        }
        var lat = camera; lat.center = Coordinate(35.2501, 138.95)
        var lng = camera; lng.center = Coordinate(35.25, 138.9501)
        var distance = camera; distance.distance = 52_001
        var heading = camera; heading.heading = 309
        var pitch = camera; pitch.pitch = 64
        let moved = [TerrainPicture.Spot(id: "owakudani", coordinate: Coordinate(35.2426, 139.0198)), spots[1]]
        let movedEast = [TerrainPicture.Spot(id: "owakudani", coordinate: Coordinate(35.2425, 139.0199)), spots[1]]
        let renamed = [TerrainPicture.Spot(id: "owakudani-2", coordinate: spots[0].coordinate), spots[1]]
        let prints = [
            fp(), fp(lat), fp(lng), fp(distance), fp(heading), fp(pitch),
            fp(summit: Coordinate(35.36065, 138.72743)), fp(summit: Coordinate(35.36064, 138.72744)),
            fp(spots: moved), fp(spots: movedEast), fp(spots: renamed), fp(spots: [spots[0]]), fp(spots: []),
            fp(recipe: TerrainPicture.recipe + 1),
        ]
        #expect(Set(prints).count == prints.count)
    }

    @Test func theRecipeIsOne() {
        #expect(TerrainPicture.recipe == 1)
    }

    // MARK: The launch trim

    private let t0 = Date(timeIntervalSince1970: 1_762_560_000)

    private func stored(_ name: String, _ bytes: Int, minutes: Double = 0) -> TerrainPicture.StoredFile {
        TerrainPicture.StoredFile(name: name, bytes: bytes, used: t0.addingTimeInterval(minutes * 60))
    }

    @Test func trimTakesThePictureAndItsPointsTogetherLeastRecentlyUsedFirst() {
        let files = [
            stored("area-4-402x480@3-dark.heic", 300, minutes: 5),
            stored("area-4-402x480@3-dark.json", 10, minutes: 1),
            stored("spot-satta-pass-361x220@3-light.heic", 200, minutes: 2),
            stored("spot-satta-pass-361x220@3-light.json", 10, minutes: 2),
            stored("area-all-402x480@3-light.jpg", 300, minutes: 9),
            stored("area-all-402x480@3-light.json", 10, minutes: 9),
            stored("notes.txt", 5000),
            stored(".dat.nosync1a2b.XyZ", 5000),
        ]
        // the pictures hold 830 B; the pair used last 2 minutes in goes first (a pair's use is its newer file's)
        #expect(TerrainPicture.evicted(files.shuffled(), toBytes: 700)
            == ["spot-satta-pass-361x220@3-light.heic", "spot-satta-pass-361x220@3-light.json"])
        #expect(TerrainPicture.evicted(files, toBytes: 400) == [
            "area-4-402x480@3-dark.heic", "area-4-402x480@3-dark.json",
            "spot-satta-pass-361x220@3-light.heic", "spot-satta-pass-361x220@3-light.json",
        ])
        // a name the cache did not make is never counted, never deleted
        #expect(TerrainPicture.evicted(files, toBytes: 830).isEmpty)
        #expect(TerrainPicture.evicted(files, toBytes: 0)
            == files.map(\.name).filter { $0 != "notes.txt" && $0 != ".dat.nosync1a2b.XyZ" }.sorted())
    }

    @Test func trimKeepsAFolderExactlyAtTheBudgetAndBreaksTiesByStem() {
        let pair = [stored("area-4-10x10@1-dark.heic", 100), stored("area-4-10x10@1-dark.json", 100)]
        #expect(TerrainPicture.evicted(pair, toBytes: 200).isEmpty)
        #expect(TerrainPicture.evicted(pair, toBytes: 199) == ["area-4-10x10@1-dark.heic", "area-4-10x10@1-dark.json"])
        let same = ["b", "a", "d", "c"].flatMap { id in [stored("spot-\(id)-10x10@1-dark.heic", 100), stored("spot-\(id)-10x10@1-dark.json", 10)] }
        #expect(TerrainPicture.evicted(same.shuffled(), toBytes: 220) == [
            "spot-a-10x10@1-dark.heic", "spot-a-10x10@1-dark.json", "spot-b-10x10@1-dark.heic", "spot-b-10x10@1-dark.json",
        ])
    }

    @Test func aPairIsAsRecentAsItsNewerFileWhicheverIsListedFirst() {
        // the picture read a minute ago (a read touches it), its points written long before: the pair was used a
        // minute ago, and the pair used 5 minutes ago goes first, in either order of the listing
        let read = [stored("area-4-10x10@1-dark.heic", 100, minutes: 10), stored("area-4-10x10@1-dark.json", 10)]
        let other = [stored("area-5-10x10@1-dark.heic", 100, minutes: 5), stored("area-5-10x10@1-dark.json", 10, minutes: 5)]
        let gone = ["area-5-10x10@1-dark.heic", "area-5-10x10@1-dark.json"]
        #expect(TerrainPicture.evicted(read + other, toBytes: 150) == gone)
        #expect(TerrainPicture.evicted(read.reversed() + other, toBytes: 150) == gone)
        #expect(TerrainPicture.evicted(other + read.reversed(), toBytes: 150) == gone)
    }

    @Test func trimSparesThePicturesKeptForNoSignal() {
        // the scheme a card is not shown in is never read: kept for Tải tất cả all the same
        let files = [stored("area-4-10x10@1-dark.heic", 100), stored("area-4-10x10@1-dark.json", 10),
                     stored("spot-a-10x10@1-light.heic", 100, minutes: 1), stored("spot-a-10x10@1-light.json", 10, minutes: 1)]
        #expect(TerrainPicture.evicted(files, toBytes: 150) == ["area-4-10x10@1-dark.heic", "area-4-10x10@1-dark.json"])
        #expect(TerrainPicture.evicted(files, toBytes: 150, keeping: ["area-4-10x10@1-dark"])
            == ["spot-a-10x10@1-light.heic", "spot-a-10x10@1-light.json"])
        #expect(TerrainPicture.evicted(files, toBytes: 0, keeping: ["area-4-10x10@1-dark", "spot-a-10x10@1-light"]).isEmpty)
        // the stem the cache names a picture by is the one kept
        let stem = TerrainPicture.stem(kind: .area, id: "4", width: 10, height: 10, scale: 1, dark: true)
        #expect(stem.map { TerrainPicture.evicted(files, toBytes: 0, keeping: [$0]) } == ["spot-a-10x10@1-light.heic", "spot-a-10x10@1-light.json"])
    }

    @Test func trimTakesAPointsFileLeftWithoutItsPicture() {
        // a picture whose write failed, its points still there (or the other way round): the leftover counts and goes
        // in its turn like a pair
        let files = [stored("area-5-402x480@3-dark.json", 10), stored("area-4-402x480@3-dark.heic", 300, minutes: 1)]
        #expect(TerrainPicture.evicted(files, toBytes: 300) == ["area-5-402x480@3-dark.json"])
    }

    // MARK: Picture and live map

    @Test func theLiveMapWaitsForTheSettleAndTheNetwork() {
        #expect(!TerrainPicture.mounts(mounted: false, settled: false, online: true))
        #expect(!TerrainPicture.mounts(mounted: false, settled: true, online: false))
        #expect(!TerrainPicture.mounts(mounted: false, settled: false, online: false))
        #expect(TerrainPicture.mounts(mounted: false, settled: true, online: true))
    }

    @Test func aLiveMapOnceMountedStaysWhateverTheNetwork() {
        #expect(TerrainPicture.mounts(mounted: true, settled: true, online: false))
        #expect(TerrainPicture.mounts(mounted: true, settled: false, online: false))
    }

    @Test func theCoverIsThePictureElseThePlotOfflineElseThePlaceholder() {
        // a picture, online or not, mounted under it or not mounted yet
        for online in [false, true] {
            for atMount in [false, true] {
                #expect(TerrainPicture.cover(picture: true, pictureAtMount: atMount, mounted: false, lifted: false, online: online) == .picture)
            }
            #expect(TerrainPicture.cover(picture: true, pictureAtMount: true, mounted: true, lifted: false, online: online) == .picture)
        }
        // no picture: never live and offline, the plot; anything else, the placeholder until the beat lifts it
        for atMount in [false, true] {
            #expect(TerrainPicture.cover(picture: false, pictureAtMount: atMount, mounted: false, lifted: false, online: false) == .plot)
            #expect(TerrainPicture.cover(picture: false, pictureAtMount: atMount, mounted: false, lifted: false, online: true) == .placeholder)
            #expect(TerrainPicture.cover(picture: false, pictureAtMount: atMount, mounted: true, lifted: false, online: true) == .placeholder)
            #expect(TerrainPicture.cover(picture: false, pictureAtMount: atMount, mounted: true, lifted: false, online: false) == .placeholder)
        }
    }

    @Test func aPictureFinishedDuringTheBeatLeavesThePlaceholderOverTheLiveMap() {
        // a first visit online: the live map mounted under the placeholder, and the picture drawn alongside it lands
        // during the beat. One fade, not two: the placeholder stays until the lift; the picture waits for the next visit
        #expect(TerrainPicture.cover(picture: true, pictureAtMount: false, mounted: true, lifted: false, online: true) == .placeholder)
        // and stays so if the network goes during the beat
        #expect(TerrainPicture.cover(picture: true, pictureAtMount: false, mounted: true, lifted: false, online: false) == .placeholder)
    }

    @Test func onceLiftedNothingCoversTheLiveMap() {
        for picture in [false, true] {
            for atMount in [false, true] {
                for online in [false, true] {
                    // a picture made after the lift is kept for the next visit, never laid over the live map
                    #expect(TerrainPicture.cover(picture: picture, pictureAtMount: atMount, mounted: true, lifted: true, online: online) == nil)
                }
            }
        }
    }

    @Test func theBeatRunsOnlyOverAMountedLiveMapOnline() {
        #expect(TerrainPicture.beats(mounted: true, lifted: false, online: true))
        // offline the cover stays: the live map may have nothing under it
        #expect(!TerrainPicture.beats(mounted: true, lifted: false, online: false))
        #expect(!TerrainPicture.beats(mounted: false, lifted: false, online: true))
        #expect(!TerrainPicture.beats(mounted: true, lifted: true, online: true))
        #expect(TerrainPicture.beat == .milliseconds(800))
    }

    @Test func aPictureIsDrawnOnlySettledOnlineAndOutOfLowPowerMode() {
        #expect(TerrainPicture.draws(settled: true, online: true, lowPower: false))
        #expect(!TerrainPicture.draws(settled: false, online: true, lowPower: false))
        #expect(!TerrainPicture.draws(settled: true, online: false, lowPower: false))
        #expect(!TerrainPicture.draws(settled: true, online: true, lowPower: true))
    }
}

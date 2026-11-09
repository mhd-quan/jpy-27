import Foundation
import Testing
@testable import TripKit

/// An album page's photograph as one picture made once: the hero's height, the picture's size at the photo's own
/// pixels in the frame, where each layer goes, the fade, its name in memory and on disk, and which files the folder
/// lets go of.
@Suite struct AmbientFrameTests {
    private let webp = DecodePlan.Size(width: 800, height: 598)
    private let cover = DecodePlan.Size(width: 1290, height: 1560)

    // MARK: The hero's height

    @Test func heroHeightIsTheShareOfTheLengthRoundedToThePoint() {
        #expect(AmbientFrame.heroHeight(length: 756, fraction: 0.6) == 454)
        #expect(AmbientFrame.heroHeight(length: 852, fraction: 0.56) == 477)
        #expect(AmbientFrame.heroHeight(length: 700, fraction: 0.58) == 406)
        // halves go up, as `CGFloat.rounded()` does in the page's frame
        #expect(AmbientFrame.heroHeight(length: 5, fraction: 0.5) == 3)
        #expect(AmbientFrame.heroHeight(length: 0, fraction: 0.6) == 0)
    }

    // MARK: The frame, in whole points

    @Test func aFrameIsInWholePoints() {
        let frame = AmbientFrame.Frame(width: 393.4, height: 510.6)
        #expect(frame?.width == 393 && frame?.height == 511)
        #expect(AmbientFrame.Frame(width: 392.5, height: 1) == AmbientFrame.Frame(width: 393, height: 1))
    }

    @Test func anEmptyFrameIsNone() {
        #expect(AmbientFrame.Frame(width: 0, height: 511) == nil)
        #expect(AmbientFrame.Frame(width: 393, height: 0.4) == nil)
        #expect(AmbientFrame.Frame(width: .nan, height: 511) == nil)
        #expect(AmbientFrame.Frame(width: 393, height: .infinity) == nil)
        #expect(AmbientFrame.Frame(width: 1, height: 1) != nil)
    }

    @Test func aFrameIsUnderAHundredThousandPoints() {
        #expect(AmbientFrame.Frame(width: 99_999, height: 1) != nil)
        #expect(AmbientFrame.Frame(width: 100_000, height: 1) == nil)
        #expect(AmbientFrame.Frame(width: 1, height: 99_999) != nil)
        #expect(AmbientFrame.Frame(width: 1, height: 100_000) == nil)
    }

    // MARK: The picture's size

    @Test func aLandscapeInAPortraitFrameKeepsTheSourcesPixels() throws {
        // the Commons WebP in a place page's hero: its full height, the width the frame shows of it
        let frame = try #require(AmbientFrame.Frame(width: 393, height: 511))
        #expect(AmbientFrame.canvas(source: webp, frame: frame) == DecodePlan.Size(width: 460, height: 598))
    }

    @Test func aTallerPhotoKeepsItsWidth() throws {
        // a day cover in the day page's hero: its full width, the height the frame shows of it
        let frame = try #require(AmbientFrame.Frame(width: 393, height: 424))
        #expect(AmbientFrame.canvas(source: cover, frame: frame) == DecodePlan.Size(width: 1290, height: 1392))
    }

    @Test func aFrameOfThePhotosShapeIsThePhoto() throws {
        let frame = try #require(AmbientFrame.Frame(width: 400, height: 299))
        #expect(AmbientFrame.canvas(source: webp, frame: frame) == webp)
    }

    @Test func thePictureIsNeverLargerThanThePhoto() throws {
        let sources = [webp, cover, DecodePlan.Size(width: 1600, height: 1557), DecodePlan.Size(width: 1, height: 1),
                       DecodePlan.Size(width: 1800, height: 1350), DecodePlan.Size(width: 598, height: 800)]
        let frames = [(393.0, 511.0), (393, 424), (430, 560), (402, 377), (1, 900), (900, 1)]
        for source in sources {
            for (w, h) in frames {
                let frame = try #require(AmbientFrame.Frame(width: w, height: h))
                let canvas = try #require(AmbientFrame.canvas(source: source, frame: frame))
                #expect(canvas.width <= source.width && canvas.height <= source.height)
                // the side that limits the photo is the photo's whole side: drawn at its own size, not shrunk
                #expect(canvas.width == source.width || canvas.height == source.height)
                #expect(canvas.width >= 1 && canvas.height >= 1)
                // the frame's shape, to the pixel
                let shape = Double(frame.width) / Double(frame.height)
                #expect(abs(Double(canvas.width) - Double(canvas.height) * shape) <= max(1, shape))
            }
        }
    }

    @Test func aPhotoWithNoPixelsHasNoPicture() throws {
        let frame = try #require(AmbientFrame.Frame(width: 393, height: 511))
        #expect(AmbientFrame.canvas(source: DecodePlan.Size(width: 0, height: 598), frame: frame) == nil)
        #expect(AmbientFrame.canvas(source: DecodePlan.Size(width: 800, height: 0), frame: frame) == nil)
    }

    // MARK: Where each layer goes

    @Test func thePhotoFillsThePictureAtItsOwnSizeCentred() {
        let canvas = DecodePlan.Size(width: 460, height: 598)
        #expect(AmbientFrame.fill(webp, into: canvas) == AmbientFrame.Rect(x: -170, y: 0, width: 800, height: 598))
        let tall = DecodePlan.Size(width: 1290, height: 1392)
        #expect(AmbientFrame.fill(cover, into: tall) == AmbientFrame.Rect(x: 0, y: -84, width: 1290, height: 1560))
    }

    @Test func theVeilIsScaledUpToCoverThePicture() {
        // the 160 px veil of the WebP: scaled by the height, which limits it, and centred
        let canvas = DecodePlan.Size(width: 460, height: 598)
        let r = AmbientFrame.fill(DecodePlan.Size(width: 160, height: 120), into: canvas)
        let scale = 598.0 / 120
        #expect(abs(r.width - 160 * scale) < 1e-9 && abs(r.height - 598) < 1e-9)
        #expect(abs(r.x - (460 - 160 * scale) / 2) < 1e-9 && abs(r.y) < 1e-9)
    }

    @Test func aFillAlwaysCoversAndKeepsTheShape() {
        let images = [webp, cover, DecodePlan.Size(width: 160, height: 120), DecodePlan.Size(width: 120, height: 160)]
        let canvases = [DecodePlan.Size(width: 460, height: 598), DecodePlan.Size(width: 1290, height: 1392),
                        DecodePlan.Size(width: 800, height: 300), DecodePlan.Size(width: 50, height: 900)]
        for image in images {
            for canvas in canvases {
                let r = AmbientFrame.fill(image, into: canvas)
                #expect(r.x <= 1e-9 && r.y <= 1e-9)
                #expect(r.x + r.width >= Double(canvas.width) - 1e-9 && r.y + r.height >= Double(canvas.height) - 1e-9)
                // one side exactly the canvas's, the other no shorter
                #expect(abs(r.width - Double(canvas.width)) < 1e-9 || abs(r.height - Double(canvas.height)) < 1e-9)
                #expect(abs(r.width / r.height - Double(image.width) / Double(image.height)) < 1e-9)
                // centred: as much cut on each side
                #expect(abs(2 * r.x + r.width - Double(canvas.width)) < 1e-9)
                #expect(abs(2 * r.y + r.height - Double(canvas.height)) < 1e-9)
            }
        }
    }

    // MARK: The fade

    @Test func theFadeIsTheMaskAlbumPagesHad() {
        let stops = AmbientFrame.fade.map { [$0.shown, $0.at] }
        #expect(stops == [[1, 0], [1, 0.48], [0.65, 0.62], [0.2, 0.76], [0, 0.86]])
    }

    // MARK: Names

    @Test func theKeyNamesThePhotoAndTheFrame() throws {
        let frame = try #require(AmbientFrame.Frame(width: 393.4, height: 510.6))
        #expect(AmbientFrame.key(src: "commons/4fde5cca1448.webp", frame: frame) == "commons/4fde5cca1448.webp@amb@393x511")
        let other = try #require(AmbientFrame.Frame(width: 393, height: 424))
        #expect(AmbientFrame.key(src: "commons/4fde5cca1448.webp", frame: other) == "commons/4fde5cca1448.webp@amb@393x424")
    }

    @Test func theFileNameIsStableAndFileSafe() {
        // FNV-1a 64 of the recipe (8 bytes, least significant first), the key's UTF-8 and a 0, in base 36: the
        // same on every launch and every machine
        let name = AmbientFrame.fileName(key: "commons/4fde5cca1448.webp@amb@393x511")
        #expect(name == "1jeyu0zwl2al7.jpg")
        #expect(AmbientFrame.fileName(key: "https://example.com/a/b.jpg?x=1@amb@402x538") == "x600ch0xdqwx.jpg")
        #expect(AmbientFrame.isPicture(name))
        #expect(!name.contains("/") && !name.contains(":") && !name.contains("@"))
    }

    @Test func anotherRecipeIsAnotherFile() {
        #expect(AmbientFrame.recipe == 1)
        let key = "commons/4fde5cca1448.webp@amb@393x511"
        #expect(AmbientFrame.fileName(key: key, recipe: 2) == "1ff61ffc8q0ic.jpg")
        #expect(AmbientFrame.fileName(key: key, recipe: AmbientFrame.recipe) == AmbientFrame.fileName(key: key))
        #expect(AmbientFrame.fileName(key: key) != AmbientFrame.fileName(key: "commons/4fde5cca1448.webp@amb@393x512"))
    }

    @Test func onlyThePicturesNamesAreThePictures() {
        #expect(AmbientFrame.isPicture("1jeyu0zwl2al7.jpg"))
        #expect(AmbientFrame.isPicture("0.jpg"))
        #expect(!AmbientFrame.isPicture(".jpg"))
        #expect(!AmbientFrame.isPicture("1jeyu0zwl2al7.png"))
        #expect(!AmbientFrame.isPicture("1jeyu0zwl2al7.jpg.tmp"))
        #expect(!AmbientFrame.isPicture("1JEYU0ZWL2AL7.jpg"))
        #expect(!AmbientFrame.isPicture("day-1-abc.jpg"))
        #expect(!AmbientFrame.isPicture(".DS_Store"))
    }

    // MARK: The folder held to a budget

    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func file(_ name: String, _ kb: Int, _ minutes: Double) -> AmbientFrame.StoredFile {
        AmbientFrame.StoredFile(name: name, bytes: kb * 1024, used: t0.addingTimeInterval(minutes * 60))
    }

    @Test func theLeastRecentlyUsedGoUntilTheRestFits() {
        let files = [file("c.jpg", 100, 3), file("a.jpg", 100, 1), file("b.jpg", 100, 2), file("d.jpg", 100, 4)]
        #expect(AmbientFrame.evicted(files.shuffled(), toBytes: 250 * 1024) == ["a.jpg", "b.jpg"])
        #expect(AmbientFrame.evicted(files, toBytes: 300 * 1024) == ["a.jpg"])
        #expect(AmbientFrame.evicted(files, toBytes: 0) == ["a.jpg", "b.jpg", "c.jpg", "d.jpg"])
    }

    @Test func nothingGoesWhileTheFolderFits() {
        let files = [file("a.jpg", 100, 1), file("b.jpg", 100, 2)]
        #expect(AmbientFrame.evicted(files, toBytes: 200 * 1024) == [])
        #expect(AmbientFrame.evicted(files, toBytes: 40 << 20) == [])
        #expect(AmbientFrame.evicted([], toBytes: 0) == [])
    }

    @Test func tiesGoByName() {
        let files = [file("b.jpg", 100, 1), file("a.jpg", 100, 1), file("c.jpg", 100, 1)]
        #expect(AmbientFrame.evicted(files, toBytes: 200 * 1024) == ["a.jpg"])
        #expect(AmbientFrame.evicted(files.reversed(), toBytes: 100 * 1024) == ["a.jpg", "b.jpg"])
    }

    @Test func theNamesComeBackByNameNotInTheOrderTheyGo() {
        // z goes first (the oldest), then m
        let files = [file("z.jpg", 100, 1), file("m.jpg", 100, 2), file("a.jpg", 100, 3)]
        #expect(AmbientFrame.evicted(files, toBytes: 100 * 1024) == ["m.jpg", "z.jpg"])
    }

    @Test func aFileThatIsNotAPictureIsNeitherCountedNorDeleted() {
        // a write in progress, or anything else in the folder, is left alone and does not count toward the budget
        let files = [file("a.jpg", 100, 1), file("b.jpg", 100, 2), file("a.jpg.tmp", 5000, 0), file(".DS_Store", 9000, 0)]
        #expect(AmbientFrame.evicted(files, toBytes: 200 * 1024) == [])
        #expect(AmbientFrame.evicted(files, toBytes: 150 * 1024) == ["a.jpg"])
        #expect(AmbientFrame.evicted(files, toBytes: 0) == ["a.jpg", "b.jpg"])
    }
}

import AVFoundation
import CoreImage
import Foundation
import Observation
import os
import Photos
import SwiftUI
import Synchronization
import TripKit
import UIKit

// MARK: - Place photos

/// Photos of places: the self-hosted Commons set ships in the bundle (commons/…); restaurant photos
/// are remote and kept on disk once seen, or all at once from Settings before the flight.
///
/// Decoded photos sit in a cache any thread can read, so a view looks there synchronously and draws
/// a photo decoded before in its very first frame: no placeholder, no fade, no extra update while a
/// list scrolls. Reading and decoding run off this actor and off the main thread, side by side.
actor PhotoCache {
    static let shared = PhotoCache()

    /// NSCache locks itself. Sized for the home's covers (about 15 MB each at 2400 px) and a few
    /// pages' photos; the system empties it under memory pressure. A photo decoded large serves the
    /// smaller asks for it too (`cached`), so the home's day cards draw from the covers' decodes
    /// instead of holding a second copy of each.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    /// the sizes each photo was decoded at (by src), for `cached` to find a larger one; an entry
    /// the cache has since let go of is simply a miss
    private nonisolated static let sizes = OSAllocatedUnfairLock<[String: Set<Int>]>(initialState: [:])
    /// loads in flight, so two views asking for the same photo share one decode
    private var loading: [NSString: Task<UIImage?, Never>] = [:]
    /// photo src → the average of its lower band, kept on disk: a page opened before (or read at
    /// launch, see `warmTones`) is laid on its colour from its first frame instead of fading into it
    /// halfway through the zoom that opens it
    private nonisolated static let tones = OSAllocatedUnfairLock<[String: AmbientTone]>(initialState: readTones())
    /// On the CPU: the veil's input is 160 px, cheaper to blur here than to queue on the GPU, which
    /// is busy drawing the transition the veil arrives in.
    private let filters = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
    /// Downloaded photos, kept for use with no signal: in Application Support, which the system
    /// does not purge as it does Caches, but out of the iCloud backup (they download again).
    private nonisolated static let folder: URL = {
        var url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    nonisolated static func bundled(_ src: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(src)
    }

    private nonisolated static func file(for url: URL) -> URL {
        var h: UInt64 = 5381
        for b in url.absoluteString.utf8 { h = (h &<< 5) &+ h &+ UInt64(b) }
        return folder.appendingPathComponent(String(h, radix: 36) + ".img")
    }

    private nonisolated static func key(_ photo: Photo, _ maxPixel: CGFloat) -> NSString {
        "\(photo.src)@\(Int(maxPixel))" as NSString
    }

    /// The photo, if it was decoded at this size already, or at a larger one up to twice it (more
    /// than that costs more to draw than a decode of its own): for a view's first frame.
    nonisolated static func cached(_ photo: Photo, maxPixel: CGFloat = 1200) -> UIImage? {
        if let hit = memory.object(forKey: key(photo, maxPixel)) { return hit }
        let want = Int(maxPixel)
        let larger = sizes.withLock { $0[photo.src]?.filter { $0 > want && $0 <= 2 * want } } ?? []
        for size in larger.sorted() {
            if let hit = memory.object(forKey: key(photo, CGFloat(size))) { return hit }
        }
        return nil
    }

    /// The photo's veil, if it was blurred already.
    nonisolated static func cachedVeil(_ photo: Photo) -> UIImage? {
        memory.object(forKey: "\(photo.src)@veil" as NSString)
    }

    /// The colour of the photo's foot, if it was ever read.
    nonisolated static func knownTone(_ photo: Photo) -> AmbientTone? {
        tones.withLock { $0[photo.src] }
    }

    func image(_ photo: Photo, maxPixel: CGFloat = 1200) async -> UIImage? {
        let key = Self.key(photo, maxPixel)
        if let hit = Self.cached(photo, maxPixel: maxPixel) { return hit }
        if let running = loading[key] { return await running.value }
        let task = Task { await Self.load(photo, maxPixel: maxPixel, network: true) }
        loading[key] = task
        let image = await task.value
        loading[key] = nil
        if let image {
            Self.memory.setObject(image, forKey: key, cost: Int(image.size.width * image.scale * image.size.height * image.scale * 4))
            Self.sizes.withLock { _ = $0[photo.src, default: []].insert(Int(maxPixel)) }
        }
        return image
    }

    /// Reads (from the bundle, the disk, or the network once) and decodes, on a background thread.
    @concurrent private nonisolated static func load(_ photo: Photo, maxPixel: CGFloat, network: Bool) async -> UIImage? {
        var data: Data?
        if photo.isBundled {
            data = bundled(photo.src).flatMap { try? Data(contentsOf: $0) }
        } else if let url = URL(string: photo.src) {
            let disk = file(for: url)
            data = try? Data(contentsOf: disk)
            if data == nil, network, let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
                // whole or not at all: a half-written file would count as saved for use offline
                try? d.write(to: disk, options: .atomic)
                data = d
            }
        }
        guard let data else { return nil }
        return downsample(data, maxPixel: maxPixel)
    }

    /// Read (from the bundle or the disk, never the network) and decoded, and not kept: for work in
    /// the background (the widget's photos) that should neither download what nobody asked for nor
    /// push the photos on screen out of memory.
    nonisolated static func decodeLocal(_ photo: Photo, maxPixel: CGFloat) async -> UIImage? {
        await load(photo, maxPixel: maxPixel, network: false)
    }

    /// The average colour of the photograph's lower band, read once from a small thumbnail and kept:
    /// what an ambient page is tinted with, so the photograph dissolves into its own colour.
    func tone(_ photo: Photo) async -> AmbientTone? {
        if let hit = Self.knownTone(photo) { return hit }
        guard let small = await image(photo, maxPixel: 96), let cg = small.cgImage, let tone = AmbientTone.sample(cg) else { return nil }
        Self.tones.withLock { $0[photo.src] = tone }
        saveTones()
        return tone
    }

    /// Reads the colour of every photograph a page opens on, once, in the background, from what is
    /// in the bundle or on disk (nothing is downloaded for it). Kept on disk, so it is done once.
    func warmTones(_ photos: [Photo]) async {
        var seen = Set<String>()
        let missing = photos.filter { seen.insert($0.src).inserted && Self.knownTone($0) == nil }
        guard !missing.isEmpty else { return }
        for photo in missing {
            guard let small = await Self.load(photo, maxPixel: 96, network: false), let cg = small.cgImage,
                  let tone = AmbientTone.sample(cg) else { continue }
            Self.tones.withLock { $0[photo.src] = tone }
        }
        saveTones()
    }

    /// versioned with `AmbientTone.sample`: a change there reads every photo again
    private nonisolated static var tonesFile: URL { folder.appendingPathComponent("tones-1.json") }

    private nonisolated static func readTones() -> [String: AmbientTone] {
        guard let data = try? Data(contentsOf: tonesFile),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        return raw.compactMapValues { $0.count == 3 ? AmbientTone(red: $0[0], green: $0[1], blue: $0[2]) : nil }
    }

    private func saveTones() {
        let raw = Self.tones.withLock { $0.mapValues { [$0.red, $0.green, $0.blue] } }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: Self.tonesFile, options: .atomic)
    }

    /// A small, heavily blurred copy of the photograph, laid under the sharp one where it dissolves
    /// into the page. Blurred once, here, so nothing is blurred live while the page scrolls; drawn
    /// at full width the upscaled blur only gets softer.
    func veil(_ photo: Photo) async -> UIImage? {
        let key = "\(photo.src)@veil" as NSString
        if let hit = Self.memory.object(forKey: key) { return hit }
        guard let small = await image(photo, maxPixel: 160), let cg = small.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        // clamped first, so the edges blur into themselves instead of into transparency
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        guard let out = filters.createCGImage(blurred, from: input.extent) else { return nil }
        let image = UIImage(cgImage: out)
        Self.memory.setObject(image, forKey: key, cost: out.width * out.height * 4)
        return image
    }

    /// The remote photos not on disk yet.
    @concurrent nonisolated static func missing(_ urls: [URL]) async -> [URL] {
        urls.filter { !FileManager.default.fileExists(atPath: file(for: $0).path) }
    }

    /// One remote photo onto the disk, whole or not at all. True when it is there.
    @concurrent nonisolated static func fetch(_ url: URL) async -> Bool {
        let disk = file(for: url)
        if FileManager.default.fileExists(atPath: disk.path) { return true }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty
        else { return false }
        return (try? data.write(to: disk, options: .atomic)) != nil
    }

    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Photos kept for no signal

/// The trip's remote photos (restaurants, shops, a hotel's neighbourhood) kept on disk for use
/// without signal. App-wide, so the count and the progress outlive the Settings page. Counted from
/// what is on disk, so photos seen while browsing count too; downloaded four at a time; a photo that
/// fails is counted and tried again on the next download. Asked for and not finished, it is picked
/// up when the app opens again.
@Observable final class OfflinePhotos {
    private(set) var total = 0
    /// on disk now
    private(set) var saved = 0
    /// failed in the download under way or the last one; tried again on the next
    private(set) var failed = 0
    private(set) var running = false
    /// counted from the disk: until then the page says nothing it cannot back
    private(set) var counted = false
    /// stopped by a pause (the travellers', or the system's) and not finished since: a download that was
    /// paused is not done (`OfflineJob.result`), until every photo is on disk after all
    private(set) var paused = false

    var fraction: Double { total > 0 ? Double(saved) / Double(total) : 0 }
    var complete: Bool { counted && saved >= total }

    @ObservationIgnored private var urls: [URL] = []
    @ObservationIgnored private var job: Task<Void, Never>?
    private static let wantedKey = "photos.wanted"

    /// The trip's photos (bundled ones are skipped), then a count of those on disk: on each return
    /// to the app, a few hundred file lookups off the main thread.
    func configure(_ photos: @autoclosure () -> [Photo]) {
        if urls.isEmpty {
            var seen = Set<String>()
            urls = photos().filter { !$0.isBundled && seen.insert($0.src).inserted }.compactMap { URL(string: $0.src) }
            total = urls.count
        }
        guard !running, !urls.isEmpty else { return }
        let list = urls
        Task {
            let missing = await PhotoCache.missing(list)
            guard !running else { return }
            if saved != list.count - missing.count { saved = list.count - missing.count }
            counted = true
            if missing.isEmpty, paused { paused = false }
            guard Shared.defaults.bool(forKey: Self.wantedKey) else { return }
            if missing.isEmpty { Shared.defaults.set(false, forKey: Self.wantedKey) } else { download() }
        }
    }

    func download() {
        guard job == nil, !urls.isEmpty else { return }
        Shared.defaults.set(true, forKey: Self.wantedKey)
        running = true
        paused = false
        failed = 0
        let list = urls
        job = Task {
            let missing = await PhotoCache.missing(list)
            saved = list.count - missing.count
            counted = true
            await withTaskGroup(of: Bool.self) { group in
                var queue = missing.makeIterator()
                for _ in 0..<4 {
                    guard let url = queue.next() else { break }
                    group.addTask { await PhotoCache.fetch(url) }
                }
                for await ok in group {
                    // a pause cancels what is under way: not a failure
                    if ok { saved += 1 } else if !Task.isCancelled { failed += 1 }
                    if !Task.isCancelled, let url = queue.next() { group.addTask { await PhotoCache.fetch(url) } }
                }
            }
            if !Task.isCancelled, failed == 0 { Shared.defaults.set(false, forKey: Self.wantedKey) }
            // the last ones arrived while it was being paused: nothing is left to go on with
            if saved >= list.count, paused { paused = false }
            running = false
            job = nil
        }
    }

    /// Stops where it is; what is on disk stays.
    func pause() {
        Shared.defaults.set(false, forKey: Self.wantedKey)
        guard let job else { return }
        paused = true
        job.cancel()
    }
}

// MARK: - Ambient colour

/// The mean colour of a photograph's lower band, in sRGB components.
nonisolated struct AmbientTone: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double

    /// Read from a 12 × 6 thumbnail of the lowest 38 % of the image, the lowest rows counting
    /// double: the page carries on from the photograph's very bottom.
    static func sample(_ image: CGImage) -> AmbientTone? {
        let top = (Double(image.height) * 0.62).rounded()
        let band = CGRect(x: 0, y: top, width: Double(image.width), height: Double(image.height) - top)
        guard band.height >= 1, let crop = image.cropping(to: band), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let w = 12, h = 6
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        // the bitmap's first row in memory is the top of the band
        for y in 0..<h {
            let weight = 1 + Double(y) / Double(h - 1)
            for x in 0..<w {
                let i = (y * w + x) * 4
                r += Double(pixels[i]) * weight
                g += Double(pixels[i + 1]) * weight
                b += Double(pixels[i + 2]) * weight
                total += weight
            }
        }
        guard total > 0 else { return nil }
        return AmbientTone(red: r / total / 255, green: g / total / 255, blue: b / total / 255)
    }

    /// An ambient page's colour: the first photograph decides light or dark for the whole page, the
    /// one on screen moves the hue. A tone read before comes straight from the cache, so a page is
    /// laid on its colour from its first frame instead of re-colouring itself mid-zoom.
    static func canvas(_ tones: [Int: AmbientTone], photos: [Photo], page: Int, dim: Bool) -> AmbientCanvas? {
        func tone(_ i: Int) -> AmbientTone? {
            tones[i] ?? (photos.indices.contains(i) ? PhotoCache.knownTone(photos[i]) : nil)
        }
        guard let first = tone(0) else { return nil }
        return (tone(page) ?? first).canvas(light: first.prefersLight, dim: dim)
    }

    /// Light enough that a page in this colour wants dark type.
    var prefersLight: Bool { Self.luminance(red, green, blue) > 0.4 }

    /// The page colour: the photograph's own hue, calmed (saturation capped) and pushed light or
    /// dark enough for type to read on it. `light` comes from a page's first photograph, so all its
    /// photographs land on the same side and the type never flips while paging; `dim` (dark mode)
    /// turns a light page into a deep one in the same hue instead of a glare.
    func canvas(light: Bool, dim: Bool) -> AmbientCanvas {
        var (h, s, v) = Self.hsv(red, green, blue)
        let pale = light && !dim
        if pale {
            s = min(s, 0.3) * 0.9
            v = min(max(v, 0.8), 0.93)
        } else if light {
            s = min(s, 0.35)
            v = 0.32
        } else {
            s = min(s, 0.55)
            v = min(max(v, 0.24), 0.5) * (dim ? 0.82 : 1)
        }
        var (r, g, b) = Self.rgb(h, s, v)
        // keep type legible: dark pages under a luminance of 0.16 (white type above 4.5:1),
        // light ones above 0.45 (black type well above it)
        for _ in 0..<12 {
            let l = Self.luminance(r, g, b)
            if pale, l < 0.45 {
                v = min(0.97, v + 0.03)
                s *= 0.9
            } else if !pale, l > 0.16 {
                v *= 0.92
            } else {
                break
            }
            (r, g, b) = Self.rgb(h, s, v)
        }
        return AmbientCanvas(red: r, green: g, blue: b, light: pale)
    }

    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    private static func hsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), d = maxC - minC
        var h = 0.0
        if d > 0 {
            if maxC == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if maxC == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC > 0 ? d / maxC : 0, maxC)
    }

    private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let c = v * s
        let hh = h * 6
        let x = c * (1 - abs(hh.truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        let (r, g, b): (Double, Double, Double) = switch Int(hh) % 6 {
        case 0: (c, x, 0)
        case 1: (x, c, 0)
        case 2: (0, c, x)
        case 3: (0, x, c)
        case 4: (x, 0, c)
        default: (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}

/// The colour an ambient page is laid on, and which way its type goes.
nonisolated struct AmbientCanvas: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    /// type and controls are dark on it
    let light: Bool

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }
    var scheme: ColorScheme { light ? .light : .dark }

    /// A card on the page: the colour lifted toward white as a translucent white card reads over
    /// it (40 % on a pale page, 9 % on a deep one), but opaque, so what is drawn on the card can
    /// knock itself out of the card's fill.
    var surface: Color {
        let lift = light ? 0.4 : 0.09
        return Color(.sRGB, red: red + (1 - red) * lift, green: green + (1 - green) * lift, blue: blue + (1 - blue) * lift)
    }

    /// For a page with no photograph to take a colour from: the deep blue of Fuji at dusk.
    static let dusk = AmbientCanvas(red: 0.11, green: 0.13, blue: 0.22, light: false)
}

/// A place photo, filled edge to edge; a quiet placeholder while it loads or when there is none.
struct PlacePhoto: View {
    let photo: Photo?
    var maxPixel: CGFloat = 1200
    @State private var image: UIImage?

    init(photo: Photo?, maxPixel: CGFloat = 1200) {
        self.photo = photo
        self.maxPixel = maxPixel
        // decoded before: drawn in the first frame, so a cell scrolled back into view does not
        // flash its placeholder and fade
        _image = State(initialValue: photo.flatMap { PhotoCache.cached($0, maxPixel: maxPixel) })
    }

    var body: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .accessibilityLabel(photo?.caption ?? "")
            .task(id: photo?.src) {
                guard let photo else { return }
                if let hit = PhotoCache.cached(photo, maxPixel: maxPixel) {
                    if image !== hit { image = hit }
                    return
                }
                let loaded = await PhotoCache.shared.image(photo, maxPixel: maxPixel)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }
}

// MARK: - Widget photos

/// Small JPEGs of each planned place in the App Group, for the widget's background.
///
/// Made from what is already on the phone: the bundled photos, and the restaurants' once they have
/// been seen or downloaded from Settings. Nothing is downloaded for it, and nothing is kept in the
/// photo cache (some eighty photos at 800 px would push out the covers the home is showing). Done
/// only once every place has its JPEG; until then each return to the app writes the ones missing.
enum HeroExporter {
    static func exportIfNeeded(store: TripStore) async {
        // 2: the first version counted itself done with photos still missing (offline at first launch)
        let version = "2:\(store.trip.places.count)"
        guard Shared.defaults.string(forKey: "heroes") != version else { return }
        let ids = Set(store.trip.days.flatMap(\.items).compactMap { $0.stop?.place } + store.trip.altDays.flatMap(\.items).compactMap { $0.stop?.place })
        let photos: [(String, Photo)] = ids.compactMap { id in store.place(id)?.hero.map { (id, $0) } }
        let complete = await Task.detached(priority: .utility) { () -> Bool in
            var folder = Shared.heroes
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // made again from the photos at any time: nothing for the iCloud backup
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
            var complete = true
            for (id, photo) in photos {
                let target = Shared.hero(id)
                if FileManager.default.fileExists(atPath: target.path) { continue }
                guard let image = await PhotoCache.decodeLocal(photo, maxPixel: 800), let jpeg = image.jpegData(compressionQuality: 0.72),
                      (try? jpeg.write(to: target, options: .atomic)) != nil
                else {
                    complete = false
                    continue
                }
            }
            return complete
        }.value
        if complete { Shared.defaults.set(version, forKey: "heroes") }
    }
}

// MARK: - Japanese voice

/// Reads Japanese aloud with the on-device voice, so a phrase can be played to staff.
@Observable final class Speaker: NSObject {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private(set) var speaking: String?
    /// `speaking != nil`, readable from Nghe's audio thread: the microphone's buffers are dropped
    /// while the app speaks, so Nghe does not write down the app's own voice (`.measurement` has no
    /// echo cancelling)
    let voice = SpeakingFlag()

    override init() {
        super.init()
        synth.delegate = self
    }

    /// the session was set up for speaking here, so it is ours to hand back when done
    private var ownsSession = false

    func say(_ ja: String, slow: Bool = false) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let session = AVAudioSession.sharedInstance()
        // while Nghe is listening the session records: speak through it as it is (changing the
        // category would stop the microphone), and leave it to Nghe to end
        if session.category != .playAndRecord {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            ownsSession = true
        }
        let u = AVSpeechUtterance(string: ja)
        u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        u.rate = slow ? 0.38 : AVSpeechUtteranceDefaultSpeechRate
        speaking = ja
        voice.set(true)
        synth.speak(u)
    }

    /// Nghe stopped while a line is being read: the session, its category already given back, is
    /// the Speaker's to end once nothing is left to say (`ended`).
    func adoptSession() {
        ownsSession = true
    }

    /// An utterance ended or was cut off: once nothing is left to say, the music ducked for it
    /// comes back up (`notifyOthersOnDeactivation`); without this it stays low until the app quits.
    fileprivate func ended(_ text: String) {
        // the same line again cuts this one off: still speaking it
        guard !synth.isSpeaking else { return }
        if speaking == text {
            speaking = nil
            voice.set(false)
        }
        guard ownsSession else { return }
        ownsSession = false
        // Nghe may have taken the session over meanwhile: it is Nghe's to end then
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playAndRecord else { return }
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Whether the app is speaking, set on the main actor and read on the audio thread: one lock-free
/// atomic, nothing else.
nonisolated final class SpeakingFlag: Sendable {
    private let on = Atomic<Bool>(false)

    func set(_ value: Bool) { on.store(value, ordering: .releasing) }

    var isOn: Bool { on.load(ordering: .acquiring) }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        Task { @MainActor in self.ended(text) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let text = utterance.speechString
        Task { @MainActor in self.ended(text) }
    }
}

// MARK: - Photo library (journal)

/// Photos taken during the trip, found by time and place for the journal.
@Observable final class PhotoLibrary {
    private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var allowed: Bool { status == .authorized || status == .limited }

    func request() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Photos taken between two instants, nearest the place first when it is known. The library is
    /// searched on a background thread (every photo of the window, each with its location): a
    /// journal page asks once per stop as it slides in, and the main thread is drawing that.
    func photos(from: Date, to: Date, near: Coordinate? = nil, radiusKm: Double = 0.3, limit: Int = 12) async -> [PHAsset] {
        guard allowed else { return [] }
        let ids = await Self.find(from: from, to: to, near: near, radiusKm: radiusKm, limit: limit)
        guard !ids.isEmpty else { return [] }
        // the few found, by identifier: an indexed lookup
        var byID: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { a, _, _ in byID[a.localIdentifier] = a }
        return ids.compactMap { byID[$0] }
    }

    @concurrent private nonisolated static func find(from: Date, to: Date, near: Coordinate?, radiusKm: Double, limit: Int) async -> [String] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d", from as NSDate, to as NSDate, PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        guard let near else { return list.prefix(limit).map(\.localIdentifier) }
        let scored = list.compactMap { a -> (PHAsset, Double)? in
            guard let l = a.location else { return (a, radiusKm) }
            let d = Geo.km(near, Coordinate(l.coordinate.latitude, l.coordinate.longitude))
            return d <= radiusKm * 2 ? (a, d) : nil
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0.localIdentifier)
    }
}

/// A thumbnail from the photo library.
struct AssetImage: View {
    let asset: PHAsset
    var side: CGFloat = 300
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .task(id: asset.localIdentifier) {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = true
                let size = CGSize(width: side * 2, height: side * 2)
                image = await withCheckedContinuation { cont in
                    // Photos may answer on a queue of its own (an iCloud download especially), so the
                    // handler is nonisolated and the once-only flag is a lock, not a captured var
                    let resumed = OSAllocatedUnfairLock(initialState: false)
                    PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { @Sendable img, info in
                        let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        guard !degraded, resumed.withLock({ done in defer { done = true }; return !done }) else { return }
                        cont.resume(returning: img)
                    }
                }
            }
    }
}

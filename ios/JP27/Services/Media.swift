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
/// list scrolls. Reading, decoding, deriving and composing run off this actor and off the main
/// thread, side by side; the actor only keeps the books (what is in flight, the colours to save).
///
/// One decode per photo on an album page: the hero's decode (`heroPixel`) is the one its colour and
/// its veil are made from (`derive`), and the one the page's picture is composed from (`ambient`).
actor PhotoCache {
    static let shared = PhotoCache()

    /// NSCache locks itself. Sized for the home's covers (about 8 MB each, decoded whole) and a few
    /// pages' photos; the system empties it under memory pressure. A photo decoded whole serves every
    /// larger ask for it, and any decode serves asks down to half its size (`DecodePlan`), so the
    /// home's day cards, its covers and the day pages draw from one decode of each cover.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    /// the asks each photo was decoded smaller than its source for (by src), for `cached` to find one
    /// that serves another ask; an entry the cache has since let go of is simply a miss. A photo
    /// decoded whole has one entry of its own (`fullKey`) whatever it was asked at.
    private nonisolated static let sizes = OSAllocatedUnfairLock<[String: Set<Int>]>(initialState: [:])
    /// loads in flight, by ask, so two views asking for the same photo share one decode; `network`
    /// says whether the load may download (a colour never does, `tone`)
    private var loading: [NSString: (task: Task<UIImage?, Never>, network: Bool)] = [:]
    /// veils and colours being made, by src: the page's colour and its hero ask for them together
    private var deriving: [String: Task<Derived?, Never>] = [:]
    /// album pictures being composed, by `ambientKey`
    private var composing: [String: Task<UIImage?, Never>] = [:]
    /// the debounced write of `tones` (`scheduleSave`)
    private var saving: Task<Void, Never>?
    /// photo src → the average of its lower band, kept on disk: a page opened before (or read at
    /// launch, see `warmTones`) is laid on its colour from its first frame instead of fading into it
    /// halfway through the zoom that opens it
    private nonisolated static let tones = OSAllocatedUnfairLock<[String: AmbientTone]>(initialState: readTones())
    /// On the CPU: the veil's input is 160 px, cheaper to blur here than to queue on the GPU, which
    /// is busy drawing the transition the veil arrives in. `CIContext` is thread-safe (Sendable), so
    /// one serves every `derive`, wherever it runs.
    private nonisolated static let filters = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
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
    /// Album pictures (`ambient`), made again from the photos at any time: in Caches, which the
    /// system purges when it needs the room.
    private nonisolated static let ambientFolder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Ambient", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// What an album page's hero asks for: the page's picture, its colour and its veil are all made
    /// from this one decode.
    nonisolated static let heroPixel: CGFloat = 1800

    /// How much of the sharp photograph shows over its veil, top to bottom (`shown` 1 to 0 at `at`):
    /// sharp at the top, soft where the type sits, the veil alone at the bottom. Composed into the
    /// album picture (`compose`), and drawn as a mask under Reduce Transparency.
    nonisolated static let heroFade: [(shown: Double, at: Double)] = [(1, 0), (1, 0.48), (0.65, 0.62), (0.2, 0.76), (0, 0.86)]

    nonisolated static func bundled(_ src: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(src)
    }

    /// The same short name for the same text on every run, for files named after a photo.
    private nonisolated static func hash36(_ text: String) -> String {
        var h: UInt64 = 5381
        for b in text.utf8 { h = (h &<< 5) &+ h &+ UInt64(b) }
        return String(h, radix: 36)
    }

    private nonisolated static func file(for url: URL) -> URL {
        folder.appendingPathComponent(hash36(url.absoluteString) + ".img")
    }

    private nonisolated static func key(_ photo: Photo, _ maxPixel: CGFloat) -> NSString {
        "\(photo.src)@\(Int(maxPixel))" as NSString
    }

    private nonisolated static func fullKey(_ photo: Photo) -> NSString {
        "\(photo.src)@full" as NSString
    }

    private nonisolated static func veilKey(_ photo: Photo) -> NSString {
        "\(photo.src)@veil" as NSString
    }

    /// An album picture's name: the photo and the size of the box it fills, in whole points.
    nonisolated static func ambientKey(_ photo: Photo, size: CGSize) -> String {
        "\(photo.src)@amb@\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }

    /// "a1": the way pictures are composed; a change there names every picture anew instead of
    /// reading old ones
    private nonisolated static func ambientFile(_ key: String) -> URL {
        ambientFolder.appendingPathComponent("a1-" + hash36(key) + ".heic")
    }

    private nonisolated static func pixels(_ image: UIImage) -> Size {
        Size(width: Double(image.size.width * image.scale), height: Double(image.size.height * image.scale))
    }

    private nonisolated static func cost(_ image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    /// The photo, if a decode in memory serves this size (`DecodePlan`): one made for this very ask,
    /// the whole photo, or a decode made for a nearby ask. For a view's first frame.
    nonisolated static func cached(_ photo: Photo, maxPixel: CGFloat = 1200) -> UIImage? {
        if let hit = memory.object(forKey: key(photo, maxPixel)) { return hit }
        let want = Int(maxPixel)
        if let full = memory.object(forKey: fullKey(photo)),
           DecodePlan.serves(decoded: pixels(full), sourceIsFull: true, asked: want) { return full }
        let asks = sizes.withLock { $0[photo.src] } ?? []
        for ask in asks.sorted() where ask != want {
            if let hit = memory.object(forKey: key(photo, CGFloat(ask))),
               DecodePlan.serves(decoded: pixels(hit), sourceIsFull: false, asked: want) { return hit }
        }
        return nil
    }

    /// The photo's veil (`derive`), if it was made already: for a view's first frame.
    nonisolated static func cachedVeil(_ photo: Photo) -> UIImage? {
        memory.object(forKey: veilKey(photo))
    }

    /// The photo's album picture for a box of this size (`ambient`), if it is in memory: for a
    /// view's first frame.
    nonisolated static func cachedAmbient(_ photo: Photo, size: CGSize) -> UIImage? {
        memory.object(forKey: ambientKey(photo, size: size) as NSString)
    }

    /// The colour of the photo's foot, if it was ever read.
    nonisolated static func knownTone(_ photo: Photo) -> AmbientTone? {
        tones.withLock { $0[photo.src] }
    }

    /// The photo at this size, decoded once and kept. `network` false reads only what is on this
    /// phone. A read in flight for the same ask is shared, except that one which may not download
    /// and found nothing does not answer an ask that may: that one then downloads.
    func image(_ photo: Photo, maxPixel: CGFloat = 1200, network: Bool = true) async -> UIImage? {
        if let hit = Self.cached(photo, maxPixel: maxPixel) { return hit }
        let key = Self.key(photo, maxPixel)
        if let running = loading[key] {
            let image = await running.task.value
            guard image == nil, !running.network, network else { return image }
            if let hit = Self.cached(photo, maxPixel: maxPixel) { return hit }
            // a download started by another view while this one waited
            if let other = loading[key], other.task != running.task, other.network { return await other.task.value }
        }
        let task = Task { () -> UIImage? in
            guard let decoded = await Self.load(photo, maxPixel: maxPixel, network: network) else { return nil }
            return Self.keep(decoded, photo, maxPixel: maxPixel)
        }
        loading[key] = (task, network)
        let image = await task.value
        // a download that took over this ask after a local read found nothing is not this one's to clear
        if loading[key]?.task == task { loading[key] = nil }
        return image
    }

    /// Into memory: a whole decode under the photo's one full entry (a whole decode made for another
    /// ask meanwhile is the same pixels, and stays the one kept), a downsampled one under its ask.
    private nonisolated static func keep(_ decoded: Decoded, _ photo: Photo, maxPixel: CGFloat) -> UIImage {
        let image = decoded.image
        if decoded.whole {
            if let held = memory.object(forKey: fullKey(photo)) { return held }
            memory.setObject(image, forKey: fullKey(photo), cost: cost(image))
        } else {
            memory.setObject(image, forKey: key(photo, maxPixel), cost: cost(image))
            sizes.withLock { _ = $0[photo.src, default: []].insert(Int(maxPixel)) }
        }
        return image
    }

    /// A decode, and whether it holds the whole source (its long edge is the source's own).
    nonisolated struct Decoded: Sendable {
        let image: UIImage
        let whole: Bool
    }

    /// Reads (from the bundle, the disk, or the network once) and decodes, on a background thread.
    @concurrent private nonisolated static func load(_ photo: Photo, maxPixel: CGFloat, network: Bool) async -> Decoded? {
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
        await load(photo, maxPixel: maxPixel, network: false)?.image
    }

    /// The average colour of the photograph's lower band, read once and kept: what an ambient page
    /// is tinted with, so the photograph dissolves into its own colour. Read from the decode the
    /// page's hero draws from (`heroPixel`), with its veil (`derive`), and only from what is on this
    /// phone: nothing is downloaded for a colour, and a photo not here yet gives nil.
    func tone(_ photo: Photo) async -> AmbientTone? {
        if let hit = Self.knownTone(photo) { return hit }
        // decided before anything is read: a download the hero has under way does not count
        guard await Self.isLocal(photo),
              let sharp = await image(photo, maxPixel: Self.heroPixel, network: false) else { return nil }
        return await derived(photo, from: sharp)?.tone
    }

    /// In the bundle, or downloaded before.
    @concurrent private nonisolated static func isLocal(_ photo: Photo) async -> Bool {
        if photo.isBundled { return true }
        guard let url = URL(string: photo.src) else { return false }
        return FileManager.default.fileExists(atPath: file(for: url).path)
    }

    /// Reads the colour of every photograph a page opens on, once, in the background, from what is
    /// in the bundle or on disk (nothing is downloaded for it). Kept on disk, so it is done once.
    /// Read from the same decode as `tone`, so a colour is the same whichever of the two read it.
    func warmTones(_ photos: [Photo]) async {
        var seen = Set<String>()
        let missing = photos.filter { seen.insert($0.src).inserted && Self.knownTone($0) == nil }
        var read = false
        for photo in missing {
            guard let tone = await Self.readTone(photo) else { continue }
            Self.tones.withLock { $0[photo.src] = tone }
            read = true
        }
        if read { scheduleSave() }
    }

    @concurrent private nonisolated static func readTone(_ photo: Photo) async -> AmbientTone? {
        guard let sharp = await load(photo, maxPixel: heroPixel, network: false)?.image.cgImage else { return nil }
        return AmbientTone.sample(sharp)
    }

    /// 2: read from the hero's decode (`derive`) instead of a 96 px thumbnail. Versioned with
    /// `AmbientTone.sample` and its input: a change there reads every photo again.
    private nonisolated static var tonesFile: URL { folder.appendingPathComponent("tones-2.json") }

    private nonisolated static func readTones() -> [String: AmbientTone] {
        guard let data = try? Data(contentsOf: tonesFile),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        return raw.compactMapValues { $0.count == 3 ? AmbientTone(red: $0[0], green: $0[1], blue: $0[2]) : nil }
    }

    /// The colours, written once a second has passed with none read: one write for a page's
    /// photos, or for the launch's `warmTones`, instead of one per photo.
    private func scheduleSave() {
        saving?.cancel()
        saving = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let raw = Self.tones.withLock { $0.mapValues { [$0.red, $0.green, $0.blue] } }
            await Self.writeTones(raw)
        }
    }

    /// a cache: colours that cannot be written are read again at a later launch
    @concurrent private nonisolated static func writeTones(_ raw: [String: [Double]]) async {
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: tonesFile, options: .atomic)
    }

    /// What a page takes from a photograph besides the photograph itself, made from one decode of it.
    /// Images cross threads as `UIImage` (Sendable), never as a bare `CGImage`.
    nonisolated struct Derived: Sendable {
        /// a small, heavily blurred copy, laid under the sharp photograph where it dissolves into
        /// the page: drawn at full width the upscaled blur only gets softer
        let veil: UIImage
        /// the colour of its foot (`AmbientTone.sample`)
        let tone: AmbientTone?
    }

    /// The veil and the colour of a photograph, from the decode its page draws (`heroPixel`): the
    /// decode drawn into a 160 px sRGB bitmap and blurred, and its foot sampled. Off the main thread
    /// and off the actor, so nothing queued behind it waits.
    @concurrent nonisolated static func derive(_ full: CGImage) async -> Derived? {
        guard let blurred = veil(of: full) else { return nil }
        return Derived(veil: UIImage(cgImage: blurred), tone: AmbientTone.sample(full))
    }

    private nonisolated static func veil(of full: CGImage) -> CGImage? {
        let scale = 160 / Double(max(full.width, full.height, 1))
        let width = max(1, Int((Double(full.width) * scale).rounded()))
        let height = max(1, Int((Double(full.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let small = bitmap(width: width, height: height, space: space) else { return nil }
        small.interpolationQuality = .high
        small.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let drawn = small.makeImage() else { return nil }
        let input = CIImage(cgImage: drawn)
        // clamped first, so the edges blur into themselves instead of into transparency
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        return filters.createCGImage(blurred, from: input.extent, format: .RGBA8, colorSpace: space)
    }

    /// An opaque 8-bit sRGB bitmap: the photos are sRGB, and a bitmap in another space would shift
    /// their colours (the flattened layer this replaces kept sRGB too).
    private nonisolated static func bitmap(width: Int, height: Int, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    }

    /// The veil and the colour of a photograph, made once (`derive`) and kept: the veil in memory,
    /// the colour with the others (saved). A page's colour and its hero ask for them together; the
    /// second waits for the first's.
    private func derived(_ photo: Photo, from sharp: UIImage) async -> Derived? {
        if let veil = Self.cachedVeil(photo), let tone = Self.knownTone(photo) {
            return Derived(veil: veil, tone: tone)
        }
        if let running = deriving[photo.src] { return await running.value }
        let task = Task { () -> Derived? in
            guard let full = sharp.cgImage else { return nil }
            return await Self.derive(full)
        }
        deriving[photo.src] = task
        let made = await task.value
        deriving[photo.src] = nil
        guard let made else { return nil }
        Self.memory.setObject(made.veil, forKey: Self.veilKey(photo), cost: Self.cost(made.veil))
        if let tone = made.tone, Self.knownTone(photo) != tone {
            Self.tones.withLock { $0[photo.src] = tone }
            scheduleSave()
        }
        return made
    }

    /// An album page's photograph as one picture, for a box of this size: the veil filling the
    /// box, the sharp photograph over it fading out from the middle down (`heroFade`), cropped to
    /// the box as `scaledToFill` would at the photograph's own pixels. Composed once, off the main
    /// thread, and kept in memory and in Caches/Ambient, so the zoom, the swipe and the scroll move
    /// a finished picture. The photograph is downloaded if it is not on this phone yet.
    func ambient(_ photo: Photo, size: CGSize) async -> UIImage? {
        let key = Self.ambientKey(photo, size: size)
        if let hit = Self.memory.object(forKey: key as NSString) { return hit }
        if let running = composing[key] { return await running.value }
        let task = Task { await self.makeAmbient(photo, size: size, key: key) }
        composing[key] = task
        let picture = await task.value
        composing[key] = nil
        return picture
    }

    private func makeAmbient(_ photo: Photo, size: CGSize, key: String) async -> UIImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        let file = Self.ambientFile(key)
        if let saved = await Self.readAmbient(file) {
            Self.memory.setObject(saved, forKey: key as NSString, cost: Self.cost(saved))
            return saved
        }
        guard let sharp = await image(photo, maxPixel: Self.heroPixel),
              let parts = await derived(photo, from: sharp),
              let picture = await Self.compose(sharp, veil: parts.veil, aspect: Double(size.width / size.height))
        else { return nil }
        Self.memory.setObject(picture, forKey: key as NSString, cost: Self.cost(picture))
        // on disk after it is on screen: nobody waits for the file
        Task(priority: .utility) { await Self.writeAmbient(picture, to: file) }
        return picture
    }

    /// See `ambient`. The box's aspect decides the crop; the photograph is drawn at scale 1, the veil
    /// scaled to fill the same crop.
    @concurrent private nonisolated static func compose(_ photo: UIImage, veil soft: UIImage, aspect: Double) async -> UIImage? {
        guard let sharp = photo.cgImage, let veil = soft.cgImage else { return nil }
        let source = Size(width: Double(sharp.width), height: Double(sharp.height))
        // the part of the photograph a box of this aspect shows when the photograph fills it
        let cropWidth = min(source.width, source.height * aspect)
        let width = max(1, Int(cropWidth.rounded()))
        let height = max(1, Int((cropWidth / aspect).rounded()))
        let box = Size(width: Double(width), height: Double(height))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = bitmap(width: width, height: height, space: space),
              let fade = CGGradient(colorSpace: space,
                                    colorComponents: heroFade.flatMap { [0, 0, 0, CGFloat($0.shown)] },
                                    locations: heroFade.map { CGFloat($0.at) }, count: heroFade.count)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(veil, in: filling(Size(width: Double(veil.width), height: Double(veil.height)), box))
        // the sharp photograph alone in a layer, its alpha cut by the fade, then laid over the veil
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.draw(sharp, in: filling(source, box))
        context.setBlendMode(.destinationIn)
        // Core Graphics counts y up from the bottom: the fade's top is the bitmap's last row
        context.drawLinearGradient(fade, start: CGPoint(x: 0, y: box.height), end: CGPoint(x: 0, y: 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.endTransparencyLayer()
        guard let out = context.makeImage() else { return nil }
        return UIImage(cgImage: out)
    }

    /// Where a picture of size `image` lands when it fills `box` as `scaledToFill` lays it out
    /// (`Size.point`), as a rect in Core Graphics' bottom-up coordinates.
    private nonisolated static func filling(_ image: Size, _ box: Size) -> CGRect {
        let top = image.point(0, 0, filling: box)
        let bottom = image.point(image.width, image.height, filling: box)
        let height = bottom.y - top.y
        return CGRect(x: top.x, y: box.height - top.y - height, width: bottom.x - top.x, height: height)
    }

    /// Off the main thread, decoded here rather than at its first draw. ImageIO reads the file by
    /// its content: HEIC, or the JPEG written where HEIC could not be (`writeAmbient`).
    @concurrent private nonisolated static func readAmbient(_ file: URL) async -> UIImage? {
        guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else { return nil }
        return await image.byPreparingForDisplay() ?? image
    }

    /// Whole or not at all, as HEIC, or as JPEG (0.85) where HEIC cannot be made. A cache: a picture
    /// that cannot be written is composed again at a later launch.
    @concurrent private nonisolated static func writeAmbient(_ picture: UIImage, to file: URL) async {
        guard let data = picture.heicData() ?? picture.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: file, options: .atomic)
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

    /// Decoded at most `maxPixel` along the long edge, and whether that is the whole source: the
    /// source's own long edge, read from its properties without decoding it again.
    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> Decoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        var whole = false
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            // the orientation may swap width and height, never the long edge
            whole = max(width, height) == max(cg.width, cg.height)
        }
        return Decoded(image: UIImage(cgImage: cg), whole: whole)
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

    /// An ambient page's colour, from its first photograph's tone, for as long as the page is open:
    /// swiping to another photograph leaves it as it is, so nothing re-colours the page while it
    /// moves. nil until that tone is known: the page stays on paper. The page holds the tone in its
    /// own state, seeded from `PhotoCache.knownTone` when it is made, so a page opened before (or
    /// read at launch) is laid on its colour from its first frame.
    static func canvas(_ first: AmbientTone?, dim: Bool) -> AmbientCanvas? {
        first.map { $0.canvas(light: $0.prefersLight, dim: dim) }
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

#if DEBUG
// MARK: - Colour check (Debug)

/// How far a photograph's colour, read from the hero's decode (`PhotoCache.derive`), lies from the
/// colour the build before read off a 96 px thumbnail: the largest difference of one channel (0–1).
nonisolated struct ToneDrift: Sendable, Identifiable {
    let src: String
    let drift: Double
    var id: String { src }

    /// Both readings of each bundled photograph, decoded here and not kept.
    @concurrent static func measure(_ photos: [Photo]) async -> [ToneDrift] {
        photos.compactMap { photo in
            guard let url = PhotoCache.bundled(photo.src), let data = try? Data(contentsOf: url),
                  let thumbnail = PhotoCache.downsample(data, maxPixel: 96)?.image.cgImage,
                  let hero = PhotoCache.downsample(data, maxPixel: PhotoCache.heroPixel)?.image.cgImage,
                  let old = AmbientTone.sample(thumbnail), let new = AmbientTone.sample(hero)
            else { return nil }
            return ToneDrift(src: photo.src, drift: max(abs(old.red - new.red), abs(old.green - new.green), abs(old.blue - new.blue)))
        }
    }
}

/// For docs/perf/2026-11-device-perf-phase4-5.md, Task 5.1 step 1: the covers and the first 20
/// Commons photographs, each group's largest drift and the largest overall.
struct ToneCheck: View {
    @Environment(AppModel.self) private var model
    @State private var covers: [ToneDrift]?
    @State private var commons: [ToneDrift]?

    var body: some View {
        List {
            group("Ảnh bìa", covers)
            group("Ảnh Commons, 20 ảnh đầu", commons)
            if let covers, let commons {
                Section {
                    LabeledContent("Lớn nhất", value: Self.text((covers + commons).map(\.drift).max()))
                } footer: {
                    Text("Đạt khi không quá 0,02.")
                }
            }
        }
        .navigationTitle("Lệch màu ảnh")
        .task {
            let coverPhotos = HomeCovers.byDay.values.map(\.photo).sorted { $0.src < $1.src }
            var seen = Set<String>()
            let commonsPhotos = model.store.places.values.compactMap(\.hero)
                .filter { $0.src.hasPrefix("commons/") && seen.insert($0.src).inserted }
                .sorted { $0.src < $1.src }
            covers = await ToneDrift.measure(coverPhotos)
            commons = await ToneDrift.measure(Array(commonsPhotos.prefix(20)))
        }
    }

    private func group(_ title: String, _ rows: [ToneDrift]?) -> some View {
        Section {
            if let rows {
                ForEach(rows) { LabeledContent($0.src, value: Self.text($0.drift)) }
            } else {
                ProgressView()
            }
        } header: {
            Text(title)
        } footer: {
            if let rows { Text("Lớn nhất: \(Self.text(rows.map(\.drift).max()))") }
        }
    }

    private static func text(_ value: Double?) -> String {
        value.map { String(format: "%.4f", $0) } ?? "—"
    }
}
#endif

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
///
/// The audio session is not touched here. `AudioSessionController.shared` takes it for a line in the
/// Speaker's category, or leaves Nghe's session as it is while Nghe listens. Its calls run off the main
/// thread, in the order they were issued, and it releases the session half a second after the last line.
@Observable final class Speaker: NSObject {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private(set) var speaking: String?
    /// `speaking != nil`, readable from Nghe's audio thread: the microphone's buffers are dropped
    /// while the app speaks, so Nghe does not write down the app's own voice (`.measurement` has no
    /// echo cancelling)
    let voice = SpeakingFlag()
    /// the line waiting for its session calls, spoken from their completion
    @ObservationIgnored private var waiting: AVSpeechUtterance?
    /// bumped by every `say`: only the latest line waiting is spoken
    @ObservationIgnored private var lines = 0

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ ja: String, slow: Bool = false) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: ja)
        u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        u.rate = slow ? 0.38 : AVSpeechUtteranceDefaultSpeechRate
        // the button and Nghe's mute answer the tap at once; the voice follows the session
        speaking = ja
        voice.set(true)
        lines += 1
        let line = lines
        waiting = u
        // Spoken only once every session call issued before it has run. Otherwise the synthesizer would
        // activate the session itself, in whatever category it has, and `.soloAmbient` stops the music
        // instead of ducking it. Spoken even if the session refused: the synthesizer then tries on its own.
        AudioSessionController.shared.say { [weak self] _ in self?.speak(line) }
    }

    private func speak(_ line: Int) {
        guard line == lines, let u = waiting else { return }
        waiting = nil
        synth.speak(u)
    }

    /// An utterance ended or was cut off. Once nothing is left to say, the music ducked for it comes back
    /// up: the session is released half a second later, unless a line or Nghe comes first. Right after a
    /// line, a deactivation fails while the voice winds down.
    fileprivate func ended(_ text: String) {
        // The same line again cuts this one off: still speaking it. A line waiting for the session cut it
        // off: still to speak.
        guard !synth.isSpeaking, waiting == nil else { return }
        if speaking == text {
            speaking = nil
            voice.set(false)
        }
        AudioSessionController.shared.ended()
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

/// The app's audio session, as `AudioSessionController` drives it. Each call is made on the controller's
/// queue, never on the main thread. A failed call is thrown on to the controller, which stops that step
/// there and tells `failed` once the failure is final: only then is it logged (Console, subsystem
/// tech.delphyra.jp27, category audio). A deactivation refused as busy and made good by its retry logs
/// nothing, so each `setActive false failed` line is one counted in Chẩn đoán's "nhả lỗi".
nonisolated struct SystemAudioSession: AudioSessionPort {
    private static let log = Logger(subsystem: "tech.delphyra.jp27", category: "audio")

    func current() -> AudioSetup {
        let session = AVAudioSession.sharedInstance()
        return AudioSetup(session.category, session.mode, session.categoryOptions)
    }

    func setCategory(_ setup: AudioSetup) throws {
        try AVAudioSession.sharedInstance().setCategory(AVAudioSession.Category(rawValue: setup.category),
                                                        mode: AVAudioSession.Mode(rawValue: setup.mode),
                                                        options: AVAudioSession.CategoryOptions(rawValue: setup.options))
    }

    func activate() throws {
        try AVAudioSession.sharedInstance().setActive(true)
    }

    func deactivate() throws {
        try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func isBusy(_ error: any Error) -> Bool {
        (error as NSError).code == AVAudioSession.ErrorCode.isBusy.rawValue
    }

    func failed(_ call: AudioSessionOwners.Call, _ error: any Error) {
        let what = switch call {
        case .setCategory(let setup): "setCategory \(setup.category)"
        case .activate: "setActive true"
        case .deactivate: "setActive false"
        }
        Self.log.error("\(what, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
    }
}

extension AudioSetup {
    nonisolated init(_ category: AVAudioSession.Category, _ mode: AVAudioSession.Mode, _ options: AVAudioSession.CategoryOptions) {
        self.init(category: category.rawValue, mode: mode.rawValue, options: options.rawValue)
    }
}

extension AudioSessionController {
    /// The app's one audio session, shared by the Speaker and Nghe.
    static let shared = AudioSessionController(
        port: SystemAudioSession(),
        // the Speaker: mixable and ducking what else plays, heard with the Ring/Silent switch on silent
        speaker: AudioSetup(.playback, .spokenAudio, [.duckOthers]),
        // Nghe: `.measurement` cancels no echo, so what the app reads aloud reaches the microphone, and
        // Nghe's tap drops it (`Speaker.voice`)
        listener: AudioSetup(.playAndRecord, .measurement, [.duckOthers, .defaultToSpeaker]))
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

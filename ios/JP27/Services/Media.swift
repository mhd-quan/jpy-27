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
///
/// A photo is decoded once where once will do: a decode is kept under the size it came out at
/// (`DecodePlan`), so the 800 px of a Commons WebP that the home's day card asked for at 1200 also
/// serve the day page's 1800; and an album page's veil and tone are derived from the very decode its
/// photograph is drawn from (`derive`), off this actor. The album page then draws one picture made
/// from the two (`ambient`), kept in memory and on disk.
actor PhotoCache {
    static let shared = PhotoCache()

    /// what an album page asks its photographs at (`AmbientPhoto`): the decode their veil and tone are
    /// derived from, so they share the photograph's
    nonisolated static let albumPixel: CGFloat = 1800

    /// NSCache locks itself. Sized for the home's covers (about 8 MB each, whole) and a few pages'
    /// photos; the system empties it under memory pressure. A decode serves every ask it can
    /// (`cached`), so the home's day cards and the day pages draw from the covers' decodes instead
    /// of holding a second copy of each.
    nonisolated(unsafe) private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 128 * 1024 * 1024
        return cache
    }()
    /// the sizes each photo was decoded at (by src), and whether each was the whole photo, for
    /// `cached` to find one that serves an ask; an entry the cache has since let go of is simply a miss
    private nonisolated static let decodes = OSAllocatedUnfairLock<[String: [DecodePlan.Size: Bool]]>(initialState: [:])
    /// loads in flight, by photo and ask, so the views, the veil and the tone asking for the same
    /// photo share one decode
    private var loading: [String: Load] = [:]
    /// numbers the loads, so each clears only its own entry
    private var loads = 0
    /// derivations in flight, by photo: a veil and a tone asked for together share one
    private var deriving: [String: Task<(held: Derived, newTone: Bool), Never>] = [:]
    /// album pictures being made, by key (`AmbientFrame.key`): the page and a prefetch of it share one, which is
    /// cancelled when the last of them stops waiting
    private var composing: [String: Making] = [:]
    /// the makings so far, numbering each: a waiter that leaves late does not count against a later one
    private var makings = 0
    /// the latest write of the tones file: waiting out its second, or writing
    private var saving: Task<Void, Never>?
    /// photo src → the average of its lower band, kept on disk: a page opened before (or read at
    /// launch, see `warmTones`) is laid on its colour from its first frame instead of fading into it
    /// halfway through the zoom that opens it
    private nonisolated static let tones = OSAllocatedUnfairLock<[String: AmbientTone]>(initialState: readTones())
    /// On the CPU: the veil's input is 160 px, cheaper to blur here than to queue on the GPU, which
    /// is busy drawing the transition the veil arrives in. CIContext is thread-safe: every derivation
    /// shares this one, none of them on this actor.
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
    /// The album pictures on disk (`ambient`): one JPEG per photo and hero size, named by `AmbientFrame.fileName`. A
    /// cache, made again from the photos at any time: in Caches, held to 40 MB at launch (`trimAmbient`).
    private nonisolated static let ambientFolder: URL = {
        let url = URL.cachesDirectory.appending(path: "Ambient", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// One decode under way: whether it may download, and its number.
    private nonisolated struct Load: Sendable {
        let id: Int
        let network: Bool
        let task: Task<UIImage?, Never>
    }

    /// One decode: the image, and the pixel size of the photo it was read from (nil when ImageIO does
    /// not say), which tells a copy from the whole photo exactly.
    nonisolated struct Decode: Sendable {
        let image: UIImage
        let source: DecodePlan.Size?
    }

    /// What an album page lays under and around a photograph, derived from one decode of it.
    nonisolated struct Derived: Sendable {
        /// a small, heavily blurred copy, laid under the sharp one where it dissolves into the page
        let veil: UIImage?
        /// the colour of its foot (`AmbientTone.sample`)
        let tone: AmbientTone?
    }

    nonisolated static func bundled(_ src: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(src)
    }

    private nonisolated static func file(for url: URL) -> URL {
        var h: UInt64 = 5381
        for b in url.absoluteString.utf8 { h = (h &<< 5) &+ h &+ UInt64(b) }
        return folder.appendingPathComponent(String(h, radix: 36) + ".img")
    }

    /// a decode's name in the cache: the photo and the pixels it came out at
    private nonisolated static func key(_ photo: Photo, _ size: DecodePlan.Size) -> NSString {
        "\(photo.src)@\(size.width)x\(size.height)" as NSString
    }

    private nonisolated static func veilKey(_ photo: Photo) -> NSString {
        "\(photo.src)@veil" as NSString
    }

    /// The photo, if a decode of it serves this size (`DecodePlan.serves`): the whole photo for any
    /// ask, else a copy at most twice as large as asked (more than that costs more to draw than a
    /// decode of its own). For a view's first frame.
    nonisolated static func cached(_ photo: Photo, maxPixel: CGFloat = 1200) -> UIImage? {
        let asked = Int(maxPixel)
        let known = decodes.withLock { $0[photo.src] } ?? [:]
        // the smallest that serves: every one that does is at least the ask, or else the whole photo
        let serving = known.filter { DecodePlan.serves(decoded: $0.key, sourceIsFull: $0.value, asked: asked) }.keys
        for size in serving.sorted(by: { $0.longest < $1.longest }) {
            if let hit = memory.object(forKey: key(photo, size)) { return hit }
        }
        return nil
    }

    /// The photo's veil, if it was blurred already.
    nonisolated static func cachedVeil(_ photo: Photo) -> UIImage? {
        memory.object(forKey: veilKey(photo))
    }

    /// The colour of the photo's foot, if it was ever read.
    nonisolated static func knownTone(_ photo: Photo) -> AmbientTone? {
        tones.withLock { $0[photo.src] }
    }

    func image(_ photo: Photo, maxPixel: CGFloat = 1200) async -> UIImage? {
        await decoded(photo, maxPixel: maxPixel, network: true)
    }

    /// The photo at this size: from the cache, from a load under way for the same ask, or loaded now
    /// and kept. A load that may not download (a tone's) is shared too; an ask that may download and
    /// finds it came back empty loads again, from the network.
    private func decoded(_ photo: Photo, maxPixel: CGFloat, network: Bool) async -> UIImage? {
        if let hit = Self.cached(photo, maxPixel: maxPixel) { return hit }
        let ask = "\(photo.src)@\(Int(maxPixel))"
        if let running = loading[ask] {
            let image = await running.task.value
            guard image == nil, network, !running.network else { return image }
            // cleared here too, in case its own caller has not run yet: the ask below must not find it
            if loading[ask]?.id == running.id { loading[ask] = nil }
            return await decoded(photo, maxPixel: maxPixel, network: true)
        }
        loads += 1
        let id = loads
        // kept as soon as it is decoded, before anyone waiting on it goes on
        let task = Task { () -> UIImage? in
            guard let made = await Self.load(photo, maxPixel: maxPixel, network: network) else { return nil }
            return Self.keep(made, of: photo, asked: maxPixel)
        }
        loading[ask] = Load(id: id, network: network, task: task)
        let image = await task.value
        if loading[ask]?.id == id { loading[ask] = nil }
        return image
    }

    /// Keeps a decode under the size it came out at, and hands back the one kept: a decode the size of
    /// one already held (two asks that both got the whole photo) leaves the held one in place, so a
    /// view drawing it is not handed a new image.
    private nonisolated static func keep(_ made: Decode, of photo: Photo, asked maxPixel: CGFloat) -> UIImage {
        let image = made.image
        guard let cg = image.cgImage else { return image }
        let size = DecodePlan.Size(width: cg.width, height: cg.height)
        let full = DecodePlan.isFull(decoded: size, source: made.source, asked: Int(maxPixel))
        return decodes.withLock { decodes -> UIImage in
            // the whole photo, once seen to be, stays so: the same pixels from a decode with no size in its header,
            // asked at exactly the photo's size, cannot tell
            let wasFull = decodes[photo.src]?[size] ?? false
            decodes[photo.src, default: [:]][size] = full || wasFull
            let name = key(photo, size)
            if let held = memory.object(forKey: name) { return held }
            memory.setObject(image, forKey: name, cost: cg.width * cg.height * 4)
            return image
        }
    }

    /// Reads (from the bundle, the disk, or the network once) and decodes, on a background thread.
    @concurrent private nonisolated static func load(_ photo: Photo, maxPixel: CGFloat, network: Bool) async -> Decode? {
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
        // one per ImageIO decode, for Instruments (os_signpost), named by its photo (a bundle path or a public
        // URL) and the size asked: a photo on screen is decoded once
        Perf.signposter.emitEvent("photo.decode", "\(photo.src, privacy: .public) @\(Int(maxPixel), privacy: .public)")
        return downsample(data, maxPixel: maxPixel)
    }

    /// Read (from the bundle or the disk, never the network) and decoded, and not kept: for work in
    /// the background (the widget's photos) that should neither download what nobody asked for nor
    /// push the photos on screen out of memory.
    nonisolated static func decodeLocal(_ photo: Photo, maxPixel: CGFloat) async -> UIImage? {
        await load(photo, maxPixel: maxPixel, network: false)?.image
    }

    /// Bundled, or downloaded already: read without the network.
    private nonisolated static func onPhone(_ photo: Photo) -> Bool {
        if photo.isBundled { return true }
        guard let url = URL(string: photo.src) else { return false }
        return FileManager.default.fileExists(atPath: file(for: url).path)
    }

    /// `onPhone`, looked up off the main thread: what a prefetch (`Prefetch`) may load without the network.
    @concurrent nonisolated static func isOnPhone(_ photo: Photo) async -> Bool {
        onPhone(photo)
    }

    /// The average colour of the photograph's lower band, read once and kept: what an ambient page is
    /// tinted with, so the photograph dissolves into its own colour. Read from the decode the page
    /// draws, with the veil; never downloaded for, nor waited on: a photo not on the phone yet leaves
    /// its page on paper.
    func tone(_ photo: Photo) async -> AmbientTone? {
        if let hit = Self.knownTone(photo) { return hit }
        guard Self.onPhone(photo) else { return nil }
        return await derived(photo, network: false)?.tone
    }

    /// Reads the colour of every photograph a page opens on, once, in the background, from what is
    /// in the bundle or on disk (nothing is downloaded for it). Kept on disk, so it is done once.
    func warmTones(_ photos: [Photo]) async {
        var seen = Set<String>()
        let missing = photos.filter { seen.insert($0.src).inserted && Self.knownTone($0) == nil }
        guard !missing.isEmpty, await Self.sampleTones(missing) > 0 else { return }
        saveTonesSoon()
    }

    /// The tone of each photo on the phone, from the decode an album page would draw: the one in
    /// memory, else read and decoded here and not kept, with no veil (some three hundred at launch
    /// would push the photos on screen out of memory). Each is known as soon as it is read. How many
    /// were new.
    @concurrent private nonisolated static func sampleTones(_ photos: [Photo]) async -> Int {
        var found = 0
        for photo in photos {
            var image = cached(photo, maxPixel: albumPixel)
            if image == nil { image = await load(photo, maxPixel: albumPixel, network: false)?.image }
            guard let full = image?.cgImage, let tone = AmbientTone.sample(full) else { continue }
            let new = tones.withLock { tones -> Bool in
                guard tones[photo.src] == nil else { return false }
                tones[photo.src] = tone
                return true
            }
            if new { found += 1 }
        }
        return found
    }

    /// 2: read from the decode an album page draws (`derive`), no longer from a 96 px thumbnail. The
    /// file of version 1 is not read: a cache, read again from the photos (`warmTones` at launch, a
    /// page as it opens). Versioned with `AmbientTone.sample` too: a change there reads every photo again.
    private nonisolated static var tonesFile: URL { folder.appendingPathComponent("tones-2.json") }

    private nonisolated static func readTones() -> [String: AmbientTone] {
        guard let data = try? Data(contentsOf: tonesFile),
              let raw = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        return raw.compactMapValues { $0.count == 3 ? AmbientTone(red: $0[0], green: $0[1], blue: $0[2]) : nil }
    }

    /// One write of the tones file per round of new tones (a page opening, the launch's warm-up): a
    /// second after the last new one. Each of these tasks ends only after the one before it, whether it
    /// writes or was cancelled by a later round, so the writes run one at a time, in the order they were
    /// asked for, and the file never goes back to an older set.
    private func saveTonesSoon() {
        let previous = saving
        previous?.cancel()
        saving = Task {
            // cut short when a later round cancels this one
            try? await Task.sleep(for: .seconds(1))
            // before anything else, cancelled or not: a cancelled task that ended at once would let the
            // next one write beside a write still running before it
            await previous?.value
            // a later round took over: it writes, with this one's tones
            guard !Task.isCancelled else { return }
            Perf.signposter.emitEvent("photo.tones")
            await Self.writeTones(Self.tones.withLock { $0 })
        }
    }

    @concurrent private nonisolated static func writeTones(_ tones: [String: AmbientTone]) async {
        let raw = tones.mapValues { [$0.red, $0.green, $0.blue] }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        try? data.write(to: tonesFile, options: .atomic)
    }

    /// A small, heavily blurred copy of the photograph, laid under the sharp one where it dissolves
    /// into the page. Blurred once, from the decode the page draws, so nothing is blurred live while
    /// the page scrolls; drawn at full width the upscaled blur only gets softer.
    func veil(_ photo: Photo) async -> UIImage? {
        if let hit = Self.cachedVeil(photo) { return hit }
        return await derived(photo, network: true)?.veil
    }

    /// The photo's veil and tone, derived once from the decode its album page draws (`albumPixel`), off
    /// this actor: a veil and a tone asked for together share the decode and the derivation.
    private func derived(_ photo: Photo, network: Bool) async -> Derived? {
        if let held = Self.held(photo) { return held }
        guard let full = await decoded(photo, maxPixel: Self.albumPixel, network: network)?.cgImage else { return nil }
        if let running = deriving[photo.src] { return await running.value.held }
        // a derivation may have finished while this one was decoding
        if let held = Self.held(photo) { return held }
        // kept as soon as it is derived, before anyone waiting on it goes on
        let task = Task { () -> (held: Derived, newTone: Bool) in
            let derived = await Self.derive(full)
            return Self.keep(derived, of: photo)
        }
        deriving[photo.src] = task
        let (held, newTone) = await task.value
        deriving[photo.src] = nil
        if newTone { saveTonesSoon() }
        return held
    }

    /// both, if both are held already
    private nonisolated static func held(_ photo: Photo) -> Derived? {
        guard let veil = cachedVeil(photo), let tone = knownTone(photo) else { return nil }
        return Derived(veil: veil, tone: tone)
    }

    /// Keeps what a derivation found that was not held yet, and hands back what is held: a veil
    /// already drawn stays the one drawn, a tone read before stays the page's colour. Whether the
    /// tone is new, for the tones file.
    private nonisolated static func keep(_ derived: Derived, of photo: Photo) -> (held: Derived, newTone: Bool) {
        var veil = cachedVeil(photo)
        if veil == nil, let made = derived.veil, let cg = made.cgImage {
            memory.setObject(made, forKey: veilKey(photo), cost: cg.width * cg.height * 4)
            veil = made
        }
        let (tone, new) = tones.withLock { tones -> (AmbientTone?, Bool) in
            if let known = tones[photo.src] { return (known, false) }
            guard let found = derived.tone else { return (nil, false) }
            tones[photo.src] = found
            return (found, true)
        }
        return (Derived(veil: veil, tone: tone), new)
    }

    /// The veil and the tone of a photograph, from the decode its page draws, off any actor: the veil is
    /// the photograph drawn into 160 px and blurred; the tone is read from the whole of it.
    @concurrent nonisolated static func derive(_ full: CGImage) async -> Derived {
        Derived(veil: veilBase(full).flatMap(blurred).map { UIImage(cgImage: $0) }, tone: AmbientTone.sample(full))
    }

    /// The photograph drawn into 160 px on its longest side (never enlarged): what the veil blurs.
    private nonisolated static func veilBase(_ full: CGImage) -> CGImage? {
        let scale = min(1, 160 / Double(max(full.width, full.height)))
        let w = max(1, Int((Double(full.width) * scale).rounded()))
        let h = max(1, Int((Double(full.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    private nonisolated static func blurred(_ base: CGImage) -> CGImage? {
        let input = CIImage(cgImage: base)
        // clamped first, so the edges blur into themselves instead of into transparency
        let soft = input.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        return filters.createCGImage(soft, from: input.extent)
    }

    // MARK: Album pictures

    /// An album page's photograph as one picture, made once: its veil filling the hero and the sharp photo over it,
    /// fading out from the middle down (`AmbientFrame`), in the hero's shape at the photo's own pixels. The zoom, a
    /// swipe and a scroll then move a finished picture: no mask, no flattening, nothing drawn again on the way. From
    /// memory; else from `Caches/Ambient` (made on an earlier launch); else made now from the decode the page draws
    /// (`albumPixel`, downloaded if need be, as the photo itself is) and its veil, off this actor, and kept in both.
    /// One making per picture at a time: the page and a prefetch of it share it. It is background work (contract
    /// § 4.2), so it stops when the last of them stops waiting (the page went away, or shows another photo): it is
    /// then neither kept nor written, and the next to ask starts again. Not asked for in Low Power Mode, where the
    /// page shows only a picture made before (`savedAmbient`).
    func ambient(_ photo: Photo, size: CGSize) async -> UIImage? {
        guard let frame = Self.frame(size) else { return nil }
        let key = AmbientFrame.key(src: photo.src, frame: frame)
        if let hit = Self.memory.object(forKey: key as NSString) { return hit }
        guard !Task.isCancelled else { return nil }
        let making: Making
        if var running = composing[key] {
            running.waiters += 1
            composing[key] = running
            making = running
        } else {
            makings += 1
            making = Making(id: makings, task: Task { await self.composed(photo, frame: frame, key: key) }, waiters: 1)
            composing[key] = making
        }
        let id = making.id
        let image = await withTaskCancellationHandler {
            await making.task.value
        } onCancel: {
            // called off this actor, at once: the count is kept on it
            Task { await self.leave(key, making: id) }
        }
        if composing[key]?.id == id { composing[key] = nil }
        return image
    }

    /// The album picture if it was made before: from memory, else from `Caches/Ambient`. Never made here.
    func savedAmbient(_ photo: Photo, size: CGSize) async -> UIImage? {
        guard let frame = Self.frame(size) else { return nil }
        let key = AmbientFrame.key(src: photo.src, frame: frame)
        if let hit = Self.memory.object(forKey: key as NSString) { return hit }
        return await readSaved(photo, frame: frame, key: key)
    }

    /// One making of an album picture, and how many wait for it.
    private nonisolated struct Making: Sendable {
        let id: Int
        let task: Task<UIImage?, Never>
        var waiters: Int
    }

    /// A waiter of `ambient` stopped waiting: the making goes on for the others; with none left it is cancelled, and
    /// whoever asks next starts a new one.
    private func leave(_ key: String, making id: Int) {
        guard var making = composing[key], making.id == id else { return }
        making.waiters -= 1
        if making.waiters > 0 {
            composing[key] = making
        } else {
            making.task.cancel()
            composing[key] = nil
        }
    }

    /// The album picture, if memory has it: for a view's first frame.
    nonisolated static func cachedAmbient(_ photo: Photo, size: CGSize) -> UIImage? {
        guard let key = ambientKey(photo, size: size) else { return nil }
        return memory.object(forKey: key as NSString)
    }

    /// The album picture's name (`AmbientFrame.key`): the photo and its hero in whole points; nil for an empty hero.
    nonisolated static func ambientKey(_ photo: Photo, size: CGSize) -> String? {
        frame(size).map { AmbientFrame.key(src: photo.src, frame: $0) }
    }

    private nonisolated static func frame(_ size: CGSize) -> AmbientFrame.Frame? {
        AmbientFrame.Frame(width: Double(size.width), height: Double(size.height))
    }

    /// From the disk, else made from the photo, and kept on disk when it is whole (opaque). Cancelled (`leave`): it
    /// stops after the decode, after the veil or once composed, and keeps and writes nothing. The decode and the veil
    /// it waited for are shared with the photo's other uses, and kept.
    private func composed(_ photo: Photo, frame: AmbientFrame.Frame, key: String) async -> UIImage? {
        if let saved = await readSaved(photo, frame: frame, key: key) { return saved }
        guard let full = await decoded(photo, maxPixel: Self.albumPixel, network: true)?.cgImage,
              !Task.isCancelled else { return nil }
        // the veil from that same decode (and its tone, kept as it is read)
        let veil = await derived(photo, network: true)?.veil?.cgImage
        guard !Task.isCancelled, let made = await Self.compose(full, veil: veil, frame: frame),
              !Task.isCancelled else { return nil }
        Self.markAmbient(photo, frame, "made")
        let kept = Self.keepAmbient(made.image, as: key)
        // nobody waits for the file: the next launch reads it, or makes the picture again
        let name = AmbientFrame.fileName(key: key)
        if made.opaque { Task(priority: .utility) { await Self.storeAmbient(kept, as: name) } }
        return kept
    }

    /// The picture from `Caches/Ambient`, kept in memory.
    private func readSaved(_ photo: Photo, frame: AmbientFrame.Frame, key: String) async -> UIImage? {
        guard let saved = await Self.readAmbient(AmbientFrame.fileName(key: key)) else { return nil }
        Self.markAmbient(photo, frame, "disk")
        return Self.keepAmbient(saved, as: key)
    }

    private nonisolated static func keepAmbient(_ image: UIImage, as key: String) -> UIImage {
        memory.setObject(image, forKey: key as NSString,
                         cost: Int(image.size.width * image.scale * image.size.height * image.scale) * 4)
        return image
    }

    /// One `photo.ambient` event per album picture made or read from the disk, for Instruments (os_signpost):
    /// "<src> <width>x<height> made|disk", the hero in points. A page seen before makes none.
    private nonisolated static func markAmbient(_ photo: Photo, _ frame: AmbientFrame.Frame, _ how: String) {
        Perf.signposter.emitEvent("photo.ambient", "\(photo.src, privacy: .public) \(frame.width, privacy: .public)x\(frame.height, privacy: .public) \(how, privacy: .public)")
    }

    /// A picture and whether it is whole: opaque when the veil fills it, the only kind kept on disk (a JPEG has no
    /// transparency).
    private nonisolated struct Composite: Sendable {
        let image: UIImage
        let opaque: Bool
    }

    /// The veil filling the frame and the sharp photo over it, fading out under `AmbientFrame.fade`, drawn once into a
    /// picture of the frame's shape at the photo's own pixels (`AmbientFrame.canvas`), off any actor. The sharp photo
    /// is drawn at its own size, so the screen samples it as it did when the layers were drawn live. With no veil (its
    /// blur failed), the faded part is left transparent, over the page's colour.
    @concurrent private nonisolated static func compose(_ full: CGImage, veil: CGImage?, frame: AmbientFrame.Frame) async -> Composite? {
        let source = DecodePlan.Size(width: full.width, height: full.height)
        guard let canvas = AmbientFrame.canvas(source: source, frame: frame),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let opaque = veil != nil
        let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
        guard let context = CGContext(data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8,
                                      bytesPerRow: canvas.width * 4, space: space, bitmapInfo: alpha.rawValue),
              let fade = fadeGradient(in: space) else { return nil }
        context.interpolationQuality = .high
        if let veil {
            context.draw(veil, in: rect(AmbientFrame.fill(DecodePlan.Size(width: veil.width, height: veil.height), into: canvas)))
        }
        let whole = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        // the sharp photo on a layer of its own, its alpha multiplied by the fade's (destination-in), then laid over
        // the veil
        context.beginTransparencyLayer(in: whole, auxiliaryInfo: nil)
        context.draw(full, in: rect(AmbientFrame.fill(source, into: canvas)))
        // destination-in for the fade alone: the layer is laid over the veil in the normal mode, whatever Core
        // Graphics would do with a blend mode still set when it ends
        context.saveGState()
        context.setBlendMode(.destinationIn)
        // from the picture's top, which a bitmap context puts at y = height, to its bottom at y = 0
        context.drawLinearGradient(fade, start: CGPoint(x: 0, y: whole.height), end: .zero,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        context.restoreGState()
        context.endTransparencyLayer()
        guard let picture = context.makeImage() else { return nil }
        return Composite(image: UIImage(cgImage: picture), opaque: opaque)
    }

    /// `AmbientFrame.fade` as black at each stop's strength: only its alpha counts
    private nonisolated static func fadeGradient(in space: CGColorSpace) -> CGGradient? {
        let stops = AmbientFrame.fade
        let components: [CGFloat] = stops.flatMap { [0, 0, 0, CGFloat($0.shown)] }
        let locations: [CGFloat] = stops.map { CGFloat($0.at) }
        return CGGradient(colorSpace: space, colorComponents: components, locations: locations, count: stops.count)
    }

    private nonisolated static func rect(_ r: AmbientFrame.Rect) -> CGRect {
        CGRect(x: r.x, y: r.y, width: r.width, height: r.height)
    }

    /// Read and decoded off any actor; the read is its last use, for the trim.
    @concurrent private nonisolated static func readAmbient(_ name: String) async -> UIImage? {
        let file = ambientFolder.appendingPathComponent(name, isDirectory: false)
        guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path(percentEncoded: false))
        return image.preparingForDisplay() ?? image
    }

    /// Encoded and written off any actor, whole or not at all; a cache, so a failed write is made again next time.
    @concurrent private nonisolated static func storeAmbient(_ image: UIImage, as name: String) async {
        guard let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        try? jpeg.write(to: ambientFolder.appendingPathComponent(name, isDirectory: false), options: .atomic)
    }

    /// At launch: the least recently used pictures go until the folder's pictures fit in `budget` bytes
    /// (`AmbientFrame.evicted`). In this folder only, and only the pictures' own names from its listing.
    @concurrent nonisolated static func trimAmbient(toBytes budget: Int) async {
        let files = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? files.contentsOfDirectory(at: ambientFolder, includingPropertiesForKeys: keys) else { return }
        let listed = urls.compactMap { url -> AmbientFrame.StoredFile? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return AmbientFrame.StoredFile(name: url.lastPathComponent, bytes: values.fileSize ?? 0,
                                           used: values.contentModificationDate ?? .distantPast)
        }
        for name in AmbientFrame.evicted(listed, toBytes: budget) {
            try? files.removeItem(at: ambientFolder.appendingPathComponent(name, isDirectory: false))
        }
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

    /// Decoded to `maxPixel` on its longest side, never enlarged; with the photo's own pixel size, from
    /// its header (as stored: an EXIF turn swaps the sides, the longest stays the longest).
    nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> Decode? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Decode(image: UIImage(cgImage: cg), source: pixelSize(of: source))
    }

    /// The photo's pixel size from its header, nil when ImageIO does not give it.
    private nonisolated static func pixelSize(of source: CGImageSource) -> DecodePlan.Size? {
        guard let header = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = header[kCGImagePropertyPixelWidth] as? Int, let height = header[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return DecodePlan.Size(width: width, height: height)
    }
}

extension PhotoCache {
    /// For the device check of Task 5.1a (Cài đặt › Hỗ trợ › Nhà phát triển › So màu ảnh): how far the tone read from
    /// the decode an album page draws (`derive`) strays from the one the 96 px thumbnail gave before
    /// (0,02 a channel at most passes), and, as the fallback, how far the tone of the veil's 160 px
    /// base, before its blur, strays. Read from the bundle; nothing is kept.
    @concurrent nonisolated static func toneDrift(_ photos: [Photo]) async -> String {
        var whole = Drift(), base = Drift()
        var count = 0
        for photo in photos {
            guard let thumb = await load(photo, maxPixel: 96, network: false)?.image.cgImage, let old = AmbientTone.sample(thumb),
                  let full = await load(photo, maxPixel: albumPixel, network: false)?.image.cgImage else { continue }
            count += 1
            if let tone = await derive(full).tone { whole.take(tone, against: old, photo) }
            if let tone = veilBase(full).flatMap(AmbientTone.sample) { base.take(tone, against: old, photo) }
        }
        return "\(count) ảnh. Từ ảnh nguyên: lệch \(whole.text). Từ nền 160 px: lệch \(base.text)"
    }

    /// the largest difference of one channel between two tones, and where
    private nonisolated struct Drift {
        var most = 0.0
        var channel = "—"
        var src = ""

        mutating func take(_ tone: AmbientTone, against old: AmbientTone, _ photo: Photo) {
            for (name, d) in [("R", abs(tone.red - old.red)), ("G", abs(tone.green - old.green)), ("B", abs(tone.blue - old.blue))] where d > most {
                (most, channel, src) = (d, name, photo.src)
            }
        }

        var text: String { "\(Fmt.decimal(most, digits: 3)) (\(channel)) \(src)" }
    }
}

// MARK: - Prefetch

/// A page loaded before it opens, so it opens with its photograph, its colour and its map in the first frame: a
/// day's page as its card comes to rest in the home's carousel, or as a finger comes down on the card; a place's
/// page as a finger comes down on the home's cover photo. It asks exactly what the page asks (`DayPage`, the
/// page's own photo and decode size, its hero's size and its map's key), so what it makes is what the page finds.
///
/// Background work (contract § 4.2): at most three at once, the newest winning (`NewestFew`), each a task that can
/// be cancelled; never the network for a photograph (the page downloads its own when it opens); in Low Power Mode
/// only on a touch, and no album picture is made (`AmbientPicture` makes none either).
///
/// What a cancel reaches: the album picture's making stops once nobody else waits for it (`PhotoCache.ambient`),
/// and nothing after the step under way starts. A photo's veil and tone, once begun, finish (they are shared, and
/// kept), and so does a map's picture once drawing (`MapSnapshots.snapshot`, one per key).
enum Prefetch {
    /// When it is asked for.
    enum Moment: String {
        /// the card came to rest in the middle: the map may be drawn, there is time before a touch
        case rest
        /// a finger came down on it: the page is about to open, so nothing is drawn on the main thread now (the map
        /// only from memory or the disk), and it goes first
        case touch

        var priority: TaskPriority {
            switch self {
            case .rest: .utility
            case .touch: .userInitiated
            }
        }
    }

    /// The page a day opens into, measured on the home (`TodayHome`), which sits in the same navigation stack, under
    /// the same bars, as the day page it pushes: the width, the length `heroFrame` measures
    /// (`containerRelativeFrame`, the scroll view less its safe area), the screen's scale, the system's dark.
    nonisolated struct Page: Codable, Equatable, Sendable {
        let width: CGFloat
        let length: CGFloat
        let scale: CGFloat
        let dark: Bool

        /// a page that could be one: finite, at least a point each way, a screen's scale
        var plausible: Bool {
            width.isFinite && length.isFinite && scale.isFinite && width >= 1 && length >= 1 && scale >= 1 && scale <= 4
        }
    }

    private static let pageKey = "prefetch.page"

    /// The page as the home measured it last (`TodayHome`), kept across launches: the size the day maps are
    /// counted and drawn at for use without signal (`OfflineReadiness`). Nil until measured, or when what is
    /// kept cannot be read back as a page. Written only when it changes.
    static var lastPage: Page? {
        get {
            guard let data = UserDefaults.standard.data(forKey: pageKey),
                  let page = try? JSONDecoder().decode(Page.self, from: data), page.plausible else { return nil }
            return page
        }
        set {
            guard newValue != lastPage else { return }
            if let newValue, newValue.plausible, let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: pageKey)
            } else if newValue == nil {
                UserDefaults.standard.removeObject(forKey: pageKey)
            }
        }
    }

    /// the day page's hero on `page` (`heroFrame(fraction: DayPage.heroFraction)`)
    private static func heroSize(_ page: Page) -> CGSize {
        CGSize(width: page.width, height: CGFloat(AmbientFrame.heroHeight(length: Double(page.length), fraction: Double(DayPage.heroFraction))))
    }

    /// the day page's map on `page`: the page less its gutters, `DayPage.mapHeight` tall
    private static func mapSize(_ page: Page) -> CGSize {
        CGSize(width: page.width - 2 * Metrics.gutter, height: DayPage.mapHeight)
    }

    private static var slots = NewestFew<String>(limit: 3)
    private static var tasks: [NewestFew<String>.Ticket: Task<Void, Never>] = [:]
    /// runs a touch asked for again while they ran (started at a rest): from then on they draw no map, as a touch
    /// does not (the page is about to open; a draw already under way is left to finish, the page waits for it)
    private static var touched: Set<NewestFew<String>.Ticket> = []

    /// The day's page: its photograph's colour, then its map, then its hero. `page` nil (not measured yet): only the
    /// colour and the decode, no album picture and no map, whose keys need the page's size.
    static func day(_ key: String, model: AppModel, at moment: Moment, page: Page?) {
        if moment == .rest, model.lowPower { return }
        let size = page.map { "\(Int(heroSize($0).width))x\(Int(heroSize($0).height))" } ?? "-"
        run("day:\(key)", moment, size) { ticket in
            await Prefetch.loadDay(key, model: model, moment: moment, page: page, ticket: ticket)
        }
    }

    /// The place's page, opened as a sheet: the colour, the decode and the veil of its first photograph, none of which
    /// depends on the sheet's size; its album picture is made when the sheet is up (its size is not known before).
    static func place(_ id: String, model: AppModel, at moment: Moment) {
        if moment == .rest, model.lowPower { return }
        run("place:\(id)", moment, "-") { _ in await Prefetch.loadPlace(id, model: model) }
    }

    /// Low Power Mode came on: everything under way stops (a touch then loads again).
    static func cancelAll() {
        for ticket in slots.removeAll() {
            tasks.removeValue(forKey: ticket)?.cancel()
        }
        touched.removeAll()
    }

    /// Started, unless it runs already (then raised to this priority); the oldest of three cancelled to make room.
    private static func run(_ key: String, _ moment: Moment, _ size: String,
                            _ work: @escaping @MainActor (NewestFew<String>.Ticket) async -> Void) {
        switch slots.admit(key) {
        case .running(let ticket):
            if moment == .touch { touched.insert(ticket) }
            tasks[ticket]?.escalatePriority(to: moment.priority)
        case .start(let ticket, let cancelling):
            if let cancelling {
                tasks.removeValue(forKey: cancelling)?.cancel()
                touched.remove(cancelling)
            }
            // one per prefetch started, for Instruments (os_signpost): "<key> rest|touch <hero w>x<h>"
            Perf.signposter.emitEvent("prefetch", "\(key, privacy: .public) \(moment.rawValue, privacy: .public) \(size, privacy: .public)")
            // on the main actor, as this is: stored before it can run, so its finish always finds it
            tasks[ticket] = Task(priority: moment.priority) {
                await work(ticket)
                Prefetch.finished(ticket)
            }
        }
    }

    private static func finished(_ ticket: NewestFew<String>.Ticket) {
        slots.finished(ticket)
        tasks[ticket] = nil
        touched.remove(ticket)
    }

    private static func loadDay(_ key: String, model: AppModel, moment: Moment, page: Page?, ticket: NewestFew<String>.Ticket) async {
        guard let day = model.store.day(key) else { return }
        // the page's own photograph (`DayView`)
        let photo = HomePicks.photo(for: day, store: model.store)
        var local = false
        if let photo { local = await PhotoCache.isOnPhone(photo) }
        // the colour first: the page reads it as it is made (`PageTone`), and the map's scheme follows it. From the
        // phone only, never the network (`tone`), which also decodes the photo at the page's size and blurs its veil
        if let photo, local { _ = await PhotoCache.shared.tone(photo) }
        guard !Task.isCancelled else { return }
        if let page { await dayMap(day, photo: photo, model: model, moment: moment, page: page, ticket: ticket) }
        guard !Task.isCancelled, let photo, local else { return }
        await dayHero(photo, page: page, lowPower: model.lowPower)
    }

    /// The map's picture under the key the page will ask (`StaticTripMap` in `PlanDayHeader`): from memory or the disk,
    /// and drawn only at a rest, only when the scheme is known (no photograph, or its colour read), and not once a
    /// touch has asked for the run (`touched`). A picture drawn under another key than the page's would prune the
    /// page's own from the disk (`MapSnapshots.store`).
    private static func dayMap(_ day: Day, photo: Photo?, model: AppModel, moment: Moment, page: Page,
                               ticket: NewestFew<String>.Ticket) async {
        guard let ask = await dayMapAsk(day, photo: photo, model: model, page: page), !Task.isCancelled else { return }
        let request = ask.request
        // read here, after the last wait and just before the draw: a touch that came during the colour or the
        // fingerprint keeps this run from drawing
        if moment == .rest, ask.known, !touched.contains(ticket) {
            _ = await MapSnapshots.shared.snapshot(for: request)
        } else {
            _ = await MapSnapshots.shared.stored(request)
        }
    }

    /// A day's map picture as the offline readiness and Tải tất cả count it. A day whose page sets its own scheme (a
    /// photograph's colour, or Giao diện on Sáng or Tối) needs the picture in that scheme. One whose page follows the
    /// system's light and dark (no photograph, Giao diện on "Tự động": day 12 today) turns with sunrise and sunset, and
    /// a picture of either scheme counts for it (`Readiness.dayMapReady`, R-640). The pruning of a frame's other
    /// pictures is left as it is (`SnapshotKey.stale`): one picture of the day stays on disk.
    struct DayMapPicture {
        /// the picture the day page asks for now: the one drawn when none that counts is on disk
        let request: MapSnapshots.Request
        /// the same picture in the other scheme, for a day that follows the system's; nil for any other day
        let other: MapSnapshots.Request?

        /// Whether a picture that counts is on disk (memory is not asked). The other scheme is looked for only where
        /// it counts, and only when the page's own is not there.
        func isOnDisk() async -> Bool {
            let own = await MapSnapshots.shared.isOnDisk(request)
            var otherOnDisk = false
            if !own, let other { otherOnDisk = await MapSnapshots.shared.isOnDisk(other) }
            return Readiness.dayMapReady(own: own, other: otherOnDisk, followsSystem: other != nil)
        }

        /// What the launch trim spares for no signal (`MapSnapshots.offlineKeep`): every picture that counts.
        var stems: [String] {
            [request.key.stem] + (other.map { [$0.key.stem] } ?? [])
        }
    }

    /// The picture of a day's map the day page will ask for on `page` (`PlanDayHeader`'s `StaticTripMap`), for the
    /// offline readiness count and for drawing it ahead (Task 6), with the other scheme's where it counts too. Nil when
    /// the page's light or dark cannot be told yet: the day has a photograph whose colour has not been read
    /// (`PhotoCache.knownTone`), and a picture asked for in the system's scheme then would be the wrong one, and would
    /// prune the right one once drawn.
    static func dayMapRequest(_ day: Day, photo: Photo?, model: AppModel, page: Page) async -> DayMapPicture? {
        guard let ask = await dayMapAsk(day, photo: photo, model: model, page: page), ask.known else { return nil }
        return DayMapPicture(request: ask.request, other: ask.other)
    }

    /// What `dayMap` and `dayMapRequest` both ask, made in one place so the two never name different pictures: the
    /// content, the frame, the insets, the size, the scale and the scheme of the day page's map, and whether that
    /// scheme is known (no photograph, or its colour read); for a day whose scheme follows the system's, the same
    /// picture in the other scheme. Nil for a page too narrow for a map.
    private static func dayMapAsk(_ day: Day, photo: Photo?, model: AppModel, page: Page) async
        -> (request: MapSnapshots.Request, known: Bool, other: MapSnapshots.Request?)? {
        let size = mapSize(page)
        guard size.width >= 1 else { return nil }
        let system: ColorScheme = page.dark ? .dark : .light
        // the colour the page will be made with: read when it is made, as here (`PageTone.init`)
        let canvas = PageTone(photo).canvas(dim: page.dark)
        let known = photo == nil || canvas != nil
        let own = DayPage.mapScheme(photo: photo, canvas: canvas, system: system)
        let scheme = own ?? system
        // the system's own light and dark, not one Giao diện sets (what `RootView` applies, read as it stores it)
        let automatic = (Appearance(rawValue: UserDefaults.standard.string(forKey: Appearance.key) ?? "") ?? .system) == .system
        let printed = await fingerprinted(.day(day, model: model))
        let request = MapSnapshots.Request(printed, frameID: day.key, insets: DayPage.mapInsets, size: size,
                                           scale: page.scale, dark: scheme == .dark)
        let other = own == nil && automatic
            ? MapSnapshots.Request(printed, frameID: day.key, insets: DayPage.mapInsets, size: size, scale: page.scale,
                                   dark: scheme != .dark)
            : nil
        return (request, known, other)
    }

    /// The day's hero: its album picture at the page's hero size; in Low Power Mode, or with no page measured, the
    /// picture made before if any, else the decode the page shows in its place.
    private static func dayHero(_ photo: Photo, page: Page?, lowPower: Bool) async {
        if let page, !lowPower {
            _ = await PhotoCache.shared.ambient(photo, size: heroSize(page))
            return
        }
        if let page, await PhotoCache.shared.savedAmbient(photo, size: heroSize(page)) != nil { return }
        guard !Task.isCancelled else { return }
        _ = await PhotoCache.shared.image(photo, maxPixel: PhotoCache.albumPixel)
    }

    private static func loadPlace(_ id: String, model: AppModel) async {
        // the page's first photograph (`Place.gallery`): the one its colour is taken from (`PlanAmbientPage`), and its
        // hero's first page
        guard let photo = model.store.place(id)?.leadPhoto, await PhotoCache.isOnPhone(photo),
              !Task.isCancelled else { return }
        // the decode at the page's size, its veil and its colour, in one derivation; on the phone, so nothing downloads
        _ = await PhotoCache.shared.veil(photo)
        guard !Task.isCancelled else { return }
        // the decode, if a veil and a colour read before left it out of memory
        _ = await PhotoCache.shared.image(photo, maxPixel: PhotoCache.albumPixel)
    }

    /// The map's content with its fingerprint, which reads every point: off the main thread.
    @concurrent private nonisolated static func fingerprinted(_ content: MapContent) async -> FingerprintedContent {
        FingerprintedContent(content)
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
            // the pass is over: one line, never one per photo
            let stopped = Task.isCancelled
            let fields = ["saved": "\(saved)", "failed": "\(failed)", "total": "\(list.count)", "paused": "\(stopped)"]
            if failed > 0 { AppLog.warning(.offline, "Ảnh tải xong", fields) } else { AppLog.info(.offline, "Ảnh tải xong", fields) }
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
                withAnimation(Motion.arrive) { image = loaded }
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
        // 3: a place with a home cover shows the cover, the photograph its page opens on (`Place.leadPhoto`)
        let version = "3:\(store.trip.places.count)"
        let before = Shared.defaults.string(forKey: "heroes")
        guard before != version else { return }
        let ids = Set(store.trip.days.flatMap(\.items).compactMap { $0.stop?.place } + store.trip.altDays.flatMap(\.items).compactMap { $0.stop?.place })
        let photos: [(String, Photo)] = ids.compactMap { id in store.place(id)?.leadPhoto.map { (id, $0) } }
        // made before version 3 from the Commons photograph: written again from the cover
        let redo: Set<String> = before?.hasPrefix("3:") == true ? [] : Set(ids.filter { HomeCovers.byPlace[$0] != nil })
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
                if FileManager.default.fileExists(atPath: target.path), !redo.contains(id) { continue }
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

/// Reads Japanese aloud with the on-device voice, so a phrase can be played to staff. The audio session is not
/// touched here: `AudioSessionController` decides what it needs, and its queue does it, in order with Nghe's.
@Observable final class Speaker: NSObject {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private(set) var speaking: String?
    /// `speaking != nil`, readable from Nghe's audio thread: the microphone's buffers are dropped
    /// while the app speaks, so Nghe does not write down the app's own voice (`.measurement` has no
    /// echo cancelling)
    let voice = SpeakingFlag()
    /// lines asked for so far: only the one asked for last is read
    @ObservationIgnored private var asked = 0
    /// the line asked for last, until the session work decided for it has run
    @ObservationIgnored private var waiting: (line: Int, utterance: AVSpeechUtterance)?

    override init() {
        super.init()
        synth.delegate = self
    }

    /// Reads `ja`; `slow` true for "Đọc chậm", nil for the pace chosen in Settings (`SpeechPace`).
    func say(_ ja: String, slow: Bool? = nil) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let u = AVSpeechUtterance(string: ja)
        u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        u.rate = (slow ?? (SpeechPace.current == .slow)) ? SpeechPace.slowRate : AVSpeechUtteranceDefaultSpeechRate
        asked += 1
        let line = asked
        waiting = (line, u)
        speaking = ja
        voice.set(true)
        // the Speaker's category (none while Nghe listens: the line goes through its recording session as it
        // is), set on the audio queue behind whatever was decided before. The line is read once that has run,
        // so it never starts in another category, nor in a session whose deactivation was already queued.
        AudioSessionController.send(.speakerWillSpeak) { _ in self.read(line) }
    }

    /// The session work decided for `line` has run (a failed category is logged, and the line read all the
    /// same): it is read, unless another line was asked for since.
    private func read(_ line: Int) {
        guard let w = waiting, w.line == line else {
            // a newer line was asked for; if it was read and ended already, nothing is left to say
            settle()
            return
        }
        waiting = nil
        synth.speak(w.utterance)
    }

    /// Nothing is being read and no line waits: the session goes back after a beat (the Speaker's release, in
    /// `AudioSessionController`), and the music ducked for the lines comes back up.
    fileprivate func settle() {
        guard speaking != nil, waiting == nil, !synth.isSpeaking else { return }
        speaking = nil
        voice.set(false)
        AudioSessionController.send(.speakerDone)
    }
}

/// Settings › Trải nghiệm › Đọc tiếng Nhật: the pace of the plain read button (a tap, the show card, a station's
/// announcement). "Đọc chậm" is slow whatever is chosen.
nonisolated enum SpeechPace: String, CaseIterable, Identifiable, Sendable {
    case normal, slow

    static let key = "talk.pace"
    /// the slow reading's rate, for "Đọc chậm" and for this choice
    static let slowRate: Float = 0.38

    var id: String { rawValue }

    var label: String {
        switch self {
        case .normal: "Bình thường"
        case .slow: "Chậm"
        }
    }

    /// as stored by the Settings picker (`@AppStorage`, the standard defaults); normal when unset
    static var current: SpeechPace {
        UserDefaults.standard.string(forKey: key).flatMap(SpeechPace.init(rawValue:)) ?? .normal
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
    /// An utterance ended, or was cut off by the next line.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.settle() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.settle() }
    }
}

// MARK: - Audio session

/// The app's one audio session, shared by the Speaker and Nghe. What to do with it is decided here, on the main
/// actor and in the order things happen (`AudioSessionPlan`). The session calls run off the main thread, on one
/// serial queue, in that same order (`AudioSessionQueue`).
@MainActor enum AudioSessionController {
    private static var plan = AudioSessionPlan()
    private static let queue = AudioSessionQueue()
    /// the wait before the Speaker's release; the plan's generation, not this cancel, makes a stale one harmless
    private static var release: Task<Void, Never>?
    /// the system's audio services restarting, watched from the first event on
    private static var resetWatch: (any NSObjectProtocol)?

    /// Decides on `event` now and queues its session work at once, behind everything decided before it. `done`
    /// runs on the main actor once that work has run, even when there was none, with the step that failed.
    /// Returns the generation the work was decided under: Nghe's ticket after `.listenerStarting`.
    @discardableResult
    static func send(_ event: AudioSessionPlan.Event,
                     done: (@MainActor @Sendable (AudioSessionFailure?) -> Void)? = nil) -> Int {
        watchReset()
        let commands = plan.handle(event)
        let generation = plan.generation
        run(commands, generation: generation, done: done)
        return generation
    }

    private static func run(_ commands: [AudioSessionPlan.Command], generation: Int,
                            done: (@MainActor @Sendable (AudioSessionFailure?) -> Void)?) {
        // a batch with no steps still goes through the queue, so `done` runs after every batch before it
        enqueue(schedule(commands), generation: generation, done: done)
    }

    /// The waits a decision asks for, started or cancelled here; returns its session steps, in order.
    private static func schedule(_ commands: [AudioSessionPlan.Command]) -> [AudioSessionPlan.Step] {
        var steps: [AudioSessionPlan.Step] = []
        for command in commands {
            switch command {
            case .session(let step):
                steps.append(step)
            case .cancelRelease:
                release?.cancel()
                release = nil
            case .release(let after, let due):
                release?.cancel()
                release = Task {
                    do { try await Task.sleep(for: .milliseconds(after)) } catch { return }
                    send(.releaseDue(generation: due))
                }
            case .retry(let after, let due):
                // the wait is on the audio queue; whether the retry is still wanted is decided here
                queue.after(milliseconds: after) {
                    Task { @MainActor in send(.retryDue(generation: due)) }
                }
            }
        }
        return steps
    }

    private static func enqueue(_ steps: [AudioSessionPlan.Step], generation: Int,
                                done: (@MainActor @Sendable (AudioSessionFailure?) -> Void)?) {
        queue.run(steps) { failure in
            Task { @MainActor in
                // the plan learns of a failure before anyone waiting on the batch goes on
                if let failure { failed(failure, generation: generation) }
                done?(failure)
            }
        }
    }

    /// A step failed: never hidden. A deactivation refused as busy is tried once more; anything else is an error.
    private static func failed(_ failure: AudioSessionFailure, generation: Int) {
        let commands = plan.handle(.failed(failure.failure, generation: generation))
        let step = String(describing: failure.failure.step)
        if commands.contains(where: { if case .retry = $0 { true } else { false } }) {
            AppLog.warning(.talk, "Phiên âm thanh bận, thử lại", ["step": step, "after": "\(AudioSessionPlan.busyRetryAfter)", "error": failure.message])
        } else {
            AppLog.error(.talk, "Phiên âm thanh lỗi", ["step": step, "error": failure.message])
        }
        // the plan answers a failure with a retry's wait or nothing: no step, and nobody waits on it, so no batch
        let steps = schedule(commands)
        if !steps.isEmpty { enqueue(steps, generation: plan.generation, done: nil) }
    }

    /// After a media services reset the session's category is the default again: the plan forgets the one it set.
    private static func watchReset() {
        guard resetWatch == nil else { return }
        resetWatch = NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in AudioSessionController.send(.mediaServicesReset) }
        }
    }
}

/// A session step that threw: what the plan learns, and what the log says.
nonisolated struct AudioSessionFailure: Error {
    let failure: AudioSessionPlan.Failure
    let message: String
}

/// The audio session's calls, off the main thread and in order: one serial queue, one block per batch of the
/// plan's steps. A batch stops at its first failing step: what follows it was decided on it succeeding.
nonisolated final class AudioSessionQueue: Sendable {
    private let queue = DispatchQueue(label: "jp27.audio-session")
    /// the session's setup from before Nghe (`capturePrior`), given back by `restorePrior`; only the queue's
    /// blocks touch it
    private let prior = Mutex<Setup?>(nil)

    nonisolated struct Setup: Sendable {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions
    }

    /// `steps` in one block on the queue, then `done` there with the first failure.
    func run(_ steps: [AudioSessionPlan.Step], done: @escaping @Sendable (AudioSessionFailure?) -> Void) {
        queue.async { done(self.execute(steps)) }
    }

    /// `work` on the queue once `milliseconds` have passed.
    func after(milliseconds: Int, _ work: @escaping @Sendable () -> Void) {
        queue.asyncAfter(deadline: .now() + .milliseconds(milliseconds), execute: work)
    }

    private func execute(_ steps: [AudioSessionPlan.Step]) -> AudioSessionFailure? {
        let session = AVAudioSession.sharedInstance()
        for step in steps {
            do {
                try execute(step, on: session)
            } catch {
                // `AVAudioSession.ErrorCode` is no Error type: the code is read from the NSError
                let busy = (error as NSError).code == AVAudioSession.ErrorCode.isBusy.rawValue
                return AudioSessionFailure(failure: AudioSessionPlan.Failure(step: step, busy: busy),
                                           message: error.localizedDescription)
            }
        }
        return nil
    }

    private func execute(_ step: AudioSessionPlan.Step, on session: AVAudioSession) throws {
        switch step {
        case .setCategory(let setup):
            let values = Self.values(setup)
            try session.setCategory(values.category, mode: values.mode, options: values.options)
        case .capturePrior:
            let now = Setup(category: session.category, mode: session.mode, options: session.categoryOptions)
            prior.withLock { $0 = now }
        case .restorePrior:
            let kept = prior.withLock { value in
                let kept = value
                value = nil
                return kept
            }
            if let kept { try session.setCategory(kept.category, mode: kept.mode, options: kept.options) }
        case .activate:
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        case .deactivate:
            // what another app plays comes back up
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// The one place each setup's values are written. The Speaker's: mixable and ducking what else plays, heard
    /// with the Ring/Silent switch on silent. Nghe's: recording through the speaker, ducking what else plays.
    private static func values(_ setup: AudioSessionPlan.Setup) -> Setup {
        switch setup {
        case .speaker: Setup(category: .playback, mode: .spokenAudio, options: [.duckOthers])
        case .listener: Setup(category: .playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        }
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

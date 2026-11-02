import AVFoundation
import CoreImage
import Foundation
import Observation
import os
import Photos
import SwiftUI
import TripKit
import UIKit

// MARK: - Place photos

/// Photos of places: the self-hosted Commons set ships in the bundle (commons/…); restaurant photos
/// are remote and kept on disk once seen, or all at once from Settings before the flight.
actor PhotoCache {
    static let shared = PhotoCache()

    private let memory = NSCache<NSString, UIImage>()
    /// photo src → the average of its lower band
    private var tones: [String: AmbientTone] = [:]
    private let filters = CIContext(options: [.cacheIntermediates: false])
    private let folder: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init() {
        memory.totalCostLimit = 80 * 1024 * 1024
    }

    nonisolated static func bundled(_ src: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent(src)
    }

    private func file(for url: URL) -> URL {
        var h: UInt64 = 5381
        for b in url.absoluteString.utf8 { h = (h &<< 5) &+ h &+ UInt64(b) }
        return folder.appendingPathComponent(String(h, radix: 36) + ".img")
    }

    func image(_ photo: Photo, maxPixel: CGFloat = 1200) async -> UIImage? {
        let key = "\(photo.src)@\(Int(maxPixel))" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        var data: Data?
        if photo.isBundled {
            data = PhotoCache.bundled(photo.src).flatMap { try? Data(contentsOf: $0) }
        } else if let url = URL(string: photo.src) {
            let disk = file(for: url)
            data = try? Data(contentsOf: disk)
            if data == nil, let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
                try? d.write(to: disk)
                data = d
            }
        }
        guard let data, let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        memory.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
        return image
    }

    /// The average colour of the photograph's lower band, read once from a small thumbnail and kept:
    /// what an ambient page is tinted with, so the photograph dissolves into its own colour.
    func tone(_ photo: Photo) async -> AmbientTone? {
        if let hit = tones[photo.src] { return hit }
        guard let small = await image(photo, maxPixel: 96), let cg = small.cgImage, let tone = AmbientTone.sample(cg) else { return nil }
        tones[photo.src] = tone
        return tone
    }

    /// A small, heavily blurred copy of the photograph, laid under the sharp one where it dissolves
    /// into the page. Blurred once, here, so nothing is blurred live while the page scrolls; drawn
    /// at full width the upscaled blur only gets softer.
    func veil(_ photo: Photo) async -> UIImage? {
        let key = "\(photo.src)@veil" as NSString
        if let hit = memory.object(forKey: key) { return hit }
        guard let small = await image(photo, maxPixel: 160), let cg = small.cgImage else { return nil }
        let input = CIImage(cgImage: cg)
        // clamped first, so the edges blur into themselves instead of into transparency
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 6).cropped(to: input.extent)
        guard let out = filters.createCGImage(blurred, from: input.extent) else { return nil }
        let image = UIImage(cgImage: out)
        memory.setObject(image, forKey: key, cost: out.width * out.height * 4)
        return image
    }

    /// Download every remote photo of the trip, for use without signal. Returns how many are on disk.
    func prefetch(_ photos: [Photo], progress: @Sendable (Double) -> Void) async -> Int {
        let remote = photos.filter { !$0.isBundled }.compactMap { URL(string: $0.src) }
        var done = 0
        for (i, url) in remote.enumerated() {
            let disk = file(for: url)
            if FileManager.default.fileExists(atPath: disk.path) {
                done += 1
            } else if let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
                try? d.write(to: disk)
                done += 1
            }
            progress(Double(i + 1) / Double(max(1, remote.count)))
        }
        return done
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
}

/// A place photo, filled edge to edge; a quiet placeholder while it loads or when there is none.
struct PlacePhoto: View {
    let photo: Photo?
    var maxPixel: CGFloat = 1200
    @State private var image: UIImage?

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
                let loaded = await PhotoCache.shared.image(photo, maxPixel: maxPixel)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }
}

// MARK: - Widget photos

/// Small JPEGs of each planned place in the App Group, for the widget's background.
enum HeroExporter {
    static func exportIfNeeded(store: TripStore) async {
        let version = "1:\(store.trip.places.count)"
        guard Shared.defaults.string(forKey: "heroes") != version else { return }
        let ids = Set(store.trip.days.flatMap(\.items).compactMap { $0.stop?.place } + store.trip.altDays.flatMap(\.items).compactMap { $0.stop?.place })
        let photos: [(String, Photo)] = ids.compactMap { id in store.place(id)?.hero.map { (id, $0) } }
        await Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: Shared.heroes, withIntermediateDirectories: true)
            for (id, photo) in photos {
                let target = Shared.hero(id)
                if FileManager.default.fileExists(atPath: target.path) { continue }
                guard let image = await PhotoCache.shared.image(photo, maxPixel: 800), let jpeg = image.jpegData(compressionQuality: 0.72) else { continue }
                try? jpeg.write(to: target)
            }
        }.value
        Shared.defaults.set(version, forKey: "heroes")
    }
}

// MARK: - Japanese voice

/// Reads Japanese aloud with the on-device voice, so a phrase can be played to staff.
@Observable final class Speaker: NSObject {
    static let shared = Speaker()
    private let synth = AVSpeechSynthesizer()
    private(set) var speaking: String?

    override init() {
        super.init()
        synth.delegate = self
    }

    func say(_ ja: String, slow: Bool = false) {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let u = AVSpeechUtterance(string: ja)
        u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        u.rate = slow ? 0.38 : AVSpeechUtteranceDefaultSpeechRate
        speaking = ja
        synth.speak(u)
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = nil }
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

    /// Photos taken between two instants, nearest the place first when it is known.
    func photos(from: Date, to: Date, near: Coordinate? = nil, radiusKm: Double = 0.3, limit: Int = 12) -> [PHAsset] {
        guard allowed else { return [] }
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate <= %@ AND mediaType == %d", from as NSDate, to as NSDate, PHAssetMediaType.image.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        let result = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in list.append(asset) }
        guard let near else { return Array(list.prefix(limit)) }
        let scored = list.compactMap { a -> (PHAsset, Double)? in
            guard let l = a.location else { return (a, radiusKm) }
            let d = Geo.km(near, Coordinate(l.coordinate.latitude, l.coordinate.longitude))
            return d <= radiusKm * 2 ? (a, d) : nil
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(limit).map(\.0)
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

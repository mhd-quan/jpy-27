import AVFoundation
import Foundation
import Observation
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
                    var resumed = false
                    PHImageManager.default().requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: options) { img, info in
                        let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        guard !degraded, !resumed else { return }
                        resumed = true
                        cont.resume(returning: img)
                    }
                }
            }
    }
}

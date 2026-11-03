import Foundation

// Offline map areas: what one pack holds, where its download is, and when a download the travellers
// started is done. The app (OfflineMaps, Downloads) reads MapLibre and asks these; nothing here knows
// MapLibre, so the rules run in the Linux tests.

/// The tile build a map reads or a pack holds: its tile URL template. A pack keeps tiles by URL, so a
/// pack of one build is no use to a map that asks for another.
public struct TileBuild: Codable, Sendable, Hashable {
    public let template: String

    public init(template: String) {
        self.template = template
    }
}

/// What a style or a TileJSON says about itself.
public enum StyleInfo {
    /// The tile build of a style: the first URL template of its `omt` source. Nil for a style whose
    /// tiles come from a TileJSON (`url`, the `-current` styles): the TileJSON names the build.
    public static func build(style: Data) -> TileBuild? {
        build((try? JSONDecoder().decode(StyleTiles.self, from: style))?.sources?.omt?.tiles)
    }

    /// The tile build a TileJSON names now (its first URL template).
    public static func build(tileJSON: Data) -> TileBuild? {
        build((try? JSONDecoder().decode(Source.self, from: tileJSON))?.tiles)
    }

    /// The name of an exported style (`metadata["jp27:build"]`, scripts/export-ios.mjs): its tile
    /// build and a hash of its content. The site serves that very style for good at
    /// `map/jp27-<theme>@<name>.json`, so a pack can be made from the style the app was built with.
    public static func styleBuild(style: Data) -> String? {
        guard let name = (try? JSONDecoder().decode(StyleName.self, from: style))?.metadata?.build, !name.isEmpty else { return nil }
        return name
    }

    private static func build(_ tiles: [String]?) -> TileBuild? {
        guard let template = tiles?.first, !template.isEmpty else { return nil }
        return TileBuild(template: template)
    }

    // Each reader decodes only its own part of the style, so an odd value in the other part hides nothing.
    private struct StyleTiles: Decodable {
        let sources: Sources?
    }

    private struct StyleName: Decodable {
        let metadata: Metadata?
    }

    private struct Metadata: Decodable {
        let build: String?
        enum CodingKeys: String, CodingKey { case build = "jp27:build" }
    }

    /// Only the basemap's source is read: the others may hold anything.
    private struct Sources: Decodable {
        let omt: Source?
    }

    private struct Source: Decodable {
        let tiles: [String]?
    }
}

/// `MLNOfflinePackState`, by the same raw values (MLNOfflinePack.h): `PackState(rawValue: pack.state.rawValue)`.
public enum PackState: Int, Sendable {
    /// read from storage and not asked yet (`requestProgress`)
    case unknown = 0
    /// not complete, not downloading: just made, suspended, or back after a relaunch
    case inactive = 1
    case active = 2
    case complete = 3
    /// removed, or its database entry is gone: nothing may be asked of it
    case invalid = 4
}

/// What a pack was made for, kept as its context: the area, the tile build its style really held when
/// it was made, and the style's URL.
public struct PackTag: Codable, Sendable, Hashable {
    public var v = 2
    public let area: String
    public let build: TileBuild
    public let styleURL: String

    public init(area: String, build: TileBuild, styleURL: String) {
        self.area = area
        self.build = build
        self.styleURL = styleURL
    }

    /// The pack's context. Encoding strings cannot fail; if it ever did, the area alone (read as an
    /// untagged pack: stale, made again).
    public var context: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(self)) ?? Data(area.utf8)
    }

    /// The tag of a pack made by this version. Nil for older packs (`{"area", "tiles"}`, whose tiles were
    /// the app's and not the downloaded style's, or the bare area), and for anything else.
    public static func read(_ context: Data) -> PackTag? {
        guard let tag = try? JSONDecoder().decode(PackTag.self, from: context), tag.v == 2 else { return nil }
        return tag
    }

    /// The area a pack of any version was made for: to show it per area, and to remove it when the area
    /// is downloaded again.
    public static func area(of context: Data) -> String? {
        if let area = (try? JSONDecoder().decode(Legacy.self, from: context))?.area {
            return area.isEmpty ? nil : area
        }
        // the first packs: the area id itself
        guard let plain = String(data: context, encoding: .utf8), !plain.isEmpty,
              plain.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" })
        else { return nil }
        return plain
    }

    private struct Legacy: Decodable {
        let area: String
    }
}

/// Where one area is.
public enum AreaPhase: Sendable, Hashable {
    /// asked for, nothing known yet
    case requested
    /// the pack is being made (its style read, its build checked)
    case creating
    case downloading(completed: UInt64, expected: UInt64)
    /// MapLibre reported an error and is trying again by itself
    case waitingForNetwork
    case paused
    case complete(TileBuild)
    /// made for another build than the map reads (nil: by an older version, build unknown)
    case stale(TileBuild?)
    case failed(String)
}

public enum OfflineArea {
    static let broken = "Vùng tải đã hỏng, tải lại"

    /// Where a pack is, from what MapLibre says of it.
    ///
    /// - `state`: read first. An invalid pack raises on any other message (MLNOfflinePack.h), so its
    ///   caller has no tag for it: it is broken, whatever the tag.
    /// - `tag`: `PackTag.read` of its context; nil (an older pack) is stale, as is a pack of a build the
    ///   map (`mapBuild`) does not read.
    /// - `error`: the last error MapLibre reported since the pack last moved, if any.
    /// - `previous`: the phase the app holds for the area. A complete pack stays complete: resumed, it
    ///   counts its resources again from 0 (MLNOfflinePack.h), which is not a pack losing its tiles.
    ///   A pack not known yet (`unknown`) keeps it too.
    public static func phase(state: PackState, completed: UInt64, expected: UInt64, maximum: UInt64, tag: PackTag?,
                             mapBuild: TileBuild, error: String?, previous: AreaPhase? = nil) -> AreaPhase {
        if state == .invalid { return .failed(broken) }
        guard let tag else { return .stale(nil) }
        guard tag.build == mapBuild else { return .stale(tag.build) }
        // every resource counted, and the count is final (`maximum` is UInt64.max until it is)
        let counted = expected > 0 && completed >= expected && maximum == expected
        if counted || previous == .complete(mapBuild) { return .complete(mapBuild) }
        switch state {
        case .complete: return .complete(mapBuild)
        case .unknown: return previous ?? .requested
        case .inactive: return .paused
        case .active: return error == nil ? .downloading(completed: completed, expected: expected) : .waitingForNetwork
        case .invalid: return .failed(broken) // returned above, before the tag
        }
    }
}

/// One download the travellers started (a tap): its areas and whether it takes the photos. Saved, so
/// it is picked up again at the next launch.
public struct OfflineJob: Codable, Sendable {
    public let areas: Set<String>
    public let photos: Bool

    public init(areas: Set<String>, photos: Bool) {
        self.areas = areas
        self.photos = photos
    }

    /// How the job ended (or stands): a success only when every area holds the map's build and, when
    /// the job takes the photos, every photo is on disk and they were not paused. A job without the
    /// photos does not look at them.
    public func result(phases: [String: AreaPhase], photos state: PhotoState, mapBuild: TileBuild) -> JobResult {
        let photos = self.photos ? state : .finished
        // the failed ones are among those left; either count may be the larger one the app knows
        let photosLeft = max(photos.left, photos.failed)
        var done = 0
        var failed: [String] = []
        var paused = photos.paused
        for id in areas {
            switch phases[id] {
            case .complete(let b) where b == mapBuild: done += 1
            case .complete, .stale, .failed: failed.append(id)
            case .paused: paused = true
            case .requested, .creating, .downloading, .waitingForNetwork, nil: break
            }
        }
        let success = done == areas.count && photosLeft == 0 && !photos.paused
        let subtitle: String
        if success {
            subtitle = "Xong"
        } else if paused {
            subtitle = "Đã dừng"
        } else {
            var parts: [String] = []
            if !areas.isEmpty { parts.append("Bản đồ \(done)/\(areas.count) vùng") }
            if !failed.isEmpty { parts.append("\(failed.count) lỗi") }
            if photosLeft > 0 { parts.append("\(photosLeft) ảnh chưa tải được") }
            subtitle = parts.joined(separator: " · ")
        }
        return JobResult(success: success, done: done, failed: failed.sorted(), paused: paused, subtitle: subtitle)
    }
}

/// The photos of a job, as `OfflinePhotos` has them when the job ends.
public struct PhotoState: Sendable, Equatable {
    /// failed in this download
    public let failed: Int
    /// not on disk yet, the failed ones included
    public let left: Int
    /// stopped by the travellers or by the system
    public let paused: Bool

    public init(failed: Int, left: Int, paused: Bool) {
        self.failed = failed
        self.left = left
        self.paused = paused
    }
    /// every photo on disk
    public static let finished = PhotoState(failed: 0, left: 0, paused: false)
}

public struct JobResult: Sendable, Equatable {
    public let success: Bool
    /// areas complete for the map's build
    public let done: Int
    /// areas that failed or hold another build, sorted
    public let failed: [String]
    /// an area or the photos were stopped where they were
    public let paused: Bool
    /// "Xong", "Đã dừng", or "Bản đồ 8/10 vùng · 2 lỗi"
    public var subtitle: String
}

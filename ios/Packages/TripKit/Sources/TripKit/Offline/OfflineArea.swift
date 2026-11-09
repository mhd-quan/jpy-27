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

    /// The style on another tile build: its basemap's tiles at `template` (where a TileJSON `url` was, it
    /// goes), and without the `jp27:` metadata, which names the bundled build and its immutable copy on the
    /// site, neither of which this style is. The rest is left as it was. Nil for anything without a basemap.
    public static func pointing(style: Data, at template: String) -> Data? {
        guard var json = try? JSONSerialization.jsonObject(with: style) as? [String: Any],
              var sources = json["sources"] as? [String: Any],
              var omt = sources["omt"] as? [String: Any]
        else { return nil }
        omt["url"] = nil
        omt["tiles"] = [template]
        sources["omt"] = omt
        json["sources"] = sources
        if var metadata = json["metadata"] as? [String: Any] {
            for key in Array(metadata.keys) where key.hasPrefix("jp27:") { metadata[key] = nil }
            json["metadata"] = metadata.isEmpty ? nil : metadata
        }
        return try? JSONSerialization.data(withJSONObject: json)
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

    /// Whether the style's basemap takes its tiles from a TileJSON (`url`), which then names the build.
    static func readsTileJSON(style: Data) -> Bool {
        guard let url = (try? JSONDecoder().decode(StyleURL.self, from: style))?.sources?.omt?.url else { return false }
        return !url.isEmpty
    }

    private struct StyleURL: Decodable {
        let sources: Sources?
        struct Sources: Decodable { let omt: Source? }
        struct Source: Decodable { let url: String? }
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

    /// Still going: asked for, its pack being made, downloading, or waiting for the network (MapLibre tries
    /// again by itself). A download of these areas is not over.
    public var isUnderWay: Bool {
        switch self {
        case .requested, .creating, .downloading, .waitingForNetwork: true
        case .paused, .complete, .stale, .failed: false
        }
    }
}

public enum OfflineArea {
    static let broken = "Vùng tải đã hỏng, tải lại"
    /// The style stored for the pack holds another build than the map reads (the app's own style: no site
    /// in the way any more). A new launch reads the build again and stores the style for it.
    public static let otherBuild = "Style của bản đồ không khớp bản đang dùng — mở lại app rồi thử lại"

    /// The area of the whole route ("Toàn tuyến"): zoomed out, over every other area.
    public static let overviewID = "overview"

    /// The box around every box, with `pad` degrees more on each side. Nil with no box.
    public static func overview(of boxes: [(sw: Coordinate, ne: Coordinate)], pad: Double = 0.1) -> (sw: Coordinate, ne: Coordinate)? {
        guard let b = Geo.bounds(boxes.flatMap { [$0.sw, $0.ne] }) else { return nil }
        return (Coordinate(b.sw.lat - pad, b.sw.lng - pad), Coordinate(b.ne.lat + pad, b.ne.lng + pad))
    }

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

    /// What a look at the packs (MapLibre's list changed, the app opened, the map moved to another build) makes
    /// of one area.
    ///
    /// - `current`: where its pack for the map's build is (`phase`), nil when it has none.
    /// - `older`: the `.stale` phase of a pack of it made for another build or by an older version, if any.
    /// - `previous`: the phase the app holds for it.
    /// - `requested`: the travellers asked for it and it is not complete.
    /// - `making`: its pack is being made: the style read, or the pack added (`.creating`, or `.paused` by a tap
    ///   meanwhile). Over once the pack is added, or the area failed or was removed.
    ///
    /// A pack for the map's build says where the area is. Without one, an area that failed keeps its failure
    /// and one being made is left to its make: neither is made again here, since a look runs on every change of
    /// the packs (a failure is tried again by a tap, or at the next launch). An area asked for is made, one left
    /// `.creating` by a make that is over among them (the map moved while its pack was added, so that pack holds
    /// the old build). An older pack is let go only once the new one is complete: until then it is what the area has.
    public static func settle(current: AreaPhase?, older: AreaPhase?, previous: AreaPhase?, requested: Bool, making: Bool) -> Settled {
        if let current {
            let complete = if case .complete = current { true } else { false }
            return Settled(phase: current, make: false, dropOld: complete && older != nil)
        }
        if making { return Settled(phase: previous, make: false, dropOld: false) }
        switch previous {
        case .failed?: return Settled(phase: previous, make: false, dropOld: false)
        case .requested?, .creating?, .downloading?, .waitingForNetwork?, .paused?, .complete?, .stale?, nil: break
        }
        if requested { return Settled(phase: .requested, make: true, dropOld: false) }
        return Settled(phase: older, make: false, dropOld: false)
    }

    /// The tile build a pack made from this style would hold, if it is the map's: the style's own tiles, or,
    /// for a style on a TileJSON (the `-current` ones), the build the TileJSON names. Nil otherwise (another
    /// build, a page that is not a style, a TileJSON missing): such a pack would hold tiles the map never asks for.
    public static func packBuild(style: Data, tileJSON: Data?, mapBuild: TileBuild) -> TileBuild? {
        let build: TileBuild?
        if let own = StyleInfo.build(style: style) {
            build = own
        } else if StyleInfo.readsTileJSON(style: style), let tileJSON {
            build = StyleInfo.build(tileJSON: tileJSON)
        } else {
            build = nil
        }
        return build == mapBuild ? build : nil
    }

    /// The map moved to another tile build while an area's pack was being made: nothing is at fault, and a second
    /// try stores the style for the build the map reads now.
    public static let moved = "Nguồn bản đồ vừa đổi — thử lại"

    /// What a make does once it has the style (`served`) for an area's pack: the one the app stored for it
    /// (`PackStyle`), or why it has none.
    ///
    /// - `mapBuild`: the build the map reads now; `askedOn`: the one it read when the style was asked for.
    /// - `again`: this is the second read.
    ///
    /// A style holding the map's build makes the pack, of that build. A move of the map's build during the read
    /// reads the style once more; a second move fails the area with `moved`. So does a TileJSON naming a build the
    /// map does not read yet: OpenFreeMap moved on, and the map follows once the app has looked at this launch
    /// (`checkPinnedTiles`), so updating the app would not help. Otherwise the area fails with the reason given,
    /// or `otherBuild` for a style of another build.
    public static func step(_ served: ServedStyle, mapBuild: TileBuild, askedOn: TileBuild, again: Bool) -> MakeStep {
        if case .files(let style, let tileJSON) = served, let build = packBuild(style: style, tileJSON: tileJSON, mapBuild: mapBuild) {
            return .add(build)
        }
        if mapBuild != askedOn { return again ? .fail(moved) : .again }
        switch served {
        case .refused(let reason):
            return .fail(reason)
        case .files(let style, let tileJSON):
            if StyleInfo.build(style: style) == nil, StyleInfo.readsTileJSON(style: style),
               let named = tileJSON.flatMap({ StyleInfo.build(tileJSON: $0) }), named != mapBuild {
                return .fail(moved)
            }
            return .fail(otherBuild)
        }
    }
}

/// The style a pack is made from: the style and, for one on a TileJSON (the `-current` styles of earlier
/// builds), the TileJSON that names its build; or why there is none.
public enum ServedStyle: Sendable, Equatable {
    case files(style: Data, tileJSON: Data?)
    case refused(String)
}

/// What a make does once it has read the style (`OfflineArea.step`).
public enum MakeStep: Sendable, Equatable {
    /// make the pack, of this build
    case add(TileBuild)
    /// the map moved to another build during the read: read the style again
    case again
    /// the area fails, saying why
    case fail(String)
}

extension OfflineArea {
    /// What a look at the packs makes of one area (`settle`).
    public struct Settled: Sendable, Equatable {
        /// nil: nothing asked for, no pack
        public let phase: AreaPhase?
        /// make its pack now
        public let make: Bool
        /// remove its packs of another build or an older version: the one for the map's build is complete
        public let dropOld: Bool
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
    /// photos does not look at them. Its end line names what is missing: the areas failed, the ones removed
    /// during the job ("1 vùng đã xoá"), the photos not on disk.
    public func result(phases: [String: AreaPhase], photos state: PhotoState, mapBuild: TileBuild) -> JobResult {
        let photos = self.photos ? state : .finished
        // the failed ones are among those left; either count may be the larger one the app knows
        let photosLeft = max(photos.left, photos.failed)
        var done = 0
        var failed: [String] = []
        var paused = photos.paused
        // no phase once the packs are read: Xoá on its row (its packs and its request gone)
        var removed = 0
        for id in areas {
            switch phases[id] {
            case .complete(let b) where b == mapBuild: done += 1
            case .complete, .stale, .failed: failed.append(id)
            case .paused: paused = true
            case nil: removed += 1
            case .requested, .creating, .downloading, .waitingForNetwork: break
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
            if removed > 0 { parts.append("\(removed) vùng đã xoá") }
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
    /// "Xong", "Đã dừng", or "Bản đồ 7/10 vùng · 2 lỗi · 1 vùng đã xoá"
    public var subtitle: String
}

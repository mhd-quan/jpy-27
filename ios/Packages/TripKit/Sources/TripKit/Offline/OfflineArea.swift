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
        // keys sorted: the same bytes every time (a dictionary's order changes from one instance to the next), so a
        // style stored for a pack is the same at every launch, and tests compare bytes
        return try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
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

/// One download the travellers started (a tap): its areas, whether it takes the photos, and its extras (the day maps'
/// pictures, the Fuji pictures, the forecasts). Saved, so it is picked up again at the next launch. `everything`: it
/// is Tải tất cả, judged at its end by the whole readiness list.
public struct OfflineJob: Codable, Sendable {
    public let areas: Set<String>
    public let photos: Bool
    public let extras: Set<OfflineExtra>
    /// started by Tải tất cả: "Xong" only when every item of the list is ready (or this phone cannot have it)
    public let everything: Bool

    public init(areas: Set<String>, photos: Bool, extras: Set<OfflineExtra> = [], everything: Bool = false) {
        self.areas = areas
        self.photos = photos
        self.extras = extras
        self.everything = everything
    }

    private enum CodingKeys: String, CodingKey {
        case areas, photos, extras, everything
    }

    /// A job saved before the extras has neither key: no extras, not everything. A name this build does not know (a
    /// later build's, read after going back to this one) is dropped, and a value it cannot read is none: the areas and
    /// the photos are never lost over them. An earlier build reads the two keys it knows and passes over the others.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        areas = try c.decode(Set<String>.self, forKey: .areas)
        photos = try c.decode(Bool.self, forKey: .photos)
        let names = (try? c.decodeIfPresent([String].self, forKey: .extras)) ?? []
        extras = Set(names.compactMap(OfflineExtra.init(rawValue:)))
        everything = (try? c.decodeIfPresent(Bool.self, forKey: .everything)) ?? false
    }

    /// How the job ended (or stands).
    ///
    /// A success only when every area holds the map's build, and, when the job takes them: every photo is on disk and
    /// they were not paused; each of its extras was counted (`extras`, the app's states) with all of it there and not
    /// paused. An extra of the job with no state is not done; an extra not of the job is not looked at, nor are the
    /// photos of a job without them. A job of Tải tất cả (`everything`) is also judged by the readiness list as one more
    /// look found it after the job (`ready`): every item ready or one this phone cannot have, an item not read counting
    /// as not ready.
    ///
    /// Its end line is "Xong", else "Đã dừng" when anything was stopped, else what is missing, in the list's order: the
    /// maps ("Bản đồ 7/10 vùng", the areas failed, the ones removed during the job), the photos ("12 ảnh chưa tải được"),
    /// the day maps ("Ảnh bản đồ 12/13 ngày"), Fuji ("Fuji 60/69 ảnh"), the forecasts ("Dự báo chưa mới"), then for
    /// Tải tất cả the language packs ("Gói dịch chưa tải", "Gói nghe chưa tải"). Each item is said once: by the job's
    /// own count when it has one short of all, else by the look's ("chưa tải" when it could not count it).
    public func result(phases: [String: AreaPhase], photos state: PhotoState, mapBuild: TileBuild,
                       extras states: [OfflineExtra: ExtraState] = [:], ready: [ReadyItem: ReadyState] = [:]) -> JobResult {
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
        // the job's own extras, in the list's order (a set's order changes from one run to the next)
        let members = OfflineExtra.allCases.filter(extras.contains)
        var extrasDone = true
        for extra in members {
            guard let s = states[extra] else {
                extrasDone = false
                continue
            }
            if s.paused { paused = true }
            if s.paused || s.done < s.total { extrasDone = false }
        }
        let unready: Set<ReadyItem> = everything ? Set(ReadyItem.allCases.filter { !Readiness.settled(ready[$0]) }) : []
        let success = done == areas.count && photosLeft == 0 && !photos.paused && extrasDone && unready.isEmpty
        let subtitle: String
        if success {
            subtitle = "Xong"
        } else if paused {
            subtitle = "Đã dừng"
        } else {
            var parts: [String] = []
            // the job's areas, unless they are all there and the look finds the maps are not (an area of the route the
            // job did not take): then the look's count
            if !areas.isEmpty && !(done == areas.count && unready.contains(.maps)) {
                parts.append("Bản đồ \(done)/\(areas.count) vùng")
            } else if unready.contains(.maps) {
                parts.append(Self.short(ready[.maps]).map { "Bản đồ \($0.done)/\($0.total) vùng" } ?? "Bản đồ chưa tải")
            }
            if !failed.isEmpty { parts.append("\(failed.count) lỗi") }
            if removed > 0 { parts.append("\(removed) vùng đã xoá") }
            if photosLeft > 0 {
                parts.append("\(photosLeft) ảnh chưa tải được")
            } else if unready.contains(.photos) {
                parts.append(Self.short(ready[.photos]).map { "\($0.total - $0.done) ảnh chưa tải được" } ?? "Ảnh quán, khách sạn chưa tải")
            }
            for extra in OfflineExtra.allCases {
                if extras.contains(extra) {
                    guard let s = states[extra] else {
                        // not counted by the job: the look's count when it is Tải tất cả and has one
                        parts.append(extra.missing(everything ? Self.short(ready[extra.item]) : nil))
                        continue
                    }
                    if s.done < s.total {
                        parts.append(extra.missing((s.done, s.total)))
                        continue
                    }
                }
                if unready.contains(extra.item) { parts.append(extra.missing(Self.short(ready[extra.item]))) }
            }
            if unready.contains(.translation) { parts.append("Gói dịch chưa tải") }
            if unready.contains(.speech) { parts.append("Gói nghe chưa tải") }
            subtitle = parts.joined(separator: " · ")
        }
        return JobResult(success: success, done: done, failed: failed.sorted(), paused: paused, subtitle: subtitle)
    }

    /// The count of an item the look found short of all, when it could count it.
    private static func short(_ state: ReadyState?) -> (done: Int, total: Int)? {
        guard case .missing(let done?, let total?)? = state, done < total else { return nil }
        return (done, total)
    }
}

/// What a download takes besides the map areas and the photos: the items of the readiness list the app makes itself.
/// Saved with the job by their raw values.
public enum OfflineExtra: String, Codable, Sendable, CaseIterable {
    /// each day's map picture, at the page size measured last
    case dayMaps
    /// the Fuji terrain pictures of every viewpoint card and area hero
    case fuji
    /// the cloud forecasts of the summit and every viewpoint
    case forecasts

    /// Its item on the readiness list.
    public var item: ReadyItem {
        switch self {
        case .dayMaps: .dayMaps
        case .fuji: .fuji
        case .forecasts: .forecasts
        }
    }

    /// The extra an item of the readiness list is; nil for the maps, the photos and the language packs, which are not.
    public init?(_ item: ReadyItem) {
        switch item {
        case .dayMaps: self = .dayMaps
        case .fuji: self = .fuji
        case .forecasts: self = .forecasts
        case .maps, .photos, .translation, .speech: return nil
        }
    }

    /// The extras "Tải tất cả" asks for: those of its plan, and the pictures that read ready, whose pass only checks the
    /// disk, counts them again and writes their keep list (pictures ready through the pages, or under new names).
    /// A part that needs a page opened first stays out, as in the plan.
    public static func forEverything(_ s: [ReadyItem: ReadyState]) -> Set<OfflineExtra> {
        var extras = Set(Readiness.plan(s).compactMap { OfflineExtra($0) })
        for extra in [OfflineExtra.dayMaps, .fuji] where s[extra.item] == .ready { extras.insert(extra) }
        return extras
    }

    /// What the end line says of it short of all: how many of how many when that is known, else that it is missing.
    /// A forecast is fresh or not, so it is never counted there.
    func missing(_ count: (done: Int, total: Int)?) -> String {
        switch self {
        case .dayMaps: count.map { "Ảnh bản đồ \($0.done)/\($0.total) ngày" } ?? "Ảnh bản đồ chưa tải"
        case .fuji: count.map { "Fuji \($0.done)/\($0.total) ảnh" } ?? "Fuji chưa tải"
        case .forecasts: "Dự báo chưa mới"
        }
    }
}

/// An extra of a job as the app has it when the job ends: what is on disk of it (fresh, for the forecasts) of how
/// many, and whether it was stopped.
public struct ExtraState: Sendable, Equatable {
    public let done: Int
    public let total: Int
    /// stopped by the travellers or by the system
    public let paused: Bool

    public init(done: Int, total: Int, paused: Bool) {
        self.done = done
        self.total = total
        self.paused = paused
    }
}

/// The extras of the downloads (`OfflineExtras` in the app) as they run: one part at a time, in the list's order
/// (`OfflineExtra.allCases`), from the moment each is asked for to its end.
///
/// - Asked for, a part is pending, and busy from then on: a job whose maps and photos are already there does not end
///   before its first picture, nor between two parts.
/// - The one loop takes `next`, `begin`s it (a second start is refused), `counted`s it as it goes and `end`s it with
///   what is on disk, or with nil when it cannot be counted (a page to open first): over, with no state, which the
///   job's end reads as not done.
/// - Asked for again while it runs: `again`, which the app's loop reads at the part's next item, stopping the pass there
///   and starting it again (`end` puts it back to pending), so a change it may have missed is seen.
/// - `pause()` stops what waits and what runs; a picture in flight lands on a part that stays paused. A request after a
///   pause goes on from what is missing.
/// - A stop holds every part the run knows, the ones already over with it (`held`), until each is asked for again; kept
///   across a launch, it comes back by `restore`, so a kill after the stop does not run any of them against it.
/// - A part waiting its turn again (asked for again, or stepping aside) shows the last count it had.
public struct ExtrasRun: Sendable, Equatable {
    public struct Count: Sendable, Equatable {
        public let done: Int
        public let total: Int

        public init(done: Int, total: Int) {
            self.done = done
            self.total = total
        }
    }

    public enum Phase: Sendable, Equatable {
        /// asked for, waiting its turn
        case pending
        /// under way, with what it has counted so far
        case running(Count?)
        /// over: what was on disk at its end; nil, it could not be counted
        case finished(Count?)
        /// stopped where it was
        case paused(Count?)
    }

    public private(set) var phases: [OfflineExtra: Phase] = [:]
    /// asked for while running: the loop stops the pass at its next item and starts it again
    public private(set) var again: Set<OfflineExtra> = []
    /// stopped, and not asked for since: every part the run knew at the stop, the ones over with it; kept across a launch
    public private(set) var held: Set<OfflineExtra> = []
    /// the last count of each part, shown while it waits its turn again
    private var last: [OfflineExtra: Count] = [:]

    public init() {}

    /// Asks for parts: each waits its turn, or runs again once its pass stops if it is under way. What was held by a
    /// stop is let go for these only.
    public mutating func request(_ extras: Set<OfflineExtra>) {
        held.subtract(extras)
        for extra in extras {
            if case .running? = phases[extra] { again.insert(extra) } else { phases[extra] = .pending }
        }
    }

    /// The travellers or the system stopped the job: what waits and what runs stops where it is.
    public mutating func pause() {
        for (extra, phase) in phases {
            switch phase {
            case .pending: phases[extra] = .paused(nil)
            case .running(let count): phases[extra] = .paused(count)
            case .finished, .paused: break
            }
        }
        again = []
        held.formUnion(phases.keys)
    }

    /// The job's parts at launch: those `held` before the app was ended come back paused, not run against the stop, the
    /// ones that were over with them; the others wait their turn. What was kept for a part no longer in the job is let go.
    public mutating func restore(_ members: Set<OfflineExtra>, held kept: Set<OfflineExtra>) {
        let stopped = members.intersection(kept)
        request(members.subtracting(stopped))
        for extra in stopped { phases[extra] = .paused(nil) }
        held = stopped
    }

    /// The part to run next: the first pending one in the list's order.
    public var next: OfflineExtra? {
        OfflineExtra.allCases.first { phases[$0] == .pending }
    }

    /// Starts a pending part; false for any other.
    public mutating func begin(_ extra: OfflineExtra) -> Bool {
        guard phases[extra] == .pending else { return false }
        phases[extra] = .running(nil)
        return true
    }

    /// How far a part under way (or paused while its picture was in flight) is.
    public mutating func counted(_ extra: OfflineExtra, done: Int, total: Int) {
        let count = Count(done: done, total: total)
        switch phases[extra] {
        case .running?: phases[extra] = .running(count)
        case .paused?: phases[extra] = .paused(count)
        case .pending?, .finished?, nil: return
        }
        last[extra] = count
    }

    /// A pass is over, with what is on disk of it (nil: it cannot be counted).
    public mutating func end(_ extra: OfflineExtra, _ count: Count?) {
        switch phases[extra] {
        case .running?:
            phases[extra] = again.remove(extra) == nil ? .finished(count) : .pending
        case .paused?:
            phases[extra] = .paused(count)
        case .pending?, .finished?, nil:
            return
        }
        if let count { last[extra] = count }
    }

    /// Any of `members` waiting its turn or under way.
    public func busy(_ members: Set<OfflineExtra>) -> Bool {
        members.contains { extra in
            switch phases[extra] {
            case .pending?, .running?: true
            case .finished?, .paused?, nil: false
            }
        }
    }

    /// The parts stopped, to keep across a launch.
    public var paused: Set<OfflineExtra> {
        Set(phases.keys.filter { extra in
            if case .paused? = phases[extra] { true } else { false }
        })
    }

    /// What the job's end reads of a part: its count once over, or its pause (0 of 0 when never counted). Nil while it
    /// waits or runs, and for a part over that could not be counted: not done.
    public func state(_ extra: OfflineExtra) -> ExtraState? {
        switch phases[extra] {
        case .finished(let count?)?: ExtraState(done: count.done, total: count.total, paused: false)
        case .paused(let count)?: ExtraState(done: count?.done ?? 0, total: count?.total ?? 0, paused: true)
        case .finished(nil)?, .pending?, .running?, nil: nil
        }
    }

    /// `state` of each of `members` that has one.
    public func states(_ members: Set<OfflineExtra>) -> [OfflineExtra: ExtraState] {
        var out: [OfflineExtra: ExtraState] = [:]
        for extra in members {
            if let state = state(extra) { out[extra] = state }
        }
        return out
    }

    /// What a part has counted, for the page and the progress line: its count, else the last one it had (a part
    /// waiting its turn again, or a new pass not counted yet). Nil for a part not asked for.
    public func progress(_ extra: OfflineExtra) -> Count? {
        switch phases[extra] {
        case .running(let count)?, .finished(let count)?, .paused(let count)?: count ?? last[extra]
        case .pending?: last[extra]
        case nil: nil
        }
    }

    /// A part's share of the job's bar, 0…1: what it has counted (or last counted) while it waits, runs or is paused,
    /// and all of it once over with nothing to count or nothing to draw.
    public func fraction(_ extra: OfflineExtra) -> Double {
        switch phases[extra] {
        case .running(let count)?, .paused(let count)?:
            return (count ?? last[extra]).map(Self.ratio) ?? 0
        case .finished(let count)?:
            guard let count, count.total > 0 else { return 1 }
            return Self.ratio(count)
        case .pending?:
            return last[extra].map(Self.ratio) ?? 0
        case nil:
            return 0
        }
    }

    private static func ratio(_ count: Count) -> Double {
        guard count.total > 0 else { return 0 }
        return min(1, max(0, Double(count.done) / Double(count.total)))
    }
}

/// The Live Activity's bar of a job (`units` of it). The system reads a bar that does not move as a task that is
/// stuck, so it only moves forward; when the job grows (a tap adds to it), its fraction falls, and what is done from
/// then on fills what is left of the bar, from where it stood.
public struct JobBar: Sendable, Equatable {
    public static let units: Int64 = 1000
    /// where the bar stood when the job last grew, and the job's fraction then
    private var from: Int64 = 0
    private var fractionFrom: Double = 0

    public init() {}

    /// The job grew to `fraction` with the bar at `bar`.
    public mutating func grew(fraction: Double, bar: Int64) {
        from = min(Self.units, max(0, bar))
        fractionFrom = Self.clamped(fraction)
    }

    /// The bar for the job at `fraction`, 0…`units`: never below where it stood when the job last grew.
    public func units(for fraction: Double) -> Int64 {
        let f = Self.clamped(fraction)
        let room = 1 - fractionFrom
        let share = room > 0 ? max(0, f - fractionFrom) / room : (f >= 1 ? 1 : 0)
        // the millionth added keeps a share that is whole in decimal whole in binary (0.05 / 0.1 is 0.4999…)
        return min(Self.units, from + Int64((share * Double(Self.units - from) + 1e-6).rounded(.down)))
    }

    /// 0…1; a value out of range or not a number is held to the range
    private static func clamped(_ x: Double) -> Double {
        x.isFinite ? min(1, max(0, x)) : 0
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

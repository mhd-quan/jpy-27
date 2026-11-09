import ImageIO
import MapKit
import SwiftUI
import TripKit
import UniformTypeIdentifiers

// The 3D terrain round Fuji as the pages show it (the Fuji page's hero, a viewpoint's card): a picture drawn
// once by MapKit's snapshotter and kept, then the live map under it once the page has come on screen.

/// The terrain from `camera`, with the viewpoints' pins and lines of sight to the summit, as a page shows it.
///
/// The picture (`FujiTerrainPictures`):
/// - comes from memory in the first frame, from `Caches/Fuji` when read;
/// - is otherwise drawn once the page has come on screen, with a steady network, out of Low Power Mode.
///
/// The live map (`FujiTerrainMap`):
/// - goes under the picture once the page has settled and the network is steady (`NetworkStatus.online`);
/// - the picture stays over it a beat, then fades (`TerrainPicture.beat`);
/// - once up, it stays while the view lives, whatever the network does, so a flaky signal never rebuilds it.
///
/// Without a network and with no picture, the viewpoints are laid out round the summit instead
/// (`FujiCompassPlot`). Another camera (a day chosen) flies the live map there; over the picture it crossfades
/// to the new one's. A picture: the caller turns hit testing off.
struct FujiTerrainSnapshot: View {
    @Environment(\.colorScheme) private var environmentScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.transitionSettled) private var settled
    let camera: FujiCamera.Shot
    /// the viewpoints drawn, and the one chosen (its line in the sun's colour)
    let spots: [FujiGuide.Spot]
    let selection: String?
    /// room the plot leaves round itself
    let plotInset: EdgeInsets
    /// the page's light or dark when it is laid on a colour of its own (`AmbientCanvas.scheme`); nil: the
    /// environment's
    let scheme: ColorScheme?
    /// where on its page the picture sits, for the sizes kept for the offline readiness (`FujiTerrainPictures.lastSizes`)
    let slot: FujiTerrainPictures.Slot?
    /// the scheme the page opened in, held while it comes on screen: a page colour read during the zoom changes the
    /// picture once the zoom is over, never inside it (as `StaticTripMap`)
    @State private var opened: ColorScheme?

    init(camera: FujiCamera.Shot, spots: [FujiGuide.Spot], selection: String?, plotInset: EdgeInsets = EdgeInsets(),
         scheme: ColorScheme? = nil, slot: FujiTerrainPictures.Slot? = nil) {
        self.camera = camera
        self.spots = spots
        self.selection = selection
        self.plotInset = plotInset
        self.scheme = scheme
        self.slot = slot
        _opened = State(initialValue: scheme)
    }

    /// light or dark, for the picture and the live map under it
    private var pictureScheme: ColorScheme {
        let now = scheme ?? environmentScheme
        return settled ? now : (opened ?? now)
    }

    var body: some View {
        let dark = pictureScheme == .dark
        let scale = displayScale
        let settled = self.settled
        GeometryReader { geo in
            // the picture is named by its size: none until it has one
            if geo.size.width >= 1, geo.size.height >= 1 {
                TerrainLayers(camera: camera, spots: spots, selection: selection, plotInset: plotInset,
                              size: geo.size, scale: scale, dark: dark, settled: settled)
                    // the size this slot is drawn at, kept for the offline readiness (written only when it changes)
                    .onChange(of: geo.size, initial: true) { _, size in
                        if let slot { FujiTerrainPictures.keep(size, scale: scale, for: slot) }
                    }
                    .onChange(of: scale) { _, scale in
                        if let slot { FujiTerrainPictures.keep(geo.size, scale: scale, for: slot) }
                    }
            }
        }
    }
}

/// `FujiTerrainSnapshot` at its size: the live map once mounted, and over it what covers it
/// (`TerrainPicture.cover`).
private struct TerrainLayers: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let camera: FujiCamera.Shot
    let spots: [FujiGuide.Spot]
    let selection: String?
    let plotInset: EdgeInsets
    let size: CGSize
    let scale: CGFloat
    let dark: Bool
    let settled: Bool
    /// where the live map's pins and lines go
    private let summit: Coordinate
    /// the live map has been mounted (`TerrainPicture.mounts`): never cleared while the view lives. Seeded as the view
    /// is made, so one made on a page already settled (a card scrolled to) writes nothing as it appears
    @State private var mounted: Bool
    /// a picture was the cover as the live map was mounted (`TerrainPicture.cover`): one finished during the beat is
    /// not laid over it
    @State private var pictureAtMount: Bool
    /// the beat over the live map has passed: the cover is gone for good
    @State private var lifted = false
    @State private var position: MapCameraPosition
    /// the last picture shown, held should memory let it go while it is on screen, and kept on screen while the next
    /// camera's loads; let go when that load comes back empty
    @State private var shown: Shown?

    init(camera: FujiCamera.Shot, spots: [FujiGuide.Spot], selection: String?, plotInset: EdgeInsets,
         size: CGSize, scale: CGFloat, dark: Bool, settled: Bool) {
        self.camera = camera
        self.spots = spots
        self.selection = selection
        self.plotInset = plotInset
        self.size = size
        self.scale = scale
        self.dark = dark
        self.settled = settled
        let model = AppModel.shared
        let summit = model.guide.fuji.summit.coordinate
        self.summit = summit
        _mounted = State(initialValue: !FujiTerrainPictures.pictureOnly
            && TerrainPicture.mounts(mounted: false, settled: settled, online: model.network.online))
        _position = State(initialValue: .camera(camera.mapCamera))
        let request = FujiTerrainPictures.Request(camera: camera, spots: spots, summit: summit, size: size, scale: scale, dark: dark)
        let hit = request.flatMap { FujiTerrainPictures.shared.cached($0) }
        _shown = State(initialValue: request.flatMap { r in hit.map { Shown(stem: r.stem, picture: $0, spots: spots, selection: selection) } })
        _pictureAtMount = State(initialValue: hit != nil)
    }

    private var request: FujiTerrainPictures.Request? {
        FujiTerrainPictures.Request(camera: camera, spots: spots, summit: summit, size: size, scale: scale, dark: dark)
    }

    var body: some View {
        let online = model.network.online
        let pictureOnly = FujiTerrainPictures.pictureOnly
        let live = !pictureOnly && TerrainPicture.mounts(mounted: mounted, settled: settled, online: online)
        let request = self.request
        // this camera's picture from memory in the same frame; else the one held (this camera's, or the last one's
        // while this one loads)
        let displayed = request.flatMap { r in
            FujiTerrainPictures.shared.cached(r).map { Shown(stem: r.stem, picture: $0, spots: spots, selection: selection) }
        } ?? shown
        // the live map goes in under what covers it now (latched below as it is mounted)
        let atMount = mounted ? pictureAtMount : displayed != nil
        let cover = TerrainPicture.cover(picture: displayed != nil, pictureAtMount: atMount, mounted: live, lifted: lifted,
                                         online: online)
        let lowPower = model.lowPower
        let draws = TerrainPicture.draws(settled: settled, online: online, lowPower: lowPower)
        let reduceTransparency = self.reduceTransparency
        ZStack {
            if live {
                FujiTerrainMap(spots: spots, position: $position, selection: .constant(selection))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    // one per live map put on screen (and again when its page is come back to): a flaky network adds none
                    .onAppear { Perf.mark("fuji.live") }
                    // while a cover is up, it alone speaks: both carry the map's label
                    .accessibilityHidden(cover != nil)
            }
            // a cover's change fades, whatever the transaction it comes in (an area chip's own)
            coverLayer(cover, displayed)
                .animation(Motion.reduced(Motion.arrive, reduceMotion),
                           value: CoverKey(cover: cover, stem: cover == .picture ? displayed?.stem : nil))
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onChange(of: settled && online) { _, now in
            if now, !mounted, !pictureOnly {
                pictureAtMount = displayed != nil
                mounted = true
            }
        }
        .onChange(of: camera) { _, next in
            if live {
                withAnimation(Motion.reduced(Motion.travel, reduceMotion)) { position = .camera(next.mapCamera) }
            } else {
                // a live map mounted later starts here
                position = .camera(next.mapCamera)
            }
        }
        .task(id: Beat(live: live, lifted: lifted, online: online)) { await beat(live: live, online: online) }
        .task(id: Load(stem: request?.stem, fingerprint: request?.fingerprint, draws: draws,
                       blurring: !lowPower && !reduceTransparency)) {
            await load(request, draws: draws, lowPower: lowPower, reduceTransparency: reduceTransparency)
        }
    }

    @ViewBuilder
    private func coverLayer(_ cover: TerrainPicture.Cover?, _ displayed: Shown?) -> some View {
        switch cover {
        case .picture?:
            if let displayed {
                TerrainPictureView(shown: displayed, size: size)
                    .id(displayed.stem)
                    .transition(.opacity)
            }
        case .plot?:
            ZStack {
                FujiCompassPlot.backdrop
                FujiCompassPlot(spots: spots, selection: .constant(selection))
                    .padding(plotInset)
            }
            .transition(.opacity)
        case .placeholder?:
            FujiCompassPlot.backdrop
                .transition(.opacity)
        case nil:
            EmptyView()
        }
    }

    /// The cover stays a beat over a live map just mounted, then fades: only while online, so it is never taken off
    /// a live map that may have nothing under it.
    private func beat(live: Bool, online: Bool) async {
        guard TerrainPicture.beats(mounted: live, lifted: lifted, online: online) else { return }
        try? await Task.sleep(for: TerrainPicture.beat)
        guard !Task.isCancelled else { return }
        withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) { lifted = true }
    }

    /// From memory (already drawn); else read from the disk, or drawn when it may be (`TerrainPicture.draws`), and
    /// faded in; then its blurred copy for the hero's name, when it may be made (`FujiTerrainPictures.blur`). Cancelled
    /// with the view, or when the camera, size, scheme or a gate changes; a draw nobody else waits for stops with it.
    private func load(_ request: FujiTerrainPictures.Request?, draws: Bool, lowPower: Bool, reduceTransparency: Bool) async {
        guard let request else { return }
        let pictures = FujiTerrainPictures.shared
        let picture: FujiTerrainPicture
        if let hit = pictures.cached(request) {
            // held, should memory let it go while it is on screen; never faded: it was drawn from memory
            if shown?.picture.image !== hit.image { shown = Shown(stem: request.stem, picture: hit, spots: spots, selection: selection) }
            picture = hit
        } else {
            let found: FujiTerrainPicture?
            if draws {
                found = await pictures.picture(for: request)
            } else {
                found = await pictures.stored(request)
            }
            guard !Task.isCancelled else { return }
            guard let found else {
                if shown != nil, shown?.stem != request.stem {
                    // nothing for this camera now: the last one's picture goes, the plot or the plain ground stands in
                    withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) { shown = nil }
                }
                return
            }
            withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) {
                shown = Shown(stem: request.stem, picture: found, spots: spots, selection: selection)
            }
            picture = found
        }
        await pictures.blur(picture, for: request, lowPower: lowPower, reduceTransparency: reduceTransparency)
    }

    /// what the beat waits on: mounting starts it, going offline stops it (coming back starts it afresh)
    private nonisolated struct Beat: Equatable, Sendable {
        let live: Bool
        let lifted: Bool
        let online: Bool
    }

    /// what the picture's task loads: a new name or fingerprint loads again; leave to draw starts the drawing, and
    /// leave to blur (out of Low Power Mode, without Reduce Transparency) makes the blurred copy then, as 5.2's veil
    private nonisolated struct Load: Equatable, Sendable {
        let stem: String?
        let fingerprint: String?
        let draws: Bool
        let blurring: Bool
    }

    /// what the cover's fade follows
    private nonisolated struct CoverKey: Equatable, Sendable {
        let cover: TerrainPicture.Cover?
        let stem: String?
    }
}

/// A picture on screen, with the viewpoints it was asked for: its pins are its own, even while the next camera's
/// loads.
private struct Shown {
    let stem: String
    let picture: FujiTerrainPicture
    let spots: [FujiGuide.Spot]
    let selection: String?
}

/// The picture, with the summit, the viewpoints and their lines of sight drawn over it where the snapshot projected
/// them, as the live map draws them (`FujiTerrainMap`): the snapshotter draws neither.
private struct TerrainPictureView: View {
    @Environment(AppModel.self) private var model
    let shown: Shown
    let size: CGSize

    var body: some View {
        let picture = shown.picture
        // the picture fills the view as `scaledToFill` lays it: scaled by the larger ratio, centred
        let image = picture.image.size
        let scale = image.width > 0 && image.height > 0 ? max(size.width / image.width, size.height / image.height) : 1
        let dx = (size.width - image.width * scale) / 2
        let dy = (size.height - image.height * scale) / 2
        let at = { (p: CGPoint) in CGPoint(x: p.x * scale + dx, y: p.y * scale + dy) }
        let top = picture.summit.map(at)
        Image(uiImage: picture.image)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipped()
            .overlay {
                ZStack {
                    if let top {
                        ForEach(shown.spots) { s in
                            if let p = picture.points[s.id] {
                                Path { line in
                                    line.move(to: at(p))
                                    line.addLine(to: top)
                                }
                                .stroke(FujiTerrainMap.lineColor(s, selection: shown.selection),
                                        style: FujiTerrainMap.lineStyle(s, selection: shown.selection))
                            }
                        }
                        // standing on the summit, as the live map's annotation (anchored at its bottom)
                        FujiSummitPin(height: Int(model.guide.fuji.summit.h))
                            .fixedSize()
                            .frame(width: 0, height: 0, alignment: .bottom)
                            .position(top)
                    }
                    ForEach(shown.spots) { s in
                        if let p = picture.points[s.id] {
                            FujiSpotPin(visible: s.visible, major: s.role != "popular", selected: s.id == shown.selection)
                                .position(at(p))
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .accessibilityElement()
            .accessibilityLabel(FujiTerrainMap.label)
    }
}

/// A picture of the terrain and where its pins go: points from its top left, in its size.
nonisolated struct FujiTerrainPicture: Sendable {
    let image: UIImage
    /// nil when the snapshot could not place it
    let summit: CGPoint?
    /// by viewpoint id
    let points: [String: CGPoint]
}

/// The terrain's pictures (`FujiTerrainSnapshot`). They are drawn by MapKit's snapshotter
/// (`MKHybridMapConfiguration`, realistic elevation, no points of interest: the live map's style) with the
/// camera's numbers.
///
/// Where they are kept:
/// - in memory, 32 MB;
/// - on disk in `Caches/Fuji`: `<stem>.heic` (JPEG where the encoder has no HEIC), and beside it `<stem>.json`,
///   which holds the projected points and the fingerprint (`TerrainPicture`);
/// - a picture read back with another fingerprint is a miss, drawn again under the same name;
/// - the folder is held to 40 MB at launch (`trim`). They can always be drawn again.
///
/// One drawing per picture (name and fingerprint) at a time, shared by whoever asks. It is cancelled when the last of
/// them stops waiting, or after 15 s. One drawn with no signal is not kept on disk: its tiles may be missing.
/// Reading, encoding, writing and deleting run off the main thread.
@Observable final class FujiTerrainPictures {
    static let shared = FujiTerrainPictures()

    #if DEBUG
    /// Settings › Chẩn đoán › "Fuji: chỉ ảnh địa hình" (Debug, not kept): the picture alone, never the live map, so
    /// what the snapshotter draws can be looked at (the 5.3 spike)
    static var pictureOnly = false
    #else
    static let pictureOnly = false
    #endif

    /// A picture asked for: the camera and the viewpoints, at a size, scale and scheme, with its name and fingerprint
    /// made once.
    nonisolated struct Request: Sendable {
        let camera: FujiCamera.Shot
        let summit: Coordinate
        let spots: [TerrainPicture.Spot]
        /// in whole points, as the name has it
        let size: CGSize
        let scale: CGFloat
        let dark: Bool
        /// `TerrainPicture.stem`
        let stem: String
        /// `TerrainPicture.fingerprint`
        let fingerprint: String

        /// a day's area: the Fuji page's hero, which lays the picture blurred under its name. A viewpoint's card has
        /// no such foot
        var blurs: Bool { camera.kind == .area }

        /// the picture asked for, whole: its name and its fingerprint (a trip data update keeps the name)
        var key: String { "\(stem) \(fingerprint)" }

        /// Nil for a size under a point.
        init?(camera: FujiCamera.Shot, spots: [FujiGuide.Spot], summit: Coordinate, size: CGSize, scale: CGFloat, dark: Bool) {
            guard let stem = TerrainPicture.stem(kind: camera.kind, id: camera.id, width: Double(size.width),
                                                 height: Double(size.height), scale: Double(scale), dark: dark) else { return nil }
            let points = spots.map { TerrainPicture.Spot(id: $0.id, coordinate: Coordinate($0.lat, $0.lng)) }
            self.camera = camera
            self.summit = summit
            self.spots = points
            self.size = CGSize(width: size.width.rounded(), height: size.height.rounded())
            self.scale = scale
            self.dark = dark
            self.stem = stem
            fingerprint = TerrainPicture.fingerprint(camera: camera.camera, summit: summit, spots: points)
        }
    }

    /// the blurred copy under a hero's name, by camera (`FujiCamera.Shot.name`): the last one made (`blur`). Observed,
    /// so a hero redraws its foot when its camera's arrives
    private(set) var backdrops: [String: UIImage] = [:]

    /// A picture held in memory, with the fingerprint it was asked with.
    private final class Entry {
        let fingerprint: String
        let picture: FujiTerrainPicture

        init(fingerprint: String, picture: FujiTerrainPicture) {
            self.fingerprint = fingerprint
            self.picture = picture
        }
    }

    private let memory: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    /// one making of a picture, and how many wait for it
    private nonisolated struct Making: Sendable {
        let id: Int
        let task: Task<FujiTerrainPicture?, Never>
        var waiters: Int
    }

    /// a snapshotter drawing, and its waiter
    private struct Drawing {
        let snapshotter: MKMapSnapshotter
        let done: CheckedContinuation<Drawn?, Never>
    }

    /// what a snapshot gave: the picture and where the pins go
    private nonisolated struct Drawn: Sendable {
        let image: UIImage
        let summit: CGPoint?
        let points: [String: CGPoint]
    }

    /// the pictures being made, by name and fingerprint (`Request.key`): a second ask for the same picture waits for
    /// the first; one with another fingerprint makes its own
    @ObservationIgnored private var makings: [String: Making] = [:]
    /// the picture each blurred copy in `backdrops` was made from (`Request.key`), by camera
    @ObservationIgnored private var blurred: [String: String] = [:]
    /// the snapshotters drawing, by number: whichever of its answer, its stop and its cap comes first resumes it
    @ObservationIgnored private var drawing: [Int: Drawing] = [:]
    /// numbers the makings and the drawings
    @ObservationIgnored private var serial = 0

    /// a drawing that has not come back by then is given up
    private static let cap: Duration = .seconds(15)

    /// The picture, if memory has it (with the same fingerprint): for a view's first frame.
    func cached(_ request: Request) -> FujiTerrainPicture? {
        guard let entry = memory.object(forKey: request.stem as NSString), entry.fingerprint == request.fingerprint else { return nil }
        return entry.picture
    }

    /// The blurred copy for `camera`, the last one made.
    func backdrop(for camera: FujiCamera.Shot) -> UIImage? {
        backdrops[camera.name]
    }

    /// The picture from memory or the disk; never drawn. Cancelled while the disk is read, it keeps nothing.
    func stored(_ request: Request) async -> FujiTerrainPicture? {
        if let hit = cached(request) { return hit }
        guard let saved = await Self.read(request.stem, fingerprint: request.fingerprint, scale: request.scale),
              !Task.isCancelled else { return nil }
        keep(saved, for: request)
        Self.mark(request.stem, "disk")
        return saved
    }

    /// Whether the picture, with this fingerprint, is in memory or on disk, for the offline readiness count: only the
    /// small `.json` is read (its fingerprint compared, as `read` does), the picture's file is only looked for, nothing
    /// is decoded or kept and its last use is left as it is.
    func has(_ request: Request) async -> Bool {
        if cached(request) != nil { return true }
        return await Self.onDisk(request.stem, fingerprint: request.fingerprint)
    }

    // MARK: For no signal (Tải tất cả)

    /// Whether the picture, with this fingerprint, is on disk: what a launch with no signal finds. Memory is not asked.
    func isOnDisk(_ request: Request) async -> Bool {
        await Self.onDisk(request.stem, fingerprint: request.fingerprint)
    }

    /// Draws the picture for use with no signal unless it is on disk, and waits for its files: true once they are
    /// there. A making of the same picture under way (a page's) is waited for, not drawn twice. Nothing is kept in
    /// memory: the seventy or so pictures Tải tất cả draws in turn would push out what the open pages show. Stored only
    /// when `keep()` still holds once it is drawn (the signal held, the app stayed in front: MapKit answers only there,
    /// and a drawing the app left comes back with nothing after the 15 s cap).
    func drawForKeeping(_ request: Request, keep: () -> Bool) async -> Bool {
        let stem = request.stem, fingerprint = request.fingerprint
        if await Self.onDisk(stem, fingerprint: fingerprint) { return true }
        let picture: FujiTerrainPicture?
        if let making = makings[request.key] {
            picture = await making.task.value
        } else {
            picture = await draw(request).map { FujiTerrainPicture(image: $0.image, summit: $0.summit, points: $0.points) }
        }
        guard let picture, keep() else { return false }
        Self.mark(stem, "kept")
        await Self.store(picture, stem: stem, fingerprint: fingerprint)
        return await Self.onDisk(stem, fingerprint: fingerprint)
    }

    /// The pictures Tải tất cả drew for no signal, by stem: the launch trim spares them (a card's other scheme is never
    /// read, so it would be the first to go). Each pass's set replaces the last.
    static var offlineKeep: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: offlineKeepKey) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: offlineKeepKey) }
    }

    private static let offlineKeepKey = "offline.keep.fuji"

    // MARK: What the offline readiness counts

    /// Where a picture sits, each drawn at its own size: the Fuji page's hero (an area), a viewpoint's card whose hero
    /// it is (a viewpoint with no photographs), and the 220 pt map under a card's photographs ("Tia ngắm").
    nonisolated enum Slot: String, Codable, CaseIterable, Sendable {
        case area, spot, sight

        /// what to open so this slot's size is measured
        var setup: String {
            switch self {
            case .area: "Mở trang Fuji một lần"
            case .spot: "Mở một chỗ ngắm chưa có ảnh chụp"
            case .sight: "Mở một chỗ ngắm có ảnh chụp"
            }
        }
    }

    /// The sizes kept, `"fuji.sizes"`: each slot's in points, and the screen's scale.
    private nonisolated struct Sizes: Codable, Equatable {
        var area: [Double]?
        var spot: [Double]?
        var sight: [Double]?
        var scale: Double?

        subscript(slot: Slot) -> [Double]? {
            get {
                switch slot {
                case .area: area
                case .spot: spot
                case .sight: sight
                }
            }
            set {
                switch slot {
                case .area: area = newValue
                case .spot: spot = newValue
                case .sight: sight = newValue
                }
            }
        }
    }

    private static let sizesKey = "fuji.sizes"

    private static var savedSizes: Sizes {
        guard let data = UserDefaults.standard.data(forKey: sizesKey),
              let sizes = try? JSONDecoder().decode(Sizes.self, from: data) else { return Sizes() }
        return sizes
    }

    /// A size read back: two finite numbers, at least a point each. Anything else is no size.
    private static func size(_ xy: [Double]?) -> CGSize? {
        guard let xy, xy.count == 2, xy[0].isFinite, xy[1].isFinite, xy[0] >= 1, xy[1] >= 1 else { return nil }
        return CGSize(width: xy[0], height: xy[1])
    }

    /// The sizes each slot was drawn at last, and the screen's scale: nil until a page with that slot was opened, or
    /// when what is kept cannot be read back.
    static var lastSizes: (area: CGSize?, spot: CGSize?, sight: CGSize?, scale: CGFloat?) {
        let s = savedSizes
        let scale = s.scale.flatMap { $0.isFinite && $0 >= 1 && $0 <= 4 ? CGFloat($0) : nil }
        return (size(s.area), size(s.spot), size(s.sight), scale)
    }

    /// Keeps the size `slot` is drawn at (`FujiTerrainSnapshot`), written only when it changed.
    static func keep(_ size: CGSize, scale: CGFloat, for slot: Slot) {
        guard size.width >= 1, size.height >= 1, size.width.isFinite, size.height.isFinite, scale.isFinite, scale >= 1 else { return }
        var s = savedSizes
        let old = s
        s[slot] = [Double(size.width), Double(size.height)]
        s.scale = Double(scale)
        guard s != old, let data = try? JSONEncoder().encode(s) else { return }
        UserDefaults.standard.set(data, forKey: sizesKey)
    }

    /// Where a viewpoint's card draws its terrain: as the card's hero when it has no photographs, else under them.
    /// `FujiSpotPage.photos`' rule: none of its own, and none of its place's.
    static func slot(of spot: FujiGuide.Spot, store: TripStore) -> Slot {
        spot.images.isEmpty && (store.place(spot.id)?.images ?? []).isEmpty ? .spot : .sight
    }

    /// The pictures the pages draw, for use without signal: every area's hero (`FujiHero`) and every viewpoint's card
    /// (`FujiSightMap`), light and dark (R-600: a card's scheme follows its photograph's colour, not the Appearance
    /// setting), except a card with no photograph, which is always on Fuji's dusk (`schemes(of:)`), at the sizes kept. The cameras, viewpoints and summits are the views' own:
    /// - a hero: `Shot.area(area, spots: the area's, summit: guide's summit)`, drawn with the area's viewpoints;
    /// - a card: `.spot(spot, summit: FujiSight.summit)`, drawn with that viewpoint alone;
    /// - both named with the guide's summit (`TerrainLayers`).
    /// Or the first slot a page uses whose size is not known yet (area, spot, sight), to be opened once first.
    static func wanted(guide: FujiGuide, store: TripStore) -> Wanted {
        let sizes = lastSizes
        let summit = guide.summit.coordinate
        let used = Set([Slot.area] + guide.spots.map { slot(of: $0, store: store) })
        let kept: [Slot: CGSize?] = [.area: sizes.area, .spot: sizes.spot, .sight: sizes.sight]
        let measured = kept.compactMapValues { $0 }
        if let first = Slot.allCases.first(where: { used.contains($0) && measured[$0] == nil }) { return .needs(first) }
        guard let scale = sizes.scale else { return .needs(.area) }
        var out: [Request] = []
        for area in FujiArea.allCases {
            let shown = guide.spots.filter { area.contains($0) }
            let shot = FujiCamera.Shot.area(area, spots: shown, summit: summit)
            for dark in [false, true] {
                if let size = measured[.area],
                   let r = Request(camera: shot, spots: shown, summit: summit, size: size, scale: scale, dark: dark) { out.append(r) }
            }
        }
        for spot in guide.spots {
            let shot = FujiCamera.Shot.spot(spot, summit: FujiSight.summit)
            let card = slot(of: spot, store: store)
            for dark in schemes(of: card) {
                if let size = measured[card],
                   let r = Request(camera: shot, spots: [spot], summit: summit, size: size, scale: scale, dark: dark) { out.append(r) }
            }
        }
        return .pictures(out)
    }

    /// The schemes a slot is ever shown in, as dark or not. An area's hero follows the Appearance; a card with photographs
    /// follows its first photograph's colour: both. A card with none is laid on Fuji's dusk (`FujiSpotAlbum.canvas`), so
    /// only that one.
    private static func schemes(of slot: Slot) -> [Bool] {
        switch slot {
        case .area, .sight: [false, true]
        case .spot: [AmbientCanvas.dusk.scheme == .dark]
        }
    }

    /// `wanted`'s answer.
    enum Wanted {
        /// a page to open first, for this slot's size
        case needs(Slot)
        case pictures([Request])
    }

    /// The blurred copy under the Fuji page hero's name (`DetailHero(backdrop:)`), made from `picture` when there is
    /// none of it yet: `PhotoCache.derive`'s 160 px veil, off the main thread (the tone it also samples is not used).
    /// It is made by the rule of 5.2's photograph veil, `HeroFoot.derivesVeil`, whose inputs this fits. The terrain's
    /// picture plays the photograph's part (`hasVeil`: an area's, the one with a foot), and no picture of the page's
    /// own is laid under the name instead of it (`hasBackdrop`). So it is not made in Low Power Mode, nor with
    /// Reduce Transparency, where none is shown; the load's task id holds both, so it is made once they end.
    /// Cancelled, it writes nothing.
    func blur(_ picture: FujiTerrainPicture, for request: Request, lowPower: Bool, reduceTransparency: Bool) async {
        let name = request.camera.name, key = request.key
        guard HeroFoot.derivesVeil(lowPower: lowPower, reduceTransparency: reduceTransparency, hasVeil: request.blurs,
                                   hasBackdrop: false, cached: blurred[name] == key),
              let full = picture.image.cgImage else { return }
        let veil = await PhotoCache.derive(full).veil
        guard !Task.isCancelled, let veil else { return }
        blurred[name] = key
        backdrops[name] = veil
    }

    /// The picture from memory, the disk, or drawn now. Background work (contract § 4.2): it stops when the last of
    /// those asking stops waiting, keeping and writing nothing, and whoever asks next starts again.
    func picture(for request: Request) async -> FujiTerrainPicture? {
        if let hit = cached(request) { return hit }
        guard !Task.isCancelled else { return nil }
        let key = request.key
        let making: Making
        if var running = makings[key] {
            running.waiters += 1
            makings[key] = running
            making = running
        } else {
            serial += 1
            making = Making(id: serial, task: Task { await self.make(request) }, waiters: 1)
            makings[key] = making
        }
        let id = making.id
        let picture = await withTaskCancellationHandler {
            await making.task.value
        } onCancel: {
            // called off the main actor, at once: the count is kept on it
            Task { @MainActor [weak self] in self?.leave(key, making: id) }
        }
        if makings[key]?.id == id { makings[key] = nil }
        return picture
    }

    /// A waiter stopped waiting: the making goes on for the others; with none left it is cancelled.
    private func leave(_ key: String, making id: Int) {
        guard var making = makings[key], making.id == id else { return }
        making.waiters -= 1
        if making.waiters > 0 {
            makings[key] = making
        } else {
            making.task.cancel()
            makings[key] = nil
        }
    }

    /// From the disk, else drawn; kept in memory, and on disk when the signal was there as it finished. Cancelled
    /// (`leave`) at any point, it keeps and writes nothing: `stored` checks after its read, this after its draw.
    private func make(_ request: Request) async -> FujiTerrainPicture? {
        if let saved = await stored(request) { return saved }
        guard !Task.isCancelled, let drawn = await draw(request), !Task.isCancelled else { return nil }
        let picture = FujiTerrainPicture(image: drawn.image, summit: drawn.summit, points: drawn.points)
        keep(picture, for: request)
        Self.mark(request.stem, "made")
        if AppModel.shared.network.raw {
            let stem = request.stem, fingerprint = request.fingerprint
            // nobody waits for the files: the next ask finds them, or draws again
            Task(priority: .utility) { await Self.store(picture, stem: stem, fingerprint: fingerprint) }
        }
        return picture
    }

    private func keep(_ picture: FujiTerrainPicture, for request: Request) {
        let image = picture.image
        memory.setObject(Entry(fingerprint: request.fingerprint, picture: picture), forKey: request.stem as NSString,
                         cost: Int(image.size.width * image.scale * image.size.height * image.scale * 4))
    }

    /// MapKit's snapshotter, started on the main thread and answering there (`start(completionHandler:)`). Whichever
    /// comes first resumes the waiter once: its answer, the task's stop, or the 15 s cap. A stop or the cap also stops
    /// the snapshotter, and an answer coming later finds nothing to resume.
    private func draw(_ request: Request) async -> Drawn? {
        Perf.mark("fuji.snapshot")
        let options = MKMapSnapshotter.Options()
        options.camera = request.camera.mkCamera
        options.size = request.size
        let dark = request.dark, scale = request.scale
        // the scale and the scheme as traits (`Options.scale` is deprecated from iOS 27.3)
        options.traitCollection = UITraitCollection(mutations: { traits in
            traits.userInterfaceStyle = dark ? .dark : .light
            traits.displayScale = scale
        })
        let configuration = MKHybridMapConfiguration(elevationStyle: .realistic)
        configuration.pointOfInterestFilter = .excludingAll
        options.preferredConfiguration = configuration
        let snapshotter = MKMapSnapshotter(options: options)
        serial += 1
        let id = serial
        let summit = request.summit, spots = request.spots
        let cap = Task { [weak self] in
            try? await Task.sleep(for: Self.cap)
            guard !Task.isCancelled else { return }
            self?.finish(id, nil)
        }
        defer { cap.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (done: CheckedContinuation<Drawn?, Never>) in
                guard !Task.isCancelled else {
                    done.resume(returning: nil)
                    return
                }
                drawing[id] = Drawing(snapshotter: snapshotter, done: done)
                snapshotter.start { [weak self] snapshot, _ in
                    self?.finish(id, snapshot.map { Self.project($0, summit: summit, spots: spots) })
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, nil) }
        }
    }

    /// Drawing `id` answered (`drawn`), or was given up (nil): its waiter resumes, once; given up, the snapshotter
    /// stops ("If the snapshotter isn't in the process of generating the snapshot, calling this method does nothing").
    private func finish(_ id: Int, _ drawn: Drawn?) {
        guard let d = drawing.removeValue(forKey: id) else { return }
        if drawn == nil { d.snapshotter.cancel() }
        d.done.resume(returning: drawn)
    }

    /// Where the summit and each viewpoint landed in the snapshot: what is drawn over the picture.
    private static func project(_ snapshot: MKMapSnapshotter.Snapshot, summit: Coordinate, spots: [TerrainPicture.Spot]) -> Drawn {
        func point(_ c: Coordinate) -> CGPoint? {
            let p = snapshot.point(for: FujiCamera.cl(c))
            return p.x.isFinite && p.y.isFinite ? p : nil
        }
        var points: [String: CGPoint] = [:]
        for s in spots {
            if let p = point(s.coordinate) { points[s.id] = p }
        }
        return Drawn(image: snapshot.image, summit: point(summit), points: points)
    }

    /// One `fuji.picture` event per picture drawn or read from the disk, for Instruments: "<stem> made|disk".
    private static func mark(_ stem: String, _ how: String) {
        Perf.signposter.emitEvent("fuji.picture", "\(stem, privacy: .public) \(how, privacy: .public)")
    }

    // MARK: On disk, off the main thread

    /// `Caches/Fuji`: this cache's own folder, the only place it writes or deletes.
    private nonisolated static let folder: URL = {
        let url = URL.cachesDirectory.appending(path: "Fuji", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// HEIC where the encoder lists it (every iPhone that runs iOS 26), else JPEG (a simulator host without it):
    /// decided once, written and read the same way.
    private nonisolated static let format: (ext: String, type: String) = {
        let types = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        return types.contains(UTType.heic.identifier) ? ("heic", UTType.heic.identifier) : ("jpg", UTType.jpeg.identifier)
    }()

    /// The `.json` beside a picture: `{"fingerprint", "summit": [x, y], "spots": {"<id>": [x, y]}}`.
    private nonisolated struct StoredPoints: Codable {
        var fingerprint: String
        var summit: [Double]?
        var spots: [String: [Double]]
    }

    /// The picture and its points, read and decoded off the main thread, only with the fingerprint asked for (else a
    /// miss). The read is the picture's last use, for `trim`.
    @concurrent private nonisolated static func read(_ stem: String, fingerprint: String, scale: CGFloat) async -> FujiTerrainPicture? {
        let file = folder.appendingPathComponent("\(stem).\(format.ext)")
        guard let json = try? Data(contentsOf: folder.appendingPathComponent("\(stem).json")),
              let stored = try? JSONDecoder().decode(StoredPoints.self, from: json), stored.fingerprint == fingerprint,
              let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: scale) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path(percentEncoded: false))
        let shown = image.preparingForDisplay() ?? image
        return FujiTerrainPicture(image: shown, summit: point(stored.summit), points: stored.spots.compactMapValues { Self.point($0) })
    }

    /// `has`: the `.json` beside the picture with the fingerprint asked for, and the picture's file.
    @concurrent private nonisolated static func onDisk(_ stem: String, fingerprint: String) async -> Bool {
        guard let json = try? Data(contentsOf: folder.appendingPathComponent("\(stem).json")),
              let stored = try? JSONDecoder().decode(StoredPoints.self, from: json), stored.fingerprint == fingerprint else { return false }
        return FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(stem).\(format.ext)").path(percentEncoded: false))
    }

    private nonisolated static func point(_ xy: [Double]?) -> CGPoint? {
        guard let xy, xy.count == 2, xy[0].isFinite, xy[1].isFinite else { return nil }
        return CGPoint(x: xy[0], y: xy[1])
    }

    /// Encoded and written off the main thread: the picture first, then its `.json`, each whole or not at all. A
    /// picture written over an old one with the old `.json` still beside it reads as a miss (another fingerprint), and
    /// no `.json` is written for a picture that failed.
    @concurrent private nonisolated static func store(_ picture: FujiTerrainPicture, stem: String, fingerprint: String) async {
        let points = StoredPoints(fingerprint: fingerprint, summit: picture.summit.map { [Double($0.x), Double($0.y)] },
                                  spots: picture.points.mapValues { [Double($0.x), Double($0.y)] })
        guard let full = picture.image.cgImage, let encoded = encode(full), let json = try? JSONEncoder().encode(points) else { return }
        do {
            try encoded.write(to: folder.appendingPathComponent("\(stem).\(format.ext)"), options: .atomic)
            try json.write(to: folder.appendingPathComponent("\(stem).json"), options: .atomic)
        } catch {
            // a cache: the picture is drawn again next time
            return
        }
    }

    private nonisolated static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, format.type as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// At launch: the least recently used pictures, each with its `.json`, until the folder's fit in `budget` bytes
    /// (`TerrainPicture.evicted`). Only names from this folder's own listing that the cache made; the folder stays.
    /// Never one of `keeping` (`offlineKeep`).
    @concurrent nonisolated static func trim(toBytes budget: Int, keeping: Set<String> = []) async {
        let files = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let listed = urls.compactMap { url -> TerrainPicture.StoredFile? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return TerrainPicture.StoredFile(name: url.lastPathComponent, bytes: values.fileSize ?? 0,
                                             used: values.contentModificationDate ?? .distantPast)
        }
        for name in TerrainPicture.evicted(listed, toBytes: budget, keeping: keeping) {
            try? files.removeItem(at: folder.appendingPathComponent(name, isDirectory: false))
        }
    }

    #if DEBUG
    /// Settings › Chẩn đoán (Debug): the pictures on disk and what the folder's own files hold, "6 ảnh HEIC · 2,1 MB".
    @concurrent nonisolated static func usage() async -> String {
        let keys: [URLResourceKey] = [.fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let own = urls.compactMap { url in TerrainPicture.parse(url.lastPathComponent).map { (url, $0) } }
        let bytes = own.reduce(0) { $0 + ((try? $1.0.resourceValues(forKeys: Set(keys)))?.fileSize ?? 0) }
        let pictures = own.filter { $0.1.ext != "json" }.count
        return "\(pictures) ảnh \(format.ext.uppercased()) · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Settings › Chẩn đoán › Xoá (Debug): every picture, in memory and in `Caches/Fuji` (the cache's own files only),
    /// so the next page draws its picture afresh.
    func clear() async {
        memory.removeAllObjects()
        backdrops = [:]
        blurred = [:]
        await Self.removeOwnFiles()
    }

    @concurrent private nonisolated static func removeOwnFiles() async {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
        for name in names where TerrainPicture.parse(name) != nil {
            try? files.removeItem(at: folder.appendingPathComponent(name, isDirectory: false))
        }
    }
    #endif
}

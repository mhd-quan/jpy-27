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
    /// the scheme the page opened in, held while it comes on screen: a page colour read during the zoom changes the
    /// picture once the zoom is over, never inside it (as `StaticTripMap`)
    @State private var opened: ColorScheme?

    init(camera: FujiCamera.Shot, spots: [FujiGuide.Spot], selection: String?, plotInset: EdgeInsets = EdgeInsets(),
         scheme: ColorScheme? = nil) {
        self.camera = camera
        self.spots = spots
        self.selection = selection
        self.plotInset = plotInset
        self.scheme = scheme
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
            }
        }
    }
}

/// `FujiTerrainSnapshot` at its size: the live map once mounted, and over it what covers it
/// (`TerrainPicture.cover`).
private struct TerrainLayers: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        let cover = TerrainPicture.cover(picture: displayed != nil, mounted: live, lifted: lifted, online: online)
        let draws = TerrainPicture.draws(settled: settled, online: online, lowPower: model.lowPower)
        ZStack {
            if live {
                FujiTerrainMap(spots: spots, position: $position, selection: .constant(selection))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    // one per live map put on screen (and again when its page is come back to): a flaky network adds none
                    .onAppear { Perf.mark("fuji.live") }
            }
            // a cover's change fades, whatever the transaction it comes in (an area chip's own)
            coverLayer(cover, displayed)
                .animation(Motion.reduced(Motion.arrive, reduceMotion), value: CoverKey(cover: cover, stem: displayed?.stem))
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .onChange(of: settled && online) { _, now in
            if now, !mounted, !pictureOnly { mounted = true }
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
        .task(id: Load(stem: request?.stem, fingerprint: request?.fingerprint, draws: draws)) { await load(request, draws: draws) }
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
    /// faded in. Cancelled with the view, or when the camera, size or scheme changes; a draw nobody else waits for
    /// stops with it.
    private func load(_ request: FujiTerrainPictures.Request?, draws: Bool) async {
        guard let request else { return }
        let pictures = FujiTerrainPictures.shared
        if let hit = pictures.cached(request) {
            // held, should memory let it go while it is on screen; never faded: it was drawn from memory
            if shown?.picture.image !== hit.image { shown = Shown(stem: request.stem, picture: hit, spots: spots, selection: selection) }
            return
        }
        let found: FujiTerrainPicture?
        if draws {
            found = await pictures.picture(for: request)
        } else {
            found = await pictures.stored(request)
        }
        guard !Task.isCancelled else { return }
        if let found {
            withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) {
                shown = Shown(stem: request.stem, picture: found, spots: spots, selection: selection)
            }
        } else if shown != nil, shown?.stem != request.stem {
            // nothing for this camera now: the last one's picture goes, the plot or the plain ground stands in
            withAnimation(Motion.reduced(Motion.arrive, reduceMotion)) { shown = nil }
        }
    }

    /// what the beat waits on: mounting starts it, going offline stops it (coming back starts it afresh)
    private nonisolated struct Beat: Equatable, Sendable {
        let live: Bool
        let lifted: Bool
        let online: Bool
    }

    /// what the picture's task loads: a new name or fingerprint loads again; leave to draw starts the drawing
    private nonisolated struct Load: Equatable, Sendable {
        let stem: String?
        let fingerprint: String?
        let draws: Bool
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
    /// the picture as a 160 px blurred copy, for the name over the Fuji page's hero (`DetailHero(backdrop:)`):
    /// `PhotoCache.derive`'s veil, the one the photographs' heroes have. Nil for a viewpoint's, or when the blur failed
    let backdrop: UIImage?
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
/// One drawing per name at a time, shared by whoever asks. It is cancelled when the last of them stops waiting,
/// or after 15 s. One drawn with no signal is not kept on disk: its tiles may be missing.
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

    /// the blurred copy under a hero's name, by camera (`FujiCamera.Shot.name`): the last one read or drawn. Observed,
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

    /// the pictures being made, by name: a second ask waits for the first
    @ObservationIgnored private var makings: [String: Making] = [:]
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

    /// The blurred copy for `camera`, the last one read or drawn.
    func backdrop(for camera: FujiCamera.Shot) -> UIImage? {
        backdrops[camera.name]
    }

    /// The picture from memory or the disk; never drawn.
    func stored(_ request: Request) async -> FujiTerrainPicture? {
        if let hit = cached(request) { return hit }
        guard let saved = await Self.read(request.stem, fingerprint: request.fingerprint, scale: request.scale,
                                          blurs: request.blurs) else { return nil }
        keep(saved, for: request)
        Self.mark(request.stem, "disk")
        return saved
    }

    /// The picture from memory, the disk, or drawn now. Background work (contract § 4.2): it stops when the last of
    /// those asking stops waiting, keeping and writing nothing, and whoever asks next starts again.
    func picture(for request: Request) async -> FujiTerrainPicture? {
        if let hit = cached(request) { return hit }
        guard !Task.isCancelled else { return nil }
        let stem = request.stem
        let making: Making
        if var running = makings[stem] {
            running.waiters += 1
            makings[stem] = running
            making = running
        } else {
            serial += 1
            making = Making(id: serial, task: Task { await self.make(request) }, waiters: 1)
            makings[stem] = making
        }
        let id = making.id
        let picture = await withTaskCancellationHandler {
            await making.task.value
        } onCancel: {
            // called off the main actor, at once: the count is kept on it
            Task { @MainActor [weak self] in self?.leave(stem, making: id) }
        }
        if makings[stem]?.id == id { makings[stem] = nil }
        return picture
    }

    /// A waiter stopped waiting: the making goes on for the others; with none left it is cancelled.
    private func leave(_ stem: String, making id: Int) {
        guard var making = makings[stem], making.id == id else { return }
        making.waiters -= 1
        if making.waiters > 0 {
            makings[stem] = making
        } else {
            making.task.cancel()
            makings[stem] = nil
        }
    }

    /// From the disk, else drawn; kept in memory, and on disk when the signal was there as it finished. Cancelled, it
    /// keeps and writes nothing.
    private func make(_ request: Request) async -> FujiTerrainPicture? {
        if let saved = await stored(request) { return saved }
        guard !Task.isCancelled, let drawn = await draw(request), !Task.isCancelled else { return nil }
        // the photographs' heroes' 160 px veil, from the picture (the tone `derive` also samples is not used)
        var backdrop: UIImage?
        if request.blurs, let full = drawn.image.cgImage { backdrop = await PhotoCache.derive(full).veil }
        guard !Task.isCancelled else { return nil }
        let picture = FujiTerrainPicture(image: drawn.image, summit: drawn.summit, points: drawn.points, backdrop: backdrop)
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
        let name = request.camera.name
        if let backdrop = picture.backdrop, backdrops[name] !== backdrop { backdrops[name] = backdrop }
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
    /// miss); its blurred copy made from it when it `blurs`. The read is the picture's last use, for `trim`.
    @concurrent private nonisolated static func read(_ stem: String, fingerprint: String, scale: CGFloat,
                                                     blurs: Bool) async -> FujiTerrainPicture? {
        let file = folder.appendingPathComponent("\(stem).\(format.ext)")
        guard let json = try? Data(contentsOf: folder.appendingPathComponent("\(stem).json")),
              let stored = try? JSONDecoder().decode(StoredPoints.self, from: json), stored.fingerprint == fingerprint,
              let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: scale) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path(percentEncoded: false))
        let shown = image.preparingForDisplay() ?? image
        var backdrop: UIImage?
        if blurs, let full = shown.cgImage { backdrop = await PhotoCache.derive(full).veil }
        return FujiTerrainPicture(image: shown, summit: point(stored.summit), points: stored.spots.compactMapValues { Self.point($0) },
                                  backdrop: backdrop)
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
    @concurrent nonisolated static func trim(toBytes budget: Int) async {
        let files = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let listed = urls.compactMap { url -> TerrainPicture.StoredFile? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return TerrainPicture.StoredFile(name: url.lastPathComponent, bytes: values.fileSize ?? 0,
                                             used: values.contentModificationDate ?? .distantPast)
        }
        for name in TerrainPicture.evicted(listed, toBytes: budget) {
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

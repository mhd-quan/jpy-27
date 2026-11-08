import MapLibre
import SwiftUI
import TripKit

// Maps only looked at: a picture of the trip's map in a page that scrolls, drawn by MapLibre's snapshotter
// with the layers the live map (`TripMap.swift`) puts in, and the live map put under it on a tap.

/// A map that is only looked at, in a page that scrolls (a day, a hotel's neighbourhood, a shopping
/// slot): MapLibre draws it once into a picture (`MapSnapshots`), kept on disk, instead of a live
/// map held open in the page, each of which is a Metal surface with its own tiles in memory and its
/// own display link. The picture is there from the first frame when memory has it, read from the disk
/// off the main thread otherwise, and drawn only once the page has come on screen. With
/// `tapToInteract` a tap puts the live map under the picture, which lifts once the map has drawn itself.
struct StaticTripMap: View {
    let content: MapContent
    let insets: UIEdgeInsets
    let frameID: String
    let tapToInteract: Bool
    /// the page's light or dark when the page is laid on a colour of its own (`AmbientCanvas.scheme`, read
    /// from `PhotoCache.knownTone` before it opens); nil: the environment's
    let scheme: ColorScheme?
    /// `content.fingerprint`, once per value of this view: it reads every point
    private let fingerprint: UInt64

    @Environment(\.colorScheme) private var environmentScheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.transitionSettled) private var settled
    /// the last picture shown, kept on screen while another one is made (another size, the other scheme)
    @State private var image: MapSnapshot?
    @State private var live = false
    /// the live map under the picture has drawn itself (or the cap passed): the picture goes
    @State private var liveReady = false
    /// the scheme the page opened in, held while the page comes on screen: a page colour read during the
    /// zoom changes the picture once the zoom is over, never inside it
    @State private var opened: ColorScheme?

    init(content: MapContent, insets: UIEdgeInsets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30), frameID: String = "",
         tapToInteract: Bool = true, scheme: ColorScheme? = nil) {
        self.content = content
        self.insets = insets
        self.frameID = frameID
        self.tapToInteract = tapToInteract
        self.scheme = scheme
        fingerprint = content.fingerprint
        _opened = State(initialValue: scheme)
    }

    /// light or dark, for the picture and the live map under it
    private var pictureScheme: ColorScheme {
        let now = scheme ?? environmentScheme
        return settled ? now : (opened ?? now)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if live {
                    TripMap(content: content, showsUser: false, insets: insets, frameID: frameID, onReady: { lift() })
                        .environment(\.colorScheme, pictureScheme)
                }
                if !liveReady {
                    picture(size: geo.size)
                        .transition(.opacity)
                }
            }
        }
        // offline the map may never draw itself whole: the picture lifts all the same
        .task(id: live) {
            guard live else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            lift()
        }
    }

    private func lift() {
        guard live, !liveReady else { return }
        withAnimation(.easeOut(duration: 0.2)) { liveReady = true }
    }

    private func picture(size: CGSize) -> some View {
        let request = MapSnapshots.Request(content: content, fingerprint: fingerprint, frameID: frameID, insets: insets,
                                           size: size, scale: displayScale, dark: pictureScheme == .dark)
        let wanted = Wanted(key: request.key, settled: settled)
        // the right picture from the first frame when memory has it, else the last one shown
        let shown = MapSnapshots.shared.cached(request.key) ?? image
        return Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                if let shown {
                    Image(uiImage: shown.image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .overlay {
                if let shown {
                    SnapshotPins(snapshot: shown, pins: content.pins.filter { $0.kind == .done }, size: size)
                }
            }
            .overlay(alignment: .topTrailing) {
                if tapToInteract && !live {
                    Image(systemName: "hand.draw")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(7)
                        .background(Palette.card.opacity(0.92), in: .capsule)
                        .padding(8)
                        .accessibilityHidden(true)
                }
            }
            .clipped()
            .contentShape(.rect)
            .onTapGesture {
                guard tapToInteract, !live else { return }
                live = true
            }
            // the live map under it takes the pan at once
            .allowsHitTesting(!live)
            .accessibilityElement()
            .accessibilityLabel(Text("Bản đồ"))
            .accessibilityAddTraits(tapToInteract ? AccessibilityTraits.isButton : AccessibilityTraits())
            .accessibilityHint(Text(verbatim: tapToInteract ? "Mở bản đồ để kéo và phóng to" : ""))
            .accessibilityHidden(live)
            .task(id: wanted) { await load(request, settled: wanted.settled) }
    }

    /// From memory, else from the disk (read off the main thread, shown when it lands); drawn only once the
    /// page has come on screen, or 400 ms after it was asked for at the latest, so the snapshotter's style
    /// work on the main thread (`SnapshotStyler`) stays out of the zoom. Not drawn once the live map is up.
    private func load(_ request: MapSnapshots.Request, settled: Bool) async {
        guard request.size.width >= 1, request.size.height >= 1 else { return }
        let snapshots = MapSnapshots.shared
        if let hit = snapshots.cached(request.key) {
            // held, should memory let it go while it is on screen
            if image?.image !== hit.image { image = hit }
            return
        }
        if let saved = await snapshots.stored(request) {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { image = saved }
            return
        }
        if !settled {
            // the settle starts this again at once: it is part of the task's id
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
        }
        guard !live, let made = await snapshots.snapshot(for: request), !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { image = made }
    }

    /// what the picture's task waits on: a new key loads again, the settle ends the wait
    private nonisolated struct Wanted: Equatable, Sendable {
        let key: SnapshotKey
        let settled: Bool
    }
}

/// The visited stops over a map's picture, where the snapshot put their pins: the picture shows them as
/// stops (`MapContent.unvisited`), so marking one never draws a new picture.
private struct SnapshotPins: View {
    let snapshot: MapSnapshot
    let pins: [MapPin]
    let size: CGSize

    var body: some View {
        // the picture fills the view as `scaledToFill` lays it: scaled by the larger ratio, centred
        let picture = snapshot.image.size
        let scale = picture.width > 0 && picture.height > 0 ? max(size.width / picture.width, size.height / picture.height) : 1
        let dx = (size.width - picture.width * scale) / 2
        let dy = (size.height - picture.height * scale) / 2
        ZStack {
            ForEach(pins, id: \.id) { pin in
                if let p = snapshot.points[pin.id] {
                    SnapshotPin(number: pin.number, dark: snapshot.dark)
                        .position(x: p.x * scale + dx, y: p.y * scale + dy)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One visited stop as the live map draws it (`TripMap.Coordinator.look(.done)`): gray, 8 pt from the
/// middle, a 2 pt edge in the picture's light or dark, its number in white.
private struct SnapshotPin: View {
    let number: Int?
    let dark: Bool

    var body: some View {
        Circle()
            .fill(Color(.systemGray))
            .padding(2)
            .background(dark ? Color.black : Color.white, in: .circle)
            .frame(width: 20, height: 20)
            .overlay {
                if let number {
                    Text(verbatim: "\(number)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
    }
}

/// A picture of a map, and where its pins landed in it (points from its top left, in its size).
nonisolated struct MapSnapshot: Sendable {
    let image: UIImage
    let points: [String: CGPoint]
    /// drawn dark: the pins over it are edged in black
    let dark: Bool
}

/// Pictures of maps (`StaticTripMap`), drawn by MapLibre's snapshotter with the trip's layers put in
/// as `TripMap` puts them, kept in memory a while and on disk in `Caches/MapSnapshots` (they can always be
/// drawn again): `<frameID>-<hash>.jpg` with its pins' points beside it (`.json`), one picture per frame
/// (`prune`), the folder held to 40 MB at launch (`trim`). One drawn with no signal is not kept on disk:
/// its tiles may be missing. All but the style (`SnapshotStyler`) runs off the main thread: reading,
/// decoding, encoding, writing, deleting.
final class MapSnapshots {
    static let shared = MapSnapshots()

    /// A picture asked for: a page's map (Task 5.7's prefetch asks for the same). The key is made once;
    /// pass the content's fingerprint when it is known already.
    struct Request {
        let content: MapContent
        let frameID: String
        let insets: UIEdgeInsets
        let size: CGSize
        let scale: CGFloat
        let dark: Bool
        /// names the picture: the content, the frame, the size, scale, scheme and insets, the tile build,
        /// and the app's build, whose style draws it
        let key: SnapshotKey

        init(content: MapContent, fingerprint: UInt64? = nil, frameID: String, insets: UIEdgeInsets, size: CGSize, scale: CGFloat, dark: Bool) {
            self.content = content
            self.frameID = frameID
            self.insets = insets
            self.size = size
            self.scale = scale
            self.dark = dark
            key = SnapshotKey.make(frameID: frameID, content: fingerprint ?? content.fingerprint,
                                   size: SnapshotKey.Size(width: Double(size.width), height: Double(size.height)),
                                   scale: Double(scale), dark: dark,
                                   insets: [insets.top, insets.left, insets.bottom, insets.right].map { Double($0) },
                                   tiles: OfflineMaps.mapBuild.template, build: MapSnapshots.build)
        }
    }

    /// the app's build: a new one may draw the same content differently
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    /// A picture held in memory.
    private final class Entry {
        let snapshot: MapSnapshot

        init(_ snapshot: MapSnapshot) {
            self.snapshot = snapshot
        }
    }

    private let memory: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    /// the pictures being made, by file name: a second ask waits for the first
    private var running: [String: Task<MapSnapshot?, Never>] = [:]
    /// the snapshotters' delegates, held while they draw (a snapshotter holds its delegate weakly)
    private var stylers: [ObjectIdentifier: SnapshotStyler] = [:]

    private nonisolated static let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MapSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// The picture, if memory has it: for a view's first frame.
    func cached(_ key: SnapshotKey) -> MapSnapshot? {
        memory.object(forKey: key.fileName as NSString)?.snapshot
    }

    /// The picture from memory or the disk; never drawn.
    func stored(_ request: Request) async -> MapSnapshot? {
        if let hit = cached(request.key) { return hit }
        guard let saved = await Self.read(request.key, scale: request.scale, dark: request.dark) else { return nil }
        keep(saved, as: request.key)
        return saved
    }

    /// The picture from memory, the disk, or drawn now: one drawing per picture at a time.
    func snapshot(for request: Request) async -> MapSnapshot? {
        let name = request.key.fileName
        if let hit = cached(request.key) { return hit }
        if let task = running[name] { return await task.value }
        let task = Task { await self.load(request) }
        running[name] = task
        let made = await task.value
        running[name] = nil
        if let made { keep(made, as: request.key) }
        return made
    }

    private func keep(_ snapshot: MapSnapshot, as key: SnapshotKey) {
        let image = snapshot.image
        memory.setObject(Entry(snapshot), forKey: key.fileName as NSString,
                         cost: Int(image.size.width * image.scale * image.size.height * image.scale * 4))
    }

    private func load(_ request: Request) async -> MapSnapshot? {
        if let saved = await Self.read(request.key, scale: request.scale, dark: request.dark) { return saved }
        guard let made = await render(request) else { return nil }
        if AppModel.shared.network.online {
            let key = request.key
            // nobody waits for the files: the next ask finds them, or draws again
            Task(priority: .utility) { await MapSnapshots.store(made, as: key) }
        }
        return made
    }

    /// On the main thread: MapLibre starts a snapshotter there, and the style work (`SnapshotStyler`)
    /// stays there. The picture shows every stop as not visited (`MapContent.unvisited`); where each pin
    /// landed is read from the snapshot as it comes back, on the main queue.
    private func render(_ request: Request) async -> MapSnapshot? {
        Perf.mark("map.snapshot")
        let drawn = request.content.unvisited
        let options = MLNMapSnapshotOptions(styleURL: OfflineMaps.style(dark: request.dark), camera: MLNMapCamera(), size: request.size)
        options.scale = request.scale
        options.showsLogo = false
        Self.frame(drawn.outline, insets: request.insets, size: request.size, in: options)
        let snapshotter = MLNMapSnapshotter(options: options)
        let styler = SnapshotStyler(content: drawn, dark: request.dark)
        snapshotter.delegate = styler
        let id = ObjectIdentifier(styler)
        stylers[id] = styler
        defer { stylers[id] = nil }
        let pins = drawn.pins
        let dark = request.dark
        return await withCheckedContinuation { (done: CheckedContinuation<MapSnapshot?, Never>) in
            // started on the main thread, as MapLibre insists; the snapshotter keeps itself alive
            // until it calls back
            snapshotter.start { snapshot, _ in
                guard let snapshot else {
                    done.resume(returning: nil)
                    return
                }
                var points: [String: CGPoint] = [:]
                for pin in pins where points[pin.id] == nil {
                    points[pin.id] = snapshot.point(for: CLLocationCoordinate2D(latitude: pin.coordinate.lat, longitude: pin.coordinate.lng))
                }
                done.resume(returning: MapSnapshot(image: snapshot.image, points: points, dark: dark))
            }
        }
    }

    /// `MapFraming` (TripKit), as `TripMap.Coordinator.fit` frames the live map: a lone place centred at street
    /// level; else the area grown by the share of the picture the insets take, so the content fills what
    /// is left, as the live map's edge padding leaves it.
    private static func frame(_ pts: [Coordinate], insets i: UIEdgeInsets, size: CGSize, in options: MLNMapSnapshotOptions) {
        switch MapFraming.of(pts) {
        case nil:
            return
        case .point(let c):
            options.camera = MLNMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng), altitude: 1000, pitch: 0, heading: 0)
            options.zoomLevel = MapFraming.pointZoom
        case .area(let sw, let ne):
            let mid = (lat: (sw.lat + ne.lat) / 2, lng: (sw.lng + ne.lng) / 2)
            let half = (lat: (ne.lat - sw.lat) / 2, lng: (ne.lng - sw.lng) / 2)
            let w = Double(size.width), h = Double(size.height)
            let sx = w / max(1, w - Double(i.left + i.right))
            let sy = h / max(1, h - Double(i.top + i.bottom))
            options.coordinateBounds = MLNCoordinateBounds(
                sw: CLLocationCoordinate2D(latitude: mid.lat - half.lat * sy, longitude: mid.lng - half.lng * sx),
                ne: CLLocationCoordinate2D(latitude: mid.lat + half.lat * sy, longitude: mid.lng + half.lng * sx))
        }
    }

    // MARK: On disk, off the main thread

    /// The pins' points beside a picture: `{"pins": {"<id>": [x, y]}}`.
    private nonisolated struct StoredPoints: Codable {
        var pins: [String: [Double]]
    }

    /// Read and decoded off the main thread, the picture and its pins together: a picture without them is
    /// no picture (its visited stops could not be drawn over it). The read is its last use, for `trim`.
    @concurrent private nonisolated static func read(_ key: SnapshotKey, scale: CGFloat, dark: Bool) async -> MapSnapshot? {
        let file = folder.appendingPathComponent(key.fileName)
        guard let json = try? Data(contentsOf: folder.appendingPathComponent(key.pointsFileName)),
              let stored = try? JSONDecoder().decode(StoredPoints.self, from: json),
              let data = try? Data(contentsOf: file), let image = UIImage(data: data, scale: scale) else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path(percentEncoded: false))
        var points: [String: CGPoint] = [:]
        for (id, xy) in stored.pins where xy.count == 2 {
            points[id] = CGPoint(x: xy[0], y: xy[1])
        }
        return MapSnapshot(image: image.preparingForDisplay() ?? image, points: points, dark: dark)
    }

    /// Encoded and written off the main thread, the pins first and then the picture, each whole or not at
    /// all, so a picture on disk always has its pins; then the frame's other pictures go (`prune`).
    @concurrent private nonisolated static func store(_ snapshot: MapSnapshot, as key: SnapshotKey) async {
        let pins = StoredPoints(pins: snapshot.points.mapValues { [Double($0.x), Double($0.y)] })
        guard let json = try? JSONEncoder().encode(pins), let jpeg = snapshot.image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try json.write(to: folder.appendingPathComponent(key.pointsFileName), options: .atomic)
            try jpeg.write(to: folder.appendingPathComponent(key.fileName), options: .atomic)
        } catch {
            // a cache: the picture is drawn again next time
            return
        }
        await prune(keeping: key)
    }

    /// Deletes the frame's other pictures and their pins (`SnapshotKey.stale`: the same frame, compared
    /// whole; nothing for a picture without a frame), in this folder only.
    @concurrent nonisolated static func prune(keeping key: SnapshotKey) async {
        let files = FileManager.default
        guard let names = try? files.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) else { return }
        for name in SnapshotKey.stale(names, keeping: key) {
            try? files.removeItem(at: folder.appendingPathComponent(name, isDirectory: false))
        }
    }

    /// At launch: the old format's pictures (`<key>.png`), then the least recently used ones until the
    /// folder's pictures fit in `budget` bytes (`SnapshotKey.evicted`), in this folder only.
    @concurrent nonisolated static func trim(toBytes budget: Int) async {
        let files = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let listed = urls.compactMap { url -> SnapshotKey.StoredFile? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return SnapshotKey.StoredFile(name: url.lastPathComponent, bytes: values.fileSize ?? 0, used: values.contentModificationDate ?? .distantPast)
        }
        for name in SnapshotKey.evicted(listed, toBytes: budget) {
            try? files.removeItem(at: folder.appendingPathComponent(name, isDirectory: false))
        }
    }

    #if DEBUG
    /// Settings › Chẩn đoán (Debug): the pictures on disk and what the folder holds, "12 ảnh · 3,1 MB".
    @concurrent nonisolated static func usage() async -> String {
        let keys: [URLResourceKey] = [.fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let bytes = urls.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: Set(keys)))?.fileSize ?? 0) }
        let pictures = urls.filter { $0.pathExtension == "jpg" }.count
        let old = urls.filter { $0.pathExtension == "png" }.count
        var line = "\(pictures) ảnh · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        if old > 0 { line += " · \(old) ảnh kiểu cũ" }
        return line
    }
    #endif
}

#if DEBUG
/// Settings › Chẩn đoán › So khung bản đồ (Debug): a day's picture and the live map of the same content, at
/// the size and insets of the day's page, one above the other or the live map at half strength over the
/// picture: both should frame the same view (`MapFraming`), as the live map replaces a picture on a tap.
struct MapFrameCheck: View {
    @Environment(AppModel.self) private var model
    @State private var dayKey: String?
    @State private var overlaid = false

    private let insets = UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)

    var body: some View {
        let days = model.store.trip.days + model.store.trip.altDays
        let day = days.first { $0.key == (dayKey ?? model.focusDay.key) } ?? model.focusDay
        let content = MapContent.day(day, model: model)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Ngày", selection: Binding(get: { day.key }, set: { dayKey = $0 })) {
                    ForEach(days, id: \.key) { d in
                        Text(d.isAlternative ? d.title : "Ngày \(d.n)").tag(d.key)
                    }
                }
                Toggle("Bản đồ thật chồng lên ảnh", isOn: $overlaid)
                Text(overlaid ? "Ảnh, bản đồ thật mờ một nửa ở trên" : "Ảnh")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ZStack {
                    StaticTripMap(content: content, insets: insets, frameID: "debug-frame", tapToInteract: false)
                    if overlaid {
                        TripMap(content: content, showsUser: false, interactive: false, insets: insets, frameID: day.key)
                            .opacity(0.5)
                    }
                }
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                if !overlaid {
                    Text("Bản đồ thật")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TripMap(content: content, showsUser: false, interactive: false, insets: insets, frameID: day.key)
                        .frame(height: 240)
                        .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                }
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .navigationTitle("So khung bản đồ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

/// Puts the trip's layers into a snapshot's style with the code that puts them into a map's.
final class SnapshotStyler: NSObject, MLNMapSnapshotterDelegate {
    private let content: MapContent
    private let painter: TripMap.Coordinator

    init(content: MapContent, dark: Bool) {
        self.content = content
        painter = TripMap.Coordinator(parent: TripMap(content: content, showsUser: false, interactive: false), dark: dark)
    }

    /// On the main thread: MapLibre starts a snapshotter only there (it raises otherwise) and calls
    /// back on that thread's run loop, which `assumeIsolated` checks. The style is not Sendable (a
    /// plain NSObject, where the map view's delegate hands over a main-actor UIView), so it crosses
    /// into the main actor in a box; it never leaves the main thread.
    nonisolated func mapSnapshotter(_ snapshotter: MLNMapSnapshotter, didFinishLoading style: MLNStyle) {
        let handed = Handed(style: style)
        MainActor.assumeIsolated { painter.apply(content, in: handed.style) }
    }

    private nonisolated struct Handed: @unchecked Sendable { let style: MLNStyle }
}

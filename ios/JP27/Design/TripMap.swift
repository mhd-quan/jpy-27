import MapLibre
import Metal
import SwiftUI
import TripKit

// The trip's map on MapLibre Native, with the site's own basemap. MapLibre over MapKit because the
// plan's real rail geometry, our own quiet style, offline packs and a heatmap layer are all first
// class here; Apple Maps is used only for walking turn-by-turn, which it does better.

nonisolated struct MapRoute: Hashable, Sendable {
    let id: String
    let points: [Coordinate]
    /// "#RRGGBB"
    let color: String
    var width: Double = 4.5
    var dashed = false
    var opacity: Double = 1
}

nonisolated struct MapPin: Hashable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        /// halo: a soft disc under the place being looked at; never tappable
        case stop, done, stay, station, along, snack, fuji, highlight, halo
    }

    let id: String
    let coordinate: Coordinate
    let kind: Kind
    var label: String?
    var number: Int?
    /// draw the label beside the pin (side trips one can tap)
    var titled = false
}

/// A camera move asked of the map; a new id moves it again even to the same place.
nonisolated struct TripMapCamera: Equatable, Sendable {
    enum Move: Equatable, Sendable {
        /// fit these points in the clear part of the map
        case fit([Coordinate])
        /// centre on a point at this zoom (or the current one, if closer)
        case center(Coordinate, zoom: Double)
    }

    let id: Int
    let move: Move
}

nonisolated struct MapContent: Equatable, Sendable {
    var routes: [MapRoute] = []
    var pins: [MapPin] = []
    var heat: [Coordinate] = []

    /// Everything drawn, to fit the camera to.
    var outline: [Coordinate] { routes.flatMap(\.points) + pins.map(\.coordinate) }
}

struct TripMap: UIViewRepresentable {
    var content: MapContent
    var showsUser = true
    var interactive = true
    var insets = UIEdgeInsets(top: 80, left: 40, bottom: 80, right: 40)
    /// change it to frame the content again
    var frameID = ""
    /// centre on this when it changes, or when focusID changes (to recentre on the same point)
    var focus: Coordinate?
    var focusID = 0
    /// the parts of the map covered by the app's own chrome (a panel, a strip of days); the map
    /// centres and fits within what is left. nil leaves the map's inset alone.
    var chrome: UIEdgeInsets?
    var camera: TripMapCamera?
    var onSelect: ((String) -> Void)?
    /// the person panned or zoomed the map themselves
    var onUserMove: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    /// Settings › Đo khung hình bản đồ: the map's own frame readings, over the map
    @AppStorage(MapPacer.readingsKey) private var readings = false

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self, dark: scheme == .dark)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero, styleURL: OfflineMaps.style(dark: scheme == .dark))
        map.delegate = context.coordinator
        map.showsUserLocation = showsUser
        map.isPitchEnabled = false
        map.isRotateEnabled = interactive
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.compassViewPosition = .topRight
        // the MapLibre mark, small and tucked into the bottom-right corner; the attribution the
        // licences ask for stays at the bottom left
        map.logoViewPosition = .bottomRight
        map.logoViewMargins = CGPoint(x: 4, y: 4)
        if let size = map.logoView.image?.size {
            let scale = 0.62
            map.logoView.transform = CGAffineTransform(translationX: size.width * (1 - scale) / 2, y: size.height * (1 - scale) / 2)
                .scaledBy(x: scale, y: scale)
        }
        map.logoView.alpha = 0.7
        map.attributionButtonPosition = .bottomLeft
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.tilesChanged(_:)), name: OfflineMaps.tilesChanged, object: nil)
        context.coordinator.map = map
        let top = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.maximumFramesPerSecond ?? 60
        map.preferredFramesPerSecond = MLNMapViewPreferredFramesPerSecond(rawValue: context.coordinator.pacer.start(top: top))
        map.maximumZoomLevel = 18
        // the map's clear area is set from `chrome`, not guessed from the safe area
        map.automaticallyAdjustsContentInset = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.showsReadings(readings, on: map)
        map.showsUserLocation = showsUser
        let inset = chrome ?? .zero
        if map.contentInset != inset {
            map.setContentInset(inset, animated: c.loaded, completionHandler: nil)
        }
        let dark = scheme == .dark
        if c.dark != dark {
            c.dark = dark
            c.loaded = false
            map.styleURL = OfflineMaps.style(dark: dark)
            return
        }
        guard c.loaded else { return }
        c.apply(content, to: map)
        if c.frameID != frameID {
            c.frameID = frameID
            c.frame(map, animated: true)
        }
        if let focus, focus != c.focus || focusID != c.focusID {
            c.focus = focus
            c.focusID = focusID
            map.setCenter(CLLocationCoordinate2D(latitude: focus.lat, longitude: focus.lng), zoomLevel: max(map.zoomLevel, 15), animated: true)
        }
        if let camera, camera.id != c.cameraID {
            c.cameraID = camera.id
            c.move(map, camera.move)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TripMap
        var dark: Bool
        var loaded = false
        weak var map: MLNMapView?
        var frameID: String
        var focus: Coordinate?
        var focusID = 0
        var cameraID: Int?
        private var applied: MapContent?
        /// the style holds the trip's sources and layers (made once per style load)
        private var built = false
        let pacer = MapPacer()
        private var hud: UILabel?
        private let pinLayers = MapPin.Kind.allCases.filter { $0 != .halo }.map { "pins-\($0.rawValue)" } + ["pins-titles"]

        init(parent: TripMap, dark: Bool) {
            self.parent = parent
            self.dark = dark
            frameID = parent.frameID
            focus = parent.focus
            focusID = parent.focusID
            cameraID = parent.camera?.id
        }

        /// The pinned tile build went away (or came back): reload the style; the trip's layers are
        /// rebuilt when it finishes loading.
        @objc func tilesChanged(_ note: Notification) {
            guard let map else { return }
            loaded = false
            map.styleURL = OfflineMaps.style(dark: dark)
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                loaded = true
                applied = nil
                built = false
                apply(parent.content, to: mapView)
                if let camera = parent.camera {
                    cameraID = camera.id
                    move(mapView, camera.move, animated: false)
                } else {
                    frame(mapView, animated: false)
                }
            }
        }

        nonisolated func mapView(_ mapView: MLNMapView, regionWillChangeWith reason: MLNCameraChangeReason, animated: Bool) {
            let touched = !reason.intersection([.gesturePan, .gesturePinch, .gestureRotate, .gestureZoomIn, .gestureZoomOut, .gestureOneFingerZoom, .gestureTilt]).isEmpty
            guard touched else { return }
            MainActor.assumeIsolated { parent.onUserMove?() }
        }

        // Each frame, on the main thread: timed, so the map asks only for a rate it keeps.
        nonisolated func mapViewWillStartRenderingFrame(_ mapView: MLNMapView) {
            let now = CACurrentMediaTime()
            MainActor.assumeIsolated { pacer.willRender(at: now, measuring: hud != nil) }
        }

        nonisolated func mapViewDidFinishRenderingFrame(_ mapView: MLNMapView, fullyRendered: Bool) {
            let now = CACurrentMediaTime()
            MainActor.assumeIsolated {
                if let rate = pacer.didRender(at: now, measuring: hud != nil) {
                    mapView.preferredFramesPerSecond = MLNMapViewPreferredFramesPerSecond(rawValue: rate)
                }
                if let hud, let reading = pacer.takeReading() { hud.text = reading }
            }
        }

        /// The readings over the map's top corner (a plain label: measuring adds no SwiftUI work).
        func showsReadings(_ on: Bool, on map: MLNMapView) {
            if on, hud == nil {
                let label = UILabel()
                label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
                label.textColor = .white
                label.backgroundColor = UIColor.black.withAlphaComponent(0.62)
                label.numberOfLines = 0
                label.layer.cornerRadius = 8
                label.layer.masksToBounds = true
                label.text = " đang chờ bản đồ chuyển động… "
                label.translatesAutoresizingMaskIntoConstraints = false
                map.addSubview(label)
                NSLayoutConstraint.activate([
                    label.leadingAnchor.constraint(equalTo: map.leadingAnchor, constant: 12),
                    label.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: 58),
                ])
                hud = label
            } else if !on, let hud {
                hud.removeFromSuperview()
                self.hud = nil
            }
        }

        nonisolated func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MLNMapView, let onSelect = parent.onSelect else { return }
            let point = g.location(in: map)
            let rect = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let hit = map.visibleFeatures(in: rect, styleLayerIdentifiers: Set(pinLayers))
            if let id = hit.first?.attribute(forKey: "id") as? String { onSelect(id) }
        }

        func move(_ map: MLNMapView, _ move: TripMapCamera.Move, animated: Bool = true) {
            switch move {
            case .fit(let pts):
                fit(map, pts, animated: animated)
            case .center(let c, let zoom):
                map.setCenter(CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng), zoomLevel: zoom, direction: map.direction, animated: animated, completionHandler: nil)
            }
        }

        func frame(_ map: MLNMapView, animated: Bool) {
            fit(map, parent.content.outline, animated: animated)
        }

        private func fit(_ map: MLNMapView, _ pts: [Coordinate], animated: Bool) {
            guard let b = Geo.bounds(pts) else { return }
            if pts.count == 1 || (b.ne.lat - b.sw.lat < 0.002 && b.ne.lng - b.sw.lng < 0.002) {
                map.setCenter(CLLocationCoordinate2D(latitude: (b.sw.lat + b.ne.lat) / 2, longitude: (b.sw.lng + b.ne.lng) / 2), zoomLevel: 15.5, animated: animated)
                return
            }
            // a short walk is not blown up to street level: at least ~600 m across
            let mid = (lat: (b.sw.lat + b.ne.lat) / 2, lng: (b.sw.lng + b.ne.lng) / 2)
            let half = (lat: max((b.ne.lat - b.sw.lat) / 2, 0.0028), lng: max((b.ne.lng - b.sw.lng) / 2, 0.0034))
            let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: mid.lat - half.lat, longitude: mid.lng - half.lng),
                                             ne: CLLocationCoordinate2D(latitude: mid.lat + half.lat, longitude: mid.lng + half.lng))
            map.setVisibleCoordinateBounds(bounds, edgePadding: parent.insets, animated: animated, completionHandler: nil)
        }

        /// Draws the content. The sources and layers are made once per style load; after that a
        /// change only hands the sources new shapes, which MapLibre re-tiles off the main thread,
        /// instead of tearing the style down and rebuilding it (that stalled the map, and the
        /// panel over it, every time the timeline moved on).
        func apply(_ content: MapContent, to map: MLNMapView) {
            guard let style = map.style, content != applied else { return }
            if !built { build(style) }
            let old = applied
            applied = content

            if old?.heat != content.heat, let heat = heatSource(in: style, needed: !content.heat.isEmpty) {
                heat.shape = MLNShapeCollectionFeature(shapes: content.heat.map { c -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
                    return f
                })
            }

            if old?.routes != content.routes, let routes = style.source(withIdentifier: "routes") as? MLNShapeSource {
                routes.shape = MLNShapeCollectionFeature(shapes: content.routes.compactMap { r -> MLNPolylineFeature? in
                    var coords = r.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                    guard coords.count > 1 else { return nil }
                    let f = MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                    f.attributes = ["id": r.id, "color": r.color, "width": r.width, "opacity": r.opacity, "dashed": r.dashed ? 1 : 0]
                    return f
                })
            }

            if old?.pins != content.pins, let pins = style.source(withIdentifier: "pins") as? MLNShapeSource {
                pins.shape = MLNShapeCollectionFeature(shapes: content.pins.map { p -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: p.coordinate.lat, longitude: p.coordinate.lng)
                    var attrs: [String: Any] = ["id": p.id, "kind": p.kind.rawValue]
                    if let n = p.number { attrs["n"] = "\(n)" }
                    if let l = p.label { attrs["label"] = l }
                    if p.titled { attrs["titled"] = 1 }
                    f.attributes = attrs
                    return f
                })
            }
        }

        /// The heat of the walked trail (the journal's map), made the first time a map has some: a
        /// heatmap draws into a texture of its own on every frame, so the maps without heat, the
        /// Map tab's among them, carry no heatmap layer at all. Nil while none is needed.
        private func heatSource(in style: MLNStyle, needed: Bool) -> MLNShapeSource? {
            if let made = style.source(withIdentifier: "heat") as? MLNShapeSource { return made }
            guard needed else { return nil }
            let heat = MLNShapeSource(identifier: "heat", shape: MLNShapeCollectionFeature(shapes: []), options: nil)
            style.addSource(heat)
            let layer = MLNHeatmapStyleLayer(identifier: "heat", source: heat)
            layer.heatmapRadius = NSExpression(forConstantValue: 22)
            layer.heatmapOpacity = NSExpression(forConstantValue: 0.75)
            layer.heatmapIntensity = NSExpression(forConstantValue: 0.8)
            // under the routes, as the trail is under the plan
            if let routes = style.layer(withIdentifier: "routes-case") {
                style.insertLayer(layer, below: routes)
            } else {
                style.addLayer(layer)
            }
            return heat
        }

        /// The style's own layers for the trip: routes (a light casing under solid lines, colour,
        /// width and opacity read from each line), then pins by kind, numbers and side-trip names.
        private func build(_ style: MLNStyle) {
            let empty = MLNShapeCollectionFeature(shapes: [])
            let routes = MLNShapeSource(identifier: "routes", shape: empty, options: nil)
            let pins = MLNShapeSource(identifier: "pins", shape: empty, options: nil)
            for source in [routes, pins] { style.addSource(source) }
            built = true

            let width = NSExpression(forKeyPath: "width")
            let opacity = NSExpression(forKeyPath: "opacity")
            let casing = MLNLineStyleLayer(identifier: "routes-case", source: routes)
            casing.predicate = NSPredicate(format: "dashed == 0")
            casing.lineColor = NSExpression(forConstantValue: dark ? UIColor.black.withAlphaComponent(0.6) : UIColor.white)
            casing.lineWidth = NSExpression(format: "width + 3")
            casing.lineOpacity = opacity
            let solid = MLNLineStyleLayer(identifier: "routes-solid", source: routes)
            solid.predicate = NSPredicate(format: "dashed == 0")
            let dashed = MLNLineStyleLayer(identifier: "routes-dashed", source: routes)
            dashed.predicate = NSPredicate(format: "dashed == 1")
            dashed.lineDashPattern = NSExpression(forConstantValue: [0.1, 2])
            for line in [solid, dashed] {
                // "#RRGGBB" in the feature, made a colour by the style engine (to-color)
                line.lineColor = NSExpression(format: "CAST(color, 'UIColor')")
                line.lineWidth = width
                line.lineOpacity = opacity
            }
            for line in [casing, solid, dashed] {
                line.lineCap = NSExpression(forConstantValue: "round")
                line.lineJoin = NSExpression(forConstantValue: "round")
                style.addLayer(line)
            }

            for kind in [MapPin.Kind.halo, .station, .along, .highlight, .snack, .fuji, .stay, .done, .stop] {
                let layer = MLNCircleStyleLayer(identifier: "pins-\(kind.rawValue)", source: pins)
                layer.predicate = NSPredicate(format: "kind == %@", kind.rawValue)
                let look = Self.look(kind, dark: dark)
                layer.circleColor = NSExpression(forConstantValue: look.fill)
                layer.circleRadius = NSExpression(forConstantValue: look.radius)
                layer.circleStrokeColor = NSExpression(forConstantValue: look.stroke)
                layer.circleStrokeWidth = NSExpression(forConstantValue: look.strokeWidth)
                style.addLayer(layer)
            }
            let numbers = MLNSymbolStyleLayer(identifier: "pins-numbers", source: pins)
            numbers.predicate = NSPredicate(format: "n != nil")
            numbers.text = NSExpression(forKeyPath: "n")
            numbers.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            numbers.textFontSize = NSExpression(forConstantValue: 11)
            numbers.textColor = NSExpression(forConstantValue: UIColor.white)
            numbers.textAllowsOverlap = NSExpression(forConstantValue: true)
            numbers.textIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(numbers)

            // names beside the side trips, so the map says what can be tapped
            let titles = MLNSymbolStyleLayer(identifier: "pins-titles", source: pins)
            titles.predicate = NSPredicate(format: "titled == 1")
            titles.text = NSExpression(forKeyPath: "label")
            titles.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            titles.textFontSize = NSExpression(forConstantValue: 11.5)
            titles.textColor = NSExpression(forConstantValue: dark ? UIColor.white : UIColor(white: 0.12, alpha: 1))
            titles.textHaloColor = NSExpression(forConstantValue: dark ? UIColor.black.withAlphaComponent(0.85) : UIColor.white)
            titles.textHaloWidth = NSExpression(forConstantValue: 1.6)
            titles.textAnchor = NSExpression(forConstantValue: "left")
            titles.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0.9, dy: 0)))
            titles.maximumTextWidth = NSExpression(forConstantValue: 9)
            style.addLayer(titles)
        }

        private static func look(_ kind: MapPin.Kind, dark: Bool) -> (fill: UIColor, stroke: UIColor, radius: Double, strokeWidth: Double) {
            let edge: UIColor = dark ? .black : .white
            switch kind {
            case .stop: return (UIColor(named: "AccentColor") ?? .systemRed, edge, 9, 2)
            case .done: return (.systemGray, edge, 8, 2)
            // the palette's colours (Theme.swift): wisteria stays, persimmon food, Fuji violet, indigo
            case .stay: return (UIColor(Color(hex: "#7A5BB5")), edge, 8, 2)
            case .station: return (edge, .systemGray, 4.5, 2)
            case .along: return (edge, UIColor(Color(hex: "#E07A2F")), 5, 2.5)
            case .snack: return (UIColor(Color(hex: "#E07A2F")), edge, 5.5, 1.5)
            case .fuji: return (UIColor(Color(hex: "#6B4FD8")), edge, 6, 2)
            case .highlight: return (UIColor(named: "Ai") ?? .systemBlue, edge, 5.5, 1.5)
            case .halo: return ((UIColor(named: "AccentColor") ?? .systemRed).withAlphaComponent(0.22), .clear, 18, 0)
            }
        }
    }
}

// MARK: - Frame pacing

/// Holds the map to a frame rate it keeps. MapLibre prepares each frame on the main thread, from a
/// display link that asks for the screen's top rate (120 Hz on ProMotion). When a frame needs more
/// than the 8 ms that leaves (street level, tiles arriving, the glass over the map sampling it
/// again), frames land unevenly, 8, 17, 25, 33 ms apart, and an uneven 120 judders worse than an
/// even 60. So frames are timed while the map moves: while 120 holds, the map keeps it; when it does
/// not, the map asks for an even 60 and tries 120 again at the start of a later move, waiting
/// longer after each miss (15 s, 30 s, … 4 min). Low Power Mode or a hot phone keep it at 60.
final class MapPacer {
    static let readingsKey = "debug.mapFrames"
    /// Settings › Chẩn đoán, while the readings are on: the panel, the day strip and the buttons over
    /// the map drawn without glass, to see what the glass costs the map's frames
    static let glassKey = "debug.mapGlass"

    /// what the map asks for now
    private(set) var target = 60
    private var top = 60
    private var began: CFTimeInterval = 0
    /// the main thread's own CPU time when the frame began, in ns; 0 when not measured
    private var cpuBegan: UInt64 = 0
    private var last: CFTimeInterval = 0
    /// frame-to-frame times of the move under way
    private var gaps: [Double] = []
    private var retry: CFTimeInterval = 0
    private var wait: CFTimeInterval = 15
    /// half a second of frames, for the readings
    private var tally = Tally()
    private var probe: GPUProbe?
    private var reading: String?

    private struct Tally {
        var from = 0.0
        var frames = 0
        var moving = 0
        var movingTime = 0.0
        var late = 0
        /// main-thread time inside the frames, and the worst of them
        var wall = 0.0
        var worst = 0.0
        /// of the frames whose CPU time was read: that CPU time, and their main-thread time
        var timed = 0
        var cpu = 0.0
        var timedWall = 0.0
    }

    /// The rate for a map just made.
    func start(top: Int) -> Int {
        self.top = max(60, top)
        target = allowed ? self.top : 60
        return target
    }

    private var allowed: Bool {
        top > 60 && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && ProcessInfo.processInfo.thermalState != .serious && ProcessInfo.processInfo.thermalState != .critical
    }

    /// The frame's main-thread time runs from here to `didRender`. With the readings on, the
    /// thread's CPU clock is read too: the difference between the two is time the main thread
    /// spent waiting (for a drawable, so for the GPU) rather than working.
    func willRender(at now: CFTimeInterval, measuring: Bool) {
        began = now
        cpuBegan = measuring ? clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) : 0
    }

    /// After each frame. Returns a rate to ask for when it should change.
    func didRender(at now: CFTimeInterval, measuring: Bool) -> Int? {
        let spent = began > 0 ? now - began : 0
        let gap = last > 0 ? now - last : .infinity
        last = now
        if measuring {
            var cpu: Double?
            if cpuBegan > 0 {
                let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                if end >= cpuBegan { cpu = min(Double(end - cpuBegan) / 1e9, spent) }
            }
            if probe == nil { probe = GPUProbe() }
            probe?.ping()
            measure(now: now, spent: spent, cpu: cpu, gap: gap)
        } else if probe != nil {
            probe = nil
            tally = Tally()
        }
        cpuBegan = 0
        // the first frame of a move (or a lone frame for a tile that arrived)
        guard gap < 0.1 else {
            gaps.removeAll(keepingCapacity: true)
            if target < top, now >= retry, allowed { target = top; return top }
            if target > 60, !allowed { target = 60; return 60 }
            return nil
        }
        gaps.append(gap)
        guard gaps.count >= 24 else { return nil }
        gaps.sort()
        let median = gaps[gaps.count / 2]
        gaps.removeAll(keepingCapacity: true)
        guard target > 60 else { return nil }
        // most frames should be one refresh apart (8.3 ms); past 11 ms they are not
        if median > 1.0 / 90 || !allowed {
            target = 60
            retry = now + wait
            wait = min(wait * 2, 240)
            return 60
        }
        wait = 15
        return nil
    }

    /// The latest readings, once each, about twice a second.
    func takeReading() -> String? {
        defer { reading = nil }
        return reading
    }

    private func measure(now: CFTimeInterval, spent: Double, cpu: Double?, gap: Double) {
        if tally.from == 0 { tally.from = now - spent }
        tally.frames += 1
        tally.wall += spent
        tally.worst = max(tally.worst, spent)
        if let cpu {
            tally.timed += 1
            tally.cpu += cpu
            tally.timedWall += spent
        }
        if gap < 0.1 {
            tally.moving += 1
            tally.movingTime += gap
            if gap > 1.5 / Double(target) { tally.late += 1 }
        }
        let span = now - tally.from
        guard span >= 0.5 else { return }
        let fps = tally.movingTime > 0 ? Double(tally.moving) / tally.movingTime : 0
        var lines = [
            String(format: " xin %d Hz · vẽ được %.0f khung/giây ", target, fps),
            String(format: " mỗi khung %.1f ms (lâu nhất %.0f) ", tally.wall / Double(tally.frames) * 1000, tally.worst * 1000),
        ]
        if tally.timed > 0 {
            let n = Double(tally.timed)
            lines.append(String(format: "   CPU %.1f ms · chờ %.1f ms ", tally.cpu / n * 1000, max(0, tally.timedWall - tally.cpu) / n * 1000))
        }
        if let waits = probe?.take(), !waits.isEmpty {
            let mean = waits.reduce(0, +) / Double(waits.count)
            lines.append(String(format: " GPU nhận việc sau %.1f ms (lâu nhất %.0f) ", mean * 1000, (waits.max() ?? 0) * 1000))
        }
        lines.append(String(format: " bản đồ giữ main thread %.0f%% · trễ %d/%d ", min(1, tally.wall / span) * 100, tally.late, tally.moving))
        let info = ProcessInfo.processInfo
        var phone: [String] = []
        if info.isLowPowerModeEnabled { phone.append("nguồn điện thấp") }
        switch info.thermalState {
        case .fair: phone.append("máy hơi ấm")
        case .serious: phone.append("máy nóng")
        case .critical: phone.append("máy rất nóng")
        default: break
        }
        if UIAccessibility.isReduceTransparencyEnabled { phone.append("giảm trong suốt") }
        for notes in [phone, Self.launch] where !notes.isEmpty {
            lines.append(" " + notes.joined(separator: " · ") + " ")
        }
        reading = lines.joined(separator: "\n")
        tally = Tally(from: now)
    }

    /// How this copy was built and started. A Debug build, or one Xcode is attached to and records
    /// the GPU of, runs slower than the app does on its own: readings taken so say so.
    private static let launch = launchNotes()

    private nonisolated static func launchNotes() -> [String] {
        var notes: [String] = []
        #if DEBUG
        notes.append("bản Debug")
        #endif
        if debuggerAttached() { notes.append("gắn Xcode") }
        if MTLCaptureManager.shared().supportsDestination(.developerTools) { notes.append("Xcode ghi GPU") }
        if ProcessInfo.processInfo.environment["MTL_DEBUG_LAYER"] == "1" { notes.append("kiểm tra Metal") }
        return notes
    }

    /// Whether a debugger is attached (Apple's Technical Q&A QA1361).
    private nonisolated static func debuggerAttached() -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, u_int(name.count), &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
    }
}

/// A thimble of GPU work, sent at most ten times a second while the readings are on. How long the
/// GPU takes to start it says how busy the GPU is with everything else: the map's own frames and the
/// glass the system recomposes over them each time the map changes. A frame that waits on the main
/// thread while this comes back quickly is waiting on something other than a busy GPU.
final class GPUProbe {
    private let queue: (any MTLCommandQueue)?
    private let scratch: (any MTLBuffer)?
    private var out = false
    private var sent: CFTimeInterval = 0
    private var waits: [Double] = []

    init() {
        let device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        scratch = device?.makeBuffer(length: 4, options: .storageModePrivate)
    }

    func ping() {
        let now = CACurrentMediaTime()
        guard !out, now - sent >= 0.1, let queue, let scratch,
              let buffer = queue.makeCommandBuffer(), let blit = buffer.makeBlitCommandEncoder() else { return }
        blit.fill(buffer: scratch, range: 0..<4, value: 0)
        blit.endEncoding()
        out = true
        sent = now
        // on a Metal thread: only the time crosses back
        buffer.addCompletedHandler { @Sendable [weak self] done in
            let started = done.gpuStartTime
            guard let self else { return }
            Task { @MainActor in self.landed(started > now ? started - now : nil) }
        }
        buffer.commit()
    }

    private func landed(_ wait: Double?) {
        out = false
        if let wait { waits.append(wait) }
    }

    /// The waits since the last call.
    func take() -> [Double] {
        defer { waits.removeAll(keepingCapacity: true) }
        return waits
    }
}

// MARK: - What a day draws

extension MapContent {
    /// A day's legs in their line colours, its numbered stops, hotel, stations and nearby extras.
    @MainActor static func day(_ day: Day, model: AppModel, along: Bool = true) -> MapContent {
        let store = model.store
        var routes: [MapRoute] = []
        var pins: [MapPin] = []
        var seen = Set<String>()
        for item in day.items {
            guard case .move(let m) = item else { continue }
            let line = store.line(m.leg.line)
            let mode = line?.mode ?? .walk
            let pts = store.path(m.leg.id)
            guard pts.count > 1 else { continue }
            routes.append(MapRoute(id: m.leg.id, points: pts, color: mode == .walk ? "#8E8E93" : (line?.color ?? "#8E8E93"), width: mode == .walk ? 3.5 : 5, dashed: mode == .walk))
            for id in [m.leg.from, m.leg.to] {
                if let p = store.place(id), p.kind == .station, seen.insert(id).inserted {
                    pins.append(MapPin(id: id, coordinate: p.coordinate, kind: .station, label: p.name))
                }
            }
        }
        for (i, s) in day.stops {
            guard let p = store.place(s.place), p.kind != .station, !seen.contains(p.id) else { continue }
            seen.insert(p.id)
            let kind: MapPin.Kind = p.kind == .stay ? .stay : (model.isDone(day, i) ? .done : .stop)
            pins.append(MapPin(id: p.id, coordinate: p.coordinate, kind: kind, label: p.name, number: p.kind == .stay ? nil : s.n))
        }
        if let stay = store.place(day.stay), seen.insert(stay.id).inserted {
            pins.append(MapPin(id: stay.id, coordinate: stay.coordinate, kind: .stay, label: stay.name))
        }
        if along {
            for a in day.along {
                guard let p = store.place(a.place), seen.insert(p.id).inserted else { continue }
                pins.append(MapPin(id: p.id, coordinate: p.coordinate, kind: p.snack != nil ? .snack : .along, label: p.name))
            }
        }
        return MapContent(routes: routes, pins: pins)
    }

    /// A detour line from where the day is on foot to a side sight.
    static func detour(_ a: Along) -> MapRoute? {
        guard let p = a.detour?.p else { return nil }
        return MapRoute(id: "detour-\(a.place)", points: Polyline.decode(p), color: "#FF9500", width: 3, dashed: true)
    }
}

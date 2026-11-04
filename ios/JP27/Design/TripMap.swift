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
    /// stays at full strength while another route is in focus (the way to a side trip)
    var dims = true
}

nonisolated struct MapPin: Hashable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        /// halo: a soft disc under the place being looked at; never tappable
        case stop, done, stay, station, along, snack, fuji, highlight, halo

        /// Drawn over a map's picture (`SnapshotPin`) instead of into it: the stops, visited or not, so that
        /// marking one changes neither the picture nor its key (`SnapshotKey.Pin.overlaid`).
        var overlaid: Bool { self == .stop || self == .done }
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
    /// the route being read: drawn a little wider, the others (but those that do not dim) faded.
    /// Changing it restyles the route layers; the routes' shapes stay as they are.
    var focus: String?

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
    /// once, when the map has first drawn everything it holds (style, tiles, the trip's layers): a picture
    /// of it laid over it (`StaticTripMap`) can go
    var onReady: (() -> Void)?

    @Environment(\.colorScheme) private var scheme
    /// Settings › Đo khung hình bản đồ: the map's own frame readings, over the map
    @AppStorage(MapPacer.readingsKey) private var readings = false
    /// Settings › Chẩn đoán › Bóng địa hình, only while measuring
    @AppStorage(MapPacer.reliefKey) private var relief = false

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
        c.showsRelief(readings && relief, in: map)
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
        /// `onReady` was called (it is called once)
        private var ready = false
        private var applied: MapContent?
        /// the style holds the trip's sources and layers (made once per style load)
        private var built = false
        let pacer = MapPacer()
        private var hud: UILabel?
        /// the relief the app's style leaves out, put back over this style to compare frames with it
        private var relief = false
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
                relief = false
                showsRelief(parent.readings && parent.relief, in: mapView)
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
                if let hud, let reading = pacer.takeReading() { hud.text = relief ? reading + "\n bóng địa hình đang bật " : reading }
            }
        }

        /// The map has drawn all it holds, on the main thread as the frame callbacks above (MLNMapView.mm
        /// calls it from the map's own run loop). MapLibre reports it once per style load, once the style and
        /// every source are loaded (a tile that failed counts as loaded); the trip's layers were added in
        /// `didFinishLoading style`, before any frame could count, so they are in it.
        nonisolated func mapViewDidFinishRenderingMap(_ mapView: MLNMapView, fullyRendered: Bool) {
            guard fullyRendered else { return }
            MainActor.assumeIsolated {
                guard loaded, !ready else { return }
                ready = true
                parent.onReady?()
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

        /// The hillshade the site draws and the app's style leaves out (scripts/export-ios.mjs: MapLibre
        /// Native renders each elevation tile it has loaded into a texture of its own on every frame, and
        /// waits for each on the main thread), put back with the site's look while measuring, to see
        /// with the readings what it costs: off, then on, then browse a while.
        func showsRelief(_ on: Bool, in map: MLNMapView) {
            guard on != relief, let style = map.style else { return }
            relief = on
            guard on else {
                if let layer = style.layer(withIdentifier: "relief") { style.removeLayer(layer) }
                return
            }
            let dem: MLNSource
            if let made = style.source(withIdentifier: "relief") {
                dem = made
            } else {
                dem = MLNRasterDEMSource(identifier: "relief",
                                         tileURLTemplates: ["https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"],
                                         options: [.demEncoding: MLNDEMEncoding.terrarium.rawValue, .tileSize: 256, .maximumZoomLevel: 12])
                style.addSource(dem)
            }
            // src/lib/mapStyle.ts: the site's hillshade, under the water. MapLibre 7 lights a hillshade
            // from one or more directions, so the shadow and highlight colours and the direction are
            // arrays, one per light (a lone colour there is an uncaught exception: -[UIColor count]);
            // the accent colour stays a single colour.
            let layer = MLNHillshadeStyleLayer(identifier: "relief", source: dem)
            let shadow = dark ? UIColor.black : UIColor(Color(hex: "#7E7A6E"))
            layer.hillshadeExaggeration = NSExpression(forConstantValue: dark ? 0.45 : 0.32)
            layer.hillshadeShadowColor = NSExpression(forConstantValue: [shadow])
            layer.hillshadeHighlightColor = NSExpression(forConstantValue: [dark ? UIColor(Color(hex: "#5A5A60")) : UIColor.white])
            layer.hillshadeIlluminationDirection = NSExpression(forConstantValue: [315])
            layer.hillshadeAccentColor = NSExpression(forConstantValue: shadow)
            if let water = style.layer(withIdentifier: "water") {
                style.insertLayer(layer, below: water)
            } else {
                style.addLayer(layer)
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
            guard let style = map.style else { return }
            apply(content, in: style)
        }

        /// The same into a style: a map's, or a snapshot's (`MapSnapshots`), drawn once.
        func apply(_ content: MapContent, in style: MLNStyle) {
            guard content != applied else { return }
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
                    f.attributes = ["id": r.id, "color": r.color, "width": r.width, "opacity": r.opacity, "dashed": r.dashed ? 1 : 0, "keep": r.dims ? 0 : 1]
                    return f
                })
            }

            if old?.focus != content.focus { focus(content.focus, in: style) }

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

        /// The route in focus, by restyling the three route layers with expressions that read each
        /// line's id: the timeline moving from one leg to the next changes four properties, where
        /// handing the source new shapes had MapLibre cut every route into tiles again.
        private func focus(_ id: String?, in style: MLNStyle) {
            guard let casing = style.layer(withIdentifier: "routes-case") as? MLNLineStyleLayer,
                  let solid = style.layer(withIdentifier: "routes-solid") as? MLNLineStyleLayer,
                  let dashed = style.layer(withIdentifier: "routes-dashed") as? MLNLineStyleLayer else { return }
            let width: NSExpression, caseWidth: NSExpression, opacity: NSExpression
            if let id {
                width = NSExpression(format: "TERNARY(id == %@, width + 1.5, width)", id)
                caseWidth = NSExpression(format: "TERNARY(id == %@, width + 4.5, width + 3)", id)
                opacity = NSExpression(format: "TERNARY(id == %@ OR keep == 1, opacity, opacity * 0.28)", id)
            } else {
                width = Self.routeWidth
                caseWidth = Self.caseWidth
                opacity = Self.routeOpacity
            }
            casing.lineWidth = caseWidth
            for line in [casing, solid, dashed] { line.lineOpacity = opacity }
            for line in [solid, dashed] { line.lineWidth = width }
        }

        private static var routeWidth: NSExpression { NSExpression(forKeyPath: "width") }
        private static var caseWidth: NSExpression { NSExpression(format: "width + 3") }
        private static var routeOpacity: NSExpression { NSExpression(forKeyPath: "opacity") }

        /// The heat of the walked trail (the journal's map), made the first time a map has some: a
        /// heatmap draws into a texture of its own on every frame and the main thread waits for the
        /// GPU to finish it (as for the relief, showsRelief), so the maps without heat, the Map tab's
        /// among them, carry no heatmap layer at all. Nil while none is needed.
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

            let width = Self.routeWidth
            let opacity = Self.routeOpacity
            let casing = MLNLineStyleLayer(identifier: "routes-case", source: routes)
            casing.predicate = NSPredicate(format: "dashed == 0")
            casing.lineColor = NSExpression(forConstantValue: dark ? UIColor.black.withAlphaComponent(0.6) : UIColor.white)
            casing.lineWidth = Self.caseWidth
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

        /// A pin's colours and sizes, in the map's own scheme: the asset colours (AccentColor, Ai) are resolved
        /// against `dark`, not against whatever trait collection is current when MapLibre reads them. On an
        /// album page the map follows the page's colour, and can be dark on a phone set to light. A map's
        /// picture draws its stops with the same (`SnapshotPin`).
        static func look(_ kind: MapPin.Kind, dark: Bool) -> (fill: UIColor, stroke: UIColor, radius: Double, strokeWidth: Double) {
            let traits = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
            let look = unresolved(kind, dark: dark)
            return (look.fill.resolvedColor(with: traits), look.stroke.resolvedColor(with: traits), look.radius, look.strokeWidth)
        }

        private static func unresolved(_ kind: MapPin.Kind, dark: Bool) -> (fill: UIColor, stroke: UIColor, radius: Double, strokeWidth: Double) {
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
/// than the 8 ms that leaves (street level, tiles arriving and being laid out), frames land
/// unevenly, 8, 17, 25, 33 ms apart, and an uneven 120 judders worse than an even 60. So frames are
/// timed while the map moves: while 120 holds, the map keeps it; when it does not, the map asks for
/// an even 60 and tries 120 again at the start of a later move, waiting longer after each miss
/// (15 s, 30 s, … 4 min). Low Power Mode holds the whole screen at 60 anyway; a phone merely hot
/// does not: the panel and the glass over the map go on at 120, and a map held at 60 under them
/// juddered against them (a recording at "máy nóng" showed it). Only a critical phone holds it.
final class MapPacer {
    static let readingsKey = "debug.mapFrames"
    /// Settings › Chẩn đoán, while the readings are on: the panel, the day strip and the buttons over
    /// the map drawn without glass, to see what the glass costs the map's frames
    static let glassKey = "debug.mapGlass"
    /// Settings › Chẩn đoán, while the readings are on: the hillshade the app's style leaves out, put
    /// back over the map (TripMap.Coordinator.showsRelief)
    static let reliefKey = "debug.mapRelief"

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
            && ProcessInfo.processInfo.thermalState != .critical
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

// MARK: - Maps only looked at

/// A map that is only looked at, in a page that scrolls (a day, a hotel's neighbourhood, a shopping
/// slot): MapLibre draws it once into a picture (`MapSnapshots`), kept on disk, instead of a live
/// map held open in the page, each of which is a Metal surface with its own tiles in memory and its
/// own display link. With `tapToInteract` a tap opens the live map under the picture, to pan and zoom;
/// the picture goes once the map has drawn itself.
///
/// The picture holds no stops: `SnapshotPin` draws them over it, so marking one visited draws no new
/// picture and writes no file. A picture memory holds is there from the first frame; one on disk is
/// read off the main thread; one still to draw waits until the transition that brought the page in has
/// settled (`transitionSettled`), so no snapshot competes with a zoom.
struct StaticTripMap: View {
    let content: MapContent
    let insets: UIEdgeInsets
    let frameID: String
    let tapToInteract: Bool
    /// what the picture draws, folded once here rather than on every body (`MapSnapshots.prints`)
    private let prints: MapSnapshots.Prints

    /// Under `ambientPage` this is the page's canvas scheme (`canvas?.scheme ?? system`,
    /// Components.swift:707), which the page reads from `PhotoCache.knownTone` in its first frame when
    /// the photograph's colour was read before; elsewhere the system's. The picture, its key, its stops
    /// and the live map all take it.
    @Environment(\.colorScheme) private var scheme
    @Environment(\.displayScale) private var displayScale
    @Environment(\.transitionSettled) private var settled
    /// the picture last shown, kept while the next one is found or drawn (a new size, a new scheme)
    @State private var shown: MapSnapshots.Picture?
    @State private var live = false
    /// the live map under the picture has drawn itself, was moved, or took too long: the picture goes
    @State private var uncovered = false

    /// The longest a picture still to draw waits for `transitionSettled`. Longer than
    /// `Perf.Settle.modal` (500 ms: zooms, sheets, the phrase card), so a settle that comes always wins;
    /// the wait is cut short only where none comes (a page left before it settled keeps it false).
    static let settleCap: Duration = .milliseconds(600)
    /// The longest the picture covers a live map that has not said it has drawn (its style failed).
    static let liveCap: Duration = .seconds(2)

    init(content: MapContent, insets: UIEdgeInsets = UIEdgeInsets(top: 30, left: 30, bottom: 30, right: 30),
         frameID: String = "", tapToInteract: Bool = true) {
        self.content = content
        self.insets = insets
        self.frameID = frameID
        self.tapToInteract = tapToInteract
        prints = MapSnapshots.prints(content, insets: insets)
    }

    private var dark: Bool { scheme == .dark }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if live {
                    TripMap(content: content, showsUser: false, insets: insets, frameID: frameID,
                            onUserMove: { uncover() }, onReady: { uncover() })
                }
                if !uncovered {
                    picture(size: geo.size)
                        // from the tap on, the live map underneath takes the touches
                        .allowsHitTesting(!live)
                        .transition(.opacity)
                }
            }
        }
        .task(id: live) {
            guard live else { return }
            do { try await Task.sleep(for: Self.liveCap) } catch { return }
            uncover()
        }
    }

    private func picture(size: CGSize) -> some View {
        let request = MapSnapshots.Request(content: content, frameID: frameID, prints: prints, insets: insets,
                                           size: size, scale: displayScale, dark: dark)
        // the very picture when memory holds it, from the first frame; else the last one shown
        let current = MapSnapshots.shared.cached(request.key) ?? shown
        return Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                if let current {
                    Color.clear
                        .overlay {
                            Image(uiImage: current.image)
                                .resizable()
                                .scaledToFill()
                        }
                        .overlay { stops(on: current, in: size) }
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if tapToInteract, !live {
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
            .accessibilityElement()
            .accessibilityLabel(Text("Bản đồ"))
            .accessibilityAddTraits(tapToInteract ? AccessibilityTraits.isButton : AccessibilityTraits())
            .accessibilityHint(Text(verbatim: tapToInteract ? "Mở bản đồ để kéo và phóng to" : ""))
            .task(id: Wanted(key: request.key, settled: settled)) { await load(request) }
    }

    /// The stops over the picture, at the points the snapshotter gave their places (`Picture.pins`),
    /// laid out as `scaledToFill()` lays out the picture; visited ones under the others and every number
    /// over every disc, as the live map's layers stack. Hidden from VoiceOver: the picture is one
    /// element, "Bản đồ".
    private func stops(on picture: MapSnapshots.Picture, in box: CGSize) -> some View {
        let drawn = Size(width: Double(picture.size.width), height: Double(picture.size.height))
        let view = Size(width: Double(box.width), height: Double(box.height))
        let layered = content.pins.filter { $0.kind == .done } + content.pins.filter { $0.kind == .stop }
        let placed = layered.compactMap { pin -> Placed? in
            guard let p = picture.pins[pin.id] else { return nil }
            let at = drawn.point(Double(p.x), Double(p.y), filling: view)
            return Placed(pin: pin, at: CGPoint(x: at.x, y: at.y))
        }
        // by pin id: a stop marked visited moves under the others without another stop's disc taking its place
        return ZStack {
            ForEach(placed, id: \.pin.id) { stop in
                SnapshotPin(kind: stop.pin.kind, dark: dark)
                    .position(stop.at)
            }
            ForEach(placed, id: \.pin.id) { stop in
                if let n = stop.pin.number {
                    SnapshotPin.number(n)
                        .position(stop.at)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// a stop and where it lands on the view
    private nonisolated struct Placed: Sendable {
        let pin: MapPin
        let at: CGPoint
    }

    /// The picture for `request`: from memory, else from the disk, else drawn, no sooner than the
    /// transition that brought the page in has settled or `settleCap` after this began. A settle that
    /// comes mid-wait restarts this (it is in the task's id) and the drawing starts at once; a drawing
    /// already started for the key is joined, not started again (`MapSnapshots.render`).
    private func load(_ request: MapSnapshots.Request) async {
        guard request.size.width >= 1, request.size.height >= 1 else { return }
        let snapshots = MapSnapshots.shared
        if let hit = snapshots.cached(request.key) {
            if shown !== hit { shown = hit }
            return
        }
        if let saved = await snapshots.stored(request) {
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { shown = saved }
            return
        }
        if !settled {
            do { try await Task.sleep(for: Self.settleCap) } catch { return }
        }
        guard let made = await snapshots.render(request), !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { shown = made }
    }

    private func uncover() {
        guard live, !uncovered else { return }
        withAnimation(.easeOut(duration: 0.2)) { uncovered = true }
    }

    /// what the picture's task waits on: a new key, or the page settling
    private nonisolated struct Wanted: Equatable, Sendable {
        let key: SnapshotKey
        let settled: Bool
    }
}

/// A stop over a map's picture, drawn as the live map draws it (`TripMap.Coordinator.look`): a disc,
/// and its edge outside it, as MapLibre strokes a circle. The picture holds no stops, so a stop marked
/// visited redraws this and nothing else. Its number (`number(_:)`) is set in SF Bold 11, where the
/// live map's is the style's Noto Sans Bold 11.
struct SnapshotPin: View {
    let kind: MapPin.Kind
    let dark: Bool

    var body: some View {
        let look = TripMap.Coordinator.look(kind, dark: dark)
        let outer = (look.radius + look.strokeWidth) * 2
        Circle()
            .fill(Color(uiColor: look.stroke))
            .frame(width: outer, height: outer)
            .overlay {
                Circle()
                    .fill(Color(uiColor: look.fill))
                    .frame(width: look.radius * 2, height: look.radius * 2)
            }
    }

    /// A stop's number, white, laid over every disc as the map's number layer is.
    static func number(_ n: Int) -> some View {
        Text(verbatim: "\(n)")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .fixedSize()
    }
}

/// Pictures of maps (`StaticTripMap`), drawn by MapLibre's snapshotter with the trip's layers put in as
/// `TripMap` puts them, all but the stops (`SnapshotPin` draws those over the picture, at the points
/// kept with it). Kept in memory a while, and on disk in Caches/MapSnapshots/, one picture per frame
/// (`SnapshotKey`): they can always be drawn again. One drawn with no signal is not kept on disk: its
/// tiles may be missing.
final class MapSnapshots {
    static let shared = MapSnapshots()

    /// A drawn map: the image, its size in points, and where each stop it leaves out sits on it.
    nonisolated final class Picture: Sendable {
        let image: UIImage
        /// the snapshot's size in points, which `pins` are in
        let size: CGSize
        /// by pin id, from the image's top left (`MLNMapSnapshot.point(for:)`)
        let pins: [String: CGPoint]

        init(image: UIImage, size: CGSize, pins: [String: CGPoint]) {
            self.image = image
            self.size = size
            self.pins = pins
        }
    }

    /// What a map draws, folded into the key's two numbers (`SnapshotKey.make`).
    nonisolated struct Prints: Equatable, Sendable {
        let route: UInt64
        let pins: UInt64
    }

    /// One picture asked for: what to draw and frame on, at which size and scheme, under which key.
    struct Request {
        /// all of it: the camera frames on the stops too, which the picture leaves out
        let content: MapContent
        let key: SnapshotKey
        let insets: UIEdgeInsets
        let size: CGSize
        let scale: CGFloat
        let dark: Bool

        init(content: MapContent, frameID: String, prints: Prints, insets: UIEdgeInsets, size: CGSize, scale: CGFloat, dark: Bool) {
            self.content = content
            self.insets = insets
            self.size = size
            self.scale = scale
            self.dark = dark
            key = SnapshotKey.make(frameID: frameID, route: prints.route, pins: prints.pins,
                                   size: Size(width: Double(size.width), height: Double(size.height)),
                                   scale: Double(scale), dark: dark, tiles: OfflineMaps.mapBuild.template)
        }
    }

    /// What `content` draws, folded once per map (`StaticTripMap.init`), never per frame: everything but
    /// the pins (each line's look and points, the heat, the focus, the insets, and the app's build, whose
    /// style, code and data draw it), then the pins, a stop by its id and place alone
    /// (`MapPin.Kind.overlaid`), so that marking it visited leaves the key as it was.
    static func prints(_ content: MapContent, insets: UIEdgeInsets) -> Prints {
        var route = SnapshotKey.Fingerprint()
        route.add(UInt64(content.routes.count))
        for r in content.routes {
            route.add(r.id)
            route.add(r.color)
            route.add(r.width)
            route.add(r.opacity)
            route.add(r.dashed)
            route.add(r.dims)
            route.add(r.points)
        }
        route.add(content.heat)
        route.add(content.focus ?? "")
        for edge in [insets.top, insets.left, insets.bottom, insets.right] { route.add(Double(edge)) }
        route.add(build)
        let pins = content.pins.map { p in
            let number = p.number.map { String($0) } ?? ""
            let title = p.titled ? p.label ?? "" : ""
            return SnapshotKey.Pin(id: p.id, coordinate: p.coordinate, look: "\(p.kind.rawValue)·\(number)·\(title)", overlaid: p.kind.overlaid)
        }
        return Prints(route: route.value, pins: SnapshotKey.fingerprint(pins))
    }

    /// the app's build: its style, its code and its data draw the picture
    private static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    private let memory: NSCache<NSString, Picture> = {
        let cache = NSCache<NSString, Picture>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
    /// reads and drawings in flight, so that two asks for one picture share one
    private var reading: [SnapshotKey: Task<Picture?, Never>] = [:]
    private var running: [SnapshotKey: Task<Picture?, Never>] = [:]
    /// the snapshotters' delegates, held while they draw (a snapshotter holds its delegate weakly)
    private var stylers: [ObjectIdentifier: SnapshotStyler] = [:]

    private nonisolated static let folder: URL = {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MapSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// The picture, if memory holds it: for a view's very first frame.
    func cached(_ key: SnapshotKey) -> Picture? {
        memory.object(forKey: key.fileName as NSString)
    }

    /// The picture kept on disk for `request`, read and decoded off the main thread; nil when there is
    /// none, or only half of one. Two asks at once share one read.
    func stored(_ request: Request) async -> Picture? {
        let key = request.key
        if let hit = cached(key) { return hit }
        if let task = reading[key] { return await task.value }
        let image = Self.folder.appending(path: key.fileName)
        let pins = Self.folder.appending(path: key.pinsFileName)
        let scale = request.scale
        let task = Task { await Self.read(image: image, pins: pins, scale: scale) }
        reading[key] = task
        let picture = await task.value
        reading[key] = nil
        if let picture { keep(picture, as: key) }
        return picture
    }

    /// Draws `request`, one snapshotter per key at a time: an ask while one draws waits for it. Kept in
    /// memory, and on disk when online (`write`), after which the frame's other pictures go.
    func render(_ request: Request) async -> Picture? {
        let key = request.key
        if let hit = cached(key) { return hit }
        if let task = running[key] { return await task.value }
        let task = Task { await self.draw(request) }
        running[key] = task
        let picture = await task.value
        running[key] = nil
        guard let picture else { return nil }
        keep(picture, as: key)
        if AppModel.shared.network.online {
            // nobody waits for the files: the picture is in memory already
            Task(priority: .utility) { await Self.write(picture, as: key) }
        }
        return picture
    }

    private func keep(_ picture: Picture, as key: SnapshotKey) {
        let image = picture.image
        memory.setObject(picture, forKey: key.fileName as NSString, cost: Int(image.size.width * image.scale * image.size.height * image.scale * 4))
    }

    private func draw(_ request: Request) async -> Picture? {
        let options = MLNMapSnapshotOptions(styleURL: OfflineMaps.style(dark: request.dark), camera: MLNMapCamera(), size: request.size)
        options.scale = request.scale
        options.showsLogo = false
        Self.frame(request, in: options)
        let snapshotter = MLNMapSnapshotter(options: options)
        var drawn = request.content
        drawn.pins.removeAll { $0.kind.overlaid }
        let styler = SnapshotStyler(content: drawn, dark: request.dark)
        snapshotter.delegate = styler
        let id = ObjectIdentifier(styler)
        stylers[id] = styler
        defer { stylers[id] = nil }
        let stops = request.content.pins.filter { $0.kind.overlaid }
        Perf.mark("map.snapshot")
        return await withCheckedContinuation { (done: CheckedContinuation<Picture?, Never>) in
            // started on the main thread, as MapLibre insists; the snapshotter keeps itself alive
            // until it calls back, on the main queue
            snapshotter.start { snapshot, _ in
                guard let snapshot else {
                    done.resume(returning: nil)
                    return
                }
                var points: [String: CGPoint] = [:]
                for stop in stops {
                    points[stop.id] = snapshot.point(for: CLLocationCoordinate2D(latitude: stop.coordinate.lat, longitude: stop.coordinate.lng))
                }
                done.resume(returning: Picture(image: snapshot.image, size: snapshot.image.size, pins: points))
            }
        }
    }

    /// "<frameID>-<hash>.json": the snapshot's size in points and where each stop sits on it, by pin id.
    private nonisolated struct SavedPins: Codable, Sendable {
        var v = 1
        var w: Double
        var h: Double
        var pins: [String: [Double]]
    }

    /// Off the main thread, both files or nothing (half a picture is drawn again). ImageIO reads the
    /// image by its content: HEIC, or the JPEG written where HEIC could not be (`write`).
    @concurrent private nonisolated static func read(image: URL, pins: URL, scale: CGFloat) async -> Picture? {
        guard let data = try? Data(contentsOf: image), let decoded = UIImage(data: data, scale: scale),
              let json = try? Data(contentsOf: pins), let saved = try? JSONDecoder().decode(SavedPins.self, from: json),
              saved.v == 1 else { return nil }
        var points: [String: CGPoint] = [:]
        for (id, p) in saved.pins where p.count == 2 { points[id] = CGPoint(x: p[0], y: p[1]) }
        let ready = await decoded.byPreparingForDisplay() ?? decoded
        return Picture(image: ready, size: CGSize(width: saved.w, height: saved.h), pins: points)
    }

    /// Off the main thread: the image as HEIC, or as JPEG (0.85) under the same name where HEIC cannot be
    /// made, then its pins, each written whole; then, both written, the frame's other pictures go
    /// (`prune`). A file that cannot be written leaves the frame's older picture where it is.
    @concurrent private nonisolated static func write(_ picture: Picture, as key: SnapshotKey) async {
        var pins: [String: [Double]] = [:]
        for (id, p) in picture.pins { pins[id] = [Double(p.x), Double(p.y)] }
        let saved = SavedPins(w: Double(picture.size.width), h: Double(picture.size.height), pins: pins)
        guard let image = picture.image.heicData() ?? picture.image.jpegData(compressionQuality: 0.85),
              let json = try? JSONEncoder().encode(saved) else { return }
        do {
            try image.write(to: folder.appending(path: key.fileName), options: .atomic)
            try json.write(to: folder.appending(path: key.pinsFileName), options: .atomic)
        } catch {
            // a cache: the picture stays in memory, and is drawn again at a later launch
            return
        }
        prune(keeping: key)
    }

    /// Deletes the frame's other pictures (`SnapshotKey.stale`): one picture per frame on disk.
    nonisolated static func prune(keeping key: SnapshotKey) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for name in SnapshotKey.stale(urls.map(\.lastPathComponent), keeping: key) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    /// At launch, off the main thread: the pictures of the build before 4.1 ("<key>.png") go, then the
    /// oldest pictures until the folder holds `bytes` at most (`SnapshotKey.trimmed`). Nothing that is
    /// not ours is touched.
    @concurrent nonisolated static func trim(toBytes bytes: Int) async {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        let files = urls.compactMap { url -> SnapshotKey.File? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return SnapshotKey.File(name: url.lastPathComponent, bytes: values.fileSize ?? 0,
                                    modified: values.contentModificationDate ?? .distantPast)
        }
        for name in SnapshotKey.trimmed(files, toBytes: bytes) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }

    #if DEBUG
    /// "12 ảnh · 1.8 MB": the pictures on disk, for Settings › Chẩn đoán › So khung bản đồ, with those
    /// of the build before 4.1 if any are left.
    @concurrent nonisolated static func onDisk() async -> String {
        let keys: [URLResourceKey] = [.fileSizeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return "—" }
        var pictures = 0, old = 0, bytes = 0
        for url in urls {
            let name = url.lastPathComponent
            if name.hasSuffix(".heic") {
                pictures += 1
            } else if name.hasSuffix(".png") {
                old += 1
            } else if !name.hasSuffix(".json") {
                continue
            }
            bytes += (try? url.resourceValues(forKeys: Set(keys)).fileSize) ?? 0
        }
        let size = String(format: "%.1f MB", Double(bytes) / 1_048_576)
        return old > 0 ? "\(pictures) ảnh · \(old) ảnh cũ · \(size)" : "\(pictures) ảnh · \(size)"
    }
    #endif

    /// The camera `TripMap` would fit to the same content: a point (or a few metres) at street
    /// level, else everything, at least ~600 m across, with the insets kept clear around it.
    private static func frame(_ request: Request, in options: MLNMapSnapshotOptions) {
        let pts = request.content.outline
        guard let b = Geo.bounds(pts) else { return }
        if pts.count == 1 || (b.ne.lat - b.sw.lat < 0.002 && b.ne.lng - b.sw.lng < 0.002) {
            let center = CLLocationCoordinate2D(latitude: (b.sw.lat + b.ne.lat) / 2, longitude: (b.sw.lng + b.ne.lng) / 2)
            options.camera = MLNMapCamera(lookingAtCenter: center, altitude: 1000, pitch: 0, heading: 0)
            options.zoomLevel = 15.5
            return
        }
        let mid = (lat: (b.sw.lat + b.ne.lat) / 2, lng: (b.sw.lng + b.ne.lng) / 2)
        let half = (lat: max((b.ne.lat - b.sw.lat) / 2, 0.0028), lng: max((b.ne.lng - b.sw.lng) / 2, 0.0034))
        let w = Double(request.size.width), h = Double(request.size.height)
        let i = request.insets
        // the bounds grown by the share of the picture the insets take, so the content fills what is left
        let sx = w / max(1, w - Double(i.left + i.right))
        let sy = h / max(1, h - Double(i.top + i.bottom))
        options.coordinateBounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: mid.lat - half.lat * sy, longitude: mid.lng - half.lng * sx),
            ne: CLLocationCoordinate2D(latitude: mid.lat + half.lat * sy, longitude: mid.lng + half.lng * sx))
    }
}

/// Puts the trip's layers into a snapshot's style with the code that puts them into a map's.
final class SnapshotStyler: NSObject, MLNMapSnapshotterDelegate {
    private let content: MapContent
    private let painter: TripMap.Coordinator

    init(content: MapContent, dark: Bool) {
        self.content = content
        painter = TripMap.Coordinator(parent: TripMap(content: content, showsUser: false, interactive: false), dark: dark)
    }

    /// On the main thread: MapLibre starts a snapshotter only there (it raises otherwise) and calls
    /// back on that thread's run loop, which `assumeIsolated` checks. Only the rendering has a thread of
    /// its own: the map that loads the style, and calls this, is made on the thread that started the
    /// snapshotter, and the style is that map's own (MLNMapSnapshotter.mm and map_snapshotter.cpp at
    /// ios-v7.0.0), so the layers go in here, before this returns, and cannot be put in elsewhere. The
    /// style is not Sendable (a plain NSObject, where the map view's delegate hands over a main-actor
    /// UIView), so it crosses into the main actor in a box; it never leaves the main thread.
    nonisolated func mapSnapshotter(_ snapshotter: MLNMapSnapshotter, didFinishLoading style: MLNStyle) {
        let handed = Handed(style: style)
        MainActor.assumeIsolated { painter.apply(content, in: handed.style) }
    }

    private nonisolated struct Handed: @unchecked Sendable { let style: MLNStyle }
}

#if DEBUG
/// Settings › Chẩn đoán › So khung bản đồ: a day's picture (`StaticTripMap`, framed by
/// `MapSnapshots.frame`) above a live map of the same content, size and insets (framed by
/// `TripMap.Coordinator.fit`), to compare on the phone (docs/perf/2026-11-device-perf-phase4-5.md,
/// Task 4.1), and what the pictures hold on disk. The picture here has a frame of its own, so looking
/// at it prunes nothing of the day pages'.
struct MapFrameCheck: View {
    @Environment(AppModel.self) private var model
    @State private var key = "1"
    @State private var disk: String?

    /// DayView's
    private static let insets = UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28)

    var body: some View {
        let days = model.store.trip.days + model.store.trip.altDays
        List {
            Section {
                Picker("Ngày", selection: $key) {
                    ForEach(days, id: \.key) { day in
                        Text(verbatim: day.isAlternative ? day.title : "Ngày \(day.n)").tag(day.key)
                    }
                }
                LabeledContent("Ảnh bản đồ trên máy") {
                    Text(disk ?? "—").monospacedDigit()
                }
            }
            if let day = model.store.day(key) {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ảnh").font(.footnote).foregroundStyle(.secondary)
                        StaticTripMap(content: .day(day, model: model), insets: Self.insets, frameID: "frame-check", tapToInteract: false)
                            .frame(height: 240)
                        Text("Bản đồ thật").font(.footnote).foregroundStyle(.secondary)
                        TripMap(content: .day(day, model: model), showsUser: false, interactive: false, insets: Self.insets, frameID: day.key)
                            .frame(height: 240)
                    }
                    .id(day.key)
                } footer: {
                    Text("Hai khung phải trùng nhau: cùng tâm, cùng mức phóng, ghim ở cùng chỗ. Số trên ghim của ảnh là chữ SF, của bản đồ thật là Noto Sans.")
                }
            }
        }
        .navigationTitle("So khung bản đồ")
        .task(id: key) { disk = await MapSnapshots.onDisk() }
    }
}
#endif

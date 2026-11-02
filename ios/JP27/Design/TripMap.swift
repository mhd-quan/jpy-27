import MapLibre
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
nonisolated struct MapCamera: Equatable, Sendable {
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
    var camera: MapCamera?
    var onSelect: ((String) -> Void)?
    /// the person panned or zoomed the map themselves
    var onUserMove: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

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
        private var layers: [String] = []
        private var sources: [String] = []
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
                layers = []
                sources = []
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

        func move(_ map: MLNMapView, _ move: MapCamera.Move, animated: Bool = true) {
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
            if sources.isEmpty { build(style) }
            let old = applied
            applied = content

            if old?.heat != content.heat, let heat = style.source(withIdentifier: "heat") as? MLNShapeSource {
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

        /// The style's own layers for the trip: heat, then routes (a light casing under solid
        /// lines, colour, width and opacity read from each line), then pins by kind, numbers and
        /// side-trip names.
        private func build(_ style: MLNStyle) {
            let empty = MLNShapeCollectionFeature(shapes: [])
            let heat = MLNShapeSource(identifier: "heat", shape: empty, options: nil)
            let routes = MLNShapeSource(identifier: "routes", shape: empty, options: nil)
            let pins = MLNShapeSource(identifier: "pins", shape: empty, options: nil)
            for source in [heat, routes, pins] { style.addSource(source) }
            sources = ["heat", "routes", "pins"]

            let heatLayer = MLNHeatmapStyleLayer(identifier: "heat", source: heat)
            heatLayer.heatmapRadius = NSExpression(forConstantValue: 22)
            heatLayer.heatmapOpacity = NSExpression(forConstantValue: 0.75)
            heatLayer.heatmapIntensity = NSExpression(forConstantValue: 0.8)
            style.addLayer(heatLayer)

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

            var ids = ["heat", "routes-case", "routes-solid", "routes-dashed"]
            for kind in [MapPin.Kind.halo, .station, .along, .highlight, .snack, .fuji, .stay, .done, .stop] {
                let layer = MLNCircleStyleLayer(identifier: "pins-\(kind.rawValue)", source: pins)
                layer.predicate = NSPredicate(format: "kind == %@", kind.rawValue)
                let look = Self.look(kind, dark: dark)
                layer.circleColor = NSExpression(forConstantValue: look.fill)
                layer.circleRadius = NSExpression(forConstantValue: look.radius)
                layer.circleStrokeColor = NSExpression(forConstantValue: look.stroke)
                layer.circleStrokeWidth = NSExpression(forConstantValue: look.strokeWidth)
                style.addLayer(layer)
                ids.append(layer.identifier)
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
            layers = ids + ["pins-numbers", "pins-titles"]
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

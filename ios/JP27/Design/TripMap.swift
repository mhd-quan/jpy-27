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
        case stop, done, stay, station, along, snack, fuji, highlight
    }

    let id: String
    let coordinate: Coordinate
    let kind: Kind
    var label: String?
    var number: Int?
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
    var onSelect: ((String) -> Void)?

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
        map.logoViewPosition = .bottomLeft
        map.attributionButtonPosition = .bottomLeft
        map.maximumZoomLevel = 18
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        map.showsUserLocation = showsUser
        map.contentInset = .zero
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
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: TripMap
        var dark: Bool
        var loaded = false
        var frameID: String
        var focus: Coordinate?
        var focusID = 0
        private var applied: MapContent?
        private var layers: [String] = []
        private var sources: [String] = []
        private let pinLayers = MapPin.Kind.allCases.map { "pins-\($0.rawValue)" }

        init(parent: TripMap, dark: Bool) {
            self.parent = parent
            self.dark = dark
            frameID = parent.frameID
            focus = parent.focus
            focusID = parent.focusID
        }

        nonisolated func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MainActor.assumeIsolated {
                loaded = true
                applied = nil
                layers = []
                sources = []
                apply(parent.content, to: mapView)
                frame(mapView, animated: false)
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

        func frame(_ map: MLNMapView, animated: Bool) {
            let pts = parent.content.outline
            guard let b = Geo.bounds(pts) else { return }
            if pts.count == 1 || (b.ne.lat - b.sw.lat < 0.002 && b.ne.lng - b.sw.lng < 0.002) {
                map.setCenter(CLLocationCoordinate2D(latitude: b.sw.lat, longitude: b.sw.lng), zoomLevel: 15.5, animated: animated)
                return
            }
            let bounds = MLNCoordinateBounds(sw: CLLocationCoordinate2D(latitude: b.sw.lat, longitude: b.sw.lng),
                                             ne: CLLocationCoordinate2D(latitude: b.ne.lat, longitude: b.ne.lng))
            map.setVisibleCoordinateBounds(bounds, edgePadding: parent.insets, animated: animated, completionHandler: nil)
        }

        func apply(_ content: MapContent, to map: MLNMapView) {
            guard let style = map.style, content != applied else { return }
            applied = content
            for id in layers { if let l = style.layer(withIdentifier: id) { style.removeLayer(l) } }
            for id in sources { if let s = style.source(withIdentifier: id) { style.removeSource(s) } }
            layers = []
            sources = []

            // heat first, so routes and pins draw over it
            if !content.heat.isEmpty {
                let points = content.heat.map { c -> MLNPointFeature in
                    let f = MLNPointFeature()
                    f.coordinate = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lng)
                    return f
                }
                let source = MLNShapeSource(identifier: "heat", shape: MLNShapeCollectionFeature(shapes: points), options: nil)
                style.addSource(source)
                let layer = MLNHeatmapStyleLayer(identifier: "heat", source: source)
                layer.heatmapRadius = NSExpression(forConstantValue: 22)
                layer.heatmapOpacity = NSExpression(forConstantValue: 0.75)
                layer.heatmapIntensity = NSExpression(forConstantValue: 0.8)
                style.addLayer(layer)
                sources.append("heat")
                layers.append("heat")
            }

            // one layer per look: a day has a handful of line colours
            let groups = Dictionary(grouping: content.routes) { "\($0.color)|\($0.width)|\($0.dashed)|\($0.opacity)" }
            for (key, routes) in groups.sorted(by: { $0.key < $1.key }) {
                let id = "route-\(abs(key.hashValue))"
                let lines = routes.compactMap { r -> MLNPolylineFeature? in
                    var coords = r.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                    guard coords.count > 1 else { return nil }
                    return MLNPolylineFeature(coordinates: &coords, count: UInt(coords.count))
                }
                guard let first = routes.first, !lines.isEmpty else { continue }
                let source = MLNShapeSource(identifier: id, shape: MLNShapeCollectionFeature(shapes: lines), options: nil)
                style.addSource(source)
                // a light casing under coloured lines keeps them readable on the basemap
                if !first.dashed {
                    let casing = MLNLineStyleLayer(identifier: id + "-case", source: source)
                    casing.lineColor = NSExpression(forConstantValue: dark ? UIColor.black.withAlphaComponent(0.6) : UIColor.white)
                    casing.lineWidth = NSExpression(forConstantValue: first.width + 3)
                    casing.lineCap = NSExpression(forConstantValue: "round")
                    casing.lineJoin = NSExpression(forConstantValue: "round")
                    casing.lineOpacity = NSExpression(forConstantValue: first.opacity)
                    style.addLayer(casing)
                    layers.append(id + "-case")
                }
                let line = MLNLineStyleLayer(identifier: id, source: source)
                line.lineColor = NSExpression(forConstantValue: UIColor(Color(hex: first.color)))
                line.lineWidth = NSExpression(forConstantValue: first.width)
                line.lineCap = NSExpression(forConstantValue: "round")
                line.lineJoin = NSExpression(forConstantValue: "round")
                line.lineOpacity = NSExpression(forConstantValue: first.opacity)
                if first.dashed { line.lineDashPattern = NSExpression(forConstantValue: [0.1, 2]) }
                style.addLayer(line)
                sources.append(id)
                layers.append(id)
            }

            // pins: one circle layer per kind, numbers on the plan's stops
            let features = content.pins.map { p -> MLNPointFeature in
                let f = MLNPointFeature()
                f.coordinate = CLLocationCoordinate2D(latitude: p.coordinate.lat, longitude: p.coordinate.lng)
                var attrs: [String: Any] = ["id": p.id, "kind": p.kind.rawValue]
                if let n = p.number { attrs["n"] = "\(n)" }
                if let l = p.label { attrs["label"] = l }
                f.attributes = attrs
                return f
            }
            let pinSource = MLNShapeSource(identifier: "pins", shape: MLNShapeCollectionFeature(shapes: features), options: nil)
            style.addSource(pinSource)
            sources.append("pins")
            for kind in [MapPin.Kind.station, .along, .highlight, .snack, .fuji, .stay, .done, .stop] {
                let layer = MLNCircleStyleLayer(identifier: "pins-\(kind.rawValue)", source: pinSource)
                layer.predicate = NSPredicate(format: "kind == %@", kind.rawValue)
                let look = Self.look(kind, dark: dark)
                layer.circleColor = NSExpression(forConstantValue: look.fill)
                layer.circleRadius = NSExpression(forConstantValue: look.radius)
                layer.circleStrokeColor = NSExpression(forConstantValue: look.stroke)
                layer.circleStrokeWidth = NSExpression(forConstantValue: look.strokeWidth)
                style.addLayer(layer)
                layers.append(layer.identifier)
            }
            let numbers = MLNSymbolStyleLayer(identifier: "pins-numbers", source: pinSource)
            numbers.predicate = NSPredicate(format: "n != nil")
            numbers.text = NSExpression(forKeyPath: "n")
            numbers.textFontNames = NSExpression(forConstantValue: ["Noto Sans Bold"])
            numbers.textFontSize = NSExpression(forConstantValue: 11)
            numbers.textColor = NSExpression(forConstantValue: UIColor.white)
            numbers.textAllowsOverlap = NSExpression(forConstantValue: true)
            numbers.textIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(numbers)
            layers.append("pins-numbers")
        }

        private static func look(_ kind: MapPin.Kind, dark: Bool) -> (fill: UIColor, stroke: UIColor, radius: Double, strokeWidth: Double) {
            let edge: UIColor = dark ? .black : .white
            switch kind {
            case .stop: return (UIColor(named: "AccentColor") ?? .systemRed, edge, 9, 2)
            case .done: return (.systemGray, edge, 8, 2)
            case .stay: return (UIColor(Color(hex: "#8A5CD0")), edge, 8, 2)
            case .station: return (edge, .systemGray, 4.5, 2)
            case .along: return (edge, .systemOrange, 5, 2.5)
            case .snack: return (.systemOrange, edge, 5.5, 1.5)
            case .fuji: return (.systemIndigo, edge, 6, 2)
            case .highlight: return (.systemBlue, edge, 5.5, 1.5)
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

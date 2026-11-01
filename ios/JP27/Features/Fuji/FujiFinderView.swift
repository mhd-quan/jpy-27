import ARKit
import Combine
import RealityKit
import SwiftUI
import TripKit

/// Hold the phone up: a marker sits where Fuji's summit is, computed from your position, with
/// curvature and refraction. On LiDAR iPhones the room around you is meshed, so a building or tree
/// in front hides the marker the way it hides the mountain.
struct FujiFinderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var onScreen = false
    @State private var cloud: Double?

    private let arSupported = ARWorldTrackingConfiguration.isSupported

    private var sight: FujiSight.Sight? {
        model.position.map { FujiSight.from($0, altitude: model.location.altitude ?? 0) }
    }

    /// A researched viewpoint within 300 m, with its terrain verdict.
    private var spot: FujiGuide.Spot? {
        guard let here = model.position else { return nil }
        return model.guide.fuji.spots
            .map { ($0, Geo.km(here, Coordinate($0.lat, $0.lng))) }
            .filter { $0.1 <= 0.3 }
            .min { $0.1 < $1.1 }?.0
    }

    var body: some View {
        ZStack {
            if let sight {
                if arSupported {
                    FujiARView(sight: sight, onScreen: $onScreen)
                        .ignoresSafeArea()
                } else {
                    FujiCompass(sight: sight, heading: model.location.heading)
                }
            } else {
                FujiWaiting()
            }
        }
        .overlay {
            if let sight, arSupported, !onScreen {
                FujiTurnHint(sight: sight, heading: model.location.heading)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .animation(.smooth, value: onScreen)
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Đóng")
            .padding(16)
        }
        .overlay(alignment: .bottom) {
            if let sight {
                FujiInfo(sight: sight, cloud: cloud, spot: spot)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 24)
            }
        }
        .task {
            model.location.resume(for: model)
            let hours = await model.forecasts.hours("summit", at: FujiSight.summit, online: model.network.online)
            let now = model.now
            let nearest = hours.min { abs($0.date.timeIntervalSince(now)) < abs($1.date.timeIntervalSince(now)) }?.cloud
            withAnimation(.smooth) { cloud = nearest }
        }
    }
}

// MARK: - Overlays

/// Distance, direction, height above the horizon, summit cloud, and the terrain verdict when known.
private struct FujiInfo: View {
    @Environment(AppModel.self) private var model
    let sight: FujiSight.Sight
    let cloud: Double?
    let spot: FujiGuide.Spot?
    @Namespace private var glass

    var body: some View {
        // the cloud and terrain pills grow out of the distance pill when their data arrives
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    Text("Fuji").fontWeight(.bold)
                    Text(Fmt.km(sight.km))
                    Text("·")
                    Text(sight.compass)
                    Text("·")
                    Text("cao \(Fmt.decimal(sight.elevation, digits: 1))°")
                }
                .font(.subheadline)
                .monospacedDigit()
                .padding(.horizontal, 16)
                .frame(minHeight: 40)
                .glassEffect(.regular, in: .capsule)
                .glassEffectID("sight", in: glass)
                .accessibilityElement(children: .combine)

                if cloud != nil || spot != nil {
                    HStack(spacing: 8) {
                        if let cloud {
                            Label("Mây đỉnh \(Int((cloud * 100).rounded()))%", systemImage: cloud > 0.6 ? "cloud.fill" : "cloud.sun.fill")
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .glassEffect(.regular, in: .capsule)
                                .glassEffectID("cloud", in: glass)
                        }
                        if let spot {
                            Label(verdict(spot), systemImage: spot.visible ? "eye" : "eye.slash")
                                .padding(.horizontal, 14)
                                .frame(minHeight: 36)
                                .glassEffect(.regular, in: .capsule)
                                .glassEffectID("spot", in: glass)
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                }
            }
        }
    }

    private func verdict(_ s: FujiGuide.Spot) -> String {
        if s.visible {
            return s.shownM.map { "Địa hình: lộ \(Fmt.grouped(Int($0))) m" } ?? "Địa hình: thấy được"
        }
        return s.blockKm.map { "Núi che ở \(Fmt.km($0))" } ?? "Bị núi che"
    }
}

/// When the marker is off screen: which way to turn and by how much.
private struct FujiTurnHint: View {
    let sight: FujiSight.Sight
    let heading: Double?

    var body: some View {
        if let heading {
            let turn = Geo.angleDelta(heading, sight.bearing)
            VStack(spacing: 8) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 44, weight: .bold))
                    .rotationEffect(.degrees(turn))
                    .animation(.smooth(duration: 0.3), value: Int(turn))
                Text(abs(turn) < 8 ? "Ngước lên" : "Xoay \(turn > 0 ? "phải" : "trái") \(Int(abs(turn).rounded()))°")
                    .font(.headline)
                    .monospacedDigit()
            }
            .padding(20)
            .glassEffect(.regular, in: .rect(cornerRadius: 28, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}

private struct FujiWaiting: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Đang tìm vị trí…").font(.headline)
            if !model.location.isAllowed {
                Button("Bật vị trí") { model.location.requestWhenInUse() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

/// Without world tracking: a compass that points at the summit.
private struct FujiCompass: View {
    let sight: FujiSight.Sight
    let heading: Double?

    var body: some View {
        let rotation = heading.map { Geo.angleDelta($0, sight.bearing) } ?? sight.bearing
        VStack(spacing: 28) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 2)
                ForEach(0 ..< 12) { i in
                    Capsule()
                        .fill(.tertiary)
                        .frame(width: 2, height: i % 3 == 0 ? 14 : 8)
                        .offset(y: -128)
                        .rotationEffect(.degrees(Double(i) * 30 - (heading ?? 0)))
                }
                Image(systemName: "location.north.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .rotationEffect(.degrees(rotation))
                    .animation(.smooth(duration: 0.3), value: Int(rotation))
            }
            .frame(width: 270, height: 270)
            Text(heading == nil ? "Hướng \(Int(sight.bearing.rounded()))° tính từ Bắc" : "Mũi tên chỉ về đỉnh Fuji")
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AR

private struct FujiARView: UIViewRepresentable {
    let sight: FujiSight.Sight
    @Binding var onScreen: Bool

    func makeCoordinator() -> FujiARCoordinator {
        FujiARCoordinator(onScreen: $onScreen)
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        let config = ARWorldTrackingConfiguration()
        // y up, −z true north: bearings from the compass map straight into the scene
        config.worldAlignment = .gravityAndHeading
        if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            view.environment.sceneUnderstanding.options.insert(.occlusion)
        }
        view.session.run(config)
        context.coordinator.attach(to: view, sight: sight)
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {
        context.coordinator.onScreen = $onScreen
        context.coordinator.move(to: sight)
    }

    static func dismantleUIView(_ view: ARView, coordinator: FujiARCoordinator) {
        coordinator.detach()
        view.session.pause()
    }
}

private final class FujiARCoordinator {
    var onScreen: Binding<Bool>
    private weak var view: ARView?
    private var anchor: AnchorEntity?
    private var placed: FujiSight.Sight?
    private var updates: (any Cancellable)?
    private var lastCheck = Date.distantPast

    /// The marker floats this far away along the summit's line: far enough that nearby buildings
    /// (meshed by LiDAR) can stand in front of it, near enough to render crisply.
    private static let distance: Float = 120

    init(onScreen: Binding<Bool>) {
        self.onScreen = onScreen
    }

    func attach(to view: ARView, sight: FujiSight.Sight) {
        self.view = view
        let anchor = AnchorEntity(world: Self.position(sight))
        anchor.addChild(Self.marker())
        view.scene.addAnchor(anchor)
        self.anchor = anchor
        placed = sight
        updates = view.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
            self?.check()
        }
    }

    /// Follow the position as you walk; small changes are not worth moving the marker.
    func move(to sight: FujiSight.Sight) {
        guard let anchor, let placed else { return }
        guard abs(Geo.angleDelta(placed.bearing, sight.bearing)) > 0.3 || abs(placed.elevation - sight.elevation) > 0.2 else { return }
        anchor.position = Self.position(sight)
        self.placed = sight
    }

    func detach() {
        updates?.cancel()
        updates = nil
    }

    /// Is the marker in front of the camera and inside the screen? Checked five times a second.
    private func check() {
        let now = Date()
        guard now.timeIntervalSince(lastCheck) > 0.2, let view, let anchor else { return }
        lastCheck = now
        let target = anchor.position(relativeTo: nil)
        let camera = view.cameraTransform
        let forward = camera.rotation.act(SIMD3<Float>(0, 0, -1))
        let toward = simd_normalize(target - camera.translation)
        var visible = simd_dot(forward, toward) > 0.3
        if visible, let p = view.project(target) {
            visible = view.bounds.insetBy(dx: 24, dy: 24).contains(p)
        } else {
            visible = false
        }
        if visible != onScreen.wrappedValue { onScreen.wrappedValue = visible }
    }

    private static func position(_ s: FujiSight.Sight) -> SIMD3<Float> {
        let b = Float(s.bearing * .pi / 180)
        let e = Float(s.elevation * .pi / 180)
        let d = distance
        return SIMD3<Float>(sin(b) * cos(e) * d, sin(e) * d, -cos(b) * cos(e) * d)
    }

    /// A red dot with "Fuji" above it, the label always turned to the camera.
    private static func marker() -> Entity {
        let root = Entity()
        let dot = ModelEntity(mesh: .generateSphere(radius: 2), materials: [UnlitMaterial(color: .systemRed)])
        root.addChild(dot)

        let mesh = MeshResource.generateText(
            "Fuji",
            extrusionDepth: 0.1,
            font: .systemFont(ofSize: 6, weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )
        let text = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
        let c = mesh.bounds.center
        text.position = SIMD3<Float>(-c.x, -c.y, 0)
        let label = Entity()
        label.addChild(text)
        label.position = SIMD3<Float>(0, 6, 0)
        label.components.set(BillboardComponent())
        root.addChild(label)
        return root
    }
}

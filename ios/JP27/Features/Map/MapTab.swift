import SwiftUI
import TripKit

/// The day on the map with you on it: the next place and how far, and what is worth a detour nearby.
///
/// The panel is drawn in the tab, not presented as a sheet: a sheet would cover the tab bar and
/// block the app's own sheets (place, ride, expense) from presenting while the map is open.
struct MapTab: View {
    @Environment(AppModel.self) private var model
    @State private var dayKey: String?
    @State private var selected: String?
    @State private var focus: Coordinate?
    @State private var focusID = 0
    @State private var reframe = 0
    @State private var stage: MapPanelStage = .peek

    private var day: Day { dayKey.flatMap { model.store.day($0) } ?? model.focusDay }

    private var content: MapContent {
        var c = MapContent.day(day, model: model)
        if let id = selected, let a = day.along.first(where: { $0.place == id }), let line = MapContent.detour(a) {
            c.routes.append(line)
        }
        return c
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                TripMap(
                    content: content,
                    insets: UIEdgeInsets(top: 120, left: 36, bottom: MapPanelStage.medium.height(in: geo.size.height) + 24, right: 72),
                    frameID: "\(day.key)-\(reframe)",
                    focus: focus,
                    focusID: focusID,
                    onSelect: select
                )
                .ignoresSafeArea()

                MapPanel(stage: $stage, containerHeight: geo.size.height) {
                    MapPanelHeader(day: day)
                } content: {
                    MapPanelList(day: day, selected: $selected, onPick: pick)
                }
            }
            .overlay(alignment: .top) {
                MapDayChip(day: day) { key in
                    dayKey = key
                    selected = nil
                    reframe += 1
                }
                .padding(.top, 8)
                .padding(.horizontal, 72)
            }
            .overlay(alignment: .topTrailing) {
                MapControls(
                    locate: locate,
                    fuji: { model.sheet = .fujiFinder },
                    frameDay: {
                        selected = nil
                        reframe += 1
                    }
                )
                .padding(.top, 64)
                .padding(.trailing, 12)
            }
        }
        .onAppear(perform: consumeFocus)
        .onChange(of: model.mapFocus) { consumeFocus() }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func select(_ id: String) {
        guard let p = model.store.place(id) else { return }
        withAnimation(.snappy) {
            selected = id
            focus = p.coordinate
            focusID += 1
            if stage == .peek { stage = .medium }
        }
    }

    private func pick(_ id: String) {
        guard let p = model.store.place(id) else { return }
        withAnimation(.snappy) {
            selected = id
            focus = p.coordinate
            focusID += 1
            // keep the map in view once a row is chosen
            if stage == .large { stage = .medium }
        }
    }

    private func locate() {
        guard let p = model.position else {
            model.location.requestWhenInUse()
            return
        }
        focus = p
        focusID += 1
    }

    private func consumeFocus() {
        guard let id = model.mapFocus else { return }
        model.mapFocus = nil
        select(id)
    }
}

// MARK: - Chrome

/// The day shown, as a glass capsule that opens the list of days.
private struct MapDayChip: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let choose: (String) -> Void

    var body: some View {
        let alternatives = model.store.trip.altDays.filter { alt in !model.days.contains { $0.key == alt.key } }
        Menu {
            Section {
                ForEach(model.days) { d in
                    Button {
                        choose(d.key)
                    } label: {
                        if d.key == day.key {
                            Label("Ngày \(d.n) · \(d.title)", systemImage: "checkmark")
                        } else {
                            Text("Ngày \(d.n) · \(d.title)")
                        }
                    }
                }
            }
            if !alternatives.isEmpty {
                Section("Phương án") {
                    ForEach(alternatives) { a in
                        Button("Thay ngày \(a.replaces ?? a.n) · \(a.title)") { choose(a.key) }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("Ngày \(day.n)").fontWeight(.semibold).monospacedDigit()
                Text(day.title).foregroundStyle(.secondary).lineLimit(1)
                Image(systemName: "chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ngày \(day.n), \(day.title)")
        .accessibilityHint("Chọn ngày khác")
    }
}

/// Locate, Fuji, frame the day: one glass column at the trailing edge.
private struct MapControls: View {
    let locate: () -> Void
    let fuji: () -> Void
    let frameDay: () -> Void

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                button("location.fill", "Vị trí của tôi", locate)
                Divider().frame(width: 26)
                button("mountain.2.fill", "Tìm Fuji", fuji)
                Divider().frame(width: 26)
                button("arrow.up.left.and.arrow.down.right", "Cả ngày", frameDay)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    private func button(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 48, height: 48)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Panel

private enum MapPanelStage: CaseIterable {
    case peek, medium, large

    func height(in container: CGFloat) -> CGFloat {
        switch self {
        case .peek: 132
        case .medium: max(260, container * 0.45)
        case .large: max(320, container - 72)
        }
    }
}

/// A floating panel that snaps to three heights. The header drags it; the list scrolls inside it.
/// Release velocity is projected forward so a flick lands where it is going.
private struct MapPanel<Header: View, Content: View>: View {
    @Binding var stage: MapPanelStage
    let containerHeight: CGFloat
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    @GestureState private var drag: CGFloat = 0

    private var lowest: CGFloat { MapPanelStage.peek.height(in: containerHeight) }
    private var highest: CGFloat { MapPanelStage.large.height(in: containerHeight) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.secondary.opacity(0.45))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                header
                    .padding(.horizontal, 18)
                    .padding(.bottom, 10)
            }
            .contentShape(.rect)
            .gesture(dragGesture)
            .onTapGesture { cycle() }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: stage == .large ? "Thu gọn" : "Mở rộng") { cycle() }

            if stage != .peek || drag < -20 {
                content
                    .transition(.opacity)
            }
        }
        .frame(height: currentHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 32, style: .continuous))
        .glassEffect(.regular, in: .rect(cornerRadius: 32, style: .continuous))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var currentHeight: CGFloat {
        let raw = stage.height(in: containerHeight) - drag
        // soft limits: resist more the further past them
        if raw > highest { return highest + rubber(raw - highest) }
        if raw < lowest { return lowest - rubber(lowest - raw) }
        return raw
    }

    private func rubber(_ overshoot: CGFloat, dimension: CGFloat = 300, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * overshoot)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($drag) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let projected = stage.height(in: containerHeight) - value.predictedEndTranslation.height
                let target = MapPanelStage.allCases.min {
                    abs($0.height(in: containerHeight) - projected) < abs($1.height(in: containerHeight) - projected)
                } ?? stage
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { stage = target }
            }
    }

    private func cycle() {
        withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
            stage = switch stage {
            case .peek: .medium
            case .medium: .large
            case .large: .peek
            }
        }
    }
}

/// "Tiếp theo: Owariya · 850 m · 12 phút", or the day when there is no position.
private struct MapPanelHeader: View {
    @Environment(AppModel.self) private var model
    let day: Day

    private var nextPlace: Place? {
        guard model.today?.key == day.key, let next = model.next else { return nil }
        return model.store.place(next.placeID)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let place = nextPlace, let here = model.position {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tiếp theo").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(place.name).font(.headline).lineLimit(1)
                    Text("\(Fmt.km(Geo.km(here, place.coordinate))) · \(Fmt.duration(PlanEngine.directWalk(here, place.coordinate, pace: model.pace.factor)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button {
                    model.walk(to: place.id)
                } label: {
                    Label("Đi bộ", systemImage: "figure.walk")
                        .frame(minHeight: 30)
                }
                // the panel is glass already: a solid button, not glass on glass
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ngày \(day.n) · \(day.title)").font(.headline).lineLimit(1)
                    Text(day.route).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Around you, nearest first; the day's stops when there is no position yet.
private struct MapPanelList: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @Binding var selected: String?
    let onPick: (String) -> Void

    private var nearby: [NearbyItem] {
        guard let here = model.position else { return [] }
        return Nearby.around(here, day: day, store: model.store, done: Set(model.marked(day).keys), pace: model.pace.factor)
    }

    private var stops: [Place] {
        var seen = Set<String>()
        return day.stops.compactMap { _, s in
            guard let p = model.store.place(s.place), p.kind != .station, seen.insert(p.id).inserted else { return nil }
            return p
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if let id = selected, let p = model.store.place(id), !nearby.contains(where: { $0.place.id == id }) {
                        MapPlaceRow(place: p, detail: p.dish ?? p.ja, isSelected: true, onPick: onPick)
                            .id(id)
                        Divider().padding(.vertical, 4)
                    }
                    if model.position != nil {
                        Text("Gần đây")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                        ForEach(nearby) { n in
                            MapPlaceRow(place: n.place, detail: detail(n), isSelected: selected == n.place.id, planned: n.planIndex != nil, onPick: onPick)
                                .id(n.place.id)
                        }
                    } else {
                        if !model.location.isAllowed {
                            Button {
                                model.location.requestWhenInUse()
                            } label: {
                                Label("Bật vị trí để thấy khoảng cách", systemImage: "location")
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                            .padding(.bottom, 8)
                        }
                        ForEach(stops) { p in
                            MapPlaceRow(place: p, detail: p.dish ?? p.ja, isSelected: selected == p.id, planned: true, onPick: onPick)
                                .id(p.id)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selected) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    /// "850 m · 12 phút · rẽ 6 phút"
    private func detail(_ n: NearbyItem) -> String {
        var parts = [Fmt.km(n.km), Fmt.duration(n.minutes)]
        if let d = n.along?.detour, d.min > 0 {
            parts.append(d.mode == "car" ? "xe \(d.min) phút" : "rẽ \(d.min) phút")
        }
        return parts.joined(separator: " · ")
    }
}

private struct MapPlaceRow: View {
    @Environment(AppModel.self) private var model
    let place: Place
    let detail: String?
    let isSelected: Bool
    var planned = false
    let onPick: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                onPick(place.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: place.snack != nil ? "takeoutbag.and.cup.and.straw.fill" : place.kind.symbol)
                        .font(.subheadline)
                        .foregroundStyle(planned ? Color.accentColor : .orange)
                        .frame(width: 36, height: 36)
                        .background(.fill.tertiary, in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(place.name).font(.body.weight(.semibold)).lineLimit(1)
                        if let detail {
                            Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                        }
                    }
                    Spacer(minLength: 0)
                    if planned {
                        Tag(text: "Trong lịch", tint: .accentColor)
                    }
                }
                .frame(minHeight: 48)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isSelected {
                HStack(spacing: 10) {
                    Button {
                        model.walk(to: place.id)
                    } label: {
                        Label("Đi bộ", systemImage: "figure.walk").frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        model.sheet = .place(place.id)
                    } label: {
                        Label("Chi tiết", systemImage: "info.circle").frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.leading, 48)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(isSelected ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 16, style: .continuous))
    }
}

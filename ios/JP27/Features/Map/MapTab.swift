import SwiftUI
import TripKit

/// The day on the map, read like the web's day page: the panel holds the day's timeline, and the
/// map follows whatever the timeline is on. A move fits its leg and dims the rest; a stop is
/// flown to, with the places one could turn off for around it (from the data) named on the map
/// and listed under it. Tapping one of those draws the way there, for as long as that stop is the
/// one being read. Past the end of a day, a further pull goes on to the next.
///
/// The panel is drawn in the tab, not presented as a sheet: a sheet would cover the tab bar and
/// block the app's own sheets (place, ride, expense) from presenting while the map is open.
struct MapTab: View {
    @Environment(AppModel.self) private var model
    @State private var dayKey: String?
    @State private var stage: MapPanelStage = .medium
    @State private var header: CGFloat = 132
    /// the item of the day the timeline is on (a stop or a move), by index
    @State private var active: Int?
    /// a place tapped off the plan: shown with the way to it from the stop being read
    @State private var side: String?
    @State private var camera: TripMapCamera?
    @State private var cameraSeq = 0
    @State private var jump: MapJump?
    /// when the person last moved the map (leave it where they put it for a few seconds), kept
    /// out of the view's state so a pan does not redraw the tab
    @State private var touch = MapTouch()
    @State private var cache = MapSidesCache()
    /// choices made by hand (a stop, a place off the plan, a day); the map also changes them by
    /// itself as the list scrolls, at midnight and when another page sends it somewhere, quietly
    @State private var picks = 0
    /// a place's card opened from the map: a stop already on show, tapped again
    @State private var opened = 0
    /// Settings › Chẩn đoán: with the frame readings on, the overlays can be drawn without glass
    @AppStorage(MapPacer.readingsKey) private var readings = false
    @AppStorage(MapPacer.glassKey) private var glass = true

    private var day: Day { dayKey.flatMap { model.store.day($0) } ?? model.focusDay }

    var body: some View {
        let day = self.day
        let sides = cache.sides(for: day, store: model.store, pace: model.pace.factor)
        GeometryReader { geo in
            let safe = geo.safeAreaInsets
            let panel = stage.height(in: geo.size.height, header: header)
            // the map's clear area is fixed at the middle height: moving the panel moves nothing
            // in the map, so a drag or a snap costs the map no work at all
            let clear = MapPanelStage.medium.height(in: geo.size.height, header: header)
            ZStack(alignment: .bottom) {
                TripMap(
                    content: content(day, sides: sides),
                    insets: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 64),
                    frameID: day.key,
                    chrome: UIEdgeInsets(top: safe.top + MapDayStrip.height + 8, left: 0, bottom: safe.bottom + clear + 6, right: 0),
                    camera: camera,
                    onSelect: { tapped($0, day: day, sides: sides) },
                    onUserMove: { [touch] in touch.movedAt = .now }
                )
                .ignoresSafeArea()

                if let id = side, let place = model.store.place(id), stage != .large {
                    MapSideCard(place: place, side: anchor(day).flatMap { a in sides[a]?.first { $0.id == id } }, from: anchorPlace(day)) {
                        withAnimation(.snappy) { side = nil }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, panel + 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(id)
                }

                MapPanel(stage: $stage, containerHeight: geo.size.height, headerHeight: $header) {
                    MapPanelTitle(day: day)
                } strip: {
                    MapStopStrip(day: day, active: active) { i in select(i, day: day, scroll: true, from: "map.stop.\(i)") }
                } content: {
                    MapTimeline(
                        day: day,
                        sides: sides,
                        active: active,
                        side: side,
                        bottomMargin: MapPanelStage.large.height(in: geo.size.height, header: header) - panel + 16,
                        window: max(0, panel - header),
                        jump: jump,
                        stage: stage,
                        next: nextDay(after: day),
                        onRead: { read($0, day: day) },
                        // a tapped row comes under the reading line too, so a scroll reads on from it
                        onTap: { select($0, day: day, scroll: true, from: "map.row.\($0)") },
                        onOpen: { _ = openCard($0, day: day, from: "map.row.\($0)") },
                        onSide: { pickSide($0, day: day, sides: sides) },
                        onPullDown: { withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { stage = .peek } },
                        // pulled past the end, the pull already ticked as it armed
                        onNextDay: { pulled in if let n = nextDay(after: day) { choose(n.key, byHand: !pulled) } }
                    )
                    .id(day.key)
                }
            }
            .overlay(alignment: .top) {
                MapDayStrip(current: day.key, choose: { choose($0, byHand: true) })
                    .padding(.top, 4)
            }
            .overlay(alignment: .topTrailing) {
                MapControls(
                    locate: locate,
                    fuji: { model.present(.fujiFinder, from: "map.fuji") },
                    frameDay: { frameDay(day) }
                )
                .padding(.top, MapDayStrip.height + 16)
                .padding(.trailing, 12)
                .opacity(stage == .large ? 0 : 1)
            }
            .environment(\.mapGlass, glass || !readings)
        }
        .onAppear {
            consumeDay()
            consumeFocus()
            followToday()
        }
        .onChange(of: model.mapFocus) { consumeFocus() }
        // the map does not follow the list behind a full panel; it catches up once the panel is
        // down and has settled
        .onChange(of: stage) { old, new in
            guard old == .large, new != .large else { return }
            let day = self.day
            Task {
                try? await Task.sleep(for: .milliseconds(380))
                fly(day, to: active, force: false)
            }
        }
        .onChange(of: model.mapDay) { consumeDay() }
        .sensoryFeedback(.pick, trigger: picks)
        .sensoryFeedback(.press, trigger: opened)
    }

    // MARK: What the map draws

    private func content(_ day: Day, sides: [Int: [MapSide]]) -> MapContent {
        var c = MapContent.day(day, model: model, along: false)
        if let i = active, day.items.indices.contains(i), case .move(let m) = day.items[i] {
            c.focus = m.leg.id
        }
        let from = anchorPlace(day)
        if let a = anchor(day), let place = from {
            c.pins.insert(MapPin(id: "halo-\(place.id)", coordinate: place.coordinate, kind: .halo), at: 0)
            for s in sides[a] ?? [] {
                c.pins.append(MapPin(id: s.id, coordinate: s.place.coordinate, kind: s.isFood ? .snack : .along, label: s.place.name, titled: true))
            }
        }
        if let id = side, let p = model.store.place(id) {
            c.pins.insert(MapPin(id: "halo-\(id)", coordinate: p.coordinate, kind: .halo), at: 0)
            if !c.pins.contains(where: { $0.id == id }) {
                c.pins.append(MapPin(id: id, coordinate: p.coordinate, kind: p.kind == .food ? .snack : .along, label: p.name, titled: true))
            }
            if let from, from.id != id {
                let s = anchor(day).flatMap { a in sides[a]?.first { $0.id == id } }
                c.routes.append(MapGuide.way(from: from, to: p, along: s?.along))
            }
        }
        return c
    }

    /// The stop whose surroundings are shown: the stop being read, or the one a move leads to.
    private func anchor(_ day: Day) -> Int? {
        guard let i = active, day.items.indices.contains(i) else { return nil }
        if case .stop = day.items[i] { return i }
        return day.stops.first { $0.index > i }?.index
    }

    private func anchorPlace(_ day: Day) -> Place? {
        anchor(day).flatMap { model.store.place(day.items[$0].stop?.place) }
    }

    // MARK: Following the timeline

    /// The reading line moved onto another item: show it, and drop the way to a place off the
    /// plan that belonged to the stop before.
    private func read(_ i: Int?, day: Day) {
        guard i != active else { return }
        withAnimation(.smooth(duration: 0.25)) {
            active = i
            side = nil
        }
        if stage != .large { fly(day, to: i, force: false) }
    }

    /// A stop, its row or its pin tapped by hand. The one already on show opens its card (the place
    /// page, as a day's page opens it), growing out of what was tapped; any other is shown.
    private func select(_ i: Int, day: Day, scroll: Bool, from source: String) {
        if i == active, openCard(i, day: day, from: source) { return }
        activate(i, day: day, scroll: scroll, byHand: true)
    }

    /// Opens the card of the stop at `i`; false when it is not a stop with a page.
    private func openCard(_ i: Int, day: Day, from source: String) -> Bool {
        guard day.items.indices.contains(i), let id = day.items[i].stop?.place, model.store.place(id) != nil else { return false }
        opened += 1
        model.present(.place(id), from: source)
        return true
    }

    /// A row or a stop was tapped: that is a request, so the map moves even if it was just handled.
    private func activate(_ i: Int, day: Day, scroll: Bool, byHand: Bool = false) {
        if byHand, i != active { picks += 1 }
        touch.movedAt = .distantPast
        withAnimation(.smooth(duration: 0.25)) {
            active = i
            side = nil
            if scroll { jump = MapJump(seq: (jump?.seq ?? 0) + 1, index: i) }
        }
        fly(day, to: i, force: true)
    }

    private func fly(_ day: Day, to i: Int?, force: Bool) {
        guard force || Date.now.timeIntervalSince(touch.movedAt) > 4 else { return }
        guard let i, day.items.indices.contains(i) else {
            move(.fit(MapContent.day(day, model: model, along: false).outline))
            return
        }
        switch day.items[i] {
        case .move(let m):
            var pts = model.store.path(m.leg.id)
            if pts.count < 2 { pts = [m.leg.from, m.leg.to].compactMap { model.store.place($0)?.coordinate } }
            move(.fit(pts))
        case .stop(let s):
            guard let p = model.store.place(s.place) else { return }
            move(.center(p.coordinate, zoom: 15.5))
        }
    }

    private func move(_ m: TripMapCamera.Move) {
        cameraSeq += 1
        camera = TripMapCamera(id: cameraSeq, move: m)
    }

    // MARK: Side trips

    private func pickSide(_ id: String, day: Day, sides: [Int: [MapSide]]) {
        // choosing one ticks; tapping the chosen one again to let it go does not
        if side != id { picks += 1 }
        withAnimation(.snappy) {
            side = side == id ? nil : id
            if stage == .large { stage = .medium }
        }
        showSide(day)
    }

    /// The stop and the place off the plan, and the way between, in view.
    private func showSide(_ day: Day) {
        guard let id = side, let p = model.store.place(id) else { return }
        touch.movedAt = .distantPast
        if let from = anchorPlace(day), from.id != id {
            move(.fit([from.coordinate, p.coordinate]))
        } else {
            move(.center(p.coordinate, zoom: 16))
        }
    }

    private func tapped(_ id: String, day: Day, sides: [Int: [MapSide]]) {
        if let i = day.stops.first(where: { $0.stop.place == id })?.index {
            // the card grows out of the stop's chip, which the strip keeps in view
            select(i, day: day, scroll: true, from: "map.stop.\(i)")
            return
        }
        pickSide(id, day: day, sides: sides)
    }

    // MARK: Days

    private func choose(_ key: String, byHand: Bool = false) {
        guard key != day.key else { return }
        if byHand { picks += 1 }
        withAnimation(.smooth(duration: 0.3)) {
            dayKey = key
            active = nil
            side = nil
            jump = nil
        }
        // the map frames the new day itself (its frameID is the day)
        touch.movedAt = .distantPast
    }

    private func nextDay(after day: Day) -> Day? {
        if let i = model.days.firstIndex(where: { $0.key == day.key }) {
            return model.days.indices.contains(i + 1) ? model.days[i + 1] : nil
        }
        // an alternative day goes on to the day after the one it replaces
        let n = day.replaces ?? day.n
        return model.days.first { $0.n > n }
    }

    private func frameDay(_ day: Day) {
        withAnimation(.snappy) {
            active = nil
            side = nil
        }
        touch.movedAt = .distantPast
        move(.fit(MapContent.day(day, model: model, along: false).outline))
    }

    private func locate() {
        guard let p = model.position else {
            model.location.requestWhenInUse()
            return
        }
        touch.movedAt = .now
        move(.center(p, zoom: 15.5))
    }

    /// On the day itself, open on the next stop.
    private func followToday() {
        guard dayKey == nil || dayKey == model.today?.key, let today = model.today, let next = model.next,
              today.items.indices.contains(next.index) else { return }
        dayKey = today.key
        activate(next.index, day: today, scroll: true)
    }

    /// A day page asked for its map.
    private func consumeDay() {
        guard let key = model.mapDay else { return }
        model.mapDay = nil
        if key != day.key { choose(key) }
    }

    /// A place page asked to be shown on the map: its stop if the day has it, else the place alone.
    private func consumeFocus() {
        guard let id = model.mapFocus else { return }
        model.mapFocus = nil
        let day = self.day
        if let i = day.stops.first(where: { $0.stop.place == id })?.index {
            activate(i, day: day, scroll: true)
        } else if model.store.place(id) != nil {
            withAnimation(.snappy) { side = id }
            showSide(day)
        }
    }
}

/// When the map was last moved by hand.
final class MapTouch {
    var movedAt = Date.distantPast
}

/// The side trips of the day on show, worked out once per day rather than on every redraw.
final class MapSidesCache {
    private var key = ""
    private var pace = 0.0
    private var value: [Int: [MapSide]] = [:]

    func sides(for day: Day, store: TripStore, pace: Double) -> [Int: [MapSide]] {
        if key != day.key || self.pace != pace {
            key = day.key
            self.pace = pace
            value = MapGuide.sides(for: day, store: store, pace: pace)
        }
        return value
    }
}

/// Scroll the timeline to an item; a new seq scrolls again to the same one.
struct MapJump: Equatable {
    let seq: Int
    let index: Int
}

// MARK: - Side trips from the data

/// A place off the plan beside a stop of the day.
struct MapSide: Identifiable {
    var id: String { place.id }
    let place: Place
    /// straight line from the stop
    let km: Double
    /// on foot from the stop, or research's own detour time
    let minutes: Int
    let along: Along?

    var isFood: Bool { place.kind == .food || place.snack != nil }
}

enum MapGuide {
    /// The places one could turn off for, given to the stop of the day each is nearest: the day's
    /// researched side trips, the snack stops research put beside a plan place, and any place in
    /// the data no day has planned, a short walk from a stop. Nearest first, a handful per stop.
    static func sides(for day: Day, store: TripStore, pace: Double) -> [Int: [MapSide]] {
        let anchors: [(index: Int, place: Place)] = day.stops.compactMap { i, s in store.place(s.place).map { (i, $0) } }
        guard !anchors.isEmpty else { return [:] }
        let planned = Set(anchors.map { $0.place.id })
        var alongs: [String: Along] = [:]
        for a in day.along where alongs[a.place] == nil { alongs[a.place] = a }

        var seen = planned
        var pool: [Place] = []
        for a in day.along {
            if let p = store.place(a.place), seen.insert(p.id).inserted { pool.append(p) }
        }
        for p in store.trip.places where p.kind != .station && p.kind != .stay && !seen.contains(p.id) {
            let tied = p.near.map(planned.contains) ?? false
            guard tied || (p.uses.isEmpty && p.role != "alt") else { continue }
            seen.insert(p.id)
            pool.append(p)
        }

        var out: [Int: [MapSide]] = [:]
        for p in pool {
            let anchor = p.near.flatMap { near in anchors.first { $0.place.id == near } }
                ?? anchors.min { Geo.km($0.place.coordinate, p.coordinate) < Geo.km($1.place.coordinate, p.coordinate) }
            guard let anchor else { continue }
            let km = Geo.km(anchor.place.coordinate, p.coordinate)
            let along = alongs[p.id]
            // researched side trips may sit a little further out; anything else, a short walk
            guard km <= (along != nil || p.near != nil ? 2.5 : 0.8) else { continue }
            let walk = Int(PlanEngine.directWalk(anchor.place.coordinate, p.coordinate, pace: pace).rounded())
            out[anchor.index, default: []].append(MapSide(place: p, km: km, minutes: along?.detour?.min ?? p.detourMin ?? max(1, walk), along: along))
        }
        for (k, list) in out {
            out[k] = Array(list.sorted { $0.km < $1.km }.prefix(6))
        }
        return out
    }

    /// The way from a stop to a place off the plan: research's own detour line when it has one,
    /// else a straight dashed line.
    static func way(from: Place, to: Place, along: Along?) -> MapRoute {
        var pts = along?.detour?.p.map { Polyline.decode($0) } ?? []
        if pts.count < 2 { pts = [from.coordinate, to.coordinate] }
        return MapRoute(id: "side-\(to.id)", points: pts, color: "#E07A2F", width: 4, dashed: true, dims: false)
    }
}

// MARK: - Glass over the map

private nonisolated struct MapGlassKey: EnvironmentKey {
    static var defaultValue: Bool { true }
}

extension EnvironmentValues {
    /// Whether the panel, the day strip and the buttons over the map are glass (always, unless the
    /// frame readings are on and Settings › Chẩn đoán › Kính trên bản đồ is off).
    nonisolated var mapGlass: Bool {
        get { self[MapGlassKey.self] }
        set { self[MapGlassKey.self] = newValue }
    }
}

private extension View {
    /// Glass over the map. Glass shows the map under it, so the system draws it again from the map
    /// on each of the map's frames; the plain fill (for measuring what that costs) does not.
    func mapGlass(_ glass: Glass, plain: Color? = nil, in shape: some Shape) -> some View {
        modifier(MapGlass(glass: glass, plain: plain, shape: shape))
    }
}

private struct MapGlass<S: Shape>: ViewModifier {
    @Environment(\.mapGlass) private var on
    let glass: Glass
    let plain: Color?
    let shape: S

    func body(content: Content) -> some View {
        if on {
            content.glassEffect(glass, in: shape)
        } else {
            content.background(plain ?? Palette.card, in: shape)
        }
    }
}

// MARK: - Days, as a strip to slide

/// The trip's days as a strip of glass pills over the map, the chosen one red and named.
/// Slides sideways; a tap chooses; the chosen day stays centred.
private struct MapDayStrip: View {
    @Environment(AppModel.self) private var model
    let current: String
    let choose: (String) -> Void

    static let height: CGFloat = 44

    var body: some View {
        let alternatives = model.store.trip.altDays.filter { alt in !model.days.contains { $0.key == alt.key } }
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 2) {
                    HStack(spacing: 8) {
                        ForEach(model.days) { d in
                            pill(d, alternative: false)
                        }
                        ForEach(alternatives) { d in
                            pill(d, alternative: true)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 12, for: .scrollContent)
            .frame(height: Self.height)
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: current) { _, key in
                withAnimation(.smooth) { proxy.scrollTo(key, anchor: .center) }
            }
        }
    }

    private func pill(_ d: Day, alternative: Bool) -> some View {
        let on = d.key == current
        return Button {
            choose(d.key)
        } label: {
            HStack(spacing: 6) {
                if alternative {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption.weight(.bold))
                    Text(d.title).lineLimit(1)
                } else {
                    Text("\(d.n)")
                        .fontWeight(.heavy)
                        .fontDesign(.rounded)
                        .monospacedDigit()
                    if on {
                        Text(d.title)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .frame(maxWidth: 190, alignment: .leading)
                    } else {
                        Text(Fmt.shortDate(d.date))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .font(.subheadline)
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .mapGlass(on ? .regular.tint(Palette.sun).interactive() : .regular.interactive(), plain: on ? Palette.sun : nil, in: .capsule)
        .id(d.key)
        .accessibilityLabel(alternative ? "Phương án: \(d.title)" : "Ngày \(d.n), \(d.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
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
                    .sheetSource("map.fuji")
                Divider().frame(width: 26)
                button("arrow.up.left.and.arrow.down.right", "Cả ngày", frameDay)
            }
            .mapGlass(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
        }
    }

    private func button(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 46, height: 46)
                .contentShape(.rect)
        }
        .buttonStyle(.pressable(.plain))
        .accessibilityLabel(label)
    }
}

// MARK: - Panel

enum MapPanelStage: CaseIterable {
    case peek, medium, large

    /// peek is the header alone: the day and its stops in a row
    func height(in container: CGFloat, header: CGFloat) -> CGFloat {
        switch self {
        case .peek: header + 4
        case .medium: max(header + 200, container * 0.5)
        case .large: max(header + 240, container - MapDayStrip.height - 16)
        }
    }
}

/// A floating glass panel that snaps to three heights. Its content is laid out once at the
/// tallest height and the panel clips it, so a drag only moves an edge: nothing inside is laid
/// out again under the finger. Release velocity is projected so a flick lands where it heads, and
/// carried into the spring, so the panel goes on at the finger's speed.
/// The grabber and title drag it; the strip under them scrolls sideways on its own.
///
/// As a sheet does (WWDC25, Build a SwiftUI app with the new design): glass and inset from the
/// screen's sides while it leaves the map in view, turning opaque and meeting the sides as it rises
/// to full height, where the map behind is no longer the subject.
private struct MapPanel<Title: View, Strip: View, Content: View>: View {
    @Binding var stage: MapPanelStage
    let containerHeight: CGFloat
    @Binding var headerHeight: CGFloat
    let title: Title
    let strip: Strip
    let content: Content
    /// how far the finger has moved the panel off its height. Put back to 0 in the same animation
    /// that moves the panel to its new height: a gesture state is reset in a transaction of its
    /// own, without the animation, and the panel jumped back to its old height for a frame before
    /// it went on to the new one (seen in a screen recording of a fold).
    @State private var drag: CGFloat = 0
    /// a finger is on the grabber; a drag the system cancels (no onEnded) is put back from it
    @GestureState private var dragging = false
    /// let go or tapped into another height; a drag that falls back where it was stays quiet
    @State private var settled = 0

    private static var snap: Animation { .spring(response: 0.38, dampingFraction: 0.86) }

    init(stage: Binding<MapPanelStage>, containerHeight: CGFloat, headerHeight: Binding<CGFloat>,
         @ViewBuilder title: () -> Title, @ViewBuilder strip: () -> Strip, @ViewBuilder content: () -> Content) {
        _stage = stage
        self.containerHeight = containerHeight
        _headerHeight = headerHeight
        self.title = title()
        self.strip = strip()
        self.content = content()
    }

    private func height(_ s: MapPanelStage) -> CGFloat { s.height(in: containerHeight, header: headerHeight) }

    var body: some View {
        let shown = currentHeight
        let solid = solidity(at: shown)
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                VStack(spacing: 6) {
                    Capsule()
                        .fill(.secondary.opacity(0.45))
                        .frame(width: 36, height: 5)
                        .padding(.top, 8)
                    title
                        .padding(.horizontal, 18)
                }
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
                .onTapGesture(perform: cycle)
                .gesture(dragGesture)
                strip
            }
            .padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityAction(named: stage == .large ? "Thu gọn" : "Mở rộng") { cycle() }

            content
                .frame(height: max(0, height(.large) - headerHeight), alignment: .top)
                .opacity(stage == .peek && drag > -20 ? 0 : 1)
        }
        .frame(height: shown, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Palette.card.opacity(solid))
        .clipShape(.rect(cornerRadius: 30, style: .continuous))
        .mapGlass(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .padding(.horizontal, 8 * (1 - solid))
        .padding(.bottom, 6)
        .animation(.smooth(duration: 0.2), value: stage == .peek && drag > -20)
        .sensoryFeedback(.snap, trigger: settled)
        .onChange(of: dragging) { _, on in
            guard !on, drag != 0 else { return }
            withAnimation(Self.snap) { drag = 0 }
        }
    }

    /// 0 (glass) up to the middle height, 1 (opaque) at full height, eased in between.
    private func solidity(at height: CGFloat) -> CGFloat {
        let from = self.height(.medium), to = self.height(.large)
        guard to > from else { return 0 }
        let t = min(max((height - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private var currentHeight: CGFloat {
        let lowest = height(.peek)
        let highest = height(.large)
        let raw = height(stage) - drag
        // soft limits: resist more the further past them
        if raw > highest { return highest + rubber(raw - highest) }
        if raw < lowest { return lowest - rubber(lowest - raw) }
        return raw
    }

    private func rubber(_ overshoot: CGFloat, dimension: CGFloat = 300, constant: CGFloat = 0.55) -> CGFloat {
        (overshoot * dimension * constant) / (dimension + constant * overshoot)
    }

    /// Measured on the screen, not on the grabber: the grabber rides the panel's top edge, so in
    /// its own space every frame the panel follows the finger takes back the translation that
    /// moved it, and the panel shakes between the two heights for as long as the drag lasts.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($dragging) { _, state, _ in state = true }
            .onChanged { value in drag = value.translation.height }
            .onEnded { value in
                let projected = height(stage) - value.predictedEndTranslation.height
                let target = MapPanelStage.allCases.min {
                    abs(height($0) - projected) < abs(height($1) - projected)
                } ?? stage
                if target != stage { settled += 1 }
                // the finger's speed, as a share of the way left per second (a spring's unit)
                let left = height(target) - currentHeight
                let speed = abs(left) > 1 ? -value.velocity.height / left : 0
                withAnimation(.interpolatingSpring(duration: 0.38, bounce: 0.1, initialVelocity: min(max(speed, -12), 12))) {
                    stage = target
                    drag = 0
                }
            }
    }

    private func cycle() {
        settled += 1
        withAnimation(Self.snap) {
            stage = switch stage {
            case .peek: .medium
            case .medium: .large
            case .large: .peek
            }
        }
    }
}

/// The day in a line, or on the day itself the next place and the way to it.
private struct MapPanelTitle: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @State private var walked = 0

    /// on the day and in its part of Japan: the next place, how far
    private var nextPlace: Place? {
        guard model.today?.key == day.key, let next = model.next, let p = model.store.place(next.placeID),
              let here = model.position, Geo.km(here, p.coordinate) < 30 else { return nil }
        return p
    }

    private var stopCount: Int {
        day.stops.filter { model.store.place($0.stop.place).map { $0.kind != .station } ?? false }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            if let place = nextPlace, let here = model.position {
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(.headline).lineLimit(1)
                    Text("\(Fmt.km(Geo.km(here, place.coordinate))) · \(Fmt.duration(PlanEngine.directWalk(here, place.coordinate, pace: model.pace.factor)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                Button {
                    walked += 1
                    model.walk(to: place.id)
                } label: {
                    Label("Đi bộ", systemImage: "figure.walk")
                }
                // the panel is glass already: a solid button, not glass on glass
                .buttonStyle(.borderedProminent)
                .sensoryFeedback(.press, trigger: walked)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(day.title).font(.headline).lineLimit(1)
                    Text("\(day.dow), \(Fmt.shortDate(day.date)) · \(model.doneCount(day))/\(stopCount) điểm")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        }
    }
}

private struct MapStop: Identifiable {
    let index: Int
    let place: Place
    var id: Int { index }
}

/// The day's stops in a row: done ones ticked, the next one ringed, the one the map is on lit.
/// Tapping a stop goes to it; tapping the one on show opens its card, which its chevron says. This
/// is what the panel shows when it is down.
private struct MapStopStrip: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let active: Int?
    let pick: (Int) -> Void

    private var stops: [MapStop] {
        day.stops.compactMap { i, s in
            guard let p = model.store.place(s.place), p.kind != .station else { return nil }
            return MapStop(index: i, place: p)
        }
    }

    var body: some View {
        let stops = self.stops
        let live = model.today?.key == day.key
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(stops) { stop in
                        if stop.index != stops.first?.index {
                            Capsule().fill(.secondary.opacity(0.3)).frame(width: 8, height: 2)
                        }
                        chip(stop, live: live)
                            .id(stop.index)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 14, for: .scrollContent)
            .onChange(of: active) { _, i in
                guard let i else { return }
                let target = stops.last { $0.index <= i }?.index ?? stops.first?.index
                withAnimation(.smooth) { proxy.scrollTo(target, anchor: .center) }
            }
        }
    }

    private func chip(_ stop: MapStop, live: Bool) -> some View {
        let index = stop.index
        let place = stop.place
        let done = model.isDone(day, index)
        let next = live && model.next?.index == index
        let lit = active.map { a in a == index || (day.items[a].move != nil && day.stops.first { $0.index > a }?.index == index) } ?? false
        // on show itself, not only lit as the end of the way being read: a tap opens it
        let opens = active == index
        return Button {
            pick(index)
        } label: {
            HStack(spacing: 6) {
                Group {
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
                    } else {
                        Text("\(day.items[index].stop?.n ?? 0)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(done ? Palette.sun : place.kind.tint, in: .circle)
                .overlay {
                    if next {
                        Circle().strokeBorder(Palette.sun, lineWidth: 2).padding(-3)
                    }
                }
                Text(place.name)
                    .font(.caption.weight(lit ? .semibold : .regular))
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
                    .foregroundStyle(done && !lit ? Color.secondary : Color.primary)
                if opens {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 10)
            .frame(height: 30)
            .background(lit ? AnyShapeStyle(Palette.sun.opacity(0.14)) : AnyShapeStyle(.clear), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // the card grows out of the chip, from a tap on it or on the stop's pin
        .sheetSource("map.stop.\(index)")
        .accessibilityLabel(place.name)
        .accessibilityValue(done ? "Đã ghé" : next ? "Tiếp theo" : "")
        .accessibilityHint(opens ? "Mở thẻ địa điểm" : "")
    }
}

// MARK: - The timeline that drives the map

/// The day's items with the rail, as in Lịch trình, each stop with its side trips under it. A line
/// across the middle of the part of the list the panel shows decides which item the map shows (it
/// slides to the ends at the ends, so the first and last items can be reached). A row or a stop
/// tapped is brought under that line, so the next scroll reads on from it.
private struct MapTimeline: View {
    let day: Day
    let sides: [Int: [MapSide]]
    let active: Int?
    let side: String?
    let bottomMargin: CGFloat
    /// how much of the list the panel shows at its height. The list is laid out at the panel's
    /// full height and clipped, so the scroll view's own size, less its insets, is not what is seen
    /// (the insets can also take the safe area the clipped part reaches into); the line once read
    /// from them sat at most about 70 pt under the top edge at the middle height.
    let window: CGFloat
    let jump: MapJump?
    let stage: MapPanelStage
    let next: Day?
    let onRead: (Int?) -> Void
    let onTap: (Int) -> Void
    /// a stop's card, straight away (VoiceOver's Chi tiết)
    let onOpen: (Int) -> Void
    let onSide: (String) -> Void
    let onPullDown: () -> Void
    /// true when the list was pulled past its end, false when the footer was tapped
    let onNextDay: (_ pulled: Bool) -> Void

    @State private var frames = RowFrames()
    @State private var armed = false
    /// set only to bring a row under the line; the list scrolls by hand as before
    @State private var position = ScrollPosition(edge: .top)

    private nonisolated static let space = "map.timeline"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(day.items.indices, id: \.self) { i in
                        ItemRow(day: day, index: i, below: chips(i))
                            .padding(.horizontal, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Palette.sun.opacity(active == i ? 0.09 : 0))
                                    .padding(.horizontal, 6)
                            }
                            .contentShape(.rect)
                            .onTapGesture { onTap(i) }
                            // a stop on show, tapped again, opens its card out of its row
                            .sheetSource("map.row.\(i)")
                            .accessibilityActions {
                                if day.items[i].stop?.place != nil {
                                    Button("Chi tiết") { onOpen(i) }
                                }
                            }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames.rows[i] = $0 }
                            .id(i)
                    }
                    if let next {
                        footer(next)
                    }
                }
                .padding(.bottom, 8)
                .coordinateSpace(.named(Self.space))
            }
            .scrollIndicators(.hidden)
            .contentMargins(.bottom, bottomMargin, for: .scrollContent)
            .scrollPosition($position)
            // the window comes with the margins: both change with the panel's height, in one update
            .onScrollGeometryChange(for: MapReading.self) { [window] in MapReading($0, window: window) } action: { _, r in reading(r) }
            .onScrollPhaseChange { old, new in
                frames.touching = new == .tracking || new == .interacting
                guard old == .interacting, new != .interacting else { return }
                released()
            }
            .onChange(of: jump) { _, j in
                guard let j else { return }
                frames.pausedUntil = .now.addingTimeInterval(0.7)
                bring(j.index, proxy: proxy, animated: true)
            }
            .onAppear {
                guard let j = jump else { return }
                // after the first layout, once the rows have been measured
                Task { bring(j.index, proxy: proxy, animated: false) }
            }
            // the visible part changes while the panel moves; the reading waits for it to settle
            .onChange(of: stage) {
                frames.pausedUntil = .now.addingTimeInterval(0.5)
            }
            // felt only under the finger: a fling that bounces past the end arms it too
            .sensoryFeedback(.snap, trigger: armed) { [frames] _, on in on && frames.touching }
        }
    }

    /// Scrolls so the reading line falls inside row `i`, where the next scroll reads on from it.
    /// Before the rows are measured, its top goes to the top.
    private func bring(_ i: Int, proxy: ScrollViewProxy, animated: Bool) {
        guard let row = frames.rows[i] else {
            if animated {
                withAnimation(.smooth(duration: 0.45)) { proxy.scrollTo(i, anchor: .top) }
            } else {
                proxy.scrollTo(i, anchor: .top)
            }
            return
        }
        let y = MapReading.offset(reading: row, window: window, end: frames.end, height: frames.height)
        if animated {
            withAnimation(.smooth(duration: 0.45)) { position.scrollTo(y: y) }
        } else {
            position.scrollTo(y: y)
        }
    }

    private func chips(_ i: Int) -> AnyView? {
        guard let list = sides[i], !list.isEmpty else { return nil }
        return AnyView(MapSideChips(sides: list, selected: active == i || isAnchor(i) ? side : nil, pick: onSide))
    }

    private func isAnchor(_ i: Int) -> Bool {
        guard let a = active, day.items.indices.contains(a), day.items[a].move != nil else { return false }
        return day.stops.first { $0.index > a }?.index == i
    }

    /// The end of the day; pulled past, it goes on to the next.
    private func footer(_ next: Day) -> some View {
        Button { onNextDay(false) } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(armed ? .white : Palette.sun)
                    .frame(width: 32, height: 32)
                    .background(armed ? AnyShapeStyle(Palette.sun) : AnyShapeStyle(Palette.sun.opacity(0.12)), in: .circle)
                    .rotationEffect(.degrees(armed ? 180 : 0))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Ngày \(next.n)").font(.subheadline.weight(.semibold))
                    Text(next.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: armed)
        .accessibilityLabel("Sang ngày \(next.n), \(next.title)")
    }

    private func reading(_ r: MapReading) {
        // each with some way back before it lets go, so a finger resting near the line does not
        // flip it, and the haptic with it, frame after frame
        let isArmed = next != nil && r.over > (armed ? 48 : 64)
        if isArmed != armed { armed = isArmed }
        // pulled down far enough that letting go folds the panel away; kept out of the view's state,
        // since a state read in the body would redraw the whole list each time it flips
        let isPulled = r.top > (frames.pulled ? 56 : 72)
        if isPulled, !frames.pulled, frames.touching { Haptic.snap() }
        frames.pulled = isPulled
        frames.end = r.end
        frames.height = r.height
        guard Date.now >= frames.pausedUntil else { return }
        // at rest at the top the map shows the whole day; the first scroll starts reading
        let i = r.atTop ? nil : frames.item(at: r.line, count: day.items.count)
        guard i != frames.last else { return }
        frames.last = i
        onRead(i)
    }

    private func released() {
        if armed {
            armed = false
            onNextDay(true)
        } else if frames.pulled {
            frames.pulled = false
            onPullDown()
        }
    }
}

/// Where the rows are in the list's content (they move only when the layout does), kept out of
/// the view's state so scrolling does not redraw anything by itself.
private final class RowFrames {
    var rows: [Int: CGRect] = [:]
    var last: Int?
    var pausedUntil = Date.distantPast
    /// a finger on the list
    var touching = false
    /// pulled past the top far enough to fold the panel on letting go
    var pulled = false
    /// how far the list scrolls and how tall its content is, as last read (unknown before the
    /// first scroll: then nothing limits the line)
    var end = CGFloat.greatestFiniteMagnitude
    var height = CGFloat.greatestFiniteMagnitude

    /// the last row starting above the line
    func item(at line: CGFloat, count: Int) -> Int? {
        var found: Int?
        for i in 0..<count {
            guard let f = rows[i] else { continue }
            if f.minY <= line { found = i } else { break }
        }
        return found
    }
}

/// The reading line in content coordinates, and how far the list is pulled past either end.
nonisolated struct MapReading: Equatable {
    var line: CGFloat
    /// past the end of the content
    var over: CGFloat
    /// past the top
    var top: CGFloat
    /// not scrolled at all
    var atTop: Bool
    /// how far the list scrolls, and how tall its content is
    var end: CGFloat
    var height: CGFloat

    /// where the line sits in the window: the middle, the item the eye is on
    static let share: CGFloat = 0.5

    /// `window` is how much of the list the panel shows (`MapTimeline.window`). How far the list
    /// scrolls still comes from the scroll view itself, whatever its insets hold.
    init(_ g: ScrollGeometry, window: CGFloat) {
        let offset = g.contentOffset.y + g.contentInsets.top
        let end = max(0, g.contentSize.height + g.contentInsets.top + g.contentInsets.bottom - g.containerSize.height)
        line = Self.line(at: offset, window: window, end: end, height: g.contentSize.height)
        over = offset - end
        top = -offset
        atTop = offset <= 2
        self.end = end
        height = g.contentSize.height
    }

    /// The line for a scroll offset: the middle of the window; over the first half-window of
    /// scrolling it comes down from the top, over the last it sinks to the bottom, so every item
    /// can come under it. It never moves back as the list scrolls on.
    static func line(at offset: CGFloat, window: CGFloat, end: CGFloat, height: CGFloat) -> CGFloat {
        let w = max(1, window)
        let y = offset + min(max(offset, 0), w * share) + max(0, w * (1 - share) - (end - offset))
        return min(max(y, 0), height)
    }

    /// The offset that puts the line inside `row`: on its middle when it is short, a little under
    /// its top when it is taller than half the window, so its top stays in view.
    static func offset(reading row: CGRect, window: CGFloat, end: CGFloat, height: CGFloat) -> CGFloat {
        let w = max(1, window)
        let target = row.minY + min(row.height / 2, max(8, w * share - 8))
        // the line is never above the offset, so the answer is at most the target
        var lo: CGFloat = 0
        var hi = max(0, min(end, target))
        guard line(at: hi, window: w, end: end, height: height) >= target else { return hi }
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if line(at: mid, window: w, end: end, height: height) >= target { hi = mid } else { lo = mid }
        }
        return hi.rounded()
    }
}

// MARK: - Side trips

/// A stop's side trips as small pills under it: what it is, its name, minutes off the way.
private struct MapSideChips: View {
    let sides: [MapSide]
    let selected: String?
    let pick: (String) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                ForEach(sides) { s in
                    let on = selected == s.id
                    Button {
                        pick(s.id)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: s.place.snack != nil ? "takeoutbag.and.cup.and.straw.fill" : s.place.kind.symbol)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(on ? Color.white : s.place.kind.tint)
                            Text(s.place.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text("\(s.minutes)′")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondary)
                        }
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                        .background(on ? AnyShapeStyle(Place.Kind.food.tint) : AnyShapeStyle(.fill.tertiary), in: .capsule)
                        .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(s.place.name), rẽ \(s.minutes) phút")
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }
}

/// The place off the plan that was tapped, over the panel: how far off the way, and what to do.
private struct MapSideCard: View {
    @Environment(AppModel.self) private var model
    let place: Place
    let side: MapSide?
    let from: Place?
    let close: () -> Void
    /// Maps, the place's page or a new expense opened; closing the card stays quiet
    @State private var opened = 0

    private var detail: String {
        var parts: [String] = []
        if let side, let from {
            parts.append("\(side.minutes) phút từ \(from.name)")
        } else if let here = model.position, Geo.km(here, place.coordinate) < 30 {
            parts.append(Fmt.km(Geo.km(here, place.coordinate)))
        }
        if let d = place.dish ?? place.snack.map({ _ in place.ja ?? "" }), !d.isEmpty { parts.append(d) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                GlyphTile(symbol: place.snack != nil ? "takeoutbag.and.cup.and.straw.fill" : place.kind.symbol, tint: place.kind.tint, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(place.name).font(.headline).lineLimit(1)
                    if !detail.isEmpty {
                        Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(.fill.tertiary, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng")
            }
            HStack(spacing: 8) {
                Button {
                    opened += 1
                    model.walk(to: place.id)
                } label: {
                    Label("Đi bộ", systemImage: "figure.walk").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                Button {
                    opened += 1
                    model.present(.place(place.id), from: "map.side.\(place.id)")
                } label: {
                    Label("Chi tiết", systemImage: "info.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .sheetSource("map.side.\(place.id)")
                Button {
                    opened += 1
                    model.present(.expense(placeID: place.id, yen: nil), from: "map.spend.\(place.id)")
                } label: {
                    Image(systemName: "yensign")
                        .frame(width: 22)
                }
                .buttonStyle(.glass)
                .sheetSource("map.spend.\(place.id)")
                .accessibilityLabel("Ghi khoản chi ở đây")
            }
            .controlSize(.large)
        }
        .padding(14)
        .mapGlass(.regular, in: .rect(cornerRadius: 26, style: .continuous))
        .sensoryFeedback(.press, trigger: opened)
    }
}

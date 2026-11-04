import SwiftData
import SwiftUI
import TripKit
import UIKit

/// The tab opened most. Before the trip it is the trip's cover (TodayHome.swift); during it, what
/// is next, whether you are late, and the rest of today; after it, the journal.
struct TodayTab: View {
    @Environment(AppModel.self) private var model
    @Environment(\.zoomSpace) private var zoomSpace
    /// the home's cover has scrolled away: the wordmark takes its place in the bar
    @State private var coverGone = false

    private var isBefore: Bool {
        if case .before = model.phase { return true }
        return false
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.todayPath) {
            content
                .screen()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(isBefore ? .inline : .large)
                .toolbar {
                    if isBefore {
                        ToolbarItem(placement: .principal) {
                            Wordmark()
                                .opacity(coverGone ? 1 : 0)
                                .animation(.smooth, value: coverGone)
                        }
                    }
                    // Nghe và dịch lives in Sổ tay only; the morph source is the bar item itself,
                    // its glass, not the button
                    SheetToolbarButton(title: "Cài đặt", symbol: "gearshape", source: "today.settings") {
                        model.present(.settings, from: "today.settings")
                    }
                }
                // a day card on the home grows into its day
                .navigationDestination(for: Route.self) { route in
                    RouteHost(route: route)
                        .zoomed(from: homeSource(route), in: zoomSpace)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .before(let days, _):
            // the cover runs under the status bar and the glass buttons
            ScrollView {
                TodayHome(days: days)
            }
            .ignoresSafeArea(edges: .top)
            // the cover brings its own paper mist under the status bar; the system's edge comes
            // back once the cover has scrolled away
            .scrollEdgeEffectHidden(!coverGone, for: .top)
            .onScrollGeometryChange(for: Bool.self) { geo in
                geo.contentOffset.y > 440
            } action: { _, gone in
                coverGone = gone
            }
        case .during(let day):
            ScrollView {
                TodayDuring(day: day)
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 32)
            }
        case .after:
            ScrollView {
                TodayAfter()
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.bottom, 32)
            }
        }
    }

    private var title: String {
        switch model.phase {
        case .before: "Hôm nay"
        case .during(let day): "\(day.dow), \(Fmt.shortDate(day.date))"
        case .after: model.store.trip.meta.title
        }
    }

    private func homeSource(_ route: Route) -> String? {
        guard isBefore, case .day(let key) = route else { return nil }
        return "home.day.\(key)"
    }
}

// MARK: - During a trip day

private struct TodayDuring: View {
    @Environment(AppModel.self) private var model
    let day: Day
    // haptics kept here rather than on their buttons, which leave in the moment they are pressed:
    // the late banner once its stops are dropped, the next card once its last stop is marked
    @State private var dropped = 0
    @State private var arrived = false

    private var fujiSpot: FujiGuide.Spot? {
        let spots = model.guide.fuji.spots.filter { $0.day == day.key }
        return spots.first { $0.role == "planned" && $0.visible } ?? spots.first { $0.visible } ?? spots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            TodayDayHeader(day: day)

            if let plan = model.replan {
                TodayLateBanner(day: day, plan: plan, dropped: $dropped)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !model.location.isAlways {
                TodayAlwaysCard()
            }

            TodayJournalQuestion()

            if let next = model.next {
                TodayNextCard(day: day, next: next, arrived: $arrived)
            } else if model.cursor < day.items.count, model.itinerary.isUntimed(day) {
                // a day with no planned time at all (day 12, the way to the airport), items remaining:
                // the one the day is at, by name. On any other day, nothing timed ahead (the walk back
                // to the hotel) is the day's end
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(untimedTitle(day.items[model.cursor]), systemImage: "arrow.forward.circle.fill")
                            .font(.headline)
                        Text("Không có giờ cố định")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Card {
                    Label("Hết lịch hôm nay", systemImage: "moon.stars.fill")
                        .font(.headline)
                        .symbolRenderingMode(.multicolor)
                }
            }

            if model.minutes(on: day) >= 19 * 60 {
                NavigationLink(value: Route.journal(day.key)) {
                    HStack(spacing: 14) {
                        GlyphTile(symbol: "book.pages.fill", tint: Palette.ai, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Nhật ký hôm nay").font(.headline)
                            Text("\(model.doneCount(day)) điểm đã ghé")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(16)
                    .background(Palette.card, in: .rect(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.pressable)
            }

            if let spot = fujiSpot {
                Card {
                    CloudForecast(title: "Fuji hôm nay", key: spot.id, coordinate: Coordinate(spot.lat, spot.lng))
                }
            }

            TodayTimeline(day: day)
        }
        .animation(.smooth, value: model.replan == nil)
        .sensoryFeedback(.warn, trigger: dropped)
        .sensoryFeedback(.done, trigger: arrived)
    }

    /// A stop's title, or where a move goes and on what ("Đi bộ → Nankai Namba").
    private func untimedTitle(_ item: DayItem) -> String {
        switch item {
        case .stop(let s):
            return s.title
        case .move(let m):
            let to = model.store.place(m.leg.to)?.name ?? m.leg.to
            if model.store.mode(of: m.leg) == .walk { return "Đi bộ → \(to)" }
            return "\(model.store.line(m.leg.line)?.name ?? m.leg.line) → \(to)"
        }
    }
}

/// The day's city in kanji, its title, and a strip of segments, one per stop, stamped red as
/// they are visited; the next one breathes. Tapping it opens the whole day.
private struct TodayDayHeader: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let chapter = model.store.chapter(of: day)
        let stops = day.stops.filter { model.store.place($0.stop.place)?.kind != .station }.map { $0.index }
        let next = model.next?.index
        NavigationLink(value: Route.day(day.key)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    Text(chapter?.kanji ?? day.dowKanji)
                        .font(.mincho(38))
                        .foregroundStyle(chapter?.tint ?? Palette.sun)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ngày \(day.n) · \(chapter?.name ?? "")")
                            .font(.caption.weight(.bold))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.sun)
                        Text(day.title)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(spacing: 4) {
                    ForEach(stops, id: \.self) { i in
                        let done = model.isDone(day, i)
                        Capsule()
                            .fill(done ? AnyShapeStyle(Palette.sun) : AnyShapeStyle(.fill.tertiary))
                            .overlay {
                                // a still outline: an endless pulse would redraw the page every frame
                                if i == next, !done {
                                    Capsule().stroke(Palette.sun, lineWidth: 1.5)
                                }
                            }
                            .frame(height: 5)
                    }
                }
                .animation(.smooth, value: model.doneCount(day))
                .accessibilityElement()
                .accessibilityLabel("Đã ghé \(model.doneCount(day)) trên \(stops.count) điểm")
            }
            .foregroundStyle(.primary)
            .contentShape(.rect)
        }
        .buttonStyle(.pressable)
        .padding(.top, 4)
    }
}

/// "Trễ 12 phút cho Ginza Line 16:15" and, when it helps, what to drop.
private struct TodayLateBanner: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let plan: Replan
    /// counts the drops made here; the late time keeps changing under the button, so it cannot be the trigger
    @Binding var dropped: Int

    private var target: String {
        switch day.items[plan.target] {
        case .move(let m): "\(model.store.line(m.leg.line)?.name ?? m.leg.line) \(m.at ?? "")"
        case .stop(let s): "\(s.title) \(s.at ?? "")"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Trễ \(plan.lateBy) phút cho \(target)", systemImage: "clock.badge.exclamationmark")
                .font(.headline)
                .foregroundStyle(Palette.sun)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: plan.lateBy)
            if let advice = model.advice(plan, day: day) {
                Text(advice).font(.subheadline)
            }
            if plan.works {
                Button {
                    // felt only once it is saved; the alert in front says when it is not
                    if withAnimation(.snappy, { model.apply(plan) }) { dropped += 1 }
                } label: {
                    Text("Bỏ \(model.dropNames(plan, day))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.sun)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Palette.sakura, in: .rect(cornerRadius: Metrics.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// The next place or departure, with its photo, when to leave and the way there.
private struct TodayNextCard: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let next: Waypoint
    @Binding var arrived: Bool
    @State private var opened = 0

    private var place: Place? { model.store.place(next.placeID) }

    /// A departure shows the place it leads to; a station rarely has a photo worth showing.
    private var photoPlace: Place? {
        if next.kind != .departure { return place }
        for item in day.items.dropFirst(next.index + 1) {
            if let p = model.store.place(item.stop?.place), p.kind != .station, p.hero != nil { return p }
        }
        return place
    }

    private var move: Move? { day.items[next.index].move }

    private var ride: Ride? {
        move.flatMap { model.store.ride(startingWith: $0.leg.id, on: day) }
    }

    private var label: String {
        switch next.kind {
        case .stop: "Tiếp theo"
        case .departure: "Chuyến tiếp theo"
        case .reservation: "Đã đặt chỗ"
        }
    }

    private var title: String {
        switch next.kind {
        case .departure:
            let to = move.flatMap { model.store.place($0.leg.to)?.name } ?? ""
            return "\(next.title) → \(to)"
        default:
            return place?.name ?? next.title
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                PlacePhoto(photo: photoPlace?.hero)
                    .overlay {
                        if photoPlace?.hero == nil, let kind = place?.kind {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                        }
                    }
                LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.4), .init(color: .black.opacity(0.72), location: 1)], startPoint: .top, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(.caption.weight(.bold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .opacity(0.85)
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    if next.kind != .departure, place?.name != next.title {
                        Text(next.title).font(.subheadline).opacity(0.85).lineLimit(2)
                    }
                }
                .foregroundStyle(.white)
                .padding(16)
            }
            .frame(height: 300)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if let kind = place?.kind {
                    Image(systemName: next.kind == .departure ? "tram.fill" : kind.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background((next.kind == .departure ? Palette.ai : kind.tint).gradient, in: .circle)
                        .padding(12)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                // when to leave, large and red: the one thing to read at a glance
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Countdown(target: model.date(day, minutes: next.setOff), now: model.now)
                        .font(.figure(30))
                        .foregroundStyle(Palette.sun)
                        .contentTransition(.numericText())
                        .animation(.smooth, value: model.now)
                    Text("rời đi lúc \(TripTime.clock(next.setOff))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()

                if let way = wayThere {
                    Label(way, systemImage: "figure.walk")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                TodayNextActions(day: day, next: next, place: place, ride: ride, arrived: $arrived)
            }
            .padding(16)
        }
        .background(Palette.card)
        .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
        .contentShape(.rect)
        .sheetSource("today.next")
        .onTapGesture {
            if let ride {
                opened += 1
                model.present(.ride(ride.id), from: "today.next")
            } else if let id = next.placeID {
                opened += 1
                model.present(.place(id), from: "today.next")
            }
        }
        .sensoryFeedback(.press, trigger: opened)
        .accessibilityElement(children: .contain)
    }

    /// "850 m · đi bộ 12 phút" from where you are.
    private var wayThere: String? {
        guard let here = model.position, let p = place else { return nil }
        let km = Geo.km(here, p.coordinate)
        let minutes = PlanEngine.directWalk(here, p.coordinate, pace: model.pace.factor)
        return "\(Fmt.km(km)) · đi bộ \(Fmt.duration(minutes))"
    }
}

private struct TodayNextActions: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let next: Waypoint
    let place: Place?
    let ride: Ride?
    @Binding var arrived: Bool

    @State private var followed = 0
    /// Maps, the ride being followed or the order sheet opened
    @State private var opened = 0
    @Namespace private var glass

    var body: some View {
        // one container: following a ride turns its button into the tracking one in place,
        // and the row reflows as one piece of glass when the next stop changes
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let id = next.placeID {
                    Button {
                        opened += 1
                        model.walk(to: id)
                    } label: {
                        Label("Đi bộ", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .glassEffectID("walk", in: glass)
                }

                if let ride {
                    if model.live.ride?.id == ride.id {
                        Button {
                            opened += 1
                            model.present(.ride(ride.id), from: "today.ride")
                        } label: {
                            Label("Đang theo dõi", systemImage: "dot.radiowaves.left.and.right")
                                .symbolEffect(.variableColor.iterative)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("ride", in: glass)
                        .sheetSource("today.ride")
                    } else {
                        Button {
                            followed += 1
                            withAnimation(.bouncy) { model.live.start(ride, model: model) }
                        } label: {
                            Label("Theo dõi chuyến", systemImage: "train.side.front.car")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .glassEffectID("ride", in: glass)
                    }
                } else if place?.kind == .food, let id = place?.id {
                    Button {
                        opened += 1
                        model.present(.atPlace(id), from: "today.order")
                    } label: {
                        Label("Gọi món", systemImage: "menucard.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .glassEffectID("order", in: glass)
                    .sheetSource("today.order")
                }

                if next.kind != .departure {
                    Button {
                        // felt only once it is saved; the alert in front says when it is not
                        if withAnimation(.snappy, { model.toggleDone(day, next.index) }) { arrived.toggle() }
                    } label: {
                        Label("Đã tới", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .glassEffectID("arrived", in: glass)
                    .accessibilityLabel("Đã tới")
                }
            }
        }
        .controlSize(.large)
        // on the row, not the button: following swaps the button for the tracking one
        .sensoryFeedback(.start, trigger: followed)
        .sensoryFeedback(.press, trigger: opened)
    }
}

/// The rest of today, from the first item still ahead; what is behind folds away.
private struct TodayTimeline: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @State private var showPast = false
    @State private var opened = 0

    var body: some View {
        let cursor = min(model.cursor, day.items.count)
        let past = Array(0 ..< cursor)
        let ahead = Array(cursor ..< day.items.count)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Còn lại hôm nay")
            VStack(alignment: .leading, spacing: 0) {
                if !past.isEmpty {
                    DisclosureGroup(isExpanded: $showPast) {
                        rows(past)
                    } label: {
                        Text("Đã qua · \(past.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 8)
                    // unfolding answers; folding away stays quiet
                    .sensoryFeedback(.press, trigger: showPast) { _, shown in shown }
                }
                rows(ahead)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Palette.card, in: .rect(cornerRadius: Metrics.card, style: .continuous))
            NavigationLink(value: Route.day(day.key)) {
                Label("Cả ngày \(day.n)", systemImage: "list.bullet.below.rectangle")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.pressable(.borderless))
            .padding(.leading, 4)
        }
        .sensoryFeedback(.press, trigger: opened)
    }

    @ViewBuilder
    private func rows(_ indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(indices, id: \.self) { i in
                ItemRow(day: day, index: i)
                    .sheetSource(source(i))
                    .onTapGesture { open(i) }
                    .accessibilityAction(named: "Chi tiết") { open(i) }
            }
        }
    }

    private func source(_ i: Int) -> String { "today.\(day.key).\(i)" }

    private func open(_ i: Int) {
        switch day.items[i] {
        case .stop(let s):
            if let id = s.place {
                opened += 1
                model.present(.place(id), from: source(i))
            }
        case .move(let m):
            if let ride = model.store.ride(containing: m.leg.id, on: day) {
                opened += 1
                model.present(.ride(ride.id), from: source(i))
            }
        }
    }
}

// MARK: - After the trip

private struct TodayAfter: View {
    @Environment(AppModel.self) private var model
    @Query private var expenses: [Expense]

    var body: some View {
        let visited = model.days.reduce(0) { $0 + model.doneCount($1) }
        let spent = Yen.total(expenses.filter(\.isCountable).map(\.yen))
        VStack(alignment: .leading, spacing: Metrics.stack) {
            Card {
                HStack(spacing: 24) {
                    Stat(value: "\(model.days.count)", label: "ngày")
                    Stat(value: "\(visited)", label: "điểm đã ghé")
                    Stat(value: Fmt.yen(spent), label: "đã chi")
                }
            }
            SectionTitle("Nhật ký")
            Card {
                ForEach(Array(model.days.enumerated()), id: \.element.key) { i, day in
                    if i > 0 { Divider() }
                    NavigationLink(value: Route.journal(day.key)) {
                        HStack {
                            Text("\(day.n)")
                                .font(.headline)
                                .monospacedDigit()
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(day.title).font(.body.weight(.semibold))
                                Text("\(day.dow), \(Fmt.shortDate(day.date))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.pressable(.plain))
                }
            }
        }
        .padding(.top, 8)
    }
}

/// The location journal is off until asked for: asked once, on the first trip day the app is opened,
/// and answered for good either way (Settings › Nhật ký changes it later, the journal page asks too).
/// An answer given while rehearsing holds only for that rehearsal (`AppModel.journalAskedRehearsalKey`).
private struct TodayJournalQuestion: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AppModel.journalAskedKey) private var askedForTrip = false
    @AppStorage(AppModel.journalAskedRehearsalKey) private var askedInRehearsal = false

    private var asked: Bool {
        get { model.rehearsing ? askedInRehearsal : askedForTrip }
        nonmutating set {
            if model.rehearsing { askedInRehearsal = newValue } else { askedForTrip = newValue }
        }
    }

    var body: some View {
        if !asked, !model.journalEnabled {
            Card {
                HStack(alignment: .top, spacing: 12) {
                    GlyphTile(symbol: "book.pages.fill", tint: Palette.ai, size: 34)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ghi nhật ký vị trí?").font(.headline)
                        Text("App ghi chỗ đã ghé và đường đã đi để tối xem lại trên bản đồ. Chỉ trong chuyến, chỉ trên máy này. Tắt hay xoá trong Cài đặt.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Bật") {
                                // the card goes with the tap: felt at once, not at its next update
                                Haptic.press()
                                model.journalEnabled = true
                                asked = true
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Không") {
                                Haptic.press()
                                asked = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }
}

/// Marking stops by itself, the station alerts and the evening journal need location "Always";
/// without it the day only follows the plan's clock. Said on the day screen, where it matters,
/// with the one tap that fixes it: iOS's upgrade prompt the first time, Settings after that.
private struct TodayAlwaysCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @AppStorage("location.askedAlways") private var asked = false
    @State private var pressed = 0

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                GlyphTile(symbol: "location.fill", tint: .blue, size: 34)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bật vị trí “Luôn luôn”").font(.headline)
                    Text("Để app tự đánh dấu chỗ đã tới, báo món khi tới quán và báo ga, kể cả khi khoá máy. Lúc này app chỉ đoán bạn ở đâu theo giờ trong lịch.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(asked ? "Mở Cài đặt" : "Bật") {
                        pressed += 1
                        enable()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .sensoryFeedback(.press, trigger: pressed)
                }
            }
        }
    }

    private func enable() {
        switch model.location.authorization {
        case .notDetermined:
            model.location.requestWhenInUse()
        case .authorizedWhenInUse where !asked:
            // iOS shows this upgrade once; after that only Settings can change it
            asked = true
            model.location.requestAlways()
        default:
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        }
    }
}

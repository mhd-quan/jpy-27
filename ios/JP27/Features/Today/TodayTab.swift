import SwiftData
import SwiftUI
import TripKit

/// The tab opened most: what is next, whether you are late, and the rest of today.
struct TodayTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.todayPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.stack) {
                    switch model.phase {
                    case .before(let days, let first):
                        TodayBefore(days: days, first: first)
                    case .during(let day):
                        TodayDuring(day: day)
                    case .after:
                        TodayAfter()
                    }
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 32)
            }
            .screen()
            .navigationTitle(title)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        model.sheet = .listen
                    } label: {
                        Label("Nghe", systemImage: "ear")
                    }
                    Button {
                        model.sheet = .settings
                    } label: {
                        Label("Cài đặt", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: Route.self) { RouteHost(route: $0) }
        }
    }

    private var title: String {
        switch model.phase {
        case .during(let day): "\(day.dow), \(Fmt.shortDate(day.date))"
        default: model.store.trip.meta.title
        }
    }
}

// MARK: - Before the trip

private struct TodayBefore: View {
    @Environment(AppModel.self) private var model
    let days: Int
    let first: Day

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(days)")
                    .font(.system(size: 96, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("ngày nữa · \(Fmt.shortDate(first.date)) \(first.title)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .padding(.top, 8)

            TodayBookings()

            Card {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.guide.checks, id: \.self) { c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.when).font(.subheadline.weight(.semibold))
                                Text(c.text).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Trước khi đi", systemImage: "checklist").font(.headline)
                }
            }

            Button {
                model.sheet = .settings
            } label: {
                Card {
                    HStack {
                        Label("Chạy thử một ngày", systemImage: "clock.arrow.2.circlepath")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// The next booking windows: exact openings with a live countdown, then the ones set by a rule.
private struct TodayBookings: View {
    @Environment(AppModel.self) private var model

    private var upcoming: [Booking] {
        let timed = model.guide.bookings.filter { ($0.date ?? .distantPast) > model.now }.sorted { ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture) }
        let ruled = model.guide.bookings.filter { $0.at == nil }
        return Array((timed + ruled).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Đặt chỗ")
                NavigationLink(value: Route.bookings) {
                    Text("Tất cả").font(.subheadline)
                }
            }
            Card {
                ForEach(Array(upcoming.enumerated()), id: \.element) { i, b in
                    if i > 0 { Divider() }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.title).font(.headline)
                        if let date = b.date {
                            HStack(spacing: 6) {
                                Image(systemName: "alarm")
                                Text(when(date))
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.tint)
                            .monospacedDigit()
                        } else {
                            Text(b.rule).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// "20/9 · 10:00 giờ Nhật · còn 323 ngày", or a minute countdown on the day.
    private func when(_ date: Date) -> String {
        let jst = "\(Fmt.shortDate(TripTime.isoDate(of: date))) · \(TripTime.clock(date)) giờ Nhật"
        let seconds = date.timeIntervalSince(model.now)
        if seconds < 86400 {
            let m = max(0, Int((seconds / 60).rounded(.up)))
            return m < 90 ? "\(jst) · còn \(m) phút" : "\(jst) · còn \(m / 60) giờ"
        }
        return "\(jst) · còn \(Int(seconds / 86400)) ngày"
    }
}

// MARK: - During a trip day

private struct TodayDuring: View {
    @Environment(AppModel.self) private var model
    let day: Day

    private var fujiSpot: FujiGuide.Spot? {
        let spots = model.guide.fuji.spots.filter { $0.day == day.key }
        return spots.first { $0.role == "planned" && $0.visible } ?? spots.first { $0.visible } ?? spots.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.stack) {
            Text("Ngày \(day.n) · \(day.title)")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let plan = model.replan {
                TodayLateBanner(day: day, plan: plan)
            }

            if let next = model.next {
                TodayNextCard(day: day, next: next)
            } else {
                Card {
                    Label("Hết lịch hôm nay", systemImage: "moon.stars")
                        .font(.headline)
                }
            }

            if model.minutes(on: day) >= 19 * 60 {
                NavigationLink(value: Route.journal(day.key)) {
                    Card {
                        HStack {
                            Label("Nhật ký hôm nay", systemImage: "book.pages")
                                .font(.headline)
                            Spacer()
                            Text("\(model.doneCount(day)) điểm")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            if let spot = fujiSpot {
                Card {
                    CloudForecast(title: "Fuji hôm nay", key: spot.id, coordinate: Coordinate(spot.lat, spot.lng))
                }
            }

            TodayTimeline(day: day)
        }
    }
}

/// "Trễ 12 phút cho Ginza Line 16:15" and, when it helps, what to drop.
private struct TodayLateBanner: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let plan: Replan

    private var target: String {
        switch day.items[plan.target] {
        case .move(let m): "\(model.store.line(m.leg.line)?.name ?? m.leg.line) \(m.at ?? "")"
        case .stop(let s): "\(s.title) \(s.at ?? "")"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Trễ \(plan.lateBy) phút cho \(target)", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)
                .monospacedDigit()
            if let advice = model.advice(plan, day: day) {
                Text(advice).font(.subheadline)
            }
            if plan.works {
                Button {
                    withAnimation(.snappy) { model.apply(plan) }
                } label: {
                    Text("Bỏ \(model.dropNames(plan, day))")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .sensoryFeedback(.impact(weight: .medium), trigger: plan)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.red.opacity(0.12), in: .rect(cornerRadius: Metrics.card, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// The next place or departure, with its photo, when to leave and the way there.
private struct TodayNextCard: View {
    @Environment(AppModel.self) private var model
    let day: Day
    let next: Waypoint

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
            PlacePhoto(photo: photoPlace?.hero)
                .frame(height: 260)
                .overlay {
                    if photoPlace?.hero == nil, let kind = place?.kind {
                        Image(systemName: kind.symbol)
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
                }
                .overlay(alignment: .topLeading) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: .capsule)
                        .padding(12)
                }

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .lineLimit(2)
                    if next.kind != .departure, place?.name != next.title {
                        Text(next.title).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text("Rời đi lúc \(TripTime.clock(next.setOff))")
                    Text("·")
                    Countdown(target: model.date(day, minutes: next.setOff), now: model.now)
                }
                .font(.subheadline.weight(.medium))
                .monospacedDigit()

                if let way = wayThere {
                    Label(way, systemImage: "figure.walk")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                TodayNextActions(day: day, next: next, place: place, ride: ride)
            }
            .padding(16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
        .contentShape(.rect)
        .onTapGesture {
            if let ride { model.sheet = .ride(ride.id) } else if let id = next.placeID { model.sheet = .place(id) }
        }
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

    @State private var arrived = false

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let id = next.placeID {
                    Button {
                        model.walk(to: id)
                    } label: {
                        Label("Đi bộ", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.glassProminent)
                }

                if let ride {
                    if model.live.ride?.id == ride.id {
                        Button {
                            model.sheet = .ride(ride.id)
                        } label: {
                            Label("Đang theo dõi", systemImage: "dot.radiowaves.left.and.right")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.glass)
                    } else {
                        Button {
                            model.live.start(ride, model: model)
                        } label: {
                            Label("Theo dõi chuyến", systemImage: "tram.fill")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .buttonStyle(.glass)
                    }
                } else if place?.kind == .food, let id = place?.id {
                    Button {
                        model.sheet = .atPlace(id)
                    } label: {
                        Label("Gọi món", systemImage: "fork.knife")
                            .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.glass)
                }

                if next.kind != .departure {
                    Button {
                        arrived.toggle()
                        withAnimation(.snappy) { model.toggleDone(day, next.index) }
                    } label: {
                        Label("Đã tới", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 32, minHeight: 32)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Đã tới")
                    .sensoryFeedback(.success, trigger: arrived)
                }
            }
        }
        .controlSize(.large)
    }
}

/// The rest of today, from the first item still ahead; what is behind folds away.
private struct TodayTimeline: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @State private var showPast = false

    var body: some View {
        let cursor = min(model.cursor, day.items.count)
        let past = Array(0 ..< cursor)
        let ahead = Array(cursor ..< day.items.count)
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Còn lại hôm nay")
            Card {
                if !past.isEmpty {
                    DisclosureGroup(isExpanded: $showPast) {
                        rows(past)
                            .padding(.top, 8)
                    } label: {
                        Text("Đã qua · \(past.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if !ahead.isEmpty { Divider() }
                }
                rows(ahead)
            }
            NavigationLink(value: Route.day(day.key)) {
                Label("Cả ngày \(day.n)", systemImage: "calendar")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func rows(_ indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(indices, id: \.self) { i in
                ItemRow(day: day, index: i)
                    .onTapGesture { open(i) }
                    .accessibilityAction(named: "Chi tiết") { open(i) }
            }
        }
    }

    private func open(_ i: Int) {
        switch day.items[i] {
        case .stop(let s):
            if let id = s.place { model.sheet = .place(id) }
        case .move(let m):
            if let ride = model.store.ride(containing: m.leg.id, on: day) { model.sheet = .ride(ride.id) }
        }
    }
}

// MARK: - After the trip

private struct TodayAfter: View {
    @Environment(AppModel.self) private var model
    @Query private var expenses: [Expense]

    var body: some View {
        let visited = model.days.reduce(0) { $0 + model.doneCount($1) }
        let spent = expenses.reduce(0) { $0 + $1.yen }
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
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 8)
    }
}

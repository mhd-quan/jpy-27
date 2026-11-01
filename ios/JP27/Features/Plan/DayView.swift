import SwiftUI
import TripKit

/// One day: its map, the timeline to tick off, side trips, what to cut when tired, shopping and rides.
struct DayView: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        if let day = model.store.day(key) {
            PlanDayContent(day: day)
        } else {
            ContentUnavailableView("Không có ngày này", systemImage: "calendar.badge.exclamationmark")
        }
    }
}

private struct PlanDayContent: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.stack) {
                PlanDayHeader(day: day)
                PlanDayTimeline(day: day)
                if !day.along.isEmpty { PlanDayAlong(day: day) }
                if !day.trims.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle("Nếu mệt hoặc trễ")
                        Card { PlanBullets(lines: day.trims) }
                    }
                }
                if let alt = day.alt { PlanDayAlternative(alt: alt) }
                if !day.slots.isEmpty { PlanDayShopping(day: day) }
                PlanDayRides(day: day)
                PlanDayFuji(day: day)
                if planHasStarted(day, now: model.now) {
                    NavigationLink(value: Route.journal(day.key)) {
                        Label("Nhật ký ngày \(day.n)", systemImage: "book.closed")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, 32)
        }
        .screen()
        .navigationTitle(day.isAlternative ? "Kawaguchiko" : "Ngày \(day.n)")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.mapFocus = nil
                    model.mapDay = key
                    model.tab = .map
                } label: {
                    Label("Bản đồ", systemImage: "map")
                }
            }
        }
    }
}

// MARK: - Header

private struct PlanDayHeader: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(planDateLabel(day)).font(.subheadline).foregroundStyle(.secondary)
                Text(day.title).font(.title2.weight(.bold))
            }
            .accessibilityElement(children: .combine)
            TripMap(content: .day(day, model: model), showsUser: false, interactive: false,
                    insets: UIEdgeInsets(top: 28, left: 28, bottom: 28, right: 28), frameID: day.key)
                .frame(height: 240)
                .clipShape(.rect(cornerRadius: Metrics.card, style: .continuous))
                // the map is still; a tap opens the live map tab
                .overlay {
                    Button {
                        model.mapFocus = nil
                        model.mapDay = key
                        model.tab = .map
                    } label: {
                        Color.clear.contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mở bản đồ ngày \(day.n)")
                }
            if let lead = day.lead {
                Text(lead).font(.body)
            }
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 14) {
                if let walk = day.walk { Stat(value: walk, label: "đi bộ") }
                if let rail = day.km?.rail, rail >= 1 { Stat(value: Fmt.km(rail), label: "tàu") }
                if day.meals.total > 0 { Stat(value: Fmt.yen(day.meals.total), label: "ăn, 2 người") }
                if let stay = model.store.chapter(of: day)?.short ?? model.store.place(day.stay)?.name {
                    Stat(value: stay, label: "ngủ")
                }
            }
            .lineLimit(2)
        }
        .padding(.top, 8)
    }
}

// MARK: - Timeline

private struct PlanDayTimeline: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        Card(padding: 14) {
            ForEach(day.items.indices, id: \.self) { i in
                if i > 0 { Divider().padding(.leading, 54) }
                row(i)
            }
        }
    }

    @ViewBuilder
    private func row(_ i: Int) -> some View {
        switch day.items[i] {
        case .stop(let s):
            ItemRow(day: day, index: i)
                .contentShape(.rect)
                .onTapGesture {
                    if let id = s.place { model.sheet = .place(id) }
                }
                .accessibilityAction(named: "Chi tiết") {
                    if let id = s.place { model.sheet = .place(id) }
                }
                .contextMenu {
                    if model.store.place(s.place)?.kind != .station {
                        Button {
                            model.toggleDone(day, i)
                        } label: {
                            Label(model.isDone(day, i) ? "Bỏ đánh dấu" : "Đã tới", systemImage: "checkmark.circle")
                        }
                        Button {
                            model.toggleSkip(day, i)
                        } label: {
                            Label(model.isSkipped(day, i) ? "Giữ lại" : "Bỏ điểm này", systemImage: model.isSkipped(day, i) ? "arrow.uturn.backward" : "minus.circle")
                        }
                    }
                    if let id = s.place {
                        Button {
                            model.walk(to: id)
                        } label: {
                            Label("Đi bộ tới đây", systemImage: "figure.walk")
                        }
                    }
                }
        case .move(let m):
            if let ride = model.store.ride(containing: m.leg.id, on: day) {
                NavigationLink(value: Route.ride(ride.id)) {
                    ItemRow(day: day, index: i)
                }
                .buttonStyle(.plain)
            } else {
                ItemRow(day: day, index: i)
            }
        }
    }
}

// MARK: - Along the way

private struct PlanDayAlong: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Trên đường đi", trailing: "\(day.along.count)")
            Card {
                PlanRows(items: day.along.compactMap { a in model.store.place(a.place).map { (a, $0) } }) { pair in
                    NavigationLink(value: Route.place(pair.1.id)) {
                        PlaceRow(place: pair.1, detail: detail(pair.1), trailing: reach(pair.0))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detail(_ p: Place) -> String? {
        if let get = p.snack?.get.first { return "\(get.ja) · \(get.vi)" }
        return p.note.map { String($0.prefix(80)) } ?? p.ja
    }

    /// "rẽ 6 phút", "xe 12 phút", or the straight distance.
    private func reach(_ a: Along) -> String? {
        if let d = a.detour, d.min > 0 {
            return d.mode == "car" ? "xe \(d.min) phút" : "rẽ \(d.min) phút"
        }
        if let d = a.detour, d.min == 0 { return "trên đường" }
        return a.km.map { Fmt.km($0) }
    }
}

private struct PlanDayAlternative: View {
    @Environment(AppModel.self) private var model
    let alt: AltPlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Phương án khác")
            Card {
                Text(alt.title).font(.headline)
                Text(alt.text).font(.subheadline).foregroundStyle(.secondary)
                ForEach(alt.places.compactMap { model.store.place($0) }) { p in
                    Divider()
                    NavigationLink(value: Route.place(p.id)) {
                        PlaceRow(place: p)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PlanDayShopping: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let slots = model.guide.shopping.slots.filter { day.slots.contains($0.id) }
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Mua sắm hôm nay")
            Card {
                PlanRows(items: slots) { slot in
                    NavigationLink(value: Route.slot(slot.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: "bag.fill").foregroundStyle(.secondary).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text([slotTime(slot), slot.area].compactMap { $0 }.joined(separator: " · "))
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                                if let focus = slot.focus {
                                    Text(focus).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func slotTime(_ s: Shopping.Slot) -> String? {
        switch (s.start, s.end) {
        case let (a?, b?): "\(a)–\(b)"
        case let (a?, nil): a
        default: nil
        }
    }
}

private struct PlanDayRides: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let rides = model.store.rides(on: day)
        if !rides.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Tàu xe")
                Card {
                    PlanRows(items: rides) { ride in
                        NavigationLink(value: Route.ride(ride.id)) {
                            PlanRideRow(ride: ride)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// Fuji spots tied to this day, and the cloud forecast over the first of them.
private struct PlanDayFuji: View {
    @Environment(AppModel.self) private var model
    let day: Day

    var body: some View {
        let spots = model.guide.fuji.spots.filter { planFujiDayKey($0) == day.key && ($0.role == "planned" || $0.role == "alt") }
        if let first = spots.first {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Fuji")
                CloudForecast(title: "Mây quanh Fuji", key: first.id, coordinate: Coordinate(first.lat, first.lng))
                NavigationLink(value: Route.fuji) {
                    Label("\(spots.count) chỗ ngắm hôm nay", systemImage: "mountain.2.fill")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

/// The day key a Fuji spot belongs to; research files Kawaguchiko spots under day 3.
func planFujiDayKey(_ spot: FujiGuide.Spot) -> String? {
    guard let d = spot.day else { return nil }
    return d == "3" ? "kawaguchiko" : d
}

/// A ride in a list: its line, from → to at a time, the side to sit.
struct PlanRideRow: View {
    @Environment(AppModel.self) private var model
    let ride: Ride

    var body: some View {
        HStack(spacing: 12) {
            LineBadge(name: ride.title, color: Color(hex: ride.color), mode: planRideMode(ride, store: model.store), compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ride.fromName) → \(ride.toName)" + (ride.at.map { " · \($0)" } ?? ""))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(2)
                Text([ride.title, ride.seatVerdict].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// The mode of a ride's first leg.
func planRideMode(_ ride: Ride, store: TripStore) -> Mode {
    guard let day = store.day(ride.day),
          let leg = day.items.compactMap(\.move).first(where: { $0.leg.id == ride.legs.first })?.leg
    else { return .train }
    return store.mode(of: leg)
}

import SwiftUI
import TripKit

/// Lịch trình: the twelve days by the hotel they sleep in, the Kawaguchiko option under day 3,
/// and the guides one level deeper.
struct PlanTab: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.planPath) {
            List {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    ForEach(model.store.trip.chapters) { chapter in
                        PlanChapterSection(chapter: chapter)
                    }
                    PlanGuidesSection()
                } else {
                    PlanSearchResults(query: query)
                }
            }
            .listStyle(.insetGrouped)
            .paperList()
            .navigationTitle("Lịch trình")
            .searchable(text: $query, prompt: "Quán, điểm tham quan, món")
            .navigationDestination(for: Route.self) { RouteHost(route: $0) }
        }
    }
}

// MARK: - Chapters

private struct PlanChapterSection: View {
    @Environment(AppModel.self) private var model
    let chapter: Chapter

    var body: some View {
        Section {
            ForEach(model.store.trip.days.filter { chapter.days.contains($0.n) }) { day in
                NavigationLink(value: Route.day(day.key)) {
                    PlanDayRow(day: day, replaced: replacement(of: day) != nil)
                }
                ForEach(model.store.alternatives(for: day)) { alt in
                    PlanAlternativeRow(alt: alt)
                }
            }
        } header: {
            // the city in kanji in its line colour, as on a station sign
            HStack(alignment: .center, spacing: 12) {
                Text(chapter.kanji)
                    .font(.mincho(30))
                    .foregroundStyle(chapter.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(chapter.name).font(.title3.weight(.bold)).foregroundStyle(.primary)
                    Text("\(chapter.nights) đêm · \(chapter.short)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Capsule()
                    .fill(chapter.tint)
                    .frame(width: 28, height: 5)
            }
            .padding(.top, 8)
            .textCase(nil)
            .padding(.leading, -8)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func replacement(of day: Day) -> Day? {
        model.store.alternatives(for: day).first { model.alternatives.contains($0.key) }
    }
}

/// The day's photograph and number, date, title, route; a ring of stops visited once the day has begun.
private struct PlanDayRow: View {
    @Environment(AppModel.self) private var model
    let day: Day
    var replaced = false

    private var lived: Day {
        model.days.first { $0.n == day.n } ?? day
    }

    private var isToday: Bool {
        model.today?.n == day.n && model.today?.date == day.date
    }

    var body: some View {
        let tint = model.store.chapter(of: day)?.tint ?? Palette.sun
        HStack(spacing: 14) {
            // the day's photograph with its number on the chapter's colour; today ringed in red
            PlacePhoto(photo: HomePicks.photo(for: day, store: model.store), maxPixel: 200)
                .frame(width: 58, height: 58)
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .strokeBorder(Palette.sun, lineWidth: 2.5)
                            .padding(-4)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text("\(day.n)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(isToday ? Palette.sun : tint, in: .circle)
                        .overlay(Circle().strokeBorder(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        .offset(x: -7, y: 7)
                }
                .padding(.vertical, 4)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(day.dowKanji) · \(planDateLabel(day))").font(.caption).foregroundStyle(isToday ? Palette.sun : .secondary)
                Text(day.title)
                    .font(.body.weight(.semibold))
                    .strikethrough(replaced)
                    .foregroundStyle(replaced ? Color.secondary : Color.primary)
                Text(day.route).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if planHasStarted(day, now: model.now), !replaced {
                PlanProgressRing(done: model.doneCount(lived), total: stopCount(lived))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isToday ? String(localized: "Hôm nay") : String())
    }

    private func stopCount(_ d: Day) -> Int {
        d.stops.filter { model.store.place($0.stop.place)?.kind != .station }.count
    }
}

/// An alternative day under the one it can replace: a switch to choose it, and its page. Two list
/// rows, so the switch and the link never share a tap.
private struct PlanAlternativeRow: View {
    @Environment(AppModel.self) private var model
    let alt: Day

    var body: some View {
        Toggle(isOn: Binding(
            get: { model.alternatives.contains(alt.key) },
            set: { on in
                if on { model.alternatives.insert(alt.key) } else { model.alternatives.remove(alt.key) }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Phương án thay ngày \(alt.replaces ?? alt.n)").font(.caption).foregroundStyle(.secondary)
                Text(alt.title).font(.body.weight(.semibold))
            }
        }
        .padding(.leading, 48)
        NavigationLink(value: Route.day(alt.key)) {
            Text(alt.route)
                .font(.subheadline)
                .foregroundStyle(model.alternatives.contains(alt.key) ? Color.accentColor : Color.secondary)
                .padding(.leading, 48)
        }
    }
}

/// Stops visited out of the day's stops.
struct PlanProgressRing: View {
    let done: Int
    let total: Int

    var body: some View {
        let share = total > 0 ? Double(done) / Double(total) : 0
        ZStack {
            Circle().stroke(.fill.tertiary, lineWidth: 4)
            Circle()
                .trim(from: 0, to: share)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if share >= 1 {
                Image(systemName: "checkmark").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityLabel("Đã ghé \(done) trên \(total) điểm")
    }
}

// MARK: - Guides

private struct PlanGuidesSection: View {
    private struct Guide: Identifiable {
        var id: String { title }
        let title: String
        let detail: String
        let symbol: String
        let tint: Color
        let route: Route
    }

    private var links: [Guide] {
        [
            Guide(title: "Ăn uống", detail: "Quán, món nên gọi", symbol: "fork.knife", tint: Place.Kind.food.tint, route: .food),
            Guide(title: "Chỗ ở", detail: "Năm khách sạn, quanh đó", symbol: "bed.double.fill", tint: Place.Kind.stay.tint, route: .stays),
            Guide(title: "Trên tàu", detail: "Ngồi bên nào, ga nào xuống", symbol: "train.side.front.car", tint: Palette.ai, route: .trains),
            Guide(title: "Fuji", detail: "Ngắm ở đâu, lúc nào", symbol: "mountain.2.fill", tint: Palette.fuji, route: .fuji),
            Guide(title: "Đặt chỗ", detail: "Khi nào mở bán", symbol: "ticket.fill", tint: Palette.sun, route: .bookings),
            Guide(title: "Mua sắm", detail: "Theo ngày, theo cửa hàng", symbol: "bag.fill", tint: Place.Kind.shop.tint, route: .shopping),
            Guide(title: "Ngân sách", detail: "Dự tính và tỉ giá", symbol: "chart.pie.fill", tint: Palette.matcha, route: .budget),
        ]
    }

    var body: some View {
        Section("Cẩm nang") {
            ForEach(links) { link in
                NavigationLink(value: link.route) {
                    HStack(spacing: 14) {
                        GlyphTile(symbol: link.symbol, tint: link.tint)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(link.title).font(.body.weight(.semibold))
                            Text(link.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - Search

private struct PlanSearchResults: View {
    @Environment(AppModel.self) private var model
    let query: String

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let days = (model.store.trip.days + model.store.trip.altDays).filter {
            $0.title.localizedStandardContains(q) || $0.route.localizedStandardContains(q)
        }
        let places = model.store.trip.places.filter { p in
            p.name.localizedStandardContains(q) || (p.ja?.contains(q) ?? false) || (p.dish?.localizedStandardContains(q) ?? false)
                || (p.menu?.items.contains { $0.ja.contains(q) || $0.vi.localizedStandardContains(q) } ?? false)
        }
        .sorted { ($0.uses.isEmpty ? 1 : 0, $0.name) < ($1.uses.isEmpty ? 1 : 0, $1.name) }
        .prefix(40)

        if days.isEmpty && places.isEmpty {
            ContentUnavailableView.search(text: q)
        }
        if !days.isEmpty {
            Section("Ngày") {
                ForEach(days) { day in
                    NavigationLink(value: Route.day(day.key)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(planDateLabel(day)).font(.caption).foregroundStyle(.secondary)
                            Text(day.title).font(.body.weight(.semibold))
                        }
                    }
                }
            }
        }
        if !places.isEmpty {
            Section("Địa điểm") {
                ForEach(Array(places)) { p in
                    NavigationLink(value: Route.place(p.id)) {
                        PlaceRow(place: p, trailing: p.uses.first.map { planDayName($0.day, store: model.store) })
                    }
                }
            }
        }
    }
}

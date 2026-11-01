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
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color(hex: chapter.color))
                    .frame(width: 4, height: 28)
                VStack(alignment: .leading, spacing: 0) {
                    Text(chapter.name).font(.headline).foregroundStyle(.primary)
                    Text("\(chapter.nights) đêm · \(chapter.short)").font(.caption).foregroundStyle(.secondary)
                }
            }
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

/// Day number in a circle, date, title, route; a ring of stops visited once the day has begun.
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
        HStack(spacing: 12) {
            Text("\(day.n)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : .primary)
                .frame(width: 36, height: 36)
                .background(isToday ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.fill.tertiary), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(planDateLabel(day)).font(.caption).foregroundStyle(isToday ? Color.accentColor : .secondary)
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
        let symbol: String
        let route: Route
    }

    private let links: [Guide] = [
        Guide(title: "Ăn uống", symbol: "fork.knife", route: .food),
        Guide(title: "Chỗ ở", symbol: "bed.double.fill", route: .stays),
        Guide(title: "Trên tàu", symbol: "tram.fill", route: .trains),
        Guide(title: "Fuji", symbol: "mountain.2.fill", route: .fuji),
        Guide(title: "Đặt chỗ", symbol: "calendar.badge.clock", route: .bookings),
        Guide(title: "Mua sắm", symbol: "bag.fill", route: .shopping),
        Guide(title: "Ngân sách", symbol: "yensign.circle.fill", route: .budget),
    ]

    var body: some View {
        Section("Cẩm nang") {
            ForEach(links) { link in
                NavigationLink(value: link.route) {
                    Label(link.title, systemImage: link.symbol)
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

import SwiftUI
import TripKit

/// Ăn uống: the planned meals day by day, the snacks research tied to each day, and the fallbacks.
struct FoodGuideView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(model.store.trip.days + model.store.trip.altDays) { day in
                PlanFoodDaySection(day: day)
            }
            let alts = model.store.trip.places.filter { $0.kind == .food && $0.role == "alt" }
            if !alts.isEmpty {
                Section("Phương án thay thế") {
                    ForEach(alts) { p in
                        NavigationLink(value: Route.place(p.id)) {
                            PlaceRow(place: p, detail: planFoodDetail(p), trailing: p.price)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Ăn uống")
    }
}

private struct PlanFoodDaySection: View {
    @Environment(AppModel.self) private var model
    let day: Day
    @State private var showSnacks = false

    var body: some View {
        let meals = mealPlaces
        let mealIDs = Set(meals.map(\.place.id))
        let snacks = model.store.trip.places.filter { p in
            p.snack != nil && p.day == day.key && p.role != "alt" && !mealIDs.contains(p.id)
        }
        if !meals.isEmpty || !snacks.isEmpty {
            Section {
                ForEach(meals, id: \.place.id) { meal in
                    NavigationLink(value: Route.place(meal.place.id)) {
                        PlaceRow(place: meal.place, detail: planFoodDetail(meal.place), trailing: meal.at)
                    }
                }
                if !snacks.isEmpty {
                    DisclosureGroup(isExpanded: $showSnacks) {
                        ForEach(snacks) { p in
                            NavigationLink(value: Route.place(p.id)) {
                                PlaceRow(place: p, detail: planSnackDetail(p))
                            }
                        }
                    } label: {
                        Label("Ăn vặt dọc đường · \(snacks.count)", systemImage: "takeoutbag.and.cup.and.straw")
                    }
                }
            } header: {
                Text(day.isAlternative ? day.title : "Ngày \(day.n) · \(day.title)")
            }
        }
    }

    /// Food stops of the day, in plan order, once each.
    private var mealPlaces: [(place: Place, at: String?)] {
        var seen = Set<String>()
        return day.stops.compactMap { _, s in
            guard let p = model.store.place(s.place), p.kind == .food, seen.insert(p.id).inserted else { return nil }
            return (p, s.at)
        }
    }
}

/// "Tempura soba · ¥2.000–2.400 · Tiền mặt"
func planFoodDetail(_ p: Place) -> String? {
    var parts: [String] = []
    if let dish = p.dish { parts.append(dish) } else if let top = p.menu?.items.sorted(by: { $0.rank < $1.rank }).first { parts.append(top.shortVi) }
    if let price = p.price { parts.append(price) }
    if p.payment == .cash { parts.append("Tiền mặt") }
    return parts.isEmpty ? p.ja : parts.joined(separator: " · ")
}

/// "Taiyaki · ¥200 · 10:00–18:00"
func planSnackDetail(_ p: Place) -> String? {
    guard let snack = p.snack else { return p.ja }
    var parts: [String] = []
    if let g = snack.get.first { parts.append(g.vi.components(separatedBy: CharacterSet(charactersIn: ".;,(")).first ?? g.vi) }
    if let yen = snack.get.first?.yen { parts.append(Fmt.yen(yen)) }
    if let o = snack.open, let c = snack.close { parts.append("\(o)–\(c)") }
    return parts.joined(separator: " · ")
}
